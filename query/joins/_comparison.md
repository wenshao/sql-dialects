# 连接 (Joins) — 方言对比

## 语法支持对比

### 传统 RDBMS

| 特性 | MySQL | PostgreSQL | SQLite | Oracle | SQL Server | MariaDB | Firebird | Db2 | SAP HANA |
|---|---|---|---|---|---|---|---|---|---|
| INNER JOIN | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| LEFT JOIN | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| RIGHT JOIN | ✅ | ✅ | ✅ 3.39+ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| FULL OUTER JOIN | ❌ | ✅ | ✅ 3.39+ | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ |
| CROSS JOIN | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| NATURAL JOIN | ✅ | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ | ✅ |
| LATERAL | ✅ 8.0.14+ | ✅ 9.3+ | ❌ | ✅ 12c+ | ⚠️ | ✅ 10.6+ | ❌ | ✅ 9.1+ | ⚠️ |
| CROSS/OUTER APPLY | ❌ | ❌ | ❌ | ❌ | ✅ 2005+ | ❌ | ❌ | ❌ | ✅ |
| USING | ✅ | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ | ✅ |

### 大数据 / 分析引擎

| 特性 | BigQuery | Snowflake | MaxCompute | Hive | ClickHouse | StarRocks | Trino | Hologres | Doris | DuckDB | Spark | Flink |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| INNER JOIN | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| LEFT JOIN | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| RIGHT JOIN | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| FULL OUTER JOIN | ✅ | ✅ | ✅ | ✅ 0.7+ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| CROSS JOIN | ✅ | ✅ | ✅ | ✅ 0.10+ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| NATURAL JOIN | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ | ❌ | ✅ | ✅ | ❌ |
| LATERAL | ❌ | ✅ | ⚠️ | ⚠️ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ |
| SEMI JOIN | ❌ | ❌ | ❌ | ⚠️ | ❌ | ✅ | ❌ | ❌ | ✅ | ❌ | ✅ | ✅ |
| ANTI JOIN | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ✅ | ❌ | ✅ | ✅ |
| ARRAY JOIN | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| UNNEST | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ | ❌ | ❌ | ❌ | ✅ |
| LATERAL VIEW | ❌ | ❌ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |

### 云数据仓库

| 特性 | Redshift | Synapse | Databricks | Greenplum | Impala | Vertica | Teradata |
|---|---|---|---|---|---|---|---|
| FULL OUTER JOIN | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| NATURAL JOIN | ✅ | ❌ | ✅ | ✅ | ❌ | ✅ | ❌ |
| LATERAL | ❌ | ❌ | ✅ 2023+ | ✅ | ❌ | ✅ | ❌ |
| CROSS/OUTER APPLY | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| SEMI JOIN | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ |

### 分布式 / NewSQL

| 特性 | TiDB | OceanBase | CockroachDB | Spanner | YugabyteDB | PolarDB | openGauss | TDSQL | DamengDB | KingbaseES |
|---|---|---|---|---|---|---|---|---|---|---|
| FULL OUTER JOIN | ❌ | ⚠️ | ✅ | ✅ | ✅ | ❌ | ✅ | ❌ | ✅ | ✅ |
| NATURAL JOIN | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| LATERAL | ✅ | ✅ 4.0+ | ✅ | ❌ | ✅ | ✅ | ✅ | ❌ | ❌ | ✅ |

### 特殊用途

| 特性 | TimescaleDB | TDengine | ksqlDB | Materialize | H2 | Derby |
|---|---|---|---|---|---|---|
| INNER JOIN | ✅ | ⚠️ | ✅ | ✅ | ✅ | ✅ |
| LEFT JOIN | ✅ | ❌ | ✅ | ✅ | ✅ | ✅ |
| RIGHT JOIN | ✅ | ❌ | ❌ | ✅ | ✅ | ✅ |
| FULL OUTER JOIN | ✅ | ❌ | ❌ | ✅ | ❌ | ❌ |
| CROSS JOIN | ✅ | ❌ | ❌ | ✅ | ✅ | ✅ |
| LATERAL | ✅ | ❌ | ❌ | ✅ | ❌ | ❌ |

## 关键差异

- **MySQL/MariaDB/TiDB/PolarDB/TDSQL** 不支持 FULL OUTER JOIN，需用 UNION 模拟
- **SQLite 3.39.0+** 才支持 RIGHT JOIN 和 FULL OUTER JOIN
- **SQL Server** 用 CROSS APPLY / OUTER APPLY 替代 LATERAL
- **ClickHouse** 独有 ARRAY JOIN 语法展开数组列
- **Doris/StarRocks/Impala/Spark/Flink** 支持显式 SEMI JOIN / ANTI JOIN 语法
- **TDengine** JOIN 功能极为有限，仅支持子表间基于时间戳的等值 JOIN
- **ksqlDB** 仅支持 Stream-Stream 和 Stream-Table 的 INNER/LEFT JOIN
- **Hive/MaxCompute** 使用 LATERAL VIEW EXPLODE 展开数组，其他引擎多用 UNNEST
