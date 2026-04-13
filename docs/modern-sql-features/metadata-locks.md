# 元数据锁 (Metadata Locks)

凌晨 3 点，一个看似无害的 `ALTER TABLE ADD INDEX` 让整个 OLTP 集群的 P99 延迟从 5 毫秒飙升到 30 秒——罪魁祸首不是磁盘 I/O，不是 CPU，也不是行锁，而是元数据锁（Metadata Lock，MDL）。元数据锁是 DDL 与 DML 之间隐形的同步原语，它不出现在大多数监控面板上，却能在毫秒之内让一个高可用数据库的尾延迟（tail latency）彻底崩溃。理解 MDL，是任何严肃的数据库使用者、DBA 和引擎开发者从"会用 SQL"走向"理解数据库内部"的分水岭。

本文系统对比 45+ 主流数据库的元数据锁机制：从 MySQL 引入 MDL 的历史动机，到 PostgreSQL 的 8 级锁阶（lock level）模型，从 Oracle 的 library cache 双重保护，到 SQL Server 的 Sch-S/Sch-M 二元设计，再到 TiDB / CockroachDB / Snowflake 这些云原生数据库如何用 lease、版本号和 time-travel 重新定义"无锁 DDL"。

## 为什么需要元数据锁：DDL 与 DML 的并发难题

考虑下面这个最简单的并发场景：

```sql
-- 会话 A: 在事务中查询表
BEGIN;
SELECT * FROM orders WHERE id = 1;  -- 用到 schema {id, user_id, amount}
-- ... 还没 COMMIT，等待应用代码处理 ...

-- 会话 B: DBA 修改表结构
ALTER TABLE orders DROP COLUMN amount;

-- 会话 A 继续:
SELECT amount FROM orders WHERE id = 2;  -- 列不存在了！
COMMIT;
```

如果没有任何同步机制，会话 A 在同一事务内看到的 schema 会突变，事务的隔离性被彻底破坏。更严重的是：执行计划是基于"开始时刻"的 schema 编译的，运行时如果列消失了，引擎要么崩溃，要么必须做昂贵的运行时重检查。

**元数据锁的本质**：在事务持有对一个表的"使用权"期间，禁止任何会改变该表 schema 的 DDL 完成。它是一种"读者-写者锁"，但锁的对象不是数据行，而是**表的元数据本身**。

| 概念 | 行/页/表锁 | 元数据锁 (MDL) |
|------|-----------|---------------|
| 保护对象 | 数据行 / 数据页 / 整张表的数据 | 表的 schema、列定义、索引定义 |
| 持有者 | DML 语句（INSERT/UPDATE/DELETE/SELECT） | 事务（直到 COMMIT/ROLLBACK） |
| 阻塞对象 | 其他 DML 的同一行/页 | DDL（CREATE/ALTER/DROP/TRUNCATE） |
| 持续时间 | 语句级（READ COMMITTED）或事务级（REPEATABLE READ） | 事务级 |
| 监控视图 | InnoDB lock monitor / pg_locks | performance_schema.metadata_locks / pg_locks |
| 典型故障 | 死锁、行锁等待 | DDL 阻塞导致 DML 全停 |

行锁与 MDL 的关系详见 [`locks-deadlocks.md`](./locks-deadlocks.md)；DDL 自身的实现（copy / inplace / instant）详见 [`online-ddl-implementation.md`](./online-ddl-implementation.md)。本文专注于"DDL 与 DML 之间"的元数据同步层。

## 内部锁机制：为什么 MDL 不在 SQL 标准里

SQL:2016 标准（ISO/IEC 9075）从未定义元数据锁。原因很简单：标准只约束**可观察的语义**，而 MDL 是**实现细节**。标准只要求：

1. 事务内观察到的 schema 必须一致（隔离性）
2. DDL 提交后，新事务必须看到新 schema（持久性）
3. 并发的 DDL 与 DML 不能产生未定义行为

不同数据库以完全不同的方式满足这些要求：

- **传统行存 OLTP（MySQL/PostgreSQL/Oracle/DB2/SQL Server）**：用真正的锁机制（read/write lock）
- **多版本目录（Snowflake/BigQuery）**：DDL 创建 schema 的新版本，老事务继续读老版本，根本不需要锁
- **租约机制（TiDB/CockroachDB/F1）**：通过有限期的 schema 租约，租约到期前不允许 DDL 推进
- **快照隔离的 catalog（DuckDB/Materialize）**：catalog 本身是 MVCC 对象

理解这些根本性的设计分歧，是看懂下面 45+ 数据库支持矩阵的钥匙。

## 支持矩阵

### 元数据锁存在性与基本能力

