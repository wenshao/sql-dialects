# 错误处理 (ERROR HANDLING)

各数据库错误处理语法对比，包括 TRY-CATCH、EXCEPTION、HANDLER 等。

> [对比总览表](_comparison.md) -- 横向对比各方言特性支持

## 方言列表

### 传统关系型数据库
| 方言 | 简评 |
|---|---|
| [MySQL](mysql.sql) | DECLARE HANDLER(CONTINUE/EXIT)，SIGNAL/RESIGNAL |
| [PostgreSQL](postgres.sql) | EXCEPTION WHEN 块，RAISE NOTICE/EXCEPTION |
| [SQLite](sqlite.sql) | C API 错误码，无过程式错误处理 |
| [Oracle](oracle.sql) | EXCEPTION WHEN 块，RAISE_APPLICATION_ERROR |
| [SQL Server](sqlserver.sql) | TRY...CATCH 块，RAISERROR/THROW |
| [MariaDB](mariadb.sql) | 兼容 MySQL HANDLER/SIGNAL |
| [Firebird](firebird.sql) | WHEN...DO 块，EXCEPTION 自定义异常 |
| [IBM Db2](db2.sql) | DECLARE HANDLER + SIGNAL/RESIGNAL |
| [SAP HANA](saphana.sql) | DECLARE EXIT HANDLER，CE_RAISE |

### 大数据 / 分析型引擎
| 方言 | 简评 |
|---|---|
| [BigQuery](bigquery.sql) | BEGIN...EXCEPTION...END(脚本模式) |
| [Snowflake](snowflake.sql) | EXCEPTION WHEN(Snowflake Scripting) |
| [ClickHouse](clickhouse.sql) | 无过程式错误处理 |
| [Hive](hive.sql) | 无错误处理语法 |
| [Spark SQL](spark.sql) | 无 SQL 级错误处理，用 Scala/Python |
| [Flink SQL](flink.sql) | 无错误处理语法 |
| [StarRocks](starrocks.sql) | 无错误处理语法 |
| [Doris](doris.sql) | 无错误处理语法 |
| [Trino](trino.sql) | 无错误处理语法 |
| [DuckDB](duckdb.sql) | 无过程式错误处理 |
| [MaxCompute](maxcompute.sql) | 无错误处理语法，依赖调度 |
| [Hologres](hologres.sql) | PG 兼容 EXCEPTION WHEN |

### 云数仓
| 方言 | 简评 |
|---|---|
| [Redshift](redshift.sql) | 存储过程 RAISE 支持 |
| [Azure Synapse](synapse.sql) | TRY...CATCH(T-SQL 兼容) |
| [Databricks SQL](databricks.sql) | 无 SQL 级错误处理 |
| [Greenplum](greenplum.sql) | PG 兼容 EXCEPTION WHEN |
| [Impala](impala.sql) | 无错误处理语法 |
| [Vertica](vertica.sql) | 无过程式错误处理 |
| [Teradata](teradata.sql) | HANDLER 支持(存储过程内) |

### 分布式 / NewSQL
| 方言 | 简评 |
|---|---|
| [TiDB](tidb.sql) | MySQL 兼容 HANDLER/SIGNAL |
| [OceanBase](oceanbase.sql) | MySQL/Oracle 双模式错误处理 |
| [CockroachDB](cockroachdb.sql) | PG 兼容 EXCEPTION WHEN |
| [Spanner](spanner.sql) | 客户端异常处理为主 |
| [YugabyteDB](yugabytedb.sql) | PG 兼容 EXCEPTION WHEN |
| [PolarDB](polardb.sql) | MySQL 兼容错误处理 |
| [openGauss](opengauss.sql) | PG 兼容 EXCEPTION WHEN |
| [TDSQL](tdsql.sql) | MySQL 兼容错误处理 |

### 国产数据库
| 方言 | 简评 |
|---|---|
| [DamengDB](dameng.sql) | Oracle 兼容 EXCEPTION WHEN |
| [KingbaseES](kingbase.sql) | PG 兼容 |

### 时序数据库
| 方言 | 简评 |
|---|---|
| [TimescaleDB](timescaledb.sql) | 继承 PG 错误处理 |
| [TDengine](tdengine.sql) | 无错误处理语法 |

### 流处理
| 方言 | 简评 |
|---|---|
| [ksqlDB](ksqldb.sql) | 无错误处理语法 |
| [Materialize](materialize.sql) | PG 兼容错误处理 |

### 嵌入式 / 轻量
| 方言 | 简评 |
|---|---|
| [H2](h2.sql) | 无过程式错误处理 |
| [Derby](derby.sql) | DECLARE HANDLER 支持(SQL/JRT) |

