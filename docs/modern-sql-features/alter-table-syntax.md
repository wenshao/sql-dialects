# ALTER TABLE 语法对比 (ALTER TABLE Syntax)

ALTER TABLE 是 SQL 中最复杂的 DDL 语句之一——不同引擎在列操作、约束管理、在线变更等方面的语法和能力差异巨大，对 SQL 引擎开发者而言，正确处理各引擎的 ALTER TABLE 兼容性是实现跨方言 SQL 工具的核心挑战。

## SQL 标准定义

SQL:2003 标准 (ISO/IEC 9075-2) 定义了 ALTER TABLE 的基本框架，SQL:2016 进一步完善。标准语法如下：

```sql
-- SQL:2003 标准 ALTER TABLE 语法
ALTER TABLE table_name
    ADD [ COLUMN ] column_name data_type [ column_constraint ... ]
  | DROP [ COLUMN ] column_name [ CASCADE | RESTRICT ]
  | ALTER [ COLUMN ] column_name SET DEFAULT default_value
  | ALTER [ COLUMN ] column_name DROP DEFAULT
  | ALTER [ COLUMN ] column_name SET NOT NULL
  | ALTER [ COLUMN ] column_name DROP NOT NULL
  | ALTER [ COLUMN ] column_name SET DATA TYPE data_type
  | ADD table_constraint
  | DROP CONSTRAINT constraint_name [ CASCADE | RESTRICT ]
```

关键语义要点：

1. **COLUMN 关键字可选**：`ADD COLUMN col INT` 和 `ADD col INT` 等价
2. **CASCADE / RESTRICT**：DROP 操作时控制级联行为（标准默认 RESTRICT）
3. **SET DATA TYPE**：标准用 `SET DATA TYPE` 而非 `MODIFY` 或 `ALTER TYPE`
4. **无 RENAME**：SQL 标准并未定义 RENAME COLUMN 和 RENAME TABLE（各引擎自行扩展）
5. **无 IF EXISTS**：标准未定义条件 DDL，这是各引擎的常见扩展

## 支持矩阵

### 1. ADD COLUMN 语法

| 引擎 | ADD COLUMN | ADD (省略 COLUMN) | 多列 ADD | IF NOT EXISTS | FIRST / AFTER | 版本 |
|------|:---------:|:-----------------:|:--------:|:-------------:|:-------------:|------|
| PostgreSQL | 是 | 是 | 是 (多条 ADD) | 9.6+ | 不支持 | 8.0+ |
| MySQL | 是 | 是 | 是 (多条 ADD) | 不支持 | **FIRST / AFTER** | 3.22+ |
| MariaDB | 是 | 是 | 是 (多条 ADD) | 10.0+ | **FIRST / AFTER** | 5.1+ |
| SQLite | 是 | 是 | 不支持 | 不支持 | 不支持 | 3.2.0+ |
| Oracle | 不支持 (仅 ADD) | 是 | **ADD (col1, col2)** | 不支持 | 不支持 | 8i+ |
| SQL Server | 是 | 是 | 是 (多列) | 不支持 | 不支持 | 6.0+ |
| DB2 | 是 | 是 | 是 | 不支持 | 不支持 | 9.7+ |
| Snowflake | 是 | 是 | 是 (多条 ADD) | 是 | 不支持 | GA |
| BigQuery | 是 | 不支持 | 是 (多列) | 是 | 不支持 | GA |
| Redshift | 是 | 是 | 是 (多条 ADD) | 不支持 | 不支持 | GA |
| DuckDB | 是 | 是 | 是 (多条 ADD) | 是 | 不支持 | 0.3.0+ |
| ClickHouse | 是 | 是 | 是 (多条 ADD) | 是 | **FIRST / AFTER** | 1.1+ |
| Trino | 是 | 是 | 不支持 | 是 | 不支持 | 351+ |
| Presto | 是 | 是 | 不支持 | 不支持 | 不支持 | 0.200+ |
| Spark SQL | 是 | 是 | **ADD COLUMNS (col1, col2)** | 不支持 | **FIRST / AFTER** (3.0+) | 2.0+ |
| Hive | 是 | 是 | **ADD COLUMNS (col1, col2)** | 不支持 | **AFTER** (不支持 FIRST) | 0.14+ |
| Flink SQL | 是 | 是 | 是 | 不支持 | **FIRST / AFTER** | 1.13+ |
| Databricks | 是 | 是 | **ADD COLUMNS (col1, col2)** | 不支持 | **FIRST / AFTER** | Runtime 7.0+ |
| Teradata | 是 | 是 | 是 | 不支持 | 不支持 | 13.0+ |
| Greenplum | 是 | 是 | 是 (多条 ADD) | 是 | 不支持 | 5.0+ |
| CockroachDB | 是 | 是 | 是 (多条 ADD) | 是 | 不支持 | 1.0+ |
| TiDB | 是 | 是 | 是 (多条 ADD) | 不支持 | **FIRST / AFTER** | 2.0+ |
| OceanBase | 是 | 是 | 是 | 部分 | **FIRST / AFTER** (MySQL 模式) | 3.x+ |
| YugabyteDB | 是 | 是 | 是 (多条 ADD) | 是 | 不支持 | 2.0+ |
| SingleStore | 是 | 是 | 是 (多条 ADD) | 不支持 | **AFTER** | 6.0+ |
| Vertica | 是 | 是 | 是 (多条 ADD) | 不支持 | 不支持 | 7.0+ |
| Impala | 是 | 是 | **ADD COLUMNS (col1, col2)** | 不支持 | 不支持 | 2.0+ |
| StarRocks | 是 | 是 | 是 (多条 ADD) | 不支持 | **AFTER** | 2.0+ |
| Doris | 是 | 是 | 是 (多条 ADD) | 不支持 | **AFTER** | 1.0+ |
| MonetDB | 是 | 是 | 是 | 不支持 | 不支持 | 11.19+ |
| CrateDB | 是 | 是 | 是 (多条 ADD) | 不支持 | 不支持 | 2.0+ |
| TimescaleDB | 是 | 是 | 是 (多条 ADD) | 9.6+ | 不支持 | 1.0+ |
| QuestDB | 是 | 是 | 是 (多条 ADD) | 不支持 | 不支持 | 6.0+ |
| Exasol | 是 | 是 | 是 (多列) | 不支持 | 不支持 | 6.0+ |
| SAP HANA | 是 | 是 | **ADD (col1, col2)** | 不支持 | 不支持 | 1.0+ |
| Informix | 是 | 是 | **ADD (col1, col2)** | 不支持 | **BEFORE** | 9.0+ |
| Firebird | 是 | 不支持 | 不支持 (每次一列) | 不支持 | 不支持 | 1.5+ |
| H2 | 是 | 是 | 是 | 是 | **FIRST / AFTER** (1.4+) | 1.0+ |
| HSQLDB | 是 | 是 | 是 | 不支持 | **BEFORE** | 2.0+ |
| Derby | 是 | 是 | 不支持 | 不支持 | 不支持 | 10.1+ |
| Amazon Athena | 是 | 是 | **ADD COLUMNS (col1, col2)** | 不支持 | 不支持 | v2+ |
| Azure Synapse | 是 | 是 | 是 (多列) | 不支持 | 不支持 | GA |
| Google Spanner | 是 | 是 | 是 (多条 ADD) | 是 | 不支持 | GA |
| Materialize | 是 | 是 | 是 (多条 ADD) | 不支持 | 不支持 | 0.26+ |
| RisingWave | 是 | 是 | 是 (多条 ADD) | 不支持 | 不支持 | 0.18+ |
| InfluxDB | -- | -- | -- | -- | -- | 不支持 ALTER TABLE |
| DatabendDB | 是 | 是 | 是 (多条 ADD) | 不支持 | 不支持 | 0.8+ |
| Yellowbrick | 是 | 是 | 是 (多条 ADD) | 不支持 | 不支持 | 4.0+ |
| Firebolt | 是 | 是 | 是 (多条 ADD) | 不支持 | 不支持 | GA |

> **FIRST / AFTER 说明**：MySQL 系引擎（MySQL、MariaDB、TiDB、OceanBase MySQL 模式）允许在 ADD COLUMN 时指定列的物理位置（`ADD COLUMN col INT AFTER existing_col` 或 `ADD COLUMN col INT FIRST`）。标准 SQL 中列顺序无语义意义，大多数引擎将新列追加到末尾。

### 2. DROP COLUMN 支持

