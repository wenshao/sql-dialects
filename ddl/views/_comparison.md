# 视图 (Views) — 方言对比

## 语法支持对比

### 传统 RDBMS

| 特性 | MySQL | PostgreSQL | SQLite | Oracle | SQL Server | MariaDB | Firebird | Db2 | SAP HANA |
|---|---|---|---|---|---|---|---|---|---|
| CREATE VIEW | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| CREATE OR REPLACE VIEW | ✅ | ✅ | ❌ | ✅ | ❌ | ✅ | ❌ | ✅ 11.1+ | ✅ |
| CREATE OR ALTER VIEW | ❌ | ❌ | ❌ | ❌ | ✅ 2016 SP1+ | ❌ | ✅ 2.5+ | ❌ | ❌ |
| IF NOT EXISTS | ❌ | ❌ | ✅ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ |
| 临时视图 | ❌ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| 递归视图 | ❌ | ✅ 9.3+ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| 可更新视图 | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| WITH CHECK OPTION | ✅ | ✅ 9.4+ | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| INSTEAD OF 触发器 | ❌ | ✅ | ✅ | ✅ | ✅ | ❌ | ✅ | ❌ | ❌ |
| 物化视图 | ❌ | ✅ 9.3+ | ❌ | ✅ | ⚠️ 索引视图 | ❌ | ❌ | ⚠️ MQT | ❌ |
| 物化视图自动刷新 | ❌ | ❌ | ❌ | ✅ ON COMMIT | ✅ 自动维护 | ❌ | ❌ | ✅ REFRESH IMMEDIATE | ❌ |
| 物化视图并发刷新 | ❌ | ✅ 9.4+ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| 查询重写 | ❌ | ❌ | ❌ | ✅ | ✅ Enterprise | ❌ | ❌ | ✅ | ❌ |
| ALGORITHM 选项 | ✅ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ |
| SQL SECURITY | ✅ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ |
| Security Barrier | ❌ | ✅ 9.2+ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| SCHEMABINDING | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ |
| ENCRYPTION | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ |
| DROP VIEW IF EXISTS | ✅ | ✅ | ✅ | ❌ | ✅ 2016+ | ✅ | ❌ | ❌ | ❌ |
| DROP CASCADE | ❌ | ✅ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ✅ |

### 大数据 / 分析引擎

| 特性 | BigQuery | Snowflake | MaxCompute | Hive | ClickHouse | StarRocks | Trino | Hologres | Doris | DuckDB | Spark | Flink |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| CREATE VIEW | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| CREATE OR REPLACE | ✅ | ✅ | ✅ | ❌ | ✅ | ⚠️ 3.0+ | ✅ | ✅ | ✅ 2.0+ | ✅ | ✅ | ⚠️ 1.17+ |
| IF NOT EXISTS | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ |
| 临时视图 | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ | ✅ |
| 全局临时视图 | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ |
| 可更新视图 | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| 物化视图 | ✅ | ✅ Enterprise | ✅ | ✅ 3.0+ | ✅ | ✅ | ⚠️ Connector 依赖 | ❌ | ✅ | ❌ | ❌ | ❌ |
| 物化视图自动刷新 | ✅ | ✅ | ❌ | ❌ | ✅ 增量 | ✅ 同步/异步 | ❌ | ❌ | ✅ 异步 2.1+ | ❌ | ❌ | ❌ |
| 查询重写 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ |
| Secure View | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| 流式视图 | ❌ | ❌ | ❌ | ❌ | ⚠️ LIVE VIEW | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ |

### 云数据仓库

