# 分区 (PARTITIONING)

各数据库分区语法对比，包括 RANGE、LIST、HASH 分区等。

> [对比总览表](_comparison.md) -- 横向对比各方言特性支持

## 方言列表

### 传统关系型数据库
| 方言 | 简评 |
|---|---|
| [MySQL](mysql.sql) | RANGE/LIST/HASH/KEY 分区，8.0 改进 |
| [PostgreSQL](postgres.sql) | 声明式分区(10+)，RANGE/LIST/HASH |
| [SQLite](sqlite.sql) | 无分区支持 |
| [Oracle](oracle.sql) | 最丰富分区(RANGE/LIST/HASH/INTERVAL/REFERENCE) |
| [SQL Server](sqlserver.sql) | 分区函数+分区方案，Enterprise 特性 |
| [MariaDB](mariadb.sql) | 兼容 MySQL 分区 |
| [Firebird](firebird.sql) | 无分区支持 |
| [IBM Db2](db2.sql) | RANGE/HASH 分区 + MDC 多维聚簇 |
| [SAP HANA](saphana.sql) | RANGE/HASH/ROUND_ROBIN 分区 |

### 大数据 / 分析型引擎
| 方言 | 简评 |
|---|---|
| [BigQuery](bigquery.sql) | INTEGER/TIMESTAMP 分区 + 聚簇 |
| [Snowflake](snowflake.sql) | 自动微分区(无需手动)，Clustering Key |
| [ClickHouse](clickhouse.sql) | PARTITION BY 必选，TTL 自动清理 |
| [Hive](hive.sql) | PARTITIONED BY 核心特性，静态/动态分区 |
| [Spark SQL](spark.sql) | PARTITIONED BY，动态分区写入 |
| [Flink SQL](flink.sql) | PARTITIONED BY，Hive 集成分区 |
| [StarRocks](starrocks.sql) | RANGE/LIST 分区 + 分桶 |
| [Doris](doris.sql) | RANGE/LIST 分区 + HASH 分桶 |
| [Trino](trino.sql) | 依赖底层 Connector 分区 |
| [DuckDB](duckdb.sql) | Hive 风格分区(COPY TO) |
| [MaxCompute](maxcompute.sql) | PARTITIONED BY 核心特性，两级分区 |
| [Hologres](hologres.sql) | LIST/RANGE 分区(PG 兼容) |

### 云数仓
| 方言 | 简评 |
|---|---|
| [Redshift](redshift.sql) | DISTKEY+SORTKEY(非传统分区) |
| [Azure Synapse](synapse.sql) | 分布式表(HASH/ROUND_ROBIN/REPLICATE) |
| [Databricks SQL](databricks.sql) | PARTITIONED BY，Delta Lake Z-ORDER |
| [Greenplum](greenplum.sql) | RANGE/LIST 分区 + 分布键 |
| [Impala](impala.sql) | PARTITIONED BY，Hive 兼容 |
| [Vertica](vertica.sql) | PARTITION BY RANGE，层级分区 |
| [Teradata](teradata.sql) | PPI(Primary Partition Index)，多级分区 |

### 分布式 / NewSQL
| 方言 | 简评 |
|---|---|
| [TiDB](tidb.sql) | RANGE/HASH/LIST 分区(MySQL 兼容) |
| [OceanBase](oceanbase.sql) | RANGE/HASH/LIST/KEY 分区 |
| [CockroachDB](cockroachdb.sql) | PARTITION BY(RANGE/LIST)，地理分区 |
| [Spanner](spanner.sql) | INTERLEAVE 层级 + SPLIT AT |
| [YugabyteDB](yugabytedb.sql) | RANGE/HASH 自动分片 |
| [PolarDB](polardb.sql) | MySQL 兼容分区 |
| [openGauss](opengauss.sql) | RANGE/LIST/HASH/INTERVAL 分区 |
| [TDSQL](tdsql.sql) | RANGE/LIST + shardkey 分片 |

### 国产数据库
| 方言 | 简评 |
|---|---|
| [DamengDB](dameng.sql) | RANGE/LIST/HASH 分区(Oracle 兼容) |
| [KingbaseES](kingbase.sql) | PG 兼容分区 |

### 时序数据库
| 方言 | 简评 |
|---|---|
| [TimescaleDB](timescaledb.sql) | 自动时间分区(chunk)，核心特性 |
| [TDengine](tdengine.sql) | 按时间自动分片(vnode) |

### 流处理
| 方言 | 简评 |
|---|---|
| [ksqlDB](ksqldb.sql) | Kafka 分区(KEY 分区) |
| [Materialize](materialize.sql) | 无显式分区，自动分片 |

