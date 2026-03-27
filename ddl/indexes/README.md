# 索引 (INDEX)

各数据库索引类型与创建语法对比，包括 B-Tree、Hash、全文、空间索引等。

> [对比总览表](_comparison.md) -- 横向对比各方言特性支持

## 方言列表

### 传统关系型数据库
| 方言 | 简评 |
|---|---|
| [MySQL](mysql.sql) | B-Tree/Hash/全文/空间索引，InnoDB 聚簇索引 |
| [PostgreSQL](postgres.sql) | B-Tree/GiST/GIN/BRIN/SP-GiST，表达式索引 |
| [SQLite](sqlite.sql) | B-Tree 为主，部分索引(3.8+) |
| [Oracle](oracle.sql) | Bitmap/Function-Based/IOT/Global Partitioned |
| [SQL Server](sqlserver.sql) | 聚簇/非聚簇/列存储/Filtered 索引 |
| [MariaDB](mariadb.sql) | 兼容 MySQL 索引，Hash 索引(Memory) |
| [Firebird](firebird.sql) | ASC/DESC 索引，表达式索引 |
| [IBM Db2](db2.sql) | MDC Block Index，XML 索引 |
| [SAP HANA](saphana.sql) | 列存隐式索引，INVERTED/HASH/CPBTREE |

### 大数据 / 分析型引擎
| 方言 | 简评 |
|---|---|
| [BigQuery](bigquery.sql) | 无传统索引，搜索索引(SEARCH INDEX) |
| [Snowflake](snowflake.sql) | 无索引，自动微分区 + Clustering |
| [ClickHouse](clickhouse.sql) | PRIMARY KEY 稀疏索引，跳数索引(minmax/bloom) |
| [Hive](hive.sql) | 无索引(已弃用)，依赖分区+列式存储 |
| [Spark SQL](spark.sql) | 无索引，Z-ORDER(Delta Lake) |
| [Flink SQL](flink.sql) | 无索引概念 |
| [StarRocks](starrocks.sql) | Bitmap/Bloom Filter/前缀索引 |
| [Doris](doris.sql) | 前缀索引/Bloom Filter/Bitmap 索引 |
| [Trino](trino.sql) | 无索引，下推到数据源 |
| [DuckDB](duckdb.sql) | 自动索引(ART)，无需手动创建 |
| [MaxCompute](maxcompute.sql) | 无索引，依赖分区裁剪 |
| [Hologres](hologres.sql) | 聚簇索引/Bitmap/Segment Key |

### 云数仓
| 方言 | 简评 |
|---|---|
| [Redshift](redshift.sql) | 无传统索引，SORTKEY + Zone Map |
| [Azure Synapse](synapse.sql) | 聚簇列存储索引(CCI)为默认 |
| [Databricks SQL](databricks.sql) | 无索引，Z-ORDER/OPTIMIZE/Liquid Clustering |
| [Greenplum](greenplum.sql) | Bitmap 索引，继承 PG B-Tree |
| [Impala](impala.sql) | 无索引，依赖 Parquet Min/Max 过滤 |
| [Vertica](vertica.sql) | 自动投影(Projection)替代索引 |
| [Teradata](teradata.sql) | PI(Primary Index)，Secondary/Join Index |

### 分布式 / NewSQL
| 方言 | 简评 |
|---|---|
| [TiDB](tidb.sql) | MySQL 兼容索引，TiFlash 列式副本 |
| [OceanBase](oceanbase.sql) | 局部/全局索引，MySQL/Oracle 双模式 |
| [CockroachDB](cockroachdb.sql) | PG 兼容，分布式 Inverted 索引 |
| [Spanner](spanner.sql) | 交叉索引(INTERLEAVE)，全局二级索引 |
| [YugabyteDB](yugabytedb.sql) | PG 兼容，LSM-Tree 索引 |
| [PolarDB](polardb.sql) | MySQL 兼容索引 |
| [openGauss](opengauss.sql) | PG 兼容，支持 GIN/GiST |
| [TDSQL](tdsql.sql) | MySQL 兼容，全局二级索引 |

### 国产数据库
| 方言 | 简评 |
|---|---|
| [DamengDB](dameng.sql) | Oracle 兼容，Bitmap/函数索引 |
| [KingbaseES](kingbase.sql) | PG 兼容 |

### 时序数据库
| 方言 | 简评 |
|---|---|
| [TimescaleDB](timescaledb.sql) | 继承 PG 索引，自动在每个 chunk 创建 |
| [TDengine](tdengine.sql) | 时间列自动索引，TAG 索引 |

### 流处理
| 方言 | 简评 |
|---|---|
| [ksqlDB](ksqldb.sql) | 无索引，Kafka 分区即分布 |
| [Materialize](materialize.sql) | 自动索引(Arrangement)维护增量视图 |

### 嵌入式 / 轻量
| 方言 | 简评 |
|---|---|
| [H2](h2.sql) | 标准 B-Tree/Hash 索引 |
| [Derby](derby.sql) | 标准 B-Tree 索引 |

