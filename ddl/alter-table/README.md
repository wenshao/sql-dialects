# 改表 (ALTER TABLE)

各数据库 ALTER TABLE 语法对比，包括加列、改列、删列、重命名等操作。

> [对比总览表](_comparison.md) -- 横向对比各方言特性支持

## 方言列表

### 传统关系型数据库
| 方言 | 简评 |
|---|---|
| [MySQL](mysql.sql) | Online DDL (INSTANT/INPLACE/COPY)，pt-osc/gh-ost 生态 |
| [PostgreSQL](postgres.sql) | 11+ ADD COLUMN WITH DEFAULT 即时，DDL 可回滚 |
| [SQLite](sqlite.sql) | 3.35 前无 DROP COLUMN，能力最弱 |
| [Oracle](oracle.sql) | ONLINE DDL，Edition-Based Redefinition |
| [SQL Server](sqlserver.sql) | ONLINE=ON(Enterprise)，sp_rename |
| [MariaDB](mariadb.sql) | INSTANT ADD COLUMN(10.3+)，与 MySQL 兼容 |
| [Firebird](firebird.sql) | 支持 ALTER TABLE，无 Online DDL |
| [IBM Db2](db2.sql) | REORG 表重组，ADMIN_MOVE_TABLE |
| [SAP HANA](saphana.sql) | 支持 Online ALTER，列存/行存差异 |

### 大数据 / 分析型引擎
| 方言 | 简评 |
|---|---|
| [BigQuery](bigquery.sql) | 在线执行，无锁表 |
| [Snowflake](snowflake.sql) | 元数据操作为主，秒级完成 |
| [ClickHouse](clickhouse.sql) | 异步 mutation，不阻塞查询 |
| [Hive](hive.sql) | REPLACE COLUMNS，有限 ALTER |
| [Spark SQL](spark.sql) | ALTER TABLE 修改分区/列，Delta Lake 支持更多 |
| [Flink SQL](flink.sql) | 仅支持 ADD/DROP 水印和列 |
| [StarRocks](starrocks.sql) | 支持 Online Schema Change |
| [Doris](doris.sql) | Light Schema Change(1.2+)，秒级加列 |
| [Trino](trino.sql) | 依赖底层 Connector 实现 |
| [DuckDB](duckdb.sql) | 支持 ADD/DROP/RENAME COLUMN |
| [MaxCompute](maxcompute.sql) | 仅支持 ADD COLUMN，不支持 DROP |
| [Hologres](hologres.sql) | 支持 ADD/DROP COLUMN，实时生效 |

### 云数仓
| 方言 | 简评 |
|---|---|
| [Redshift](redshift.sql) | ALTER TABLE 部分操作需重建 |
| [Azure Synapse](synapse.sql) | 分布式表 ALTER 限制较多 |
| [Databricks SQL](databricks.sql) | Delta Lake ALTER TABLE 丰富 |
| [Greenplum](greenplum.sql) | 继承 PG 语法，分布键不可改 |
| [Impala](impala.sql) | 支持 ADD/DROP/CHANGE COLUMN |
| [Vertica](vertica.sql) | 支持 ALTER TABLE，投影需刷新 |
| [Teradata](teradata.sql) | 支持在线 ALTER，多 AMP 协同 |

### 分布式 / NewSQL
| 方言 | 简评 |
|---|---|
| [TiDB](tidb.sql) | MySQL 兼容，Online DDL |
| [OceanBase](oceanbase.sql) | MySQL/Oracle 双模式 DDL |
| [CockroachDB](cockroachdb.sql) | 在线 Schema Change，无锁 |
| [Spanner](spanner.sql) | 在线 Schema 变更，全球一致 |
| [YugabyteDB](yugabytedb.sql) | PG 兼容，在线 DDL |
| [PolarDB](polardb.sql) | MySQL 兼容，秒级 DDL |
| [openGauss](opengauss.sql) | PG 兼容，支持在线 ALTER |
| [TDSQL](tdsql.sql) | MySQL 兼容，分布式 DDL |

### 国产数据库
| 方言 | 简评 |
|---|---|
| [DamengDB](dameng.sql) | Oracle 兼容语法 |
| [KingbaseES](kingbase.sql) | PG 兼容 |

### 时序数据库
| 方言 | 简评 |
|---|---|
| [TimescaleDB](timescaledb.sql) | 继承 PG ALTER，超表自动同步 |
| [TDengine](tdengine.sql) | 仅支持 ADD/DROP COLUMN |

### 流处理
| 方言 | 简评 |
|---|---|
| [ksqlDB](ksqldb.sql) | ALTER 仅改流/表属性 |
| [Materialize](materialize.sql) | PG 兼容，支持 ALTER |

### 嵌入式 / 轻量
| 方言 | 简评 |
|---|---|
| [H2](h2.sql) | 标准 ALTER TABLE 支持 |
| [Derby](derby.sql) | 有限 ALTER，不支持 DROP COLUMN |

