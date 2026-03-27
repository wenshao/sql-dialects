# 临时表 (TEMPORARY TABLES)

各数据库临时表语法对比，包括局部临时表、全局临时表等。

> [对比总览表](_comparison.md) -- 横向对比各方言特性支持

## 方言列表

### 传统关系型数据库
| 方言 | 简评 |
|---|---|
| [MySQL](mysql.sql) | CREATE TEMPORARY TABLE，会话级 |
| [PostgreSQL](postgres.sql) | TEMP TABLE + ON COMMIT(DROP/DELETE/PRESERVE) |
| [SQLite](sqlite.sql) | TEMP TABLE(内存或临时文件) |
| [Oracle](oracle.sql) | GTT(Global Temp Table)，事务/会话级 |
| [SQL Server](sqlserver.sql) | #local/##global 临时表，@表变量 |
| [MariaDB](mariadb.sql) | 兼容 MySQL TEMPORARY TABLE |
| [Firebird](firebird.sql) | GTT(ON COMMIT PRESERVE/DELETE ROWS) |
| [IBM Db2](db2.sql) | DECLARE GLOBAL TEMPORARY TABLE |
| [SAP HANA](saphana.sql) | LOCAL/GLOBAL TEMPORARY TABLE |

### 大数据 / 分析型引擎
| 方言 | 简评 |
|---|---|
| [BigQuery](bigquery.sql) | TEMP TABLE(脚本内)，过期自动清理 |
| [Snowflake](snowflake.sql) | TEMPORARY/TRANSIENT TABLE |
| [ClickHouse](clickhouse.sql) | 无显式临时表(用 Memory 引擎替代) |
| [Hive](hive.sql) | TEMPORARY TABLE(会话级) |
| [Spark SQL](spark.sql) | TEMPORARY VIEW/全局临时视图 |
| [Flink SQL](flink.sql) | TEMPORARY TABLE/VIEW |
| [StarRocks](starrocks.sql) | 无临时表(用内存表替代) |
| [Doris](doris.sql) | 无显式临时表支持 |
| [Trino](trino.sql) | 无临时表(用 CTE/内存 Connector) |
| [DuckDB](duckdb.sql) | TEMP TABLE(内存) |
| [MaxCompute](maxcompute.sql) | 临时表(LIFECYCLE 1 天) |
| [Hologres](hologres.sql) | TEMP TABLE(PG 兼容) |

### 云数仓
| 方言 | 简评 |
|---|---|
| [Redshift](redshift.sql) | TEMP TABLE(会话级)，PG 兼容 |
| [Azure Synapse](synapse.sql) | #临时表(T-SQL 兼容) |
| [Databricks SQL](databricks.sql) | TEMPORARY VIEW 为主 |
| [Greenplum](greenplum.sql) | PG 兼容临时表 |
| [Impala](impala.sql) | 无临时表支持 |
| [Vertica](vertica.sql) | LOCAL/GLOBAL TEMPORARY TABLE |
| [Teradata](teradata.sql) | VOLATILE/GLOBAL TEMPORARY TABLE |

### 分布式 / NewSQL
| 方言 | 简评 |
|---|---|
| [TiDB](tidb.sql) | MySQL 兼容 TEMPORARY TABLE(10+) |
| [OceanBase](oceanbase.sql) | MySQL/Oracle 双模式临时表 |
| [CockroachDB](cockroachdb.sql) | PG 兼容临时表(实验性) |
| [Spanner](spanner.sql) | 无临时表支持 |
| [YugabyteDB](yugabytedb.sql) | PG 兼容临时表 |
| [PolarDB](polardb.sql) | MySQL 兼容临时表 |
| [openGauss](opengauss.sql) | PG 兼容临时表 |
| [TDSQL](tdsql.sql) | MySQL 兼容临时表 |

### 国产数据库
| 方言 | 简评 |
|---|---|
| [DamengDB](dameng.sql) | GTT(Oracle 兼容) |
| [KingbaseES](kingbase.sql) | PG 兼容 |

### 时序数据库
| 方言 | 简评 |
|---|---|
| [TimescaleDB](timescaledb.sql) | 继承 PG 临时表 |
| [TDengine](tdengine.sql) | 无临时表支持 |

