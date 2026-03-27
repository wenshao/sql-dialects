# 事务 (TRANSACTIONS)

各数据库事务语法对比，包括隔离级别、SAVEPOINT、嵌套事务等。

> [对比总览表](_comparison.md) -- 横向对比各方言特性支持

## 方言列表

### 传统关系型数据库
| 方言 | 简评 |
|---|---|
| [MySQL](mysql.sql) | InnoDB ACID，RC/RR/SERIALIZABLE，自动提交 |
| [PostgreSQL](postgres.sql) | 完整 ACID，SSI 真正可串行化 |
| [SQLite](sqlite.sql) | 文件级事务，WAL 模式并发读写 |
| [Oracle](oracle.sql) | MVCC 无脏读，默认 READ COMMITTED |
| [SQL Server](sqlserver.sql) | READ UNCOMMITTED~SNAPSHOT 五级隔离 |
| [MariaDB](mariadb.sql) | 兼容 MySQL 事务，InnoDB/Aria 引擎 |
| [Firebird](firebird.sql) | MVCC 事务，WAIT/NO WAIT 冲突处理 |
| [IBM Db2](db2.sql) | CS/RS/RR/UR 四级隔离 |
| [SAP HANA](saphana.sql) | MVCC + 快照隔离，SSI 支持 |

### 大数据 / 分析型引擎
| 方言 | 简评 |
|---|---|
| [BigQuery](bigquery.sql) | 快照隔离，DML 有配额限制 |
| [Snowflake](snowflake.sql) | 自动 SI 隔离，多语句事务(2021+) |
| [ClickHouse](clickhouse.sql) | 无传统事务(INSERT 批次原子性) |
| [Hive](hive.sql) | ACID(3.0+)，仅 ORC 事务表 |
| [Spark SQL](spark.sql) | Delta Lake ACID 事务 |
| [Flink SQL](flink.sql) | Exactly-Once(两阶段提交 Sink) |
| [StarRocks](starrocks.sql) | 无传统事务(导入原子性) |
| [Doris](doris.sql) | 导入事务(两阶段提交) |
| [Trino](trino.sql) | 无事务，只读查询为主 |
| [DuckDB](duckdb.sql) | 完整 ACID，MVCC，WAL |
| [MaxCompute](maxcompute.sql) | 无事务(批处理语义) |
| [Hologres](hologres.sql) | PG 兼容事务 |

### 云数仓
| 方言 | 简评 |
|---|---|
| [Redshift](redshift.sql) | SERIALIZABLE(默认)，MVCC |
| [Azure Synapse](synapse.sql) | 有限事务支持 |
| [Databricks SQL](databricks.sql) | Delta Lake ACID 事务 |
| [Greenplum](greenplum.sql) | PG 兼容 MVCC 事务 |
| [Impala](impala.sql) | 无事务(Kudu 表除外) |
| [Vertica](vertica.sql) | SERIALIZABLE/RC，MVCC |
| [Teradata](teradata.sql) | ANSI/BTET 事务模式，完整 ACID |

### 分布式 / NewSQL
| 方言 | 简评 |
|---|---|
| [TiDB](tidb.sql) | 乐观/悲观事务，分布式 ACID |
| [OceanBase](oceanbase.sql) | 分布式 ACID，2PC 提交 |
| [CockroachDB](cockroachdb.sql) | 分布式 SERIALIZABLE，无降级 |
| [Spanner](spanner.sql) | TrueTime 全球一致，外部一致性 |
| [YugabyteDB](yugabytedb.sql) | 分布式事务，SERIALIZABLE/SNAPSHOT |
| [PolarDB](polardb.sql) | MySQL 兼容事务 |
| [openGauss](opengauss.sql) | PG 兼容 MVCC 事务 |
| [TDSQL](tdsql.sql) | 分布式事务，2PC/XA |

### 国产数据库
| 方言 | 简评 |
|---|---|
| [DamengDB](dameng.sql) | Oracle 兼容事务 |
| [KingbaseES](kingbase.sql) | PG 兼容 |

### 时序数据库
| 方言 | 简评 |
|---|---|
| [TimescaleDB](timescaledb.sql) | 继承 PG 完整事务 |
| [TDengine](tdengine.sql) | 无传统事务(时序追加) |

### 流处理
| 方言 | 简评 |
|---|---|
| [ksqlDB](ksqldb.sql) | At-Least-Once 语义 |
| [Materialize](materialize.sql) | Strict Serializability 一致性 |

### 嵌入式 / 轻量
| 方言 | 简评 |
|---|---|
| [H2](h2.sql) | 完整 ACID 事务 |
| [Derby](derby.sql) | 完整 ACID 事务 |

