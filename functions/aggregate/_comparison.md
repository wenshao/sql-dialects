# 聚合函数 (Aggregate Functions) — 方言对比

## 语法支持对比

### 传统 RDBMS

| 特性 | MySQL | PostgreSQL | SQLite | Oracle | SQL Server | MariaDB | Firebird | Db2 | SAP HANA |
|---|---|---|---|---|---|---|---|---|---|
| COUNT/SUM/AVG/MIN/MAX | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| COUNT(DISTINCT) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| GROUP BY | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| HAVING | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| ROLLUP | ✅ | ✅ 9.5+ | ❌ | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ |
| CUBE | ✅ 8.0+ | ✅ 9.5+ | ❌ | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ |
| GROUPING SETS | ✅ 8.0+ | ✅ 9.5+ | ❌ | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ |
| STRING_AGG | ❌ | ✅ 9.0+ | ✅ group_concat | ✅ LISTAGG | ✅ 2017+ | ❌ | ✅ LIST | ✅ LISTAGG | ✅ STRING_AGG |
| GROUP_CONCAT | ✅ | ❌ | ✅ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ |
| ARRAY_AGG | ❌ | ✅ | ✅ json_group_array | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| STDDEV/VARIANCE | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ |
| PERCENTILE | ❌ | ✅ | ❌ | ✅ | ✅ | ❌ | ❌ | ✅ | ✅ |
| FILTER (WHERE) | ❌ | ✅ 9.4+ | ✅ 3.30+ | ❌ | ❌ | ❌ | ✅ 3.0+ | ❌ | ❌ |

### 大数据 / 分析引擎

| 特性 | BigQuery | Snowflake | MaxCompute | Hive | ClickHouse | StarRocks | Trino | Hologres | Doris | DuckDB | Spark | Flink |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ROLLUP | ✅ | ✅ | ✅ | ✅ 2.0+ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| CUBE | ✅ | ✅ | ✅ | ✅ 2.0+ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| GROUPING SETS | ✅ | ✅ | ✅ | ✅ 2.0+ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| STRING_AGG | ✅ | ✅ LISTAGG | ❌ | ❌ | ✅ groupArray | ✅ group_concat | ✅ | ✅ string_agg | ✅ group_concat | ✅ string_agg | ✅ concat_ws | ✅ LISTAGG |
| ARRAY_AGG | ✅ | ✅ | ❌ | ✅ collect_list | ✅ groupArray | ✅ array_agg | ✅ | ✅ | ❌ | ✅ | ✅ collect_list | ❌ |
| APPROX_COUNT_DISTINCT | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ approx_distinct | ✅ | ✅ | ✅ | ✅ | ✅ |
| COUNTIF | ✅ | ❌ | ❌ | ❌ | ✅ countIf | ✅ | ❌ | ❌ | ❌ | ✅ count_if | ❌ | ❌ |
| PERCENTILE | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ | ❌ |

### 云数据仓库 / 分布式

| 特性 | Redshift | Synapse | Databricks | Greenplum | Impala | Vertica | Teradata |
|---|---|---|---|---|---|---|---|
| ROLLUP/CUBE/GROUPING SETS | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| STRING_AGG | ✅ LISTAGG | ✅ STRING_AGG | ✅ | ✅ string_agg | ✅ group_concat | ❌ | ❌ |
| APPROX_COUNT_DISTINCT | ✅ | ✅ | ✅ | ❌ | ✅ | ❌ | ❌ |
| PERCENTILE | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ |

## 关键差异

- **字符串聚合**函数名称差异大：GROUP_CONCAT (MySQL), STRING_AGG (PostgreSQL/BigQuery), LISTAGG (Oracle/Snowflake), LIST (Firebird)
- **FILTER (WHERE)** 子句仅 PostgreSQL、SQLite 3.30+、Firebird、DuckDB 支持
- **GROUPING SETS/ROLLUP/CUBE** 在 MySQL 8.0+、Hive 2.0+ 才引入，之前版本不支持
- **APPROX_COUNT_DISTINCT** 是大数据引擎的重要优化特性，传统数据库大多不支持
- **BigQuery** 独有 COUNTIF 函数，其他引擎需用 SUM(CASE WHEN) 模拟
- **ClickHouse** 聚合函数最丰富，支持 -If/-Array/-ForEach 等组合后缀
- **SQLite** 不支持 STDDEV/VARIANCE 等统计函数