| 数据库 | 存在 MDL 概念 | 锁名称 | 实现机制 | 引入版本 |
|--------|--------------|--------|----------|---------|
| PostgreSQL | 是 | AccessShareLock / AccessExclusiveLock | 8 级锁阶 | 自始 |
| MySQL | 是 | MDL_SHARED_* / MDL_EXCLUSIVE | 显式 MDL 子系统 | 5.5 (2010) |
| MariaDB | 是 | 同 MySQL | 同 MySQL（fork） | 5.5+ |
| SQLite | 否（单写者） | -- | 数据库级写锁覆盖 | -- |
| Oracle | 是 | Library Cache Lock/Pin + DDL Lock | 库缓存双重锁 | 自始 |
| SQL Server | 是 | Sch-S / Sch-M | 模式锁 | 自始 |
| DB2 | 是 | Object/Table Lock + Plan Lock | 对象锁 | 自始 |
| Snowflake | 否（多版本 catalog） | -- | Time-travel 版本化 | GA |
| BigQuery | 否（多版本 catalog） | -- | 元数据快照 | GA |
| Redshift | 是 | AccessExclusiveLock | PG 衍生 | GA |
| DuckDB | 弱（catalog MVCC） | catalog version | 快照隔离 | 0.7+ |
| ClickHouse | 是 | TableExclusiveLock | 表级 RWLock | 自始 |
| Trino | 否（无事务 DDL） | -- | Connector 级 | -- |
| Presto | 否 | -- | 同 Trino | -- |
| Spark SQL | 否（catalog 由 metastore 管理） | -- | Hive metastore 锁 | -- |
| Hive | 是（可选） | Shared / Exclusive | ZooKeeper / DbTxnManager | 0.13+ |
| Flink SQL | 否 | -- | Catalog plugin | -- |
| Databricks | 是（Delta） | Optimistic concurrency | Delta log 版本 | GA |
| Teradata | 是 | Access / Read / Write / Exclusive | 4 级锁阶 | 自始 |
| Greenplum | 是 | 同 PostgreSQL | PG 衍生 | 自始 |
| CockroachDB | 是 | Schema lease | 租约 + 2 版本不变式 | 1.0+ |
| TiDB | 是 | Schema lease (etcd) | 租约 + 在线 schema change | 1.0+ |
| OceanBase | 是 | DDL Lock | 类 MySQL MDL | 自始 |
| YugabyteDB | 是 | DocDB schema version | 类 PG + Raft | 2.0+ |
| SingleStore | 是 | Metadata lock | 类 MySQL | 自始 |
| Vertica | 是 | O/I/S/SI/X 等 7 级锁 | 多级锁阶 | 自始 |
| Impala | 是 | Catalog lock | Catalogd 全局锁 | 自始 |
| StarRocks | 是 | Database/Table lock | 数据库级 RWLock | 自始 |
| Doris | 是 | Database lock | 数据库级 RWLock | 自始 |
| MonetDB | 弱 | -- | 单写者 | -- |
| CrateDB | 是 | Cluster state lock | ES cluster state | 自始 |
| TimescaleDB | 是 | 同 PostgreSQL | PG 扩展 | 自始 |
| QuestDB | 是 | Writer lock | 单写者锁 | 自始 |
| Exasol | 是 | 对象锁 | 内置 | 自始 |
| SAP HANA | 是 | Object lock | 内置 | 自始 |
| Informix | 是 | Exclusive table lock | 自始 | 自始 |
| Firebird | 是 | Metadata lock | 自始 | 自始 |
| H2 | 是 | Table lock | 表级 | 自始 |
| HSQLDB | 是 | Schema lock | 自始 | 自始 |
| Derby | 是 | Container lock | 自始 | 自始 |
| Amazon Athena | 否 | -- | Glue catalog | -- |
| Azure Synapse | 是 | Sch-S / Sch-M | 同 SQL Server | GA |
| Google Spanner | 是 | Schema version | 多版本 schema | GA |
| Materialize | 弱 | catalog version | timestamp-versioned | GA |
| RisingWave | 弱 | catalog version | meta service | GA |
| InfluxDB (SQL) | 否 | -- | TSI 索引 | -- |
| DatabendDB | 是 | Table version | 元数据版本 | GA |
| Yellowbrick | 是 | 同 PostgreSQL | PG 衍生 | GA |
| Firebolt | 否 | -- | 多版本 catalog | GA |

> 统计：约 36 个引擎实现了真正的 MDL（无论叫什么名字）；约 8 个引擎用版本化 catalog 完全规避 MDL；SQLite 和单写者引擎不需要 MDL。

### MDL 读 / 写锁级别

DDL 与 DML 的核心冲突可以归结为：DML 持读锁，DDL 持写锁，二者互斥。但不同引擎的"读锁"细分粒度不同。

| 数据库 | 读锁名称 | 写锁名称 | 中间级别 | 写写互斥 |
|--------|---------|----------|---------|---------|
| PostgreSQL | AccessShareLock | AccessExclusiveLock | RowShare/RowExclusive/Share/ShareRowExclusive/Exclusive/ShareUpdateExclusive | 是 |
| MySQL | MDL_SHARED / MDL_SHARED_READ / MDL_SHARED_WRITE | MDL_EXCLUSIVE | MDL_SHARED_UPGRADABLE / MDL_SHARED_NO_WRITE / MDL_SHARED_NO_READ_WRITE | 是 |
| MariaDB | 同 MySQL | 同 MySQL | 同 MySQL | 是 |
| Oracle | Lib cache lock (S) + Pin (S) | Lib cache lock (X) + Pin (X) | NULL/SS/SX/S/SSX/X | 是 |
| SQL Server | Sch-S | Sch-M | -- | 是 |
| DB2 | IS / IX | X | S / SIX / U | 是 |
| TiDB | Schema lease (read) | Schema change (write) | -- | 串行 |
| CockroachDB | Lease (read) | Schema change job | -- | 串行 |
| Vertica | S | X | I / IS / SI / IX | 是 |
| Snowflake | -- | -- | -- | 串行 |
| BigQuery | -- | -- | -- | 串行 |
| ClickHouse | RWLock 读 | RWLock 写 | -- | 是 |
| Hive (DbTxnManager) | SHARED_READ | EXCL_WRITE | SHARED_WRITE | 是 |

### Intention MDL（意向元数据锁）

意向锁（intention lock）允许在更高层级（database/schema）声明"我即将在某个表上加锁"，避免遍历所有子对象。

| 数据库 | 数据库级意向锁 | Schema 级意向锁 | 表级意向锁 | 备注 |
|--------|--------------|---------------|----------|------|
| PostgreSQL | -- | -- | RowShare/RowExclusive | 仅表级有意向 |
| MySQL | MDL_INTENTION_EXCLUSIVE | MDL_INTENTION_EXCLUSIVE | IS / IX | 全栈意向锁 |
| MariaDB | 同 MySQL | 同 MySQL | 同 MySQL | -- |
| Oracle | -- | -- | RS / RX / SRX | 行共享/行排他/共享行排他 |
| SQL Server | IS / IX | IS / IX | IS / IX | 全 6 层 hierarchy |
| DB2 | IS / IX | IS / IX | IS / IX / SIX | -- |
| Vertica | -- | -- | I / IS / IX | 仅表级 |
| 其他 | 大多无 | -- | -- | -- |

### DDL 是否阻塞长事务 SELECT

这是 MDL 引发线上事故最典型的场景。一个长跑 SELECT 持有 MDL 读锁，DDL 等待写锁，新进的 SELECT 因为不能跳过队列中的等待者，全部被阻塞。