| 引擎 | DROP COLUMN | IF EXISTS | 多列 DROP | CASCADE / RESTRICT | 备注 |
|------|:----------:|:---------:|:---------:|:-----------------:|------|
| PostgreSQL | 是 | 9.6+ | 是 | 是 | 标记 attisdropped, 不重写表 |
| MySQL | 是 | 不支持 | 8.0+ (多条) | 不支持 | 重建表 (8.0.29+ INSTANT) |
| MariaDB | 是 | 10.0+ | 是 (多条) | 不支持 | INSTANT (10.3.2+) |
| SQLite | **3.35.0+** | 不支持 | 不支持 | 不支持 | 3.35.0 前不支持 DROP COLUMN |
| Oracle | 是 | 不支持 | **DROP (col1, col2)** | 是 (CASCADE CONSTRAINTS) | 支持 SET UNUSED |
| SQL Server | 是 | 不支持 | 是 (多列) | 不支持 | 需先删依赖约束 |
| DB2 | 是 | 不支持 | 是 | 是 | 需 REORG 后生效 |
| Snowflake | 是 | 是 | 是 (多条) | 不支持 | 即时元数据操作 |
| BigQuery | 是 | 是 | 是 (多列) | 不支持 | 即时元数据操作 |
| Redshift | 是 | 不支持 | 是 (多条) | 是 | 标记删除, VACUUM 回收 |
| DuckDB | 是 | 是 | 是 (多条) | 是 | 即时操作 |
| ClickHouse | 是 | 是 | 是 (多条) | 不支持 | 异步 mutation |
| Trino | 是 | 是 | 不支持 | 不支持 | 取决于 connector |
| Presto | 是 | 不支持 | 不支持 | 不支持 | 取决于 connector |
| Spark SQL | 是 | 不支持 | **DROP COLUMNS (col1, col2)** | 不支持 | Delta Lake 3.0+ |
| Hive | **部分** | 不支持 | 不支持 | 不支持 | 需 REPLACE COLUMNS 变通 |
| Flink SQL | 是 | 不支持 | 是 | 不支持 | 取决于 connector |
| Databricks | 是 | 不支持 | **DROP COLUMNS (col1, col2)** | 不支持 | Delta Lake |
| Teradata | 是 | 不支持 | 不支持 | 不支持 | 需处理多列索引 |
| Greenplum | 是 | 是 | 是 (多条) | 是 | 继承 PostgreSQL |
| CockroachDB | 是 | 是 | 是 (多条) | 是 | 异步 GC 回收 |
| TiDB | 是 | 不支持 | 是 (多条) | 不支持 | Online DDL |
| OceanBase | 是 | 部分 | 是 | 不支持 | MySQL/Oracle 双模式 |
| YugabyteDB | 是 | 是 | 是 (多条) | 是 | 继承 PostgreSQL |
| SingleStore | 是 | 不支持 | 是 (多条) | 不支持 | 需重建表 |
| Vertica | 是 | 不支持 | 是 (多条) | 是 | 标记删除 |
| Impala | 不支持 | -- | -- | -- | 需 REPLACE COLUMNS 变通 |
| StarRocks | 是 | 不支持 | 是 (多条) | 不支持 | 异步 Schema Change |
| Doris | 是 | 不支持 | 是 (多条) | 不支持 | 异步 Schema Change |
| MonetDB | 是 | 不支持 | 不支持 | 是 | 需无依赖 |
| CrateDB | 不支持 | -- | -- | -- | 不支持 DROP COLUMN |
| TimescaleDB | 是 | 9.6+ | 是 (多条) | 是 | 继承 PostgreSQL |
| QuestDB | 不支持 | -- | -- | -- | 不支持 DROP COLUMN |
| Exasol | 是 | 不支持 | 是 | 不支持 | 即时操作 |
| SAP HANA | 是 | 不支持 | **DROP (col1, col2)** | 是 | 列存即时, 行存重建 |
| Informix | 是 | 不支持 | **DROP (col1, col2)** | 不支持 | 需 ALTER FRAGMENT 配合 |
| Firebird | 是 | 不支持 | 不支持 | 不支持 | 每次一列 |
| H2 | 是 | 是 | 是 | 是 | 1.4+ |
| HSQLDB | 是 | 不支持 | 是 | 是 | 2.0+ |
| Derby | 不支持 | -- | -- | -- | 不支持 DROP COLUMN |
| Amazon Athena | 不支持 | -- | -- | -- | Hive 兼容, 不支持 DROP |
| Azure Synapse | 是 | 不支持 | 是 (多列) | 不支持 | 分布式重建 |
| Google Spanner | 是 | 是 | 是 (多条) | 不支持 | 后台异步清理 |
| Materialize | 不支持 | -- | -- | -- | 流处理引擎限制 |
| RisingWave | 不支持 | -- | -- | -- | 流处理引擎限制 |
| InfluxDB | -- | -- | -- | -- | 不支持 ALTER TABLE |
| DatabendDB | 是 | 不支持 | 是 (多条) | 不支持 | 即时元数据操作 |
| Yellowbrick | 是 | 不支持 | 是 | 不支持 | 标记删除 |
| Firebolt | 是 | 不支持 | 是 | 不支持 | 即时操作 |

> **SQLite 历史**：SQLite 直到 3.35.0 (2021-03-12) 才支持 DROP COLUMN，之前唯一的变通方法是重建整张表（CREATE TABLE new ... + INSERT INTO new SELECT ... + DROP TABLE old + ALTER TABLE new RENAME TO old）。

### 3. RENAME COLUMN / RENAME TABLE

| 引擎 | RENAME COLUMN | RENAME TABLE | 语法 | 版本 |
|------|:------------:|:------------:|------|------|
| PostgreSQL | 是 | 是 | `RENAME COLUMN old TO new` / `RENAME TO new_name` | 7.4+ / 7.4+ |
| MySQL | **8.0+** | 是 | `RENAME COLUMN old TO new` / `RENAME TO new_name` | 8.0+ / 3.22+ |
| MariaDB | **10.5.2+** | 是 | `RENAME COLUMN old TO new` / `RENAME TO new_name` | 10.5.2+ / 5.1+ |
| SQLite | **3.25.0+** | 是 | `RENAME COLUMN old TO new` / `RENAME TO new_name` | 3.25.0+ / 2.0+ |
| Oracle | 是 | **RENAME old TO new** | `RENAME COLUMN old TO new` / `RENAME old_table TO new_table` | 9iR2+ |
| SQL Server | **sp_rename** | **sp_rename** | `EXEC sp_rename 'table.old', 'new', 'COLUMN'` | 6.0+ |
| DB2 | 是 | 是 | `RENAME COLUMN old TO new` / `RENAME TABLE old TO new` | 9.7+ |
| Snowflake | 是 | 是 | `RENAME COLUMN old TO new` / `RENAME TO new_name` | GA |
| BigQuery | 是 | 不支持 | `RENAME COLUMN old TO new` | GA |
| Redshift | 是 | 是 | `RENAME COLUMN old TO new` / `ALTER TABLE ... RENAME TO` | GA |
| DuckDB | 是 | 是 | `RENAME COLUMN old TO new` / `RENAME TO new_name` | 0.3.0+ |
| ClickHouse | 是 | 是 | `RENAME COLUMN old TO new` / `RENAME TABLE old TO new` | 20.4+ |
| Trino | 是 | 是 | `RENAME COLUMN old TO new` / `RENAME TO new_name` | 351+ |
| Presto | 是 | 是 | `RENAME COLUMN old TO new` / `RENAME TO new_name` | 0.200+ |
| Spark SQL | 是 | 不支持 | `RENAME COLUMN old TO new` | 3.0+ (Delta) |
| Hive | 不支持 | 不支持 | 需 `CHANGE COLUMN old new type` 变通 | -- |
| Flink SQL | 是 | 不支持 | `RENAME old TO new` | 1.14+ |
| Databricks | 是 | 不支持 | `RENAME COLUMN old TO new` | Runtime 10.4+ |
| Teradata | 是 | 不支持 | `RENAME old TO new` | 14.0+ |
| Greenplum | 是 | 是 | `RENAME COLUMN old TO new` / `RENAME TO new_name` | 5.0+ |
| CockroachDB | 是 | 是 | `RENAME COLUMN old TO new` / `RENAME TO new_name` | 1.0+ |
| TiDB | 是 | 是 | `RENAME COLUMN old TO new` (5.3+) / `RENAME TO new_name` | 5.3+ / 2.0+ |
| OceanBase | 是 | 是 | 兼容 MySQL / Oracle 对应语法 | 3.x+ |
| YugabyteDB | 是 | 是 | `RENAME COLUMN old TO new` / `RENAME TO new_name` | 2.0+ |
| SingleStore | 不支持 | 是 | 需 `CHANGE COLUMN` 变通 / `RENAME TO new_name` | -- / 6.0+ |
| Vertica | 是 | 不支持 | `RENAME COLUMN old TO new` | 9.0+ |
| Impala | 不支持 | 是 | 需 `CHANGE COLUMN` / `RENAME TO new_name` | -- / 2.0+ |
| StarRocks | 不支持 | 是 | 不支持 RENAME COLUMN / `RENAME new_name` | -- / 2.0+ |
| Doris | 不支持 | 是 | 不支持 RENAME COLUMN / `RENAME new_name` | -- / 1.0+ |
| MonetDB | 是 | 是 | `RENAME COLUMN old TO new` / `RENAME TO new_name` | 11.30+ |
| CrateDB | 不支持 | 是 | 不支持 RENAME COLUMN / `RENAME TO new_name` | -- / 4.0+ |
| TimescaleDB | 是 | 是 | 继承 PostgreSQL | 1.0+ |
| QuestDB | 是 | 是 | `RENAME COLUMN old TO new` / 需重建 | 6.5+ |
| Exasol | 是 | 是 | `RENAME COLUMN old TO new` / `RENAME TO new_name` | 6.0+ |
| SAP HANA | 是 | 是 | `RENAME COLUMN old TO new` / `RENAME TO new_name` | 2.0+ |
| Informix | 是 | 是 | `RENAME COLUMN old TO new` / `RENAME TO new_name` | 11.50+ |
| Firebird | 是 | 不支持 | `ALTER COLUMN old TO new` (注意语法差异) | 2.5+ |
| H2 | 是 | 是 | `RENAME COLUMN old TO new` / `RENAME TO new_name` | 1.4+ |
| HSQLDB | 是 | 是 | `ALTER COLUMN old RENAME TO new` / `RENAME TO new_name` | 2.0+ |
| Derby | 不支持 | 不支持 | 不支持 RENAME COLUMN/TABLE | -- |
| Amazon Athena | 不支持 | 不支持 | Hive 兼容, 不支持 RENAME | -- |
| Azure Synapse | **sp_rename** | **sp_rename** | 继承 SQL Server 语法 | GA |
| Google Spanner | 是 | 不支持 | `RENAME COLUMN old TO new` | GA |
| Materialize | 不支持 | 不支持 | 不支持 RENAME | -- |
| RisingWave | 不支持 | 不支持 | 不支持 RENAME | -- |
| InfluxDB | -- | -- | 不支持 ALTER TABLE | -- |
| DatabendDB | 是 | 是 | `RENAME COLUMN old TO new` / `RENAME TO new_name` | 0.9+ |
| Yellowbrick | 是 | 是 | `RENAME COLUMN old TO new` / `RENAME TO new_name` | 4.0+ |
| Firebolt | 是 | 是 | `RENAME COLUMN old TO new` / `RENAME TO new_name` | GA |

### 4. ALTER / MODIFY 列类型

各引擎用于修改列数据类型的关键字差异极大：

