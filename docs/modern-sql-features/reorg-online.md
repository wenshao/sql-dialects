# 在线表重组 (Online Table Reorganization)

"我们的核心订单表已经 8TB，连续运行了 5 年——历史 UPDATE 留下的死元组占了 30% 空间，主键聚簇顺序也乱了，全表扫描 IO 翻倍，但业务一刻都不能停。" 这是每一个长期运行的 OLTP 数据库都会遇到的问题。**在线表重组（Online Table Reorganization）** 就是为这种场景设计的核心运维原语：在不阻塞读写的前提下，把表的物理存储重新整理一遍——回收死元组留下的空洞、按聚簇键重新排序、改变压缩策略、迁移到新的表空间。

姊妹文章：[索引维护 (Index Maintenance)](./index-maintenance.md) 关注索引层面的 REBUILD/REORGANIZE；[VACUUM 与垃圾回收 (VACUUM and Garbage Collection)](./vacuum-gc.md) 关注 MVCC 死元组的标记和回收；[Online DDL 实现方案](./online-ddl-implementation.md) 关注表结构变更（ADD COLUMN 等）的在线实现。本文聚焦于**表级**的物理重组——不改变 schema，只是重新整理数据的物理布局。

## 为什么表会"老化"

任何持续运行的事务表在长期 INSERT、UPDATE、DELETE 之后，都会出现以下退化现象：

1. **堆碎片（Heap Fragmentation）**：UPDATE 在 MVCC 系统中通常生成新版本，原行被标记为死亡。VACUUM 后空间可重用，但物理位置已乱。物理顺序与逻辑顺序背离会让范围扫描的预读失效。
2. **聚簇度（Clustering Factor）下降**：Oracle 索引的聚簇度衡量索引顺序与堆顺序的相关性。新插入打破时间序列后，原本顺序的索引扫描需要在堆上跳来跳去，IO 成本飙升。
3. **填充率（Fill Factor）持续走低**：经过多轮 DELETE，单个数据页的有效行可能从 90% 降到 30%，缓冲池利用率骤降。
4. **表空间膨胀（Bloat）**：MVCC 系统的"墓碑"行不能立即释放磁盘——只有重组才能把空间真正还给文件系统。
5. **变长列退化**：VARCHAR 列被多次扩展更新后，行越界被切到 overflow page（InnoDB 叫 row migration），单行读放大为多页读。
6. **压缩比退化**：列存系统的 part 越合越多但每个 part 仍按"小批"压缩，丢失全局压缩潜力。

PostgreSQL 社区有一个广为流传的案例：一张表只有 200 万活动行，但因 autovacuum 长期被长事务阻塞，表膨胀到 90GB，简单的 `SELECT COUNT(*)` 要 2 分钟。Oracle 的高水位线（HWM）一旦升到峰值就不会自动下降，DELETE 后的全表扫描照旧扫到峰值水位。InnoDB 的"无主键变更但表大小增长 3 倍"是 OLTP 写密集场景下的常见运维事故。

这些退化的根本治理方式只有一个——**物理重组（reorg）**：要么把数据复制到一张新表然后切换指针（offline 风格），要么在原地分批移动（inplace 风格）。难点是：**如何让重组发生时业务还能正常读写**。

## 没有 SQL 标准

ISO/IEC 9075（SQL:2023）至今没有任何关于表重组的语句——和 VACUUM、索引维护一样，这些都是物理存储层的实现细节。SQL 标准只关心逻辑语义，不规定如何回收死元组或重新排列页面。结果是每个引擎按自己的存储引擎特性发明了一套语法和工具：

- **Oracle**：`ALTER TABLE ... MOVE [ONLINE]`、`DBMS_REDEFINITION`、`ALTER TABLE ... SHRINK SPACE`
- **SQL Server**：`ALTER TABLE ... REBUILD WITH (ONLINE = ON)`、`ALTER INDEX ALL ... REBUILD`
- **PostgreSQL**：`CLUSTER`（offline）、`VACUUM FULL`（offline）、`pg_repack` / `pg_squeeze` 扩展（online）
- **MySQL/MariaDB**：`ALTER TABLE ... ENGINE=InnoDB`、`OPTIMIZE TABLE`、`pt-online-schema-change` / `gh-ost` / `lhm`
- **DB2**：`REORG TABLE`、`ADMIN_MOVE_TABLE`（online，9.7+）
- **CockroachDB / TiDB / 云数仓**：基于 LSM/不可变 part 的存储，不需要显式重组

唯一勉强算"准标准"的是 `OPTIMIZE TABLE`——MySQL 引入后被多个 fork 继承（MariaDB、TiDB、OceanBase），并被 OLAP 引擎（ClickHouse、StarRocks、Doris、SingleStore）借用作为合并/紧凑的入口。但是它们的语义截然不同：在 InnoDB 上是 `ALTER TABLE ENGINE=InnoDB` 的别名，在 ClickHouse 上是触发 part 合并的命令。

## 支持矩阵

### 1. 在线表重建（Online Table Rebuild）

| 引擎 | 命令 | 默认 ONLINE | 阻塞 DML | 引入版本 |
|------|------|------------|---------|---------|
| Oracle | `ALTER TABLE ... MOVE ONLINE` | 否（需显式 ONLINE） | 否（带 ONLINE） | 12cR2 (2017-03) |
| Oracle | `DBMS_REDEFINITION.START_REDEF_TABLE` | 是 | 否 | 9i (2001) |
| SQL Server | `ALTER TABLE ... REBUILD WITH (ONLINE=ON)` | 否（需显式 ONLINE） | 否（带 ONLINE） | 2005 企业版 |
| SQL Server | `ALTER INDEX ALL ... REBUILD WITH (ONLINE=ON)` | 否 | 否 | 2005 企业版 |
| PostgreSQL | `CLUSTER`（offline） | -- | 是（AccessExclusiveLock） | 早期（≤7.0） |
| PostgreSQL | `VACUUM FULL`（offline） | -- | 是（AccessExclusiveLock） | 早期（≤7.0） |
| PostgreSQL + pg_repack | `pg_repack -t table` | 是 | 否 | 1.x (2010+) |
| PostgreSQL + pg_squeeze | `pg_squeeze.squeeze_table()` | 是 | 否 | 1.x (2016+) |
| MySQL InnoDB | `ALTER TABLE ... ENGINE=InnoDB` | INPLACE 是 | 否（5.6+） | 5.6 (2013) |
| MySQL InnoDB | `OPTIMIZE TABLE` | 同上（recreate + analyze） | 否（5.6+） | 5.6 (2013) |
| MySQL + pt-osc | `pt-online-schema-change` | 是 | 否 | 早期 (Percona) |
| MySQL + gh-ost | `gh-ost --alter ...` | 是 | 否 | 2016 (GitHub) |
| MariaDB | `ALTER TABLE ... ENGINE=InnoDB` | INPLACE 是 | 否 | 10.0+ |
| MariaDB | `OPTIMIZE TABLE` | 同上 | 否 | 10.0+ |
| SQLite | `VACUUM` | -- | 是（写锁） | 早期 |
| DB2 | `REORG TABLE` | 否（默认 offline） | 是（默认） | 早期 |
| DB2 | `REORG TABLE ... INPLACE` | 是 | 否 | 9.x |
| DB2 | `ADMIN_MOVE_TABLE` | 是（COPY 模式 online） | 否 | 9.7 (2009) |
| Snowflake | -- | 自动（micro-partition） | -- | 完全托管 |
| BigQuery | -- | 自动（不可变 Capacitor） | -- | 完全托管 |
| Redshift | `VACUUM FULL` | 否（弱阻塞） | 弱阻塞 | 早期 |
| DuckDB | `VACUUM ANALYZE` | -- | 是（单进程） | 全部 |
| ClickHouse | `OPTIMIZE TABLE ... FINAL` | -- | 否（后台合并） | 全部 |
| Trino / Presto | -- | -- | -- | 不存数据 |
| Spark SQL | -- | -- | -- | 不直接管理表存储 |
| Hive | -- | -- | -- | 通过 ACID 表的 compaction |
| Flink SQL | -- | -- | -- | 状态后端管理 |
| Databricks（Delta） | `OPTIMIZE` + `VACUUM` | 是 | 否（事务日志） | 早期 |
| Teradata | `INSERT ... SELECT` 重建 | 否 | 是（DBA 流程） | 全部 |
| Greenplum | `VACUUM FULL` / `CLUSTER` | -- | 是 | 继承 PG |
| CockroachDB | -- | -- | -- | LSM 自动 compaction |
| TiDB | -- | -- | -- | LSM 自动 compaction |
| OceanBase | `ALTER TABLE ... REORGANIZE` | 是 | 否 | 全部 |
| YugabyteDB | -- | -- | -- | DocDB compaction |
| SingleStore | `OPTIMIZE TABLE` | 是 | 否 | 全部 |
| Vertica | `MERGE_PARTITIONS` / `PURGE` | 是 | 否（部分场景） | 早期 |
| Impala | -- | -- | -- | 不直接管理 |
| StarRocks | -- | -- | -- | BE 后台 compaction |
| Doris | -- | -- | -- | BE 后台 compaction |
| MonetDB | -- | -- | -- | 自动 |
| CrateDB | `OPTIMIZE` | -- | 否（段合并） | 全部 |
| TimescaleDB | `compress_chunk` / `decompress_chunk` | 是 | 否 | 1.5+ |
| QuestDB | -- | -- | -- | 自动 |
| Exasol | -- | -- | -- | 自动 |
| SAP HANA | `ALTER TABLE ... RECLAIM DATA SPACE` | 是 | 否 | 2.0+ |
| Informix | `INFO TABLES` + 重组 | 否 | 是 | 全部 |
| Firebird | `gfix` 工具（offline） | -- | 是 | 全部 |
| H2 | `SHUTDOWN COMPACT` | -- | 是（关库时） | 全部 |
| HSQLDB | `CHECKPOINT DEFRAG` | -- | 是 | 全部 |
| Derby | `SYSCS_UTIL.SYSCS_COMPRESS_TABLE` | 否 | 是 | 全部 |
| Amazon Athena | -- | -- | -- | 不存数据 |
| Azure Synapse | `ALTER INDEX ALL ... REBUILD` | 否 | 否（带 ONLINE） | GA |
| Google Spanner | -- | -- | -- | 自动 |
| Materialize | -- | -- | -- | 状态自动 |
| RisingWave | -- | -- | -- | 状态自动 |
| InfluxDB | -- | -- | -- | TSM compaction |
| Databend | `OPTIMIZE TABLE` | -- | 否 | 全部 |
| Yellowbrick | `VACUUM` | -- | 否 | 全部 |
| Firebolt | -- | -- | -- | 自动 |