### SQL 标准
| 方言 | 简评 |
|---|---|
| [SQL Standard](sql-standard.sql) | SQL:2003 HANDLER/SIGNAL/RESIGNAL |

## 核心差异

1. **语法体系**：SQL Server 用 TRY...CATCH，PostgreSQL 用 EXCEPTION WHEN（PL/pgSQL BEGIN 块中），Oracle 用 EXCEPTION WHEN（PL/SQL），MySQL 用 DECLARE HANDLER
2. **错误代码**：PostgreSQL 使用 5 字符 SQLSTATE 代码（如 '23505' 唯一违反），MySQL 有自己的错误号体系，Oracle 有 ORA-xxxxx 错误号
3. **RAISE/SIGNAL**：PostgreSQL 用 RAISE EXCEPTION/NOTICE/WARNING，MySQL 用 SIGNAL SQLSTATE，Oracle 用 RAISE_APPLICATION_ERROR()，SQL Server 用 THROW/RAISERROR
4. **事务回滚行为**：PostgreSQL 的异常处理会自动回滚到 BEGIN 块开始的 SAVEPOINT，MySQL 不自动回滚需要显式处理

## 选型建议

错误处理逻辑几乎无法跨方言复用，迁移时需要完全重写。建议将错误处理逻辑保持简单：记录错误日志、回滚事务、返回错误代码。复杂的错误恢复逻辑最好放在应用层而非数据库层。

## 版本演进

- MySQL 5.5+：引入 SIGNAL/RESIGNAL 语法（替代之前非标准的错误处理）
- PostgreSQL：PL/pgSQL 的 EXCEPTION 处理一直很强大，支持获取异常详情（SQLSTATE, SQLERRM, PG_EXCEPTION_DETAIL 等）
- SQL Server 2012+：引入 THROW 语句替代 RAISERROR（语法更简洁）

## 横向对比

| 特性维度 | SQLite | ClickHouse | BigQuery | 传统 RDBMS (MySQL/PG/Oracle) |
|---|---|---|---|---|
| **错误处理** | 无数据库端错误处理，应用层通过返回码判断（SQLITE_OK/SQLITE_ERROR 等） | 无存储过程级错误处理，查询失败返回错误 | Scripting 中支持 BEGIN...EXCEPTION WHEN ERROR THEN... | MySQL DECLARE HANDLER / PG EXCEPTION WHEN / Oracle EXCEPTION |
| **错误代码** | SQLITE_xxx 返回码体系 | HTTP 错误码 + 内部错误消息 | 标准 GoogleSQL 错误消息 | PG SQLSTATE / MySQL 错误号 / Oracle ORA-xxxxx |
| **重试机制** | 应用层处理 SQLITE_BUSY 重试 | 应用层重试失败查询 | 应用层重试，Scripting 中可 CATCH 后重试 | 存储过程内可 RETRY 逻辑 |
| **事务回滚** | 错误时应用层决定是否 ROLLBACK | 无事务回滚概念 | 无跨语句事务 | PG EXCEPTION 自动回滚到 SAVEPOINT |

## 引擎开发者视角

**核心设计决策**：错误处理模型的选择直接影响引擎的可用性和调试体验。TRY-CATCH（结构化异常处理）vs DECLARE HANDLER（条件处理器）vs EXCEPTION WHEN（PL/pgSQL 风格）三种范式各有优劣。

**实现建议**：
- 推荐采用 TRY-CATCH 模型——用户学习成本低，与应用层编程语言的异常处理模式一致
- 错误码体系设计至关重要：推荐遵循 SQL 标准的 5 字符 SQLSTATE 编码（如 23505 唯一违反），而非自定义数字错误码。SQLSTATE 已被广泛认知且有标准分类
- RAISE/SIGNAL 语句应同时支持设置 SQLSTATE、错误消息和错误详情，PostgreSQL 的 RAISE EXCEPTION '消息' USING DETAIL='详情', HINT='建议' 是优秀设计范例
- 异常与事务的交互是实现难点：PostgreSQL 模式（异常自动回滚到 SAVEPOINT）用户体验更好但实现更复杂，MySQL 模式（不自动回滚）实现简单但容易导致数据不一致
- 错误堆栈信息（GET DIAGNOSTICS / GET STACKED DIAGNOSTICS）对调试至关重要，不要只返回错误码和消息
- 常见错误：异常处理后不清理事务状态。还有一个陷阱是 HANDLER 的作用域规则——MySQL 的 CONTINUE HANDLER 和 EXIT HANDLER 语义复杂，新引擎不建议采用
