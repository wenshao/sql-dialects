# 缓慢变化维度 (Slowly Changing Dimension) — 方言对比

## 语法支持对比

### 传统 RDBMS

| 特性 | MySQL | PostgreSQL | SQLite | Oracle | SQL Server | MariaDB | Firebird | Db2 | SAP HANA |
|---|---|---|---|---|---|---|---|---|---|
| MERGE 语句 | ❌ | ✅ 15+ | ❌ | ✅ | ✅ 2008+ | ❌ | ✅ 3.0+ | ✅ | ✅ |
| INSERT ON CONFLICT / ON DUPLICATE | ✅ ON DUPLICATE KEY | ✅ ON CONFLICT 9.5+ | ✅ ON CONFLICT 3.24+ | ❌ | ❌ | ✅ ON DUPLICATE KEY | ✅ UPDATE OR INSERT | ✅ | ❌ |
| 时态表 (System Versioned) | ❌ | ❌ | ❌ | ✅ Flashback | ✅ 2016+ | ✅ 10.3+ | ❌ | ✅ 10.1+ | ✅ |
| 触发器实现 SCD | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| UPDATE + INSERT 分步 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| UPDATE JOIN | ✅ | ✅ FROM | ❌ | ✅ 子查询 | ✅ FROM | ✅ | ❌ | ❌ | ✅ |
| CTE + DML | ✅ 8.0+ | ✅ | ✅ 3.35+ | ✅ | ✅ 2005+ | ✅ 10.2+ | ❌ | ✅ | ✅ |
| RETURNING / OUTPUT | ❌ | ✅ | ✅ 3.35+ | ⚠️ RETURNING 12c+ | ✅ OUTPUT | ❌ | ✅ | ❌ | ❌ |
| 生成列 / 虚拟列 | ✅ 5.7+ | ✅ 12+ | ❌ | ✅ 11g+ | ✅ 2017+ | ✅ 10.2+ | ❌ | ✅ | ✅ |

### 大数据 / 分析引擎

| 特性 | BigQuery | Snowflake | MaxCompute | Hive | ClickHouse | StarRocks | Trino | Hologres | Doris | DuckDB | Spark | Flink |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| MERGE 语句 | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ✅ 2.0+ | ❌ |
| INSERT OVERWRITE | ❌ | ❌ | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ |
| 时态表 / Time Travel | ✅ 7 天 | ✅ 90 天 | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ Delta Lake | ✅ 时态 JOIN |
| UPDATE + DELETE 支持 | ✅ DML | ✅ | ⚠️ | ⚠️ ACID 3.0+ | ✅ ALTER TABLE UPDATE | ⚠️ | ✅ | ⚠️ | ⚠️ | ✅ | ✅ Delta/Iceberg | ⚠️ |
| 分区覆盖方式 | ❌ | ❌ | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ |
| 主键模型 (UPSERT) | ❌ | ❌ | ❌ | ❌ | ✅ ReplacingMergeTree | ✅ | ❌ | ✅ | ✅ UNIQUE | ❌ | ❌ | ✅ |

### 云数据仓库

| 特性 | Redshift | Synapse | Databricks | Greenplum | Impala | Vertica | Teradata |
|---|---|---|---|---|---|---|---|
| MERGE 语句 | ✅ | ✅ | ✅ | ❌ | ❌ | ✅ | ✅ |
| 时态表 / Time Travel | ❌ | ✅ | ✅ Delta Lake | ❌ | ❌ | ❌ | ✅ |
| UPDATE + INSERT 分步 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| INSERT OVERWRITE | ❌ | ❌ | ✅ | ✅ | ✅ | ❌ | ❌ |
| 分区覆盖方式 | ❌ | ❌ | ✅ | ✅ | ✅ | ❌ | ❌ |

### 分布式 / NewSQL

| 特性 | TiDB | OceanBase | CockroachDB | Spanner | YugabyteDB | PolarDB | openGauss | TDSQL | DamengDB | KingbaseES |
|---|---|---|---|---|---|---|---|---|---|---|
| MERGE 语句 | ❌ | ✅ 4.0+ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ✅ | ✅ |
| INSERT ON CONFLICT / DUPLICATE | ✅ REPLACE / ON DUPLICATE | ✅ ON DUPLICATE / MERGE | ✅ ON CONFLICT | ✅ INSERT OR UPDATE | ✅ ON CONFLICT | ✅ ON DUPLICATE | ✅ ON CONFLICT | ✅ ON DUPLICATE | ✅ | ✅ ON CONFLICT |
| UPDATE + INSERT 分步 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| 触发器实现 SCD | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |

### 特殊用途

| 特性 | TimescaleDB | TDengine | ksqlDB | Materialize | H2 | Derby |
|---|---|---|---|---|---|---|
| MERGE 语句 | ✅ 15+ | ❌ | ❌ | ❌ | ✅ | ❌ |
| INSERT ON CONFLICT | ✅ | ❌ | ❌ | ❌ | ✅ | ❌ |
| 时态表 | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| 流式 SCD | ❌ | ⚠️ 时序覆盖 | ⚠️ 流表语义 | ✅ UPSERT 语义 | ❌ | ❌ |

## 关键差异

- **MERGE 语句**是实现 SCD 最优雅的方式，但 MySQL、MariaDB、ClickHouse、Hive 等不支持
- **SQL Server 2016+** 的系统版本时态表（System-Versioned Temporal Tables）可自动维护 SCD Type 2 历史
- **MariaDB 10.3+** 支持系统版本化表（System-Versioned Tables），功能类似 SQL Server 时态表
- **Oracle** 的 Flashback Query 可查询表的历史状态，适合审计场景
- **Snowflake** 的 Time Travel（最多 90 天）提供内置的历史数据查询能力
- **BigQuery** 提供 7 天的 Time Travel + 长期快照功能
- **Databricks / Spark** 通过 Delta Lake 支持 MERGE 和 Time Travel
- **MySQL** 没有 MERGE，SCD Type 2 需要分步执行 UPDATE + INSERT
- **Hive / MaxCompute** 通常用 INSERT OVERWRITE 分区的方式实现 SCD
- **ClickHouse** 的 `ReplacingMergeTree` 可做 SCD Type 1 的自动覆盖（后台合并）
- **ksqlDB / Materialize** 基于流处理语义，通过键值表实现最终一致的维度更新
- **大数据场景**中 SCD 通常结合调度工具（Airflow 等）按批次执行 UPDATE + INSERT