> 统计：约 18 个引擎暴露**显式**的在线表重组命令或工具，约 14 个引擎自动管理（云原生 / OLAP / LSM 系），约 13 个引擎只支持 offline 重组。

### 2. 重组期间并发 DML

| 引擎 | 重组命令 | INSERT | UPDATE | DELETE | 语义保证 |
|------|---------|--------|--------|--------|---------|
| Oracle | `MOVE ONLINE` | 是 | 是 | 是 | 内部 mlog 表记录变更 |
| Oracle | `DBMS_REDEFINITION` | 是 | 是 | 是 | 物化视图日志 + SYNC_INTERIM |
| SQL Server | `REBUILD ONLINE` | 是 | 是 | 是 | row versioning + sch-S 锁 |
| MySQL InnoDB | `ALGORITHM=INPLACE` | 是 | 是 | 是 | Online DDL Log 回放 |
| pt-osc | 触发器复制 | 是 | 是 | 是 | 应用层触发器 + chunk copy |
| gh-ost | binlog 复制 | 是 | 是 | 是 | binlog 流式追平 |
| pg_repack | pg_repack | 是 | 是 | 是 | 触发器 + log table |
| pg_squeeze | logical decoding | 是 | 是 | 是 | 逻辑解码 + 重放 |
| DB2 ADMIN_MOVE_TABLE | COPY 阶段 | 是 | 是 | 是 | 触发器 staging table |
| OceanBase | REORGANIZE | 是 | 是 | 是 | 内部协议 |
| TimescaleDB | compress_chunk | 是 | 是 | 是 | 12+ 起允许压缩 chunk 上的 DML |
| PostgreSQL CLUSTER | CLUSTER | 否 | 否 | 否 | AccessExclusiveLock |
| PostgreSQL VACUUM FULL | VACUUM FULL | 否 | 否 | 否 | AccessExclusiveLock |
| Redshift VACUUM FULL | VACUUM FULL | 是（弱阻塞） | 是（弱阻塞） | 是（弱阻塞） | 后台批 |

### 3. 可恢复（Resumable / Pausable）

可恢复重组允许操作中途暂停（手动或因故障），重启时不必从头开始——这对超大表和有限维护窗口非常关键。

| 引擎 | 操作 | 暂停命令 | 恢复命令 | 引入版本 |
|------|------|---------|---------|---------|
| SQL Server | `ALTER TABLE/INDEX ... REBUILD WITH (RESUMABLE=ON)` | `ALTER INDEX ... PAUSE` | `ALTER INDEX ... RESUME` | 2017 SP1 / Azure SQL Database (2017) |
| Oracle | `ALTER SESSION ENABLE RESUMABLE` | 自动暂停（资源不足） | 自动恢复 | 9i+ |
| pg_repack | `pg_repack` | 不支持 | 须重新开始 | -- |
| gh-ost | gh-ost | 是（信号 USR2） | 是（重启读 binlog） | 早期 |
| pt-osc | pt-online-schema-change | 是（中断 chunk） | 否（须重新开始） | -- |
| DB2 ADMIN_MOVE_TABLE | INIT/COPY/REPLAY 阶段独立 | 阶段间暂停 | 调用下一阶段 | 9.7+ |
| MySQL InnoDB | INPLACE | 不支持 | -- | -- |
| PostgreSQL VACUUM FULL/CLUSTER | -- | -- | -- | 不支持 |

> SQL Server 2017 SP1 引入的 RESUMABLE 是同类功能中最完整的：可手动 PAUSE/RESUME，可设置 `MAX_DURATION` 自动暂停（达到时间窗口后），可在故障重启后从断点继续。Oracle 的 RESUMABLE 是另一种语义——遇到 ORA-1652 类资源不足错误时挂起等待，而非用户主动控制。

### 4. 在线聚簇（Cluster on Index）

聚簇就是按某个索引顺序物理排列堆数据。在线聚簇允许重组期间继续写入。

| 引擎 | 命令 | 持久化 | 在线 | 备注 |
|------|------|-------|------|------|
| Oracle | `ALTER TABLE ... MOVE ONLINE` 后跟 `INCLUDING INDEX_ORG`（IOT） | 是 | 是 | 索引组织表（IOT） |
| Oracle | 聚簇表（CLUSTER） | 是 | 否（建表时） | DDL CREATE CLUSTER |
| SQL Server | 聚簇索引 = 物理顺序 | 是 | `REBUILD ONLINE` 维持 | 表的物理顺序由 CLUSTERED INDEX 决定 |
| MySQL InnoDB | 主键 = 聚簇键 | 是 | 主键变更可在线 | 主键即聚簇 |
| PostgreSQL | `CLUSTER table USING index` | 否（一次性） | **不在线**（AccessExclusiveLock） | 重新插入后顺序丢失 |
| PostgreSQL + pg_repack | `pg_repack -t table -i index` | 否（一次性） | 是 | 重组时按索引排序 |
| DB2 | `REORG TABLE ... INDEX clustering_idx` | 否 | INPLACE 模式在线 | -- |
| Redshift | sort key（DDL） | 是 | `VACUUM SORT ONLY` 维护 | -- |
| ClickHouse | ORDER BY（DDL） | 是 | `OPTIMIZE` 触发合并 | MergeTree 天生有序 |
| Snowflake | `CLUSTER BY` | 是（自动维护） | 自动 | 后台微分区重组 |
| BigQuery | `CLUSTER BY` | 是 | 自动 | 写入时分簇 |
| TiDB | 聚簇主键（CLUSTERED） | 是 | DDL | 6.x+ |
| CockroachDB | 主键 = 物理顺序 | 是 | DDL | KV 存储 |
| Vertica | Projection ORDER BY | 是 | refresh 维护 | -- |
| SingleStore | sort key（columnstore） | 是 | OPTIMIZE | -- |

> PostgreSQL 的 `CLUSTER` 命令是非持久的——重新插入数据不会自动按索引顺序排列，需要再次手动 CLUSTER。这是 PG 设计哲学——保持 heap 简单，让聚簇成为一次性整理动作。

### 5. 在线重组工具生态

| 工具 | 适用引擎 | 核心机制 | 维护方 | 首发 |
|------|---------|---------|--------|------|
| pt-online-schema-change（pt-osc） | MySQL/MariaDB | 影子表 + 触发器 + chunk copy | Percona | 2011 |
| gh-ost | MySQL/MariaDB | 影子表 + binlog 复制 | GitHub | 2016 |
| lhm（Large Hadron Migrator） | MySQL | 影子表 + 触发器 | SoundCloud | 2013 |
| pg_repack | PostgreSQL | 影子表 + 触发器 + log table | NTT | 2010 |
| pg_squeeze | PostgreSQL | 逻辑解码 + 重放 | Cybertec | 2016 |
| OnlineSchemaChange (Meta) | MySQL | 影子表 + 触发器 | Meta（Facebook） | 2022 |
| Skeema | MySQL | declarative schema + osc 集成 | Skeema | 2016 |
| Oracle DBMS_REDEFINITION | Oracle | 物化视图日志 + 切换 | Oracle | 2001 (9i) |
| DB2 ADMIN_MOVE_TABLE | DB2 LUW | 触发器 + staging | IBM | 2009 (9.7) |

## 各引擎实现详解

### Oracle：在线表重组的工业级标杆

Oracle 是关系数据库领域唯一在 1990 年代就把"在线维护"作为产品差异化能力的厂商。它在表重组上提供了**两套并存**的方案：

#### `ALTER TABLE ... MOVE`（基础语法）