| 数据库 | DDL 阻塞 SELECT | DDL 排队优先 | 等待队列 FIFO | 备注 |
|--------|----------------|------------|--------------|------|
| PostgreSQL | 是（除非用 lock_timeout） | 是 | 是 | 8.4+ 严格 FIFO |
| MySQL | 是 | 是 | 是 | 经典 MDL 雪崩场景 |
| MariaDB | 是 | 是 | 是 | 同 MySQL |
| Oracle | 仅瞬时（DDL lock 短暂获取） | -- | -- | DDL 不持久阻塞 SELECT |
| SQL Server | 是（Sch-M 阻塞 Sch-S） | 是 | 是 | 锁分区可优化 |
| DB2 | 是 | 是 | 是 | -- |
| Snowflake | 否（time-travel 版本） | -- | -- | 老查询读老版本 |
| BigQuery | 否 | -- | -- | catalog 快照 |
| Redshift | 是 | 是 | 是 | 同 PG |
| DuckDB | 是（catalog 排他） | -- | -- | 单进程 |
| ClickHouse | 部分（依赖 RWLock） | -- | -- | -- |
| TiDB | 否（lease + 2 版本兼容） | -- | -- | 老 SELECT 用旧 schema |
| CockroachDB | 否（2 版本不变式） | -- | -- | 类 F1 在线 schema change |
| OceanBase | 是 | 是 | 是 | 类 MySQL |
| YugabyteDB | 否 | -- | -- | 类 CRDB |
| Spanner | 否 | -- | -- | 多版本 schema |
| Vertica | 是 | -- | -- | -- |
| Impala | 是 | -- | -- | catalogd 单点 |
| StarRocks | 是 | -- | -- | 数据库级锁 |
| Doris | 是 | -- | -- | 同 StarRocks |
| Hive (DbTxnManager) | 是 | -- | -- | 依赖 metastore |
| Databricks Delta | 否 | -- | -- | 乐观并发 |

### Lazy DDL / Instant DDL 支持

如果 DDL 可以"瞬时"完成（不需要锁定全表，只改 metadata），MDL 持有时间从分钟级降到毫秒级。

| 数据库 | Instant ADD COLUMN | Instant DROP COLUMN | Instant RENAME | Instant 修改 DEFAULT | 版本 |
|--------|-------------------|---------------------|---------------|---------------------|------|
| MySQL | 是 | 是 | 是 | 是 | 8.0.12+ / 8.0.29+ |
| MariaDB | 是 | 是 | 是 | 是 | 10.3+ / 10.4+ |
| PostgreSQL | 是（NULL 默认） | 是 | 是 | 是（不重写） | 11+ / 11+ |
| Oracle | 是（11g 起 fast add） | 是 | 是 | 是 | 11g+ |
| SQL Server | 是（NULL 默认） | -- | 是 | 是 | 2012+ |
| DB2 | 是 | -- | 是 | 是 | 9.7+ |
| TiDB | 是 | 是 | 是 | 是 | 6.2+ |
| OceanBase | 是 | 是 | 是 | 是 | 4.0+ |
| CockroachDB | 是 | 是 | 是 | 是 | 19.1+ |
| Snowflake | 是（全部） | 是 | 是 | 是 | GA |
| BigQuery | 是 | 是 | 是 | 是 | GA |
| Redshift | 是 | 是（部分） | 是 | 是 | GA |
| Spanner | 是 | 是 | 是 | 是 | GA |
| ClickHouse | 是 | 是 | 是 | 是 | -- |
| Greenplum | 是 | 是 | 是 | 是 | 7.0+ |

### Lock timeout 配置

| 数据库 | 参数名 | 默认值 | 单位 | 范围 |
|--------|-------|--------|------|------|
| PostgreSQL | `lock_timeout` | 0 (无限) | 毫秒 | 会话级 |
| PostgreSQL | `statement_timeout` | 0 | 毫秒 | 会话级 |
| MySQL | `lock_wait_timeout` | 31536000 (1 年) | 秒 | 会话级 |
| MySQL | `innodb_lock_wait_timeout` | 50 | 秒 | 仅行锁 |
| MariaDB | `lock_wait_timeout` | 31536000 (1 年，继承自 MySQL) | 秒 | 会话级 |
| Oracle | `DDL_LOCK_TIMEOUT` | 0 (NOWAIT) | 秒 | 会话级 |
| SQL Server | `LOCK_TIMEOUT` | -1 (无限) | 毫秒 | SET LOCK_TIMEOUT |
| DB2 | `LOCKTIMEOUT` | -1 | 秒 | DB cfg |
| TiDB | `tidb_lock_wait_timeout` | 1 | 秒 | -- |
| CockroachDB | `lock_timeout` | 0 | 毫秒 | 类 PG |
| Snowflake | `STATEMENT_TIMEOUT_IN_SECONDS` | 172800 | 秒 | -- |
| Greenplum | `lock_timeout` | 0 | 毫秒 | 类 PG |
| Redshift | `statement_timeout` | 0 | 毫秒 | -- |
| YugabyteDB | `lock_timeout` | 0 | 毫秒 | 类 PG |

### MDL 在系统视图中的可见性

| 数据库 | 系统视图 / 表 | 默认开启 | 关键字段 |
|--------|--------------|---------|---------|
| MySQL | `performance_schema.metadata_locks` | 否（5.7+ 需启用 instrument） | OBJECT_SCHEMA, OBJECT_NAME, LOCK_TYPE, LOCK_STATUS |
| MariaDB | `information_schema.METADATA_LOCK_INFO` | 否（需安装插件） | -- |
| PostgreSQL | `pg_locks` | 是 | locktype, mode, granted, pid |
| Oracle | `V$LOCK`, `DBA_DDL_LOCKS`, `V$LIBRARY_CACHE_LOCK` | 是 | TYPE='DL' 表示 DDL lock |
| SQL Server | `sys.dm_tran_locks` | 是 | request_mode IN ('Sch-S','Sch-M') |
| DB2 | `SYSIBMADM.SNAPLOCK`, `SYSIBMADM.LOCKS_HELD` | 是 | object_type = 'TABLE' |
| TiDB | `INFORMATION_SCHEMA.TIDB_TRX`, `MDL_VIEW` | 是 | -- |
| CockroachDB | `crdb_internal.cluster_locks` | 是 | -- |
| Snowflake | `SHOW LOCKS` / `INFORMATION_SCHEMA.QUERY_HISTORY` | -- | -- |
| ClickHouse | `system.metrics` (RWLockActiveReaders) | 是 | -- |
| Greenplum | `pg_locks` | 是 | -- |
| OceanBase | `oceanbase.GV$OB_LOCKS` | 是 | -- |
| YugabyteDB | `pg_locks` | 是 | -- |
| Vertica | `V_MONITOR.LOCKS` | 是 | -- |

