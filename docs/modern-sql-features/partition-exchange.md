# 分区交换 (Partition Exchange / SWAP PARTITION)

将一张准备好的"暂存表"在毫秒内切换为分区表的一个分区——分区交换是大表批量加载的零拷贝武器，也是数据仓库 ETL 流水线中最被低估的 SQL 能力。本文系统梳理 45+ 引擎对 EXCHANGE PARTITION / SWITCH / ATTACH PARTITION 的实现差异。

## 核心思想：零拷贝的批量加载

```
传统加载流程 (慢):
  1. 数据准备到外部文件 (CSV/Parquet)
  2. INSERT INTO partitioned_table SELECT ...    -- 写入主表, 触发索引更新
  3. UPDATE/MERGE 修复异常数据
  4. 期间分区表对查询可见, 中间状态会被读到

分区交换流程 (零拷贝):
  1. CREATE TABLE staging (...) 与目标分区结构完全一致
  2. 数据加载到 staging (此时查询主表完全无感知)
  3. 在 staging 上构建索引、统计信息
  4. ALTER TABLE main EXCHANGE PARTITION p_2024 WITH TABLE staging;
  5. 一次原子的元数据交换: 主表 p_2024 ↔ staging
     - 数据文件不动 (零拷贝)
     - 仅交换数据字典中的指针 / segment 元数据
     - 整个过程毫秒级, 持有短暂的元数据锁
```

EXCHANGE PARTITION 的本质是**元数据指针交换**：分区表的某个分区与一张独立表交换数据文件归属，不实际移动任何数据。这使得它成为数据仓库 ETL 中性能最优的批量加载方案——加载 100GB 数据可能只需要几毫秒的元数据切换时间。

## SQL 标准状态

SQL:2003 / SQL:2011 / SQL:2016 / SQL:2023 标准均**未定义** EXCHANGE PARTITION 或 SWAP PARTITION 语法。事实上，SQL 标准对分区本身的定义都非常有限——SQL/MED (Management of External Data) 涉及外部数据访问，但分区交换属于纯实现层面的能力。

各厂商的实现完全自由发挥，导致语法和语义差异巨大：

```sql
-- Oracle (1999 年首创)
ALTER TABLE main EXCHANGE PARTITION p_2024 WITH TABLE staging
    INCLUDING INDEXES WITHOUT VALIDATION;

-- SQL Server (不同关键字)
ALTER TABLE main SWITCH PARTITION 5 TO staging;

-- PostgreSQL (双向操作)
ALTER TABLE main ATTACH PARTITION staging FOR VALUES FROM ('2024-01-01') TO ('2025-01-01');
ALTER TABLE main DETACH PARTITION p_2024 CONCURRENTLY;

-- MySQL
ALTER TABLE main EXCHANGE PARTITION p_2024 WITH TABLE staging WITHOUT VALIDATION;

-- DB2
ALTER TABLE main ATTACH PARTITION p_2024 STARTING ('2024-01-01') ENDING ('2025-01-01') FROM staging;
ALTER TABLE main DETACH PARTITION p_2024 INTO archive_2024;
```

## 支持矩阵：基础语法

| 引擎 | 关键字 | 双向交换 | 单向 ATTACH | 单向 DETACH | 起始版本 |
|------|--------|----------|-------------|-------------|----------|
| Oracle | `EXCHANGE PARTITION` | 是 | 不需要 | 不需要 | 8i (1999) |
| SQL Server | `SWITCH PARTITION` | 是 (用 SWITCH 双向) | -- | -- | 2005 |
| PostgreSQL | `ATTACH/DETACH PARTITION` | 否 (需两步) | 是 (10, 2017) | 是 (11, 2018) | 10/11 |
| MySQL | `EXCHANGE PARTITION` | 是 | -- | -- | 5.6 (2013) |
| MariaDB | `EXCHANGE PARTITION` | 是 | -- | -- | 10.0+ (继承 MySQL) |
| DB2 (LUW) | `ATTACH/DETACH PARTITION` | 否 | 是 (9.7, 2010) | 是 (9.7) | 9.7 |
| Greenplum | `EXCHANGE PARTITION` | 是 | -- | -- | 4.x+ (继承 PG/Oracle 风格) |
| Vertica | `SWAP_PARTITIONS_BETWEEN_TABLES` | 是 | -- | -- | 7.x+ |
| TiDB | `EXCHANGE PARTITION` | 是 | -- | -- | 6.3 (2022, 实验) / 7.1+ |
| OceanBase | `EXCHANGE PARTITION` | 是 (Oracle 兼容模式) | -- | -- | 4.x+ |
| Snowflake | -- | -- | -- | -- | 不支持 (不可控分区) |
| BigQuery | -- | -- | -- | -- | 不支持 (隐式分区) |
| Redshift | -- | -- | -- | -- | 不支持 (按 sortkey 组织) |
| ClickHouse | `MOVE PARTITION` / `REPLACE PARTITION` | 部分 | `ATTACH PARTITION` | `DETACH PARTITION` | 1.1.x+ |
| Hive | `EXCHANGE PARTITION` | 是 | -- | -- | 0.12+ (2013) |
| Spark SQL | -- | -- | -- | -- | 不直接支持 (取决于 catalog) |
| Trino/Presto | -- | -- | -- | -- | 不支持 |
| Athena (Trino) | -- | -- | -- | -- | 不支持 |
| Iceberg | -- | -- | -- | -- | 不支持 (但有 fast append) |
| Delta Lake | -- | -- | -- | -- | 不支持 (用 Z-Order/OPTIMIZE) |
| Hudi | -- | -- | -- | -- | 不支持 (Bulk Insert 替代) |
| Doris | `REPLACE PARTITION` | 部分 | 是 (临时分区) | 是 | 0.12+ |
| StarRocks | `REPLACE PARTITION` | 部分 | 是 (临时分区) | 是 | 1.18+ |
| MaxCompute | `INSERT OVERWRITE PARTITION` | -- | -- | -- | (通过 INSERT 覆盖) |
| YugabyteDB | `ATTACH/DETACH PARTITION` | 否 | 是 | 是 | 2.x+ (继承 PG) |
| CockroachDB | -- | -- | -- | -- | 不支持 (用 PARTITION BY 重声明) |
| SAP HANA | `MERGE PARTITIONS` / `ALTER PARTITIONS` | 部分 | -- | -- | 2.0+ |
| Teradata | -- | -- | -- | -- | 不支持 (但有 partition primary index 重组) |
| Informix | `ATTACH/DETACH FRAGMENT` | 否 | 是 | 是 | 11.x+ |
| Sybase ASE | `EXCHANGE PARTITION` | 是 | -- | -- | 15.7+ |
| SQLite | -- | -- | -- | -- | 不支持分区 |
| H2 | -- | -- | -- | -- | 不支持分区 |
| HSQLDB | -- | -- | -- | -- | 不支持分区 |
| Derby | -- | -- | -- | -- | 不支持分区 |
| Firebird | -- | -- | -- | -- | 不支持分区 |
| MonetDB | `MERGE TABLE`/`SPLIT TABLE` | -- | -- | -- | 替代方案: merge table |
| TimescaleDB | `attach_tablespace`/`detach_tablespace` | -- | -- | -- | 通过 chunk 机制 |
| QuestDB | -- | -- | -- | -- | 不支持 (按时间分区, 自动管理) |
| DuckDB | -- | -- | -- | -- | 不支持原生分区 |
| Crate DB | -- | -- | -- | -- | 不支持 |
| Materialize | -- | -- | -- | -- | 流式物化, 无分区 |
| RisingWave | -- | -- | -- | -- | 流式, 无分区 |
| Flink SQL | -- | -- | -- | -- | 流式, 无分区 |
| InfluxDB (SQL) | -- | -- | -- | -- | 不支持 |
| Apache Kudu | -- | -- | -- | -- | 不支持 (rebalance 替代) |
| Yellowbrick | `ATTACH PARTITION` (PG) | 是 | 是 | 是 | 继承 PG |
| DatabendDB | -- | -- | -- | -- | 不支持 |
| Firebolt | -- | -- | -- | -- | 不支持 |
| Singlestore (MemSQL) | -- | -- | -- | -- | 不支持 (用 sharding) |
| Amazon RDS Aurora MySQL | `EXCHANGE PARTITION` | 是 | -- | -- | 继承 MySQL 5.6+ |
| Amazon RDS Aurora PostgreSQL | `ATTACH/DETACH PARTITION` | 否 | 是 | 是 | 继承 PG 10+ |
| Azure SQL Database | `SWITCH PARTITION` | 是 | -- | -- | 继承 SQL Server |