```sql
-- 基础形式（offline，会阻塞所有 DML，11g 之前的唯一选项）
ALTER TABLE orders MOVE TABLESPACE users_new;

-- 12cR1（2013）开始支持非分区堆表的 ONLINE
ALTER TABLE orders MOVE ONLINE;

-- 12cR2（2017-03）扩展到分区表 + IOT
ALTER TABLE orders MOVE PARTITION p2024 ONLINE;

-- 多种迁移目标
ALTER TABLE orders MOVE
    TABLESPACE users_2024
    COMPRESS FOR OLTP
    PCTFREE 10
    INITRANS 8
    ONLINE;

-- 可同时更新依赖索引（避免索引失效）
ALTER TABLE orders MOVE ONLINE UPDATE INDEXES;

-- 索引组织表（IOT）的在线移动
ALTER TABLE orders_iot MOVE ONLINE
    INCLUDING idx_orders_pk
    OVERFLOW TABLESPACE users_overflow;
```

`ALTER TABLE ... MOVE ONLINE` 的内部机制：
1. 创建一份"日志表"（IOT 用 mapping table，普通表用内部隐藏表）记录重组期间的 DML
2. 创建新数据段，开始按当前数据复制行
3. 复制过程中所有 DML 都同时写到旧段和日志表
4. 复制完成后，回放日志表追平最新变更
5. 短暂获取排他锁，原子切换段头指针，自动维护索引（如指定 `UPDATE INDEXES`）

#### `DBMS_REDEFINITION`（细粒度的在线重定义）

`DBMS_REDEFINITION` 是 Oracle 9i（2001 年）就引入的更强大的方案。它允许**任意 schema 变更**（添加列、改类型、改约束、调整分区策略）的同时完成重组。

```sql
-- 1. 检查是否可在线重定义
BEGIN
    DBMS_REDEFINITION.CAN_REDEF_TABLE(
        uname        => 'SCOTT',
        tname        => 'ORDERS',
        options_flag => DBMS_REDEFINITION.CONS_USE_PK
    );
END;
/

-- 2. 创建中间表（interim table），可包含目标 schema
CREATE TABLE scott.orders_interim (
    order_id      NUMBER(15) NOT NULL,
    customer_id   NUMBER(15) NOT NULL,
    amount        NUMBER(18,2),
    created_at    TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP,
    region_code   VARCHAR2(20),  -- 新增列
    CONSTRAINT pk_orders_int PRIMARY KEY (order_id)
)
TABLESPACE users_2024
COMPRESS FOR OLTP
PARTITION BY RANGE (created_at) (
    PARTITION p2023 VALUES LESS THAN (TIMESTAMP '2024-01-01 00:00:00 +00:00'),
    PARTITION p2024 VALUES LESS THAN (TIMESTAMP '2025-01-01 00:00:00 +00:00')
);

-- 3. 启动重定义（创建物化视图日志）
BEGIN
    DBMS_REDEFINITION.START_REDEF_TABLE(
        uname           => 'SCOTT',
        orig_table      => 'ORDERS',
        int_table       => 'ORDERS_INTERIM',
        col_mapping     => 'order_id, customer_id, amount, created_at,
                            UPPER(region) AS region_code',
        options_flag    => DBMS_REDEFINITION.CONS_USE_PK
    );
END;
/

-- 4. 复制依赖对象（约束、索引、触发器）
DECLARE
    num_errors PLS_INTEGER;
BEGIN
    DBMS_REDEFINITION.COPY_TABLE_DEPENDENTS(
        uname        => 'SCOTT',
        orig_table   => 'ORDERS',
        int_table    => 'ORDERS_INTERIM',
        copy_indexes => DBMS_REDEFINITION.CONS_ORIG_PARAMS,
        num_errors   => num_errors
    );
    DBMS_OUTPUT.PUT_LINE('Errors: ' || num_errors);
END;
/

-- 5. 周期同步增量（可多次调用，缩短最后一次同步的时间）
BEGIN
    DBMS_REDEFINITION.SYNC_INTERIM_TABLE(
        uname      => 'SCOTT',
        orig_table => 'ORDERS',
        int_table  => 'ORDERS_INTERIM'
    );
END;
/

-- 6. 完成切换（原子操作，瞬间完成）
BEGIN
    DBMS_REDEFINITION.FINISH_REDEF_TABLE(
        uname      => 'SCOTT',
        orig_table => 'ORDERS',
        int_table  => 'ORDERS_INTERIM'
    );
END;
/

-- 7. 可选：删除中间表（现已变为旧表）
DROP TABLE scott.orders_interim PURGE;

-- 异常情况下回滚
BEGIN
    DBMS_REDEFINITION.ABORT_REDEF_TABLE(
        uname      => 'SCOTT',
        orig_table => 'ORDERS',
        int_table  => 'ORDERS_INTERIM'
    );
END;
/
```

`DBMS_REDEFINITION` 的核心机制基于**物化视图日志**：

```
原表 ORDERS                           中间表 ORDERS_INTERIM
   ↓                                       ↑
[mview log]  ← DML 增量复制 ← [INSERT … SELECT 初始填充]
   ↓
SYNC_INTERIM_TABLE 多次调用追平
   ↓
FINISH_REDEF_TABLE: 短暂锁 + 原子切换名字
   - 原表更名为 ORDERS_INTERIM
   - 中间表更名为 ORDERS
   - 所有 grant、约束、依赖对象自动迁移
```

`DBMS_REDEFINITION` vs `MOVE ONLINE` 的选择：

| 维度 | `MOVE ONLINE` | `DBMS_REDEFINITION` |
|------|--------------|---------------------|
| Schema 变更 | 不支持 | 支持任意变更 |
| 分区策略变更 | 仅 MOVE PARTITION | 支持完全重新分区 |
| 用户控制 | 一条命令 | 多步骤可干预 |
| 同步频率 | 后台自动 | 可手动多次 SYNC |
| 中断恢复 | 自动 | 调用 ABORT 然后重新开始 |
| 依赖对象 | UPDATE INDEXES | COPY_TABLE_DEPENDENTS |
| 适用场景 | 仅做物理重组（迁表空间、压缩、整理） | 同时做物理重组 + schema 升级 |

#### `ALTER TABLE ... SHRINK SPACE`（不重写文件，调整 HWM）

```sql
-- 紧凑（compact）：移动行降低 HWM 候选位置，但不实际改 HWM
-- 在线、不阻塞 DML
ALTER TABLE orders ENABLE ROW MOVEMENT;
ALTER TABLE orders SHRINK SPACE COMPACT;

-- SHRINK SPACE：实际降低 HWM，瞬间获取排他锁
-- 通常 < 1 秒，但仍是阻塞操作
ALTER TABLE orders SHRINK SPACE;

-- CASCADE 同时收缩依赖索引
ALTER TABLE orders SHRINK SPACE CASCADE;
```

SHRINK 的优势是不重写文件、不需要双倍空间，只是**重新整理段内的行位置**。劣势是粒度比 MOVE 粗（不能改压缩策略、不能换表空间）。

### SQL Server：REBUILD WITH ONLINE 与 RESUMABLE

SQL Server 自 2005 企业版开始支持 `WITH (ONLINE = ON)`，是除 Oracle 外最早进入"在线维护"工业化阶段的引擎。2017 SP1 进一步引入了**可暂停**的索引/表重建，把该领域推到一个新高度。

```sql
-- 表级在线重建（实际上是重建聚簇索引 = 整张表重写）
ALTER TABLE dbo.Orders REBUILD WITH (ONLINE = ON);

-- 整表 + 所有非聚簇索引一起重建
ALTER INDEX ALL ON dbo.Orders REBUILD WITH (ONLINE = ON);

-- 重建分区表的特定分区（2014+）
ALTER TABLE dbo.Orders REBUILD PARTITION = 5
    WITH (ONLINE = ON, MAXDOP = 4);

-- 指定填充率，预留更新空间
ALTER TABLE dbo.Orders REBUILD
    WITH (ONLINE = ON, FILLFACTOR = 90, MAXDOP = 8);

-- RESUMABLE 重建（2017 SP1 / Azure SQL）
ALTER INDEX PK_Orders ON dbo.Orders REBUILD
    WITH (ONLINE = ON, RESUMABLE = ON, MAX_DURATION = 240 MINUTES);

-- 暂停
ALTER INDEX PK_Orders ON dbo.Orders PAUSE;

-- 恢复
ALTER INDEX PK_Orders ON dbo.Orders RESUME
    WITH (MAX_DURATION = 60 MINUTES, MAXDOP = 2);

-- 终止（放弃当前进度）
ALTER INDEX PK_Orders ON dbo.Orders ABORT;

-- 查询 RESUMABLE 进度
SELECT
    object_name(object_id)                     AS table_name,
    name                                        AS index_name,
    state_desc,
    percent_complete,
    last_pause_time,
    page_count,
    total_execution_time
FROM sys.index_resumable_operations;
```

SQL Server 的 ONLINE 重建底层机制基于**版本控制 + 同步替换**：

```
 [原索引/堆]                  [新索引/堆构建中]
     ↑                              ↑
     ├── 读取（行版本快照）          ├── 后台扫描 + 排序 + 写入
     ├── INSERT/UPDATE/DELETE       └── 同步从原结构复制变更
     │   写入两份（行版本同步）
     │
     [短暂的 SCH-M 锁切换指针]
     ↓
 [新结构成为最终结构]
```

关键限制：
- 早期版本的 LOB（VARCHAR(MAX)/TEXT/IMAGE）不支持 ONLINE，2012+ 起放开
- ONLINE 重建需要更多事务日志和 tempdb（用于行版本）
- RESUMABLE 不支持禁用了 row versioning 的临时表

### PostgreSQL：CLUSTER 与 VACUUM FULL 都是 offline