| 引擎 | 语法关键字 | 示例 | 限制 | 版本 |
|------|----------|------|------|------|
| PostgreSQL | `ALTER COLUMN col SET DATA TYPE` / `ALTER COLUMN col TYPE` | `ALTER COLUMN age TYPE BIGINT` | 可能需重写表; 兼容转换免重写 | 8.0+ |
| MySQL | `MODIFY COLUMN` / `CHANGE COLUMN` | `MODIFY COLUMN age BIGINT` | CHANGE 可同时改名; 通常重建表 | 3.22+ |
| MariaDB | `MODIFY COLUMN` / `CHANGE COLUMN` | `MODIFY COLUMN age BIGINT` | 同 MySQL | 5.1+ |
| SQLite | 不支持 | -- | 需重建表变通 | -- |
| Oracle | `MODIFY` | `MODIFY (age NUMBER(10))` | 支持扩大精度; 缩小需列为空 | 8i+ |
| SQL Server | `ALTER COLUMN` | `ALTER COLUMN age BIGINT` | 可能丢失约束; 需先删依赖 | 6.0+ |
| DB2 | `ALTER COLUMN col SET DATA TYPE` | `ALTER COLUMN age SET DATA TYPE BIGINT` | 需 REORG | 9.7+ |
| Snowflake | 部分 | `ALTER COLUMN col SET DATA TYPE` | **仅支持 VARCHAR 增大长度和 NUMBER 增大精度** | GA |
| BigQuery | `ALTER COLUMN col SET DATA TYPE` | `ALTER COLUMN age SET DATA TYPE INT64` | 仅支持安全扩宽 (INT64->FLOAT64 等) | GA |
| Redshift | `ALTER COLUMN col TYPE` | `ALTER COLUMN age TYPE BIGINT` | 仅支持扩大 VARCHAR 长度 | GA |
| DuckDB | `ALTER COLUMN col SET DATA TYPE` / `ALTER COLUMN col TYPE` | `ALTER COLUMN age TYPE BIGINT` | 支持任意兼容类型转换 | 0.8.0+ |
| ClickHouse | `MODIFY COLUMN` | `MODIFY COLUMN age Int64` | 异步 mutation; 支持任意转换 | 1.1+ |
| Trino | 不支持 | -- | 无 ALTER COLUMN TYPE | -- |
| Presto | 不支持 | -- | 无 ALTER COLUMN TYPE | -- |
| Spark SQL | `ALTER COLUMN col TYPE` | `ALTER COLUMN age TYPE BIGINT` | Delta Lake 3.0+; 仅安全扩宽 | 3.0+ |
| Hive | `CHANGE COLUMN` | `CHANGE COLUMN age age BIGINT` | 需重复列名; 仅 ORC/Parquet | 0.14+ |
| Flink SQL | `MODIFY` | `MODIFY col BIGINT` | 取决于 connector | 1.14+ |
| Databricks | `ALTER COLUMN col TYPE` | `ALTER COLUMN age TYPE BIGINT` | 仅安全扩宽 | Runtime 10.4+ |
| Teradata | 不支持 | -- | 需 DROP + ADD 变通 | -- |
| Greenplum | `ALTER COLUMN col TYPE` | `ALTER COLUMN age TYPE BIGINT` | 继承 PostgreSQL | 5.0+ |
| CockroachDB | `ALTER COLUMN col SET DATA TYPE` | `ALTER COLUMN age SET DATA TYPE INT8` | 实验性; 部分类型限制 | 21.1+ |
| TiDB | `MODIFY COLUMN` / `CHANGE COLUMN` | `MODIFY COLUMN age BIGINT` | Online DDL; 部分类型变更限制 | 5.0+ |
| OceanBase | `MODIFY` / `MODIFY COLUMN` | 兼容 MySQL/Oracle 语法 | 与兼容模式相关 | 3.x+ |
| YugabyteDB | `ALTER COLUMN col TYPE` | `ALTER COLUMN age TYPE BIGINT` | 继承 PostgreSQL; 部分限制 | 2.6+ |
| SingleStore | `MODIFY COLUMN` | `MODIFY COLUMN age BIGINT` | 与 MySQL 兼容 | 7.0+ |
| Vertica | `ALTER COLUMN col SET DATA TYPE` | `ALTER COLUMN age SET DATA TYPE BIGINT` | 仅支持兼容扩宽 | 9.0+ |
| Impala | 不支持 | -- | 需 REPLACE COLUMNS 变通 | -- |
| StarRocks | `MODIFY COLUMN` | `MODIFY COLUMN age BIGINT` | 异步 Schema Change; 仅安全扩宽 | 2.0+ |
| Doris | `MODIFY COLUMN` | `MODIFY COLUMN age BIGINT` | 异步 Schema Change; 仅安全扩宽 | 1.0+ |
| MonetDB | `ALTER COLUMN col SET DATA TYPE` | `ALTER COLUMN age SET DATA TYPE BIGINT` | 有限的类型转换 | 11.30+ |
| CrateDB | 不支持 | -- | 不支持改列类型 | -- |
| TimescaleDB | `ALTER COLUMN col TYPE` | 继承 PostgreSQL | 继承 PostgreSQL | 1.0+ |
| QuestDB | 不支持 | -- | 时序引擎限制 | -- |
| Exasol | `ALTER COLUMN col` | `ALTER COLUMN age BIGINT` | 支持扩宽 | 6.0+ |
| SAP HANA | `ALTER (col type)` | `ALTER (age BIGINT)` | 仅安全扩宽 | 1.0+ |
| Informix | `MODIFY` | `MODIFY (age BIGINT)` | 仅兼容类型 | 9.0+ |
| Firebird | `ALTER COLUMN col TYPE` | `ALTER COLUMN age TYPE BIGINT` | 兼容类型转换 | 2.5+ |
| H2 | `ALTER COLUMN col SET DATA TYPE` | `ALTER COLUMN age SET DATA TYPE BIGINT` | 任意类型 | 1.4+ |
| HSQLDB | `ALTER COLUMN col SET DATA TYPE` | `ALTER COLUMN age SET DATA TYPE BIGINT` | 兼容转换 | 2.0+ |
| Derby | `ALTER COLUMN col SET DATA TYPE` | `ALTER COLUMN age SET DATA TYPE BIGINT` | 仅 VARCHAR 增大 | 10.2+ |
| Amazon Athena | 不支持 | -- | Hive 兼容, 不支持改类型 | -- |
| Azure Synapse | `ALTER COLUMN` | `ALTER COLUMN age BIGINT` | 继承 SQL Server 语法 | GA |
| Google Spanner | `ALTER COLUMN col type` | `ALTER COLUMN age INT64` | 仅安全扩宽 | GA |
| Materialize | 不支持 | -- | 流处理引擎限制 | -- |
| RisingWave | 不支持 | -- | 流处理引擎限制 | -- |
| InfluxDB | -- | -- | 不支持 ALTER TABLE | -- |
| DatabendDB | `MODIFY COLUMN` | `MODIFY COLUMN age BIGINT` | 兼容类型转换 | 0.9+ |
| Yellowbrick | `ALTER COLUMN col TYPE` | `ALTER COLUMN age TYPE BIGINT` | 兼容扩宽 | 4.0+ |
| Firebolt | `ALTER COLUMN col TYPE` | `ALTER COLUMN age TYPE BIGINT` | 兼容扩宽 | GA |

### 5. ADD / DROP CONSTRAINT

| 引擎 | ADD PRIMARY KEY | ADD FOREIGN KEY | ADD UNIQUE | ADD CHECK | DROP CONSTRAINT | 命名约束 |
|------|:--------------:|:--------------:|:----------:|:---------:|:--------------:|:--------:|
| PostgreSQL | 是 | 是 | 是 | 是 | 是 | 是 |
| MySQL | 是 | 是 | 是 | 是 (8.0.16+) | 是 | 是 |
| MariaDB | 是 | 是 | 是 | 是 (10.2.1+) | 是 | 是 |
| SQLite | 不支持 | 不支持 | 不支持 | 不支持 | 不支持 | 不支持 |
| Oracle | 是 | 是 | 是 | 是 | 是 | 是 |
| SQL Server | 是 | 是 | 是 | 是 | 是 | 是 |
| DB2 | 是 | 是 | 是 | 是 | 是 | 是 |
| Snowflake | 是 | 是 | 是 | 不支持 | 是 | 是 |
| BigQuery | 是 | 是 | 不支持 | 不支持 | 是 | 是 |
| Redshift | 是 | 是 | 是 | 不支持 | 是 | 是 |
| DuckDB | 是 | 是 | 是 | 是 | 是 | 是 |
| ClickHouse | 不支持 | 不支持 | 不支持 | 不支持 | 不支持 | 不支持 |
| Trino | 不支持 | 不支持 | 不支持 | 不支持 | 不支持 | 不支持 |
| Presto | 不支持 | 不支持 | 不支持 | 不支持 | 不支持 | 不支持 |
| Spark SQL | 不支持 | 不支持 | 不支持 | 是 (Delta 3.0+) | 不支持 | 部分 |
| Hive | 不支持 | 不支持 | 不支持 | 不支持 | 不支持 | 不支持 |
| Flink SQL | 是 | 不支持 | 是 | 不支持 | 是 | 是 |
| Databricks | 不支持 | 不支持 | 不支持 | 是 (Delta 3.0+) | 是 | 部分 |
| Teradata | 是 | 是 | 是 | 是 | 是 | 是 |
| Greenplum | 是 | 是 | 是 | 是 | 是 | 是 |
| CockroachDB | 是 | 是 | 是 | 是 | 是 | 是 |
| TiDB | 是 | 是 | 是 | 不支持 | 是 | 是 |
| OceanBase | 是 | 是 | 是 | 是 | 是 | 是 |
| YugabyteDB | 是 | 是 | 是 | 是 | 是 | 是 |
| SingleStore | 是 | 不支持 | 是 | 不支持 | 是 | 是 |
| Vertica | 是 | 是 | 是 | 是 | 是 | 是 |
| Impala | 是 | 是 | 不支持 | 不支持 | 是 | 是 |
| StarRocks | 不支持 | 不支持 | 不支持 | 不支持 | 不支持 | 不支持 |
| Doris | 不支持 | 不支持 | 不支持 | 不支持 | 不支持 | 不支持 |
| MonetDB | 是 | 是 | 是 | 是 | 是 | 是 |
| CrateDB | 是 | 不支持 | 不支持 | 是 | 是 | 是 |
| TimescaleDB | 是 | 是 | 是 | 是 | 是 | 是 |
| QuestDB | 不支持 | 不支持 | 不支持 | 不支持 | 不支持 | 不支持 |
| Exasol | 是 | 是 | 不支持 | 不支持 | 是 | 是 |
| SAP HANA | 是 | 是 | 是 | 是 | 是 | 是 |
| Informix | 是 | 是 | 是 | 是 | 是 | 是 |
| Firebird | 是 | 是 | 是 | 是 | 是 | 是 |
| H2 | 是 | 是 | 是 | 是 | 是 | 是 |
| HSQLDB | 是 | 是 | 是 | 是 | 是 | 是 |
| Derby | 是 | 是 | 是 | 是 | 是 | 是 |
| Amazon Athena | 不支持 | 不支持 | 不支持 | 不支持 | 不支持 | 不支持 |
| Azure Synapse | 是 | 是 | 是 | 是 | 是 | 是 |
| Google Spanner | 是 | 是 | 是 | 是 | 是 | 是 |
| Materialize | 不支持 | 不支持 | 不支持 | 不支持 | 不支持 | 不支持 |
| RisingWave | 不支持 | 不支持 | 不支持 | 不支持 | 不支持 | 不支持 |
| InfluxDB | -- | -- | -- | -- | -- | -- |
| DatabendDB | 不支持 | 不支持 | 不支持 | 不支持 | 不支持 | 不支持 |
| Yellowbrick | 是 | 是 | 是 | 是 | 是 | 是 |
| Firebolt | 是 | 不支持 | 是 | 不支持 | 是 | 是 |