> 统计：约 **15 个引擎**完整支持 EXCHANGE/SWAP/ATTACH 风格的零拷贝分区交换；约 **8 个引擎**通过 REPLACE PARTITION / MERGE TABLE 等替代机制提供类似能力；其余 22+ 引擎不支持或采用完全不同的批量加载范式。

## 支持矩阵：高级特性

### 索引与约束处理

| 引擎 | INCLUDING INDEXES | EXCLUDING INDEXES | 索引重建 | 主键/外键校验 |
|------|-------------------|-------------------|----------|----------------|
| Oracle | 是 (默认) | 是 | 仅本地索引随交换迁移 | 自动校验 (除非 WITHOUT VALIDATION) |
| SQL Server | 必需匹配 | 不允许 | 索引必须预先在 staging 上完全相同 | 严格校验 |
| PostgreSQL | 自动继承 | -- | 索引必须在 staging 上预先创建匹配 | 严格校验 |
| MySQL | -- | -- | 索引必须在两表上完全一致 | 严格校验 |
| MariaDB | -- | -- | 同 MySQL | 严格校验 |
| DB2 | 自动继承 | -- | 索引随分区迁移 | 严格校验 |
| Greenplum | 是 (默认) | 是 | 同 Oracle 风格 | 自动校验 |
| TiDB | -- | -- | 索引必须一致 | 严格校验 |
| Hive | -- | -- | -- (Hive 索引能力有限) | 不校验 (DFS 文件移动) |

### 数据校验与跳过

| 引擎 | WITH VALIDATION | WITHOUT VALIDATION | 校验内容 | 默认行为 |
|------|-----------------|---------------------|----------|----------|
| Oracle | 是 (默认) | 是 | 检查 staging 中行是否符合分区键约束 | WITH VALIDATION |
| SQL Server | -- | 是 (CHECK 约束) | 通过 CHECK 约束告知优化器, 跳过运行时校验 | 必须有 CHECK 约束 |
| PostgreSQL | 自动 | -- | ATTACH 时全表扫描校验, 除非有 CHECK 约束 | WITH VALIDATION |
| MySQL | 是 (默认) | 是 | 行级校验分区键 | WITH VALIDATION |
| MariaDB | 是 (默认) | 是 | 同 MySQL | WITH VALIDATION |
| DB2 | 是 (默认) | -- | 通过 NOT LOGGED INITIALLY 跳过日志, 仍校验 | WITH VALIDATION |
| Greenplum | 是 (默认) | 是 | 同 Oracle | WITH VALIDATION |

### ATTACH / DETACH (PostgreSQL 阵营)

| 引擎 | ATTACH PARTITION | DETACH PARTITION | DETACH CONCURRENTLY | DETACH FINALIZE |
|------|-------------------|-------------------|---------------------|------------------|
| PostgreSQL 10 | 是 (2017) | -- | -- | -- |
| PostgreSQL 11 | 是 | 是 (2018) | -- | -- |
| PostgreSQL 12 | 是 | 是 | -- | -- |
| PostgreSQL 13 | 是 | 是 | -- | -- |
| PostgreSQL 14 | 是 | 是 | 是 (2021) | 是 |
| PostgreSQL 15 | 是 | 是 | 是 | 是 |
| PostgreSQL 16+ | 是 | 是 (优化锁级别) | 是 | 是 |
| YugabyteDB | 是 | 是 | -- (实现中) | -- |
| Greenplum 7+ | 是 (新增, PG12 内核) | 是 | -- | -- |
| Yellowbrick | 是 | 是 | -- | -- |

### 自动检测/自动操作

| 引擎 | 自动 detach 旧分区 | 自动 attach 新分区 | 自动维护接口 |
|------|---------------------|---------------------|----------------|
| Oracle | 是 (Auto-List, Interval) | 是 (Interval) | DBMS_PART, DBMS_REDEFINITION |
| SQL Server | -- | -- | sliding window 通过 SP 实现 |
| PostgreSQL | -- (需手动 cron / pg_partman) | -- | 扩展: pg_partman |
| MySQL | -- | -- | 仅手动 |
| Snowflake | -- | -- | 隐式 micro-partition |
| BigQuery | 是 (按 partition_expiration_days) | -- | 自动生命周期 |
| ClickHouse | -- | -- | TTL DELETE WHERE |
| TimescaleDB | 是 (drop_chunks) | 是 (continuous aggregate) | hypertable API |
| TiDB | -- (通过 placement rule) | -- | -- |

## 各引擎语法详解

### Oracle (1999 年首创, 黄金标准)

Oracle 在 8i (1999) 引入 `ALTER TABLE ... EXCHANGE PARTITION`，是行业内最早、最成熟的实现。直到今天，许多其他引擎的实现都明显参考了 Oracle 的语法。

```sql
-- 基础语法: 交换分区与独立表
ALTER TABLE sales EXCHANGE PARTITION sales_q4_2024 WITH TABLE staging_q4_2024;

-- 完整语法 (推荐 ETL 模式): 包含索引, 跳过校验, 不更新全局索引
ALTER TABLE sales
    EXCHANGE PARTITION sales_q4_2024
    WITH TABLE staging_q4_2024
    INCLUDING INDEXES
    WITHOUT VALIDATION
    UPDATE GLOBAL INDEXES;

-- 各选项含义:
-- INCLUDING INDEXES: 本地索引 (LOCAL INDEX) 也一同交换 (默认)
-- EXCLUDING INDEXES: 仅交换数据, 索引保持原状, 之后需手动重建
-- WITH VALIDATION: 全表扫描校验 staging 数据是否满足分区键约束 (默认)
-- WITHOUT VALIDATION: 跳过校验, 速度极快, 但需要应用方保证数据正确性
-- UPDATE GLOBAL INDEXES: 全局索引 (GLOBAL INDEX) 增量维护 (默认会失效)

-- 子分区 (Composite Partitioning) 的交换
ALTER TABLE sales EXCHANGE SUBPARTITION sales_q4_2024_north
    WITH TABLE staging_q4_2024_north
    INCLUDING INDEXES;

-- 12c+ 单步交换多分区 (在线分区操作)
ALTER TABLE sales MODIFY PARTITION sales_q4_2024
    INDEXING ON;  -- 启用 partial indexing

-- 19c+ 在线交换 (减少锁时间)
ALTER TABLE sales EXCHANGE PARTITION sales_q4_2024
    WITH TABLE staging_q4_2024
    INCLUDING INDEXES
    WITHOUT VALIDATION
    ONLINE;  -- 19c+ 支持在线交换, 不阻塞 DML
```

