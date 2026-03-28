# 复合类型 (Array / Map / Struct) — 方言对比

## 语法支持对比

### 传统 RDBMS

| 特性 | MySQL | PostgreSQL | SQLite | Oracle | SQL Server | MariaDB | Firebird | Db2 | SAP HANA |
|---|---|---|---|---|---|---|---|---|---|
| ARRAY 类型 | ❌ (JSON 替代) | ✅ | ❌ | ⚠️ VARRAY | ❌ | ❌ | ❌ | ✅ | ✅ |
| MAP 类型 | ❌ (JSON 替代) | ⚠️ hstore | ❌ | ⚠️ Assoc. Array | ❌ | ❌ | ❌ | ✅ | ❌ |
| STRUCT/Record | ❌ (JSON 替代) | ✅ Composite | ❌ | ✅ OBJECT TYPE | ⚠️ Table-Valued | ❌ | ✅ | ✅ ROW | ✅ |
| ARRAY 索引 | ❌ | ✅ GIN | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| UNNEST/展开 | ❌ | ✅ unnest() | ❌ | ✅ TABLE() | ✅ CROSS APPLY | ❌ | ❌ | ✅ | ✅ |
| 下标起始 | N/A | 1 | N/A | 1 | N/A | N/A | N/A | 1 | 0/1 |

### 大数据 / 分析引擎

| 特性 | BigQuery | Snowflake | MaxCompute | Hive | ClickHouse | StarRocks | Trino | Hologres | Doris | DuckDB | Spark | Flink |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ARRAY 类型 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ LIST | ✅ | ✅ |
| MAP 类型 | ❌ | ❌ | ✅ MAP | ✅ MAP | ✅ Map | ✅ MAP | ✅ MAP | ✅ | ⚠️ | ✅ MAP | ✅ MAP | ✅ MAP |
| STRUCT 类型 | ✅ | ⚠️ VARIANT | ✅ STRUCT | ✅ STRUCT | ✅ Tuple | ✅ STRUCT | ✅ ROW | ✅ | ❌ | ✅ STRUCT | ✅ STRUCT | ✅ ROW |
| ARRAY 索引 | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ GIN | ❌ | ❌ | ❌ | ❌ |
| UNNEST/展开 | ✅ UNNEST | ✅ FLATTEN | ✅ EXPLODE | ✅ EXPLODE | ✅ arrayJoin | ✅ | ✅ UNNEST | ✅ unnest | ✅ | ✅ unnest | ✅ EXPLODE | ✅ UNNEST |
| 下标起始 | 0(OFFSET) | 0 | 0 | 0 | 1 | 1 | 1 | 1 | 1 | 1 | 0 | 1 |

### 云数据仓库

| 特性 | Redshift | Synapse | Databricks | Greenplum | Impala | Vertica | Teradata |
|---|---|---|---|---|---|---|---|
| ARRAY 类型 | ✅ SUPER | ❌ | ✅ | ✅ | ✅ | ✅ | ⚠️ VARRAY |
| MAP 类型 | ✅ SUPER | ❌ | ✅ MAP | ✅ hstore | ✅ | ❌ | ❌ |
| STRUCT 类型 | ✅ SUPER | ❌ | ✅ STRUCT | ✅ Composite | ✅ | ✅ | ❌ |
| UNNEST/展开 | ❌ | ❌ | ✅ EXPLODE | ✅ unnest | ❌ | ✅ EXPAND | ⚠️ |

### 分布式 / NewSQL

| 特性 | TiDB | OceanBase | CockroachDB | Spanner | YugabyteDB | PolarDB | openGauss | TDSQL | DamengDB | KingbaseES |
|---|---|---|---|---|---|---|---|---|---|---|
| ARRAY 类型 | ❌ (JSON) | ⚠️ | ✅ | ✅ ARRAY | ✅ | ✅ | ✅ | ❌ (JSON) | ⚠️ VARRAY | ✅ |
| MAP 类型 | ❌ (JSON) | ❌ | ❌ | ❌ | ⚠️ hstore | ❌ | ❌ | ❌ (JSON) | ❌ | ⚠️ hstore |
| STRUCT 类型 | ❌ (JSON) | ⚠️ | ❌ | ✅ STRUCT | ✅ Composite | ✅ | ✅ | ❌ (JSON) | ✅ OBJECT | ✅ Composite |
| ARRAY 索引 | ❌ | ❌ | ❌ | ❌ | ✅ GIN | ✅ GIN | ✅ GIN | ❌ | ❌ | ✅ GIN |

### 特殊用途

| 特性 | TimescaleDB | TDengine | ksqlDB | Materialize | H2 | Derby |
|---|---|---|---|---|---|---|
| ARRAY 类型 | ✅ | ❌ | ✅ ARRAY | ✅ LIST | ✅ | ❌ |
| MAP 类型 | ⚠️ hstore | ❌ | ✅ MAP | ✅ MAP | ❌ | ❌ |
| STRUCT 类型 | ✅ Composite | ⚠️ TAG | ✅ STRUCT | ✅ | ✅ | ❌ |
| ARRAY 索引 | ✅ GIN | ❌ | ❌ | ❌ | ❌ | ❌ |

## 关键差异

- **PostgreSQL ARRAY** 是一等公民，每种基础类型自动拥有数组类型，配合 GIN 索引实现高效的包含/重叠查询
- **BigQuery STRUCT/ARRAY** 是分析引擎中最完善的原生嵌套类型，与 Parquet/ORC 格式天然映射
- **Hive/Spark ARRAY/MAP/STRUCT** 是大数据生态的标准复合类型，配合 LATERAL VIEW EXPLODE 展开为行
- **ClickHouse** 提供最丰富的数组函数库（100+ 函数），但 Map/ Tuple 功能相对基础
- **MySQL** 无任何原生复合类型，完全依赖 JSON 替代（多值索引 8.0.17+ 部分弥补）
- **Oracle** 使用 VARRAY（定长）+ 嵌套表（变长）+ OBJECT TYPE 实现，语法繁琐且面向 PL/SQL 优化
- **Snowflake VARIANT** 是独特的半结构化类型，同时覆盖 ARRAY/MAP/STRUCT 三种语义
- **下标起始**：BigQuery/Snowflake/Hive/Spark 从 0 开始，PostgreSQL/Oracle/ClickHouse 从 1 开始
- **DuckDB LIST/STRUCT/MAP** 与 PG ARRAY/Composite 最接近，嵌入式引擎中复合类型支持最完善