### DDL 等待队列

队列模型决定了"是否可以让小读跳过排队中的 DDL"——这关乎线上 DDL 是否会触发雪崩。

| 数据库 | 队列模型 | DDL 让出 | 优先级支持 | 死锁检测 |
|--------|---------|---------|-----------|---------|
| PostgreSQL | 严格 FIFO | 否 | 否 | 是 |
| MySQL | 严格 FIFO | 否 | 否 | 是 |
| Oracle | 短时获取 + 重试 | 是（NOWAIT） | DDL_LOCK_TIMEOUT | 是 |
| SQL Server | FIFO + 锁分区 | 否 | LOCK_TIMEOUT | 是 |
| DB2 | FIFO | 否 | LOCKTIMEOUT | 是 |
| TiDB | 串行 schema change | 不阻塞 DML | -- | -- |
| CockroachDB | 串行 schema change job | 不阻塞 DML | -- | -- |
| Snowflake | 多版本无队列 | -- | -- | -- |
| ClickHouse | 表级 RWLock | -- | -- | -- |

### Schema 版本变更检测

每个事务/查询如何感知 schema 已经变更？

| 数据库 | 检测机制 | 粒度 | 老事务行为 |
|--------|---------|------|----------|
| MySQL | MDL 阻塞 | 表级 | 老事务持锁，DDL 等待 |
| PostgreSQL | AccessExclusiveLock 阻塞 | 表级 | 老事务持锁，DDL 等待 |
| Oracle | SCN 比对 + library cache invalidation | 对象级 | 老游标失效，下次解析重编译 |
| SQL Server | Sch-S/Sch-M | 表级 | 计划缓存失效 |
| TiDB | etcd 中 schema version 单调递增 | 全局 | 老事务用旧 schema 直到完成 |
| CockroachDB | Range descriptor + lease | 表级 | 2 版本不变式：新旧 schema 同时有效一段时间 |
| Snowflake | Time-travel 版本号 | 对象级 | 完全无影响 |
| BigQuery | 元数据快照 | 对象级 | 完全无影响 |
| Spanner | Schema 版本 + 长跑 schema change | 全局 | 老事务可能被 abort |
| Databricks Delta | _delta_log 版本号 | 表级 | 乐观并发可能 retry |
| YugabyteDB | DocDB schema version | 表级 | 类 PG |

## MySQL 元数据锁深入

### 历史背景

MySQL 5.5（2010 年 12 月）引入 MDL 之前，DDL 与 DML 的同步依靠 `LOCK_open`（一个全局 mutex）和 `THR_LOCK`（表级读写锁）。这种粗暴方案有两个致命缺陷：

1. **跨语句不持锁**：一个事务内的两个 SELECT 之间，可以插入一个 DROP TABLE，导致同一事务内"表突然消失"
2. **非事务性 DDL**：CREATE TRIGGER 在事务内可以与表的 DROP 交错

MySQL 5.5 引入显式的 MDL 子系统（`sql/mdl.cc`），第一次让锁的持续时间和事务对齐。

### MDL 锁类型详解

```
MDL_INTENTION_EXCLUSIVE  (IX)  -- 数据库级意向锁，DML 必持
MDL_SHARED               (S)   -- 表存在性检查
MDL_SHARED_HIGH_PRIO     (SH)  -- 仅元数据访问，不读数据
MDL_SHARED_READ          (SR)  -- 持有时可 SELECT
MDL_SHARED_WRITE         (SW)  -- 持有时可 INSERT/UPDATE/DELETE
MDL_SHARED_WRITE_LOW_PRIO (SWLP) -- 低优先级写
MDL_SHARED_UPGRADABLE    (SU)  -- ALTER 第一阶段，可升级
MDL_SHARED_NO_WRITE      (SNW) -- copy ALTER 阶段，允许读不允许写
MDL_SHARED_NO_READ_WRITE (SNRW)-- 重命名等阶段，禁读写
MDL_EXCLUSIVE            (X)   -- DDL 提交瞬间，禁一切
```

兼容性矩阵中一个关键观察：`SR`（SELECT 持有）与 `SU`（ALTER 持有）**兼容**。这意味着 ALTER TABLE 的大部分时间允许 SELECT 并发，只有最后一刻升级到 `X` 时才会真正阻塞。但在升级之前必须等待**所有持有 `SR` 的事务结束**——这就是著名的"长事务阻塞 DDL"问题。

更糟的是，DDL 在等待 `X` 锁时已经在队列中占位，**新进的 SR 请求会排在 DDL 之后**。结果是：一个长跑 SELECT → DDL 等待 → 新 SELECT 全部阻塞 → 整个表不可访问。这就是 MySQL MDL 雪崩。

### 启用 metadata_locks 视图

```sql
-- 5.7+ 默认未开启，需要先打开 instrument
UPDATE performance_schema.setup_instruments
SET ENABLED = 'YES', TIMED = 'YES'
WHERE NAME = 'wait/lock/metadata/sql/mdl';

-- 然后查看当前所有 MDL
SELECT
    OBJECT_TYPE,
    OBJECT_SCHEMA,
    OBJECT_NAME,
    LOCK_TYPE,
    LOCK_STATUS,
    OWNER_THREAD_ID,
    OWNER_EVENT_ID
FROM performance_schema.metadata_locks
WHERE OBJECT_SCHEMA NOT IN ('mysql', 'performance_schema', 'information_schema');
```

### 定位"是谁阻塞了我的 DDL"