> **分析型引擎约束**：ClickHouse、StarRocks、Doris 等 OLAP 引擎不支持传统约束（PRIMARY KEY、FOREIGN KEY、UNIQUE、CHECK），它们通过表模型（如 MergeTree、Duplicate Key Model）在引擎层面保证数据组织，而非通过 DDL 约束。

### 6. ADD / DROP INDEX

| 引擎 | ADD INDEX (内联) | CREATE INDEX (独立) | DROP INDEX | 备注 |
|------|:---------------:|:------------------:|:----------:|------|
| PostgreSQL | 不支持 | 是 | `DROP INDEX` | CREATE INDEX CONCURRENTLY 不阻塞写 |
| MySQL | **ADD INDEX** | 是 | **DROP INDEX** / `ALTER TABLE DROP INDEX` | 内联和独立均支持 |
| MariaDB | **ADD INDEX** | 是 | **DROP INDEX** / `ALTER TABLE DROP INDEX` | 同 MySQL |
| SQLite | 不支持 | 是 | `DROP INDEX` | 仅独立语法 |
| Oracle | 不支持 | 是 | `DROP INDEX` | ALTER TABLE 不支持 ADD INDEX |
| SQL Server | 不支持 | 是 | `DROP INDEX` | 需独立 CREATE/DROP INDEX |
| DB2 | 不支持 | 是 | `DROP INDEX` | 需独立 CREATE/DROP INDEX |
| Snowflake | -- | -- | -- | **无二级索引**; 自动 micro-partition 裁剪 |
| BigQuery | -- | -- | -- | **无二级索引**; 使用 SEARCH INDEX (GA) |
| Redshift | -- | -- | -- | **无二级索引**; 使用排序键 (SORTKEY) |
| DuckDB | 不支持 | 是 | `DROP INDEX` | ART 索引 |
| ClickHouse | **ADD INDEX** | 不支持 | **DROP INDEX** | 数据跳过索引 (skip index), 非传统 B-tree |
| Trino | 不支持 | 不支持 | 不支持 | 查询引擎, 不管理索引 |
| Presto | 不支持 | 不支持 | 不支持 | 查询引擎, 不管理索引 |
| Spark SQL | 不支持 | 不支持 | 不支持 | 不支持索引 |
| Hive | 不支持 | 是 (有限) | 是 | 仅 Compact/Bitmap Index |
| Flink SQL | 不支持 | 不支持 | 不支持 | 流处理, 不管理索引 |
| Databricks | 不支持 | 不支持 | 不支持 | 使用 Z-Order / Liquid Clustering |
| Teradata | 不支持 | 是 | `DROP INDEX` | 独立语法 |
| Greenplum | 不支持 | 是 | `DROP INDEX` | 继承 PostgreSQL |
| CockroachDB | **ADD INDEX** | 是 | **DROP INDEX** | 内联和独立均支持 |
| TiDB | **ADD INDEX** | 是 | **DROP INDEX** / `ALTER TABLE DROP INDEX` | MySQL 兼容; Online DDL |
| OceanBase | **ADD INDEX** | 是 | **DROP INDEX** | MySQL/Oracle 双模式 |
| YugabyteDB | 不支持 | 是 | `DROP INDEX` | 继承 PostgreSQL |
| SingleStore | **ADD INDEX** | 是 | **DROP INDEX** | MySQL 兼容 |
| Vertica | 不支持 | 不支持 | 不支持 | 使用 Projection 代替索引 |
| Impala | 不支持 | 不支持 | 不支持 | 不支持索引 |
| StarRocks | **ADD INDEX** | 是 | **DROP INDEX** | Bitmap Index |
| Doris | **ADD INDEX** | 是 | **DROP INDEX** | Bitmap/Inverted Index |
| MonetDB | 不支持 | 是 | `DROP INDEX` | 自动索引管理 |
| CrateDB | 不支持 | 不支持 | 不支持 | 使用列存储优化 |
| TimescaleDB | 不支持 | 是 | `DROP INDEX` | 继承 PostgreSQL |
| QuestDB | 不支持 | 不支持 | 不支持 | 使用 designated timestamp 索引 |
| Exasol | 不支持 | 不支持 | 不支持 | 无索引, 列存储自动优化 |
| SAP HANA | **ADD INDEX** | 是 | **DROP INDEX** | 内联和独立 |
| Informix | **ADD INDEX** (部分) | 是 | `DROP INDEX` | 独立语法为主 |
| Firebird | 不支持 | 是 | `DROP INDEX` | 独立语法 |
| H2 | 不支持 | 是 | `DROP INDEX` | 独立语法 |
| HSQLDB | 不支持 | 是 | `DROP INDEX` | 独立语法 |
| Derby | 不支持 | 是 | `DROP INDEX` | 独立语法 |
| Amazon Athena | 不支持 | 不支持 | 不支持 | 查询引擎 |
| Azure Synapse | 不支持 | 是 | `DROP INDEX` | Clustered Columnstore Index |
| Google Spanner | 不支持 | 是 | `DROP INDEX` | 独立 CREATE/DROP INDEX |
| Materialize | 不支持 | 是 | `DROP INDEX` | 用于 Arrangement 优化 |
| RisingWave | 不支持 | 是 | `DROP INDEX` | 用于物化视图优化 |
| InfluxDB | -- | -- | -- | 不支持 ALTER TABLE |
| DatabendDB | 不支持 | 是 | `DROP INDEX` | Aggregating Index |
| Yellowbrick | 不支持 | 是 | `DROP INDEX` | 独立语法 |
| Firebolt | **ADD INDEX** | 是 | **DROP INDEX** | Aggregating Index |

### 7. ALTER 列 DEFAULT 值

| 引擎 | SET DEFAULT | DROP DEFAULT | 语法 | 版本 |
|------|:----------:|:------------:|------|------|
| PostgreSQL | 是 | 是 | `ALTER COLUMN col SET DEFAULT val` / `DROP DEFAULT` | 7.1+ |
| MySQL | 是 | 是 | `ALTER COLUMN col SET DEFAULT val` / `DROP DEFAULT` | 4.0+ |
| MariaDB | 是 | 是 | `ALTER COLUMN col SET DEFAULT val` / `DROP DEFAULT` | 5.1+ |
| SQLite | 不支持 | 不支持 | 需重建表 | -- |
| Oracle | 是 | 是 | `MODIFY col DEFAULT val` / `MODIFY col DEFAULT NULL` | 8i+ |
| SQL Server | 是 | 是 | `ADD DEFAULT val FOR col` / `DROP CONSTRAINT` | 6.0+ |
| DB2 | 是 | 是 | `ALTER COLUMN col SET DEFAULT val` / `DROP DEFAULT` | 9.7+ |
| Snowflake | 是 | 是 | `ALTER COLUMN col SET DEFAULT val` / `DROP DEFAULT` | GA |
| BigQuery | 是 | 是 | `ALTER COLUMN col SET DEFAULT val` / `DROP DEFAULT` | GA |
| Redshift | 是 | 是 | `ALTER COLUMN col DEFAULT val` | GA |
| DuckDB | 是 | 是 | `ALTER COLUMN col SET DEFAULT val` / `DROP DEFAULT` | 0.5.0+ |
| ClickHouse | 是 | 是 | `MODIFY COLUMN col DEFAULT val` | 18.1+ |
| Trino | 不支持 | 不支持 | 不支持修改默认值 | -- |
| Presto | 不支持 | 不支持 | 不支持修改默认值 | -- |
| Spark SQL | 不支持 | 不支持 | 不支持 DEFAULT (3.4+ 部分) | -- |
| Hive | 不支持 | 不支持 | 不支持 DEFAULT | -- |
| Flink SQL | 不支持 | 不支持 | 不支持修改默认值 | -- |
| Databricks | 不支持 | 不支持 | 不支持 DEFAULT | -- |
| Teradata | 是 | 是 | `ADD col DEFAULT val` (需 DROP+ADD 变通) | 13.0+ |
| Greenplum | 是 | 是 | 继承 PostgreSQL | 5.0+ |
| CockroachDB | 是 | 是 | `ALTER COLUMN col SET DEFAULT val` / `DROP DEFAULT` | 1.0+ |
| TiDB | 是 | 是 | `ALTER COLUMN col SET DEFAULT val` / `DROP DEFAULT` | 3.0+ |
| OceanBase | 是 | 是 | 兼容 MySQL/Oracle 语法 | 3.x+ |
| YugabyteDB | 是 | 是 | 继承 PostgreSQL | 2.0+ |
| SingleStore | 是 | 是 | `ALTER COLUMN col SET DEFAULT val` / `DROP DEFAULT` | 7.0+ |
| Vertica | 是 | 是 | `ALTER COLUMN col SET DEFAULT val` / `DROP DEFAULT` | 7.0+ |
| Impala | 不支持 | 不支持 | 不支持修改默认值 | -- |
| StarRocks | 不支持 | 不支持 | 不支持 ALTER DEFAULT | -- |
| Doris | 不支持 | 不支持 | 不支持 ALTER DEFAULT | -- |
| MonetDB | 是 | 是 | `ALTER COLUMN col SET DEFAULT val` / `DROP DEFAULT` | 11.19+ |
| CrateDB | 不支持 | 不支持 | 不支持修改默认值 | -- |
| TimescaleDB | 是 | 是 | 继承 PostgreSQL | 1.0+ |
| QuestDB | 不支持 | 不支持 | 不支持修改默认值 | -- |
| Exasol | 是 | 是 | `ALTER COLUMN col DEFAULT val` | 6.0+ |
| SAP HANA | 是 | 是 | `ALTER (col type DEFAULT val)` | 1.0+ |
| Informix | 是 | 是 | `MODIFY (col DEFAULT val)` | 9.0+ |
| Firebird | 是 | 是 | `ALTER COLUMN col SET DEFAULT val` / `DROP DEFAULT` | 2.0+ |
| H2 | 是 | 是 | `ALTER COLUMN col SET DEFAULT val` / `DROP DEFAULT` | 1.0+ |
| HSQLDB | 是 | 是 | `ALTER COLUMN col SET DEFAULT val` / `DROP DEFAULT` | 2.0+ |
| Derby | 是 | 是 | `ALTER COLUMN col DEFAULT val` / `DROP DEFAULT` | 10.1+ |
| Amazon Athena | 不支持 | 不支持 | 不支持 ALTER DEFAULT | -- |
| Azure Synapse | 是 | 是 | 继承 SQL Server 语法 | GA |
| Google Spanner | 是 | 是 | `ALTER COLUMN col SET DEFAULT val` / `DROP DEFAULT` | GA |
| Materialize | 不支持 | 不支持 | 不支持修改默认值 | -- |
| RisingWave | 不支持 | 不支持 | 不支持修改默认值 | -- |
| InfluxDB | -- | -- | 不支持 ALTER TABLE | -- |
| DatabendDB | 不支持 | 不支持 | 不支持 ALTER DEFAULT | -- |
| Yellowbrick | 是 | 是 | `ALTER COLUMN col SET DEFAULT val` / `DROP DEFAULT` | 4.0+ |
| Firebolt | 不支持 | 不支持 | 不支持 ALTER DEFAULT | -- |