#### Oracle 完整 ETL 模式

```sql
-- 步骤 1: 创建与目标分区结构完全相同的 staging 表
CREATE TABLE staging_q4_2024 AS
    SELECT * FROM sales WHERE 1 = 0;  -- 空结构复制

-- 步骤 2: 加载数据 (可使用 NOLOGGING + DIRECT PATH 加速)
INSERT /*+ APPEND */ INTO staging_q4_2024
    SELECT * FROM external_table;
COMMIT;

-- 步骤 3: 在 staging 上构建本地索引 (与主表 LOCAL INDEX 结构完全一致)
CREATE INDEX idx_staging_customer ON staging_q4_2024(customer_id) NOLOGGING;
CREATE INDEX idx_staging_product  ON staging_q4_2024(product_id)  NOLOGGING;

-- 步骤 4: 收集统计信息 (避免交换后 CBO 缺失统计)
EXEC DBMS_STATS.GATHER_TABLE_STATS(USER, 'STAGING_Q4_2024');

-- 步骤 5: 添加 CHECK 约束 (使 EXCHANGE 可以快速跳过校验)
ALTER TABLE staging_q4_2024 ADD CONSTRAINT chk_q4_range
    CHECK (sale_date >= DATE '2024-10-01' AND sale_date < DATE '2025-01-01');

-- 步骤 6: 原子交换
ALTER TABLE sales EXCHANGE PARTITION sales_q4_2024
    WITH TABLE staging_q4_2024
    INCLUDING INDEXES WITHOUT VALIDATION;

-- 步骤 7: (可选) 删除已交换出来的旧数据
DROP TABLE staging_q4_2024 PURGE;
```

#### Oracle EXCHANGE 的关键限制

```
1. 表结构必须完全相同:
   - 列数、列名、列类型、列顺序
   - NOT NULL 约束
   - DEFAULT 值
   - 虚拟列 (Virtual Column)
   不一致会报 ORA-14097: column type or size mismatch

2. 索引结构限制:
   - LOCAL 索引在两表上必须完全一致 (列、顺序、UNIQUE)
   - GLOBAL 索引会因 EXCHANGE 失效, 除非 UPDATE GLOBAL INDEXES

3. 触发器: 触发器不会随 EXCHANGE 移动, 留在原表上

4. 外键: 引用此分区的外键约束需先 DISABLE

5. LOB 字段: 如果是 SecureFile LOB, 表空间和 SECUREFILE 设置必须一致

6. WITH VALIDATION 的开销:
   - 全表扫描 staging, 验证每行的分区键
   - 大表上可能需要数小时
   - 如果 staging 上有 CHECK 约束, 优化器会跳过运行时验证
```

### SQL Server (2005 引入 SWITCH)

SQL Server 在 2005 引入 `ALTER TABLE ... SWITCH PARTITION`，使用与 Oracle 不同的关键字和语义模型。SWITCH 是单向操作，但通过两次 SWITCH 可以实现等价的双向交换。

```sql
-- 基础语法: 将分区 5 的数据切换到 staging
ALTER TABLE Sales SWITCH PARTITION 5 TO StagingQ4;

-- 反向: 从 staging 切换回主表
ALTER TABLE StagingQ4 SWITCH TO Sales PARTITION 5;

-- 在不同的分区方案之间切换
ALTER TABLE Sales SWITCH PARTITION 5 TO Archive PARTITION 1;

-- WITH (WAIT_AT_LOW_PRIORITY): SQL Server 2014+
ALTER TABLE Sales SWITCH PARTITION 5 TO StagingQ4
    WITH (WAIT_AT_LOW_PRIORITY (
        MAX_DURATION = 60 MINUTES,
        ABORT_AFTER_WAIT = SELF
    ));
```

#### SQL Server SWITCH 的严格约束

SQL Server 的 SWITCH PARTITION 是**所有引擎中约束最严格**的实现：

```sql
-- 1. 表结构要求 (必须完全相同):
--    列数、列名、列类型、可空性、NULL 默认、计算列
--    标识列 (IDENTITY) 设置

-- 2. 文件组要求:
--    源分区和目标表必须在同一个文件组 (FILEGROUP)

-- 3. 索引要求:
--    所有索引必须完全相同 (列、列顺序、唯一性、过滤条件)
--    包括聚簇索引和非聚簇索引

-- 4. 约束要求 (CHECK 约束是关键!):
--    目标表必须有 CHECK 约束确保数据落在源分区的范围内
--    这是 SQL Server 跳过运行时校验的依据

-- 实战: 完整的 SWITCH 准备
CREATE TABLE StagingQ4 (
    OrderId BIGINT NOT NULL,
    OrderDate DATE NOT NULL,
    Amount DECIMAL(10,2),

    -- 关键: CHECK 约束告知 SQL Server 数据范围
    CONSTRAINT chk_q4_2024_range CHECK (
        OrderDate >= '2024-10-01' AND OrderDate < '2025-01-01'
    )
) ON [PRIMARY];  -- 必须与 Sales 同一文件组

-- 创建与主表完全一致的索引
CREATE CLUSTERED INDEX ix_clustered ON StagingQ4(OrderDate, OrderId);
CREATE NONCLUSTERED INDEX ix_customer ON StagingQ4(CustomerId);
```

#### SQL Server 的 sliding window 模式

```sql
-- 经典的 "时间窗口" 数据生命周期管理 (常用于事实表归档)
-- 1. 从主表 SWITCH OUT 最旧分区到 staging (变成普通表)
ALTER TABLE Sales SWITCH PARTITION 1 TO Archive_Old;

-- 2. 删除主表上空的分区
ALTER PARTITION FUNCTION pf_Sales_Date() MERGE RANGE ('2023-01-01');

-- 3. 添加新分区到主表
ALTER PARTITION SCHEME ps_Sales_Date NEXT USED [PRIMARY];
ALTER PARTITION FUNCTION pf_Sales_Date() SPLIT RANGE ('2025-04-01');

-- 4. 加载新数据到 staging, 然后 SWITCH IN
ALTER TABLE Staging_New SWITCH TO Sales PARTITION 16;

-- 整个过程: 旧数据归档 + 新数据加载, 主表无停机时间
```

### PostgreSQL: ATTACH / DETACH 范式

PostgreSQL 走了一条独特的路：没有 EXCHANGE，而是用 ATTACH PARTITION / DETACH PARTITION 实现等价语义。这种设计来自 PG 10 (2017) 引入的**声明式分区**。

#### ATTACH PARTITION (PG 10+, 2017)

```sql
-- 创建分区主表
CREATE TABLE measurement (
    city_id    INT NOT NULL,
    logdate    DATE NOT NULL,
    peaktemp   INT,
    unitsales  INT
) PARTITION BY RANGE (logdate);

-- 步骤 1: 独立创建一张表 (不是分区, 而是普通表)
CREATE TABLE measurement_y2024m12 (
    LIKE measurement INCLUDING ALL
);

-- 步骤 2: 加载数据 (此时 measurement 表完全感知不到这张表)
COPY measurement_y2024m12 FROM '/data/m_y2024m12.csv' CSV;

-- 步骤 3: 添加 CHECK 约束 (避免 ATTACH 时全表扫描)
ALTER TABLE measurement_y2024m12 ADD CONSTRAINT chk_logdate
    CHECK (logdate >= '2024-12-01' AND logdate < '2025-01-01');

-- 步骤 4: ATTACH (零拷贝, 仅元数据更新)
ALTER TABLE measurement ATTACH PARTITION measurement_y2024m12
    FOR VALUES FROM ('2024-12-01') TO ('2025-01-01');
```

