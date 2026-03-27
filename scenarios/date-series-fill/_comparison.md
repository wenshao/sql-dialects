# 日期序列生成与间隙填充 (Date Series Fill) — 方言对比

## 语法支持对比

### 传统 RDBMS

| 特性 | MySQL | PostgreSQL | SQLite | Oracle | SQL Server | MariaDB | Firebird | Db2 | SAP HANA |
|---|---|---|---|---|---|---|---|---|---|
| 递归 CTE 生成日期 | ✅ 8.0+ | ✅ 8.4+ | ✅ 3.8+ | ✅ 11gR2+ | ✅ 2005+ | ✅ 10.2+ | ✅ 2.1+ | ✅ | ✅ |
| generate_series | ❌ | ✅ | ❌ | ❌ | ❌ | ⚠️ seq 引擎 | ❌ | ❌ | ✅ SERIES_GENERATE |
| CONNECT BY LEVEL 日期 | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| LEFT JOIN 填充 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| COALESCE 填零 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| LAG IGNORE NULLS | ❌ | ❌ | ❌ | ✅ | ✅ 2022+ | ❌ | ❌ | ✅ | ✅ |
| LAST_VALUE IGNORE NULLS | ❌ | ❌ | ❌ | ✅ | ✅ 2022+ | ❌ | ❌ | ✅ | ✅ |
| INTERVAL 日期运算 | ✅ | ✅ | ❌ | ✅ | ❌ | ✅ | ❌ | ✅ | ✅ |
| 日期加减函数 | ✅ DATE_ADD | ✅ + INTERVAL | ✅ date() | ✅ ADD_MONTHS | ✅ DATEADD | ✅ DATE_ADD | ✅ DATEADD | ✅ | ✅ ADD_DAYS |

### 大数据 / 分析引擎

| 特性 | BigQuery | Snowflake | MaxCompute | Hive | ClickHouse | StarRocks | Trino | Hologres | Doris | DuckDB | Spark | Flink |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 递归 CTE 生成日期 | ✅ | ✅ | ❌ | ❌ | ✅ | ❌ | ✅ | ⚠️ | ❌ | ✅ | ✅ 3.0+ | ❌ |
| 内置日期序列函数 | ✅ GENERATE_DATE_ARRAY | ✅ | ❌ | ❌ | ❌ | ❌ | ✅ SEQUENCE | ❌ | ❌ | ✅ generate_series | ✅ sequence | ❌ |
| UNNEST 展开数组 | ✅ | ✅ FLATTEN | ❌ | ✅ LATERAL VIEW | ❌ | ❌ | ✅ | ❌ | ❌ | ✅ | ✅ EXPLODE | ❌ |
| numbers() 表函数 | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| LEFT JOIN 填充 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| IGNORE NULLS | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ✅ | ✅ | ❌ |
| COALESCE 填零 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |

### 云数据仓库

| 特性 | Redshift | Synapse | Databricks | Greenplum | Impala | Vertica | Teradata |
|---|---|---|---|---|---|---|---|
| 递归 CTE 生成日期 | ❌ | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ |
| 内置序列函数 | ❌ | ❌ | ✅ sequence | ✅ generate_series | ❌ | ❌ | ❌ |
| 日期维度表方式 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| IGNORE NULLS | ✅ | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ |
| LEFT JOIN 填充 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |

### 分布式 / NewSQL

| 特性 | TiDB | OceanBase | CockroachDB | Spanner | YugabyteDB | PolarDB | openGauss | TDSQL | DamengDB | KingbaseES |
|---|---|---|---|---|---|---|---|---|---|---|
| 递归 CTE 生成日期 | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| generate_series | ❌ | ❌ | ✅ | ❌ | ✅ | ❌ | ✅ | ❌ | ❌ | ✅ |
| IGNORE NULLS | ❌ | ⚠️ | ❌ | ❌ | ✅ | ❌ | ✅ | ❌ | ✅ | ✅ |
| LEFT JOIN 填充 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |

### 特殊用途

| 特性 | TimescaleDB | TDengine | ksqlDB | Materialize | H2 | Derby |
|---|---|---|---|---|---|---|
| 递归 CTE 生成日期 | ✅ | ❌ | ❌ | ✅ | ✅ | ❌ |
| generate_series | ✅ | ❌ | ❌ | ✅ | ✅ SYSTEM_RANGE | ❌ |
| time_bucket_gapfill | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| FILL 策略 | ✅ interpolate/locf | ✅ FILL | ❌ | ❌ | ❌ | ❌ |
| INTERVAL 聚合 | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ |

## 关键差异

- **PostgreSQL** 的 `generate_series(start, end, interval)` 是最优雅的日期序列生成方式
- **BigQuery** 的 `GENERATE_DATE_ARRAY` + `UNNEST` 等价于 `generate_series`
- **Oracle** 可用 `CONNECT BY LEVEL` 生成日期序列，无需递归 CTE
- **TimescaleDB** 独有 `time_bucket_gapfill` 函数，支持 `interpolate`（线性插值）和 `locf`（前值填充）
- **TDengine** 的 `FILL` 子句可自动填充缺失时间点（支持 PREV / LINEAR / NULL / VALUE 策略）
- **IGNORE NULLS**（用最近已知值填充）在不同方言中支持差异大；不支持时需用 `COUNT` 分组 + `FIRST_VALUE` 模拟
- **Hive / MaxCompute / StarRocks / Doris / Flink** 不支持递归 CTE，需要预建日期维度表或使用 LATERAL VIEW
- **Redshift / Impala** 不支持递归 CTE，通常使用预建的日期维度表
- **MySQL 8.0** 递归深度默认 1000，生成超过 1000 天的序列需调整 `cte_max_recursion_depth`
- **SQLite** 日期运算需要用 `date()` 函数，不支持 `INTERVAL` 语法
