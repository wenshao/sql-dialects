# 数据库/Schema/用户管理

各数据库的数据库、Schema、用户创建与管理语法对比。

## 方言列表

### 传统关系型数据库
| 方言 | 简评 |
|---|---|
| [MySQL](mysql.sql) | CREATE USER/DATABASE/SCHEMA，用户@主机粒度 |
| [PostgreSQL](postgres.sql) | ROLE 统一用户/组，DATABASE/SCHEMA 分层 |
| [SQLite](sqlite.sql) | 无用户系统，文件即数据库 |
| [Oracle](oracle.sql) | USER=SCHEMA，CDB/PDB 多租户架构 |
| [SQL Server](sqlserver.sql) | LOGIN→USER 映射，数据库→Schema 分层 |
| [MariaDB](mariadb.sql) | 兼容 MySQL，ROLE(10.0.5+) |
| [Firebird](firebird.sql) | CREATE USER/DATABASE，ROLE 授权 |
| [IBM Db2](db2.sql) | OS 用户认证，DATABASE/SCHEMA 分层 |
| [SAP HANA](saphana.sql) | SCHEMA + 用户绑定，多租户 Tenant DB |

### 大数据 / 分析型引擎
| 方言 | 简评 |
|---|---|
| [BigQuery](bigquery.sql) | IAM 权限管理，PROJECT→DATASET 结构 |
| [Snowflake](snowflake.sql) | ACCOUNT→DATABASE→SCHEMA，ROLE 继承 |
| [ClickHouse](clickhouse.sql) | CREATE USER(20.1+)，RBAC 权限模型 |
| [Hive](hive.sql) | 依赖 Ranger/Sentry，DATABASE 组织 |
| [Spark SQL](spark.sql) | 依赖 Hive Metastore 或 Unity Catalog |
| [Flink SQL](flink.sql) | Catalog→Database 结构，无用户管理 |
| [StarRocks](starrocks.sql) | GRANT 权限体系，DATABASE 组织 |
| [Doris](doris.sql) | GRANT 权限体系，Database→Table |
| [Trino](trino.sql) | Catalog→Schema→Table，外部认证 |
| [DuckDB](duckdb.sql) | 无用户系统，进程级隔离 |
| [MaxCompute](maxcompute.sql) | PROJECT→SCHEMA，RAM 权限 |
| [Hologres](hologres.sql) | PG 兼容，DATABASE/SCHEMA/ROLE |

### 云数仓
| 方言 | 简评 |
|---|---|
| [Redshift](redshift.sql) | PG 兼容用户管理，超级用户概念 |
| [Azure Synapse](synapse.sql) | SQL 认证 + AAD 集成 |
| [Databricks SQL](databricks.sql) | Unity Catalog 统一权限 |
| [Greenplum](greenplum.sql) | PG 兼容用户管理 |
| [Impala](impala.sql) | 依赖 Ranger/Sentry 授权 |
| [Vertica](vertica.sql) | ROLE/USER + GRANT，SCHEMA 隔离 |
| [Teradata](teradata.sql) | 用户=数据库空间，Profile 控制 |

### 分布式 / NewSQL
| 方言 | 简评 |
|---|---|
| [TiDB](tidb.sql) | MySQL 兼容用户权限 |
| [OceanBase](oceanbase.sql) | MySQL/Oracle 双模式用户体系 |
| [CockroachDB](cockroachdb.sql) | PG 兼容 ROLE/USER |
| [Spanner](spanner.sql) | IAM 权限，Instance→Database |
| [YugabyteDB](yugabytedb.sql) | PG 兼容 ROLE/USER |
| [PolarDB](polardb.sql) | MySQL 兼容用户管理 |
| [openGauss](opengauss.sql) | PG 兼容 ROLE/USER |
| [TDSQL](tdsql.sql) | MySQL 兼容，分布式权限同步 |

### 国产数据库
| 方言 | 简评 |
|---|---|
| [DamengDB](dameng.sql) | Oracle 兼容，USER=SCHEMA |
| [KingbaseES](kingbase.sql) | PG 兼容 |

### 时序数据库
| 方言 | 简评 |
|---|---|
| [TimescaleDB](timescaledb.sql) | 继承 PG 用户管理 |
| [TDengine](tdengine.sql) | SUPER/NORMAL 两级用户，Database 组织 |

### 流处理
| 方言 | 简评 |
|---|---|
| [ksqlDB](ksqldb.sql) | 依赖 Kafka ACL 认证授权 |
| [Materialize](materialize.sql) | PG 兼容 ROLE/USER |

