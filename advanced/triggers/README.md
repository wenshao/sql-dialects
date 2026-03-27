# 触发器 (TRIGGERS)

各数据库触发器语法对比，包括 BEFORE/AFTER、行级/语句级触发器。

> [对比总览表](_comparison.md) -- 横向对比各方言特性支持

## 方言列表

### 传统关系型数据库
| 方言 | 简评 |
|---|---|
| [MySQL](mysql.sql) | BEFORE/AFTER + INSERT/UPDATE/DELETE，行级 |
| [PostgreSQL](postgres.sql) | 行/语句级触发器，INSTEAD OF，事件触发器 |
| [SQLite](sqlite.sql) | BEFORE/AFTER/INSTEAD OF 触发器 |
| [Oracle](oracle.sql) | 行/语句/COMPOUND/DDL 触发器，FOLLOWS 排序 |
| [SQL Server](sqlserver.sql) | AFTER/INSTEAD OF 触发器，DDL 触发器 |
| [MariaDB](mariadb.sql) | 兼容 MySQL 触发器 |
| [Firebird](firebird.sql) | BEFORE/AFTER 触发器，多触发器排序 |
| [IBM Db2](db2.sql) | BEFORE/AFTER/INSTEAD OF 触发器 |
| [SAP HANA](saphana.sql) | 行/语句级触发器 |

### 大数据 / 分析型引擎
| 方言 | 简评 |
|---|---|
| [BigQuery](bigquery.sql) | 无触发器支持 |
| [Snowflake](snowflake.sql) | 无触发器支持(Stream+Task 替代) |
| [ClickHouse](clickhouse.sql) | 无触发器(MATERIALIZED VIEW 替代) |
| [Hive](hive.sql) | 无触发器支持 |
| [Spark SQL](spark.sql) | 无触发器支持 |
| [Flink SQL](flink.sql) | 无触发器(流式处理替代) |
| [StarRocks](starrocks.sql) | 无触发器支持 |
| [Doris](doris.sql) | 无触发器支持 |
| [Trino](trino.sql) | 无触发器支持 |
| [DuckDB](duckdb.sql) | 无触发器支持 |
| [MaxCompute](maxcompute.sql) | 无触发器支持 |
| [Hologres](hologres.sql) | 无触发器支持 |

### 云数仓
| 方言 | 简评 |
|---|---|
| [Redshift](redshift.sql) | 无触发器支持 |
| [Azure Synapse](synapse.sql) | 无触发器支持 |
| [Databricks SQL](databricks.sql) | 无触发器(Delta Live Tables 替代) |
| [Greenplum](greenplum.sql) | PG 兼容触发器 |
| [Impala](impala.sql) | 无触发器支持 |
| [Vertica](vertica.sql) | 无触发器支持 |
| [Teradata](teradata.sql) | 无触发器支持(ETL 工具替代) |

### 分布式 / NewSQL
| 方言 | 简评 |
|---|---|
| [TiDB](tidb.sql) | 无触发器支持 |
| [OceanBase](oceanbase.sql) | Oracle 模式触发器支持 |
| [CockroachDB](cockroachdb.sql) | 无触发器支持(CDC 替代) |
| [Spanner](spanner.sql) | 无触发器支持 |
| [YugabyteDB](yugabytedb.sql) | PG 兼容触发器 |
| [PolarDB](polardb.sql) | MySQL 兼容触发器 |
| [openGauss](opengauss.sql) | PG 兼容触发器 |
| [TDSQL](tdsql.sql) | MySQL 兼容触发器 |

### 国产数据库
| 方言 | 简评 |
|---|---|
| [DamengDB](dameng.sql) | Oracle 兼容触发器 |
| [KingbaseES](kingbase.sql) | PG 兼容 |

### 时序数据库
| 方言 | 简评 |
|---|---|
| [TimescaleDB](timescaledb.sql) | 继承 PG 触发器 |
| [TDengine](tdengine.sql) | 无触发器支持 |

### 流处理
| 方言 | 简评 |
|---|---|
| [ksqlDB](ksqldb.sql) | 无触发器(流处理替代) |
| [Materialize](materialize.sql) | 无触发器(增量计算替代) |

### 嵌入式 / 轻量
| 方言 | 简评 |
|---|---|
| [H2](h2.sql) | BEFORE/AFTER 触发器(Java) |
| [Derby](derby.sql) | AFTER 触发器(行/语句级) |