```sql
-- 找到正在等待 MDL 的 DDL 线程
SELECT
    pl.id           AS waiting_thread,
    pl.user         AS waiting_user,
    pl.host         AS waiting_host,
    pl.time         AS wait_seconds,
    pl.info         AS waiting_query
FROM information_schema.processlist pl
WHERE pl.state = 'Waiting for table metadata lock';

-- 8.0+ 用 sys schema 查找阻塞链
SELECT * FROM sys.schema_table_lock_waits;

-- 关联 MDL 视图找到持锁者
SELECT
    waiting_thread,
    waiting_query,
    blocking_thread,
    blocking_query,
    wait_age_secs
FROM sys.innodb_lock_waits
UNION ALL
SELECT
    w.OWNER_THREAD_ID  AS waiting_thread,
    NULL,
    g.OWNER_THREAD_ID  AS blocking_thread,
    NULL,
    NULL
FROM performance_schema.metadata_locks w
JOIN performance_schema.metadata_locks g
  ON w.OBJECT_SCHEMA = g.OBJECT_SCHEMA
 AND w.OBJECT_NAME = g.OBJECT_NAME
 AND w.OBJECT_TYPE = g.OBJECT_TYPE
WHERE w.LOCK_STATUS = 'PENDING'
  AND g.LOCK_STATUS = 'GRANTED'
  AND w.OWNER_THREAD_ID <> g.OWNER_THREAD_ID;
```

### 经典故障复现

```sql
-- 会话 1: 长事务持有 SR
BEGIN;
SELECT * FROM orders LIMIT 1;
-- (不要 COMMIT，模拟程序卡住或忘记关闭)

-- 会话 2: DBA 提交 DDL
ALTER TABLE orders ADD INDEX idx_user(user_id);
-- 状态: Waiting for table metadata lock

-- 会话 3: 任意业务 SELECT
SELECT * FROM orders WHERE id = 1;
-- 状态: Waiting for table metadata lock  ← 雪崩开始！

-- 救火: 在会话 4 立即:
SHOW PROCESSLIST;  -- 找到会话 1 的 thread_id
KILL <session_1_thread_id>;
-- ALTER 立即获得 X 锁，会话 3 解除等待
```

### 防雪崩最佳实践

```sql
-- 1. 给 DDL 设置短超时，宁可失败也不阻塞业务
SET SESSION lock_wait_timeout = 5;  -- 5 秒
ALTER TABLE orders ADD INDEX idx_user(user_id);
-- 失败后由调度系统重试，避开高峰

-- 2. 使用 pt-online-schema-change / gh-ost 等工具
-- 它们的本质是用影子表 + 触发器避开长 MDL 持有

-- 3. 8.0+ 使用 INSTANT 算法，MDL 持有时间从分钟降到毫秒
ALTER TABLE orders ADD COLUMN tag VARCHAR(64), ALGORITHM=INSTANT;
```

## PostgreSQL 锁模式与 DDL 影响

### 8 级锁阶模型

PostgreSQL 是少有的把 8 个锁级别完整暴露给用户的数据库：

| 级别 | 名称 | 简称 | DML 持有 | DDL 持有 |
|------|------|------|---------|---------|
| 1 | ACCESS SHARE | AS | SELECT | -- |
| 2 | ROW SHARE | RS | SELECT FOR UPDATE/SHARE | -- |
| 3 | ROW EXCLUSIVE | RX | INSERT/UPDATE/DELETE | -- |
| 4 | SHARE UPDATE EXCLUSIVE | SUX | -- | VACUUM, ANALYZE, CREATE INDEX CONCURRENTLY, ALTER TABLE VALIDATE CONSTRAINT |
| 5 | SHARE | S | -- | CREATE INDEX (非 CONCURRENTLY) |
| 6 | SHARE ROW EXCLUSIVE | SRX | -- | CREATE TRIGGER, ALTER TABLE 部分形式 |
| 7 | EXCLUSIVE | X | -- | REFRESH MATERIALIZED VIEW CONCURRENTLY |
| 8 | ACCESS EXCLUSIVE | AX | -- | DROP TABLE, TRUNCATE, REINDEX, CLUSTER, VACUUM FULL, ALTER TABLE 大部分 |

兼容性的关键规则：

- **AS 与 AS 兼容**：两个普通 SELECT 不互斥
- **RX 与 RX 兼容**：两个 INSERT 不互斥
- **AX 与一切互斥**：DDL 提交瞬间冻结一切
- **SUX 与 SUX 互斥**：两个 VACUUM 不能并发，但与 DML 兼容（这就是 VACUUM 不阻塞业务的原因）

### 哪些 ALTER 是快的？

```sql
-- 快（不重写表，不需要长 AX 持有）:
ALTER TABLE t SET (fillfactor = 80);                        -- 仅元数据
ALTER TABLE t ALTER COLUMN c DROP NOT NULL;                  -- 仅元数据
ALTER TABLE t ADD COLUMN c int;                              -- PG 11+ 默认 NULL
ALTER TABLE t ADD COLUMN c int DEFAULT 42;                   -- PG 11+ 非易失常量默认值
ALTER TABLE t ALTER COLUMN c SET DEFAULT 0;                  -- 仅元数据
ALTER TABLE t DROP COLUMN c;                                 -- 仅标记，无回填
ALTER TABLE t RENAME COLUMN a TO b;                          -- 仅元数据
ALTER TABLE t ADD CONSTRAINT chk CHECK (c > 0) NOT VALID;    -- 仅声明，不验证

-- 慢（需要表重写或全表扫描）:
ALTER TABLE t ALTER COLUMN c TYPE bigint;                    -- 重写整表
ALTER TABLE t ALTER COLUMN c SET NOT NULL;                   -- 全表扫描验证
ALTER TABLE t ADD COLUMN c int DEFAULT random();             -- volatile 默认值，全表回填
ALTER TABLE t SET TABLESPACE ts2;                            -- 拷贝整表

-- 安全的两阶段模式:
ALTER TABLE t ADD COLUMN c int;                              -- 快，仅元数据
UPDATE t SET c = compute(c) WHERE ...;                       -- 业务低峰期分批回填
ALTER TABLE t ALTER COLUMN c SET NOT NULL;                   -- 仍然慢，需 AX
```

### 防止 DDL 雪崩的 lock_timeout 模式

