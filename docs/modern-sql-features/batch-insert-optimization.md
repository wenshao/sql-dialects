# 批处理 INSERT 优化 (Batch INSERT Optimization)

把 100 万条 `INSERT INTO t VALUES(...)` 改写成 1000 条 1000 行的多值 INSERT，吞吐量通常能提升 50~200 倍——批处理 INSERT 是通过纯 SQL 语句加载数据的最快合法手段，也是任何 SQL 引擎绕不开的核心写入路径。本文聚焦于"in-query"层面的 INSERT 优化模式（多行 VALUES、INSERT...SELECT、prepared batch、direct-path 等），不涉及外部文件加载（COPY、LOAD DATA、BULK INSERT 等），后者参见 [bulk-import-export.md](./bulk-import-export.md)。

## 为什么批处理 INSERT 是最快的合法 SQL 写入方式

把一次插入拆解，单行 INSERT 的成本由以下几部分组成：

1. **网络往返 (RTT)**：每条 SQL 至少一次客户端 → 服务端 → 客户端，本地网络 0.1ms，跨可用区 1ms+，跨地域 50ms+
2. **SQL 解析与优化**：parser、binder、optimizer 重新执行，cache 命中也要 hash 查找
3. **事务开销**：autocommit 模式下每行一次 BEGIN/COMMIT，redo log/WAL fsync 一次
4. **锁与 latch**：buffer pool latch、page latch、index latch 反复获取释放
5. **B+ 树定位**：每行重新从根定位插入位置，无法批量分摊路径成本

将 N 行合并为一条多行 INSERT 可以同时摊薄上述开销：网络 RTT 从 N 次降为 1 次；解析 1 次复用；fsync 1 次；锁路径分摊；B+ 树插入可在叶子页连续填充。这就是为什么所有主流引擎都把"多值 INSERT + prepared statement + 显式事务"列为标准写入优化建议。

但批处理 INSERT 仍受到结构性限制：每条 SQL 都要走完整的 SQL 引擎层（parser、optimizer、executor），即使是直接路径插入也仍然是面向行的 SQL 语义。当数据量超过千万级时，文件级 bulk load（COPY、LOAD DATA、BULK INSERT、Snowpipe、`COPY INTO`）才是更优解。本文边界在此：仅讨论"通过 INSERT 语句"加载数据的优化模式。

## SQL 标准：多行 VALUES 与 DEFAULT VALUES

### SQL:1999 多行 INSERT VALUES

SQL:1999 (ISO/IEC 9075-2, Section 14.8) 正式引入多行 VALUES 语法：

```sql
<insert statement> ::=
    INSERT INTO <table name> [ <column list> ]
    <insert columns and source>

<insert columns and source> ::=
    <from subquery>
  | <from constructor>
  | <from default>

<from constructor> ::=
    [ <left paren> <column name list> <right paren> ]
    <contextually typed table value constructor>

<contextually typed table value constructor> ::=
    VALUES <contextually typed row value expression list>
```

关键点：`<contextually typed row value expression list>` 是 VALUES 后跟一个或多个行表达式的逗号分隔列表，理论上没有行数上限，由实现决定。

```sql
-- SQL:1999 标准多行 INSERT
INSERT INTO orders (id, customer, amount) VALUES
    (1, 'Alice', 100.00),
    (2, 'Bob',   200.00),
    (3, 'Carol', 300.00);
```

### SQL:2003 INSERT ... DEFAULT VALUES

SQL:2003 引入显式的 `DEFAULT VALUES` 形式，允许插入一行并对所有列使用默认值：

```sql
INSERT INTO sequence_table DEFAULT VALUES;
```

这在自增主键 + 默认时间戳的场景下非常有用。

### SQL:2008 之后的扩展

SQL:2008 进一步规范了 `MERGE` 语句（更接近 UPSERT），但批量 UPSERT 在 SQL 标准中至今没有原生的"批量冲突处理"语法——各家方言（`ON CONFLICT`、`ON DUPLICATE KEY UPDATE`、`MERGE`）各行其是。

## 支持矩阵（综合）

### 1. 多行 INSERT VALUES 支持

| 引擎 | 多行 VALUES | 单语句最大行数 | 备注 |
|------|------------|--------------|------|
| PostgreSQL | 是 | 受 `max_stack_depth` 与内存限制 | 实测可达数十万行 |
| MySQL | 是 | 受 `max_allowed_packet` (8.0 默认 64MB) | 单包大小限制 |
| MariaDB | 是 | 受 `max_allowed_packet` (默认 16MB) | 同 MySQL 协议 |
| SQLite | 是 | `SQLITE_MAX_COMPOUND_SELECT` 默认 500 | 3.7.11+ 支持多行 |
| Oracle | 否（需 INSERT ALL） | -- | 标准多值不支持 |
| SQL Server | 是 | 1000 行/语句 | 文档明确限制 |
| DB2 | 是 | 受语句长度限制 (2MB) | LUW |
| Snowflake | 是 | 16384 行/语句 | 推荐用 COPY INTO |
| BigQuery | 是 | DML 语句 1MB | 流式 insert 另算 |
| Redshift | 是 | 受语句长度 16MB | 不推荐大批量 |
| DuckDB | 是 | 无硬限制 | Appender API 更快 |
| ClickHouse | 是 | 无硬限制 (推荐 ≥ 1000 行) | INSERT 是核心写入路径 |
| Trino | 是 | 受 catalog 限制 | 通常用 INSERT ... SELECT |
| Presto | 是 | 同 Trino | -- |
| Spark SQL | 是 | 受 driver 内存 | 用 INSERT...SELECT 更常见 |
| Hive | 是 | 0.14+ | 主要用 INSERT...SELECT |
| Flink SQL | 是 | -- | 流式语义 |
| Databricks | 是 | 同 Spark SQL | -- |
| Teradata | 是 | -- | 多值 INSERT |
| Greenplum | 是 | 受 `max_allowed_packet` 类限制 | 继承 PG |
| CockroachDB | 是 | 受 `sql.defaults.large_full_scan_rows` 等 | 推荐 ≤ 1024 行 |
| TiDB | 是 | 受 `max_allowed_packet` (默认 64MB) | -- |
| OceanBase | 是 | 受 `ob_sql_work_area_percentage` | 兼容 MySQL/Oracle 模式 |
| YugabyteDB | 是 | 继承 PG | -- |
| SingleStore | 是 | -- | 推荐 1000~10000 行/批 |
| Vertica | 是 | -- | 推荐 COPY |
| Impala | 是 | 2.8+ | -- |
| StarRocks | 是 | -- | 推荐 Stream Load |
| Doris | 是 | -- | 推荐 Stream Load |
| MonetDB | 是 | -- | -- |
| CrateDB | 是 | bulk_args API 更快 | -- |
| TimescaleDB | 是 | 继承 PG | -- |
| QuestDB | 是 | -- | ILP 更快 |
| Exasol | 是 | -- | IMPORT 更快 |
| SAP HANA | 是 | -- | -- |
| Informix | 是 | -- | LOAD 更快 |
| Firebird | 否（需 EXECUTE BLOCK） | -- | 标准多值不支持 |
| H2 | 是 | -- | -- |
| HSQLDB | 是 | -- | -- |
| Derby | 是 | 10.6+ | -- |
| Amazon Athena | 否（INSERT 限制） | -- | 推荐 CTAS |
| Azure Synapse | 否（专用池） | -- | 推荐 COPY |
| Google Spanner | 是 | 80000 mutations/事务 | mutation 限制 |
| Materialize | 是 | -- | 流式语义 |
| RisingWave | 是 | -- | 流式语义 |
| InfluxDB (SQL) | 否 | -- | 仅 line protocol |
| Databend | 是 | -- | -- |
| Yellowbrick | 是 | -- | 推荐 LOAD |
| Firebolt | 是 | -- | 推荐 COPY FROM |

