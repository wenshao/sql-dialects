# 复合类型 (ARRAY / MAP / STRUCT)

各数据库复合类型对比，包括 ARRAY、MAP、STRUCT/ROW 的定义与操作。

## 方言列表

### 传统关系型数据库
| 方言 | 简评 |
|---|---|
| [MySQL](mysql.sql) | JSON 数组替代，无原生 ARRAY 类型 |
| [PostgreSQL](postgres.sql) | 原生 ARRAY 类型，丰富操作符/函数 |
| [SQLite](sqlite.sql) | JSON 数组替代，无原生复合类型 |
| [Oracle](oracle.sql) | VARRAY/嵌套表/OBJECT 类型 |
| [SQL Server](sqlserver.sql) | 无原生 ARRAY，用 JSON/XML/表变量替代 |
| [MariaDB](mariadb.sql) | 无原生 ARRAY 类型 |
| [Firebird](firebird.sql) | 无原生 ARRAY 类型(3.0 前有受限支持) |
| [IBM Db2](db2.sql) | ARRAY 类型(存储过程中) |
| [SAP HANA](saphana.sql) | ARRAY 类型支持 |

### 大数据 / 分析型引擎
| 方言 | 简评 |
|---|---|
| [BigQuery](bigquery.sql) | 原生 ARRAY/STRUCT 类型，UNNEST 展开 |
| [Snowflake](snowflake.sql) | VARIANT/ARRAY/OBJECT 半结构化类型 |
| [ClickHouse](clickhouse.sql) | Array/Map/Tuple/Nested 丰富复合类型 |
| [Hive](hive.sql) | ARRAY/MAP/STRUCT 完整复合类型 |
| [Spark SQL](spark.sql) | ARRAY/MAP/STRUCT 完整复合类型 |
| [Flink SQL](flink.sql) | ARRAY/MAP/ROW 复合类型 |
| [StarRocks](starrocks.sql) | ARRAY/MAP/STRUCT(3.1+) |
| [Doris](doris.sql) | ARRAY/MAP/STRUCT(2.0+) |
| [Trino](trino.sql) | ARRAY/MAP/ROW 完整复合类型 |
| [DuckDB](duckdb.sql) | LIST/MAP/STRUCT 原生支持 |
| [MaxCompute](maxcompute.sql) | ARRAY/MAP/STRUCT 复合类型 |
| [Hologres](hologres.sql) | ARRAY 类型(PG 兼容)，无 MAP/STRUCT |

### 云数仓
| 方言 | 简评 |
|---|---|
| [Redshift](redshift.sql) | SUPER 半结构化类型 |
| [Azure Synapse](synapse.sql) | 无原生复合类型，用 JSON 替代 |
| [Databricks SQL](databricks.sql) | ARRAY/MAP/STRUCT 完整支持 |
| [Greenplum](greenplum.sql) | PG 兼容 ARRAY |
| [Impala](impala.sql) | ARRAY/MAP/STRUCT(Parquet/ORC) |
| [Vertica](vertica.sql) | ROW/ARRAY 类型(10.0+) |
| [Teradata](teradata.sql) | JSON/PERIOD 类型，无原生 ARRAY |

### 分布式 / NewSQL
| 方言 | 简评 |
|---|---|
| [TiDB](tidb.sql) | 无原生 ARRAY，用 JSON 替代 |
| [OceanBase](oceanbase.sql) | 无原生 ARRAY 类型 |
| [CockroachDB](cockroachdb.sql) | PG 兼容 ARRAY |
| [Spanner](spanner.sql) | ARRAY 类型 + STRUCT(查询中) |
| [YugabyteDB](yugabytedb.sql) | PG 兼容 ARRAY |
| [PolarDB](polardb.sql) | MySQL 兼容，无原生 ARRAY |
| [openGauss](opengauss.sql) | PG 兼容 ARRAY |
| [TDSQL](tdsql.sql) | MySQL 兼容，无原生 ARRAY |

### 国产数据库
| 方言 | 简评 |
|---|---|
| [DamengDB](dameng.sql) | Oracle 兼容 VARRAY/嵌套表 |
| [KingbaseES](kingbase.sql) | PG 兼容 ARRAY |

### 时序数据库
| 方言 | 简评 |
|---|---|
| [TimescaleDB](timescaledb.sql) | 继承 PG ARRAY |
| [TDengine](tdengine.sql) | 无复合类型，NCHAR/BINARY 基础类型 |

### 流处理
| 方言 | 简评 |
|---|---|
| [ksqlDB](ksqldb.sql) | ARRAY/MAP/STRUCT 类型支持 |
| [Materialize](materialize.sql) | PG 兼容 ARRAY/MAP/RECORD |

