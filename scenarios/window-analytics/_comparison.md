# 窗口函数实战分析 (Window Analytics) — 方言对比

## 语法支持对比

### 传统 RDBMS

| 特性 | MySQL | PostgreSQL | SQLite | Oracle | SQL Server | MariaDB | Firebird | Db2 | SAP HANA |
|---|---|---|---|---|---|---|---|---|---|
| 移动平均 (ROWS/RANGE 帧) | ✅ 8.0+ | ✅ | ✅ 3.25+ | ✅ 8i+ | ✅ 2005+ | ✅ 10.2+ | ✅ 3.0+ | ✅ | ✅ |
| RANGE + INTERVAL 帧 | ❌ | ✅ | ❌ | ✅ | ⚠️ 2022+ | ❌ | ❌ | ✅ | ✅ |
| 同比/环比 (LAG/LEAD) | ✅ 8.0+ | ✅ | ✅ 3.25+ | ✅ 8i+ | ✅ 2012+ | ✅ 10.2+ | ✅ 3.0+ | ✅ | ✅ |
| 占比 (SUM OVER) | ✅ 8.0+ | ✅ | ✅ 3.25+ | ✅ 8i+ | ✅ 2005+ | ✅ 10.2+ | ✅ 3.0+ | ✅ | ✅ |
| RATIO_TO_REPORT | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| 累计聚合 (RUNNING SUM) | ✅ 8.0+ | ✅ | ✅ 3.25+ | ✅ 8i+ | ✅ 2005+ | ✅ 10.2+ | ✅ 3.0+ | ✅ | ✅ |
| 环比增长率 (LAG 计算) | ✅ 8.0+ | ✅ | ✅ 3.25+ | ✅ 8i+ | ✅ 2012+ | ✅ 10.2+ | ✅ 3.0+ | ✅ | ✅ |
| PERCENTILE_CONT | ❌ | ✅ | ❌ | ✅ | ✅ 2012+ | ❌ | ❌ | ✅ | ✅ |
| PERCENTILE_DISC | ❌ | ✅ | ❌ | ✅ | ✅ 2012+ | ❌ | ❌ | ✅ | ✅ |
| WINDOW 子句 (命名窗口) | ✅ 8.0+ | ✅ | ❌ | ❌ | ❌ | ✅ 10.2+ | ❌ | ✅ | ❌ |
| FIRST_VALUE / LAST_VALUE | ✅ 8.0+ | ✅ | ✅ 3.25+ | ✅ 8i+ | ✅ 2012+ | ✅ 10.2+ | ✅ 3.0+ | ✅ | ✅ |
| NTH_VALUE | ✅ 8.0+ | ✅ 9.4+ | ❌ | ✅ 11g+ | ✅ 2012+ | ✅ 10.2+ | ❌ | ✅ | ✅ |
| PERCENT_RANK / CUME_DIST | ✅ 8.0+ | ✅ | ✅ 3.25+ | ✅ 8i+ | ✅ 2005+ | ✅ 10.2+ | ✅ 3.0+ | ✅ | ✅ |
| IGNORE NULLS | ❌ | ❌ | ❌ | ✅ | ✅ 2012+ | ❌ | ❌ | ✅ | ❌ |

### 大数据 / 分析引擎

| 特性 | BigQuery | Snowflake | MaxCompute | Hive | ClickHouse | StarRocks | Trino | Hologres | Doris | DuckDB | Spark | Flink |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 移动平均 (ROWS/RANGE 帧) | ✅ | ✅ | ✅ | ✅ | ✅ 21.1+ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| RANGE + INTERVAL 帧 | ⚠️ 需转换 | ⚠️ 需转换 | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ |
| 同比/环比 (LAG/LEAD) | ✅ | ✅ | ✅ | ✅ | ✅ 21.1+ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| 占比 (SUM OVER) | ✅ | ✅ | ✅ | ✅ | ✅ 21.1+ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| 累计聚合 (RUNNING SUM) | ✅ | ✅ | ✅ | ✅ | ✅ 21.1+ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| 环比增长率 (LAG 计算) | ✅ | ✅ | ✅ | ✅ | ✅ 21.1+ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| PERCENTILE_CONT | ✅ 语法不同 | ✅ | ⚠️ 近似 | ✅ | ❌ | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ | ❌ |
| WINDOW 子句 (命名窗口) | ✅ | ✅ | ❌ | ❌ | ❌ | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ |
| NTH_VALUE | ✅ | ✅ | ❌ | ❌ | ❌ | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ | ❌ |
| IGNORE NULLS | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| SAFE_DIVIDE / 防除零 | ✅ | ✅ NULLIF | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |

