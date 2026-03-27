# 触发器 (Triggers) — 方言对比

## 语法支持对比

### 传统 RDBMS

| 特性 | MySQL | PostgreSQL | SQLite | Oracle | SQL Server | MariaDB | Firebird | Db2 | SAP HANA |
|---|---|---|---|---|---|---|---|---|---|
| BEFORE INSERT | ✅ | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ | ✅ |
| AFTER INSERT | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| BEFORE UPDATE | ✅ | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ | ✅ |
| AFTER UPDATE | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| BEFORE DELETE | ✅ | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ | ✅ |
| AFTER DELETE | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| INSTEAD OF | ❌ | ✅ 视图 | ✅ 视图 | ✅ 视图 | ✅ | ❌ | ❌ | ✅ | ❌ |
| FOR EACH ROW | ✅ | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ | ✅ |
| FOR EACH STATEMENT | ❌ | ✅ | ❌ | ✅ | ✅ 默认 | ❌ | ❌ | ✅ | ❌ |
| WHEN 条件 | ❌ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| 多事件触发器 | ❌ | ✅ INSERT OR UPDATE | ❌ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ |
| CREATE OR REPLACE | ❌ | ✅ | ❌ | ✅ | ❌ | ❌ | ✅ | ✅ | ✅ |
| 触发器函数 | ❌ | ✅ 需函数 | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |

### 大数据 / 分析引擎

| 特性 | BigQuery | Snowflake | MaxCompute | Hive | ClickHouse | StarRocks | Trino | Hologres | Doris | DuckDB | Spark | Flink |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 传统触发器 | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| 物化视图替代 | ✅ | ✅ Stream+Task | ✅ | ✅ | ✅ MV | ✅ MV | ❌ | ❌ | ❌ | ❌ | ✅ Streaming | ✅ |
| CDC/流式替代 | ❌ | ✅ Stream | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ Binlog | ❌ | ❌ | ✅ | ✅ |

### 云数据仓库

| 特性 | Redshift | Synapse | Databricks | Greenplum | Impala | Vertica | Teradata |
|---|---|---|---|---|---|---|---|
| 传统触发器 | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ✅ |
| 替代方案 | SP+ETL | SP+ADF | DLT/Streaming | 继承 PG | ETL | Access Policy | ✅ 完整支持 |

### 分布式 / NewSQL

| 特性 | TiDB | OceanBase | CockroachDB | Spanner | YugabyteDB | PolarDB | openGauss | TDSQL | DamengDB | KingbaseES |
|---|---|---|---|---|---|---|---|---|---|---|
| 传统触发器 | ❌ | ✅ | ⚠️ | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| BEFORE | ❌ | ✅ | ⚠️ | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| AFTER | ❌ | ✅ | ⚠️ | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |

### 特殊用途

| 特性 | TimescaleDB | TDengine | ksqlDB | Materialize | H2 | Derby |
|---|---|---|---|---|---|---|
| 传统触发器 | ✅ | ❌ | ❌ | ❌ | ✅ Java | ✅ |
| 流式替代 | ✅ Continuous Agg | ✅ Stream | ✅ 持久查询 | ✅ MV | ❌ | ❌ |

## 关键差异

- **SQL Server** 不支持 BEFORE 触发器，只有 AFTER 和 INSTEAD OF
- **TiDB** 完全不支持触发器，需用 DEFAULT/CHECK/Generated Column 替代
- **大数据引擎**（BigQuery/Snowflake/Hive/ClickHouse/Spark/Flink）均不支持触发器
- **Snowflake** 用 Stream + Task 组合替代触发器
- **PostgreSQL** 触发器必须先创建触发器函数（RETURNS TRIGGER）
- **H2** 触发器通过 Java 类实现
- **Derby** BEFORE 触发器不能修改 NEW 值，仅用于验证
- **Materialize** 物化视图的增量维护本身具有触发器效果
- **ksqlDB** 持久查询天然具有事件驱动（触发器）语义