> 统计：约 45 个引擎支持 SQL:1999 多行 VALUES，Oracle 与 Firebird 是显著例外（Oracle 用 `INSERT ALL`，Firebird 用 `EXECUTE BLOCK`）。

### 2. INSERT ... SELECT 支持

INSERT ... SELECT 是 SQL:1992 即定义的标准能力，几乎所有 SQL 引擎都支持。差异主要在于：是否支持跨数据库/跨 catalog、是否支持并行执行、是否支持 hint。

| 引擎 | INSERT ... SELECT | 跨库 | 并行执行 | Hint 控制 |
|------|------------------|------|---------|----------|
| PostgreSQL | 是 | 通过 FDW | 9.6+ 并行查询 | -- |
| MySQL | 是 | 否 | 8.0 部分 | 否 |
| MariaDB | 是 | 通过 FederatedX | 否 | 否 |
| SQLite | 是 | ATTACH | 否 | 否 |
| Oracle | 是 | DB Link | 是 | `/*+ APPEND PARALLEL */` |
| SQL Server | 是 | Linked Server | 是 | `WITH (TABLOCK)` |
| DB2 | 是 | 是 | 是 | `INSERT BUFFERED` |
| Snowflake | 是 | 三段式 | 是 | -- |
| BigQuery | 是 | 项目级 | 是 | -- |
| Redshift | 是 | 跨库 (同集群) | 是 | -- |
| DuckDB | 是 | ATTACH | 是 | -- |
| ClickHouse | 是 | 是 | 是 | settings |
| Trino | 是 | 跨 catalog | 是 | session 属性 |
| Presto | 是 | 跨 catalog | 是 | session 属性 |
| Spark SQL | 是 | 跨 catalog | 是 | hint |
| Hive | 是 | 是 | 是 | hint |
| Flink SQL | 是 | 是 | 是 | hint |
| Databricks | 是 | UC 三层 | 是 | hint |
| Teradata | 是 | 是 | 是 | -- |
| Greenplum | 是 | -- | 是 | -- |
| CockroachDB | 是 | -- | 是 | -- |
| TiDB | 是 | -- | 是 | hint |
| OceanBase | 是 | -- | 是 | hint |
| YugabyteDB | 是 | -- | 部分 | -- |
| SingleStore | 是 | -- | 是 | -- |
| Vertica | 是 | -- | 是 | `DIRECT` 提示 |
| Impala | 是 | -- | 是 | -- |
| StarRocks | 是 | -- | 是 | hint |
| Doris | 是 | -- | 是 | hint |
| MonetDB | 是 | -- | 是 | -- |
| CrateDB | 是 | -- | 是 | -- |
| TimescaleDB | 是 | -- | 继承 PG | -- |
| QuestDB | 是 | -- | -- | -- |
| Exasol | 是 | -- | 是 | -- |
| SAP HANA | 是 | -- | 是 | -- |
| Informix | 是 | -- | -- | -- |
| Firebird | 是 | -- | -- | -- |
| H2 | 是 | -- | -- | -- |
| HSQLDB | 是 | -- | -- | -- |
| Derby | 是 | -- | -- | -- |
| Amazon Athena | 是 | 跨 catalog | 是 | -- |
| Azure Synapse | 是 | -- | 是 | `WITH (TABLOCK)` |
| Google Spanner | 是 | -- | 是 | -- |
| Materialize | 是 | -- | -- | -- |
| RisingWave | 是 | -- | -- | -- |
| InfluxDB (SQL) | 否 | -- | -- | -- |
| Databend | 是 | -- | 是 | -- |
| Yellowbrick | 是 | -- | 是 | -- |
| Firebolt | 是 | -- | 是 | -- |

### 3. INSERT ALL / 多表插入

`INSERT ALL` / `INSERT FIRST` 是 Oracle 9i 引入的非标准多表插入语法，允许一次扫描源数据后同时写入多张目标表。

| 引擎 | 多表 INSERT | 语法 | 备注 |
|------|------------|------|------|
| Oracle | 是 | `INSERT ALL ... INTO t1 ... INTO t2 ... SELECT ...` | 9i+ |
| OceanBase | 是 | 同 Oracle | Oracle 模式 |
| DB2 | 部分 | INSERT INTO ... SELECT 的多次扩展 | 不原生 |
| SAP HANA | 部分 | -- | 通过 procedure |
| Teradata | 是 | `INSERT INTO t1 ... INTO t2 ...` | 多表 INSERT |
| 其他 45+ 引擎 | 否 | -- | 需要多个 INSERT 语句 |

### 4. 单 INSERT 语句最大行数限制

