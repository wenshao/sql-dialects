# 权限管理 (Permissions) — 方言对比

## 语法支持对比

### 传统 RDBMS

| 特性 | MySQL | PostgreSQL | SQLite | Oracle | SQL Server | MariaDB | Firebird | Db2 | SAP HANA |
|---|---|---|---|---|---|---|---|---|---|
| CREATE USER | ✅ | ✅ CREATE ROLE | ❌ | ✅ | ✅ | ✅ | ✅ 3.0+ | ⚠️ OS 级 | ✅ |
| CREATE ROLE | ✅ 8.0+ | ✅ | ❌ | ✅ | ✅ | ✅ 10.0.5+ | ✅ | ✅ 9.5+ | ✅ |
| GRANT 表级 | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| GRANT 列级 | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ | ❌ | ❌ | ✅ |
| GRANT Schema 级 | ✅ 数据库 | ✅ | ❌ | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ |
| REVOKE | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| 行级安全 (RLS) | ❌ | ✅ POLICY | ❌ | ✅ VPD | ✅ | ❌ | ❌ | ✅ RCAC | ✅ |
| WITH GRANT OPTION | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| 密码认证 | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |

### 大数据 / 分析引擎

| 特性 | BigQuery | Snowflake | MaxCompute | Hive | ClickHouse | StarRocks | Trino | Hologres | Doris | DuckDB | Spark | Flink |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 权限模型 | IAM | RBAC | RAM + ACL | Ranger/Sentry | RBAC 20.1+ | RBAC 3.0+ | 依赖连接器 | RAM + SPM | RBAC | ❌ | Ranger/ACL | ❌ |
| CREATE USER | ⚠️ IAM | ✅ | ⚠️ RAM | ❌ | ✅ | ✅ | ❌ | ⚠️ RAM | ✅ | ❌ | ❌ | ❌ |
| CREATE ROLE | ⚠️ IAM | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ⚠️ SPM | ✅ | ❌ | ❌ | ❌ |
| GRANT 表级 | ✅ DCL | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ✅ | ❌ |
| GRANT 列级 | ✅ | ✅ | ❌ | ✅ Ranger | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ Ranger | ❌ |
| 行级安全 | ✅ | ✅ | ❌ | ✅ Ranger | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ Ranger | ❌ |

### 云数据仓库

| 特性 | Redshift | Synapse | Databricks | Greenplum | Impala | Vertica | Teradata |
|---|---|---|---|---|---|---|---|
| CREATE USER | ✅ | ✅ | ⚠️ Unity Catalog | ✅ | ⚠️ Ranger | ✅ | ✅ |
| CREATE ROLE | ✅ GROUP | ✅ | ✅ | ✅ | ✅ Ranger | ✅ | ✅ |
| GRANT 表级 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| GRANT 列级 | ✅ | ✅ | ✅ | ✅ | ✅ Ranger | ❌ | ✅ |
| 行级安全 | ❌ | ❌ | ✅ | ✅ | ✅ Ranger | ✅ Access Policy | ✅ |

### 分布式 / NewSQL

| 特性 | TiDB | OceanBase | CockroachDB | Spanner | YugabyteDB | PolarDB | openGauss | TDSQL | DamengDB | KingbaseES |
|---|---|---|---|---|---|---|---|---|---|---|
| CREATE USER | ✅ | ✅ | ✅ | ⚠️ IAM | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| CREATE ROLE | ✅ | ✅ | ✅ | ✅ FGAC | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| GRANT 表级 | ✅ | ✅ | ✅ | ⚠️ IAM | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| GRANT 列级 | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| 行级安全 | ❌ | ❌ | ❌ | ✅ FGAC | ✅ | ❌ | ✅ | ❌ | ❌ | ✅ |

### 特殊用途

| 特性 | TimescaleDB | TDengine | ksqlDB | Materialize | H2 | Derby |
|---|---|---|---|---|---|---|
| CREATE USER | ✅ | ✅ | ⚠️ Kafka ACL | ✅ | ✅ | ⚠️ |
| GRANT | ✅ | ✅ 库级 | ⚠️ RBAC | ✅ | ✅ | ✅ |
| 行级安全 | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| 列级权限 | ✅ | ❌ | ❌ | ❌ | ✅ | ✅ |

## 关键差异

- **SQLite** 完全无权限系统，安全性依赖文件系统权限
- **DuckDB/Flink** 无内置权限管理
- **BigQuery/Spanner** 使用 Google Cloud IAM 而非 SQL GRANT/REVOKE
- **Hive/Impala/Spark** 通过 Apache Ranger 或 Sentry 外部安全框架管理权限
- **ksqlDB** 权限管理依赖 Kafka ACL 和 Confluent RBAC
- **PostgreSQL** 行级安全（RLS）最完善，通过 CREATE POLICY 实现
- **Oracle VPD** (Virtual Private Database) 是 Oracle 独有的行级安全方案
- **Snowflake** RBAC 模型最完善，支持 ACCOUNTADMIN/SYSADMIN/SECURITYADMIN 等角色层级
- **TDengine** 仅支持数据库级别的 READ/WRITE/ALL 权限
- **Databricks** Unity Catalog 提供跨工作区的统一权限管理
