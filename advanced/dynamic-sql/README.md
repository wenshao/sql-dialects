# 动态 SQL (DYNAMIC SQL)

各数据库动态 SQL 语法对比，包括 EXECUTE IMMEDIATE、PREPARE、游标等。

> [对比总览表](_comparison.md) -- 横向对比各方言特性支持

## 方言列表

### 传统关系型数据库
| 方言 | 简评 |
|---|---|
| [MySQL](mysql.sql) | PREPARE/EXECUTE/DEALLOCATE，存储过程内动态 |
| [PostgreSQL](postgres.sql) | EXECUTE format()，PL/pgSQL 动态 SQL |
| [SQLite](sqlite.sql) | C API sqlite3_prepare()，无过程式 SQL |
| [Oracle](oracle.sql) | EXECUTE IMMEDIATE/DBMS_SQL，NDS 原生动态 |
| [SQL Server](sqlserver.sql) | sp_executesql/EXEC()，参数化支持 |
| [MariaDB](mariadb.sql) | 兼容 MySQL PREPARE/EXECUTE |
| [Firebird](firebird.sql) | EXECUTE STATEMENT，过程式动态 SQL |
| [IBM Db2](db2.sql) | PREPARE/EXECUTE/EXECUTE IMMEDIATE |
| [SAP HANA](saphana.sql) | EXEC/EXECUTE IMMEDIATE，SQLScript 内 |

### 大数据 / 分析型引擎
| 方言 | 简评 |
|---|---|
| [BigQuery](bigquery.sql) | EXECUTE IMMEDIATE(脚本模式) |
| [Snowflake](snowflake.sql) | EXECUTE IMMEDIATE(Snowflake Scripting) |
| [ClickHouse](clickhouse.sql) | 无过程式 SQL，客户端拼接 |
| [Hive](hive.sql) | 无动态 SQL，依赖 HiveQL 脚本 |
| [Spark SQL](spark.sql) | 无原生动态 SQL，用 DataFrame API |
| [Flink SQL](flink.sql) | 无动态 SQL 支持 |
| [StarRocks](starrocks.sql) | 无动态 SQL 支持 |
| [Doris](doris.sql) | 无动态 SQL 支持 |
| [Trino](trino.sql) | 无动态 SQL 支持 |
| [DuckDB](duckdb.sql) | 无过程式 SQL，客户端 API |
| [MaxCompute](maxcompute.sql) | 无动态 SQL，用 PyODPS 脚本 |
| [Hologres](hologres.sql) | PG 兼容 EXECUTE format() |

### 云数仓
| 方言 | 简评 |
|---|---|
| [Redshift](redshift.sql) | 无存储过程动态 SQL(用客户端) |
| [Azure Synapse](synapse.sql) | sp_executesql(T-SQL 兼容) |
| [Databricks SQL](databricks.sql) | 无动态 SQL，用 Python/Scala |
| [Greenplum](greenplum.sql) | PG 兼容 EXECUTE format() |
| [Impala](impala.sql) | 无动态 SQL 支持 |
| [Vertica](vertica.sql) | 无存储过程动态 SQL |
| [Teradata](teradata.sql) | EXECUTE IMMEDIATE(存储过程内) |

### 分布式 / NewSQL
| 方言 | 简评 |
|---|---|
| [TiDB](tidb.sql) | MySQL 兼容 PREPARE/EXECUTE |
| [OceanBase](oceanbase.sql) | MySQL/Oracle 双模式动态 SQL |
| [CockroachDB](cockroachdb.sql) | PG 兼容 EXECUTE format() |
| [Spanner](spanner.sql) | 客户端参数化查询为主 |
| [YugabyteDB](yugabytedb.sql) | PG 兼容 EXECUTE format() |
| [PolarDB](polardb.sql) | MySQL 兼容 PREPARE/EXECUTE |
| [openGauss](opengauss.sql) | PG 兼容动态 SQL |
| [TDSQL](tdsql.sql) | MySQL 兼容 PREPARE/EXECUTE |

### 国产数据库
| 方言 | 简评 |
|---|---|
| [DamengDB](dameng.sql) | EXECUTE IMMEDIATE(Oracle 兼容) |
| [KingbaseES](kingbase.sql) | PG 兼容 |

### 时序数据库
| 方言 | 简评 |
|---|---|
| [TimescaleDB](timescaledb.sql) | 继承 PG 动态 SQL |
| [TDengine](tdengine.sql) | 无动态 SQL 支持 |

