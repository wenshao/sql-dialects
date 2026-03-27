# 权限管理 (PERMISSIONS)

各数据库权限管理语法对比，包括 GRANT、REVOKE、角色管理等。

> [对比总览表](_comparison.md) -- 横向对比各方言特性支持

## 方言列表

### 传统关系型数据库
| 方言 | 简评 |
|---|---|
| [MySQL](mysql.sql) | GRANT/REVOKE，全局/库/表/列粒度 |
| [PostgreSQL](postgres.sql) | GRANT/REVOKE，ROLE 继承，行级安全(RLS) |
| [SQLite](sqlite.sql) | 无权限系统(文件级访问控制) |
| [Oracle](oracle.sql) | 系统/对象权限，ROLE，VPD/DBMS_RLS |
| [SQL Server](sqlserver.sql) | GRANT/DENY/REVOKE 三态，SCHEMA 隔离 |
| [MariaDB](mariadb.sql) | 兼容 MySQL 权限，ROLE(10.0.5+) |
| [Firebird](firebird.sql) | GRANT/REVOKE + ROLE，DDL 权限 |
| [IBM Db2](db2.sql) | GRANT/REVOKE，LBAC 标签安全 |
| [SAP HANA](saphana.sql) | GRANT/REVOKE + 分析权限(Analytic Privilege) |

### 大数据 / 分析型引擎
| 方言 | 简评 |
|---|---|
| [BigQuery](bigquery.sql) | IAM ROLE 绑定，Dataset/Table/View 粒度 |
| [Snowflake](snowflake.sql) | RBAC + DAC，ROLE 层级继承，列级安全 |
| [ClickHouse](clickhouse.sql) | GRANT/REVOKE(20.1+)，RBAC 权限模型 |
| [Hive](hive.sql) | Ranger/Sentry 外部授权 |
| [Spark SQL](spark.sql) | Unity Catalog 权限或 Ranger |
| [Flink SQL](flink.sql) | 无权限管理(依赖外部) |
| [StarRocks](starrocks.sql) | GRANT/REVOKE，RBAC 模型 |
| [Doris](doris.sql) | GRANT/REVOKE，RBAC 模型 |
| [Trino](trino.sql) | 外部 Authorizer(OPA/Ranger) |
| [DuckDB](duckdb.sql) | 无权限系统(进程级) |
| [MaxCompute](maxcompute.sql) | RAM + ACL + Policy，三层权限 |
| [Hologres](hologres.sql) | PG 兼容 GRANT/REVOKE |

### 云数仓
| 方言 | 简评 |
|---|---|
| [Redshift](redshift.sql) | GRANT/REVOKE(PG 兼容) |
| [Azure Synapse](synapse.sql) | GRANT/DENY/REVOKE + AAD(T-SQL) |
| [Databricks SQL](databricks.sql) | Unity Catalog GRANT/REVOKE |
| [Greenplum](greenplum.sql) | PG 兼容 GRANT/REVOKE |
| [Impala](impala.sql) | Ranger/Sentry 外部授权 |
| [Vertica](vertica.sql) | GRANT/REVOKE + ROLE，列级权限 |
| [Teradata](teradata.sql) | GRANT/REVOKE，对象级精细控制 |

### 分布式 / NewSQL
| 方言 | 简评 |
|---|---|
| [TiDB](tidb.sql) | MySQL 兼容 GRANT/REVOKE |
| [OceanBase](oceanbase.sql) | MySQL/Oracle 双模式权限 |
| [CockroachDB](cockroachdb.sql) | PG 兼容 GRANT/REVOKE |
| [Spanner](spanner.sql) | IAM 权限，细粒度访问控制 |
| [YugabyteDB](yugabytedb.sql) | PG 兼容 GRANT/REVOKE + RLS |
| [PolarDB](polardb.sql) | MySQL 兼容权限 |
| [openGauss](opengauss.sql) | PG 兼容 + 行级安全 |
| [TDSQL](tdsql.sql) | MySQL 兼容，分布式权限同步 |

### 国产数据库
| 方言 | 简评 |
|---|---|
| [DamengDB](dameng.sql) | Oracle 兼容权限体系 |
| [KingbaseES](kingbase.sql) | PG 兼容 |

### 时序数据库
| 方言 | 简评 |
|---|---|
| [TimescaleDB](timescaledb.sql) | 继承 PG 权限 + RLS |
| [TDengine](tdengine.sql) | SUPER/NORMAL 两级权限 |

### 流处理
| 方言 | 简评 |
|---|---|
| [ksqlDB](ksqldb.sql) | Kafka ACL + RBAC(Confluent) |
| [Materialize](materialize.sql) | PG 兼容 RBAC |

### 嵌入式 / 轻量
| 方言 | 简评 |
|---|---|
| [H2](h2.sql) | 简单用户权限 |
| [Derby](derby.sql) | GRANT/REVOKE 标准支持 |

### SQL 标准
| 方言 | 简评 |
|---|---|
| [SQL Standard](sql-standard.sql) | SQL:2003 GRANT/REVOKE/ROLE 规范 |

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

## 引擎开发者视角

**核心设计决策**：权限系统是安全性的基石，设计不当会导致安全漏洞或管理噩梦。核心抉择：RBAC（基于角色的访问控制）vs ABAC（基于属性的访问控制），以及权限检查的粒度和性能开销。

**实现建议**：
- 从第一天就采用 ROLE 统一模型（PostgreSQL 方式）——USER 和 ROLE 使用相同的底层对象，ROLE 可以继承、嵌套和授权。MySQL 直到 8.0 才加入 ROLE 是设计教训
- GRANT/REVOKE 的粒度层次推荐：全局 -> 数据库 -> 表 -> 列 -> 行。列级权限实现不复杂但很有用，行级安全（Row-Level Security）实现复杂但对多租户场景至关重要
- DEFAULT PRIVILEGES（PostgreSQL 特性）应从一开始就支持——新创建的对象自动继承权限，否则 DBA 需要在每次 CREATE TABLE 后手动 GRANT，运维成本极高
- 权限检查的性能需要特别关注：每条查询都要做权限验证，缓存权限检查结果（per-session 或 per-transaction）是必要的优化
- 云原生引擎应考虑 IAM 集成（如 BigQuery 的做法），但同时保留 SQL GRANT 接口以兼容传统工具链
- 常见错误：GRANT WITH GRANT OPTION 的级联撤销语义容易出错。REVOKE 级联时是否自动撤销被授权者再授出去的权限，需要明确定义并文档化