### SQL 标准
| 方言 | 简评 |
|---|---|
| [SQL Standard](sql-standard.sql) | SQL:1992 隔离级别 / SQL:2003 SAVEPOINT |

## 核心差异

1. **默认隔离级别**：MySQL InnoDB 默认 REPEATABLE READ，PostgreSQL 默认 READ COMMITTED，Oracle 默认 READ COMMITTED 且只支持 RC 和 SERIALIZABLE，SQL Server 默认 READ COMMITTED
2. **MVCC 实现**：PostgreSQL 用多版本元组（需要 VACUUM 清理），MySQL InnoDB 用 undo log，Oracle 用 undo tablespace，实现差异影响并发性能和空间管理
3. **自动提交**：MySQL/PostgreSQL/SQL Server 默认 autocommit=ON（每条语句自动提交），Oracle 默认不自动提交（需要显式 COMMIT）
4. **SAVEPOINT**：所有主要 RDBMS 都支持 SAVEPOINT，但分析型引擎大多不支持
5. **分布式事务**：TiDB/CockroachDB/Spanner 支持分布式 ACID 事务，BigQuery/Snowflake/ClickHouse 只有有限的事务支持

## 选型建议

OLTP 系统必须理解所选数据库的隔离级别行为（尤其是幻读、不可重复读的实际表现）。大多数 Web 应用使用 READ COMMITTED 即可。高并发场景下 SERIALIZABLE 性能代价大，通常用乐观锁或应用层重试替代。

## 版本演进

- MySQL 8.0：事务 DDL 支持增强（部分 DDL 操作是原子的）
- PostgreSQL 12+：改进 SERIALIZABLE 隔离级别的性能
- ClickHouse：从无事务逐步演进到支持轻量级事务（实验性）
- Hive 0.14+/3.0+：引入 ACID 事务支持（基于 delta files 实现）

## 横向对比

| 特性维度 | SQLite | ClickHouse | BigQuery | 传统 RDBMS (MySQL/PG/Oracle) |
|---|---|---|---|---|
| **事务支持** | 支持完整 ACID 事务（单写模型下） | 无传统事务：轻量级事务为实验性功能 | 无跨语句事务，每条 DML 是独立原子操作（快照隔离） | 完整 ACID 事务 |
| **隔离级别** | 序列化隔离（单写天然保证）或 WAL 模式下读写并发 | 无隔离级别概念，数据最终一致 | 快照隔离（每条查询看到一致的快照） | RC/RR/SERIALIZABLE 等多级可选 |
| **SAVEPOINT** | 支持 SAVEPOINT（嵌套事务模拟） | 不支持 | 不支持 | 所有主流 RDBMS 支持 |
| **并发控制** | 文件级锁，单写多读（WAL 模式改善并发） | 无行级锁，INSERT 并发由存储引擎管理（MergeTree 合并） | 无锁概念，Serverless 管理并发，DML 有配额限制 | MVCC + 行级锁 |
| **一致性模型** | 即时一致（写入立即可见） | 最终一致：MergeTree 后台合并后数据才"收敛" | 即时一致（每条 DML 原子完成） | 即时一致（事务提交后可见） |
| **权限保护** | 无权限系统防止误操作 | GRANT/REVOKE 控制操作权限 | IAM 策略控制访问 | GRANT/REVOKE 完整权限体系 |

## 引擎开发者视角

**核心设计决策**：事务是 ACID 引擎的核心，MVCC 的实现方式决定了引擎的并发性能天花板和存储管理复杂度。选择哪种隔离级别作为默认值也影响用户体验。

**实现建议**：
- MVCC 有两大流派：追加式（PostgreSQL——旧版本留在原地，需要 VACUUM 清理）和回滚段式（MySQL InnoDB/Oracle——旧版本存在 undo log 中）。追加式实现更简单但需要后台清理机制，回滚段式对长事务更友好但 undo 管理复杂
- 默认隔离级别推荐 READ COMMITTED——平衡了一致性和并发性能。REPEATABLE READ（MySQL InnoDB 默认）在很多场景下有不必要的性能开销，SERIALIZABLE 只有特殊需求才使用
- SAVEPOINT 的实现必须从第一天就支持——这是嵌套事务的基础，也是错误处理中部分回滚的关键机制
- 分布式事务的实现难度是数量级上的跃升：2PC（两阶段提交）有阻塞问题，Percolator 模型（TiDB）或 TrueTime（Spanner）各有适用场景。新的分布式引擎应认真评估是否需要跨节点 ACID
- 自动提交（autocommit）行为需要明确：推荐默认 ON（每条语句自动提交），与 MySQL/PostgreSQL 一致。Oracle 的默认不自动提交会让新用户困惑
- 常见错误：长事务导致 MVCC 版本堆积。引擎应有长事务检测和告警机制（如超过 N 分钟的事务自动告警或终止）
