# 锁机制 (LOCKING)

各数据库锁机制语法对比，包括行锁、表锁、FOR UPDATE、Advisory Lock 等。

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

1. **FOR UPDATE**：PostgreSQL/Oracle/MySQL 支持 `SELECT ... FOR UPDATE`，SQL Server 用 `WITH (UPDLOCK, ROWLOCK)` 锁提示
2. **SKIP LOCKED/NOWAIT**：PostgreSQL 9.5+/Oracle/MySQL 8.0+ 支持 SKIP LOCKED（跳过已锁定行）和 NOWAIT（立即失败不等待），非常适合任务队列场景
3. **锁粒度**：MySQL InnoDB 有行锁和间隙锁（Gap Lock），PostgreSQL 有行锁和咨询锁（Advisory Lock），Oracle 没有锁升级问题，SQL Server 有锁升级（行→页→表）
4. **死锁检测**：所有 RDBMS 都有死锁检测器会自动回滚一个事务，但检测速度和策略不同
5. **分析型引擎**：大多数分析型引擎没有行级锁概念，BigQuery 靠快照隔离，ClickHouse 靠 mutation 队列

## 选型建议

尽量避免显式锁（FOR UPDATE），优先用乐观锁（版本号/CAS）或数据库的 MVCC 机制。需要显式锁时始终以固定顺序获取锁以避免死锁。SKIP LOCKED 是实现数据库任务队列的最佳方案。Advisory Lock（PostgreSQL）适合分布式锁的轻量级实现。

## 版本演进

- MySQL 8.0+：支持 SKIP LOCKED 和 NOWAIT（之前只能等待锁超时）
- PostgreSQL 9.5+：引入 SKIP LOCKED，使得用 SELECT FOR UPDATE 实现任务队列成为实际可用方案
- MySQL 8.0：改进死锁检测和诊断信息（SHOW ENGINE INNODB STATUS 的死锁日志更详细）

## 横向对比

| 特性维度 | SQLite | ClickHouse | BigQuery | 传统 RDBMS (MySQL/PG/Oracle) |
|---|---|---|---|---|
| **锁粒度** | 文件级锁：SHARED（读）/ RESERVED / EXCLUSIVE（写） | 无行级锁概念，数据写入通过 mutation 队列串行化 | 无锁概念，Serverless 平台管理并发 | 行级锁（InnoDB/PG/Oracle），SQL Server 有锁升级 |
| **FOR UPDATE** | 不支持行级 SELECT FOR UPDATE | 不支持 | 不支持 | PG/MySQL/Oracle 支持 |
| **SKIP LOCKED** | 不支持 | 不支持 | 不支持 | PG 9.5+ / MySQL 8.0+ / Oracle 支持 |
| **死锁** | 单写模型无传统死锁，但可能出现 SQLITE_BUSY | 无死锁问题（无行级锁） | 无死锁问题 | 所有 RDBMS 都有死锁检测和自动回滚 |
| **并发模型** | WAL 模式：允许并发读+单写；非 WAL 模式：读写互斥 | 多节点并发 INSERT，后台合并，最终一致 | Serverless 无限并发读，DML 有配额限制 | MVCC 高并发读写 |
| **Advisory Lock** | 不支持 | 不支持 | 不支持 | PG 支持 Advisory Lock（轻量级应用锁） |

## 引擎开发者视角

**核心设计决策**：锁机制的设计直接决定引擎的并发能力和吞吐量上限。核心抉择：悲观锁（先锁后操作）vs 乐观锁（先操作后检测冲突），以及锁粒度（行级 vs 页级 vs 表级）。

**实现建议**：
- OLTP 引擎必须实现行级锁 + MVCC，这是并发性能的基础。仅靠表级锁的引擎在并发写入场景中完全不可用
- FOR UPDATE / FOR SHARE 是 SQL 生态的基本期望，新引擎必须支持。SKIP LOCKED 和 NOWAIT 实现成本低但价值大（支撑任务队列等关键场景），推荐优先实现
- 死锁检测器是必须的：推荐使用等待图（wait-for graph）周期检测算法，设置合理的检测间隔（InnoDB 默认每秒检测一次）。被选中回滚的事务应该是代价最小的
- 分布式引擎的锁管理极其复杂：推荐使用时间戳排序（如 Spanner 的 TrueTime）或乐观并发控制（如 CockroachDB 的 SSI），而非跨节点的分布式锁
- Advisory Lock 是低成本高价值的特性，PostgreSQL 的实现可作为参考——会话级和事务级两种生命周期都应支持
- 常见错误：锁升级（row -> page -> table）策略不当导致性能悬崖。SQL Server 的锁升级问题是反面教材。另一个陷阱是间隙锁（Gap Lock）的范围过大导致意外的写入阻塞