| 引擎 | 硬限制 | 软限制（推荐） | 决定因素 |
|------|-------|--------------|---------|
| PostgreSQL | 无硬限制 | 1000~10000 | 内存、parser 栈深度 |
| MySQL | 无硬限制 | 受 `max_allowed_packet` (默认 64MB) | 单包大小 |
| MariaDB | 无 | 受 `max_allowed_packet` (默认 16MB) | 同 MySQL |
| SQLite | 500 复合 SELECT | 500 行 | `SQLITE_MAX_COMPOUND_SELECT` |
| Oracle | 1000 (INSERT ALL) | 1000 | INSERT ALL 限制 |
| SQL Server | 1000 行/VALUES | 1000 | T-SQL 文档明确限制 |
| DB2 | 32767 | 数百~数千 | 语句长度 2MB |
| Snowflake | 16384 行 | 16384 | DML 限制 |
| BigQuery | 1MB DML | ~10000 | 1MB 语句长度 |
| Redshift | 16MB 语句 | ~10000 | 语句长度 |
| DuckDB | 无 | 无 | 内存 |
| ClickHouse | 无 | ≥ 1000 (避免小批) | -- |
| TiDB | 受 `max_allowed_packet` | 数千 | 协议层 |
| CockroachDB | 无 | ≤ 1024 | 事务大小 |
| Spanner | 80000 mutations | 数千 | mutations/txn |

### 5. Prepared Statement 批量执行

prepared statement + 多次 bind 执行是另一类批处理路径，有些数据库提供专门的 batch 执行 API。

| 引擎 | Prepared 协议 | 批量绑定 API | 备注 |
|------|--------------|------------|------|
| PostgreSQL | 是 | libpq `PQexecPrepared` 多次 | JDBC `addBatch()` |
| MySQL | 是 | C API + JDBC `rewriteBatchedStatements` | 服务端 batch |
| MariaDB | 是 | 同 MySQL | 同 |
| SQLite | 是 | `sqlite3_step` + `sqlite3_reset` 复用 | 显式事务 + reset |
| Oracle | 是 | `OCIBindArrayOfStruct` (array binding) | array DML |
| SQL Server | 是 | `SqlBulkCopy` (.NET), TDS RPC batch | -- |
| DB2 | 是 | array insert | -- |
| ClickHouse | 是 | RowBinary 协议 | -- |
| Snowflake | 是 | JDBC batch | -- |
| BigQuery | 否 | -- | REST 协议 |
| Spanner | 是 | mutation batch API | -- |
| CrateDB | 是 | bulk_args | -- |

### 6. Unlogged / 最小日志 INSERT

| 引擎 | 机制 | 触发条件 | 代价 |
|------|------|---------|------|
| PostgreSQL | `UNLOGGED TABLE` (9.1+) | 建表时声明 | 崩溃丢失全部数据 |
| MySQL | -- | -- | -- |
| Oracle | `NOLOGGING` + `/*+ APPEND */` | 表属性 + hint | 介质恢复需重做 |
| SQL Server | minimally logged INSERT | 简单/批量日志恢复 + TABLOCK | 不能 Always-On |
| DB2 | `NOT LOGGED INITIALLY` | 表属性 + 同事务首次 | 恢复需重做 |
| Greenplum | UNLOGGED | 同 PG | -- |
| Vertica | DIRECT 模式 | hint | 跳过 WOS |
| Snowflake | -- (透明) | -- | -- |
| BigQuery | -- (透明) | -- | -- |
| ClickHouse | -- (LSM 天然轻日志) | -- | -- |

### 7. INSERT 与 CTAS / SELECT INTO 的对比

| 引擎 | CREATE TABLE AS SELECT | SELECT INTO | INSERT ... SELECT 优势场景 |
|------|----------------------|-------------|-------------------------|
| PostgreSQL | 是 | 是 (PL/pgSQL 内部含义不同) | 已有表追加 |
| MySQL | 是 | 否 | -- |
| Oracle | 是 | 否 (PL/SQL 独立含义) | -- |
| SQL Server | 否 | 是 (DDL 形式) | -- |
| Snowflake | 是 | -- | -- |
| BigQuery | 是 | -- | -- |
| Redshift | 是 | 是 | -- |
| DuckDB | 是 | -- | -- |

### 8. ON CONFLICT / ON DUPLICATE KEY UPDATE 批量

| 引擎 | 语法 | 批量支持 | 备注 |
|------|------|---------|------|
| PostgreSQL | `INSERT ... ON CONFLICT ... DO UPDATE` | 是 | 9.5+ |
| MySQL | `INSERT ... ON DUPLICATE KEY UPDATE` | 是 | 早期 |
| MariaDB | 同 MySQL | 是 | -- |
| SQLite | `INSERT ... ON CONFLICT` | 是 | 3.24+ |
| Oracle | `MERGE INTO` | 是 | 9i+ |
| SQL Server | `MERGE INTO` | 是 | 2008+ |
| DB2 | `MERGE INTO` | 是 | -- |
| Snowflake | `MERGE INTO` / `INSERT ... OVERWRITE` | 是 | -- |
| BigQuery | `MERGE INTO` | 是 | -- |
| Redshift | `MERGE INTO` (新) | 是 | 2023 GA |
| DuckDB | `INSERT ... ON CONFLICT` | 是 | 0.8+ |
| ClickHouse | `INSERT ... ON DUPLICATE` 否 | -- | ReplacingMergeTree |
| Trino | `MERGE INTO` | 是 | 411+ |
| Spark SQL | `MERGE INTO` | 是 | Delta/Iceberg/Hudi |
| Hive | `MERGE INTO` | 是 | 2.2+ ACID |
| CockroachDB | `INSERT ... ON CONFLICT` | 是 | -- |
| TiDB | `INSERT ... ON DUPLICATE KEY UPDATE` | 是 | MySQL 兼容 |
| OceanBase | 二者皆有 | 是 | 双模式 |
| YugabyteDB | `INSERT ... ON CONFLICT` | 是 | 继承 PG |
| Greenplum | `INSERT ... ON CONFLICT` | 6.0+ | -- |

### 9. INSERT ... RETURNING 批量

