# 累计求和 (Running Total) — 方言对比

## 语法支持对比

### 传统 RDBMS

| 特性 | MySQL | PostgreSQL | SQLite | Oracle | SQL Server | MariaDB | Firebird | Db2 | SAP HANA |
|---|---|---|---|---|---|---|---|---|---|
| SUM() OVER (ORDER BY) | ✅ 8.0+ | ✅ | ✅ 3.25+ | ✅ 8i+ | ✅ 2005+ | ✅ 10.2+ | ✅ 3.0+ | ✅ | ✅ |
| ROWS 帧 | ✅ 8.0+ | ✅ | ✅ 3.25+ | ✅ | ✅ 2012+ | ✅ 10.2+ | ✅ 3.0+ | ✅ | ✅ |
| RANGE 帧 | ✅ 8.0+ | ✅ | ✅ 3.28+ | ✅ | ✅ 2012+ | ✅ 10.2+ | ✅ | ✅ | ✅ |
| RANGE + INTERVAL | ✅ 8.0+ | ✅ | ❌ | ✅ | ❌ | ✅ 10.2+ | ❌ | ✅ | ✅ |
| GROUPS 帧 | ❌ | ✅ 11+ | ✅ 3.28+ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| AVG() OVER (移动平均) | ✅ 8.0+ | ✅ | ✅ 3.25+ | ✅ | ✅ 2012+ | ✅ 10.2+ | ✅ 3.0+ | ✅ | ✅ |
| COUNT() OVER | ✅ 8.0+ | ✅ | ✅ 3.25+ | ✅ | ✅ 2012+ | ✅ 10.2+ | ✅ 3.0+ | ✅ | ✅ |
| PARTITION BY 分组累计 | ✅ 8.0+ | ✅ | ✅ 3.25+ | ✅ | ✅ 2012+ | ✅ 10.2+ | ✅ 3.0+ | ✅ | ✅ |
| 自连接替代 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| 用户变量替代 | ✅ 5.7 | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ |

### 大数据 / 分析引擎

| 特性 | BigQuery | Snowflake | MaxCompute | Hive | ClickHouse | StarRocks | Trino | Hologres | Doris | DuckDB | Spark | Flink |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| SUM() OVER (ORDER BY) | ✅ | ✅ | ✅ | ✅ | ✅ 21.1+ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| ROWS 帧 | ✅ | ✅ | ✅ | ✅ | ✅ 21.1+ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| RANGE 帧 | ✅ | ✅ | ⚠️ | ✅ | ✅ | ⚠️ | ✅ | ✅ | ⚠️ | ✅ | ✅ | ✅ |
| RANGE + INTERVAL | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ✅ | ⚠️ | ❌ | ✅ | ❌ | ❌ |
| GROUPS 帧 | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ |
| AVG() OVER (移动平均) | ✅ | ✅ | ✅ | ✅ | ✅ 21.1+ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| 条件重置累计 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| runningAccumulate | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |

### 云数据仓库

| 特性 | Redshift | Synapse | Databricks | Greenplum | Impala | Vertica | Teradata |
|---|---|---|---|---|---|---|---|
| SUM() OVER (ORDER BY) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| ROWS 帧 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| RANGE 帧 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| RANGE + INTERVAL | ❌ | ❌ | ❌ | ✅ | ❌ | ✅ | ✅ |
| AVG() OVER (移动平均) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| QUALIFY | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ✅ |

### 分布式 / NewSQL

| 特性 | TiDB | OceanBase | CockroachDB | Spanner | YugabyteDB | PolarDB | openGauss | TDSQL | DamengDB | KingbaseES |
|---|---|---|---|---|---|---|---|---|---|---|
| SUM() OVER (ORDER BY) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| ROWS 帧 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| RANGE 帧 | ✅ | ✅ | ✅ | ⚠️ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| RANGE + INTERVAL | ❌ | ⚠️ | ❌ | ❌ | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ |
| AVG() OVER (移动平均) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |

### 特殊用途

| 特性 | TimescaleDB | TDengine | ksqlDB | Materialize | H2 | Derby |
|---|---|---|---|---|---|---|
| SUM() OVER (ORDER BY) | ✅ | ❌ | ❌ | ✅ | ✅ | ✅ 10.4+ |
| ROWS 帧 | ✅ | ❌ | ❌ | ✅ | ✅ | ✅ 10.4+ |
| RANGE 帧 | ✅ | ❌ | ❌ | ✅ | ✅ | ⚠️ |
| INTERVAL 时间窗口聚合 | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ |
| time_bucket 聚合 | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| CSUM (内置累加) | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |

## 关键差异

- **TDengine** 不支持标准窗口函数，只能用 `INTERVAL` 时间窗口做时序聚合
- **ksqlDB** 不支持传统窗口函数，仅支持流式时间窗口（Tumbling / Hopping / Session）
- **MySQL 5.7** 需用用户变量 `@running` 模拟累计求和，8.0+ 支持标准窗口函数
- **ClickHouse** 21.1+ 支持标准窗口函数，还有独有的 `runningAccumulate` 函数
- **RANGE + INTERVAL**（如最近 30 天滑动总和）在不同方言中支持差异较大
- **GROUPS 帧**（SQL:2011 标准）目前仅 PostgreSQL 11+、SQLite 3.28+、DuckDB 支持
- **SQL Server 2005-2008** 仅支持 `ROWS UNBOUNDED PRECEDING`，不支持其他帧定义
- **TimescaleDB** 提供 `time_bucket` 函数，适合时序数据的时间段聚合
- **大数据引擎**中累计计算会导致数据倾斜，建议先 PARTITION BY 再做累计