```sql
-- 方案 1: 主动放弃，定时重试
SET lock_timeout = '2s';
ALTER TABLE orders ADD COLUMN tag text;
-- 若 2 秒内拿不到 AX，立即报错 ERROR: canceling statement due to lock timeout
-- 由外部重试，避免阻塞业务

-- 方案 2: 不可重入的 DDL，先用短超时反复尝试
DO $$
DECLARE
    attempts int := 0;
BEGIN
    LOOP
        BEGIN
            SET LOCAL lock_timeout = '500ms';
            ALTER TABLE orders ADD COLUMN tag text;
            EXIT;  -- 成功
        EXCEPTION WHEN lock_not_available THEN
            attempts := attempts + 1;
            IF attempts > 100 THEN
                RAISE;
            END IF;
            PERFORM pg_sleep(1);
        END;
    END LOOP;
END $$;

-- 方案 3: 用 CONCURRENTLY 替代
CREATE INDEX CONCURRENTLY idx_user ON orders(user_id);
-- 持有 SUX 而不是 S/AX，与 DML 完全兼容
-- 缺点：不能在事务内执行，失败后留下 INVALID 索引
```

### pg_locks 实战查询

```sql
-- 当前所有锁
SELECT
    locktype,
    relation::regclass AS table,
    mode,
    granted,
    pid,
    pg_blocking_pids(pid) AS blocked_by
FROM pg_locks
WHERE relation IS NOT NULL
ORDER BY relation, granted DESC;

-- 找到正在等待 AccessExclusiveLock 的 DDL 及阻塞它的查询
SELECT
    blocked.pid          AS blocked_pid,
    blocked.usename      AS blocked_user,
    blocked.query        AS blocked_query,
    blocking.pid         AS blocking_pid,
    blocking.usename     AS blocking_user,
    blocking.query       AS blocking_query,
    blocking.state       AS blocking_state,
    age(now(), blocking.query_start) AS blocking_duration
FROM pg_stat_activity blocked
JOIN pg_stat_activity blocking
  ON blocking.pid = ANY(pg_blocking_pids(blocked.pid))
WHERE blocked.wait_event_type = 'Lock';
```

## Oracle：库缓存锁与 DDL 锁的双重保护

Oracle 的元数据保护是所有数据库中最复杂的。它把"防止 schema 突变"和"防止编译后的 SQL 计划失效"分成两层：

### 三种相关锁

1. **Library Cache Lock**：保护对象在 library cache 中的句柄不被其他会话修改。两种模式：S（shared，解析时持有）和 X（exclusive，DDL 持有）
2. **Library Cache Pin**：保护对象在 library cache 中的"内容"（编译后的 PL/SQL、cursor）。同样 S/X
3. **DDL Lock**：执行 DDL 期间持有，确保 DDL 互斥

```sql
-- 查看 library cache lock
SELECT * FROM V$LIBRARY_CACHE_LOCK;

-- 查看 DDL lock
SELECT * FROM DBA_DDL_LOCKS WHERE OWNER = 'APP_USER';

-- DDL 等待行为
ALTER SESSION SET DDL_LOCK_TIMEOUT = 30;  -- 等 30 秒
ALTER TABLE orders ADD (tag VARCHAR2(64));
-- 默认 DDL_LOCK_TIMEOUT = 0，意味着 NOWAIT，立即失败
```

Oracle 的关键差异：**DDL 不长时间持锁阻塞 SELECT**。Oracle 的 DDL 在执行瞬间获取 X 锁，但通过游标失效（cursor invalidation）机制，让老游标在下次解析时自动重编译，而不是让查询挂起等待。代价是 library cache 中所有依赖该对象的游标都被失效，可能引发"硬解析风暴"。

## SQL Server：Sch-S 与 Sch-M 的二元世界

SQL Server 把 schema 锁极简化为二元：

- **Sch-S（Schema Stability）**：编译查询时持有，确保 schema 不变
- **Sch-M（Schema Modification）**：DDL 持有，与一切（包括 IS、Sch-S）互斥

```sql
-- 查看当前 schema 锁
SELECT
    request_session_id,
    resource_type,
    resource_associated_entity_id,
    request_mode,
    request_status
FROM sys.dm_tran_locks
WHERE request_mode IN ('Sch-S', 'Sch-M');

-- 设置短锁超时
SET LOCK_TIMEOUT 5000;  -- 5 秒
ALTER TABLE Orders ADD Tag NVARCHAR(64);
```

Sch-M 与"任何东西"都不兼容——这个规则简单粗暴，但易于推理。SQL Server 还有"锁分区"（lock partitioning）优化：当 CPU 数 ≥ 16 时，IS 锁会被分区到 16 个 hash bucket，减少高并发 SELECT 的锁竞争——但 Sch-M 依然要逐个 bucket 获取，所以 DDL 在大表上反而变慢。

## DB2：层次化对象锁

DB2 用统一的对象锁机制覆盖表、表空间、缓冲池：

```sql
-- 查看锁
SELECT TABSCHEMA, TABNAME, LOCK_OBJECT_TYPE, LOCK_MODE, LOCK_STATUS
FROM SYSIBMADM.LOCKS_HELD
WHERE LOCK_OBJECT_TYPE = 'TABLE';

-- 设置 DDL 锁等待
db2 UPDATE DB CFG USING LOCKTIMEOUT 30;
```

DB2 还有一个其他数据库少见的"plan lock"——存储过程编译后的计划本身需要锁保护，DDL 修改对象会让所有依赖的 plan 失效并重新编译。

## TiDB：基于租约的两阶段 schema change

TiDB 借鉴 Google F1 论文的"在线、异步 schema change"算法。核心思想是：**任何时刻最多允许两个相邻的 schema 版本同时存在**。

```
版本 N      → DELETE_ONLY → WRITE_ONLY → WRITE_REORG → PUBLIC (版本 N+1)
                ↑              ↑              ↑           ↑
                老 TiDB        允许写         回填数据    完成
                看不到         不能读
```

每个 TiDB 节点持有一个 **schema lease**（默认 45 秒）从 PD（基于 etcd）获取。租约到期时必须重新加载 schema，否则节点自我下线。这保证了：

1. DDL 推进到下一阶段前，必须等所有节点都加载到当前版本
2. DDL 不会阻塞 DML，老事务继续在旧版本上执行
3. 旧版本最长存活时间 = 1 个 lease