| 引擎 | RETURNING | 多行返回 | 备注 |
|------|-----------|--------|------|
| PostgreSQL | 是 | 是 | 8.2+ |
| MariaDB | 是 | 是 | 10.5+ |
| MySQL | 否 | -- | -- |
| Oracle | 是 (RETURNING INTO) | array 形式 | 早期 |
| SQL Server | `OUTPUT` | 是 | 2005+ |
| DB2 | `SELECT FROM FINAL TABLE (INSERT ...)` | 是 | -- |
| SQLite | 是 | 是 | 3.35+ (2021) |
| DuckDB | 是 | 是 | -- |
| Snowflake | 否 (无 RETURNING) | -- | -- |
| BigQuery | 否 | -- | -- |
| CockroachDB | 是 | 是 | -- |
| YugabyteDB | 是 | 是 | -- |
| TimescaleDB | 是 | 是 | 继承 PG |
| Greenplum | 是 | 是 | 继承 PG |
| Firebird | 是 | 部分 | -- |
| H2 | -- | -- | -- |

### 10. 直接路径插入（Direct-Path / Bulk-Logged）

| 引擎 | 机制 | 触发方式 | 关键限制 |
|------|------|---------|---------|
| Oracle | direct-path insert | `/*+ APPEND */` (序列) `/*+ APPEND_VALUES */` (单值) | 串行化、HWM 之上写入 |
| SQL Server | minimally logged | `WITH (TABLOCK)` + 简单/批量日志恢复 | 表锁 |
| DB2 | LOAD from cursor | `LOAD FROM CURSOR` 实用程序 | 非纯 SQL |
| Vertica | DIRECT mode | `INSERT /*+ DIRECT */` | 跳过 WOS 直写 ROS |
| Greenplum | -- (heap 默认即追加) | -- | -- |
| Snowflake | 隐式 micro-partition | 自动 | -- |
| Redshift | -- | 推荐 COPY | -- |
| ClickHouse | LSM 直写 | 默认 | part 太多需 merge |

## 主流引擎深入解析

### MySQL：max_allowed_packet 与 bulk_insert_buffer_size

MySQL 的批处理 INSERT 主要受三个变量制约：

```sql
-- 单个 SQL 包的最大尺寸（含响应包）
SHOW VARIABLES LIKE 'max_allowed_packet';
-- MySQL 5.7 默认 4MB，MySQL 8.0 默认 64MB
-- 超过此值的 INSERT 会报 "MySQL server has gone away" 或 "Packet too large"

-- MyISAM 批量插入缓冲区（对 InnoDB 无效）
SHOW VARIABLES LIKE 'bulk_insert_buffer_size';
-- 默认 8MB，仅 MyISAM 在 INSERT ... SELECT、LOAD DATA、多行 INSERT 时使用

-- InnoDB 关键参数
SHOW VARIABLES LIKE 'innodb_flush_log_at_trx_commit';
-- 默认 1（每次提交 fsync），改为 2 可大幅加速但降低耐久性
```

MySQL 8.0 把 `max_allowed_packet` 默认值从 5.7 的 4MB 提升到 64MB，正是为了支撑更大的批量 INSERT 与 BLOB 写入。客户端侧 JDBC 还需要打开 `rewriteBatchedStatements=true` 才能把 `addBatch()` 的多次 prepared 调用真正合并为单条多值 INSERT 发送给服务端：

```java
// JDBC 连接串
jdbc:mysql://host/db?rewriteBatchedStatements=true&useServerPrepStmts=false
```

不打开此选项时，`PreparedStatement.addBatch()` 仍然会逐条发送，性能与单行无异。

```sql
-- INSERT IGNORE：忽略主键/唯一键冲突
INSERT IGNORE INTO users (id, name) VALUES (1,'a'), (2,'b'), (1,'dup');
-- 第三行被静默忽略，不报错

-- INSERT ... ON DUPLICATE KEY UPDATE
INSERT INTO counters (id, cnt) VALUES (1, 1), (2, 1), (3, 1)
ON DUPLICATE KEY UPDATE cnt = cnt + VALUES(cnt);
-- 8.0.20+ 推荐改用 alias 形式：
INSERT INTO counters (id, cnt) VALUES (1, 1), (2, 1) AS new
ON DUPLICATE KEY UPDATE cnt = cnt + new.cnt;
```

InnoDB 在批量 INSERT 时还有一个重要优化：自增主键的 lock 模式 `innodb_autoinc_lock_mode`，默认 2（interleaved）允许批量分配自增值而无需表级锁。

### PostgreSQL：UNLOGGED、COPY 与 ON CONFLICT

PostgreSQL 在 SQL 批处理上是最接近 SQL 标准且最完整的实现：

```sql
-- UNLOGGED 表（9.1+）：跳过 WAL，崩溃后表被截断但保留 schema
CREATE UNLOGGED TABLE staging_orders (LIKE orders INCLUDING ALL);

-- 批量插入到 UNLOGGED 表，吞吐量通常是 LOGGED 表的 2~3 倍
INSERT INTO staging_orders SELECT * FROM source_orders;

-- 验证后切换为 LOGGED
ALTER TABLE staging_orders SET LOGGED;  -- 此时会重写整张表并写 WAL

-- ON CONFLICT 批量 UPSERT (9.5+)
INSERT INTO orders (id, customer, amount) VALUES
    (1, 'Alice', 100),
    (2, 'Bob',   200),
    (3, 'Carol', 300)
ON CONFLICT (id) DO UPDATE
SET customer = EXCLUDED.customer,
    amount   = EXCLUDED.amount
WHERE orders.amount < EXCLUDED.amount;

-- DO NOTHING 形式：去重插入
INSERT INTO orders (id, customer, amount) VALUES (...)
ON CONFLICT (id) DO NOTHING;

-- RETURNING 批量取回
INSERT INTO orders (customer, amount) VALUES
    ('Alice', 100), ('Bob', 200), ('Carol', 300)
RETURNING id, customer;
```

虽然 `INSERT` 已经很快，但当数据量超过几十万行时，PostgreSQL 的官方推荐仍然是 `COPY FROM STDIN`，比批量 INSERT 还要快 2~3 倍，因为 COPY 走的是专用协议路径，跳过 SQL 解析与行级触发的部分开销。这部分细节参见 [bulk-import-export.md](./bulk-import-export.md)。

### Oracle：INSERT ALL 与 /*+ APPEND */ 直接路径

Oracle 不支持 SQL:1999 的多行 VALUES，但提供了功能更强的 `INSERT ALL`（9i+）：

