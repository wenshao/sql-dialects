# 锁机制 (LOCKING)

各数据库锁机制语法对比，包括行锁、表锁、FOR UPDATE、Advisory Lock 等。

## 方言列表

### 传统关系型数据库
| 方言 | 简评 |
|---|---|
| [MySQL](mysql.sql) | InnoDB 行锁/间隙锁/Next-Key，FOR UPDATE |
| [PostgreSQL](postgres.sql) | MVCC + 行锁，FOR UPDATE/SHARE/NO KEY |
| [SQLite](sqlite.sql) | 文件级锁(SHARED/RESERVED/EXCLUSIVE)，WAL 模式 |
| [Oracle](oracle.sql) | 行锁无锁升级，FOR UPDATE WAIT/NOWAIT |
| [SQL Server](sqlserver.sql) | 行/页/表锁升级，NOLOCK/UPDLOCK 提示 |
| [MariaDB](mariadb.sql) | 兼容 MySQL InnoDB 锁，SKIP LOCKED(10.6+) |
| [Firebird](firebird.sql) | MVCC + 行锁，WITH LOCK |
| [IBM Db2](db2.sql) | 行/页/表锁，LOCK TABLE 显式 |
| [SAP HANA](saphana.sql) | MVCC 为主，行锁/表锁 |

### 大数据 / 分析型引擎
| 方言 | 简评 |
|---|---|
| [BigQuery](bigquery.sql) | 无显式锁，Snapshot 隔离 |
| [Snowflake](snowflake.sql) | 无显式锁，自动并发控制 |
| [ClickHouse](clickhouse.sql) | 无行锁，Part 级互斥(mutation) |
| [Hive](hive.sql) | 表/分区锁(ZooKeeper)，ACID(3.0+) |
| [Spark SQL](spark.sql) | Delta Lake 乐观并发控制 |
| [Flink SQL](flink.sql) | 无锁概念(流式处理) |
| [StarRocks](starrocks.sql) | 表级锁(DDL)，无行锁 |
| [Doris](doris.sql) | 表级锁(DDL)，无行锁 |
| [Trino](trino.sql) | 无锁概念，只读查询为主 |
| [DuckDB](duckdb.sql) | MVCC + WAL，进程级并发 |
| [MaxCompute](maxcompute.sql) | 无锁概念(批处理) |
| [Hologres](hologres.sql) | MVCC + 行锁(PG 兼容) |

### 云数仓
| 方言 | 简评 |
|---|---|
| [Redshift](redshift.sql) | 表级锁，无行锁 |
| [Azure Synapse](synapse.sql) | 表级锁，并发有限 |
| [Databricks SQL](databricks.sql) | Delta Lake 乐观并发 |
| [Greenplum](greenplum.sql) | PG 兼容锁，分布式协调 |
| [Impala](impala.sql) | 无锁概念(只读分析) |
| [Vertica](vertica.sql) | MVCC + 投影锁，无行锁 |
| [Teradata](teradata.sql) | 行级锁/ROWHASH 锁，ACCESS 锁模式 |

### 分布式 / NewSQL
| 方言 | 简评 |
|---|---|
| [TiDB](tidb.sql) | 乐观/悲观事务锁，FOR UPDATE |
| [OceanBase](oceanbase.sql) | 行锁/意向锁，MySQL 兼容 |
| [CockroachDB](cockroachdb.sql) | PG 兼容 FOR UPDATE，分布式锁 |
| [Spanner](spanner.sql) | 读写锁/共享锁，Paxos 复制 |
| [YugabyteDB](yugabytedb.sql) | PG 兼容行锁 |
| [PolarDB](polardb.sql) | MySQL 兼容 InnoDB 锁 |
| [openGauss](opengauss.sql) | PG 兼容锁机制 |
| [TDSQL](tdsql.sql) | MySQL 兼容，分布式锁协调 |

### 国产数据库
| 方言 | 简评 |
|---|---|
| [DamengDB](dameng.sql) | Oracle 兼容锁机制 |
| [KingbaseES](kingbase.sql) | PG 兼容 |

### 时序数据库
| 方言 | 简评 |
|---|---|
| [TimescaleDB](timescaledb.sql) | 继承 PG 锁机制 |
| [TDengine](tdengine.sql) | 无行锁(追加写入) |

### 流处理
| 方言 | 简评 |
|---|---|
| [ksqlDB](ksqldb.sql) | 无锁概念(Kafka 分区) |
| [Materialize](materialize.sql) | 无锁(流式增量计算) |

### 嵌入式 / 轻量
| 方言 | 简评 |
|---|---|
| [H2](h2.sql) | 表级/行级锁(MVCC 模式) |
| [Derby](derby.sql) | 行级锁，锁升级到表 |

### SQL 标准
| 方言 | 简评 |
|---|---|
| [SQL Standard](sql-standard.sql) | SQL:2003 隔离级别隐含锁语义 |

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