### SQL 标准
| 方言 | 简评 |
|---|---|
| [SQL Standard](sql-standard.sql) | SQL:2003 ALTER TABLE 规范 |

## 核心差异

1. **ADD COLUMN**：所有方言都支持，但 PostgreSQL 11+ 对带 DEFAULT 的 ADD COLUMN 是即时操作，MySQL 5.6 之前可能锁全表
2. **MODIFY/ALTER COLUMN**：MySQL 用 `MODIFY COLUMN`，PostgreSQL 用 `ALTER COLUMN ... TYPE`，SQL Server 用 `ALTER COLUMN`，语法完全不同
3. **DROP COLUMN**：SQLite 3.35.0 之前不支持，ClickHouse 支持但是异步操作，BigQuery 用 `DROP COLUMN` 但有限制
4. **RENAME COLUMN**：MySQL 8.0+/PostgreSQL/Oracle 支持 `RENAME COLUMN`，MySQL 5.7 需要用 `CHANGE COLUMN`（必须重写完整列定义）
5. **在线 DDL**：MySQL 8.0 的 `ALGORITHM=INSTANT` 可即时完成部分 ALTER 操作，PostgreSQL 大多数 ADD COLUMN 天然即时

## 选型建议

生产环境做 ALTER TABLE 前务必在测试环境验证是否会锁表。MySQL 大表改列推荐使用 pt-online-schema-change 或 gh-ost 工具。PostgreSQL 的大多数 ALTER 操作更友好，但 ALTER COLUMN TYPE 仍可能需要重写表。

## 版本演进

- MySQL 8.0.12+：ALGORITHM=INSTANT 支持更多即时 ALTER 操作
- PostgreSQL 11+：ADD COLUMN WITH DEFAULT 不再需要重写全表
- SQLite 3.35.0：首次支持 DROP COLUMN
- SQLite 3.25.0：首次支持 RENAME COLUMN

## 横向对比

| 特性维度 | SQLite | ClickHouse | BigQuery | 传统 RDBMS (MySQL/PG/Oracle) |
|---|---|---|---|---|
| **DROP COLUMN** | 3.35.0 之前完全不支持，只能重建表；3.35.0+ 才可用 | 支持但为异步操作（mutation），不立即释放空间 | 支持 DROP COLUMN，Serverless 后台处理 | 完整支持，部分方言可能短暂锁表 |
| **MODIFY COLUMN** | 不支持修改列类型或默认值，必须重建表 | 支持 MODIFY COLUMN 改类型，但为异步 mutation | 支持修改列类型（有限制），不停服 | 各方言语法不同但均支持（可能需重写表） |
| **RENAME COLUMN** | 3.25.0+ 才支持 | 支持 RENAME COLUMN | 支持 RENAME COLUMN | MySQL 8.0+/PG/Oracle 支持原生语法 |
| **在线 DDL** | 无此概念，文件级操作天然轻量 | ALTER 操作多为异步 mutation，不阻塞查询 | 完全在线，Serverless 架构无锁表概念 | MySQL ALGORITHM=INSTANT/PG 即时 ADD COLUMN |
| **ADD COLUMN** | 支持但只能追加到末尾，不能指定位置 | 支持，可用 AFTER 指定位置 | 支持 | 均支持，MySQL 可用 AFTER/FIRST 指定位置 |
| **权限需求** | 无权限系统，文件访问权即操作权 | 需要 ALTER TABLE 权限 | 需要 IAM bigquery.tables.update 权限 | 需要 ALTER 权限（GRANT/REVOKE 控制） |

## 引擎开发者视角

**核心设计决策**：ALTER TABLE 的在线能力直接影响生产环境的可用性。需要决定：哪些 ALTER 操作可以即时完成（metadata-only），哪些需要重写表数据，以及是否支持并发 DML。

**实现建议**：
- ADD COLUMN（无默认值或默认值为常量）应设计为即时操作（只修改元数据）——PostgreSQL 11+ 和 MySQL 8.0 的 ALGORITHM=INSTANT 都证明这是可行的。对行格式中未出现的列返回默认值即可
- DROP COLUMN 的物理删除可以延迟到后台 compaction 阶段执行，前台操作只标记列为已删除。ClickHouse 的异步 mutation 模式值得参考
- MODIFY COLUMN TYPE 是最复杂的操作：如果新旧类型存储兼容（如 INT -> BIGINT），可以只修改元数据；否则需要全表重写。重写时必须支持并发读写（shadow copy 或 online DDL 方式）
- RENAME TABLE/COLUMN 应始终是即时操作——只修改元数据字典
- 分布式引擎的 ALTER TABLE 需要跨节点协调元数据变更：推荐使用 schema version + 两阶段方案，确保所有节点在查询时使用一致的 schema 版本
- 常见错误：ALTER TABLE 获取排他锁的时间过长导致查询阻塞。MySQL 的 MDL（Metadata Lock）等待是经典问题——应支持 LOCK TIMEOUT 或 NOWAIT 选项