ATTACH 的关键语义：

```
1. ATTACH 时 PG 必须验证 staging 数据满足分区边界:
   - 如果 staging 没有 CHECK 约束 → 全表扫描验证 (慢!)
   - 如果有匹配的 CHECK 约束 → 跳过扫描 (秒级完成)

2. 对主表的锁:
   PG 10-13: ACCESS EXCLUSIVE LOCK (阻塞所有读写)
   PG 14+:   ShareUpdateExclusiveLock (允许并发查询, 阻塞 schema 变更)

3. 索引继承:
   PG 11+: 主表上的索引会自动在新分区上创建 (如果不存在)
   PG 10:  必须先在 staging 上手动创建匹配索引

4. 约束继承:
   主表上的 NOT NULL, CHECK 约束自动应用
   主表的 PRIMARY KEY (PG 11+) 自动包含分区键
```

#### DETACH PARTITION (PG 11+, 2018)

```sql
-- 基础 DETACH: 将分区脱离, 变成独立表
ALTER TABLE measurement DETACH PARTITION measurement_y2020m01;

-- 之后可以正常查询、修改 measurement_y2020m01, 不影响主表
SELECT * FROM measurement_y2020m01;
DROP TABLE measurement_y2020m01;
```

DETACH 在 PG 11-13 仍然需要 ACCESS EXCLUSIVE LOCK，对生产环境是个问题。

#### DETACH PARTITION CONCURRENTLY (PG 14+, 2021)

PG 14 是关键里程碑：引入 `DETACH PARTITION CONCURRENTLY`，将分区脱离做成不阻塞读写的操作。

```sql
-- 步骤 1: 启动 CONCURRENTLY DETACH
ALTER TABLE measurement DETACH PARTITION measurement_y2020m01 CONCURRENTLY;

-- 此时分区进入 "pending detach" 状态:
-- - 新查询不再访问该分区
-- - 已有事务仍可访问 (避免破坏一致性)
-- - 主表的 partition descriptor 标记此分区为 detaching

-- 步骤 2: 等待所有快照完成 (内部自动完成, 一般几秒到几分钟)

-- 步骤 3: 如果上一步因故中断 (如客户端崩溃), 用 FINALIZE 完成
ALTER TABLE measurement DETACH PARTITION measurement_y2020m01 FINALIZE;

-- 完成后, measurement_y2020m01 成为独立表
```

CONCURRENTLY 的实现细节：

```
锁级别变化 (PG 14+):
  传统 DETACH: ACCESS EXCLUSIVE LOCK (阻塞所有 DML)
  DETACH CONCURRENTLY:
    阶段 1: ShareUpdateExclusiveLock (允许 SELECT/INSERT/UPDATE/DELETE)
    阶段 2: 等待 long-running 事务结束
    阶段 3: ShareUpdateExclusiveLock (短暂) 完成 catalog 更新

限制:
  1. 不能在事务块内执行 (类似 CREATE INDEX CONCURRENTLY)
  2. 如果有默认分区 (DEFAULT PARTITION), CONCURRENTLY 不可用
     原因: 需要将默认分区中可能的行物理移动
  3. 失败后表处于 "detaching" 状态, 必须用 FINALIZE 完成或回滚
```

#### PG ATTACH PARTITION 没有 CONCURRENTLY 版本

PG 截至 17 版本仍未实现 ATTACH PARTITION CONCURRENTLY。原因是 ATTACH 涉及对主表 partition descriptor 的修改，对 row-level routing 影响巨大，难以在不停顿写入的情况下完成。

#### PostgreSQL: 用 ATTACH + DETACH 实现 Oracle 风格的 EXCHANGE

```sql
-- 模拟 Oracle EXCHANGE PARTITION 的等价操作: 两步法
BEGIN;
    -- 步骤 1: DETACH 旧分区
    ALTER TABLE measurement DETACH PARTITION measurement_y2024m12;

    -- 步骤 2: 重命名旧分区, 让出名字
    ALTER TABLE measurement_y2024m12 RENAME TO measurement_y2024m12_old;
    ALTER TABLE staging_y2024m12 RENAME TO measurement_y2024m12;

    -- 步骤 3: ATTACH 新分区 (新表已是正确名称)
    ALTER TABLE measurement ATTACH PARTITION measurement_y2024m12
        FOR VALUES FROM ('2024-12-01') TO ('2025-01-01');
COMMIT;

-- 注意: 整个过程在事务中完成, ATTACH 仍会阻塞主表
-- 如果使用 PG 14+ 的 DETACH CONCURRENTLY, 不能与 ATTACH 在同一事务
```

### MySQL EXCHANGE PARTITION (5.6+, 2013)

MySQL 在 5.6 (2013) 引入 EXCHANGE PARTITION，语法上模仿 Oracle 但限制更多。

```sql
-- 基础语法
ALTER TABLE sales EXCHANGE PARTITION p_q4_2024 WITH TABLE staging_q4_2024;

-- WITHOUT VALIDATION (5.7+)
ALTER TABLE sales EXCHANGE PARTITION p_q4_2024 WITH TABLE staging_q4_2024
    WITHOUT VALIDATION;

-- 完整 ETL 流程
-- 步骤 1: 创建结构相同的 staging 表 (注意: 不能是分区表)
CREATE TABLE staging_q4_2024 LIKE sales;

-- 重要: MySQL 不支持 CREATE TABLE LIKE 复制分区结构, 但 staging 必须是非分区表
-- 因此需要手动移除分区结构
ALTER TABLE staging_q4_2024 REMOVE PARTITIONING;

-- 步骤 2: 加载数据
LOAD DATA INFILE '/data/q4_2024.csv' INTO TABLE staging_q4_2024;

-- 步骤 3: 索引必须完全一致
-- (CREATE TABLE LIKE 已复制索引, 但需确认与主表分区结构相同)

-- 步骤 4: 交换
ALTER TABLE sales EXCHANGE PARTITION p_q4_2024 WITH TABLE staging_q4_2024
    WITHOUT VALIDATION;
```

#### MySQL EXCHANGE PARTITION 的限制

MySQL 的实现是所有引擎中限制最多的：

```
1. staging 表不能是分区表
   - Oracle/SQL Server 允许两个分区之间交换
   - MySQL 只能 "分区 ↔ 普通表"

2. 表结构必须严格一致
   - 列数、列名、类型、顺序、字符集、collation
   - 索引 (包括 PRIMARY KEY) 必须完全一致
   - 外键: staging 不能有指向其他表的外键

3. 不支持触发器
   - 主表上的触发器不会在 EXCHANGE 时触发

4. 不支持 INCLUDING/EXCLUDING INDEXES 选项
   - 索引必须预先在两表上完全相同
   - 不能选择性地交换或不交换索引

5. WITH VALIDATION 是强制的 (默认), 大表慢
   - WITHOUT VALIDATION 跳过, 但需要应用方保证数据正确

6. AUTO_INCREMENT 列的处理
   - staging 上的 AUTO_INCREMENT 计数器会被丢弃
   - 主表的计数器保持

7. 临时表 (TEMPORARY TABLE) 不能用作 staging

8. 不能对 SUBPARTITION 直接交换 (只能交换最外层 PARTITION)
   - 如果定义了子分区, 交换的是整个分区 (含所有子分区)
```