### SQL 标准
| 方言 | 简评 |
|---|---|
| [SQL Standard](sql-standard.sql) | SQL:2003 CREATE INDEX(非标准但通用) |

## 核心差异

1. **默认索引类型**：大多数 RDBMS 默认 B-Tree，PostgreSQL 还支持 GiST/GIN/BRIN/Hash，ClickHouse 用跳数索引（minmax/set/bloom_filter）
2. **部分索引**：PostgreSQL/SQLite 支持 `CREATE INDEX ... WHERE`，MySQL 不支持，需要用生成列 + 索引模拟
3. **函数索引/表达式索引**：PostgreSQL 原生支持，MySQL 8.0+ 通过虚拟生成列支持，Oracle 直接支持
4. **全文索引**：MySQL 用 `FULLTEXT INDEX`，PostgreSQL 用 GIN 索引 + tsvector，Oracle 用 Oracle Text，各方言实现完全不同
5. **分析型引擎的索引哲学**：BigQuery/Snowflake 没有用户创建的索引（靠自动优化），ClickHouse 靠排序键和跳数索引，理念与 OLTP 完全不同

## 选型建议

OLTP 场景下索引是性能优化的第一手段，但不要过度建索引（写入性能和存储开销）。OLAP 场景下索引的重要性大幅降低，列式存储和分区裁剪才是关键。复合索引的列顺序至关重要，应把选择性最高的列放在前面。

## 版本演进

- PostgreSQL 11+：CREATE INDEX CONCURRENTLY 支持覆盖索引（INCLUDE）
- MySQL 8.0：支持降序索引、不可见索引（INVISIBLE INDEX）、函数索引
- PostgreSQL 13+：B-Tree 索引去重（deduplication）减少索引体积

## 横向对比

| 特性维度 | SQLite | ClickHouse | BigQuery | 传统 RDBMS (MySQL/PG/Oracle) |
|---|---|---|---|---|
| **索引类型** | B-Tree 索引，支持部分索引（WHERE 条件） | 跳数索引（minmax/set/bloom_filter/ngrambf），非传统 B-Tree | 无用户创建的索引，靠分区 + 聚簇（Clustering）自动优化 | B-Tree/Hash/GiST/GIN/全文索引等丰富类型 |
| **索引哲学** | 传统 OLTP 索引思路，适合点查和范围查 | 列式存储 + 排序键天然加速扫描，跳数索引辅助过滤 | Serverless 自动管理，无需手动索引，CLUSTER BY 影响数据布局 | 索引是性能优化的第一手段 |
| **部分索引** | 支持 CREATE INDEX ... WHERE | 不支持传统部分索引 | 无索引概念 | PG 支持，MySQL 不支持 |
| **CREATE INDEX** | 标准 CREATE INDEX 语法 | 用 ALTER TABLE ADD INDEX 添加跳数索引 | 不支持 CREATE INDEX | 标准 CREATE INDEX 语法 |
| **全文索引** | 通过 FTS5 虚拟表实现（非传统索引） | tokenbf_v1/ngrambf_v1 实现简单全文查找 | 无原生全文索引 | MySQL FULLTEXT / PG GIN+tsvector / Oracle Text |
| **存储开销** | 索引存储在同一数据库文件中 | 跳数索引开销极小（只存聚合信息） | 无索引存储开销（按存储和查询计费） | 索引占用独立存储空间，影响写入性能 |

## 引擎开发者视角

**核心设计决策**：索引子系统是 OLTP 引擎的心脏。需要决定：支持哪些索引类型、如何与查询优化器集成、是否支持在线索引创建。

**实现建议**：
- B-Tree 索引是最高优先级——覆盖等值查找、范围扫描、排序三大场景。B+ Tree（叶子节点链表）是标准实现，支持高效的范围遍历
- CREATE INDEX CONCURRENTLY（不阻塞写入的索引创建）对生产环境至关重要。实现方式：先构建索引快照再增量追加期间的变更。PostgreSQL 的两阶段方式（build + validate）是参考
- 部分索引（CREATE INDEX ... WHERE condition）实现成本低但价值大——减少索引大小、提高查询效率。SQLite 和 PostgreSQL 都支持，MySQL 不支持是遗憾
- 覆盖索引（INCLUDE 子句）让索引包含额外列避免回表查询，PostgreSQL 11+ 的实现可做参考
- 列式引擎的索引哲学完全不同：ClickHouse 的跳数索引（minmax/bloom_filter）只存聚合信息、开销极小——这是列式引擎索引的正确方向，不要照搬 B-Tree
- 不可见索引（MySQL 8.0 INVISIBLE INDEX）是优秀的运维特性——让 DBA 可以安全地测试删除索引的影响而不实际删除
- 常见错误：索引选择性估算不准导致优化器做出错误决策。索引的基数统计（cardinality statistics）需要定期更新