### 8. ALTER 列 NULL / NOT NULL

| 引擎 | SET NOT NULL | DROP NOT NULL | 语法 |
|------|:-----------:|:------------:|------|
| PostgreSQL | 是 | 是 | `ALTER COLUMN col SET NOT NULL` / `DROP NOT NULL` |
| MySQL | 部分 | 部分 | 需 `MODIFY COLUMN col type NOT NULL` (重写整列定义) |
| MariaDB | 部分 | 部分 | 同 MySQL, 需 `MODIFY COLUMN` |
| SQLite | 不支持 | 不支持 | 需重建表 |
| Oracle | 是 | 是 | `MODIFY col NOT NULL` / `MODIFY col NULL` |
| SQL Server | 部分 | 部分 | `ALTER COLUMN col type NOT NULL` (需重写完整类型) |
| DB2 | 是 | 是 | `ALTER COLUMN col SET NOT NULL` / `DROP NOT NULL` |
| Snowflake | 是 | 是 | `ALTER COLUMN col SET NOT NULL` / `DROP NOT NULL` |
| BigQuery | 不支持 | 是 | `ALTER COLUMN col DROP NOT NULL` (仅 DROP) |
| Redshift | 不支持 | 不支持 | 需重建表 |
| DuckDB | 是 | 是 | `ALTER COLUMN col SET NOT NULL` / `DROP NOT NULL` |
| ClickHouse | 不支持 | 不支持 | 使用 Nullable(T) 类型定义 |
| Trino | 不支持 | 是 | `ALTER COLUMN col DROP NOT NULL` (部分 connector) |
| Presto | 不支持 | 不支持 | 不支持修改可空性 |
| Spark SQL | 不支持 | 不支持 | 不支持 ALTER NULL |
| Hive | 不支持 | 不支持 | 不支持 NOT NULL 约束 |
| Flink SQL | 是 | 是 | `MODIFY col type NOT NULL` / `MODIFY col type` |
| Databricks | 不支持 | 不支持 | 不支持 ALTER NULL |
| Teradata | 是 | 是 | `ALTER col NOT NULL` / `ALTER col NULL` |
| Greenplum | 是 | 是 | 继承 PostgreSQL |
| CockroachDB | 是 | 是 | `ALTER COLUMN col SET NOT NULL` / `DROP NOT NULL` |
| TiDB | 部分 | 部分 | 需 `MODIFY COLUMN` (MySQL 兼容) |
| OceanBase | 部分 | 部分 | 兼容 MySQL/Oracle 语法 |
| YugabyteDB | 是 | 是 | 继承 PostgreSQL |
| SingleStore | 部分 | 部分 | 需 `MODIFY COLUMN` (MySQL 兼容) |
| Vertica | 是 | 是 | `ALTER COLUMN col SET NOT NULL` / `DROP NOT NULL` |
| Impala | 不支持 | 不支持 | 不支持修改可空性 |
| StarRocks | 不支持 | 不支持 | 通过建表定义控制 |
| Doris | 不支持 | 不支持 | 通过建表定义控制 |
| MonetDB | 是 | 是 | `ALTER COLUMN col SET NOT NULL` / `DROP NOT NULL` |
| CrateDB | 不支持 | 不支持 | 不支持修改可空性 |
| TimescaleDB | 是 | 是 | 继承 PostgreSQL |
| QuestDB | 不支持 | 不支持 | 不支持修改可空性 |
| Exasol | 不支持 | 不支持 | 需重建列 |
| SAP HANA | 是 | 是 | `ALTER (col type NOT NULL)` / `ALTER (col type NULL)` |
| Informix | 是 | 是 | `MODIFY (col NOT NULL)` / `MODIFY (col type)` |
| Firebird | 是 | 是 | `ALTER COLUMN col NOT NULL` / `ALTER COLUMN col DROP NOT NULL` (3.0+) |
| H2 | 是 | 是 | `ALTER COLUMN col SET NOT NULL` / `DROP NOT NULL` |
| HSQLDB | 是 | 是 | `ALTER COLUMN col SET NOT NULL` / `SET NULL` |
| Derby | 是 | 是 | `ALTER COLUMN col NOT NULL` / `NULL` |
| Amazon Athena | 不支持 | 不支持 | 不支持修改可空性 |
| Azure Synapse | 部分 | 部分 | `ALTER COLUMN col type NOT NULL` (同 SQL Server) |
| Google Spanner | 是 | 是 | `ALTER COLUMN col type NOT NULL` / `ALTER COLUMN col type` |
| Materialize | 不支持 | 不支持 | 不支持 |
| RisingWave | 不支持 | 不支持 | 不支持 |
| InfluxDB | -- | -- | 不支持 ALTER TABLE |
| DatabendDB | 不支持 | 不支持 | 不支持修改可空性 |
| Yellowbrick | 不支持 | 不支持 | 需重建列 |
| Firebolt | 是 | 是 | `ALTER COLUMN col SET NOT NULL` / `DROP NOT NULL` |

> **MySQL / SQL Server 的 NULL 修改陷阱**：这两个引擎需要在修改可空性时重写完整的列定义（包括类型、长度等），不能单独设置 NOT NULL。例如 MySQL 需要 `MODIFY COLUMN age INT NOT NULL`，如果只写 `MODIFY COLUMN age NOT NULL` 会报语法错误。

### 9. Online DDL / 非阻塞 ALTER 支持

| 引擎 | Online ADD COLUMN | Online DROP COLUMN | Online 改类型 | Online ADD INDEX | 机制 |
|------|:----------------:|:------------------:|:------------:|:---------------:|------|
| PostgreSQL | 是 (11+, 带 DEFAULT) | 是 (即时) | 不支持 (需 ACCESS EXCLUSIVE) | `CREATE INDEX CONCURRENTLY` | 元数据即时修改 |
| MySQL | **INSTANT** (8.0.12+) | **INSTANT** (8.0.29+) | 不支持 (COPY) | **INPLACE, LOCK=NONE** (5.6+) | INSTANT/INPLACE/COPY 算法 |
| MariaDB | **INSTANT** (10.3.2+) | **INSTANT** (10.3.2+) | 不支持 (COPY) | **NOCOPY** (10.3+) | INSTANT/NOCOPY/INPLACE/COPY |
| SQLite | 不支持 | 不支持 | 不支持 | 不支持 | 无 Online DDL |
| Oracle | 是 (部分) | 是 (SET UNUSED + DROP) | 不支持 | **ONLINE** (11g+) | Edition-Based Redefinition |
| SQL Server | 是 | 是 (需先删约束) | 不支持 | **ONLINE=ON** (Enterprise) | Online Index Operations |
| DB2 | 是 | 是 (需 REORG) | 不支持 | 是 | ADMIN_MOVE_TABLE |
| Snowflake | 是 (即时) | 是 (即时) | -- | -- | 元数据操作; 无索引 |
| BigQuery | 是 (即时) | 是 (即时) | 部分 | -- | 元数据操作; 无传统索引 |
| Redshift | 是 | 是 | 不支持 | -- | 无索引; SORTKEY 需 VACUUM |
| DuckDB | 是 (即时) | 是 (即时) | 是 | 是 | 单进程嵌入式, 无并发问题 |
| ClickHouse | 是 (即时) | 是 (异步 mutation) | 是 (异步) | 是 (即时) | 异步 mutation 后台执行 |
| Trino | -- | -- | -- | -- | 查询引擎, 不管理存储 |
| Presto | -- | -- | -- | -- | 查询引擎, 不管理存储 |
| Spark SQL | -- | -- | -- | -- | 取决于底层存储格式 |
| Hive | -- | -- | -- | -- | 元数据操作为主 |
| Flink SQL | -- | -- | -- | -- | 流处理, Schema Evolution |
| Databricks | 是 (Delta) | 是 (Delta) | 部分 | -- | Delta Lake Protocol |
| Teradata | 是 | 不支持 | 不支持 | 是 | 并行 DDL |
| Greenplum | 是 | 是 | 不支持 | `CREATE INDEX CONCURRENTLY` | 继承 PostgreSQL |
| CockroachDB | 是 (即时) | 是 (GC 异步) | 部分 | 是 (后台) | 分布式 Schema Change |
| TiDB | **是 (Online DDL)** | **是** | **部分** | **是** | DDL Owner + 多阶段协调 |
| OceanBase | 是 | 是 | 部分 | 是 | Online DDL |
| YugabyteDB | 是 | 是 | 部分 | 是 (后台) | 分布式 Schema Change |
| SingleStore | 是 | 是 (重建) | 不支持 | 是 | Online ADD COLUMN 无锁 |
| Vertica | 是 | 是 | 不支持 | -- | Projection 管理 |
| Impala | -- | -- | -- | -- | 元数据操作 |
| StarRocks | 是 (异步) | 是 (异步) | 部分 (异步) | 是 (异步) | 异步 Schema Change |
| Doris | 是 (异步) | 是 (异步) | 部分 (异步) | 是 (异步) | 异步 Schema Change |
| MonetDB | 是 | 是 | 不支持 | 是 | 列存即时操作 |
| CrateDB | 是 | 不支持 | 不支持 | 不支持 | 分布式限制 |
| TimescaleDB | 是 (继承 PG) | 是 | 不支持 | `CONCURRENTLY` | 继承 PostgreSQL |
| QuestDB | 是 | 不支持 | 不支持 | 不支持 | 追加写入优化 |
| Exasol | 是 | 是 | 不支持 | 不支持 | 列存即时操作 |
| SAP HANA | 是 | 是 | 部分 | 是 | 列存即时; 行存需锁 |
| Informix | 是 | 是 | 不支持 | 是 | ALTER IN PLACE |
| Firebird | 不支持 | 不支持 | 不支持 | 不支持 | 需独占访问 |
| H2 | 是 | 是 | 是 | 是 | 嵌入式, 轻量锁 |
| HSQLDB | 是 | 是 | 是 | 是 | 嵌入式, 轻量锁 |
| Derby | 不支持 | 不支持 | 不支持 | 不支持 | 需表级锁 |
| Amazon Athena | -- | -- | -- | -- | 查询引擎 |
| Azure Synapse | 是 | 是 | 不支持 | 是 | 分布式重建 |
| Google Spanner | 是 (即时) | 是 (后台) | 部分 | 是 (后台) | 分布式 Schema Change |
| Materialize | -- | -- | -- | -- | 流处理限制 |
| RisingWave | -- | -- | -- | -- | 流处理限制 |
| InfluxDB | -- | -- | -- | -- | 不支持 ALTER TABLE |
| DatabendDB | 是 | 是 | 部分 | 是 | 元数据操作 |
| Yellowbrick | 是 | 是 | 不支持 | 是 | 分布式 DDL |
| Firebolt | 是 | 是 | 部分 | 是 | 云原生即时操作 |