```sql
-- TiDB 配置
SET GLOBAL tidb_ddl_reorg_worker_cnt = 4;
SET GLOBAL tidb_ddl_reorg_batch_size = 1000;

-- 查看正在执行的 DDL
ADMIN SHOW DDL JOBS;
ADMIN SHOW DDL JOB QUERIES 100;

-- 从 6.3 起 TiDB 也引入了 MDL（默认开启）
SHOW VARIABLES LIKE 'tidb_enable_metadata_lock';
-- 这个 MDL 用于防止"老事务读到不兼容的新 schema"，与传统 MySQL MDL 语义不同
```

## CockroachDB：lease + 2 版本不变式

CockroachDB 也使用 lease 机制，但实现细节不同：

- 每个 schema 对象有一个 **descriptor**，包含版本号
- 节点向 leaseholder 申请 descriptor 的 lease（默认 5 分钟）
- DDL 推进到新版本时，必须等所有持有旧版本 lease 的节点 lease 到期或主动 release
- 同时最多 2 个版本有效——这是 F1 论文的"2-version invariant"

```sql
-- 查看 schema change job
SHOW JOBS;
SELECT * FROM crdb_internal.jobs WHERE job_type = 'SCHEMA CHANGE';

-- 查看锁
SELECT * FROM crdb_internal.cluster_locks;
```

## Snowflake：完全无 MDL 的 time-travel 设计

Snowflake 的 catalog 是完全多版本的。每个对象的每次修改都会创建新版本，老版本保留在 time-travel 窗口内（默认 1 天，企业版最多 90 天）。

```sql
-- DDL 永远不阻塞 DML
ALTER TABLE orders ADD COLUMN tag STRING;
-- 老查询继续读老版本

-- 查询历史版本
SELECT * FROM orders AT(OFFSET => -60*5);  -- 5 分钟前
SELECT * FROM orders BEFORE(STATEMENT => '01abc...');

-- DDL 之间仍然串行（避免 lost update）
-- 但与 DML 完全无锁竞争
```

Snowflake 不需要传统 MDL 的根本原因：**存储和元数据完全分离**，元数据是 FoundationDB 上的 KV，DDL 是元数据的 CAS 操作，DML 引用的元数据版本号被对象快照锁定。

## Vitess：OnlineDDL 与 gh-ost 集成

Vitess 是 MySQL 的水平分片代理，DDL 必须在所有 shard 上执行。直接执行 ALTER 会触发 N 个 MySQL MDL 雪崩。Vitess 的解决方案是 **OnlineDDL**：

```sql
-- Vitess 提交 OnlineDDL（默认用 vitess 内置的 VReplication）
ALTER WITH 'vitess' TABLE orders ADD COLUMN tag VARCHAR(64);

-- 或使用 gh-ost
ALTER WITH 'gh-ost' TABLE orders ADD COLUMN tag VARCHAR(64);

-- 或 pt-osc
ALTER WITH 'pt-osc' TABLE orders ADD COLUMN tag VARCHAR(64);

-- 监控
SHOW VITESS_MIGRATIONS;
```

本质上是**绕开** MySQL MDL：用影子表 + 二进制日志同步，最后一刻原子切换。MDL 只在切换瞬间持有数毫秒。

## DuckDB：catalog 的快照隔离

DuckDB 是单进程嵌入式数据库，没有传统的 MDL 子系统。它的 catalog 本身是 MVCC 对象：

```sql
-- 在事务中可以看到一致的 catalog
BEGIN;
CREATE TABLE t (id INT);
INSERT INTO t VALUES (1);
-- 其他连接看不到 t
COMMIT;
-- 现在所有连接都看到 t
```

DuckDB 的 catalog 修改与数据修改使用同一个 MVCC 框架。事务开始时拍摄 catalog 快照，事务期间所有 schema 查询都基于这个快照。提交时检测冲突——这是"乐观并发"而非"悲观锁"。

## ClickHouse：表级 RWLock 的简单方案

```sql
-- 查看正在等待的查询
SELECT * FROM system.processes WHERE elapsed > 1;

-- ClickHouse 的 ALTER 默认是异步的
ALTER TABLE orders ADD COLUMN tag String;
-- 立即返回，后台慢慢应用 mutation

-- 等待应用完成
SELECT * FROM system.mutations WHERE table = 'orders' AND not is_done;

-- 同步等待
SET mutations_sync = 2;
ALTER TABLE orders ADD COLUMN tag String;
```

ClickHouse 的 mutation 与传统事务型数据库的 ALTER 完全不同：metadata 修改是瞬时的，数据回填是异步 mutation。MDL 只保护 metadata 修改本身，时间极短。

## Greenplum / Yellowbrick / Redshift：PostgreSQL 衍生家族

这三个数据库都是 PG fork，因此 MDL 模型与 PG 完全一致：8 级锁阶、`pg_locks` 视图、`AccessExclusiveLock`。差异主要在分布式部分：

- **Greenplum**：DDL 必须在 master + 所有 segment 上一致提交，使用 2PC
- **Redshift**：DDL 是串行的，由 leader node 发起
- **Yellowbrick**：MPP 之上保留 PG 的锁语义

## YugabyteDB / Spanner：分布式版本化 schema

YugabyteDB 基于 PostgreSQL 兼容层 + DocDB 存储，schema 版本由 master 维护。Spanner 使用类似 F1 的长跑 schema change，可以在数小时内完成 schema 变更而不阻塞写。

```sql
-- YugabyteDB
SELECT * FROM pg_locks;

-- Spanner
-- DDL 是异步的，通过 long-running operation 跟踪
gcloud spanner operations list --instance=test --database=app
```

## 关键发现

1. **MDL 不在 SQL 标准中，但每个生产数据库都有**：标准只规定隔离语义，实现机制完全自由。45+ 数据库中约 36 个有显式 MDL，其余靠版本化 catalog 规避。

2. **MySQL MDL 引入于 5.5（2010）**，是 MySQL 第一次把"事务边界内的 schema 一致性"作为强保证。在此之前，事务内的 schema 可以"突变"。

3. **MySQL `performance_schema.metadata_locks` 是 5.7 引入的，但默认关闭**。生产系统第一件事应该是启用 `wait/lock/metadata/sql/mdl` instrument，否则 MDL 雪崩排查只能靠 `SHOW PROCESSLIST` 看 `Waiting for table metadata lock` 字符串。

