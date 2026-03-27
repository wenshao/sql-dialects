# 插入 (INSERT)

各数据库 INSERT 语法对比，包括单行插入、批量插入、INSERT INTO SELECT 等。

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

1. **多行 VALUES**：MySQL/PostgreSQL/SQLite 支持 `INSERT INTO t VALUES (1,'a'),(2,'b')`，Oracle 12c 之前必须用 `INSERT ALL` 或 `UNION ALL` 子查询
2. **INSERT ... RETURNING**：PostgreSQL/Oracle/MariaDB 10.5+ 支持返回插入后的数据（含自增 ID），MySQL 不支持需要用 LAST_INSERT_ID()
3. **INSERT OVERWRITE**：Hive/Spark/MaxCompute 支持 INSERT OVERWRITE（覆盖写入分区），传统 RDBMS 没有此语法
4. **批量插入性能**：MySQL 的多值 INSERT 和 LOAD DATA INFILE 性能差异可达 10-50 倍，PostgreSQL 的 COPY 命令是最快的批量导入方式
5. **默认值处理**：`INSERT INTO t DEFAULT VALUES` 在 PostgreSQL/SQL Server 中有效，MySQL 用 `INSERT INTO t () VALUES ()`

## 选型建议

少量数据插入用标准 INSERT VALUES。大批量数据导入应使用专用工具：MySQL 的 LOAD DATA INFILE、PostgreSQL 的 COPY、BigQuery 的 Load Job、Snowflake 的 COPY INTO。ORM 生成的逐行 INSERT 在大批量场景下性能极差。

## 版本演进

- Oracle 12c+：支持多行 VALUES 语法，告别 INSERT ALL 的繁琐写法
- MariaDB 10.5+：INSERT ... RETURNING 支持
- MySQL 8.0：VALUES 语句可以作为独立的行构造器使用

## 横向对比

| 特性维度 | SQLite | ClickHouse | BigQuery | 传统 RDBMS (MySQL/PG/Oracle) |
|---|---|---|---|---|
| **INSERT 哲学** | 标准 INSERT，单写模型，适合小批量 | INSERT 是核心操作（INSERT-only 哲学），批量写入性能极强 | 流式插入（Streaming INSERT）和批量 Load Job 两种模式 | 标准逐行/批量 INSERT |
| **批量写入** | 多值 VALUES 支持，事务内批量插入 | 推荐大批量插入（每批至少数千行），小批量频繁 INSERT 效率低 | Streaming INSERT 有行级配额限制，大批量推荐 Load Job（免费） | MySQL LOAD DATA / PG COPY / Oracle SQL*Loader |
| **并发写入** | 文件级锁，同一时刻只允许一个写入者 | 多节点并发写入，列式存储后台合并 | DML 配额限制（每表每天 1500 次 DML），需合理规划 | 行级锁支持高并发写入 |
| **INSERT RETURNING** | 不支持 | 不支持 | 不支持 | PG 支持，MySQL 不支持（用 LAST_INSERT_ID） |
| **INSERT OVERWRITE** | 不支持 | 不支持（用 DROP + INSERT 或 ALTER TABLE DELETE） | 支持 INSERT OVERWRITE（覆盖表/分区） | 不支持（Hive/Spark 支持） |
| **事务保证** | 每条 INSERT 在事务中原子执行 | 无传统事务，INSERT 批次要么全成功要么全失败 | DML 操作有快照隔离但无跨语句事务 | 完整 ACID 事务保证 |

## 引擎开发者视角

**核心设计决策**：INSERT 是数据写入的主要入口，其性能直接决定引擎的写入吞吐量。批量 INSERT 的效率和单行 INSERT 的延迟是两个不同的优化方向。

**实现建议**：
- 多行 VALUES 语法（INSERT INTO t VALUES (1,'a'),(2,'b'),...）是基本要求，批量写入性能可以比逐行 INSERT 快 10-100 倍（减少解析和事务开销）
- COPY/LOAD DATA（批量导入）应作为独立的高速通道实现——跳过 SQL 解析、使用二进制协议、直接写入存储层。PostgreSQL 的 COPY 和 MySQL 的 LOAD DATA INFILE 是成熟参考
- INSERT ... RETURNING 对 ORM 框架至关重要——插入后立即获取自增 ID 和默认值列，避免额外的 SELECT 查询。这个特性对用户体验影响巨大
- INSERT INTO ... SELECT 的执行必须避免源表和目标表是同一张表时的读写冲突。PostgreSQL 的做法是先物化 SELECT 结果再 INSERT
- 列式引擎应优化批量写入而非单行写入：ClickHouse 推荐每批至少数千行的设计哲学是正确的。可以提供客户端缓冲机制将小批量合并为大批量
- INSERT OVERWRITE（覆盖写入）对 ETL 场景很重要，Hive/Spark 的支持证明了其价值。RDBMS 中可以用 TRUNCATE + INSERT 或分区替换模拟
- 常见错误：INSERT 性能受索引维护拖累——每个索引在 INSERT 时都需要更新。应提供批量插入时延迟索引更新的选项