### 流处理
| 方言 | 简评 |
|---|---|
| [ksqlDB](ksqldb.sql) | 无动态 SQL 支持 |
| [Materialize](materialize.sql) | PG 兼容 EXECUTE |

### 嵌入式 / 轻量
| 方言 | 简评 |
|---|---|
| [H2](h2.sql) | PREPARE/EXECUTE 支持 |
| [Derby](derby.sql) | PREPARE/EXECUTE 支持(JDBC) |

### SQL 标准
| 方言 | 简评 |
|---|---|
| [SQL Standard](sql-standard.sql) | SQL:2003 PREPARE/EXECUTE 规范 |

## 核心差异

1. **执行方式**：MySQL 用 PREPARE + EXECUTE + DEALLOCATE，PostgreSQL 用 EXECUTE（PL/pgSQL 中）或 PREPARE，Oracle 用 EXECUTE IMMEDIATE，SQL Server 用 sp_executesql 或 EXEC()
2. **参数绑定**：PostgreSQL/Oracle/SQL Server 支持参数化动态 SQL（防注入），MySQL 的 PREPARE 支持 `?` 占位符
3. **安全风险**：动态 SQL 是 SQL 注入的主要入口，必须使用参数绑定而非字符串拼接
4. **分析型引擎**：大多数分析型引擎不支持存储过程内的动态 SQL，BigQuery 的 EXECUTE IMMEDIATE 是例外

## 选型建议

动态 SQL 应作为最后手段使用：表名/列名动态时无法避免，但 WHERE 条件值应始终用参数绑定。生产环境的动态 SQL 必须做白名单校验（只允许预定义的表名/列名）。优先考虑用 ORM 或应用层生成 SQL 替代数据库内的动态 SQL。

## 版本演进

- BigQuery：引入 EXECUTE IMMEDIATE 支持脚本中的动态 SQL
- Snowflake：存储过程中支持 JavaScript 拼接和执行 SQL
- PostgreSQL：PL/pgSQL 的 EXECUTE 一直是动态 SQL 的标准方式，支持 USING 参数绑定

## 横向对比

| 特性维度 | SQLite | ClickHouse | BigQuery | 传统 RDBMS (MySQL/PG/Oracle) |
|---|---|---|---|---|
| **动态 SQL** | 不支持（无存储过程，应用层拼接 SQL） | 不支持数据库端动态 SQL | 支持 EXECUTE IMMEDIATE（Scripting 中） | MySQL PREPARE/EXECUTE / PG EXECUTE / Oracle EXECUTE IMMEDIATE |
| **参数绑定** | 应用层 API 支持参数化查询（防注入） | 应用层参数化 | EXECUTE IMMEDIATE 支持 USING 参数绑定 | 各方言均支持参数绑定 |
| **安全风险** | 应用层拼接 SQL 需防注入 | 应用层拼接 SQL 需防注入 | EXECUTE IMMEDIATE 需防注入 | 存储过程内动态 SQL 需防注入 |
| **适用场景** | 应用层动态生成查询是唯一方式 | 应用层动态生成查询 | 报表/ETL 脚本中的动态表名/列名 | 动态报表、通用查询接口、DDL 脚本 |

## 引擎开发者视角

**核心设计决策**：是否在引擎中支持动态 SQL，以及支持到什么程度。需要权衡：完整的 EXECUTE IMMEDIATE 实现复杂度高，但对存储过程/脚本场景不可或缺。

**实现建议**：
- 最小可行方案：支持 EXECUTE IMMEDIATE 配合参数化绑定（USING 子句），满足动态表名/列名场景
- 参数绑定必须从第一天就支持——没有参数绑定的动态 SQL 等于给用户一把加载好的枪。MySQL 的 PREPARE/EXECUTE 模式实现简单但需要额外的 DEALLOCATE 步骤，PostgreSQL 的 PL/pgSQL EXECUTE ... USING 更优雅
- 分析型引擎可以只在 Scripting/存储过程层面支持动态 SQL，不必在交互式 SQL 层实现
- 动态 SQL 的执行计划缓存是难点：每次 EXECUTE IMMEDIATE 都要重新解析和优化，考虑提供 PREPARE 语义让用户可以复用执行计划
- 安全层面，引擎应提供 quote_ident()/quote_literal() 等辅助函数帮助用户安全地构造动态 SQL，而非把防注入完全推给用户
- 常见错误：允许动态 SQL 绕过权限检查。动态执行的 SQL 必须在调用者或定义者的权限上下文中运行