### 嵌入式 / 轻量
| 方言 | 简评 |
|---|---|
| [H2](h2.sql) | 简单用户密码认证 |
| [Derby](derby.sql) | 用户认证可选，内建/LDAP |

### SQL 标准
| 方言 | 简评 |
|---|---|
| [SQL Standard](sql-standard.sql) | SQL:2003 ROLE/GRANT 规范 |

## 核心差异

1. **命名空间层次**：PostgreSQL 有 database → schema → table 三层结构，MySQL 的 database 等同于 schema，Oracle 用 user 约等于 schema，SQL Server 有 server → database → schema → table 四层
2. **跨库查询**：PostgreSQL 不支持跨 database 查询（需要 dblink/FDW），MySQL 可以直接 `SELECT * FROM other_db.table`，SQL Server/Oracle 都支持跨库查询
3. **用户认证**：PostgreSQL 通过 pg_hba.conf 配置认证方式，MySQL 在 user 表中管理，Oracle 有内部认证和 OS 认证，云数据库通常集成 IAM
4. **角色系统**：PostgreSQL 的 ROLE 统一了用户和角色概念，MySQL 8.0+ 才支持 ROLE，Oracle 一直区分 USER 和 ROLE

## 选型建议

设计数据库架构时，PostgreSQL 的 schema 机制适合多租户隔离，MySQL 的多 database 方案更简单直接。云数据库（BigQuery/Snowflake）通常有自己的项目/账户/仓库层次结构，与传统 RDBMS 差异较大。

## 版本演进

- MySQL 8.0：引入角色（ROLE）机制，之前只能直接给用户授权
- PostgreSQL 16+：支持 `GRANT ... ON ALL TABLES IN SCHEMA` 的改进
- BigQuery：使用 IAM 角色代替传统 SQL 权限，与 Google Cloud 深度集成

## 横向对比

| 特性维度 | SQLite | ClickHouse | BigQuery | 传统 RDBMS (MySQL/PG/Oracle) |
|---|---|---|---|---|
| **权限系统** | 无 GRANT/REVOKE，完全依赖文件系统权限控制访问 | 有完整的 GRANT/REVOKE 和用户/角色系统 | 使用 Google Cloud IAM，不用 SQL GRANT | 完整的 GRANT/REVOKE 权限体系 |
| **用户管理** | 无用户概念，无 CREATE USER | 支持 CREATE USER、角色管理 | 通过 IAM 管理用户和服务账号 | CREATE USER / CREATE ROLE |
| **数据库层次** | 单文件即一个数据库，无 schema 概念 | database → table 两层结构 | project → dataset → table 三层结构 | PG: database→schema→table，MySQL: database=schema |
| **多租户隔离** | 每个租户一个数据库文件实现隔离 | 通过 database 或行级权限隔离 | 通过 dataset 权限 + IAM 策略隔离 | schema 隔离（PG）或 database 隔离（MySQL） |
| **跨库查询** | 通过 ATTACH DATABASE 可跨文件查询 | 支持跨 database 查询 | 支持跨 dataset/跨 project 查询 | 各方言支持程度不同（PG 需 dblink/FDW） |

## 引擎开发者视角

**核心设计决策**：命名空间层次结构直接影响多租户隔离能力和跨库查询能力。PostgreSQL 的 database -> schema -> table 三层模型和 MySQL 的 database = schema 二层模型代表两种设计哲学。

**实现建议**：
- 推荐采用三层命名空间（catalog -> schema -> table）——SQL 标准定义的就是三层模型。schema 层提供逻辑隔离但共享连接，database 层提供物理隔离
- 跨 database 查询是否支持是重大架构决策：PostgreSQL 不支持（需要 dblink/FDW），这简化了实现但限制了使用灵活性。如果引擎的存储层支持跨 database 访问，开放跨库查询会更受用户欢迎
- 用户认证应设计为可插拔的——密码认证、LDAP、Kerberos、证书认证、OAuth 等应通过统一接口接入。PostgreSQL 的 pg_hba.conf 方式灵活但配置复杂，可以在此基础上增加 SQL 级配置
- 系统用户/超级用户的设计要谨慎：PostgreSQL 的 SUPERUSER 跳过所有权限检查，这在安全审计中是隐患。推荐细粒度的系统权限（如 CREATE DATABASE、CREATE USER 等独立权限）
- database/schema 的创建应支持 IF NOT EXISTS——与 CREATE TABLE 同理，DDL 脚本需要幂等性
- 常见错误：public schema 的默认权限过于宽松。PostgreSQL 15 收紧了 public schema 的默认权限——新引擎应从一开始就采用最小权限默认值
