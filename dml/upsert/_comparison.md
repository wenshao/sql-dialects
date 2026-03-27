# 合并写入 (UPSERT) — 方言对比

## 语法支持对比

### 传统 RDBMS

| 特性 | MySQL | PostgreSQL | SQLite | Oracle | SQL Server | MariaDB | Firebird | Db2 | SAP HANA |
|---|---|---|---|---|---|---|---|---|---|
| MERGE | ❌ | ✅ 15+ | ❌ | ✅ 9i+ | ✅ 2008+ | ❌ | ✅ 3.0+ | ✅ | ✅ |
| ON CONFLICT | ❌ | ✅ 9.5+ | ✅ 3.24+ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| ON DUPLICATE KEY | ✅ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ |
| REPLACE INTO | ✅ | ❌ | ✅ INSERT OR REPLACE | ❌ | ❌ | ✅ | ❌ | ❌ | ✅ UPSERT |
| INSERT IGNORE | ✅ | ❌ | ✅ INSERT OR IGNORE | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ |
| UPDATE OR INSERT | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ 2.1+ | ❌ | ❌ |
| MERGE + DELETE | ❌ | ❌ | ❌ | ✅ 10g+ | ✅ | ❌ | ✅ 4.0+ | ✅ | ✅ |
| RETURNING | ❌ | ✅ | ✅ | ❌ | ✅ OUTPUT | ✅ 10.5+ | ❌ | ❌ | ❌ |

### 大数据 / 分析引擎

| 特性 | BigQuery | Snowflake | MaxCompute | Hive | ClickHouse | StarRocks | Trino | Hologres | Doris | DuckDB | Spark | Flink |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| MERGE | ✅ | ✅ | ✅ 事务表 | ✅ ACID 2.2+ | ❌ | ❌ | ✅ 410+ | ❌ | ❌ | ❌ | ✅ Delta | ❌ |
| ON CONFLICT | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ✅ 0.9+ | ❌ | ❌ |
| 隐式 UPSERT | ❌ | ❌ | ❌ | ❌ | ✅ RMT | ✅ PK 模型 | ❌ | ❌ | ✅ UK 模型 | ❌ | ❌ | ✅ connector |
| INSERT OR REPLACE | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ |
| INSERT OVERWRITE | ❌ | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ |

### 云数据仓库

| 特性 | Redshift | Synapse | Databricks | Greenplum | Impala | Vertica | Teradata |
|---|---|---|---|---|---|---|---|
| MERGE | ✅ 2023+ | ⚠️ 专用池 | ✅ | ❌ | ⚠️ Kudu only | ✅ | ✅ |
| ON CONFLICT | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ |
| UPSERT 关键字 | ❌ | ❌ | ❌ | ❌ | ✅ Kudu | ❌ | ❌ |
| Staging 模式 | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |

### 分布式 / NewSQL

| 特性 | TiDB | OceanBase | CockroachDB | Spanner | YugabyteDB | PolarDB | openGauss | TDSQL | DamengDB | KingbaseES |
|---|---|---|---|---|---|---|---|---|---|---|
| MERGE | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ |
| ON CONFLICT | ❌ | ❌ | ✅ | ❌ | ✅ | ❌ | ✅ | ❌ | ❌ | ✅ |
| ON DUPLICATE KEY | ✅ | ✅ | ❌ | ❌ | ❌ | ✅ | ❌ | ✅ | ❌ | ❌ |
| REPLACE INTO | ✅ | ✅ | ❌ | ❌ | ❌ | ✅ | ❌ | ✅ | ❌ | ❌ |
| UPSERT 关键字 | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| INSERT OR UPDATE | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |

### 特殊用途

| 特性 | TimescaleDB | TDengine | ksqlDB | Materialize | H2 | Derby |
|---|---|---|---|---|---|---|
| MERGE | ✅ 15+ | ❌ | ❌ | ❌ | ✅ | ✅ 10.11+ |
| ON CONFLICT | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| 隐式 UPSERT | ❌ | ✅ 时间戳覆盖 | ✅ PK 覆盖 | ❌ | ✅ MERGE KEY | ❌ |

## 关键差异

- **MySQL 系**（MySQL, MariaDB, TiDB, OceanBase, PolarDB, TDSQL）使用 ON DUPLICATE KEY UPDATE
- **PostgreSQL 系**（PostgreSQL, CockroachDB, YugabyteDB, openGauss, KingbaseES, Hologres）使用 ON CONFLICT
- **SQL 标准 MERGE** 被 Oracle, SQL Server, Db2, Snowflake, BigQuery 等支持
- **CockroachDB** 独有 UPSERT 关键字（简化的主键冲突替换）
- **Spanner** 独有 INSERT OR UPDATE 语法
- **ClickHouse** 通过 ReplacingMergeTree 引擎实现最终一致的去重
- **Doris/StarRocks** 通过数据模型（Unique Key / Primary Key）实现隐式 UPSERT
- **TDengine** 相同时间戳插入自动覆盖
- **Synapse** 专用池支持 MERGE（serverless 不支持）；旧版用 DELETE + INSERT 或 Staging 模式