### 流处理
| 方言 | 简评 |
|---|---|
| [ksqlDB](ksqldb.sql) | 无临时表(流式处理) |
| [Materialize](materialize.sql) | TEMPORARY VIEW 支持 |

### 嵌入式 / 轻量
| 方言 | 简评 |
|---|---|
| [H2](h2.sql) | TEMPORARY TABLE 支持 |
| [Derby](derby.sql) | DECLARE GLOBAL TEMPORARY TABLE |

### SQL 标准
| 方言 | 简评 |
|---|---|
| [SQL Standard](sql-standard.sql) | SQL:2003 TEMPORARY TABLE 规范 |

## 核心差异

1. **生命周期**：MySQL 的临时表会话结束自动删除，PostgreSQL 支持 ON COMMIT DROP/DELETE ROWS/PRESERVE ROWS，Oracle 的全局临时表结构持久但数据按事务/会话
2. **命名约定**：SQL Server 用 `#table`（局部）和 `##table`（全局），其他方言用 `CREATE TEMPORARY TABLE`
3. **可见性**：MySQL/PostgreSQL 的临时表只对当前会话可见，Oracle 的全局临时表定义对所有会话可见但数据隔离
4. **CTE 替代**：简单场景可用 CTE（WITH 子句）替代临时表，但 CTE 的生命周期限于单条查询，临时表可跨多条语句

## 选型建议

临时表适合复杂 ETL 管道中的中间结果存储、存储过程中的多步骤处理。简单场景优先用 CTE。大数据引擎中临时表通常存储在计算节点本地磁盘，注意数据量不要超出节点容量。

## 版本演进

- PostgreSQL 15+：改进临时表的性能和系统目录清理
- MySQL 8.0：临时表使用 TempTable 存储引擎替代 MEMORY 引擎，性能和大数据量支持改进
- BigQuery：支持临时表但有 24 小时过期限制

## 横向对比

| 特性维度 | SQLite | ClickHouse | BigQuery | 传统 RDBMS (MySQL/PG/Oracle) |
|---|---|---|---|---|
| **临时表语法** | CREATE TEMP TABLE（存储在临时文件中） | CREATE TEMPORARY TABLE（会话级） | 支持临时表（24 小时过期限制） | MySQL/PG CREATE TEMPORARY TABLE / SQL Server #table |
| **生命周期** | 连接关闭时自动删除 | 会话结束时自动删除 | 24 小时自动过期 | MySQL/PG 会话结束删除 / Oracle GTT 结构持久数据隔离 |
| **可见性** | 仅当前连接可见 | 仅当前会话可见 | 仅当前会话可见 | 各方言均为会话隔离 |
| **存储位置** | 临时数据库文件（或内存） | 本地磁盘 | Serverless 托管存储 | 各方言有专用临时表空间 |
| **CTE 替代** | CTE（3.8.3+）可替代简单临时表场景 | CTE 可替代简单场景 | CTE 可替代简单场景 | CTE 是单查询范围内的替代 |

## 引擎开发者视角

**核心设计决策**：临时表的存储位置和生命周期管理直接影响引擎的资源利用效率。需要决定：临时表存在系统目录中还是仅存于内存？会话级还是事务级？是否支持全局临时表？

**实现建议**：
- 推荐优先实现会话级临时表（CREATE TEMPORARY TABLE），会话断开自动清理。PostgreSQL 的 ON COMMIT DROP/DELETE ROWS/PRESERVE ROWS 三种策略覆盖所有场景，值得借鉴
- 临时表不应写入 WAL/重做日志——这是临时表比普通表更快的关键原因。PostgreSQL 的临时表跳过 WAL 是正确设计
- 系统目录膨胀是临时表的经典问题：频繁创建/销毁临时表会导致 pg_class 等系统表膨胀。解决方案：将临时表元数据存在独立的会话级内存结构中而非全局系统目录
- SQL Server 的 #table 命名约定（前缀标识临时性）实现简单但不够优雅，推荐使用显式的 TEMPORARY 关键字
- 对于分析型引擎，临时表可以用 CTE 或内存中的中间结果替代——不一定需要在存储层实现完整的临时表
- 常见错误：临时表与同名永久表的名称解析优先级未明确定义。应该是临时表始终优先（PostgreSQL/MySQL 的行为），并在用户创建同名临时表时给出警告