4. **PostgreSQL 的 8 级锁阶是教科书级清晰的**。AccessExclusiveLock 与一切互斥，而 ShareUpdateExclusive 与 DML 兼容（这就是 VACUUM 和 CREATE INDEX CONCURRENTLY 不阻塞业务的原因）。

5. **PostgreSQL ALTER TABLE ... SET DEFAULT 不重写表**。从 11 起，ADD COLUMN 加非 volatile 默认值也不重写。但 SET NOT NULL 仍然需要全表扫描——记住这条可以避免 90% 的 PG DDL 事故。

6. **Oracle 的 library cache lock/pin 是双层保护**：lock 保护对象句柄，pin 保护编译产物。Oracle 的 DDL 不长期阻塞 SELECT，代价是游标失效引发的硬解析风暴。

7. **SQL Server 的 Sch-M 与一切不兼容**——这条规则极简单，但意味着 SQL Server 的 DDL 在大表上更"硬碰硬"，没有 PG 那种"中间态"。

8. **TiDB 与 CockroachDB 都基于 F1 的 2 版本不变式**：DDL 推进通过 lease 同步，老 DML 用旧版本 schema 完成。代价是 DDL 总耗时 ≥ 1 个 lease 周期（TiDB 默认 45 秒，CRDB 默认 5 分钟）。

9. **Snowflake / BigQuery 完全没有 MDL**：catalog 是版本化对象，DDL 创建新版本，老查询继续读老版本，零阻塞。这是云原生数据库相对传统数据库的本质优势之一。

10. **MDL 雪崩的根因不是 MDL 本身，而是 FIFO 队列 + 长事务**：MySQL 和 PG 的队列模型让一个等待的 DDL 阻塞所有后续 DML，雪崩在毫秒内形成。Oracle 用"短时获取 + 重试"避开了这个陷阱。

11. **`lock_timeout` 是防雪崩的第一道防线**：不要让 DDL 无限期等待 MDL。MySQL 默认 `lock_wait_timeout=31536000`（一年！），PG 默认 `lock_timeout=0`（无限）——这两个默认值都是错的。生产 DDL 应该设置 1-10 秒的超时，失败后由调度系统重试。

12. **Instant DDL 是治本之策**：MySQL 8.0.12+、MariaDB 10.3+、PG 11+ 都有"瞬时 ADD COLUMN"，MDL 持有时间从分钟降到毫秒。但要小心限制：MySQL INSTANT 只能加在表末尾（8.0.29 起允许任意位置但有限制），PG 不能用 volatile 默认值。

13. **gh-ost / pt-online-schema-change 的本质是绕开 MDL**：它们不修改原表，而是用影子表 + 触发器/binlog 同步，最后原子切换，MDL 只在切换瞬间持有。在 Instant DDL 不可用时，这是唯一的生产解。

14. **TiDB 6.3+ 也引入了 MDL**（与传统 MySQL MDL 语义不同）：用于防止老事务读到不兼容的新 schema，与 lease 机制并存。这表明即使在最先进的分布式数据库中，MDL 思想依然有价值。

15. **MDL 的可观测性是分水岭**：大多数数据库的 MDL 视图默认开启（PG/Oracle/SQL Server/DB2/CRDB），但 MySQL 默认关闭——这导致 MySQL 的 MDL 故障排查显著困难。运维 MySQL 的第一件事就是打开 metadata_locks instrument。

## 引擎选型建议

| 场景 | 推荐 | 原因 |
|------|------|------|
| OLTP 频繁 DDL，零容忍业务停顿 | Snowflake / BigQuery / Spanner | 完全无 MDL，版本化 catalog |
| 自建 MySQL，频繁 DDL | MySQL 8.0+ INSTANT + gh-ost 兜底 | INSTANT 覆盖大部分场景 |
| 自建 PostgreSQL | PG 11+ + lock_timeout=2s + CREATE INDEX CONCURRENTLY | 标准 PG 工具链够用 |
| 分布式 OLTP，期望在线 schema change | TiDB / CockroachDB | 2 版本不变式 |
| HTAP，需要并发 DDL/DML | YugabyteDB / OceanBase | 平衡 |
| OLAP 数据仓库 | Snowflake / BigQuery / Databricks | DDL 与 DML 解耦 |
| 嵌入式分析 | DuckDB | catalog MVCC，单进程无锁 |

## 参考资料

- MySQL: [Metadata Locking](https://dev.mysql.com/doc/refman/8.0/en/metadata-locking.html)
- MySQL: [The metadata_locks Table](https://dev.mysql.com/doc/refman/8.0/en/performance-schema-metadata-locks-table.html)
- MySQL Worklog: [WL#5004 MDL deadlock detector](https://dev.mysql.com/worklog/task/?id=5004)
- PostgreSQL: [Explicit Locking](https://www.postgresql.org/docs/current/explicit-locking.html)
- PostgreSQL: [pg_locks](https://www.postgresql.org/docs/current/view-pg-locks.html)
- Oracle: [Library Cache Locks and Pins](https://docs.oracle.com/en/database/oracle/oracle-database/19/cncpt/data-concurrency-and-consistency.html)
- SQL Server: [Lock Modes](https://learn.microsoft.com/en-us/sql/relational-databases/sql-server-transaction-locking-and-row-versioning-guide)
- DB2: [Lock modes](https://www.ibm.com/docs/en/db2/11.5?topic=locks-lock-modes)
- TiDB: [Online DDL](https://docs.pingcap.com/tidb/stable/ddl-introduction)
- TiDB: [Metadata Lock](https://docs.pingcap.com/tidb/stable/metadata-lock)
- CockroachDB: [Online Schema Changes](https://www.cockroachlabs.com/docs/stable/online-schema-changes)
- Snowflake: [Time Travel](https://docs.snowflake.com/en/user-guide/data-time-travel)
- F1 paper: Rae et al., "Online, Asynchronous Schema Change in F1" (VLDB 2013)
- gh-ost: [GitHub gh-ost design](https://github.com/github/gh-ost/blob/master/doc/cheatsheet.md)
- pt-online-schema-change: [Percona Toolkit docs](https://docs.percona.com/percona-toolkit/pt-online-schema-change.html)