PostgreSQL 内核长期没有真正的在线表重组——`CLUSTER` 和 `VACUUM FULL` 都需要 `AccessExclusiveLock`（阻塞所有读写）。这一限制在过去 15 年间催生了三个主流外部工具：**pg_repack**（NTT 2010）、**pg_squeeze**（Cybertec 2016），以及一些基于 `CREATE TABLE LIKE + INSERT + ALTER ... RENAME` 的应用层方案。

```sql
-- 内核原生方案（offline）
-- CLUSTER：按索引重组堆，回收空间，更新统计信息
CLUSTER orders USING idx_orders_created_at;

-- 之前 ALTER TABLE ... CLUSTER ON 标记的索引可省略 USING 子句
ALTER TABLE orders CLUSTER ON idx_orders_created_at;
CLUSTER orders;

-- 注意：CLUSTER 是一次性的，新插入的行不会保持顺序
-- 持续 INSERT 后需要再次 CLUSTER

-- 整库 CLUSTER 之前所有 ALTER TABLE ... CLUSTER ON 标记过的表
CLUSTER;

-- VACUUM FULL：重写整张表，回收空间
-- 不按索引排序，但产生紧凑的新堆
VACUUM FULL orders;
VACUUM (FULL, VERBOSE, ANALYZE) orders;
```

`CLUSTER` 和 `VACUUM FULL` 都通过创建一份新堆 + 复制 + 重命名实现，过程中持有排他锁。9.0 之前的 VACUUM FULL 是真正"原地紧凑"，但因为锁碎片化和性能问题，9.0 之后改为重写式。

为什么 PG 内核不支持在线重组？历史原因：
1. PG 的 heap 没有 InnoDB 那样的"行版本链表"——每行的多版本独立存储，重组需要重新计算所有 ctid，难度大于 Oracle/InnoDB
2. PG 的索引项直接指向 ctid（物理位置），表重组必须同步重写所有索引
3. 社区认为这种重型操作可由扩展实现，无需进核心

### pg_repack：触发器 + 影子表方案

pg_repack 是目前最广泛使用的 PG 在线重组扩展，由 NTT 在 2010 年开源。它通过**触发器 + log table + 切换表名**实现。

```bash
# 安装
$ apt-get install postgresql-15-repack

# 简单调用：按主键聚簇重组 orders 表
$ pg_repack -d mydb -t public.orders

# 按特定索引聚簇
$ pg_repack -d mydb -t public.orders -i idx_orders_created_at

# 仅重建索引（不重写表）
$ pg_repack -d mydb -t public.orders -x

# 整库重组（指定多个表）
$ pg_repack -d mydb --all

# 干跑（仅打印将执行的 SQL）
$ pg_repack -d mydb -t public.orders --dry-run

# 调整 chunk 大小、并发度
$ pg_repack -d mydb -t public.orders -j 4 --no-superuser-check

# 设置等待时长（避免长事务阻塞）
$ pg_repack -d mydb -t public.orders --wait-timeout=60
```

pg_repack 的内部流程：

```
1. 创建影子表 SHADOW = repack.table_<oid>，与原表同 schema
2. 创建 log table LOG = repack.log_<oid> 和触发器
3. 触发器：原表的 INSERT/UPDATE/DELETE 都同步写入 LOG
4. INSERT INTO SHADOW SELECT ... FROM 原表 ORDER BY index
5. 重放 LOG 中的增量
6. 短暂获取 AccessExclusiveLock：再次重放 + 切换表名
7. 删除原表（已变为影子）和 LOG
```

关键限制：
- 表必须有主键或 NOT NULL UNIQUE 索引
- 不支持有 GIN 索引的表（早期版本，新版本部分支持）
- 不能用于系统目录、临时表
- 重组期间触发器额外开销约 10-20%
- 需要等量于原表的额外磁盘空间

### pg_squeeze：逻辑解码方案

pg_squeeze 由 Cybertec 在 2016 年开源，是 pg_repack 的现代化替代。它使用 PostgreSQL 9.4+ 的**逻辑解码（logical decoding）** 而非触发器，避免了对原表性能的影响。

```sql
-- 安装
CREATE EXTENSION pg_squeeze;

-- 注册要监控的表
INSERT INTO squeeze.tables (tabschema, tabname, schedule)
VALUES ('public', 'orders', '(0,1,2)');  -- 凌晨 0/1/2 点检查

-- 立即重组
SELECT squeeze.squeeze_table('public', 'orders', NULL, NULL);

-- 按特定索引聚簇
SELECT squeeze.squeeze_table(
    tabschema => 'public',
    tabname   => 'orders',
    clustering_index => 'idx_orders_created_at'
);

-- 查询自动重组任务
SELECT * FROM squeeze.tables;

-- 查询历史任务
SELECT * FROM squeeze.tasks ORDER BY started DESC LIMIT 20;
```

pg_squeeze 的内部流程：

```
1. 创建复制槽（replication slot），开始捕获原表 WAL 变更
2. 创建影子表 SHADOW，复制基础数据
3. 解码并重放 WAL 中的增量
4. 短暂获取 AccessExclusiveLock：最终追平 + 切换 relfilenode
5. 删除复制槽
```

pg_squeeze vs pg_repack 对比：

| 维度 | pg_repack | pg_squeeze |
|------|-----------|-----------|
| 增量捕获 | 触发器 + log table | 逻辑解码（WAL） |
| 对原表影响 | 触发器开销 ~10-20% | 几乎无开销 |
| 锁开销 | 短暂 AccessExclusiveLock | 短暂 AccessExclusiveLock |
| 索引同步 | 主动重建 | 主动重建 |
| 内置调度 | 否（需 cron） | 是（squeeze.tables） |
| 部署形式 | 客户端命令 + 扩展 | 服务端扩展 + 函数 |
| 切换机制 | 重命名 | swap relfilenode |
| 故障恢复 | 须重新开始 | 须重新开始 |
| 社区活跃 | 高（NTT 维护） | 中（Cybertec 维护） |

实际选型上，pg_repack 因为成熟度高、文档全、生态广，仍是大多数场景的首选；pg_squeeze 对触发器开销敏感的极高 TPS 场景更优。

### MySQL：Online DDL + 第三方 OSC 工具

MySQL InnoDB 自 5.6（2013）起把 ALTER TABLE 默认升级为 Online DDL，支持大多数操作不阻塞 DML。这同时也提供了"重组表"的内置能力——`ALTER TABLE ... ENGINE=InnoDB`（重写表，等价于 `OPTIMIZE TABLE`）。

```sql
-- 重组（重写）整张表 = 等价于 OPTIMIZE TABLE
ALTER TABLE orders ENGINE=InnoDB,
    ALGORITHM=INPLACE, LOCK=NONE;

-- OPTIMIZE TABLE 也是同样的内部机制
OPTIMIZE TABLE orders;

-- 查看进度（5.7+）
SELECT * FROM performance_schema.events_stages_current
WHERE event_name LIKE 'stage/innodb/alter table%';

-- 在线变更主键（INPLACE 但需重建表）
ALTER TABLE orders DROP PRIMARY KEY, ADD PRIMARY KEY (id),
    ALGORITHM=INPLACE, LOCK=NONE;

-- INSTANT DDL（8.0+，不重建表，仅改元数据）
ALTER TABLE orders ADD COLUMN status TINYINT,
    ALGORITHM=INSTANT;

-- 8.0.29+ 可在任意位置 INSTANT ADD COLUMN
ALTER TABLE orders ADD COLUMN region VARCHAR(20) AFTER customer_id,
    ALGORITHM=INSTANT;
```

MySQL Online DDL 的内部机制（针对 INPLACE 算法）：

```
1. 获取共享 metadata lock，读取原表元数据
2. 创建新的 .ibd 文件（INPLACE 但需重建时）
3. 短暂排他锁：建立 Online DDL Log（in-memory + 溢出到磁盘）
4. 释放排他锁，扫描 + 复制原表数据到新 .ibd
5. 复制期间所有 DML 都同时写到新文件 + Online DDL Log
6. 复制完成后，回放 Online DDL Log 追平
7. 短暂排他锁：原子重命名 .ibd 文件
```

关键问题：
- Online DDL Log 在内存（可配 `innodb_online_alter_log_max_size`，默认 128MB），溢出后操作失败
- 长时间运行的 ALTER 可能因 binlog 一致性导致主从延迟
- LOCK=NONE 在某些场景下（如更改主键）实际上仍会短暂上锁

这就是社区催生 **pt-osc** 和 **gh-ost** 的原因——它们把 ALTER 转换为应用层的影子表 + 切换流程，绕过 Online DDL Log 的限制。

### gh-ost vs pt-osc：MySQL 社区两大主流方案对比

#### pt-osc（Percona Toolkit Online Schema Change）

pt-osc 由 Percona 在 2011 年发布，是最早的 MySQL OSC 工具。

```bash
# 基础用法：在线重组 sbtest1
pt-online-schema-change \
    --alter "ENGINE=InnoDB" \
    D=test,t=sbtest1 \
    --execute

# 真正变更 schema
pt-online-schema-change \
    --alter "ADD COLUMN status TINYINT NOT NULL DEFAULT 0" \
    D=test,t=orders \
    --execute

# 控制 chunk 大小、并发
pt-online-schema-change \
    --alter "ENGINE=InnoDB" \
    --chunk-size=2000 \
    --max-load Threads_running=50 \
    --critical-load Threads_running=100 \
    D=test,t=orders \
    --execute

# 主从延迟监控
pt-online-schema-change \
    --alter "ENGINE=InnoDB" \
    --max-lag=2 \
    --check-slave-lag h=replica1 \
    D=test,t=orders \
    --execute
```