### 10. IF EXISTS / IF NOT EXISTS 子句

| 引擎 | ALTER TABLE IF EXISTS | ADD COLUMN IF NOT EXISTS | DROP COLUMN IF EXISTS | 版本 |
|------|:--------------------:|:-----------------------:|:--------------------:|------|
| PostgreSQL | 9.6+ | 9.6+ | 9.6+ | 9.6+ |
| MySQL | 不支持 | 不支持 | 不支持 | -- |
| MariaDB | 10.0+ | 10.0+ | 10.0+ | 10.0+ |
| SQLite | 不支持 | 不支持 | 不支持 | -- |
| Oracle | 不支持 | 不支持 | 不支持 | -- |
| SQL Server | 不支持 | 不支持 | 不支持 | -- |
| DB2 | 不支持 | 不支持 | 不支持 | -- |
| Snowflake | 是 | 是 | 是 | GA |
| BigQuery | 是 | 是 | 是 | GA |
| Redshift | 不支持 | 不支持 | 不支持 | -- |
| DuckDB | 是 | 是 | 是 | 0.5.0+ |
| ClickHouse | 是 | 是 | 是 | 20.1+ |
| Trino | 是 | 是 | 是 | 351+ |
| Presto | 不支持 | 不支持 | 不支持 | -- |
| Spark SQL | 不支持 | 不支持 | 不支持 | -- |
| Hive | 不支持 | 不支持 | 不支持 | -- |
| Flink SQL | 不支持 | 不支持 | 不支持 | -- |
| Databricks | 不支持 | 不支持 | 不支持 | -- |
| Teradata | 不支持 | 不支持 | 不支持 | -- |
| Greenplum | 9.6+ | 是 | 是 | 6.0+ |
| CockroachDB | 是 | 是 | 是 | 1.0+ |
| TiDB | 不支持 | 是 | 不支持 | 5.0+ |
| OceanBase | 不支持 | 不支持 | 不支持 | -- |
| YugabyteDB | 是 | 是 | 是 | 2.0+ |
| SingleStore | 不支持 | 不支持 | 不支持 | -- |
| Vertica | 不支持 | 不支持 | 不支持 | -- |
| Impala | 不支持 | 不支持 | 不支持 | -- |
| StarRocks | 不支持 | 不支持 | 不支持 | -- |
| Doris | 不支持 | 不支持 | 不支持 | -- |
| MonetDB | 不支持 | 不支持 | 不支持 | -- |
| CrateDB | 不支持 | 不支持 | 不支持 | -- |
| TimescaleDB | 9.6+ | 9.6+ | 9.6+ | 继承 PG |
| QuestDB | 不支持 | 不支持 | 不支持 | -- |
| Exasol | 不支持 | 不支持 | 不支持 | -- |
| SAP HANA | 不支持 | 不支持 | 不支持 | -- |
| Informix | 不支持 | 不支持 | 不支持 | -- |
| Firebird | 不支持 | 不支持 | 不支持 | -- |
| H2 | 是 | 是 | 是 | 1.4+ |
| HSQLDB | 不支持 | 不支持 | 不支持 | -- |
| Derby | 不支持 | 不支持 | 不支持 | -- |
| Amazon Athena | 不支持 | 不支持 | 不支持 | -- |
| Azure Synapse | 不支持 | 不支持 | 不支持 | -- |
| Google Spanner | 是 | 是 | 是 | GA |
| Materialize | 不支持 | 不支持 | 不支持 | -- |
| RisingWave | 不支持 | 不支持 | 不支持 | -- |
| InfluxDB | -- | -- | -- | -- |
| DatabendDB | 不支持 | 不支持 | 不支持 | -- |
| Yellowbrick | 不支持 | 不支持 | 不支持 | -- |
| Firebolt | 不支持 | 不支持 | 不支持 | -- |

## 各引擎语法详解

### PostgreSQL

```sql
-- ADD COLUMN
ALTER TABLE orders ADD COLUMN status VARCHAR(20) DEFAULT 'pending';
ALTER TABLE orders ADD COLUMN IF NOT EXISTS priority INT;

-- DROP COLUMN
ALTER TABLE orders DROP COLUMN IF EXISTS legacy_field CASCADE;

-- RENAME
ALTER TABLE orders RENAME COLUMN status TO order_status;
ALTER TABLE orders RENAME TO customer_orders;

-- 修改类型 (SET DATA TYPE / TYPE)
ALTER TABLE orders ALTER COLUMN amount SET DATA TYPE NUMERIC(12,2);
ALTER TABLE orders ALTER COLUMN amount TYPE BIGINT USING amount::BIGINT;
-- USING 子句指定转换表达式, 是 PostgreSQL 的独特能力

-- 修改 DEFAULT
ALTER TABLE orders ALTER COLUMN status SET DEFAULT 'new';
ALTER TABLE orders ALTER COLUMN status DROP DEFAULT;

-- 修改 NOT NULL
ALTER TABLE orders ALTER COLUMN customer_id SET NOT NULL;
ALTER TABLE orders ALTER COLUMN notes DROP NOT NULL;

-- 约束管理
ALTER TABLE orders ADD CONSTRAINT orders_pk PRIMARY KEY (id);
ALTER TABLE orders ADD CONSTRAINT fk_customer FOREIGN KEY (customer_id) REFERENCES customers(id);
ALTER TABLE orders ADD CONSTRAINT uq_order_no UNIQUE (order_no);
ALTER TABLE orders ADD CONSTRAINT chk_amount CHECK (amount > 0);
ALTER TABLE orders DROP CONSTRAINT chk_amount;

-- 多操作合并 (单条 ALTER TABLE 多个子句)
ALTER TABLE orders
    ADD COLUMN created_at TIMESTAMP DEFAULT NOW(),
    ADD COLUMN updated_at TIMESTAMP,
    DROP COLUMN IF EXISTS old_field,
    ALTER COLUMN amount SET NOT NULL;
```

### MySQL

```sql
-- ADD COLUMN (支持 FIRST / AFTER 定位)
ALTER TABLE orders ADD COLUMN status VARCHAR(20) DEFAULT 'pending';
ALTER TABLE orders ADD COLUMN priority INT AFTER customer_id;
ALTER TABLE orders ADD COLUMN row_id INT FIRST;

-- DROP COLUMN
ALTER TABLE orders DROP COLUMN legacy_field;
-- MySQL 不支持 DROP COLUMN IF EXISTS

-- RENAME COLUMN (8.0+)
ALTER TABLE orders RENAME COLUMN status TO order_status;
-- 8.0 之前用 CHANGE COLUMN (需重复类型定义):
ALTER TABLE orders CHANGE COLUMN status order_status VARCHAR(20);

-- RENAME TABLE
ALTER TABLE orders RENAME TO customer_orders;
-- 或独立语法:
RENAME TABLE orders TO customer_orders;

-- MODIFY (改类型/属性, 需完整列定义)
ALTER TABLE orders MODIFY COLUMN amount DECIMAL(12,2) NOT NULL;
-- CHANGE (改名+改类型)
ALTER TABLE orders CHANGE COLUMN old_name new_name BIGINT NOT NULL;

-- DEFAULT
ALTER TABLE orders ALTER COLUMN status SET DEFAULT 'new';
ALTER TABLE orders ALTER COLUMN status DROP DEFAULT;

-- ADD INDEX (内联)
ALTER TABLE orders ADD INDEX idx_status (status);
ALTER TABLE orders ADD UNIQUE INDEX uq_order_no (order_no);

-- 约束管理
ALTER TABLE orders ADD CONSTRAINT pk_orders PRIMARY KEY (id);
ALTER TABLE orders ADD CONSTRAINT fk_customer
    FOREIGN KEY (customer_id) REFERENCES customers(id);
ALTER TABLE orders ADD CHECK (amount > 0);  -- 8.0.16+

-- Online DDL 控制
ALTER TABLE orders ADD COLUMN status VARCHAR(20), ALGORITHM=INSTANT;
ALTER TABLE orders ADD INDEX idx_status (status), ALGORITHM=INPLACE, LOCK=NONE;
-- ALGORITHM: INSTANT > INPLACE > COPY (性能从高到低)
-- LOCK: NONE > SHARED > EXCLUSIVE (并发从高到低)
```

### Oracle