### MariaDB

MariaDB 继承 MySQL 5.5 的代码基线，因此 MariaDB 10.0+ 也支持 EXCHANGE PARTITION，语法和限制与 MySQL 几乎一致。

```sql
-- 完全等同于 MySQL
ALTER TABLE sales EXCHANGE PARTITION p_q4_2024 WITH TABLE staging_q4_2024
    WITHOUT VALIDATION;

-- MariaDB 独有 (10.0+): WITHOUT VALIDATION 子句
-- (MariaDB 10.0 实际上比 MySQL 5.7 更早引入此选项)
```

### DB2 ATTACH / DETACH PARTITION (9.7+, 2010)

IBM DB2 LUW 在 9.7 (2010) 引入分区表的 ATTACH/DETACH。语法风格介于 PostgreSQL 和 Oracle 之间。

```sql
-- ATTACH: 将独立表附加为分区
ALTER TABLE sales
    ATTACH PARTITION p_q4_2024
    STARTING ('2024-10-01') ENDING ('2025-01-01') EXCLUSIVE
    FROM staging_q4_2024;

-- 需要 SET INTEGRITY 完成校验:
SET INTEGRITY FOR sales ALLOW WRITE ACCESS IMMEDIATE CHECKED;
-- 或跳过校验 (如果 staging 已有等价 CHECK 约束):
SET INTEGRITY FOR sales ALL IMMEDIATE UNCHECKED;

-- DETACH: 将分区脱离为独立表
ALTER TABLE sales
    DETACH PARTITION p_q4_2020 INTO archive_q4_2020;

-- DB2 的 DETACH 是异步的 (Asynchronous Partition Detach)
-- 立即返回, 后台线程完成数据移动
```

DB2 的 ATTACH 流程总览：

```
1. ATTACH 后, 分区进入 "set integrity pending" 状态
2. 此时主表对该分区的查询返回错误 (除非用 SET INTEGRITY OFF)
3. 必须手动执行 SET INTEGRITY 完成:
   - CHECKED: 全表扫描验证 (默认)
   - UNCHECKED: 跳过验证 (需手动确保数据正确)
   - GENERATED: 重新计算生成列
4. 完成后分区可正常访问
```

### Greenplum (继承 PG 但保留 EXCHANGE 语法)

Greenplum 基于 PostgreSQL 8.x 分支，但同时保留了 Oracle 风格的 EXCHANGE PARTITION 语法 (旧式分区)。在 Greenplum 7+ 切换到 PG 12 内核后，开始支持原生的 ATTACH/DETACH。

```sql
-- Greenplum 6.x 及更早: Oracle 风格
ALTER TABLE sales EXCHANGE PARTITION FOR (DATE '2024-12-01')
    WITH TABLE staging_q4_2024
    INCLUDING INDEXES
    WITHOUT VALIDATION;

-- Greenplum 7+: 兼容 PG 风格
ALTER TABLE sales DETACH PARTITION sales_q4_2024;
ALTER TABLE sales ATTACH PARTITION staging_q4_2024
    FOR VALUES FROM ('2024-10-01') TO ('2025-01-01');
```

### Hive EXCHANGE PARTITION (0.12+, 2013)

Hive 在 0.12 (2013) 引入了相同名称的语法，但语义完全不同——Hive 的 EXCHANGE PARTITION 实际上是**分区在两个表之间移动**。

```sql
-- 将 source_table 的某个分区移动到 target_table 的同名分区
ALTER TABLE target_table EXCHANGE PARTITION (ds='2024-12-01') WITH TABLE source_table;

-- 关键差异:
-- 1. 不是 "分区表 ↔ 普通表", 而是 "分区表 ↔ 分区表" (按分区键移动)
-- 2. 实际上是 HDFS 上的目录重命名 (零拷贝)
-- 3. 无校验 (Hive 不做行级约束)
-- 4. 两表的分区结构必须完全一致
-- 5. Hive 0.13+ 实现, 早期版本 (0.12) 有 bug

-- 应用场景: 数据归档
ALTER TABLE archive EXCHANGE PARTITION (ds='2020-01-01') WITH TABLE main;
-- 主表 main 的 ds=2020-01-01 分区移动到 archive 表
```

### ClickHouse: MOVE / REPLACE / ATTACH / DETACH PARTITION

ClickHouse 提供了一组完整的分区操作命令，覆盖各种使用场景。

```sql
-- DETACH: 将分区从活跃表中移除 (但物理文件保留)
ALTER TABLE events DETACH PARTITION '2024-12';
-- 此时分区移动到 detached/ 目录, 不再被查询访问

-- ATTACH: 将之前 DETACH 的分区或外部分区附加回表
ALTER TABLE events ATTACH PARTITION '2024-12';
ALTER TABLE events ATTACH PART 'all_42_42_0';  -- 单个 part 级别

-- MOVE: 将分区移动到另一张表 (零拷贝, 同磁盘)
ALTER TABLE events_2024 MOVE PARTITION '2024-12' TO TABLE events_archive;
-- 表结构必须一致, 同一磁盘, 仅元数据移动

-- REPLACE: 用一张表的分区替换另一张表的同名分区
ALTER TABLE events REPLACE PARTITION '2024-12' FROM events_staging;
-- 与 EXCHANGE 类似, 但是单向 (events_staging 的分区不变)

-- DROP: 删除分区
ALTER TABLE events DROP PARTITION '2024-12';
ALTER TABLE events DROP DETACHED PARTITION '2024-12';  -- 删除 detached 中的

-- FREEZE: 冻结分区 (硬链接到备份目录)
ALTER TABLE events FREEZE PARTITION '2024-12';
```

ClickHouse 的特殊之处：

```
1. 分区文件存储独立: 每个分区是独立的目录, 包含 part 文件
2. ATTACH 不需要校验: 信任元数据 (如果 part 损坏会报错)
3. MOVE 跨表零拷贝: 仅修改元数据 (如果在同一磁盘)
4. detached/ 目录: DETACH 不删除物理文件, 适合临时移除
```

### TiDB EXCHANGE PARTITION (6.3+, 实验; 7.1+ GA)

TiDB 在 6.3 (2022) 引入实验性的 EXCHANGE PARTITION，7.1 (2023) GA。设计上对齐 MySQL，但作为分布式数据库有额外考虑。

```sql
-- 基础语法 (与 MySQL 一致)
ALTER TABLE sales EXCHANGE PARTITION p_q4_2024 WITH TABLE staging_q4_2024
    WITHOUT VALIDATION;

-- TiDB 特殊考虑:
-- 1. 分布式校验: WITH VALIDATION 在所有 TiKV 节点并行执行
-- 2. 元数据变更通过 PD 协调
-- 3. 仍受限: 不支持子分区交换、staging 不能是分区表
-- 4. 全局索引 (Global Index, 7.6+) 的影响:
--    交换前后需要更新全局索引, 类似 Oracle 的 UPDATE GLOBAL INDEXES
```

### OceanBase

OceanBase 4.x+ 在 Oracle 兼容模式下完整支持 EXCHANGE PARTITION，MySQL 兼容模式支持 MySQL 风格。