pt-osc 内部机制（**触发器 + chunk copy**）：

```
1. 创建影子表 _orders_new（与原表同结构，加上需要的变更）
2. 在原表上创建 3 个触发器（INSERT/UPDATE/DELETE）
   每个 DML 都同时操作影子表
3. 按主键范围分批（chunk）从原表 INSERT INTO 影子表
   每个 chunk 是独立事务
4. 复制完成后：
   RENAME TABLE orders TO _orders_old, _orders_new TO orders;
5. 删除 _orders_old 和触发器
```

关键限制：
- **触发器在原表上**，对原表 DML 性能有 10-30% 影响
- 不能用于本身有触发器的表（5.7 之前彻底不支持，之后部分支持）
- 不能用于子表（外键约束需用 `--alter-foreign-keys-method`）
- 主从延迟监控有限

#### gh-ost（GitHub Online Schema Change）

gh-ost 由 GitHub 在 2016 年开源，针对 pt-osc 的两大问题——触发器开销和主从延迟——设计了**binlog 复制**方案。

```bash
# 基础用法
gh-ost \
    --user=root \
    --password=xxx \
    --host=replica1.example.com \
    --database=test \
    --table=orders \
    --alter="ENGINE=InnoDB" \
    --execute

# 通过 replica 读 binlog（推荐生产模式）
gh-ost \
    --user=root \
    --password=xxx \
    --host=replica1.example.com \
    --assume-master-host=master.example.com \
    --database=test \
    --table=orders \
    --alter="ADD COLUMN region VARCHAR(20)" \
    --switch-to-rbr \
    --max-load=Threads_running=25 \
    --critical-load=Threads_running=1000 \
    --chunk-size=1000 \
    --max-lag-millis=1500 \
    --execute

# 暂停（信号 USR2）
killall -USR2 gh-ost

# 通过 socket 暂停/继续
echo throttle > /tmp/gh-ost.test.orders.sock
echo no-throttle > /tmp/gh-ost.test.orders.sock

# 立即终止（保留中间状态可恢复）
echo cut-over > /tmp/gh-ost.test.orders.sock
```

gh-ost 内部机制（**binlog 复制 + 影子表**）：

```
1. 创建影子表 _orders_gho
2. 创建 changelog 表 _orders_ghc 用于状态心跳
3. gh-ost 进程订阅 binlog（最好从 replica 读，不增加 master 负载）
4. 同时进行：
   a. 按主键范围分批（chunk）从原表 INSERT INTO 影子表
   b. 解析 binlog 中针对原表的所有 DML，应用到影子表
5. 心跳检测主从延迟、master 负载
6. 切换：
   a. 短暂锁住原表
   b. RENAME 操作
   c. 切换前最后一次 binlog 追平
```

#### gh-ost vs pt-osc 全面对比

| 维度 | pt-osc | gh-ost |
|------|--------|--------|
| 增量捕获 | 触发器 | binlog 解析 |
| 对原表影响 | 触发器 ~10-30% | 几乎无 |
| 主从延迟感知 | 简单 lag 检查 | 心跳 + 自适应限速 |
| 暂停/恢复 | 中断 chunk 后须重新开始 | 信号 USR2 暂停，恢复无缝 |
| 切换控制 | 不可控（自动） | 可手动触发（cut-over） |
| 配置项 | 命令行参数（多） | 命令行 + socket 命令 |
| 异常恢复 | 中断后重新开始 | 中断后可继续（保留 _gho 表） |
| 自定义触发器 | 冲突 | 不冲突（不用触发器） |
| 本身有触发器的表 | 不支持/受限 | 支持 |
| Galera Cluster 兼容 | 部分 | 良好 |
| RDS/Aurora 支持 | 是 | 是 |
| AWS RDS 上的 binlog 方式 | -- | 需要 super 或开启 binlog |
| 生产部署形式 | 单进程 | 单进程 |
| 维护方 | Percona | GitHub（已转向 Vitess） |
| 推荐场景 | 简单环境、快速试用 | 大规模生产、长跑变更 |

> 业界共识：对于稳定的大规模 MySQL 生产环境，**gh-ost 已成为事实标准**。GitHub、Shopify、Vitess、Etsy、Slack 等公司都将其标准化为 schema 变更流水线。pt-osc 仍在小规模、本地开发、CI 场景流行。

### DB2：ADMIN_MOVE_TABLE 与 REORG 双路径

DB2 LUW（Linux/Unix/Windows）在表重组上的能力非常完整，从 9.7（2009）起就支持在线 REORG。

```sql
-- 经典 offline REORG
REORG TABLE schema1.orders;

-- INPLACE REORG（更轻量但仍可能阻塞写）
REORG TABLE schema1.orders INPLACE;
REORG TABLE schema1.orders INPLACE START;
REORG TABLE schema1.orders INPLACE PAUSE;
REORG TABLE schema1.orders INPLACE RESUME;
REORG TABLE schema1.orders INPLACE STOP;

-- 带索引重组
REORG TABLE schema1.orders INDEX idx_created_at;

-- 仅重组索引
REORG INDEXES ALL FOR TABLE schema1.orders;

-- ADMIN_MOVE_TABLE：在线重组 + 可选 schema 变更
CALL SYSPROC.ADMIN_MOVE_TABLE(
    'SCHEMA1',           -- schema
    'ORDERS',            -- table
    'TBSP_DATA_NEW',     -- target tablespace
    '',                  -- index tablespace
    '',                  -- LOB tablespace
    '',                  -- partition definition
    '',                  -- column definition
    '',                  -- index definition
    '',                  -- mdc keys
    'COPY_USE_LOAD,FORCE_ALL', -- options
    'MOVE'                -- operation
);

-- 分阶段执行（精细控制）
CALL SYSPROC.ADMIN_MOVE_TABLE(
    'SCHEMA1', 'ORDERS', 'TBSP_DATA_NEW',
    '', '', '', '', '', '',
    '', 'INIT'
);
CALL SYSPROC.ADMIN_MOVE_TABLE(
    'SCHEMA1', 'ORDERS', '', '', '', '', '', '', '',
    '', 'COPY'
);
CALL SYSPROC.ADMIN_MOVE_TABLE(
    'SCHEMA1', 'ORDERS', '', '', '', '', '', '', '',
    '', 'REPLAY'
);
CALL SYSPROC.ADMIN_MOVE_TABLE(
    'SCHEMA1', 'ORDERS', '', '', '', '', '', '', '',
    '', 'SWAP'
);
CALL SYSPROC.ADMIN_MOVE_TABLE(
    'SCHEMA1', 'ORDERS', '', '', '', '', '', '', '',
    '', 'CLEANUP'
);

-- 查询进度
SELECT * FROM SYSTOOLS.ADMIN_MOVE_TABLE
WHERE TABNAME = 'ORDERS';
```

`ADMIN_MOVE_TABLE` 内部分 6 阶段：

```
INIT       创建 staging table 和触发器
COPY       INSERT INTO ... SELECT 初始填充
REPLAY     重放 staging 中的增量（可多次调用）
VERIFY     可选的一致性校验
SWAP       原子切换（短暂锁）
CLEANUP    清理 staging table 和触发器
```

DB2 的 ADMIN_MOVE_TABLE 是 IBM 在 2009 年率先把 Oracle 风格的 DBMS_REDEFINITION 模式引入开源/标准 SQL 兼容层的实践，对后来的 pg_repack、pt-osc 设计有显著影响。

### CockroachDB / Spanner / Vitess：分布式 SQL 的"无重组"哲学

CockroachDB、TiDB、Google Spanner、Vitess（MySQL 兼容的分片引擎）等分布式 SQL 数据库**不暴露表重组命令**——它们的存储引擎是基于 LSM Tree（RocksDB / Pebble）或不可变的 SSTable，所有"重组"都通过后台 compaction 自动完成。

```sql
-- CockroachDB：没有 VACUUM、CLUSTER、REORG 命令
-- 数据通过 Pebble 的 compaction 自动整理
-- 删除的行通过 MVCC GC 在 ttl=24h（默认）后清除
ALTER ZONE FOR TABLE orders CONFIGURE ZONE USING gc.ttlseconds = 600;

-- Spanner：完全黑盒，自动 split / merge / compact
-- 不暴露重组接口，所有维护工作由 GFS/Colossus 后台进行

-- Vitess：表重组通过 vstream + onlineDDL 实现
-- 内部使用 gh-ost 或自研的 OnlineDDL（基于 vreplication）
SET @@ddl_strategy = 'online';
ALTER TABLE orders ENGINE=InnoDB;

-- 监控 Vitess OnlineDDL
SELECT * FROM mysql.schema_migrations WHERE migration_status != 'complete';
```

这种设计的优劣：

**优点**：用户完全不用关心物理重组，数据库自动维护磁盘布局；无需维护窗口；自动适应负载变化。

**缺点**：用户失去对重组时机的控制——业务峰值期间也可能触发 compaction；compaction 的资源消耗不可预测；某些场景（如批量删除后期望立即回收）无显式入口。