```sql
-- ADD COLUMN (Oracle 使用 ADD 不带 COLUMN 关键字)
ALTER TABLE orders ADD (status VARCHAR2(20) DEFAULT 'pending');
-- 多列
ALTER TABLE orders ADD (
    created_at TIMESTAMP DEFAULT SYSTIMESTAMP,
    updated_at TIMESTAMP
);

-- DROP COLUMN
ALTER TABLE orders DROP COLUMN legacy_field;
ALTER TABLE orders DROP (col1, col2);  -- 多列
-- SET UNUSED: 标记列不可见但不立即删除 (适合大表)
ALTER TABLE orders SET UNUSED COLUMN legacy_field;
-- 之后离线期间执行:
ALTER TABLE orders DROP UNUSED COLUMNS;

-- RENAME
ALTER TABLE orders RENAME COLUMN status TO order_status;
-- RENAME TABLE (独立语法)
RENAME orders TO customer_orders;

-- MODIFY (改类型/属性)
ALTER TABLE orders MODIFY (amount NUMBER(12,2) NOT NULL);
ALTER TABLE orders MODIFY (status DEFAULT 'new');
ALTER TABLE orders MODIFY (customer_id NOT NULL);
ALTER TABLE orders MODIFY (notes NULL);  -- 允许 NULL

-- 约束管理
ALTER TABLE orders ADD CONSTRAINT pk_orders PRIMARY KEY (id);
ALTER TABLE orders ADD CONSTRAINT fk_customer
    FOREIGN KEY (customer_id) REFERENCES customers(id)
    ON DELETE CASCADE;
ALTER TABLE orders ADD CONSTRAINT chk_amount CHECK (amount > 0);
ALTER TABLE orders DROP CONSTRAINT chk_amount CASCADE;
-- ENABLE / DISABLE 约束 (Oracle 独特能力)
ALTER TABLE orders DISABLE CONSTRAINT fk_customer;
ALTER TABLE orders ENABLE CONSTRAINT fk_customer;

-- 不可见列 (12c+)
ALTER TABLE orders MODIFY (internal_code INVISIBLE);
ALTER TABLE orders MODIFY (internal_code VISIBLE);
```

### SQL Server

```sql
-- ADD COLUMN
ALTER TABLE orders ADD status VARCHAR(20) DEFAULT 'pending';
ALTER TABLE orders ADD
    created_at DATETIME2 DEFAULT GETDATE(),
    updated_at DATETIME2;

-- DROP COLUMN (需先删除列上的约束)
-- 先删默认约束:
ALTER TABLE orders DROP CONSTRAINT DF_orders_status;
-- 再删列:
ALTER TABLE orders DROP COLUMN legacy_field;

-- RENAME (使用 sp_rename 存储过程, 非标准 SQL)
EXEC sp_rename 'orders.status', 'order_status', 'COLUMN';
EXEC sp_rename 'orders', 'customer_orders';

-- ALTER COLUMN (改类型, 需完整类型定义)
ALTER TABLE orders ALTER COLUMN amount DECIMAL(12,2) NOT NULL;
-- 注意: ALTER COLUMN 会丢失 DEFAULT 约束, 需要单独重建

-- 约束管理
ALTER TABLE orders ADD CONSTRAINT PK_orders PRIMARY KEY CLUSTERED (id);
ALTER TABLE orders ADD CONSTRAINT FK_customer
    FOREIGN KEY (customer_id) REFERENCES customers(id);
ALTER TABLE orders ADD CONSTRAINT UQ_order_no UNIQUE (order_no);
ALTER TABLE orders ADD CONSTRAINT CK_amount CHECK (amount > 0);
ALTER TABLE orders DROP CONSTRAINT CK_amount;

-- Online Index (Enterprise Edition)
CREATE INDEX IX_status ON orders(status) WITH (ONLINE = ON);

-- 条件约束删除 (避免不存在报错)
IF EXISTS (SELECT * FROM sys.check_constraints WHERE name = 'CK_amount')
    ALTER TABLE orders DROP CONSTRAINT CK_amount;
```

### Snowflake

```sql
-- ADD COLUMN
ALTER TABLE orders ADD COLUMN status VARCHAR DEFAULT 'pending';
ALTER TABLE IF EXISTS orders ADD COLUMN IF NOT EXISTS priority INT;
-- 多列
ALTER TABLE orders ADD COLUMN col1 INT, COLUMN col2 VARCHAR;

-- DROP COLUMN
ALTER TABLE orders DROP COLUMN legacy_field;
ALTER TABLE IF EXISTS orders DROP COLUMN IF EXISTS old_field;

-- RENAME
ALTER TABLE orders RENAME COLUMN status TO order_status;
ALTER TABLE orders RENAME TO customer_orders;

-- 修改类型 (仅支持扩大 VARCHAR 长度和 NUMBER 精度)
ALTER TABLE orders ALTER COLUMN name SET DATA TYPE VARCHAR(200);
ALTER TABLE orders ALTER COLUMN amount SET DATA TYPE NUMBER(12,2);
-- 不支持: INT -> VARCHAR, VARCHAR -> INT 等不兼容转换

-- DEFAULT / NOT NULL
ALTER TABLE orders ALTER COLUMN status SET DEFAULT 'new';
ALTER TABLE orders ALTER COLUMN status DROP DEFAULT;
ALTER TABLE orders ALTER COLUMN customer_id SET NOT NULL;
ALTER TABLE orders ALTER COLUMN notes DROP NOT NULL;

-- 约束
ALTER TABLE orders ADD CONSTRAINT pk_orders PRIMARY KEY (id);
ALTER TABLE orders ADD CONSTRAINT fk_customer
    FOREIGN KEY (customer_id) REFERENCES customers(id);
ALTER TABLE orders DROP CONSTRAINT fk_customer;
-- 注意: Snowflake 约束默认 NOT ENFORCED (不强制执行)
-- 需显式: ALTER TABLE orders ADD PRIMARY KEY (id) ENFORCED; -- 仅 NOT NULL
```

### BigQuery

```sql
-- ADD COLUMN
ALTER TABLE dataset.orders ADD COLUMN status STRING DEFAULT 'pending';
ALTER TABLE dataset.orders ADD COLUMN IF NOT EXISTS priority INT64;

-- DROP COLUMN
ALTER TABLE dataset.orders DROP COLUMN legacy_field;
ALTER TABLE dataset.orders DROP COLUMN IF EXISTS old_field;

-- RENAME COLUMN
ALTER TABLE dataset.orders RENAME COLUMN status TO order_status;
-- BigQuery 不支持 RENAME TABLE

-- 修改类型 (仅安全扩宽)
ALTER TABLE dataset.orders ALTER COLUMN amount SET DATA TYPE FLOAT64;
-- 支持: INT64 -> FLOAT64, NUMERIC -> BIGNUMERIC 等
-- 不支持: STRING -> INT64 等缩窄转换

-- DEFAULT / NOT NULL
ALTER TABLE dataset.orders ALTER COLUMN status SET DEFAULT 'new';
ALTER TABLE dataset.orders ALTER COLUMN status DROP DEFAULT;
ALTER TABLE dataset.orders ALTER COLUMN notes DROP NOT NULL;
-- BigQuery 不支持 SET NOT NULL (仅支持 DROP NOT NULL)

-- 约束 (有限支持)
ALTER TABLE dataset.orders ADD PRIMARY KEY (id) NOT ENFORCED;
ALTER TABLE dataset.orders ADD FOREIGN KEY (customer_id)
    REFERENCES dataset.customers(id) NOT ENFORCED;
-- BigQuery 约束始终 NOT ENFORCED, 仅用于优化器提示

-- 设置/修改选项
ALTER TABLE dataset.orders SET OPTIONS (
    expiration_timestamp = TIMESTAMP '2026-01-01 00:00:00 UTC',
    description = 'Customer orders table'
);
```

### ClickHouse

```sql
-- ADD COLUMN
ALTER TABLE orders ADD COLUMN status String DEFAULT 'pending';
ALTER TABLE orders ADD COLUMN IF NOT EXISTS priority Int32;
-- 支持 FIRST / AFTER
ALTER TABLE orders ADD COLUMN row_id UInt64 FIRST;
ALTER TABLE orders ADD COLUMN priority Int32 AFTER customer_id;

-- DROP COLUMN
ALTER TABLE orders DROP COLUMN legacy_field;
ALTER TABLE orders DROP COLUMN IF EXISTS old_field;

-- RENAME COLUMN (20.4+)
ALTER TABLE orders RENAME COLUMN status TO order_status;

-- MODIFY COLUMN (改类型)
ALTER TABLE orders MODIFY COLUMN amount Float64;
ALTER TABLE orders MODIFY COLUMN status LowCardinality(String);
-- ClickHouse 异步执行 mutation, 可用 SETTINGS mutations_sync=1 同步等待

-- DEFAULT
ALTER TABLE orders MODIFY COLUMN status String DEFAULT 'new';

-- COMMENT
ALTER TABLE orders COMMENT COLUMN status 'Order status field';
ALTER TABLE orders MODIFY COLUMN status String COMMENT 'updated comment';

-- INDEX (数据跳过索引, 非 B-tree)
ALTER TABLE orders ADD INDEX idx_status status TYPE set(100) GRANULARITY 4;
ALTER TABLE orders DROP INDEX idx_status;

-- RENAME TABLE (独立语法)
RENAME TABLE orders TO customer_orders;

-- 分布式表需在所有节点执行 (或使用 ON CLUSTER)
ALTER TABLE orders ON CLUSTER my_cluster ADD COLUMN status String;
```

### DuckDB

```sql
-- ADD COLUMN
ALTER TABLE orders ADD COLUMN status VARCHAR DEFAULT 'pending';
ALTER TABLE orders ADD COLUMN IF NOT EXISTS priority INTEGER;

-- DROP COLUMN
ALTER TABLE orders DROP COLUMN legacy_field;
ALTER TABLE orders DROP COLUMN IF EXISTS old_field;

-- RENAME
ALTER TABLE orders RENAME COLUMN status TO order_status;
ALTER TABLE orders RENAME TO customer_orders;

-- 修改类型
ALTER TABLE orders ALTER COLUMN amount SET DATA TYPE DOUBLE;
ALTER TABLE orders ALTER COLUMN amount TYPE BIGINT;

-- DEFAULT / NOT NULL
ALTER TABLE orders ALTER COLUMN status SET DEFAULT 'new';
ALTER TABLE orders ALTER COLUMN status DROP DEFAULT;
ALTER TABLE orders ALTER COLUMN customer_id SET NOT NULL;
ALTER TABLE orders ALTER COLUMN notes DROP NOT NULL;

-- 约束
ALTER TABLE orders ADD CONSTRAINT pk_orders PRIMARY KEY (id);
ALTER TABLE orders ADD CONSTRAINT fk_customer
    FOREIGN KEY (customer_id) REFERENCES customers(id);
ALTER TABLE orders ADD CONSTRAINT chk_amount CHECK (amount > 0);
ALTER TABLE orders DROP CONSTRAINT chk_amount;
```

