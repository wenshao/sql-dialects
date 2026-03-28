# 数据库、模式与用户管理 (Users & Databases) — 方言对比

## 语法支持对比

### 传统 RDBMS

| 特性 | MySQL | PostgreSQL | SQLite | Oracle | SQL Server | MariaDB | Firebird | Db2 | SAP HANA |
|---|---|---|---|---|---|---|---|---|---|
| CREATE DATABASE | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| CREATE SCHEMA | ✅ (=DATABASE) | ✅ | ❌ | ✅ (=USER) | ✅ | ✅ (=DATABASE) | ❌ | ✅ | ✅ |
| CREATE USER | ✅ | ✅ CREATE ROLE | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| DROP USER | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| ALTER USER | ✅ | ✅ ALTER ROLE | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| GRANT/REVOKE | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| ROLE | ✅ 8.0+ | ✅ | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Row-Level Security | ❌ | ✅ 9.5+ | ❌ | ✅ VPD | ✅ | ❌ | ❌ | ✅ | ✅ |
| DATABASE = SCHEMA | ✅ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ |
| USER = SCHEMA | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| 多租户 | ❌ | ❌ | ❌ | ✅ CDB/PDB | ❌ | ❌ | ❌ | ✅ | ✅ |
| 跨库查询 | ❌ | ⚠️ dblink/FDW | ❌ | ⚠️ DB Link | ✅ | ❌ | ⚠️ | ✅ | ✅ |

### 大数据 / 分析引擎

| 特性 | BigQuery | Snowflake | MaxCompute | Hive | ClickHouse | StarRocks | Trino | Hologres | Doris | DuckDB | Spark | Flink |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| CREATE DATABASE | ❌ (project) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ CATALOG | ✅ | ✅ | ✅ | ✅ | ✅ |
| CREATE SCHEMA | ✅ (dataset) | ✅ | ✅ | ✅ (=DATABASE) | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ |
| CREATE USER | ❌ (IAM) | ✅ | ❌ (RAM) | ❌ (Ranger) | ✅ | ✅ | ❌ | ❌ (RAM) | ✅ | ❌ | ❌ | ❌ |
| GRANT/REVOKE | ✅ (IAM) | ✅ | ✅ | ⚠️ Ranger | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ✅ | ❌ |
| ROLE | ✅ (IAM) | ✅ | ✅ | ⚠️ Ranger | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ✅ | ❌ |
| Row-Level Security | ✅ | ✅ | ✅ | ⚠️ Ranger | ❌ | ❌ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ |

### 云数据仓库

| 特性 | Redshift | Synapse | Databricks | Greenplum | Impala | Vertica | Teradata |
|---|---|---|---|---|---|---|---|
| CREATE DATABASE | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| CREATE SCHEMA | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| CREATE USER | ✅ | ✅ | ✅ (SCIM) | ✅ | ✅ | ✅ | ✅ |
| GRANT/REVOKE | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Row-Level Security | ❌ | ✅ | ✅ | ✅ | ❌ | ✅ | ❌ |

### 分布式 / NewSQL

| 特性 | TiDB | OceanBase | CockroachDB | Spanner | YugabyteDB | PolarDB | openGauss | TDSQL | DamengDB | KingbaseES |
|---|---|---|---|---|---|---|---|---|---|---|
| CREATE DATABASE | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| CREATE SCHEMA | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| CREATE USER | ✅ | ✅ | ✅ | ❌ (IAM) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| GRANT/REVOKE | ✅ | ✅ | ✅ | ❌ (IAM) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| ROLE | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| 多租户 | ❌ | ✅ (双模) | ❌ | ✅ | ❌ | ✅ | ❌ | ⚠️ | ✅ | ❌ |

### 特殊用途

| 特性 | TimescaleDB | TDengine | ksqlDB | Materialize | H2 | Derby |
|---|---|---|---|---|---|---|
| CREATE DATABASE | ✅ | ✅ | ❌ | ❌ | ✅ | ✅ |
| CREATE SCHEMA | ✅ | ❌ | ❌ | ✅ | ✅ | ✅ |
| CREATE USER | ✅ | ❌ | ❌ | ✅ | ✅ | ✅ |
| GRANT/REVOKE | ✅ | ❌ | ❌ | ✅ | ✅ | ✅ |
| 多数据库 | ✅ | ✅ | ❌ | ❌ | ✅ | ✅ |

## 关键差异

- **命名层级**是最核心差异：MySQL 两级（database=-schema）、PostgreSQL/SQL Server 三级（database>schema）、Oracle 两级（user=schema）、BigQuery 两级（project>dataset）
- **Oracle CDB/PDB** 是最成熟的多租户方案，类似容器化理念；OceanBase 双模（MySQL/Oracle）是国产多租户代表
- **BigQuery/Spanner** 无 CREATE USER，完全依赖 IAM（云原生安全模型）
- **Hive/Spark** 用户和权限依赖外部组件（Apache Ranger），非 SQL 内置
- **PostgreSQL** RLS（行级安全策略）是内核级实现，对比 Oracle VPD 实现层次更深
- **SQLite** 无任何用户/权限管理，依赖文件系统权限
- **分布式引擎**（TiDB/CockroachDB）的权限模型基本兼容 MySQL/PostgreSQL，但分布式 RBAC 实现复杂度更高