```sql
-- 多行单表插入（INSERT ALL 实际上是 1 行 1 个 INTO 子句）
INSERT ALL
    INTO orders (id, customer, amount) VALUES (1, 'Alice', 100)
    INTO orders (id, customer, amount) VALUES (2, 'Bob',   200)
    INTO orders (id, customer, amount) VALUES (3, 'Carol', 300)
SELECT 1 FROM dual;

-- 真正的多表 INSERT：从一次 SELECT 同时写多张表
INSERT ALL
    WHEN amount >= 1000 THEN
        INTO big_orders (id, customer, amount) VALUES (id, customer, amount)
    WHEN amount < 1000 THEN
        INTO small_orders (id, customer, amount) VALUES (id, customer, amount)
SELECT id, customer, amount FROM source_orders;

-- INSERT FIRST：每行只走第一个匹配的 WHEN 分支
INSERT FIRST
    WHEN region = 'US' THEN INTO orders_us VALUES (...)
    WHEN region = 'EU' THEN INTO orders_eu VALUES (...)
    ELSE                    INTO orders_other VALUES (...)
SELECT * FROM source_orders;
```

`INSERT ALL` 单语句最多 999 个 INTO 子句（10g 起放宽到 1000），适合中等规模批量插入。

```sql
-- Direct-Path Insert (/*+ APPEND */)，自 Oracle 7.3 起
INSERT /*+ APPEND */ INTO sales SELECT * FROM staging_sales;

-- 单行 VALUES 形式需用 APPEND_VALUES (11.2+)
INSERT /*+ APPEND_VALUES */ INTO sales VALUES (1, '2026-01-01', 100);

-- 配合 NOLOGGING 表实现"几乎不写 redo"
ALTER TABLE sales NOLOGGING;
INSERT /*+ APPEND PARALLEL(sales, 8) */ INTO sales SELECT * FROM staging_sales;
COMMIT;
```

### SQL Server：BULK INSERT 与最小日志

SQL Server 提供最丰富的"最小日志"机制，但触发条件相当严格：

```sql
-- TABLOCK 提示是触发最小日志的关键
INSERT INTO Sales WITH (TABLOCK)
SELECT * FROM Staging.Sales;

-- 多行 VALUES（最多 1000 行）
INSERT INTO Sales (id, customer, amount) VALUES
    (1, 'Alice', 100),
    (2, 'Bob',   200);

-- MERGE 实现批量 UPSERT
MERGE INTO Orders AS T
USING (VALUES (1,'Alice',100), (2,'Bob',200), (3,'Carol',300))
       AS S(id, customer, amount)
ON T.id = S.id
WHEN MATCHED THEN UPDATE SET T.amount = S.amount
WHEN NOT MATCHED THEN INSERT (id, customer, amount)
                      VALUES (S.id, S.customer, S.amount);

-- OUTPUT 子句批量取回（类似 RETURNING）
INSERT INTO Orders (customer, amount)
OUTPUT INSERTED.id, INSERTED.customer
VALUES ('Alice', 100), ('Bob', 200);
```

最小日志的触发条件需要全部满足：

1. 数据库恢复模式为 `SIMPLE` 或 `BULK_LOGGED`
2. 目标表无非聚集索引（或为空表）
3. 使用 `WITH (TABLOCK)` 提示
4. 不在 Always-On 可用性组中
5. 不开启复制或 CDC

任何一项不满足都会退化为完整日志，吞吐量下降一个数量级。

### DB2：INSERT BUFFERED 与 LOAD from cursor

DB2 LUW 提供 `INSERT BUFFERED`（registry 变量 `DB2_LOAD_COPY_NO_OVERRIDE` 与 `DB2_INLIST_TO_NLJN` 的配合），以及通过 `LOAD FROM CURSOR` 把 INSERT...SELECT 转换为 LOAD 实用程序的高级形式：

```sql
-- 创建游标并 LOAD（语法层面是 SQL，但内部走 LOAD 路径）
DECLARE c1 CURSOR FOR SELECT * FROM staging.sales;
LOAD FROM c1 OF CURSOR INSERT INTO sales NONRECOVERABLE;

-- NOT LOGGED INITIALLY：同事务内首次插入不写日志
CREATE TABLE staging_sales (...) NOT LOGGED INITIALLY;
INSERT INTO staging_sales SELECT * FROM source;
COMMIT;
```

`NOT LOGGED INITIALLY` 的代价是：如果该事务回滚或失败，整张表会被标记为不可用并被自动 DROP，因为没有日志可回滚。

### ClickHouse：大批 INSERT 与 async_insert

ClickHouse 是少数把 INSERT 当作核心写入路径的列存引擎。其 LSM (MergeTree) 架构要求 INSERT 尽量批量，每次 INSERT 都会生成一个新的 part，过多小 part 会触发后台 merge 风暴：

```sql
-- 推荐：单条 INSERT 至少包含 1000 行，最好 ≥ 100000 行
INSERT INTO events VALUES
    (1, '2026-04-13 10:00:00', 'click'),
    (2, '2026-04-13 10:00:01', 'view'),
    ...
    (100000, '2026-04-13 11:00:00', 'click');

-- HTTP / Native / RowBinary 协议都支持流式发送大批量
INSERT INTO events FORMAT JSONEachRow
{"id":1,"ts":"2026-04-13 10:00:00","ev":"click"}
{"id":2,"ts":"2026-04-13 10:00:01","ev":"view"}
...
```

对于无法在客户端聚合的场景（例如 IoT 边缘设备每秒一行），21.11 引入的 **async_insert** 把"小批合并"放到服务端：

```sql
-- 会话级开启
SET async_insert = 1;
SET wait_for_async_insert = 1;  -- 0 表示 fire-and-forget

-- 小批 INSERT 会被服务端 buffer，达到阈值后才落 part
SET async_insert_max_data_size = 1000000;       -- 字节
SET async_insert_busy_timeout_ms = 200;          -- 最长等待
SET async_insert_max_query_number = 450;
```

服务端会按 (table, settings, columns, format) 维度合并不同客户端的小 INSERT，大幅降低 part 数量。23.x 起进一步引入 `adaptive_async_insert` 自适应模式。

### Snowflake：多行 INSERT 与 COPY INTO

Snowflake 的多行 INSERT 上限是 16384 行/语句，但官方强烈建议任何超过几万行的数据都用 `COPY INTO ... FROM @stage`，因为 INSERT 会走 query 计费而 COPY 计费更优：

