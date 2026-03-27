# 分页 (Pagination) — 方言对比

## 语法支持对比

### 传统 RDBMS

| 特性 | MySQL | PostgreSQL | SQLite | Oracle | SQL Server | MariaDB | Firebird | Db2 | SAP HANA |
|---|---|---|---|---|---|---|---|---|---|
| LIMIT / OFFSET | ✅ | ✅ | ✅ | ❌ | ❌ | ✅ | ❌ | ❌ | ✅ |
| OFFSET / FETCH | ❌ | ✅ 8.4+ | ❌ | ✅ 12c+ | ✅ 2012+ | ✅ 10.6+ | ✅ 4.0+ | ✅ 11.1+ | ✅ |
| TOP | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ✅ |
| ROWNUM | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| FIRST / SKIP | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ |
| WITH TIES | ❌ | ❌ | ❌ | ✅ 12c+ | ❌ | ✅ 10.6+ | ✅ 4.0+ | ✅ | ❌ |
| ROW_NUMBER 分页 | ✅ 8.0+ | ✅ | ✅ 3.25+ | ✅ 8i+ | ✅ 2005+ | ✅ 10.2+ | ✅ 3.0+ | ✅ | ✅ |
| 游标分页 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| LIMIT offset, count | ✅ | ❌ | ✅ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ |

### 大数据 / 分析引擎

| 特性 | BigQuery | Snowflake | MaxCompute | Hive | ClickHouse | StarRocks | Trino | Hologres | Doris | DuckDB | Spark | Flink |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| LIMIT / OFFSET | ✅ | ✅ | ✅ 2.0+ | ✅ 2.0+ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ 3.4+ | ✅ 1.15+ |
| OFFSET / FETCH | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ | ❌ | ✅ | ✅ 3.4+ | ✅ 1.15+ |
| TOP | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| WITH TIES | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| ROW_NUMBER 分页 | ✅ | ✅ | ✅ | ✅ | ✅ 21.1+ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| 游标分页 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ⚠️ |
| QUALIFY | ❌ | ✅ | ❌ | ❌ | ❌ | ✅ 3.2+ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ |
| LIMIT BY | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| TABLESAMPLE | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ✅ | ✅ | ❌ |

### 云数据仓库

| 特性 | Redshift | Synapse | Databricks | Greenplum | Impala | Vertica | Teradata |
|---|---|---|---|---|---|---|---|
| LIMIT / OFFSET | ✅ | ❌ | ✅ | ✅ | ✅ | ✅ | ❌ |
| OFFSET / FETCH | ❌ | ✅ | ❌ | ✅ | ❌ | ✅ | ✅ |
| TOP | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ✅ |
| WITH TIES | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| ROW_NUMBER 分页 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| 游标分页 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| QUALIFY | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ✅ |

### 分布式 / NewSQL

| 特性 | TiDB | OceanBase | CockroachDB | Spanner | YugabyteDB | PolarDB | openGauss | TDSQL | DamengDB | KingbaseES |
|---|---|---|---|---|---|---|---|---|---|---|
| LIMIT / OFFSET | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ⚠️ | ✅ |
| OFFSET / FETCH | ❌ | ✅ 4.0+ | ✅ | ❌ | ✅ | ❌ | ✅ | ❌ | ✅ | ✅ |
| TOP | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ |
| ROWNUM | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ |
| ROW_NUMBER 分页 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| 游标分页 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |

### 特殊用途

| 特性 | TimescaleDB | TDengine | ksqlDB | Materialize | H2 | Derby |
|---|---|---|---|---|---|---|
| LIMIT / OFFSET | ✅ | ✅ | ⚠️ | ✅ | ✅ | ❌ |
| OFFSET / FETCH | ✅ | ❌ | ❌ | ✅ | ✅ | ✅ 10.5+ |
| WITH TIES | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ |
| SLIMIT / SOFFSET | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ |
| ROW_NUMBER 分页 | ✅ | ❌ | ❌ | ✅ | ✅ | ✅ 10.11+ |
| 游标分页 | ✅ | ❌ | ❌ | ✅ | ✅ | ✅ |

## 关键差异

- **Oracle 12c 之前**只能用 ROWNUM 子查询方式分页
- **SQL Server 2012 之前**只能用 TOP + ROW_NUMBER() 分页
- **ClickHouse** 独有 LIMIT BY 语法（分组级别分页）和 WITH TIES
- **TDengine** 独有 SLIMIT/SOFFSET 用于子表级别分页
- **ksqlDB** 仅在 Pull Query 中支持 LIMIT，不支持 OFFSET
- **Hive 2.0 之前**不支持 OFFSET，只能用窗口函数
- **大数据引擎**中大 OFFSET 性能普遍较差，推荐游标分页
- **Snowflake/Databricks/Teradata/StarRocks** 支持 QUALIFY 子句简化 ROW_NUMBER 分页
