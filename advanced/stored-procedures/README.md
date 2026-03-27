# 存储过程 (STORED PROCEDURES)

各数据库存储过程语法对比，包括创建、参数、变量、游标、异常处理等。

> [对比总览表](_comparison.md) -- 横向对比各方言特性支持

## 方言列表

### 传统关系型数据库
| 方言 | 简评 |
|---|---|
| [MySQL](mysql.sql) | CREATE PROCEDURE，DELIMITER 定义，游标支持 |
| [PostgreSQL](postgres.sql) | CREATE PROCEDURE(11+)/FUNCTION，PL/pgSQL |
| [SQLite](sqlite.sql) | 无存储过程支持 |
| [Oracle](oracle.sql) | PL/SQL 包(PACKAGE)/过程/函数，最成熟 |
| [SQL Server](sqlserver.sql) | T-SQL 存储过程，丰富系统 SP |
| [MariaDB](mariadb.sql) | 兼容 MySQL 存储过程，Oracle 模式(10.3+) |
| [Firebird](firebird.sql) | PSQL 过程/函数，EXECUTE BLOCK |
| [IBM Db2](db2.sql) | SQL PL 过程/函数，C/Java 外部过程 |
| [SAP HANA](saphana.sql) | SQLScript 过程，CE 函数 |

### 大数据 / 分析型引擎
| 方言 | 简评 |
|---|---|
| [BigQuery](bigquery.sql) | CREATE PROCEDURE(脚本)，JavaScript UDF |
| [Snowflake](snowflake.sql) | Snowflake Scripting/JavaScript/Python 过程 |
| [ClickHouse](clickhouse.sql) | 无存储过程支持 |
| [Hive](hive.sql) | 无存储过程(UDF/UDAF 替代) |
| [Spark SQL](spark.sql) | 无存储过程(Scala/Python 替代) |
| [Flink SQL](flink.sql) | 无存储过程支持 |
| [StarRocks](starrocks.sql) | 无存储过程支持 |
| [Doris](doris.sql) | 无存储过程支持 |
| [Trino](trino.sql) | 无存储过程支持 |
| [DuckDB](duckdb.sql) | 无存储过程支持 |
| [MaxCompute](maxcompute.sql) | 无存储过程(PyODPS/DataWorks 替代) |
| [Hologres](hologres.sql) | PG 兼容 PL/pgSQL 过程 |

### 云数仓
| 方言 | 简评 |
|---|---|
| [Redshift](redshift.sql) | CREATE PROCEDURE(PL/pgSQL 子集) |
| [Azure Synapse](synapse.sql) | T-SQL 存储过程(与 SQL Server 兼容) |
| [Databricks SQL](databricks.sql) | 无存储过程(Notebook 替代) |
| [Greenplum](greenplum.sql) | PG 兼容 PL/pgSQL |
| [Impala](impala.sql) | 无存储过程支持 |
| [Vertica](vertica.sql) | 无存储过程(UDx 替代) |
| [Teradata](teradata.sql) | SQL 存储过程 + BTEQ 脚本 |

### 分布式 / NewSQL
| 方言 | 简评 |
|---|---|
| [TiDB](tidb.sql) | MySQL 兼容存储过程(有限) |
| [OceanBase](oceanbase.sql) | MySQL/Oracle 双模式过程 |
| [CockroachDB](cockroachdb.sql) | PG 兼容 PL/pgSQL(23.1+) |
| [Spanner](spanner.sql) | 无存储过程支持 |
| [YugabyteDB](yugabytedb.sql) | PG 兼容 PL/pgSQL |
| [PolarDB](polardb.sql) | MySQL 兼容存储过程 |
| [openGauss](opengauss.sql) | PG 兼容 + Oracle PL/SQL 兼容 |
| [TDSQL](tdsql.sql) | MySQL 兼容存储过程 |

### 国产数据库
| 方言 | 简评 |
|---|---|
| [DamengDB](dameng.sql) | PL/SQL 兼容(Oracle 风格) |
| [KingbaseES](kingbase.sql) | PG 兼容 PL/pgSQL |

### 时序数据库
| 方言 | 简评 |
|---|---|
| [TimescaleDB](timescaledb.sql) | 继承 PG PL/pgSQL |
| [TDengine](tdengine.sql) | 无存储过程支持 |

### 流处理
| 方言 | 简评 |
|---|---|
| [ksqlDB](ksqldb.sql) | 无存储过程支持 |
| [Materialize](materialize.sql) | 无存储过程支持 |

