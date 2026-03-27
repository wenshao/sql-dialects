# 插入 (INSERT)

各数据库 INSERT 语法对比，包括单行插入、批量插入、INSERT INTO SELECT 等。

> [对比总览表](_comparison.md) -- 横向对比各方言特性支持

## 方言列表

### 传统关系型数据库
| 方言 | 简评 |
|---|---|
| [MySQL](mysql.sql) | 多行 VALUES，LOAD DATA INFILE 批量导入 |
| [PostgreSQL](postgres.sql) | INSERT RETURNING，COPY 高速批量导入 |
| [SQLite](sqlite.sql) | 多行 VALUES，事务内批量性能佳 |
| [Oracle](oracle.sql) | INSERT ALL 多表，12c+ 多行 VALUES |
| [SQL Server](sqlserver.sql) | INSERT OUTPUT，BULK INSERT 批量 |
| [MariaDB](mariadb.sql) | 兼容 MySQL，RETURNING(10.5+) |
| [Firebird](firebird.sql) | INSERT RETURNING，标准 SQL 风格 |
| [IBM Db2](db2.sql) | INSERT + SELECT FROM FINAL TABLE |
| [SAP HANA](saphana.sql) | 批量 INSERT，IMPORT FROM 快速导入 |

### 大数据 / 分析型引擎
| 方言 | 简评 |
|---|---|
| [BigQuery](bigquery.sql) | Streaming INSERT + Load Job 双模式 |
| [Snowflake](snowflake.sql) | COPY INTO 高速加载，VARIANT 半结构化 |
| [ClickHouse](clickhouse.sql) | 大批量写入优化，INSERT SELECT 高效 |
| [Hive](hive.sql) | INSERT OVERWRITE 覆盖，LOAD DATA 加载 |
| [Spark SQL](spark.sql) | INSERT INTO/OVERWRITE，DataFrame API 更常用 |
| [Flink SQL](flink.sql) | INSERT INTO 流式写入，CDC 支持 |
| [StarRocks](starrocks.sql) | Stream Load/Broker Load/INSERT 多通道 |
| [Doris](doris.sql) | Stream Load/Broker Load 批量导入 |
| [Trino](trino.sql) | INSERT INTO SELECT 为主 |
| [DuckDB](duckdb.sql) | COPY/INSERT 高效，直接从文件插入 |
| [MaxCompute](maxcompute.sql) | Tunnel 批量上传，INSERT OVERWRITE |
| [Hologres](hologres.sql) | 实时写入 + 批量 COPY 导入 |

### 云数仓
| 方言 | 简评 |
|---|---|
| [Redshift](redshift.sql) | COPY 从 S3 加载，推荐批量 |
| [Azure Synapse](synapse.sql) | COPY INTO 从 Blob 加载 |
| [Databricks SQL](databricks.sql) | INSERT INTO/OVERWRITE，Auto Loader |
| [Greenplum](greenplum.sql) | gpload/COPY 批量导入 |
| [Impala](impala.sql) | INSERT INTO/OVERWRITE SELECT |
| [Vertica](vertica.sql) | COPY 批量加载，Flex Table 半结构化 |
| [Teradata](teradata.sql) | FastLoad/MultiLoad/TPump 工具体系 |

### 分布式 / NewSQL
| 方言 | 简评 |
|---|---|
| [TiDB](tidb.sql) | MySQL 兼容，Lightning 批量导入 |
| [OceanBase](oceanbase.sql) | MySQL/Oracle 双模式 INSERT |
| [CockroachDB](cockroachdb.sql) | PG 兼容 INSERT，IMPORT 批量 |
| [Spanner](spanner.sql) | Mutation API 更高效，INSERT DML |
| [YugabyteDB](yugabytedb.sql) | PG 兼容 INSERT |
| [PolarDB](polardb.sql) | MySQL 兼容，并行 INSERT |
| [openGauss](opengauss.sql) | PG 兼容，COPY 批量导入 |
| [TDSQL](tdsql.sql) | MySQL 兼容，分布式批量导入 |

### 国产数据库
| 方言 | 简评 |
|---|---|
| [DamengDB](dameng.sql) | Oracle 兼容 INSERT ALL |
| [KingbaseES](kingbase.sql) | PG 兼容 |

### 时序数据库
| 方言 | 简评 |
|---|---|
| [TimescaleDB](timescaledb.sql) | 继承 PG INSERT/COPY，时序优化批量 |
| [TDengine](tdengine.sql) | INSERT 多子表写入，Schemaless 协议 |

### 流处理
| 方言 | 简评 |
|---|---|
| [ksqlDB](ksqldb.sql) | INSERT INTO 向流写入 |
| [Materialize](materialize.sql) | 不支持直接 INSERT(源驱动) |

### 嵌入式 / 轻量
| 方言 | 简评 |
|---|---|
| [H2](h2.sql) | 标准 INSERT + CSVREAD 导入 |
| [Derby](derby.sql) | 标准 INSERT 支持 |

### SQL 标准
| 方言 | 简评 |
|---|---|
| [SQL Standard](sql-standard.sql) | SQL:2003 INSERT 规范 |

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