```sql
-- 多行 INSERT
INSERT INTO orders (id, customer, amount) VALUES
    (1, 'Alice', 100),
    (2, 'Bob',   200);

-- INSERT ... SELECT 跨数据库
INSERT INTO prod.public.orders
SELECT * FROM staging.public.orders WHERE order_date = CURRENT_DATE;

-- INSERT OVERWRITE：先 truncate 再 insert
INSERT OVERWRITE INTO daily_summary
SELECT date, COUNT(*) FROM events GROUP BY date;
```

Snowflake 不支持 RETURNING 子句，需要的话需要先 INSERT 然后 SELECT 元数据表 `RESULT_SCAN(LAST_QUERY_ID())`。

### BigQuery：DML INSERT 与流式 INSERT

BigQuery 区分两种"INSERT"：

1. **DML INSERT**：标准 SQL，按 1MB 语句长度限制，按扫描计费，每张表每天最多 1500 个 DML 操作
2. **Streaming INSERT (`tabledata.insertAll`)**：REST API，按"插入字节数"计费（成本约为 DML 的 5 倍），但延迟 < 1s 且无 DML 配额限制
3. **Storage Write API**（推荐替代 streaming insert）：按字节计费但单价更低，支持 exactly-once

```sql
-- DML INSERT
INSERT INTO `project.dataset.orders` (id, customer, amount) VALUES
    (1, 'Alice', 100),
    (2, 'Bob',   200);

-- INSERT ... SELECT
INSERT INTO `project.dataset.orders`
SELECT * FROM `project.staging.orders` WHERE date = CURRENT_DATE();
```

对于真正的大批量加载，BigQuery 推荐 LOAD JOB（GCS 文件 → BQ 表），完全免费（按存储计费）。

## Oracle 直接路径 /*+ APPEND */ 深入解析

Oracle 的 direct-path insert 是 SQL 引擎中最经典的"绕过 buffer cache 的 INSERT"实现，自 7.3 起就存在。它的核心机制如下：

```text
常规 INSERT (conventional path):
  1. 从 free list / ASSM 找有空间的块
  2. 把块读入 buffer cache（可能产生物理 I/O）
  3. 在块内寻找空闲空间，写入行
  4. 更新行目录、列偏移量
  5. 写 redo + undo
  6. 标记块为脏，等 DBWR 刷盘
  7. 行可能写入散布在多个块中（高 HWM 之下）

Direct-path INSERT (/*+ APPEND */):
  1. 跳过 free list，直接在 HWM (High Water Mark) 之上分配新块
  2. 数据块在 PGA 中组装，不进 buffer cache
  3. 整块直接写入数据文件（绕过 DBWR）
  4. 提交时调整 HWM
  5. 索引维护用 mini-load 模式（先排序后追加）
```

### 关键限制

1. **整表锁定**：direct-path insert 会获取目标表的 X 锁（mode 6 TM lock），其它会话无法同时 DML
2. **必须 COMMIT 才能再次 SELECT**：插入完成后到 COMMIT 之前，同一会话也不能 SELECT 该表
3. **不能与触发器、外键引用一起使用**：会自动回退到 conventional path
4. **不能 INSERT INTO 索引组织表 (IOT)**
5. **APPEND_VALUES 仅对单行 VALUES 有效**，多行 VALUES Oracle 本来就不支持

### 与 NOLOGGING 配合

```sql
-- 单独使用 APPEND 仍然写完整 redo
INSERT /*+ APPEND */ INTO sales SELECT * FROM staging;

-- APPEND + NOLOGGING 表才能跳过 redo
ALTER TABLE sales NOLOGGING;
INSERT /*+ APPEND */ INTO sales SELECT * FROM staging;
-- 此时只生成最少量的 redo（数据字典更新），数据本身不写 redo
-- 代价：物理介质恢复时该表数据不可恢复，需要 NOARCHIVELOG 或备份
```

### 并行 direct-path

```sql
-- 8 路并行 direct-path
INSERT /*+ APPEND PARALLEL(sales, 8) */ INTO sales
SELECT /*+ PARALLEL(staging, 8) */ * FROM staging;
```

每个并行 slave 写入自己的 HWM 段，最后 coordinator 合并。这是 Oracle ETL 场景下最快的纯 SQL 写入路径，吞吐量可以接近物理 I/O 极限。

## ClickHouse async_insert 深入解析

`async_insert` 是 ClickHouse 21.11 (2021-11) 引入的功能，用于解决"无法在客户端攒批"场景下的写放大问题。

### 问题背景

ClickHouse 的 MergeTree 引擎是 LSM 结构，每次 INSERT 至少创建一个新 part：

```text
INSERT 1 行 → 1 个 part (元数据 + 1 行的列文件)
INSERT 1 行 → 又 1 个 part
...
INSERT 1 行 → 第 1000 个 part
```

后台 merge 线程必须不停合并这些小 part，CPU 与 I/O 全部消耗在 merge 上。当 part 数超过 `parts_to_throw_insert`（默认 3000）时，新 INSERT 会被直接拒绝，错误信息 `Too many parts`。

### async_insert 的工作机制

```text
客户端 INSERT (行数小)
   │
   ▼
服务端 query_thread 把语句解析后的数据放入 async insert queue
   │
   ▼
按 (database, table, format, settings, columns) 分桶
   │
   ▼
满足任一条件后 flush:
  - async_insert_max_data_size 字节 (默认 10MB)
  - async_insert_busy_timeout_ms 毫秒 (默认 1000ms)
  - async_insert_max_query_number 个查询 (默认 450)
   │
   ▼
合并为单个大 INSERT，生成 1 个 part
```

### 配置示例

```sql
-- 用户级或会话级
SET async_insert = 1;
SET wait_for_async_insert = 1;          -- 客户端是否等待 flush 完成
SET async_insert_max_data_size = 10000000;
SET async_insert_busy_timeout_ms = 1000;

-- 也可写入用户配置文件 users.xml
```

### 一致性权衡

- `wait_for_async_insert = 1`（默认）：客户端等待数据真正写入 part 才返回，提供"at-least-once"语义
- `wait_for_async_insert = 0`：fire-and-forget，吞吐量更高但服务端崩溃可能丢失尚未 flush 的数据
- 23.4+ 引入 `async_insert_use_adaptive_busy_timeout`，根据负载自适应调整 flush 间隔
- 24.x 进一步引入 `async_insert_deduplicate` 保证幂等