### Spark SQL / Databricks

```sql
-- ADD COLUMNS (注意: COLUMNS 复数形式, 用括号包围)
ALTER TABLE orders ADD COLUMNS (
    status STRING DEFAULT 'pending' COMMENT 'Order status',
    priority INT AFTER customer_id
);

-- DROP COLUMN (Delta Lake)
ALTER TABLE orders DROP COLUMN legacy_field;
ALTER TABLE orders DROP COLUMNS (col1, col2);

-- RENAME COLUMN
ALTER TABLE orders RENAME COLUMN status TO order_status;

-- 修改类型 (仅安全扩宽, Delta Lake)
ALTER TABLE orders ALTER COLUMN amount TYPE DOUBLE;
-- 支持: INT -> BIGINT, FLOAT -> DOUBLE, DECIMAL 精度增大

-- COMMENT
ALTER TABLE orders ALTER COLUMN status COMMENT 'Updated status field';

-- 修改位置 (Databricks)
ALTER TABLE orders ALTER COLUMN priority FIRST;
ALTER TABLE orders ALTER COLUMN priority AFTER customer_id;

-- SET TBLPROPERTIES
ALTER TABLE orders SET TBLPROPERTIES (
    'delta.enableChangeDataFeed' = 'true',
    'delta.minReaderVersion' = '2'
);
```

### Hive

```sql
-- ADD COLUMNS
ALTER TABLE orders ADD COLUMNS (
    status STRING COMMENT 'Order status',
    priority INT COMMENT 'Priority level'
);

-- CHANGE COLUMN (改名 + 改类型, 需重复列名)
ALTER TABLE orders CHANGE COLUMN status order_status STRING;
ALTER TABLE orders CHANGE COLUMN amount amount BIGINT;  -- 仅改类型, 名字重复写

-- REPLACE COLUMNS (删除/重排列的唯一方式)
-- 危险: 用新列定义完全替换现有列
ALTER TABLE orders REPLACE COLUMNS (
    id BIGINT,
    customer_id BIGINT,
    amount DOUBLE,
    order_date DATE
);
-- REPLACE COLUMNS 中不包含的列会被删除

-- SET/CHANGE 文件格式
ALTER TABLE orders SET FILEFORMAT ORC;

-- SET LOCATION
ALTER TABLE orders SET LOCATION 'hdfs://path/to/new/location';

-- PARTITION 操作
ALTER TABLE orders ADD PARTITION (dt='2024-01-01') LOCATION '/data/orders/2024-01-01';
ALTER TABLE orders DROP PARTITION (dt='2024-01-01');

-- 注意: Hive 不支持 RENAME COLUMN, DROP COLUMN, ADD/DROP CONSTRAINT
```

### Google Spanner

```sql
-- ADD COLUMN
ALTER TABLE orders ADD COLUMN status STRING(20) DEFAULT ('pending');
ALTER TABLE orders ADD COLUMN IF NOT EXISTS priority INT64;

-- DROP COLUMN
ALTER TABLE orders DROP COLUMN legacy_field;

-- RENAME COLUMN
ALTER TABLE orders RENAME COLUMN status TO order_status;

-- 修改类型 (仅安全扩宽)
ALTER TABLE orders ALTER COLUMN name STRING(200);  -- 扩大 STRING 长度
ALTER TABLE orders ALTER COLUMN amount FLOAT64;     -- INT64 -> FLOAT64

-- NOT NULL
ALTER TABLE orders ALTER COLUMN customer_id INT64 NOT NULL;
ALTER TABLE orders ALTER COLUMN notes STRING(MAX);  -- 去掉 NOT NULL

-- DEFAULT
ALTER TABLE orders ALTER COLUMN status SET DEFAULT ('new');
ALTER TABLE orders ALTER COLUMN status DROP DEFAULT;

-- 约束
ALTER TABLE orders ADD CONSTRAINT chk_amount CHECK (amount > 0);
ALTER TABLE orders DROP CONSTRAINT chk_amount;

-- 注意: Spanner 不支持 RENAME TABLE
-- Spanner 使用 interleaved tables 而非传统 FOREIGN KEY:
CREATE TABLE order_items (
    order_id INT64 NOT NULL,
    item_id INT64 NOT NULL,
    ...
) PRIMARY KEY (order_id, item_id),
  INTERLEAVE IN PARENT orders ON DELETE CASCADE;
```

### Flink SQL

```sql
-- ADD COLUMN
ALTER TABLE orders ADD (
    status STRING,
    priority INT
);
-- 支持 FIRST / AFTER
ALTER TABLE orders ADD status STRING AFTER customer_id;

-- DROP COLUMN
ALTER TABLE orders DROP (legacy_field);
ALTER TABLE orders DROP (col1, col2);

-- RENAME COLUMN
ALTER TABLE orders RENAME old_name TO new_name;

-- MODIFY (改类型)
ALTER TABLE orders MODIFY (amount BIGINT);

-- WATERMARK (流处理特有)
ALTER TABLE orders ADD WATERMARK FOR event_time AS event_time - INTERVAL '5' SECOND;
ALTER TABLE orders DROP WATERMARK;

-- 约束 (有限)
ALTER TABLE orders ADD PRIMARY KEY (id) NOT ENFORCED;
ALTER TABLE orders DROP PRIMARY KEY;

-- 注意: Flink SQL 的 ALTER TABLE 取决于底层 connector 的能力
-- 某些 connector (如 Kafka) 可能不支持 schema evolution
```

## 关键发现

### 1. 语法关键字的三大阵营

各引擎修改列类型的关键字形成了三大阵营：

| 阵营 | 关键字 | 代表引擎 |
|------|--------|---------|
| SQL 标准派 | `ALTER COLUMN col SET DATA TYPE type` | PostgreSQL, DB2, DuckDB, H2, HSQLDB |
| MySQL 派 | `MODIFY COLUMN col type` / `CHANGE COLUMN old new type` | MySQL, MariaDB, TiDB, OceanBase, SingleStore, StarRocks, Doris |
| SQL Server 派 | `ALTER COLUMN col type` | SQL Server, Azure Synapse |
| Oracle 派 | `MODIFY (col type)` | Oracle, Informix, SAP HANA |

### 2. DROP COLUMN 的历史包袱

- **SQLite** 直到 2021 年 (3.35.0) 才支持 DROP COLUMN，之前需要重建整张表
- **Derby** 至今不支持 DROP COLUMN
- **Hive / Impala** 需要 REPLACE COLUMNS 变通（用新列定义完全替换所有列）
- **CrateDB / QuestDB** 不支持 DROP COLUMN
- **流处理引擎** (Materialize, RisingWave) 不支持 DROP COLUMN，因为会破坏下游 pipeline

### 3. Online DDL 的三种路线

| 路线 | 原理 | 代表 | 优点 | 缺点 |
|------|------|------|------|------|
| 元数据即时修改 | 只改系统表/元数据, 不重写数据 | PostgreSQL (11+), MySQL INSTANT, MariaDB INSTANT, Snowflake, BigQuery | 毫秒级完成 | 仅部分操作支持 |
| 后台异步 mutation | 后台线程/进程逐步重写数据 | ClickHouse, StarRocks, Doris, CockroachDB, TiDB | 不阻塞读写 | 变更不立即生效 |
| 外部工具 | 创建影子表, 同步增量, 原子切换 | MySQL (gh-ost, pt-osc), PostgreSQL (pg-repack) | 适用于任意操作 | 操作复杂, 需额外存储 |

### 4. FIRST / AFTER 列位置控制

仅 MySQL 系引擎（MySQL、MariaDB、TiDB、OceanBase MySQL 模式、SingleStore）和部分 OLAP 引擎（ClickHouse、Spark SQL、Databricks、Flink SQL、H2）支持在 ADD COLUMN 时指定列位置。SQL 标准认为列顺序无语义意义，PostgreSQL、Oracle、SQL Server 等均不支持此特性。

### 5. IF EXISTS / IF NOT EXISTS 的采纳率

IF EXISTS / IF NOT EXISTS 对部署脚本的幂等性至关重要，但令人意外的是，许多主流引擎至今不支持：

- **支持**: PostgreSQL (9.6+), MariaDB (10.0+), Snowflake, BigQuery, DuckDB, ClickHouse, Trino, CockroachDB, YugabyteDB, H2, Google Spanner
- **不支持**: MySQL, SQLite, Oracle, SQL Server, DB2, Redshift, Spark SQL, Hive, TiDB, OceanBase, Teradata

MySQL 不支持 `ADD COLUMN IF NOT EXISTS` 是一个常见的兼容性痛点，MariaDB 在 10.0 就添加了这一能力。

### 6. 约束管理的 OLTP / OLAP 鸿沟

传统 OLTP 引擎（PostgreSQL、MySQL、Oracle、SQL Server、DB2）完整支持 ADD/DROP CONSTRAINT，而大多数 OLAP 和大数据引擎（ClickHouse、StarRocks、Doris、Hive、Spark SQL、Trino）完全不支持约束管理。云数仓（BigQuery、Snowflake、Redshift）支持约束语法但默认 NOT ENFORCED（不强制执行），约束仅作为优化器提示使用。

### 7. 类型变更的安全边界

几乎所有引擎在类型变更时都遵循"安全扩宽"原则：

- **总是允许**: INT -> BIGINT, FLOAT -> DOUBLE, VARCHAR(50) -> VARCHAR(200), DECIMAL 精度增大
- **通常拒绝**: VARCHAR -> INT, FLOAT -> INT, 精度缩小
- **需特殊处理**: PostgreSQL 的 `USING` 子句允许自定义转换表达式, ClickHouse 的异步 mutation 允许任意类型转换

### 8. InfluxDB 的特殊地位

InfluxDB 作为时序数据库，完全不支持 ALTER TABLE 概念。其 schema 由写入数据自动推断（schema-on-write），无法通过 DDL 修改已有的 measurement 结构。这是时序数据库与关系数据库在数据模型上的根本差异。
