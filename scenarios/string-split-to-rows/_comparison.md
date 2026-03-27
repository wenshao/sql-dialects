# 字符串拆分为多行 (String Split to Rows) — 方言对比

## 语法支持对比

### 传统 RDBMS

| 特性 | MySQL | PostgreSQL | SQLite | Oracle | SQL Server | MariaDB | Firebird | Db2 | SAP HANA |
|---|---|---|---|---|---|---|---|---|---|
| 专用拆分函数 | ❌ | ✅ STRING_TO_ARRAY + UNNEST | ❌ | ❌ | ✅ STRING_SPLIT 2016+ | ❌ | ❌ | ❌ | ❌ |
| regexp_split_to_table | ❌ | ✅ 8.3+ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| JSON_TABLE 拆分 | ✅ 8.0.4+ | ❌ | ❌ | ✅ 21c+ | ✅ OPENJSON 2016+ | ✅ 10.6+ | ❌ | ❌ | ❌ |
| CONNECT BY + REGEXP_SUBSTR | ❌ | ❌ | ❌ | ✅ 10g+ | ❌ | ❌ | ❌ | ❌ | ❌ |
| 递归 CTE 拆分 | ✅ 8.0+ | ✅ 8.4+ | ✅ 3.8+ | ✅ 11gR2+ | ✅ 2005+ | ✅ 10.2+ | ✅ 2.1+ | ✅ | ✅ |
| 数字辅助表 + SUBSTRING | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| XML 方式拆分 | ❌ | ❌ | ❌ | ✅ XMLTABLE | ✅ XML nodes | ❌ | ❌ | ✅ XMLTABLE | ❌ |
| LATERAL + WITH ORDINALITY | ❌ | ✅ 9.3+ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| 保留序号 | ⚠️ 手动 | ✅ WITH ORDINALITY | ⚠️ 手动 | ✅ LEVEL | ✅ 2022+ ordinal | ⚠️ 手动 | ⚠️ 手动 | ⚠️ 手动 | ⚠️ 手动 |

### 大数据 / 分析引擎

| 特性 | BigQuery | Snowflake | MaxCompute | Hive | ClickHouse | StarRocks | Trino | Hologres | Doris | DuckDB | Spark | Flink |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 专用拆分函数 | ✅ SPLIT + UNNEST | ✅ SPLIT_TO_TABLE | ❌ | ✅ EXPLODE(SPLIT()) | ✅ splitByChar | ✅ SPLIT + UNNEST | ✅ SPLIT + UNNEST | ✅ | ✅ EXPLODE(SPLIT()) | ✅ UNNEST(STRING_SPLIT) | ✅ EXPLODE(SPLIT()) | ✅ UNNEST |
| LATERAL VIEW EXPLODE | ❌ | ❌ | ✅ | ✅ | ❌ | ✅ | ❌ | ❌ | ✅ | ❌ | ✅ | ❌ |
| FLATTEN | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| 递归 CTE 拆分 | ✅ | ✅ | ❌ | ❌ | ✅ | ❌ | ✅ | ⚠️ | ❌ | ✅ | ✅ 3.0+ | ❌ |
| 保留序号 | ✅ WITH OFFSET | ✅ seq | ⚠️ | ⚠️ POSEXPLODE | ✅ arrayJoin | ⚠️ | ✅ WITH ORDINALITY | ⚠️ | ⚠️ POSEXPLODE | ✅ WITH ORDINALITY | ✅ POSEXPLODE | ⚠️ |
| arrayJoin | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |

### 云数据仓库

| 特性 | Redshift | Synapse | Databricks | Greenplum | Impala | Vertica | Teradata |
|---|---|---|---|---|---|---|---|
| 专用拆分函数 | ❌ | ✅ STRING_SPLIT | ✅ EXPLODE(SPLIT()) | ✅ regexp_split_to_table | ❌ | ❌ | ✅ STRTOK_SPLIT_TO_TABLE |
| 递归 CTE 拆分 | ❌ | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ |
| JSON/XML 方式 | ✅ JSON_PARSE | ✅ OPENJSON | ❌ | ❌ | ❌ | ❌ | ❌ |
| 数字辅助表 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |

### 分布式 / NewSQL

| 特性 | TiDB | OceanBase | CockroachDB | Spanner | YugabyteDB | PolarDB | openGauss | TDSQL | DamengDB | KingbaseES |
|---|---|---|---|---|---|---|---|---|---|---|
| 专用拆分函数 | ❌ | ❌ | ❌ | ✅ SPLIT + UNNEST | ✅ regexp_split_to_table | ❌ | ✅ regexp_split_to_table | ❌ | ❌ | ✅ regexp_split_to_table |
| JSON_TABLE 拆分 | ✅ | ✅ | ❌ | ❌ | ❌ | ✅ | ❌ | ✅ | ⚠️ | ❌ |
| 递归 CTE 拆分 | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |

### 特殊用途

| 特性 | TimescaleDB | TDengine | ksqlDB | Materialize | H2 | Derby |
|---|---|---|---|---|---|---|
| 专用拆分函数 | ✅ regexp_split_to_table | ❌ | ❌ | ✅ regexp_split_to_table | ❌ | ❌ |
| 递归 CTE 拆分 | ✅ | ❌ | ❌ | ✅ | ✅ | ❌ |
| 数字辅助表 | ✅ | ❌ | ❌ | ✅ | ✅ | ✅ |

## 关键差异

- **PostgreSQL** 有最丰富的拆分方式：`STRING_TO_ARRAY` + `UNNEST`、`regexp_split_to_table`、`LATERAL UNNEST WITH ORDINALITY`
- **SQL Server 2016+** 的 `STRING_SPLIT` 最简单直接；2022+ 新增 `ordinal` 参数支持保留序号
- **MySQL** 无专用拆分函数，推荐用 `JSON_TABLE` 将逗号字符串转 JSON 数组再展开（8.0.4+）
- **Oracle** 经典方式是 `CONNECT BY LEVEL + REGEXP_SUBSTR`；21c+ 也支持 `JSON_TABLE`
- **Hive / Spark / Doris** 使用 `LATERAL VIEW EXPLODE(SPLIT())` 模式
- **ClickHouse** 有独有的 `arrayJoin` + `splitByChar` / `splitByString` 组合
- **Snowflake** 有 `SPLIT_TO_TABLE` 专用函数和 `FLATTEN` 通用展开函数
- **Teradata** 有 `STRTOK_SPLIT_TO_TABLE` 专用函数
- **BigQuery** 使用 `SPLIT` + `UNNEST`，配合 `WITH OFFSET` 保留序号
- **TDengine / ksqlDB** 无字符串拆分到多行的能力
- 不支持专用函数的方言都可以用**递归 CTE** 或**数字辅助表**作为通用解决方案