### 列存与 OLAP 引擎的"重组" = 合并 part

列存引擎（ClickHouse、Vertica、Redshift、Doris、StarRocks、Snowflake、BigQuery）的物理单位不是页面而是 part / micro-partition / segment。它们的重组本质上是**合并小 part 为大 part**。

#### ClickHouse：OPTIMIZE TABLE

```sql
-- 触发后台合并到最大 part
OPTIMIZE TABLE events;

-- 强制合并到一个 part（昂贵，不建议生产常用）
OPTIMIZE TABLE events FINAL;

-- 仅合并某个分区
OPTIMIZE TABLE events PARTITION '2024-01' FINAL;

-- 等待合并完成（默认异步）
OPTIMIZE TABLE events FINAL SETTINGS optimize_throw_if_noop = 1;

-- 控制后台合并
SYSTEM START MERGES events;
SYSTEM STOP MERGES events;

-- 监控 part 数量和合并状态
SELECT
    table,
    sum(rows)             AS rows,
    sum(bytes_on_disk)    AS bytes,
    count()               AS parts,
    max(level)            AS max_level
FROM system.parts
WHERE active AND table = 'events'
GROUP BY table;
```

ClickHouse 的 part 合并由后台 merge thread pool 自动触发，规则基于 part 大小、年龄、级别（level）。`OPTIMIZE FINAL` 会强制把所有 active part 合并为一个，但代价高昂（重写整张表）。

#### Snowflake / BigQuery：完全自动

```sql
-- Snowflake 不暴露表重组语法
-- micro-partition 的重组由后台服务自动完成
-- 唯一可控的是 clustering：
ALTER TABLE orders CLUSTER BY (customer_id, created_at);

-- 检查聚簇质量
SELECT SYSTEM$CLUSTERING_INFORMATION('orders');

-- 手动重新聚簇（极少需要）
ALTER TABLE orders RECLUSTER;

-- BigQuery 也类似
CREATE OR REPLACE TABLE orders
PARTITION BY DATE(created_at)
CLUSTER BY customer_id
AS SELECT * FROM orders;

-- 查看分区元数据
SELECT * FROM `project.dataset.INFORMATION_SCHEMA.PARTITIONS`
WHERE table_name = 'orders';
```

#### Databricks Delta Lake：OPTIMIZE + Z-ORDER

```sql
-- 基础合并（小文件 → 大文件）
OPTIMIZE orders;

-- 按列做 Z-order 聚簇
OPTIMIZE orders ZORDER BY (customer_id, created_at);

-- 仅优化某分区
OPTIMIZE orders WHERE date >= '2024-01-01';

-- 自动优化（写入时）
ALTER TABLE orders SET TBLPROPERTIES (
    'delta.autoOptimize.optimizeWrite' = 'true',
    'delta.autoOptimize.autoCompact' = 'true'
);

-- VACUUM 清理已被新文件取代的旧文件
VACUUM orders RETAIN 168 HOURS;  -- 保留 7 天版本

-- 预测性优化（Predictive Optimization，2024 GA）
ALTER TABLE orders SET TBLPROPERTIES (
    'delta.predictiveOptimization' = 'true'
);
```

#### Vertica：MERGE_PARTITIONS

```sql
-- 触发分区内 ROS 容器合并（重组）
SELECT MERGE_PARTITIONS('public.orders', '2024-01-01', '2024-12-31');

-- PURGE 真删除（移除墓碑）
SELECT PURGE_TABLE('public.orders');

-- 移动 projection 到新存储位置
SELECT MOVE_STATEMENT('public.orders');
```

### TimescaleDB：chunk 压缩与重组

TimescaleDB 是 PG 上的时序扩展，把 hypertable 切成大量 chunk（按时间）。它的"重组"是把热 chunk 压缩为列存格式。

```sql
-- 创建 hypertable
SELECT create_hypertable('metrics', 'time', chunk_time_interval => INTERVAL '1 day');

-- 启用压缩
ALTER TABLE metrics SET (
    timescaledb.compress,
    timescaledb.compress_segmentby = 'sensor_id',
    timescaledb.compress_orderby = 'time DESC'
);

-- 添加压缩策略（自动）
SELECT add_compression_policy('metrics', INTERVAL '7 days');

-- 手动压缩单个 chunk
SELECT compress_chunk(c) FROM show_chunks('metrics') c;

-- 解压（用于回写）
SELECT decompress_chunk(c) FROM show_chunks('metrics', older_than => INTERVAL '30 days') c;

-- 查询压缩状态
SELECT * FROM timescaledb_information.compressed_chunk_stats;
```

TimescaleDB 12（2024）起允许在压缩 chunk 上执行 INSERT/UPDATE/DELETE，标志着列存 chunk 的"在线重组"达到了和行存表同等的可用性。

## Oracle DBMS_REDEFINITION 深度剖析

`DBMS_REDEFINITION` 是 Oracle 数据库工程师工具箱里最强大的 schema 变更/重组武器。它的设计思路——**interim table + materialized view log + atomic swap**——影响了后来几乎所有的在线 schema 变更工具。

### 工作原理图解

```
原表 ORDERS                          中间表 ORDERS_INTERIM
   ┃                                       ┃
   ┣─→ DML（INSERT/UPDATE/DELETE）         ┣─→ INSERT INTO ... SELECT
   ┃   ↓                                   ┃   （初始数据复制 + 类型/约束/列变更）
   ┃   写入 mview log                      ┃
   ┃                                       ┃
   ┃   START_REDEF_TABLE 创建 mview        ┃
   ┃                                       ┃
   ┣─→ SYNC_INTERIM_TABLE（多次）          ┣─→ 重放 log 中的 DML
   ┃                                       ┃
   ┣─→ COPY_TABLE_DEPENDENTS               ┣─→ 复制约束/索引/触发器
   ┃                                       ┃
   ┣─→ FINISH_REDEF_TABLE                  ┃
   ┃   短暂锁                              ┃
   ┃   重命名：原表→ORDERS_INTERIM        ┃
   ┃   重命名：中间表→ORDERS              ┃
   ┃                                       ┃
   ┗──────────────────────────────────────┛
       现在 ORDERS 是新表，原表是 ORDERS_INTERIM
```

### 实战场景：把无分区表改成范围分区

```sql
-- 现状：ORDERS 是非分区堆表，2 亿行，需要按月分区
-- 步骤：

-- 1. 检查可在线重定义
DECLARE
    can_redef PLS_INTEGER;
BEGIN
    DBMS_REDEFINITION.CAN_REDEF_TABLE(
        uname        => USER,
        tname        => 'ORDERS',
        options_flag => DBMS_REDEFINITION.CONS_USE_PK
    );
END;
/

-- 2. 创建分区中间表
CREATE TABLE orders_interim (
    order_id      NUMBER(15) NOT NULL,
    customer_id   NUMBER(15) NOT NULL,
    amount        NUMBER(18,2),
    created_at    TIMESTAMP NOT NULL,
    status        VARCHAR2(20),
    CONSTRAINT pk_orders_int PRIMARY KEY (order_id) USING INDEX LOCAL
)
PARTITION BY RANGE (created_at) INTERVAL (NUMTOYMINTERVAL(1,'MONTH')) (
    PARTITION p_initial VALUES LESS THAN (TIMESTAMP '2020-01-01 00:00:00')
)
COMPRESS FOR OLTP
TABLESPACE ts_orders_2024;

-- 3. 启动重定义
BEGIN
    DBMS_REDEFINITION.START_REDEF_TABLE(
        uname           => USER,
        orig_table      => 'ORDERS',
        int_table       => 'ORDERS_INTERIM',
        col_mapping     => NULL,  -- 列同名时可省略
        options_flag    => DBMS_REDEFINITION.CONS_USE_PK,
        orderby_cols    => 'created_at, customer_id'  -- 物理顺序
    );
END;
/

-- 4. 复制约束、索引、触发器
DECLARE
    err_count PLS_INTEGER;
BEGIN
    DBMS_REDEFINITION.COPY_TABLE_DEPENDENTS(
        uname             => USER,
        orig_table        => 'ORDERS',
        int_table         => 'ORDERS_INTERIM',
        copy_indexes      => DBMS_REDEFINITION.CONS_ORIG_PARAMS,
        copy_triggers     => TRUE,
        copy_constraints  => TRUE,
        copy_privileges   => TRUE,
        ignore_errors     => FALSE,
        num_errors        => err_count
    );
    DBMS_OUTPUT.PUT_LINE('Errors during copy_dependents: ' || err_count);
END;
/

-- 5. 多次同步（在维护窗口前缩短最后一次同步的时长）
BEGIN
    DBMS_REDEFINITION.SYNC_INTERIM_TABLE(
        uname      => USER,
        orig_table => 'ORDERS',
        int_table  => 'ORDERS_INTERIM'
    );
END;
/

-- 6. 完成切换
BEGIN
    DBMS_REDEFINITION.FINISH_REDEF_TABLE(
        uname      => USER,
        orig_table => 'ORDERS',
        int_table  => 'ORDERS_INTERIM'
    );
END;
/

-- 7. 删除旧表（现在叫 ORDERS_INTERIM）
DROP TABLE orders_interim PURGE;

-- 8. 收集统计信息
EXEC DBMS_STATS.GATHER_TABLE_STATS(USER, 'ORDERS', degree => 8);
```

