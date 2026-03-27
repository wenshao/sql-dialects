# 行列转换 (PIVOT / UNPIVOT) — 方言对比

## 语法支持对比

### 传统 RDBMS

| 特性 | MySQL | PostgreSQL | SQLite | Oracle | SQL Server | MariaDB | Firebird | Db2 | SAP HANA |
|---|---|---|---|---|---|---|---|---|---|
| 原生 PIVOT | ❌ | ❌ | ❌ | ✅ 11g+ | ✅ 2005+ | ❌ | ❌ | ⚠️ | ❌ |
| 原生 UNPIVOT | ❌ | ❌ | ❌ | ✅ 11g+ | ✅ 2005+ | ❌ | ❌ | ⚠️ | ❌ |
| CASE WHEN + GROUP BY | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| FILTER 子句 | ❌ | ✅ 9.4+ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| crosstab 函数 | ❌ | ✅ tablefunc | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| DECODE | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ✅ | ❌ |
| UNION ALL UNPIVOT | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| LATERAL + VALUES | ❌ | ✅ 9.3+ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| CROSS APPLY + VALUES | ❌ | ❌ | ❌ | ❌ | ✅ 2008+ | ❌ | ❌ | ❌ | ❌ |
| unnest + array | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| json_each UNPIVOT | ❌ | ❌ | ✅ 3.38.0+ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| PIVOT 多聚合函数 | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| PIVOT XML | ❌ | ❌ | ❌ | ✅ 11g+ | ❌ | ❌ | ❌ | ❌ | ❌ |
| UNPIVOT INCLUDE NULLS | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| 动态 PIVOT | ⚠️ Prepared Statement | ⚠️ PL/pgSQL | ❌ | ⚠️ PL/SQL | ✅ sp_executesql | ⚠️ Prepared Statement | ⚠️ | ⚠️ | ⚠️ |
| IF() 函数替代 | ✅ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ |

### 大数据 / 分析引擎

| 特性 | BigQuery | Snowflake | MaxCompute | Hive | ClickHouse | StarRocks | Trino | Hologres | Doris | DuckDB | Spark | Flink |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 原生 PIVOT | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ 3.4+ | ❌ |
| 原生 UNPIVOT | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ 3.4+ | ❌ |
| CASE WHEN + GROUP BY | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| 动态 PIVOT | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |

### 云数据仓库

| 特性 | Redshift | Synapse | Databricks | Greenplum | Impala | Vertica | Teradata |
|---|---|---|---|---|---|---|---|
| 原生 PIVOT | ❌ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ |
| 原生 UNPIVOT | ❌ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ |
| CASE WHEN + GROUP BY | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| CROSS APPLY + VALUES | ❌ | ✅ | ❌ | ✅ | ❌ | ❌ | ❌ |

### 分布式 / NewSQL

| 特性 | TiDB | OceanBase | CockroachDB | Spanner | YugabyteDB | PolarDB | openGauss | TDSQL | DamengDB | KingbaseES |
|---|---|---|---|---|---|---|---|---|---|---|
| 原生 PIVOT | ❌ | ⚠️ Oracle 模式 | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ |
| 原生 UNPIVOT | ❌ | ⚠️ Oracle 模式 | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ |
| CASE WHEN + GROUP BY | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |

### 特殊用途

| 特性 | TimescaleDB | TDengine | ksqlDB | Materialize | H2 | Derby |
|---|---|---|---|---|---|---|
| 原生 PIVOT | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| CASE WHEN + GROUP BY | ✅ | ⚠️ | ❌ | ✅ | ✅ | ✅ |
| LATERAL + VALUES | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |

## 关键差异

- **Oracle 11g+** 和 **SQL Server 2005+** 是最早支持原生 PIVOT/UNPIVOT 的数据库
- **Oracle** 独有 PIVOT XML 支持动态列，以及多聚合函数 PIVOT
- **SQL Server** PIVOT 只支持一个聚合函数（不像 Oracle 支持多个）
- **PostgreSQL** 使用 FILTER 子句（9.4+）比 CASE WHEN 更简洁高效
- **PostgreSQL** 的 crosstab() 需要 tablefunc 扩展
- **MySQL/MariaDB** 全部使用 CASE WHEN + GROUP BY 模拟
- **SQLite 3.38.0+** 可用 json_each 实现 UNPIVOT
- **BigQuery/Snowflake/DuckDB/Spark 3.4+** 支持原生 PIVOT/UNPIVOT
- 动态 PIVOT 在所有数据库中都需要动态 SQL 或应用层拼接
