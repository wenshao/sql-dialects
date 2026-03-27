# Top-N 查询 (Ranking / Top-N) — 方言对比

## 语法支持对比

### 传统 RDBMS

| 特性 | MySQL | PostgreSQL | SQLite | Oracle | SQL Server | MariaDB | Firebird | Db2 | SAP HANA |
|---|---|---|---|---|---|---|---|---|---|
| LIMIT / OFFSET | ✅ | ✅ | ✅ | ❌ | ❌ | ✅ | ❌ | ❌ | ✅ |
| FETCH FIRST | ❌ | ✅ 8.4+ | ❌ | ✅ 12c+ | ✅ 2012+ | ✅ 10.6+ | ✅ 4.0+ | ✅ | ✅ |
| WITH TIES | ❌ | ✅ 13+ | ❌ | ✅ 12c+ | ✅ | ❌ | ✅ 4.0+ | ✅ | ❌ |
| TOP | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ✅ |
| ROWNUM | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| ROW_NUMBER() | ✅ 8.0+ | ✅ | ✅ 3.25+ | ✅ 8i+ | ✅ 2005+ | ✅ 10.2+ | ✅ 3.0+ | ✅ | ✅ |
| RANK() | ✅ 8.0+ | ✅ | ✅ 3.25+ | ✅ 8i+ | ✅ 2005+ | ✅ 10.2+ | ✅ 3.0+ | ✅ | ✅ |
| DENSE_RANK() | ✅ 8.0+ | ✅ | ✅ 3.25+ | ✅ 8i+ | ✅ 2005+ | ✅ 10.2+ | ✅ 3.0+ | ✅ | ✅ |
| QUALIFY | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| LATERAL / CROSS APPLY | ✅ 8.0.14+ | ✅ 9.3+ | ❌ | ✅ 12c+ | ✅ 2005+ | ✅ 10.6+ | ❌ | ✅ | ⚠️ |
| DISTINCT ON | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| KEEP (DENSE_RANK) | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| FETCH PERCENT | ❌ | ❌ | ❌ | ✅ 12c+ | ✅ | ❌ | ❌ | ❌ | ❌ |

### 大数据 / 分析引擎

| 特性 | BigQuery | Snowflake | MaxCompute | Hive | ClickHouse | StarRocks | Trino | Hologres | Doris | DuckDB | Spark | Flink |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| LIMIT / OFFSET | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| FETCH FIRST | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ | ❌ | ✅ | ✅ 3.4+ | ✅ 1.15+ |
| WITH TIES | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| ROW_NUMBER() | ✅ | ✅ | ✅ | ✅ | ✅ 21.1+ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| RANK() | ✅ | ✅ | ✅ | ✅ | ✅ 21.1+ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| DENSE_RANK() | ✅ | ✅ | ✅ | ✅ | ✅ 21.1+ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| QUALIFY | ✅ | ✅ | ❌ | ❌ | ❌ | ✅ 3.2+ | ❌ | ❌ | ❌ | ✅ | ✅ | ❌ |
| LIMIT BY | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| ARRAY_AGG + LIMIT | ✅ | ✅ | ❌ | ❌ | ✅ | ❌ | ✅ | ❌ | ❌ | ✅ | ✅ | ❌ |

### 云数据仓库

| 特性 | Redshift | Synapse | Databricks | Greenplum | Impala | Vertica | Teradata |
|---|---|---|---|---|---|---|---|
| LIMIT / OFFSET | ✅ | ❌ | ✅ | ✅ | ✅ | ✅ | ❌ |
| FETCH FIRST | ❌ | ✅ | ❌ | ✅ | ❌ | ✅ | ✅ |
| TOP | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ✅ |
| WITH TIES | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| ROW_NUMBER() | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| RANK() | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| DENSE_RANK() | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| QUALIFY | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ✅ |
| SAMPLE | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ |

### 分布式 / NewSQL

| 特性 | TiDB | OceanBase | CockroachDB | Spanner | YugabyteDB | PolarDB | openGauss | TDSQL | DamengDB | KingbaseES |
|---|---|---|---|---|---|---|---|---|---|---|
| LIMIT / OFFSET | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ⚠️ | ✅ |
| FETCH FIRST | ❌ | ✅ 4.0+ | ✅ | ❌ | ✅ | ❌ | ✅ | ❌ | ✅ | ✅ |
| ROW_NUMBER() | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| RANK() | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| DENSE_RANK() | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| LATERAL | ❌ | ⚠️ | ✅ | ❌ | ✅ | ❌ | ✅ | ❌ | ⚠️ | ✅ |

### 特殊用途

| 特性 | TimescaleDB | TDengine | ksqlDB | Materialize | H2 | Derby |
|---|---|---|---|---|---|---|
| LIMIT / OFFSET | ✅ | ✅ | ⚠️ | ✅ | ✅ | ❌ |
| FETCH FIRST | ✅ | ❌ | ❌ | ✅ | ✅ | ✅ 10.5+ |
| ROW_NUMBER() | ✅ | ❌ | ❌ | ✅ | ✅ | ✅ 10.4+ |
| RANK() | ✅ | ❌ | ❌ | ✅ | ✅ | ✅ 10.4+ |
| DENSE_RANK() | ✅ | ❌ | ❌ | ✅ | ✅ | ✅ 10.4+ |
| TOPK 聚合 | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ |
| DISTINCT ON | ✅ | ❌ | ❌ | ✅ | ❌ | ❌ |

## 关键差异

- **PostgreSQL** 独有 `DISTINCT ON` 语法，取每组第一行最为简洁
- **Oracle** 12c 之前只能用 `ROWNUM` 子查询实现 Top-N；独有 `KEEP (DENSE_RANK)` 聚合
- **SQL Server** 的 `TOP` 语法放在 `SELECT` 后面，支持 `WITH TIES` 和 `PERCENT`
- **ClickHouse** 独有 `LIMIT BY` 语法，可直接按分组取前 N 行，无需窗口函数
- **BigQuery / Snowflake / Databricks / Teradata / StarRocks** 支持 `QUALIFY` 子句，省去子查询嵌套
- **ksqlDB** 无窗口排名函数，仅能用 `TOPK` / `TOPKDISTINCT` 聚合函数做近似 Top-N
- **TDengine** 仅支持简单 `LIMIT`，不支持窗口排名函数
- **MySQL 5.7** 需用用户变量模拟 `ROW_NUMBER()`，8.0+ 支持标准窗口函数
- **LATERAL / CROSS APPLY** 在分组 Top-N 中配合索引性能最优，但并非所有方言支持