### 嵌入式 / 轻量
| 方言 | 简评 |
|---|---|
| [H2](h2.sql) | ARRAY 类型支持 |
| [Derby](derby.sql) | 无 ARRAY 类型 |

### SQL 标准
| 方言 | 简评 |
|---|---|
| [SQL Standard](sql-standard.sql) | SQL:2003 ARRAY / SQL:2016 JSON |

## 核心差异

1. **ARRAY 支持**：PostgreSQL 原生支持 ARRAY 类型（任意元素类型），BigQuery/ClickHouse/Hive/Spark 都支持 ARRAY，MySQL/SQL Server/Oracle 不原生支持
2. **MAP 类型**：Hive/Spark/ClickHouse/Flink 支持 MAP 类型（键值对），PostgreSQL 用 hstore 扩展或 JSONB 模拟，传统 RDBMS 大多不支持
3. **STRUCT/ROW 类型**：BigQuery 的 STRUCT、PostgreSQL 的 ROW/复合类型、Hive 的 STRUCT，适合嵌套数据但查询语法各不相同
4. **展开操作**：PostgreSQL 用 unnest()，BigQuery 用 UNNEST()，Hive/Spark 用 explode()/LATERAL VIEW，ClickHouse 用 arrayJoin()

## 选型建议

复合类型在分析型引擎中很常见（处理嵌套 JSON/Parquet 数据），但在 OLTP 数据库中应谨慎使用（违反第一范式）。PostgreSQL 的 ARRAY 适合存储标签列表等简单场景。需要复杂嵌套数据结构时优先考虑 BigQuery/Spark 等原生支持 STRUCT 的引擎。

## 版本演进

- PostgreSQL：ARRAY 类型从早期版本就支持，是传统 RDBMS 中支持最完善的
- Hive 0.7+：引入复合类型（ARRAY、MAP、STRUCT）
- BigQuery：原生支持 ARRAY 和 STRUCT，是云数仓中嵌套数据能力最强的
- ClickHouse：ARRAY 和 MAP 支持完善，近年引入 Tuple/Named Tuple 类型

## 横向对比

| 特性维度 | SQLite | ClickHouse | BigQuery | 传统 RDBMS (MySQL/PG/Oracle) |
|---|---|---|---|---|
| **ARRAY 支持** | 不支持原生 ARRAY（可用 JSON 数组模拟） | 完整支持 Array(T) 类型，丰富的数组函数 | 完整支持 ARRAY 类型 | PG 原生支持 / MySQL 不支持 / Oracle 需 VARRAY |
| **MAP 类型** | 不支持（可用 JSON 对象模拟） | 支持 Map(K,V) 类型 | 不原生支持（用 STRUCT 的 ARRAY 模拟） | PG 用 hstore 或 JSONB / MySQL 不支持 |
| **STRUCT/ROW** | 不支持 | 支持 Tuple/Named Tuple | 完整支持 STRUCT（嵌套数据的核心类型） | PG 支持 ROW/复合类型 / MySQL 不支持 |
| **展开操作** | 不支持 | arrayJoin() 展开数组为多行 | UNNEST() 展开数组/结构体 | PG unnest() / Hive explode() |
| **动态类型影响** | 用 JSON 模拟复合类型，灵活但无类型检查 | 严格类型的复合类型，高性能列式操作 | 严格类型 | PG 严格 / MySQL 不支持原生复合类型 |

## 引擎开发者视角

**核心设计决策**：复合类型（ARRAY/MAP/STRUCT）的支持程度直接影响引擎处理半结构化数据的能力。这是 OLAP 引擎与传统 RDBMS 的关键差异点。

**实现建议**：
- ARRAY 类型是优先级最高的复合类型——覆盖标签列表、多值属性等常见场景。PostgreSQL 的 ARRAY 实现（支持任意元素类型、多维数组、数组运算符）是完整参考
- UNNEST（展开数组为行）和 ARRAY_AGG（聚合行为数组）是 ARRAY 类型的配套函数，必须同时实现。两者互为逆操作
- MAP 类型（键值对集合）在大数据引擎中很常见（Hive/Spark/ClickHouse），适合存储动态属性。实现可以基于两个并行数组（keys 数组 + values 数组）
- STRUCT/ROW 类型在列式引擎中的存储设计是关键：BigQuery 将 STRUCT 的每个字段存为独立的列——这保持了列式存储的优势。行存引擎中 STRUCT 通常序列化为二进制块存储
- 嵌套类型的深度应有限制——无限嵌套（如 ARRAY<STRUCT<ARRAY<...>>>）会导致类型推导和存储管理的复杂度爆炸
- 常见错误：复合类型的比较和排序语义未定义清晰。ARRAY 的比较是逐元素比较？STRUCT 的排序是按字段顺序？NULL 元素如何影响比较结果？这些都需要在设计阶段明确
