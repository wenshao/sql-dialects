# 临时表 (Temporary Tables) — 方言对比

## 语法支持对比

### 传统 RDBMS

| 特性 | MySQL | PostgreSQL | SQLite | Oracle | SQL Server | MariaDB | Firebird | Db2 | SAP HANA |
|---|---|---|---|---|---|---|---|---|---|
| CREATE TEMPORARY TABLE | ✅ | ✅ | ✅ | ✅ GTT | ✅ | ✅ | ✅ GTT | ✅ DGTT | ✅ |
| # 前缀临时表 | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ✅ |
| ## 全局临时表 | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ |
| 会话级临时表 | ✅ | ✅ | ✅ | ✅ | ✅ # | ✅ | ✅ PRESERVE | ✅ DGTT | ✅ |
| 事务级临时表 | ❌ | ✅ ON COMMIT DELETE | ❌ | ✅ ON COMMIT DELETE | ❌ | ❌ | ✅ ON COMMIT DELETE | ❌ | ✅ |
| 全局临时表 (GTT) | ❌ | ✅ 15+ | ❌ | ✅ | ✅ ## | ❌ | ✅ | ✅ CGTT | ✅ |
| CTAS 临时表 | ✅ | ✅ | ✅ | ✅ | ✅ SELECT INTO | ✅ | ❌ | ✅ | ✅ |
| CREATE OR REPLACE TEMP | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ |
| CTE (WITH) | ✅ 8.0+ | ✅ | ✅ 3.8.3+ | ✅ | ✅ | ✅ 10.2.1+ | ✅ 2.1+ | ✅ | ✅ |
| 递归 CTE | ✅ 8.0+ | ✅ | ✅ 3.8.3+ | ✅ | ✅ | ✅ 10.2.2+ | ✅ 2.1+ | ✅ | ✅ |
| 临时表支持索引 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ |
| 临时表支持触发器 | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ | ❌ | ❌ | ❌ |
| 表变量 | ❌ | ❌ | ❌ | ❌ | ✅ DECLARE @t | ❌ | ❌ | ❌ | ✅ |
| 临时表对其他会话不可见 | ✅ | ✅ | ✅ | ❌ GTT 结构可见 | ✅ # | ✅ | ❌ GTT 结构可见 | ✅ DGTT | ✅ |
| DROP TEMPORARY TABLE | ✅ | ❌ DROP TABLE | ❌ DROP TABLE | ❌ | ❌ DROP TABLE | ✅ | ❌ | ❌ | ❌ |

### 大数据 / 分析引擎

| 特性 | BigQuery | Snowflake | MaxCompute | Hive | ClickHouse | StarRocks | Trino | Hologres | Doris | DuckDB | Spark | Flink |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| CREATE TEMPORARY TABLE | ✅ 脚本内 | ✅ | ❌ | ✅ 0.14+ | ✅ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ✅ |
| TRANSIENT TABLE | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| 临时视图 | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ | ✅ |
| CACHE TABLE | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ |
| CTE | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| CTAS | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Memory 引擎表 | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |

### 云数据仓库

| 特性 | Redshift | Synapse | Databricks | Greenplum | Impala | Vertica | Teradata |
|---|---|---|---|---|---|---|---|
| CREATE TEMPORARY TABLE | ✅ | ✅ # 前缀 | ❌ | ✅ | ❌ | ✅ LOCAL | ✅ VOLATILE |
| CTAS 临时表 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| 分布键支持 | ✅ DISTSTYLE | ✅ DISTRIBUTION | ❌ | ✅ DISTRIBUTED BY | ❌ | ❌ | ✅ |
| CTE | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |

### 分布式 / NewSQL

| 特性 | TiDB | OceanBase | CockroachDB | Spanner | YugabyteDB | PolarDB | openGauss | TDSQL | DamengDB | KingbaseES |
|---|---|---|---|---|---|---|---|---|---|---|
| CREATE TEMPORARY TABLE | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| 全局临时表 | ✅ 10.0+ | ✅ | ❌ | ❌ | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ |
| CTE | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |

### 特殊用途

| 特性 | TimescaleDB | TDengine | ksqlDB | Materialize | H2 | Derby |
|---|---|---|---|---|---|---|
| CREATE TEMPORARY TABLE | ✅ | ❌ | ❌ | ✅ | ✅ | ✅ DECLARE GTT |
| CTE | ✅ | ❌ | ❌ | ✅ | ✅ | ✅ |

## 关键差异

- **SQL Server** 使用 # 前缀表示局部临时表，## 表示全局临时表（独特语法）
- **Oracle** 的全局临时表（GTT）结构永久存在，数据按会话/事务隔离
- **PostgreSQL** 临时表在会话结束时自动删除，支持 ON COMMIT DELETE ROWS（事务级）
- **Snowflake** 区分 TEMPORARY（会话级）和 TRANSIENT（持久但无 Fail-safe）
- **Spark SQL** 不支持临时表，使用临时视图 + CACHE TABLE 替代
- **Trino** 是联邦查询引擎，不支持临时表，使用 CTE 替代
- **DB2** 使用 DECLARE GLOBAL TEMPORARY TABLE（DGTT）和 CREATE GLOBAL TEMPORARY TABLE（CGTT）
- **Firebird** 只有全局临时表（表结构永久，数据临时），没有会话级 CREATE TEMPORARY TABLE