### 性能数据（官方基准）

| 模式 | 1 行/INSERT 吞吐 | part 数/分钟 | CPU 使用 |
|------|----------------|------------|---------|
| 同步 INSERT | ~5000 行/秒 | 300000 | 高（merge 占主导） |
| async_insert | ~50000 行/秒 | ~60 | 低 |
| 客户端攒批 (10000 行/INSERT) | ~500000 行/秒 | ~6 | 最低 |

可以看出，async_insert 不能替代客户端攒批，但能在客户端无法攒批时把性能提升一个数量级。

## DuckDB Appender API：API 级批处理

DuckDB 在 SQL 层支持多行 INSERT，但官方推荐高性能写入用 C/C++/Python/R 的 Appender API：

```cpp
duckdb::Appender appender(con, "orders");
for (int i = 0; i < 1000000; i++) {
    appender.AppendRow(i, "customer_" + std::to_string(i), 100.0);
}
appender.Close();
```

Appender 直接写入向量化 column chunk，跳过 SQL parser、binder、optimizer，吞吐量比多行 INSERT 高 5~10 倍。这种"API 级 bulk"在嵌入式数据库（DuckDB、SQLite）中特别常见。

## 关键发现

### 1. 多行 VALUES 是几乎所有引擎都支持的最低公分母

45+ 引擎中，仅 Oracle 与 Firebird 不支持 SQL:1999 的多行 VALUES 语法。Oracle 用 `INSERT ALL`（语义更强但 ~1000 行/语句限制），Firebird 用 PSQL 的 `EXECUTE BLOCK`。这意味着跨引擎数据访问层最容易实现的批处理优化就是"把 N 个单行 INSERT 重写为 1 个多行 INSERT"。

### 2. 客户端协议层的"假批处理"是常见陷阱

JDBC `addBatch()` / .NET `SqlCommand` / Python `executemany()` 等 API 在很多驱动下默认仍然逐条发送，必须显式开启服务端 batch（如 MySQL 的 `rewriteBatchedStatements=true`、PostgreSQL 的 `reWriteBatchedInserts=true`）才能合并为单条多行 INSERT 发送。这是性能调优中最常见的"我以为我在 batch"陷阱。

### 3. INSERT 不是数据加载的最佳路径

当数据量 > 100 万行时，所有主流引擎都有比 INSERT 更快的方案：

- PostgreSQL → `COPY FROM STDIN`（快 2~3x）
- MySQL → `LOAD DATA INFILE`（快 5~10x）
- Oracle → `SQL*Loader` 或 External Table（快 5~10x）
- SQL Server → `BULK INSERT` 或 `bcp`（快 5~10x）
- Snowflake → `COPY INTO @stage`（快 10x，且更便宜）
- BigQuery → LOAD JOB（免费 vs DML 计费）
- ClickHouse → `clickhouse-client --query "INSERT ..." < file`（与 INSERT 等价但走原生协议）

INSERT 优化的真正适用场景是：OLTP 场景下的中等批量（数百到数万行）、需要事务回滚保护、需要 RETURNING、或客户端是应用程序而非 ETL 工具。

### 4. Oracle direct-path 与 SQL Server 最小日志的本质差异

两者都是"少写 redo / log"的优化，但触发条件完全不同：

- Oracle `/*+ APPEND */`：hint 即可触发，但要求表 NOLOGGING 才能真正跳过 redo，恢复风险由 DBA 承担
- SQL Server minimally logged：必须同时满足恢复模式、TABLOCK 提示、无非聚集索引、非 Always-On 等多个条件，规则极复杂，DBA 容易踩坑

如果引擎开发者要实现类似优化，Oracle 的"显式 hint + 表级 NOLOGGING"模型更易理解，SQL Server 的"隐式触发"模型对用户更友好但调试更难。

### 5. ClickHouse async_insert 是"服务端攒批"模式的代表

传统观点认为攒批应该在客户端完成，但当客户端是边缘设备（IoT 网关、移动端）或者无状态函数（Lambda）时，客户端无法保留状态。ClickHouse 21.11 的 async_insert 把这部分逻辑下推到服务端，这是 SQL 引擎在 2020 年代的一个重要新模式。其它 LSM 引擎（StarRocks Stream Load v2、Doris Routine Load）也在跟进类似设计。

### 6. ON CONFLICT / MERGE 的批量语义差异

虽然语法都是"批量 UPSERT"，但语义上有重要差异：

- PostgreSQL `ON CONFLICT`：只能基于唯一约束/排除约束触发，行级冲突
- MySQL `ON DUPLICATE KEY UPDATE`：基于任何唯一键（包括主键），行级冲突
- 标准 SQL `MERGE`：基于任意 ON 条件，可以是非唯一连接，可能有"不确定 MERGE"问题

引擎实现 MERGE 时必须处理"同一行在 source 中匹配多次目标"的情况（standard 要求报错，但 Oracle/SQL Server/Snowflake 行为不一）。这是 MERGE 实现中最微妙的语义点。

### 7. RETURNING 的批量行为分歧

PostgreSQL、SQLite、CockroachDB 等系列把 RETURNING 当成"INSERT 后立即 SELECT"，自然支持多行。Oracle 的 RETURNING INTO 必须搭配 `BULK COLLECT INTO` 数组才能批量取回；SQL Server 用 OUTPUT 子句，可以输出到表变量或临时表。MySQL 至今不支持 RETURNING（8.0 路线图中曾出现但未实现），是主流 OLTP 引擎中最大的缺失。

### 8. 单语句最大行数的"硬限制"分布

| 限制 | 引擎 |
|------|------|
| 1000 行 | SQL Server (T-SQL 文档明确), Oracle INSERT ALL |
| 500 复合 | SQLite (SQLITE_MAX_COMPOUND_SELECT) |
| 16384 行 | Snowflake |
| 1MB 语句 | BigQuery |
| 16MB 语句 | Redshift |
| 64MB 包 | MySQL 8.0 (max_allowed_packet) |
| 80000 mutations/事务 | Spanner |
| 无硬限制 | PostgreSQL, DuckDB, ClickHouse |

引擎设计者在引入新的 INSERT 优化时必须考虑这些限制带来的"切批"逻辑。

### 9. UNLOGGED / 临时表的真实代价

PostgreSQL 的 UNLOGGED 表是最易用的"绕日志"方案，但有两个隐藏成本：

