# 索引 (INDEX)

各数据库索引类型与创建语法对比，包括 B-Tree、Hash、全文、空间索引等。

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
