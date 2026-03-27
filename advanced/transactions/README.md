# 事务 (TRANSACTIONS)

各数据库事务语法对比，包括隔离级别、SAVEPOINT、嵌套事务等。

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