1. 切换为 LOGGED 时（`ALTER TABLE ... SET LOGGED`）会重写整张表并写完整 WAL，大表上可能耗时数小时
2. 复制流不会同步 UNLOGGED 表，主备切换后从库上的 UNLOGGED 表是空的

这两点导致 UNLOGGED 表在生产环境主要用于 staging 而非长期表。

## 总结对比矩阵

### 批处理 INSERT 能力总览

| 能力 | PostgreSQL | MySQL | Oracle | SQL Server | DB2 | Snowflake | ClickHouse | DuckDB | BigQuery |
|------|-----------|-------|--------|------------|-----|-----------|------------|--------|----------|
| 多行 VALUES | 是 | 是 | 否 (INSERT ALL) | 1000 行 | 是 | 16384 行 | 是 | 是 | 是 |
| INSERT...SELECT | 是 | 是 | 是 | 是 | 是 | 是 | 是 | 是 | 是 |
| 多表 INSERT | 否 | 否 | INSERT ALL | 否 | 否 | 否 | 否 | 否 | 否 |
| ON CONFLICT/UPSERT | 是 (9.5+) | 是 | MERGE | MERGE | MERGE | MERGE | -- | 是 | MERGE |
| RETURNING | 是 | 否 | INTO | OUTPUT | FINAL TABLE | 否 | 否 | 是 | 否 |
| Direct-path | -- | -- | /*+APPEND*/ | TABLOCK | LOAD | 自动 | LSM | -- | LOAD JOB |
| Unlogged | 9.1+ | -- | NOLOGGING | 简单恢复 | NOT LOGGED | -- | LSM | -- | -- |
| 异步 INSERT | -- | -- | -- | -- | -- | -- | 21.11+ | -- | streaming |
| 服务端 batch 合并 | -- | -- | array DML | -- | array | -- | async_insert | -- | -- |

### 引擎选型与优化建议

| 场景 | 推荐方案 | 原因 |
|------|---------|------|
| OLTP 中等批量 (100~10000 行) | 多行 INSERT VALUES + 显式事务 | 通用、事务安全 |
| ETL 中等批量 (1万~100万行) | INSERT ... SELECT + 适当 hint | 跳过网络往返 |
| 大批量纯写 (Oracle) | `/*+ APPEND PARALLEL */` + NOLOGGING | 最快纯 SQL 路径 |
| 大批量纯写 (SQL Server) | `WITH (TABLOCK)` + 简单恢复 | 最小日志 |
| 边缘设备小批高频 | ClickHouse async_insert | 服务端攒批 |
| 嵌入式高吞吐 | DuckDB Appender / SQLite step+reset | API 级 bulk |
| 跨表分流 (Oracle) | INSERT ALL / INSERT FIRST | 单次扫描多次写 |
| 幂等批量 UPSERT | PG/MySQL ON CONFLICT, 其他 MERGE | 避免重试逻辑 |
| Snowflake 批量加载 | COPY INTO 而非 INSERT | 计费便宜 10x |
| BigQuery 大批量加载 | LOAD JOB 而非 DML | 完全免费 |

## 参考资料

- SQL:1999 标准: ISO/IEC 9075-2, Section 14.8 (insert statement)
- SQL:2003 标准: ISO/IEC 9075-2 (DEFAULT VALUES 形式)
- PostgreSQL: [INSERT](https://www.postgresql.org/docs/current/sql-insert.html)
- PostgreSQL: [Populating a Database](https://www.postgresql.org/docs/current/populate.html)
- PostgreSQL: [UNLOGGED Tables](https://www.postgresql.org/docs/current/sql-createtable.html#SQL-CREATETABLE-UNLOGGED)
- MySQL: [Bulk Data Loading for InnoDB Tables](https://dev.mysql.com/doc/refman/8.0/en/optimizing-innodb-bulk-data-loading.html)
- MySQL: [INSERT Statement](https://dev.mysql.com/doc/refman/8.0/en/insert.html)
- MySQL: [Configuring max_allowed_packet](https://dev.mysql.com/doc/refman/8.0/en/packet-too-large.html)
- Oracle: [INSERT Statement](https://docs.oracle.com/en/database/oracle/oracle-database/19/sqlrf/INSERT.html)
- Oracle: [Direct-Path INSERT](https://docs.oracle.com/en/database/oracle/oracle-database/19/vldbg/parallel-exec-tips.html#GUID-5A8FF4F3-9C2A-4B0D-9F0F-9E4A12A4D1E8)
- Oracle: [Multitable Inserts (INSERT ALL / INSERT FIRST)](https://docs.oracle.com/en/database/oracle/oracle-database/19/sqlrf/INSERT.html)
- SQL Server: [INSERT (Transact-SQL)](https://learn.microsoft.com/en-us/sql/t-sql/statements/insert-transact-sql)
- SQL Server: [Prerequisites for Minimal Logging in Bulk Import](https://learn.microsoft.com/en-us/sql/relational-databases/import-export/prerequisites-for-minimal-logging-in-bulk-import)
- DB2: [INSERT statement](https://www.ibm.com/docs/en/db2/11.5?topic=statements-insert)
- ClickHouse: [INSERT INTO Statement](https://clickhouse.com/docs/en/sql-reference/statements/insert-into)
- ClickHouse: [Asynchronous Inserts (async_insert)](https://clickhouse.com/docs/en/optimize/asynchronous-inserts)
- Snowflake: [INSERT](https://docs.snowflake.com/en/sql-reference/sql/insert)
- Snowflake: [INSERT (Multi-Row)](https://docs.snowflake.com/en/sql-reference/sql/insert-multi-row)
- BigQuery: [Streaming inserts](https://cloud.google.com/bigquery/docs/streaming-data-into-bigquery)
- BigQuery: [Storage Write API](https://cloud.google.com/bigquery/docs/write-api)
- DuckDB: [Appender](https://duckdb.org/docs/data/appender)
- SQLite: [Multi-row INSERT (3.7.11+)](https://www.sqlite.org/lang_insert.html)
- CockroachDB: [INSERT performance best practices](https://www.cockroachlabs.com/docs/stable/insert.html)
- Spanner: [DML best practices](https://cloud.google.com/spanner/docs/dml-best-practices)
- Vertica: [DIRECT hint](https://docs.vertica.com/latest/en/admin/bulk-loading-data/)