```sql
-- Oracle 兼容模式
ALTER TABLE sales EXCHANGE PARTITION p_q4_2024
    WITH TABLE staging_q4_2024
    INCLUDING INDEXES
    WITHOUT VALIDATION;

-- MySQL 兼容模式
ALTER TABLE sales EXCHANGE PARTITION p_q4_2024 WITH TABLE staging_q4_2024
    WITHOUT VALIDATION;
```

### Vertica SWAP_PARTITIONS_BETWEEN_TABLES

Vertica 用一个独特的函数式接口实现分区交换。

```sql
-- 函数调用风格
SELECT SWAP_PARTITIONS_BETWEEN_TABLES(
    'public.sales',           -- 源表
    '2024-10-01',             -- 起始分区键值
    '2024-12-31',             -- 结束分区键值
    'public.staging_q4_2024'  -- 目标表
);

-- 单向 MOVE
SELECT MOVE_PARTITIONS_TO_TABLE(
    'public.sales',
    '2020-01-01',
    '2020-12-31',
    'public.archive_2020'
);

-- COPY 而非 MOVE (保留源)
SELECT COPY_PARTITIONS_TO_TABLE(...);
```

### Doris / StarRocks: REPLACE PARTITION 与临时分区

Doris 和 StarRocks 不直接支持 EXCHANGE PARTITION，而是用**临时分区**机制实现等价语义。

```sql
-- Doris/StarRocks 临时分区 (Temporary Partition) 模式
-- 步骤 1: 添加临时分区
ALTER TABLE sales ADD TEMPORARY PARTITION tp_q4_2024
    VALUES [('2024-10-01'), ('2025-01-01'));

-- 步骤 2: 加载数据到临时分区
INSERT INTO sales TEMPORARY PARTITION (tp_q4_2024)
    SELECT * FROM staging;

-- 步骤 3: 用临时分区替换正式分区 (原子操作)
ALTER TABLE sales REPLACE PARTITION (p_q4_2024) WITH TEMPORARY PARTITION (tp_q4_2024);

-- 替代方式: 一次性
ALTER TABLE sales REPLACE PARTITION (p_q4_2024) WITH TEMPORARY PARTITION (tp_q4_2024)
    PROPERTIES ("use_temp_partition_name" = "false", "strict_range" = "true");
```

### TimescaleDB: hypertable / chunks

TimescaleDB (PostgreSQL 扩展) 用 hypertable 抽象掉了分区，但底层仍是 PostgreSQL 分区。它提供了 chunk 级别的操作，类似 EXCHANGE。

```sql
-- 查看 chunks
SELECT show_chunks('measurements');

-- 移动 chunk 到另一个 tablespace (类似 partition exchange)
SELECT move_chunk(
    chunk => '_timescaledb_internal._hyper_1_1_chunk',
    destination_tablespace => 'archive_ts',
    index_destination_tablespace => 'archive_ts'
);

-- 删除 chunks (按时间清理)
SELECT drop_chunks('measurements', older_than => INTERVAL '6 months');

-- 压缩 chunk (类似冷热分层)
SELECT compress_chunk('_timescaledb_internal._hyper_1_1_chunk');
```

### YugabyteDB

YugabyteDB 完全继承 PostgreSQL 的 ATTACH/DETACH PARTITION 语法。

```sql
-- 与 PostgreSQL 完全一致
ALTER TABLE measurement ATTACH PARTITION measurement_y2024m12
    FOR VALUES FROM ('2024-12-01') TO ('2025-01-01');

ALTER TABLE measurement DETACH PARTITION measurement_y2020m01;
```

但注意：YugabyteDB 截至当前版本尚未完全实现 PG 14 的 DETACH PARTITION CONCURRENTLY。

### 不支持的引擎与替代方案

#### Snowflake (无原生分区交换)

Snowflake 使用 micro-partition (自动管理), 用户无法直接控制分区。

```sql
-- 替代方案 1: CTAS + SWAP
CREATE TABLE sales_new AS
    SELECT * FROM sales WHERE order_date < '2024-10-01'
    UNION ALL
    SELECT * FROM staging_q4_2024;

ALTER TABLE sales SWAP WITH sales_new;
DROP TABLE sales_new;

-- 替代方案 2: INSERT OVERWRITE
INSERT OVERWRITE INTO sales
    SELECT * FROM sales WHERE order_date < '2024-10-01'
    UNION ALL
    SELECT * FROM staging_q4_2024;
-- 不真正实现分区交换的零拷贝特性
```

#### BigQuery (基于时间的隐式分区)

BigQuery 的分区是基于时间或整数范围的隐式分区，无法做"分区与表"的交换。

```sql
-- 替代方案: CTAS 重新建表
CREATE OR REPLACE TABLE sales
PARTITION BY DATE_TRUNC(order_date, MONTH) AS
    SELECT * FROM sales WHERE order_date < '2024-10-01'
    UNION ALL
    SELECT * FROM staging_q4_2024;

-- 替代方案: MERGE INTO
MERGE INTO sales AS target
USING staging_q4_2024 AS source
ON target.order_id = source.order_id
WHEN MATCHED THEN UPDATE SET ...
WHEN NOT MATCHED THEN INSERT ...;
```

#### Iceberg / Delta Lake / Hudi (lakehouse 表格式)

```
Iceberg:
  - 不支持 EXCHANGE PARTITION (由 catalog 决定)
  - 替代: Fast Append (RewriteFiles, ReplacePartitions API)
  - 通过 metadata file 切换数据指针, 实现快速加载

Delta Lake:
  - 不支持 EXCHANGE
  - 替代: REPLACE WHERE 语法
    INSERT INTO sales REPLACE WHERE order_date >= '2024-10-01'
        SELECT * FROM staging_q4_2024;

Hudi:
  - 通过 Bulk Insert + cleaning 完成 (非零拷贝)
```

#### Redshift / Athena / Trino

```sql
-- Redshift: 无 EXCHANGE PARTITION, 用 ALTER TABLE APPEND
ALTER TABLE sales APPEND FROM staging_q4_2024;
-- 移动行 (实际是 mark for deletion + insert), 非零拷贝

-- Athena/Trino: 无原生分区交换
-- 替代: 用 ALTER TABLE ADD PARTITION 指向不同目录
ALTER TABLE sales ADD PARTITION (year='2024', month='12')
    LOCATION 's3://bucket/staging/q4_2024/';
```

## 关键应用场景

### 场景 1: ETL 批量加载（Oracle/SQL Server/PG）

```
传统方案 (慢):
  原表 → INSERT 大量数据 → 重建索引 → 收集统计 → 影响业务查询

EXCHANGE 方案 (快):
  staging 表准备好所有数据和索引 →
  EXCHANGE PARTITION (毫秒级原子切换) →
  新数据立即可见, 查询无感知
```

性能对比示例 (100GB 数据, 50 亿行):
- 传统 INSERT: 4 小时, 期间索引锁占用, 查询延迟翻倍
- EXCHANGE PARTITION: 总耗时 35 分钟 (staging 准备), 但元数据切换仅 0.3 秒, 主表全程可用

### 场景 2: 数据归档（sliding window）