### 嵌入式 / 轻量
| 方言 | 简评 |
|---|---|
| [H2](h2.sql) | 无分区支持 |
| [Derby](derby.sql) | 无分区支持 |

### SQL 标准
| 方言 | 简评 |
|---|---|
| [SQL Standard](sql-standard.sql) | SQL:2003 无分区标准(厂商扩展) |

## 核心差异

1. **分区类型**：RANGE（按范围，最常用于日期分区）、LIST（按枚举值）、HASH（均匀分布），Oracle/PostgreSQL/MySQL 都支持这三种，ClickHouse/Hive 有自己的分区语法
2. **声明式 vs 继承式**：PostgreSQL 10+ 用声明式分区（原生语法），10 之前用表继承模拟分区。MySQL 一直使用声明式
3. **自动分区管理**：Oracle 有自动间隔分区（INTERVAL PARTITIONING），PostgreSQL/MySQL 需要手动创建新分区或用 pg_partman 等扩展
4. **分区裁剪**：查询优化器自动跳过无关分区，但 WHERE 条件必须直接引用分区键才能触发裁剪（函数包装会破坏裁剪）
5. **大数据引擎**：Hive/Spark 的分区是目录级别的（每个分区一个目录），与 RDBMS 的分区概念不同

## 选型建议

分区的核心目的是查询裁剪和数据生命周期管理（快速删除旧分区）。日志类数据按时间 RANGE 分区最常见。分区数不宜过多（MySQL 单表限制约 8192 个分区），大数据引擎分区数通常也建议控制在合理范围。

## 版本演进

- PostgreSQL 10+：引入声明式分区（取代表继承），PostgreSQL 11+ 支持 hash 分区和默认分区
- PostgreSQL 13+：改进分区裁剪性能，支持逻辑复制分区表
- MySQL 8.0：分区与索引的交互改进，支持在分区表上使用 InnoDB 全部功能

## 横向对比

| 特性维度 | SQLite | ClickHouse | BigQuery | 传统 RDBMS (MySQL/PG/Oracle) |
|---|---|---|---|---|
| **分区支持** | 不支持表分区 | 通过 PARTITION BY 表达式分区（建表时指定） | PARTITION BY（日期/时间戳/整数范围）+ CLUSTER BY | PG 10+ 声明式 / MySQL RANGE/LIST/HASH / Oracle 全面支持 |
| **分区裁剪** | 无分区裁剪 | 自动分区裁剪（WHERE 条件匹配分区表达式时） | 自动分区裁剪（WHERE 条件包含分区列时减少扫描和费用） | 优化器自动裁剪 |
| **分区管理** | 不适用 | 自动管理分区（按表达式自动创建） | 自动管理（按分区列值自动分配） | PG/MySQL 需手动管理 / Oracle 有自动间隔分区 |
| **分区 vs 索引** | 只有索引 | 分区+排序键是核心性能手段（无传统索引） | 分区+聚簇是唯一的数据布局优化手段（无索引） | 分区和索引配合使用 |
| **数据生命周期** | 无分区删除概念 | TTL 自动过期删除分区数据 | 分区过期策略自动删除旧数据 | DROP PARTITION 快速删除旧数据 |

## 引擎开发者视角

**核心设计决策**：分区是存储层的核心组织方式，直接影响查询性能和数据生命周期管理。需要决定：分区策略（声明式 vs 自动推断）、分区裁剪的优化器深度、以及分区管理的自动化程度。

**实现建议**：
- RANGE 分区是优先级最高的分区类型——覆盖时序数据的日期分区这一最常见场景。LIST 和 HASH 分区可延后实现
- 分区裁剪必须在优化器中深度集成：WHERE 条件中的分区键比较应自动消除无关分区。注意函数包装（如 YEAR(date_col) = 2024）会破坏裁剪——引擎应尽可能做表达式简化以恢复裁剪能力
- 自动分区管理是高价值特性：Oracle 的 INTERVAL PARTITIONING（按间隔自动创建新分区）极大减轻了 DBA 负担。TimescaleDB 的自动 chunk 管理也是优秀参考
- 分区数的上限需要设计：MySQL 的 ~8192 限制源于元数据管理开销。分布式引擎的分区数可以更大但仍需控制——过多小分区会导致元数据膨胀和查询计划生成变慢
- DDL 操作的分区支持（如 ALTER TABLE ... DROP PARTITION）应该是 O(1) 操作——这是分区相比 DELETE 的核心优势
- 常见错误：分区表上的全局唯一索引实现。传统 RDBMS 中分区表的唯一索引必须包含分区键，否则需要全分区扫描来验证唯一性