### 嵌入式 / 轻量
| 方言 | 简评 |
|---|---|
| [H2](h2.sql) | 无原生存储过程(Java Alias) |
| [Derby](derby.sql) | Java 存储过程(SQL/JRT) |

### SQL 标准
| 方言 | 简评 |
|---|---|
| [SQL Standard](sql-standard.sql) | SQL:2003 SQL/PSM 过程规范 |

## 核心差异

1. **过程式语言**：MySQL 用 SQL/PSM（BEGIN...END），PostgreSQL 用 PL/pgSQL（DECLARE...BEGIN...END），Oracle 用 PL/SQL，SQL Server 用 T-SQL，四种语法几乎完全不同
2. **CREATE PROCEDURE vs FUNCTION**：PostgreSQL 11 之前只有 FUNCTION（用 RETURNS VOID 模拟 PROCEDURE），11+ 才支持真正的 PROCEDURE 和事务控制
3. **返回结果集**：MySQL 过程可直接执行 SELECT 返回结果集，PostgreSQL 需要 RETURNS TABLE 或 REFCURSOR，Oracle 用 SYS_REFCURSOR
4. **分析型引擎支持**：BigQuery 支持 Scripting（过程式 SQL），Snowflake 支持 JavaScript/Python 存储过程，ClickHouse/Hive 不支持存储过程

## 选型建议

现代架构趋势是将业务逻辑从存储过程移到应用层，存储过程主要用于：DBA 的维护脚本、数据迁移/ETL、性能关键的批处理。新项目不建议重度依赖存储过程（可移植性差、版本控制困难、调试不便）。

## 版本演进

- PostgreSQL 11+：引入 CREATE PROCEDURE（支持事务控制 COMMIT/ROLLBACK）
- BigQuery 2019+：引入 Scripting 和存储过程支持
- Snowflake：支持 JavaScript/SQL/Python/Scala 编写存储过程，多语言支持是独特优势

## 横向对比

| 特性维度 | SQLite | ClickHouse | BigQuery | 传统 RDBMS (MySQL/PG/Oracle) |
|---|---|---|---|---|
| **存储过程** | 不支持存储过程（无过程式语言） | 不支持存储过程 | 支持 Scripting 和 CREATE PROCEDURE | MySQL/PG/Oracle/SQL Server 各有独立过程式语言 |
| **替代方案** | 应用层（Python/Java 等）实现逻辑 | 用物化视图 + 定时任务实现 ETL 逻辑 | EXECUTE IMMEDIATE + Scripting 实现动态逻辑 | 存储过程 + 触发器 |
| **UDF 支持** | 可通过 C API 注册自定义函数 | 支持 UDF（C++/SQL） | 支持 UDF（SQL/JavaScript） | 各方言支持 UDF |
| **事务控制** | 应用层管理事务 | 无事务控制 | Scripting 中无显式事务控制 | PG 11+ PROCEDURE 支持事务控制 |
| **调试能力** | 无数据库端调试 | 无存储过程调试 | 有限的错误信息 | 各方言有不同的调试工具 |

## 引擎开发者视角

**核心设计决策**：是否实现存储过程，以及选择什么过程式语言。这是引擎功能范围的重大决策——存储过程为引擎增加了一个完整的编程运行时。

**实现建议**：
- 新引擎不建议自研过程式语言——维护成本极高且用户学习曲线陡峭。推荐方案：嵌入已有语言运行时（JavaScript V8/Python/Lua），Snowflake 的多语言存储过程是成功案例
- 如果必须支持 SQL 过程式语言，优先兼容 PL/pgSQL 或 MySQL 的 BEGIN...END 语法——用户基数大，迁移门槛低
- PROCEDURE vs FUNCTION 的区别必须明确：PROCEDURE 可以有事务控制（COMMIT/ROLLBACK）和多结果集，FUNCTION 是表达式的一部分且有确定性要求。PostgreSQL 11 之前混淆两者是设计负债
- 安全上下文（DEFINER vs INVOKER）决定存储过程以谁的权限运行。两者都要支持，默认推荐 INVOKER（更安全）
- 返回结果集的方式需要统一设计：直接 SELECT（MySQL 风格）最简单，RETURNS TABLE（PostgreSQL 风格）类型更安全，REFCURSOR（Oracle 风格）最灵活但最复杂
- 常见错误：忽略存储过程的执行计划缓存问题。过程体内的 SQL 应该有独立的计划缓存——每次调用都重新编译会导致严重的性能问题