```sql
-- Oracle: 季度滚动归档
-- 1. 创建 archive 表 (与 sales 结构相同, 非分区)
-- 2. 交换出最旧分区
ALTER TABLE sales EXCHANGE PARTITION sales_q1_2020 WITH TABLE archive_q1_2020
    WITHOUT VALIDATION;
-- 3. 删除主表上的空分区
ALTER TABLE sales DROP PARTITION sales_q1_2020;
-- 4. archive_q1_2020 移到归档存储 (慢速磁盘)

-- SQL Server: SWITCH OUT 等价操作
ALTER TABLE Sales SWITCH PARTITION 1 TO Archive_2020_Q1;
ALTER PARTITION FUNCTION pf_Sales_Date() MERGE RANGE ('2020-04-01');
```

### 场景 3: 在线 schema 升级

```
需求: 修改主表的列定义, 但不能停机

EXCHANGE PARTITION 方案:
  1. 创建 new_sales 分区表, 使用新 schema
  2. 对每个分区:
     a. CTAS 旧分区数据到 staging (按新 schema)
     b. EXCHANGE PARTITION 到 new_sales
  3. RENAME: sales → sales_old, new_sales → sales
  4. 应用切换连接
```

### 场景 4: 数据修复

```sql
-- 发现某分区数据错误, 用修正后的数据替换
-- 1. 创建 staging 表
CREATE TABLE staging_fix LIKE sales;
-- 2. 加载修正数据
INSERT INTO staging_fix SELECT ... -- 修正后的行
FROM sales PARTITION (p_q4_2024) WHERE ...
JOIN correction_table USING (...);
-- 3. 原子替换
ALTER TABLE sales EXCHANGE PARTITION p_q4_2024 WITH TABLE staging_fix
    WITHOUT VALIDATION;
```

## 性能特征对比

### 元数据操作 vs 数据操作

| 操作 | 数据移动量 | 锁时间 (10GB 分区) | 索引重建 |
|------|-----------|---------------------|----------|
| Oracle EXCHANGE WITHOUT VALIDATION | 0 (零拷贝) | < 1 秒 | LOCAL 索引交换, GLOBAL 标记失效 |
| Oracle EXCHANGE WITH VALIDATION | 0 (但读取全表) | ~分钟 (校验时间) | 同上 |
| SQL Server SWITCH | 0 | < 1 秒 | 索引必须预先匹配 |
| PG ATTACH (无 CHECK 约束) | 0 (但读取全表) | ~分钟 (校验时间) | PG 11+ 自动构建索引 |
| PG ATTACH (有 CHECK 约束) | 0 | < 1 秒 | 同上 |
| PG DETACH | 0 | < 1 秒 (PG 14+ CONCURRENTLY 几乎无锁) | -- |
| MySQL EXCHANGE WITH VALIDATION | 0 (读取全表) | ~分钟 | 索引预先匹配 |
| MySQL EXCHANGE WITHOUT VALIDATION | 0 | < 1 秒 | 索引预先匹配 |
| 传统 INSERT 100GB | 100GB | -- (但全程影响业务) | 实时维护 |
| 传统 DELETE + INSERT 100GB | 200GB IO | -- | 多次重建 |

### 校验开销实测

```
1 亿行 / 50GB 分区:

WITH VALIDATION (默认):
  - 全表扫描 staging 验证分区键
  - 单线程: ~5 分钟
  - 并行扫描: ~1 分钟

WITHOUT VALIDATION + CHECK 约束:
  - 优化器读取约束元数据
  - < 0.1 秒
  - 风险: 应用方必须保证 staging 数据正确

WITHOUT VALIDATION 无 CHECK 约束:
  - 跳过校验, 但元数据中分区不严格 (可能有越界数据)
  - 后续查询可能因分区裁剪错误返回不正确结果
```

## 实现层面的关键设计

### 1. 元数据交换的原子性

```
所有引擎的 EXCHANGE 都需要保证原子性:
  - 主表中分区指针 (data_object_id 等) 与 staging 表的指针交换
  - 通过分布式事务 (单机) 或 catalog 锁保证

Oracle 的实现:
  - 在 dictionary 上短暂排他锁
  - 修改 SYS.TAB$, SYS.IND$ 等系统表的 OBJ#
  - 提交事务 → 切换可见

PostgreSQL 的实现:
  - pg_class 中 relfilenode 字段交换
  - 主表的 partition descriptor 中 oid 替换
```

### 2. 索引的处理策略

```
LOCAL 索引 (随分区移动):
  - Oracle/MySQL/SQL Server/MariaDB/TiDB 都支持
  - EXCHANGE 时索引文件指针随数据一起交换
  - 要求: staging 上的索引必须与分区上的索引完全一致

GLOBAL 索引 (跨分区):
  - 仅 Oracle 显式区分
  - EXCHANGE 后会失效 (USABLE/UNUSABLE 状态)
  - UPDATE GLOBAL INDEXES 选项: 增量更新, 但慢
  - 替代: EXCHANGE 后重建 (REBUILD ... PARTITION ...)

PostgreSQL 的策略:
  - PG 11+ 主表索引会在新分区上自动创建 (如果不存在)
  - ATTACH 时检查 staging 已有索引是否匹配, 不匹配则报错
```

### 3. 校验与跳过校验的权衡

```
WITH VALIDATION:
  +  数据正确性保证
  -  全表扫描开销 (大表上数小时)

WITHOUT VALIDATION + CHECK 约束:
  +  快速 (元数据检查)
  +  仍有正确性保证 (CHECK 约束语义)
  -  CHECK 约束本身需要在 staging 上预先添加

WITHOUT VALIDATION 无约束:
  +  最快
  -  完全依赖应用方保证数据正确
  -  错误数据进入分区后, 可能因分区裁剪导致 SELECT 漏数据
```

### 4. 锁级别的演进

```
Oracle EXCHANGE PARTITION 的锁演进:
  - 8i-11g: 整个交换过程 EXCLUSIVE LOCK
  - 12c+: 大部分时间 ROW EXCLUSIVE, 短暂 EXCLUSIVE 切换
  - 19c+: ONLINE 选项允许并发 DML

PostgreSQL ATTACH/DETACH 的锁演进:
  - PG 10: ACCESS EXCLUSIVE LOCK 全程
  - PG 12-13: ATTACH 仍是 ACCESS EXCLUSIVE
  - PG 14+: DETACH CONCURRENTLY 用 ShareUpdateExclusive
  - PG 15-16: 优化分区裁剪元数据缓存

MySQL EXCHANGE PARTITION 的锁:
  - 5.6-8.0: MDL EXCLUSIVE LOCK (短)
  - 整个交换是元数据操作, 通常 < 1 秒
```

## 关键发现 (Key Findings)

### 1. 历史脉络

- **1999 年 Oracle 8i** 首创 EXCHANGE PARTITION，确立了行业标准
- **2005 年 SQL Server 2005** 跟进，但选择了不同的关键字 (SWITCH)
- **2010 年 DB2 9.7** 加入 ATTACH/DETACH 双向风格
- **2013 年** 是关键年份: MySQL 5.6 和 Hive 0.12 同年加入 EXCHANGE PARTITION
- **2017 年 PostgreSQL 10** 引入声明式分区和 ATTACH PARTITION
- **2018 年 PostgreSQL 11** 加入 DETACH PARTITION
- **2021 年 PostgreSQL 14** 实现 DETACH PARTITION CONCURRENTLY，是真正的产线友好版本

### 2. 设计哲学的两大流派

**Oracle/MySQL/SQL Server 流派 (双向交换)**:
- 概念清晰: "分区与独立表交换"
- 单条 SQL 完成
- 适合 ETL: staging → 主表