### SQL 标准
| 方言 | 简评 |
|---|---|
| [SQL Standard](sql-standard.sql) | SQL:2003 TRIGGER 规范 |

## 核心差异

1. **触发器时机**：PostgreSQL/Oracle 支持 BEFORE/AFTER/INSTEAD OF，MySQL 支持 BEFORE/AFTER（不支持 INSTEAD OF），SQL Server 用 INSTEAD OF 和 AFTER（不支持 BEFORE）
2. **行级 vs 语句级**：PostgreSQL/Oracle 支持 FOR EACH ROW 和 FOR EACH STATEMENT，MySQL 只支持 FOR EACH ROW，SQL Server 只支持语句级
3. **触发器函数**：PostgreSQL 的触发器必须先创建触发器函数再绑定到表，MySQL/SQL Server 直接在 CREATE TRIGGER 中写逻辑
4. **引用新旧值**：MySQL 用 NEW/OLD，PostgreSQL 用 NEW/OLD（在触发器函数中），SQL Server 用 INSERTED/DELETED 伪表，Oracle 用 :NEW/:OLD

## 选型建议

触发器应谨慎使用：它们使数据流变得隐式、调试困难、影响写入性能。适用场景：审计日志、自动维护冗余字段、强制业务规则。分析型引擎大多不支持触发器（ClickHouse 的物化视图可实现类似增量处理的效果）。

## 版本演进

- PostgreSQL 10+：支持在分区表上创建触发器（自动应用到所有分区）
- MySQL 5.7+：允许同一事件的多个触发器（FOLLOWS/PRECEDES 控制顺序）
- 触发器的总体趋势是被应用层事件、CDC（Change Data Capture）等机制替代

## 横向对比

| 特性维度 | SQLite | ClickHouse | BigQuery | 传统 RDBMS (MySQL/PG/Oracle) |
|---|---|---|---|---|
| **触发器支持** | 支持 BEFORE/AFTER/INSTEAD OF 触发器 | 不支持传统触发器（物化视图实现类似的增量处理） | 不支持触发器 | MySQL BEFORE/AFTER / PG 全部 / Oracle 全部 |
| **触发器类型** | FOR EACH ROW（行级） | 无 | 无 | MySQL 行级 / PG 行级+语句级 / SQL Server 语句级 |
| **替代方案** | 触发器是唯一的数据库端自动化 | 物化视图（INSERT 触发增量更新目标表） | Cloud Functions / Pub/Sub 事件驱动 | CDC（Change Data Capture）/ 事件驱动架构 |
| **NEW/OLD 引用** | NEW/OLD 关键字 | 无 | 无 | MySQL NEW/OLD / PG NEW/OLD / SQL Server INSERTED/DELETED |
| **权限需求** | 无权限限制（文件可写即可创建触发器） | 无触发器 | 无触发器 | 需要 TRIGGER 权限 |

## 引擎开发者视角

**核心设计决策**：触发器给引擎增加了隐式执行路径——DML 操作可能触发用户定义的代码。这增加了执行计划的复杂性和性能的不可预测性。是否支持、支持到什么程度是重要决策。

**实现建议**：
- 如果目标是 OLTP 引擎，BEFORE/AFTER 行级触发器是基本需求。语句级触发器可延后实现。INSTEAD OF 触发器主要用于可更新视图，优先级更低
- PostgreSQL 的触发器函数模型（先创建函数再绑定）比 MySQL 的内联模型更灵活——同一个函数可以绑定到多个表，代码复用性好。新引擎推荐采用函数绑定模式
- NEW/OLD 伪记录的实现要注意性能：行级触发器在每行 DML 时都要构造 NEW/OLD 记录，批量操作时开销显著。考虑提供批量触发器（statement-level 触发器 + 转换表）减少调用次数
- 触发器的执行顺序必须有明确规则：同一事件的多个触发器按创建顺序还是名称顺序执行？MySQL 5.7 的 FOLLOWS/PRECEDES 让用户显式控制顺序是好设计
- 分析型/分布式引擎可以用 CDC（Change Data Capture）或物化视图替代触发器——ClickHouse 的物化视图在 INSERT 时增量更新就是优秀的替代方案
- 常见错误：触发器中执行的 DML 再次触发触发器导致无限递归。必须有递归深度限制和检测机制
