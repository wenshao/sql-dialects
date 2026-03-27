# 权限管理 (PERMISSIONS)

各数据库权限管理语法对比，包括 GRANT、REVOKE、角色管理等。

> [对比总览表](_comparison.md) -- 横向对比各方言特性支持

## 方言列表

### 传统关系型数据库
| 方言 | 链接 |
|---|---|
| MySQL | [mysql.sql](mysql.sql) |
| PostgreSQL | [postgres.sql](postgres.sql) |
| SQLite | [sqlite.sql](sqlite.sql) |
| Oracle | [oracle.sql](oracle.sql) |
| SQL Server | [sqlserver.sql](sqlserver.sql) |
| MariaDB | [mariadb.sql](mariadb.sql) |
| Firebird | [firebird.sql](firebird.sql) |
| IBM Db2 | [db2.sql](db2.sql) |
| SAP HANA | [saphana.sql](saphana.sql) |

### 大数据 / 分析型引擎
| 方言 | 链接 |
|---|---|
| BigQuery | [bigquery.sql](bigquery.sql) |
| Snowflake | [snowflake.sql](snowflake.sql) |
| ClickHouse | [clickhouse.sql](clickhouse.sql) |
| Hive | [hive.sql](hive.sql) |
| Spark SQL | [spark.sql](spark.sql) |
| Flink SQL | [flink.sql](flink.sql) |
| StarRocks | [starrocks.sql](starrocks.sql) |
| Doris | [doris.sql](doris.sql) |
| Trino | [trino.sql](trino.sql) |
| DuckDB | [duckdb.sql](duckdb.sql) |
| MaxCompute | [maxcompute.sql](maxcompute.sql) |
| Hologres | [hologres.sql](hologres.sql) |

### 云数仓
| 方言 | 链接 |
|---|---|
| Redshift | [redshift.sql](redshift.sql) |
| Azure Synapse | [synapse.sql](synapse.sql) |
| Databricks SQL | [databricks.sql](databricks.sql) |
| Greenplum | [greenplum.sql](greenplum.sql) |
| Impala | [impala.sql](impala.sql) |
| Vertica | [vertica.sql](vertica.sql) |
| Teradata | [teradata.sql](teradata.sql) |

### 分布式 / NewSQL
| 方言 | 链接 |
|---|---|
| TiDB | [tidb.sql](tidb.sql) |
| OceanBase | [oceanbase.sql](oceanbase.sql) |
| CockroachDB | [cockroachdb.sql](cockroachdb.sql) |
| Spanner | [spanner.sql](spanner.sql) |
| YugabyteDB | [yugabytedb.sql](yugabytedb.sql) |
| PolarDB | [polardb.sql](polardb.sql) |
| openGauss | [opengauss.sql](opengauss.sql) |
| TDSQL | [tdsql.sql](tdsql.sql) |

### 国产数据库
| 方言 | 链接 |
|---|---|
| DamengDB | [dameng.sql](dameng.sql) |
| KingbaseES | [kingbase.sql](kingbase.sql) |

### 时序数据库
| 方言 | 链接 |
|---|---|
| TimescaleDB | [timescaledb.sql](timescaledb.sql) |
| TDengine | [tdengine.sql](tdengine.sql) |

### 流处理
| 方言 | 链接 |
|---|---|
| ksqlDB | [ksqldb.sql](ksqldb.sql) |
| Materialize | [materialize.sql](materialize.sql) |

### 嵌入式 / 轻量
| 方言 | 链接 |
|---|---|
| H2 | [h2.sql](h2.sql) |
| Derby | [derby.sql](derby.sql) |

### SQL 标准
| 方言 | 链接 |
|---|---|
| SQL Standard | [sql-standard.sql](sql-standard.sql) |

## 核心差异

1. **权限粒度**：PostgreSQL 支持列级权限，MySQL 支持列级权限，Oracle 用 VPD（Virtual Private Database）实现行级安全，SQL Server 有行级安全策略（2016+）
2. **角色系统**：PostgreSQL 角色即用户（ROLE 统一模型），MySQL 8.0+ 才有 ROLE，Oracle 一直区分 USER 和 ROLE，SQL Server 有固定服务器/数据库角色
3. **默认权限**：PostgreSQL 可设置 DEFAULT PRIVILEGES 自动授权新对象，MySQL 无此功能需要逐个授权
4. **云数据库权限**：BigQuery 使用 IAM 而非 SQL GRANT，Snowflake 有独特的角色继承树，Databricks 集成 Unity Catalog

## 选型建议

遵循最小权限原则：应用程序账户只给 SELECT/INSERT/UPDATE/DELETE 权限，DDL 权限留给 DBA 账户。使用角色（ROLE）管理权限组而非逐用户授权。云数据库的权限体系通常与传统 SQL GRANT 差异大，需要单独学习。

## 版本演进

- MySQL 8.0：引入 ROLE 机制，权限管理能力显著提升
- PostgreSQL 15+：对 PUBLIC schema 的默认权限收紧（安全增强）
- SQL Server 2016+：引入行级安全（Row-Level Security）策略

## 横向对比

| 特性维度 | SQLite | ClickHouse | BigQuery | 传统 RDBMS (MySQL/PG/Oracle) |
|---|---|---|---|---|
| **权限系统** | 无 GRANT/REVOKE，完全依赖操作系统文件权限 | 有完整的 GRANT/REVOKE/CREATE USER/ROLE 系统 | 使用 Google Cloud IAM 管理权限（非 SQL GRANT） | 完整的 SQL GRANT/REVOKE 权限体系 |
| **用户认证** | 无认证机制，文件可读即可查 | 支持密码认证、LDAP、Kerberos 等 | Google 账号 / 服务账号 / OAuth | 各方言有独立的认证体系 |
| **角色管理** | 不支持 | 支持 CREATE ROLE 和角色继承 | IAM 角色（Viewer/Editor/Owner + 自定义） | PG ROLE 统一模型 / MySQL 8.0+ ROLE / Oracle USER+ROLE |
| **行级安全** | 不支持（应用层实现） | 支持行级策略（Row Policy） | 通过 IAM 条件和行级访问策略实现 | PG Row-Level Security / Oracle VPD / SQL Server 2016+ |
| **列级权限** | 不支持 | 支持列级 GRANT | 支持列级 IAM 绑定 | PG/MySQL 支持列级权限 |
| **安全模型** | 文件系统安全是唯一防线 | 数据库级安全 | 云平台级安全（IAM + VPC + 加密） | 数据库级安全 |