### 云数据仓库

| 特性 | Redshift | Synapse | Databricks | Greenplum | Impala | Vertica | Teradata |
|---|---|---|---|---|---|---|---|
| 移动平均 (ROWS/RANGE 帧) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| RANGE + INTERVAL 帧 | ❌ | ❌ | ❌ | ✅ | ❌ | ✅ | ✅ |
| 同比/环比 (LAG/LEAD) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| 占比 (SUM OVER) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| 累计聚合 (RUNNING SUM) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| 环比增长率 (LAG 计算) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| PERCENTILE_CONT | ✅ | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ |
| WINDOW 子句 (命名窗口) | ❌ | ❌ | ✅ | ✅ | ❌ | ❌ | ✅ |
| QUALIFY 过滤窗口 | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ✅ |

### 分布式 / NewSQL

| 特性 | TiDB | OceanBase | CockroachDB | Spanner | YugabyteDB | PolarDB | openGauss | TDSQL | DamengDB | KingbaseES |
|---|---|---|---|---|---|---|---|---|---|---|
| 移动平均 (ROWS/RANGE 帧) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| RANGE + INTERVAL 帧 | ❌ | ⚠️ | ❌ | ❌ | ✅ | ⚠️ | ✅ | ❌ | ⚠️ | ✅ |
| 同比/环比 (LAG/LEAD) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| 占比 (SUM OVER) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| 累计聚合 (RUNNING SUM) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| 环比增长率 (LAG 计算) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| PERCENTILE_CONT | ❌ | ✅ | ❌ | ❌ | ✅ | ❌ | ✅ | ❌ | ✅ | ✅ |
| WINDOW 子句 (命名窗口) | ❌ | ✅ | ✅ | ❌ | ✅ | ❌ | ✅ | ❌ | ⚠️ | ✅ |

### 特殊用途

| 特性 | TimescaleDB | TDengine | ksqlDB | Materialize | H2 | Derby |
|---|---|---|---|---|---|---|
| 移动平均 (ROWS/RANGE 帧) | ✅ | ⚠️ 有限 | ❌ | ✅ | ✅ | ✅ 10.4+ |
| 同比/环比 (LAG/LEAD) | ✅ | ❌ | ❌ | ✅ | ✅ | ✅ 10.4+ |
| 占比 (SUM OVER) | ✅ | ❌ | ❌ | ✅ | ✅ | ✅ 10.4+ |
| 累计聚合 (RUNNING SUM) | ✅ | ❌ | ❌ | ✅ | ✅ | ✅ 10.4+ |
| 环比增长率 (LAG 计算) | ✅ | ❌ | ❌ | ✅ | ✅ | ✅ 10.4+ |
| PERCENTILE_CONT | ✅ | ❌ | ❌ | ✅ | ✅ | ✅ 10.4+ |

## 关键差异

- **MySQL 8.0** 是窗口函数的分水岭，5.7 及以下完全不支持窗口函数（需用户变量模拟）
- **Oracle** 是窗口函数的发明者（8i, 1999），独有 `RATIO_TO_REPORT`、`MEDIAN`、`KEEP (DENSE_RANK)` 等便捷函数
- **RANGE + INTERVAL 帧** 是时间序列分析的核心特性，仅 PostgreSQL、Oracle、Db2 等原生支持；MySQL 不支持（需用 ROWS 近似）
- **PERCENTILE_CONT / PERCENTILE_DISC** 在 MySQL/MariaDB 中不可用，需用 `PERCENT_RANK` + 子查询或 `NTILE` 模拟
- **WINDOW 子句**（命名窗口复用）可减少重复定义并帮助优化器合并排序，PostgreSQL/MySQL/DuckDB/Trino 支持但 Oracle/SQL Server 不支持
- **IGNORE NULLS** 仅 Oracle/SQL Server/BigQuery/Snowflake 支持，跳过 NULL 值在 FIRST_VALUE/LAG 等场景中很实用
- **BigQuery** 的 `PERCENTILE_CONT` 语法与 SQL 标准不同（`PERCENTILE_CONT(expr, percentile) OVER (...)`），且提供 `APPROX_QUANTILES` 用于大数据集近似计算
- **ClickHouse** 21.1 之前不支持窗口函数，现在支持标准窗口函数但不支持 `RANGE + INTERVAL` 帧
- **TDengine / ksqlDB** 不支持标准窗口函数，时序分析需依赖内置聚合函数
- **Spark** 不支持 `RANGE + INTERVAL` 帧，但窗口函数覆盖全面，是大数据窗口分析的主力引擎