### 关键参数与陷阱

| 参数 / 选项 | 作用 | 默认 / 推荐 |
|------------|------|------------|
| `options_flag => CONS_USE_PK` | 用主键作为唯一标识跟踪行 | 推荐（要求有 PK） |
| `options_flag => CONS_USE_ROWID` | 用 ROWID 跟踪 | 仅当无 PK 时使用 |
| `orderby_cols` | 物理顺序（聚簇） | 按访问模式选择 |
| `copy_indexes => CONS_ORIG_PARAMS` | 索引保留原参数（PCTFREE 等） | 推荐 |
| `copy_constraints => TRUE` | 复制约束 | 推荐 |
| `copy_triggers => TRUE` | 复制触发器 | 注意触发器在新表上立即生效 |
| `copy_privileges => TRUE` | 复制 GRANT | 推荐 |

常见陷阱：
- 中间表创建时不要建立约束指向原表（会被 COPY_TABLE_DEPENDENTS 重命名）
- LOB 列默认按"copy"模式重定义；超大 LOB 应考虑用 `LOB_OPTIONS_FLAG`
- 长时间运行的事务会阻碍 mview log 的及时清理
- FINISH_REDEF_TABLE 期间会获取短暂的排他锁——选择业务低峰期
- COMMIT_TIMESTAMP 列、IDENTITY 列、虚拟列各有特殊处理规则

## 关键发现

### 1. "在线"是一道光谱，不是是/否

所有"在线表重组"在某个瞬间都会获取一次短暂的排他锁——这个时刻通常是切换段头指针、重命名表、原子替换 relfilenode 的那 100ms 到几秒。真正的差异在于：**这个排他锁之前的几小时/几天里，DML 是否被阻塞**。

```
真正的"在线" = 切换瞬间的短锁 + 中间长时间的并发友好
```

不同方案的"切换锁"持续时间对比：

| 方案 | 切换锁时长 | 备注 |
|------|-----------|------|
| Oracle MOVE ONLINE | < 1 秒 | 段头指针切换 |
| SQL Server REBUILD ONLINE | < 1 秒 | 元数据 SCH-M |
| MySQL Online DDL | 短（应用 Online DDL Log） | Log 越大越长 |
| pg_repack | < 几秒 | RENAME |
| gh-ost | 可控（cut-over phase） | 可挑业务低峰 |
| Oracle DBMS_REDEFINITION | < 1 秒 | RENAME |
| DB2 ADMIN_MOVE_TABLE | < 1 秒 | SWAP 阶段 |
| PostgreSQL CLUSTER | 整个过程 | 全程阻塞 |
| PostgreSQL VACUUM FULL | 整个过程 | 全程阻塞 |

### 2. 重组方案的两条主流技术路径

业界所有真正的在线重组方案都走以下两条路径之一：

**路径 A：触发器 + 影子表**（pg_repack、pt-osc、DB2 ADMIN_MOVE_TABLE、Oracle DBMS_REDEFINITION 早期）
- 优点：实现简单、跨版本兼容性好
- 缺点：原表 DML 性能下降 10-30%，不适合极高 TPS 场景

**路径 B：日志解析 + 流式追平**（gh-ost、pg_squeeze、Oracle MOVE ONLINE 内置 mlog、SQL Server row versioning）
- 优点：对原表 DML 几乎无影响
- 缺点：实现复杂、依赖 binlog/WAL/mview log 等存储引擎特性

业界趋势：**路径 B 正在成为主流**。GitHub 投入资源开发 gh-ost、Cybertec 推 pg_squeeze、Oracle 把 MOVE ONLINE 做成内核功能而非工具——都说明日志解析方案在大规模场景下更具优势。

### 3. PostgreSQL 是主流引擎中"内核能力最弱"的一个

PostgreSQL 内核没有真正的在线表重组。`CLUSTER` 和 `VACUUM FULL` 都是 offline 操作。这是 PG 在大规模生产环境中最大的运维痛点之一。

主流缓解方案：
- 使用 pg_repack 或 pg_squeeze 扩展
- 应用层做"双写 + 切换"
- 接受 routine 的 VACUUM（autovacuum）做不完全的空间回收

PostgreSQL 18（2025）虽然在 VACUUM 路径上做了大量优化（如多级 visibility map、并行 VACUUM 加强），但仍未将 pg_repack 类功能纳入内核。这是 PostgreSQL 社区一个长期争议——"扩展能做的事不进核心"的哲学，与运维实际诉求之间的张力。

### 4. 云原生与分布式 SQL 让"重组"成为不存在的问题

Snowflake、BigQuery、Databricks、Spanner、CockroachDB、TiDB 等系统的运维者**几乎不需要思考表重组**——所有的物理整理都由后台服务自动进行。

这是过去 10 年云数据库相对于自管理 OLTP 数据库最大的运维优势之一。代价是：
- 用户失去对重组时机的控制
- 资源占用不可预测
- 极端场景下（如紧急回收磁盘）没有显式触发入口

### 5. RESUMABLE 是为大表运维量身定做的能力

SQL Server 2017 SP1 引入的 RESUMABLE 是同类功能中最完整的实现：可手动 PAUSE、RESUME、ABORT，可设置 MAX_DURATION 自动暂停，故障重启后从断点继续。

这一能力对 TB 级表的运维价值巨大：
- 可以在每天的维护窗口内"分次"完成同一个 REBUILD
- 故障后不必重头开始
- 业务突发负载时主动 PAUSE，避免互相影响

Oracle 的 RESUMABLE 是另一种语义（资源不足时自动等待），不能与 SQL Server 直接类比。其他引擎大多缺乏类似机制——这是 SQL Server 在企业级运维上的护城河之一。

### 6. gh-ost 取代了 pt-osc 成为 MySQL 生态的事实标准

2016 年 GitHub 发布 gh-ost 之后，MySQL 在线 schema 变更的实践明显从 pt-osc 转向 gh-ost。原因有三：
1. gh-ost 不在原表上挂触发器，对原表性能影响可忽略
2. gh-ost 通过 binlog 解析获取增量，主从延迟控制更精准
3. gh-ost 提供 socket 接口，可以在运行时暂停、调整速率、提前切换

但 pt-osc 并未消亡——在简单环境、CI/CD 场景、本地开发环境中，pt-osc 的"一条命令搞定"仍然是更轻量的选择。Vitess 内置的 OnlineDDL 引擎吸收了 gh-ost 的核心设计，成为分布式 MySQL 集群的新标准。

### 7. 列存与行存的"重组"概念差异巨大

行存系统（Oracle、SQL Server、PostgreSQL、MySQL）的重组聚焦于：
- 回收死元组
- 按聚簇键重排
- 调整填充率
- 修复行迁移（row migration）

列存系统（ClickHouse、Vertica、Redshift、Doris、StarRocks、Snowflake、BigQuery）的"重组"聚焦于：
- 合并小 part 为大 part
- 按 sort key / cluster by 重排
- 提升压缩率
- 删除被覆盖的旧 part

两者面临的物理挑战完全不同。OLAP 引擎的合并是"批读 + 重写"，OLTP 引擎的重组是"在线分批迁移"。两个领域逐渐积累了**几乎不重叠的两套术语和工具**。

### 8. 分区策略变更几乎只能靠 in-memory swap 类工具

很多生产事故源于一个"无害"的需求：把一张运行了 5 年的非分区表改成范围分区。这种变更**任何引擎的内核都不直接支持**——必须借助 swap-table 类机制：

- Oracle：`DBMS_REDEFINITION` 是唯一一线方案
- DB2：`ADMIN_MOVE_TABLE` 支持指定新分区定义
- SQL Server：手动建分区表 + 切换分区
- MySQL：通过 gh-ost 或 pt-osc 可重新分区
- PostgreSQL：`pg_repack` 仅按索引重组，无法改分区策略；需要应用层 swap-table

这意味着分区策略一旦定型，事后调整代价非常高。建议设计阶段就把分区策略当作一等关注点。

## 对引擎开发者的实现建议

### 1. 在线重组的最小可行架构

任何在线表重组方案都至少要解决三个问题：**初始数据复制 + 增量捕获 + 原子切换**。最小可行实现：

```
phase 1: prepare
    创建 shadow_table（与原表 schema 兼容，可附加变更）
    启动增量捕获机制（触发器/binlog 订阅/mview log）

phase 2: copy
    SELECT FROM source ORDER BY pk
    分块批量 INSERT INTO shadow_table
    控制每批的事务大小、限速、监控源表负载

phase 3: replay
    重放 phase 1 启动后到当前的所有增量
    保持增量捕获持续运行

phase 4: cutover
    短暂获取 source 上的排他锁
    最后一次重放，确保严格追平
    重命名 source → tmp，shadow → source
    释放锁

phase 5: cleanup
    删除 tmp（旧表）
    停止增量捕获
    收集统计信息
```

### 2. 增量捕获的工程权衡

**触发器路径**：
- 对原表插入额外开销 10-30%
- 实现简单，与存储引擎几乎解耦
- 适合中等规模、对原表性能不敏感的场景

**日志解析路径**：
- 几乎无性能开销
- 实现复杂（需理解 binlog/WAL/redo 格式）
- 适合大规模、高 TPS 场景

实现建议：**优先选择日志解析**。如果引擎已经有逻辑复制（PG logical decoding、MySQL binlog、Oracle LogMiner），就直接复用而非新写触发器框架。