**PostgreSQL/DB2 流派 (单向 ATTACH/DETACH)**:
- 更原子化的操作: 解耦"附加"和"脱离"
- 更灵活: 可以单独 DETACH 而不立即 ATTACH 新分区
- 锁友好: PG 14+ 的 CONCURRENTLY 是大表场景的最佳选择

### 3. 校验机制的重要性

**WITHOUT VALIDATION** 几乎是所有引擎的标配选项，原因是：
- 大数据场景下，全表校验耗时数小时
- staging 上的 CHECK 约束 (或应用方的数据正确性保证) 可以替代运行时校验
- 跳过校验后，EXCHANGE 真正成为元数据操作 (毫秒级)

**没有 WITHOUT VALIDATION 的引擎** (如某些版本的 PG 10 ATTACH) 会在大表场景上不可用。

### 4. 索引处理是最大限制

各引擎都需要 staging 表的索引与目标分区**完全一致**:
- Oracle: LOCAL 索引必须一致, GLOBAL 索引交换后失效
- SQL Server: 所有索引必须完全一致 (列、顺序、唯一性、过滤条件)
- PostgreSQL: PG 11+ 自动创建主表索引
- MySQL: 索引必须预先在两表上完全相同

这是 EXCHANGE 操作"看起来简单实际不易"的核心原因——准备一个完全匹配的 staging 表需要细致的工程工作。

### 5. 分布式数据库的挑战

分布式场景 (TiDB, OceanBase, Greenplum) 的 EXCHANGE PARTITION 面临:
- 元数据原子性: 跨节点的 catalog 更新一致性
- 数据分布: staging 数据是否需要 reshuffle 到与目标分区相同的节点
- 全局索引: 维护跨分区的全局索引
- 校验并行化: 大表校验在所有节点并行

### 6. 云数仓的范式转变

Snowflake/BigQuery/Redshift 等云数仓**不提供 EXCHANGE PARTITION**:
- Snowflake 使用 micro-partition 自动管理, 用户无控制权
- BigQuery 是 append-only + clustering, 没有传统分区概念
- 替代方案: CTAS + SWAP, INSERT OVERWRITE, MERGE INTO
- 性能上: 云数仓的存算分离架构使大批量 INSERT 也很快, EXCHANGE 的优势减弱

### 7. Lakehouse 表格式的新范式

Iceberg/Delta Lake/Hudi 提供了**事务级别**的等价能力:
- Iceberg 的 RewriteFiles / ReplacePartitions API: 元数据切换数据指针
- Delta Lake 的 REPLACE WHERE: 原子替换满足条件的行
- Hudi 的 Bulk Insert + Compaction: 异步合并

这些机制虽然不叫 "EXCHANGE PARTITION", 但本质相同: **通过元数据切换实现零拷贝的批量数据更新**。

### 8. 没有 SQL 标准

EXCHANGE PARTITION / SWAP / ATTACH 始终未进入 SQL 标准, 导致:
- 各引擎语法迥异: Oracle 用 EXCHANGE PARTITION, SQL Server 用 SWITCH PARTITION, PostgreSQL 用 ATTACH PARTITION
- 跨引擎迁移困难: ETL 脚本难以移植
- ORM 和工具支持有限: 大多数 ORM 不抽象分区操作

### 9. EXCHANGE 仍然是大表 ETL 的最优解

尽管云原生方案 (CTAS + SWAP) 很流行，但对于**单机/分布式 OLTP/HTAP** 场景:
- Oracle EXCHANGE PARTITION + WITHOUT VALIDATION 仍是 100GB+ 单表加载的最快方案
- PG 14+ ATTACH PARTITION (with CHECK) + DETACH CONCURRENTLY 是 PG 生态的最佳实践
- SQL Server SWITCH PARTITION 是数据仓库 sliding window 模式的核心

### 10. 选型建议

| 场景 | 推荐方案 | 原因 |
|------|---------|------|
| Oracle 数据仓库 | EXCHANGE PARTITION + WITHOUT VALIDATION + LOCAL 索引 | 行业最成熟实现 |
| SQL Server 数据仓库 | SWITCH PARTITION + CHECK 约束 + sliding window | 严格但高性能 |
| PostgreSQL 大表 | ATTACH PARTITION + CHECK 约束; DETACH CONCURRENTLY (PG 14+) | 原子且支持并发 |
| MySQL 数据归档 | EXCHANGE PARTITION + WITHOUT VALIDATION | 简单可靠 |
| Snowflake/BigQuery | CTAS + SWAP / INSERT OVERWRITE | 云数仓范式 |
| Iceberg/Delta Lake | RewriteFiles / REPLACE WHERE | 事务级元数据切换 |
| ClickHouse 时序数据 | MOVE PARTITION + DETACH/ATTACH | 灵活的分区操作 |
| TiDB/OceanBase | EXCHANGE PARTITION (兼容 MySQL/Oracle) | 分布式场景 |

## 参考资料

- Oracle: [ALTER TABLE ... EXCHANGE PARTITION](https://docs.oracle.com/en/database/oracle/oracle-database/19/sqlrf/ALTER-TABLE.html)
- Oracle: [VLDB and Partitioning Guide](https://docs.oracle.com/en/database/oracle/oracle-database/19/vldbg/)
- SQL Server: [ALTER TABLE ... SWITCH](https://learn.microsoft.com/en-us/sql/t-sql/statements/alter-table-transact-sql)
- PostgreSQL: [ALTER TABLE ATTACH/DETACH PARTITION](https://www.postgresql.org/docs/current/sql-altertable.html)
- PostgreSQL: [Table Partitioning](https://www.postgresql.org/docs/current/ddl-partitioning.html)
- PostgreSQL 14 Release Notes: DETACH PARTITION CONCURRENTLY
- MySQL: [Exchanging Partitions and Subpartitions with Tables](https://dev.mysql.com/doc/refman/8.0/en/partitioning-management-exchange.html)
- MariaDB: [Exchanging Partitions and Subpartitions with Tables](https://mariadb.com/kb/en/exchanging-partitions-and-subpartitions-with-tables/)
- DB2: [Attaching and Detaching Data Partitions](https://www.ibm.com/docs/en/db2/11.5?topic=tables-attaching-detaching-data-partitions)
- Greenplum: [ALTER TABLE ... EXCHANGE PARTITION](https://docs.vmware.com/en/VMware-Greenplum/index.html)
- Hive: [ALTER TABLE EXCHANGE PARTITION](https://cwiki.apache.org/confluence/display/Hive/LanguageManual+DDL+AlterTable)
- ClickHouse: [Manipulating Partitions and Parts](https://clickhouse.com/docs/en/sql-reference/statements/alter/partition)
- TiDB: [Partitioning - Exchange Partition](https://docs.pingcap.com/tidb/stable/partitioned-table)
- Vertica: [SWAP_PARTITIONS_BETWEEN_TABLES](https://docs.vertica.com/latest/en/sql-reference/functions/data-management-functions/swap-partitions-between-tables/)
- Doris: [Temporary Partition](https://doris.apache.org/docs/data-table/temp-partition)
- StarRocks: [Temporary Partition](https://docs.starrocks.io/docs/table_design/Temporary_partition/)
- Apache Iceberg: [RewriteFiles API](https://iceberg.apache.org/javadoc/latest/)
- Delta Lake: [REPLACE WHERE](https://docs.delta.io/latest/delta-batch.html)