| 特性 | Redshift | Synapse | Databricks | Greenplum | Impala | Vertica | Teradata |
|---|---|---|---|---|---|---|---|
| CREATE VIEW | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| CREATE OR REPLACE | ✅ | ❌ | ✅ | ✅ | ❌ | ✅ | ⚠️ REPLACE VIEW |
| IF NOT EXISTS | ❌ | ❌ | ✅ | ❌ | ✅ | ✅ | ❌ |
| 临时视图 | ❌ | ❌ | ✅ | ✅ | ❌ | ❌ | ❌ |
| 可更新视图 | ❌ | ❌ | ❌ | ✅ 7+ | ❌ | ❌ | ✅ |
| WITH CHECK OPTION | ❌ | ❌ | ❌ | ✅ 7+ | ❌ | ❌ | ✅ |
| 物化视图 | ✅ | ✅ Dedicated Pool | ✅ Unity Catalog | ✅ | ❌ | ⚠️ Projection | ⚠️ Join Index |
| 物化视图自动刷新 | ✅ AUTO REFRESH | ✅ 自动维护 | ⚠️ DLT 管道 | ❌ | ❌ | ✅ 自动维护 | ✅ 自动维护 |
| 查询重写 | ✅ | ✅ | ❌ | ❌ | ❌ | ✅ | ✅ |
| Late-binding View | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |

### 分布式 / NewSQL

| 特性 | TiDB | OceanBase | CockroachDB | Spanner | YugabyteDB | PolarDB | openGauss | TDSQL | DamengDB | KingbaseES |
|---|---|---|---|---|---|---|---|---|---|---|
| CREATE VIEW | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| CREATE OR REPLACE | ✅ | ✅ | ✅ 22.2+ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| 可更新视图 | ✅ | ✅ | ❌ | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| WITH CHECK OPTION | ✅ 5.0+ | ✅ | ❌ | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| 物化视图 | ❌ | ⚠️ Oracle 模式 | ✅ 21.2+ | ❌ | ✅ | ⚠️ PG 模式 | ✅ | ❌ | ✅ | ✅ |
| 增量物化视图 | ❌ | ❌ | ✅ 22.1+ | ❌ | ✅ | ❌ | ✅ | ❌ | ✅ | ❌ |

### 特殊用途

| 特性 | TimescaleDB | TDengine | ksqlDB | Materialize | H2 | Derby |
|---|---|---|---|---|---|---|
| CREATE VIEW | ✅ | ✅ 3.2.1+ | ❌ | ✅ | ✅ | ✅ |
| CREATE OR REPLACE | ✅ | ❌ | ❌ | ✅ | ✅ | ❌ |
| 可更新视图 | ✅ | ❌ | ❌ | ❌ | ✅ | ✅ |
| WITH CHECK OPTION | ✅ | ❌ | ❌ | ❌ | ✅ | ✅ |
| 物化视图 | ✅ + 连续聚合 | ❌ | ⚠️ TABLE AS SELECT | ✅ 增量 | ❌ | ❌ |
| 自动刷新 | ✅ 策略驱动 | ❌ | ✅ 持续更新 | ✅ 自动增量 | ❌ | ❌ |
| 实时聚合 | ✅ | ⚠️ 流计算 | ✅ Push Query | ✅ SUBSCRIBE | ❌ | ❌ |

## 关键差异

- **Oracle** 物化视图功能最丰富（快速刷新、ON COMMIT、查询重写、物化视图日志）
- **SQL Server** 使用索引视图（Indexed View）代替物化视图，需要 SCHEMABINDING 和 COUNT_BIG
- **DB2** 使用 MQT（Materialized Query Table）而非标准 MATERIALIZED VIEW 语法
- **Teradata** 使用 Join Index 代替物化视图，支持多表 JOIN
- **Vertica** 使用 Projection（投影）代替物化视图，自动维护
- **MySQL/MariaDB** 不支持物化视图，使用 EVENT + 表模拟
- **SQLite** 视图功能最精简：不支持可更新视图、物化视图、WITH CHECK OPTION
- **TimescaleDB** 的连续聚合（Continuous Aggregate）结合了物化视图和实时聚合
- **ksqlDB** 没有传统视图，使用 STREAM/TABLE AS SELECT 实现流式物化
- **Materialize** 专为增量计算物化视图设计，自动毫秒级更新
- **Snowflake/BigQuery** 的物化视图仅支持单表查询（不支持 JOIN）