### 3. 切换瞬间的原子性

切换是整个流程的关键瞬间。常见错误：
- 在切换前没有最后一次"严格追平"，导致数据丢失
- 切换锁过粗（锁了整个表空间），对邻接表造成影响
- 没有 rollback 机制，切换失败后陷入"半组装"状态

正确做法：
- 切换锁只锁 source 表的元数据（不锁数据页）
- 在锁内完成最后一次增量回放（在锁外通常做不到完全追平）
- 提供 ABORT 入口，使切换失败可回滚到原状态

### 4. 资源限速与维护窗口控制

大表重组通常运行数小时到数天，必须支持：
- **限速**：`max_lag`（主从延迟）、`max_load`（max running queries）、`max_io`（每秒 IO 上限）
- **维护窗口**：`max_duration`（达到上限自动暂停）、`active_hours`（仅在某时段运行）
- **优雅暂停**：`PAUSE/RESUME` 信号、socket 命令、SQL 语句

```
推荐的限速策略（参考 gh-ost）:
  if avg_replication_lag > 1.5s -> 暂停 5s 后重试
  if Threads_running > critical_threshold -> 暂停
  if hour in maintenance_blackout -> 暂停
  else: copy chunk + sleep(adaptive_delay)
```

### 5. 可观测性的最小要求

在线重组必须提供给 DBA 的可观测能力：
- **进度**：已复制的行数 / 总行数 / 预计完成时间
- **延迟**：增量捕获和回放的滞后量
- **资源占用**：CPU、IO、临时空间使用量
- **当前阶段**：copy / replay / cutover / cleanup
- **错误**：每一步骤的成功/失败状态

实现建议：通过专用系统视图暴露状态，例如 PG 的 `pg_stat_progress_cluster`、SQL Server 的 `sys.index_resumable_operations`、Oracle 的 `V$ONLINE_REDEF`。

### 6. 测试矩阵

任何在线重组实现的测试矩阵至少包括：
- **空表 / 极小表 / 极大表**
- **无 PK / 单列 PK / 复合 PK / UUID PK**
- **无索引 / 多索引 / 包含表达式索引 / 部分索引**
- **无外键 / 自引用外键 / 跨表外键**
- **无触发器 / 多触发器 / 嵌套触发器**
- **空 LOB / 大 LOB / 多 LOB**
- **并发 INSERT / UPDATE / DELETE / SELECT 各 1k QPS**
- **故障注入：源端崩溃 / 目标端崩溃 / 网络分区 / 磁盘满**

### 7. 与其他维护操作的协调

在线重组与其他后台任务可能冲突：
- **VACUUM/GC**：重组期间 VACUUM 可能扫描影子表，浪费资源
- **统计信息收集**：重组完成后必须主动收集，否则优化器使用旧统计
- **备份**：重组期间增量捕获的临时表是否纳入备份
- **复制**：跨集群复制（streaming replication / GTID）能否处理重组的元数据切换

实现建议：在重组的元数据中标记为"维护中"，让其他后台任务避让；切换完成后主动触发统计收集。

## 总结对比矩阵

### 在线重组能力总览

| 引擎 | 内核 ONLINE | 内核 RESUMABLE | 主流外部工具 | 自动维护 |
|------|------------|---------------|-------------|---------|
| Oracle | MOVE ONLINE (12cR2+) | RESUMABLE（资源） | DBMS_REDEFINITION | 部分（Auto-Tune） |
| SQL Server | REBUILD ONLINE (2005+) | RESUMABLE (2017 SP1+) | -- | 部分（Auto-Tune） |
| PostgreSQL | -- | -- | pg_repack / pg_squeeze | 仅 autovacuum |
| MySQL InnoDB | INPLACE (5.6+) | -- | gh-ost / pt-osc / lhm | 否 |
| MariaDB | INPLACE (10.0+) | -- | gh-ost / pt-osc | 否 |
| DB2 | INPLACE / ADMIN_MOVE_TABLE | 阶段性 | -- | 否 |
| Snowflake | 完全自动 | -- | -- | 完全自动 |
| BigQuery | 完全自动 | -- | -- | 完全自动 |
| Databricks | OPTIMIZE | -- | -- | Predictive |
| ClickHouse | OPTIMIZE FINAL | -- | -- | merge pool |
| CockroachDB | -- | -- | -- | LSM compaction |
| TiDB | -- | -- | -- | LSM compaction |
| OceanBase | REORGANIZE ONLINE | -- | -- | 自动合并 |
| YugabyteDB | -- | -- | -- | DocDB compaction |
| TimescaleDB | compress_chunk | -- | -- | 调度策略 |
| Redshift | VACUUM FULL（弱阻塞） | -- | -- | 部分 |
| Vertica | MERGE_PARTITIONS | -- | -- | TM 后台 |
| SAP HANA | RECLAIM DATA SPACE | -- | -- | 自动合并 |
| SingleStore | OPTIMIZE | -- | -- | 后台 |
| Spanner | -- | -- | -- | 完全自动 |
| Vitess | OnlineDDL（vreplication） | 是 | gh-ost | 否 |

### 引擎选型建议

| 场景 | 推荐方案 | 原因 |
|------|---------|------|
| Oracle 大表迁移到新表空间 + 改压缩 | `ALTER TABLE ... MOVE ONLINE` | 一条命令、内核级、12cR2+ 即支持 |
| Oracle 改分区策略 / 改列类型 | `DBMS_REDEFINITION` | 唯一支持 schema 变更的在线方案 |
| SQL Server TB 级索引重建 | `REBUILD WITH (ONLINE=ON, RESUMABLE=ON)` | 可暂停、跨维护窗口 |
| PostgreSQL 高 TPS 表的清理 | `pg_squeeze` | 逻辑解码、无触发器开销 |
| PostgreSQL 通用场景重组 | `pg_repack` | 成熟、文档全、社区活跃 |
| MySQL 大规模生产环境 | `gh-ost` | binlog 模式、无触发器、可暂停 |
| MySQL CI/CD / 简单环境 | `pt-online-schema-change` | 一条命令、配置简单 |
| MySQL Vitess 集群 | OnlineDDL（vreplication） | 内置、跨分片协调 |
| 分布式 SQL（Cockroach/TiDB/Spanner） | 不需要做重组 | 后台 LSM 自动 compaction |
| 列存数据仓库 | 引擎自动 + 偶尔 OPTIMIZE | 不暴露表级重组接口 |
| TimescaleDB 时序表 | 压缩策略 + compress_chunk | 利用列存压缩 |

## 参考资料

- Oracle: [ALTER TABLE ... MOVE ONLINE](https://docs.oracle.com/en/database/oracle/oracle-database/19/sqlrf/ALTER-TABLE.html)
- Oracle: [DBMS_REDEFINITION](https://docs.oracle.com/en/database/oracle/oracle-database/19/arpls/DBMS_REDEFINITION.html)
- SQL Server: [ALTER TABLE](https://learn.microsoft.com/en-us/sql/t-sql/statements/alter-table-transact-sql)
- SQL Server: [Resumable index operations](https://learn.microsoft.com/en-us/sql/relational-databases/indexes/guidelines-for-online-index-operations)
- PostgreSQL: [CLUSTER](https://www.postgresql.org/docs/current/sql-cluster.html)
- PostgreSQL: [VACUUM FULL](https://www.postgresql.org/docs/current/sql-vacuum.html)
- pg_repack: [Documentation](https://reorg.github.io/pg_repack/)
- pg_squeeze: [Documentation](https://github.com/cybertec-postgresql/pg_squeeze)
- MySQL: [Online DDL Operations](https://dev.mysql.com/doc/refman/8.0/en/innodb-online-ddl-operations.html)
- MySQL: [OPTIMIZE TABLE](https://dev.mysql.com/doc/refman/8.0/en/optimize-table.html)
- gh-ost: [GitHub Online Schema Change](https://github.com/github/gh-ost)
- pt-online-schema-change: [Percona Toolkit](https://docs.percona.com/percona-toolkit/pt-online-schema-change.html)
- DB2: [ADMIN_MOVE_TABLE procedure](https://www.ibm.com/docs/en/db2/11.5?topic=mp-admin-move-table-procedure-move-tables-online)
- DB2: [REORG TABLE](https://www.ibm.com/docs/en/db2/11.5?topic=commands-reorg-tables)
- ClickHouse: [OPTIMIZE TABLE](https://clickhouse.com/docs/en/sql-reference/statements/optimize)
- Snowflake: [Automatic Clustering](https://docs.snowflake.com/en/user-guide/tables-auto-reclustering)
- Databricks: [OPTIMIZE](https://docs.databricks.com/en/sql/language-manual/delta-optimize.html)
- TimescaleDB: [Compression](https://docs.timescale.com/use-timescale/latest/compression/)
- Vitess: [OnlineDDL](https://vitess.io/docs/user-guides/schema-changes/managed-online-schema-changes/)
- Shlomi Noach: [gh-ost: triggerless online schema migrations](https://github.blog/engineering/gh-ost-github-online-migration-tool-for-mysql/) (2016)
- Percona: [pt-online-schema-change tutorial](https://www.percona.com/blog/percona-online-schema-change/)
- NTT: [pg_repack: powerful online table reorganization](https://reorg.github.io/pg_repack/)
