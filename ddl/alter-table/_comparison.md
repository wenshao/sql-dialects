# 修改表 (ALTER TABLE) — 方言对比

## 语法支持对比

### 传统 RDBMS

| 特性 | MySQL | PostgreSQL | SQLite | Oracle | SQL Server | MariaDB | Firebird | Db2 | SAP HANA |
|---|---|---|---|---|---|---|---|---|---|
| ADD COLUMN | ✅ | ✅ | ✅ | ✅ ADD () | ✅ ADD | ✅ | ✅ ADD | ✅ | ✅ ADD () |
| DROP COLUMN | ✅ | ✅ | ✅ 3.35+ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ DROP () |
| 修改列类型 | MODIFY COLUMN | ALTER TYPE | ❌ | MODIFY () | ALTER COLUMN | MODIFY COLUMN | ALTER TYPE | ALTER SET DATA TYPE | ALTER () |
| RENAME COLUMN | ✅ 8.0+ | ✅ | ✅ 3.25+ | ✅ | sp_rename | ✅ | ❌ | ✅ 11.1+ | ✅ |
| RENAME TABLE | ✅ | ALTER RENAME | ALTER RENAME | ✅ | sp_rename | ✅ | ❌ | ✅ | ✅ |
| IF EXISTS/NOT EXISTS | ❌ | ✅ | ❌ | ❌ | ❌ | ✅ 10.0+ | ❌ | ❌ | ❌ |
| AFTER / FIRST | ✅ | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ | ❌ | ❌ |
| 在线 DDL | ✅ 5.6+ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ |
| 多列操作 | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ | ❌ | ❌ | ✅ |

### 大数据 / 分析引擎

| 特性 | BigQuery | Snowflake | MaxCompute | Hive | ClickHouse | StarRocks | Trino | Hologres | Doris | DuckDB | Spark | Flink |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ADD COLUMN | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ 1.17+ |
| DROP COLUMN | ✅ | ✅ | ❌ | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ |
| 修改列类型 | ✅ | ✅ | ❌ | ⚠️ CHANGE | ✅ MODIFY | ✅ MODIFY | ✅ | ✅ | ✅ MODIFY | ❌ | ✅ 3.1+ | ❌ |
| RENAME COLUMN | ❌ | ✅ | ✅ CHANGE | ✅ CHANGE | ❌ | ❌ | ✅ | ✅ | ❌ | ✅ | ✅ 3.1+ | ❌ |
| ADD/DROP PARTITION | ❌ | ❌ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ✅ | ❌ | ✅ | ❌ |
| IF EXISTS | ✅ | ❌ | ✅ | ✅ | ✅ | ❌ | ❌ | ✅ | ❌ | ✅ | ❌ | ❌ |
| SET PROPERTIES | ✅ OPTIONS | ✅ SET TAG | ✅ | ✅ TBLPROPERTIES | ❌ | ✅ | ✅ | ✅ | ✅ | ❌ | ✅ TBLPROPERTIES | ✅ SET |

### 云数据仓库

| 特性 | Redshift | Synapse | Databricks | Greenplum | Impala | Vertica | Teradata |
|---|---|---|---|---|---|---|---|
| ADD COLUMN | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| DROP COLUMN | ✅ | ✅ | ✅ | ✅ | ⚠️ Kudu only | ✅ | ✅ |
| 修改列类型 | ✅ | ❌ | ✅ | ✅ | ⚠️ CHANGE | ✅ | ❌ |
| RENAME COLUMN | ❌ | RENAME OBJECT | ✅ | ✅ | ✅ CHANGE | ✅ | ✅ 14.10+ |

### 分布式 / NewSQL

| 特性 | TiDB | OceanBase | CockroachDB | Spanner | YugabyteDB | PolarDB | openGauss | TDSQL | DamengDB | KingbaseES |
|---|---|---|---|---|---|---|---|---|---|---|
| ADD COLUMN | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| DROP COLUMN | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| 在线 DDL | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| 修改列类型 | ✅ MODIFY | ✅ MODIFY | ✅ ALTER TYPE | ❌ | ✅ ALTER TYPE | ✅ MODIFY | ✅ ALTER TYPE | ✅ MODIFY | ✅ MODIFY | ✅ ALTER TYPE |

### 特殊用途

| 特性 | TimescaleDB | TDengine | ksqlDB | Materialize | H2 | Derby |
|---|---|---|---|---|---|---|
| ADD COLUMN | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ |
| DROP COLUMN | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ |
| 修改列类型 | ✅ | ⚠️ MODIFY | ❌ | ❌ | ✅ | ✅ |
| RENAME COLUMN | ✅ | ⚠️ TAG only | ❌ | ✅ RENAME | ✅ | ❌ |

## 关键差异

- **SQLite** ALTER TABLE 功能极其有限，修改列类型和删除列需要重建表
- **ksqlDB** 不支持 ALTER STREAM/TABLE ADD COLUMN，需重建
- **MySQL/MariaDB** 独有 AFTER/FIRST 指定列位置
- **Oracle/DamengDB** 使用括号语法 ADD (col)、MODIFY (col)
- **Hive/MaxCompute/Impala** 使用 CHANGE COLUMN 同时修改名称和类型
- **Synapse** 不支持修改列类型，需 CTAS 重建表
- **分布式数据库** DDL 通常是在线的（不阻塞 DML），但异步传播
- **Doris/StarRocks** 支持 ORDER BY 列顺序调整（Light Schema Change）
