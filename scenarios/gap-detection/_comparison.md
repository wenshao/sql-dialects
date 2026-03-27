# 间隙检测与岛屿问题 (Gap Detection & Islands) — 方言对比

## 语法支持对比

### 传统 RDBMS

| 特性 | MySQL | PostgreSQL | SQLite | Oracle | SQL Server | MariaDB | Firebird | Db2 | SAP HANA |
|---|---|---|---|---|---|---|---|---|---|
| LAG / LEAD | ✅ 8.0+ | ✅ | ✅ 3.25+ | ✅ 8i+ | ✅ 2012+ | ✅ 10.2+ | ✅ 3.0+ | ✅ | ✅ |
| ROW_NUMBER() 岛屿法 | ✅ 8.0+ | ✅ | ✅ 3.25+ | ✅ 8i+ | ✅ 2005+ | ✅ 10.2+ | ✅ 3.0+ | ✅ | ✅ |
| 递归 CTE 序列生成 | ✅ 8.0+ | ✅ 8.4+ | ✅ 3.8+ | ✅ 11gR2+ | ✅ 2005+ | ✅ 10.2+ | ✅ 2.1+ | ✅ | ✅ |
| generate_series | ❌ | ✅ | ❌ | ❌ | ❌ | ⚠️ seq 引擎 | ❌ | ❌ | ✅ |
| CONNECT BY 序列生成 | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| 自连接检测间隙 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| DATEDIFF / 日期差 | ✅ | ✅ | ⚠️ julianday | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| 数字辅助表 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |

### 大数据 / 分析引擎

| 特性 | BigQuery | Snowflake | MaxCompute | Hive | ClickHouse | StarRocks | Trino | Hologres | Doris | DuckDB | Spark | Flink |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| LAG / LEAD | ✅ | ✅ | ✅ | ✅ | ✅ 21.1+ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| ROW_NUMBER() 岛屿法 | ✅ | ✅ | ✅ | ✅ | ✅ 21.1+ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| 递归 CTE | ✅ | ✅ | ❌ | ❌ | ✅ | ❌ | ✅ | ⚠️ | ❌ | ✅ | ✅ 3.0+ | ❌ |
| generate_series 等价 | ✅ GENERATE_DATE_ARRAY | ✅ | ❌ | ❌ | ✅ numbers() | ❌ | ✅ SEQUENCE | ❌ | ❌ | ✅ | ✅ sequence | ❌ |
| DATE_DIFF 函数 | ✅ | ✅ DATEDIFF | ✅ DATEDIFF | ✅ DATEDIFF | ✅ dateDiff | ✅ DATEDIFF | ✅ date_diff | ✅ | ✅ DATEDIFF | ✅ | ✅ DATEDIFF | ✅ TIMESTAMPDIFF |
| 自连接检测 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |

### 云数据仓库

| 特性 | Redshift | Synapse | Databricks | Greenplum | Impala | Vertica | Teradata |
|---|---|---|---|---|---|---|---|
| LAG / LEAD | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| ROW_NUMBER() 岛屿法 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| 递归 CTE | ❌ | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ |
| generate_series 等价 | ❌ | ❌ | ✅ sequence | ✅ | ❌ | ❌ | ❌ |
| DATE_DIFF 函数 | ✅ DATEDIFF | ✅ DATEDIFF | ✅ DATEDIFF | ✅ | ✅ DATEDIFF | ✅ DATEDIFF | ⚠️ 日期减法 |

### 分布式 / NewSQL

| 特性 | TiDB | OceanBase | CockroachDB | Spanner | YugabyteDB | PolarDB | openGauss | TDSQL | DamengDB | KingbaseES |
|---|---|---|---|---|---|---|---|---|---|---|
| LAG / LEAD | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| ROW_NUMBER() 岛屿法 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| 递归 CTE | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| generate_series | ❌ | ❌ | ✅ | ❌ | ✅ | ❌ | ✅ | ❌ | ❌ | ✅ |

### 特殊用途

| 特性 | TimescaleDB | TDengine | ksqlDB | Materialize | H2 | Derby |
|---|---|---|---|---|---|---|
| LAG / LEAD | ✅ | ❌ | ❌ | ✅ | ✅ | ✅ 10.4+ |
| ROW_NUMBER() 岛屿法 | ✅ | ❌ | ❌ | ✅ | ✅ | ✅ 10.4+ |
| 递归 CTE | ✅ | ❌ | ❌ | ✅ | ✅ | ❌ |
| generate_series | ✅ | ❌ | ❌ | ✅ | ✅ SYSTEM_RANGE | ❌ |
| time_bucket_gapfill | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |

## 关键差异

- **PostgreSQL** 的 `generate_series` 可直接生成整数或日期序列，检测间隙最为简洁
- **Oracle** 可用 `CONNECT BY LEVEL` 生成序列，无需递归 CTE
- **BigQuery** 有 `GENERATE_DATE_ARRAY` / `GENERATE_ARRAY`，通过 `UNNEST` 展开
- **ClickHouse** 有 `numbers()` 表函数，可高效生成整数序列
- **TimescaleDB** 独有 `time_bucket_gapfill` 函数，自动填充时间间隙
- **Hive / MaxCompute / StarRocks / Doris** 不支持递归 CTE，需用数字辅助表或 LATERAL VIEW
- **Redshift / Impala** 不支持递归 CTE，间隙生成需借助辅助表
- **TDengine / ksqlDB** 不支持窗口函数 LAG/LEAD，不适合传统间隙检测
- **岛屿问题**的核心方法（`id - ROW_NUMBER()` 分组法）在所有支持窗口函数的方言中通用
- **MySQL 8.0** 默认递归深度限制 1000（`cte_max_recursion_depth`），大范围序列需调整
