# 子查询 (Subquery) — 方言对比

## 语法支持对比

### 传统 RDBMS

| 特性 | MySQL | PostgreSQL | SQLite | Oracle | SQL Server | MariaDB | Firebird | Db2 | SAP HANA |
|---|---|---|---|---|---|---|---|---|---|
| WHERE IN | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| EXISTS | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| ANY / ALL / SOME | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| 标量子查询 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| 关联子查询 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| FROM 子查询 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| LATERAL 子查询 | ✅ 8.0+ | ✅ 9.3+ | ❌ | ✅ 12c+ | ⚠️ | ✅ 10.6+ | ❌ | ✅ 9.1+ | ⚠️ |
| 多列 IN | ❌ | ✅ | ✅ 3.15+ | ✅ | ❌ | ❌ | ✅ | ✅ | ✅ |

### 大数据 / 分析引擎

| 特性 | BigQuery | Snowflake | MaxCompute | Hive | ClickHouse | StarRocks | Trino | Hologres | Doris | DuckDB | Spark | Flink |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| WHERE IN | ✅ | ✅ | ✅ | ✅ 0.13+ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| EXISTS | ✅ | ✅ | ✅ | ✅ 0.13+ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ 2.1+ | ✅ |
| ANY / ALL | ❌ | ✅ | ❌ | ❌ | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ |
| 关联子查询 | ✅ | ✅ | ✅ | ✅ 2.0+ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| LATERAL 子查询 | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ |
| GLOBAL IN | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |

### 云数据仓库

| 特性 | Redshift | Synapse | Databricks | Greenplum | Impala | Vertica | Teradata |
|---|---|---|---|---|---|---|---|
| WHERE IN | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| EXISTS | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| ANY / ALL | ✅ | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ |
| LATERAL 子查询 | ❌ | ⚠️ | ❌ | ✅ | ❌ | ✅ | ❌ |

### 分布式 / NewSQL

| 特性 | TiDB | OceanBase | CockroachDB | Spanner | YugabyteDB | PolarDB | openGauss | TDSQL | DamengDB | KingbaseES |
|---|---|---|---|---|---|---|---|---|---|---|
| WHERE IN | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| EXISTS | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| ANY / ALL | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| LATERAL 子查询 | ✅ | ✅ 4.0+ | ✅ | ❌ | ✅ | ✅ | ✅ | ❌ | ❌ | ✅ |

### 特殊用途

| 特性 | TimescaleDB | TDengine | ksqlDB | Materialize | H2 | Derby |
|---|---|---|---|---|---|---|
| WHERE IN | ✅ | ⚠️ | ❌ | ✅ | ✅ | ✅ |
| EXISTS | ✅ | ❌ | ❌ | ✅ | ✅ | ✅ |
| ANY / ALL | ✅ | ❌ | ❌ | ✅ | ✅ | ✅ |
| 关联子查询 | ✅ | ❌ | ❌ | ✅ | ✅ | ✅ |
| LATERAL 子查询 | ✅ | ❌ | ❌ | ✅ | ❌ | ❌ |

## 关键差异

- **ksqlDB** 完全不支持子查询，需用物化 TABLE + JOIN 替代
- **TDengine** 仅支持基本 FROM 子查询和有限的 IN 子查询
- **Hive** 0.13+ 才支持 IN/EXISTS 子查询，2.0+ 才支持关联子查询
- **ClickHouse** 独有 GLOBAL IN 语法（分布式环境中子查询只执行一次）
- **MySQL 5.7** 及之前版本 IN 子查询性能较差，优化器不会转为 JOIN
- **SQL Server** 用 CROSS APPLY / OUTER APPLY 替代 LATERAL
- **分布式数据库**中关联子查询可能因跨分片导致性能问题
