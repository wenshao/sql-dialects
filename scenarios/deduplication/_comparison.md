# 数据去重 (Deduplication) — 方言对比

## 语法支持对比

### 传统 RDBMS

| 特性 | MySQL | PostgreSQL | SQLite | Oracle | SQL Server | MariaDB | Firebird | Db2 | SAP HANA |
|---|---|---|---|---|---|---|---|---|---|
| ROW_NUMBER() 去重 | ✅ 8.0+ | ✅ | ✅ 3.25+ | ✅ | ✅ 2005+ | ✅ 10.2+ | ✅ 3.0+ | ✅ | ✅ |
| DISTINCT ON | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| DELETE JOIN / USING | ✅ | ✅ | ❌ | ❌ | ✅ | ✅ | ❌ | ❌ | ❌ |
| ctid / ROWID 去重 | ❌ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ✅ | ❌ |
| MERGE 去重 | ❌ | ✅ 15+ | ❌ | ✅ | ✅ 2008+ | ❌ | ❌ | ✅ | ✅ |
| CTE + DELETE | ✅ 8.0+ | ✅ | ✅ 3.35+ | ✅ | ✅ 2005+ | ✅ 10.2+ | ❌ | ✅ | ✅ |
| INSERT IGNORE | ✅ | ❌ | ✅ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ |
| ON CONFLICT / ON DUPLICATE | ✅ | ✅ 9.5+ | ✅ 3.24+ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ |
| REPLACE INTO | ✅ | ❌ | ✅ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ |
| 近似去重计数 | ❌ | ⚠️ hll 扩展 | ❌ | ✅ APPROX_COUNT_DISTINCT | ⚠️ | ❌ | ❌ | ❌ | ✅ |

### 大数据 / 分析引擎

| 特性 | BigQuery | Snowflake | MaxCompute | Hive | ClickHouse | StarRocks | Trino | Hologres | Doris | DuckDB | Spark | Flink |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ROW_NUMBER() 去重 | ✅ | ✅ | ✅ | ✅ | ✅ 21.1+ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| QUALIFY 简化去重 | ✅ | ✅ | ❌ | ❌ | ❌ | ✅ 3.2+ | ❌ | ❌ | ❌ | ✅ | ✅ | ❌ |
| MERGE | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ✅ 2.0+ | ❌ |
| 引擎级去重 | ❌ | ❌ | ❌ | ❌ | ✅ ReplacingMergeTree | ✅ 主键模型 | ❌ | ✅ 行存主键 | ✅ UNIQUE 模型 | ❌ | ❌ | ⚠️ |
| APPROX_COUNT_DISTINCT | ✅ | ✅ | ✅ | ✅ | ✅ uniq/uniqExact | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| ARRAY_AGG 去重 | ✅ | ✅ | ❌ | ❌ | ✅ | ❌ | ✅ | ❌ | ❌ | ✅ | ✅ | ❌ |

### 云数据仓库

| 特性 | Redshift | Synapse | Databricks | Greenplum | Impala | Vertica | Teradata |
|---|---|---|---|---|---|---|---|
| ROW_NUMBER() 去重 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| QUALIFY 简化去重 | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ✅ |
| MERGE | ✅ | ✅ | ✅ | ❌ | ❌ | ✅ | ✅ |
| DELETE + 子查询 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| APPROX_COUNT_DISTINCT | ✅ | ❌ | ✅ | ❌ | ✅ | ✅ | ❌ |

### 分布式 / NewSQL

| 特性 | TiDB | OceanBase | CockroachDB | Spanner | YugabyteDB | PolarDB | openGauss | TDSQL | DamengDB | KingbaseES |
|---|---|---|---|---|---|---|---|---|---|---|
| ROW_NUMBER() 去重 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| MERGE | ❌ | ✅ 4.0+ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ✅ | ✅ |
| DELETE JOIN / USING | ✅ | ✅ | ❌ | ❌ | ✅ | ✅ | ✅ | ✅ | ⚠️ | ✅ |
| INSERT ON CONFLICT | ❌ | ⚠️ | ✅ | ❌ | ✅ | ❌ | ✅ | ❌ | ❌ | ✅ |
| REPLACE INTO | ✅ | ✅ | ❌ | ❌ | ❌ | ✅ | ❌ | ✅ | ❌ | ❌ |

### 特殊用途

| 特性 | TimescaleDB | TDengine | ksqlDB | Materialize | H2 | Derby |
|---|---|---|---|---|---|---|
| ROW_NUMBER() 去重 | ✅ | ❌ | ❌ | ✅ | ✅ | ✅ 10.4+ |
| DISTINCT ON | ✅ | ❌ | ❌ | ✅ | ❌ | ❌ |
| 引擎级去重 | ❌ | ⚠️ 时序覆盖 | ⚠️ 键值语义 | ✅ UPSERT 语义 | ❌ | ❌ |
| MERGE | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ |

## 关键差异

- **PostgreSQL** 的 `DISTINCT ON` 是最简洁的取每组一行方式，其他方言无此语法
- **PostgreSQL** 可用物理行 ID `ctid` 做无主键表的去重；**Oracle** 可用 `ROWID`
- **MySQL** 的 `DELETE JOIN` 是其独有的高效去重删除方式
- **ClickHouse** 的 `ReplacingMergeTree` 引擎在后台自动合并去重，非实时
- **StarRocks / Doris** 的主键模型自动保证唯一性，类似 UPSERT 语义
- **BigQuery / Snowflake / Databricks / Teradata** 支持 `QUALIFY`，去重查询无需嵌套子查询
- **ksqlDB** 基于流处理语义，通过键值表实现最终一致的去重
- **TDengine** 作为时序数据库，同一时间戳的新数据会覆盖旧数据
- **大数据场景** 推荐使用 `ROW_NUMBER() + QUALIFY` 或引擎级去重，避免 DELETE 操作
