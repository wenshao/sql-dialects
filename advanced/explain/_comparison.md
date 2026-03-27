# 执行计划 (EXPLAIN) — 方言对比

## 语法支持对比

### 传统 RDBMS

| 特性 | MySQL | PostgreSQL | SQLite | Oracle | SQL Server | MariaDB | Firebird | Db2 | SAP HANA |
|---|---|---|---|---|---|---|---|---|---|
| EXPLAIN | ✅ | ✅ | ✅ QUERY PLAN | ✅ EXPLAIN PLAN FOR | ❌ | ✅ | ❌ | ✅ | ✅ |
| EXPLAIN ANALYZE | ✅ 8.0.18+ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| ANALYZE 语句 | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ |
| 图形化执行计划 | ❌ | ❌ | ❌ | ❌ | ✅ SET SHOWPLAN | ❌ | ❌ | ❌ | ❌ |
| SET SHOWPLAN_XML | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ |
| SET SHOWPLAN_TEXT | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ |
| SET STATISTICS IO | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ |
| SET STATISTICS TIME | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ |
| FORMAT JSON | ✅ 5.6+ | ✅ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ |
| FORMAT TREE | ✅ 8.0.16+ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| FORMAT XML | ❌ | ✅ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ |
| FORMAT YAML | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| BUFFERS 选项 | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| DBMS_XPLAN | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| SET PLAN ON | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ |
| EXPLAIN PLAN TABLE | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ |
| 优化器跟踪 | ✅ OPTIMIZER_TRACE | ❌ | ❌ | ✅ 10046 Trace | ❌ | ✅ | ❌ | ❌ | ❌ |
| EXPLAIN DML | ✅ 5.6.3+ | ✅ | ❌ | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ |
| Hint 支持 | ✅ 8.0+ | ✅ pg_hint_plan | ❌ | ✅ 丰富 | ✅ 丰富 | ✅ | ❌ | ✅ | ✅ |
| SQL Monitor | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| PROFILE | ⚠️ 已废弃 | ❌ | ❌ | ❌ | ❌ | ⚠️ 已废弃 | ❌ | ❌ | ❌ |
| auto_explain | ❌ | ✅ 扩展 | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |

### 大数据 / 分析引擎

| 特性 | BigQuery | Snowflake | MaxCompute | Hive | ClickHouse | StarRocks | Trino | Hologres | Doris | DuckDB | Spark | Flink |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| EXPLAIN | ⚠️ UI/API | ✅ | ⚠️ COST SQL | ✅ | ✅ 20.6+ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| EXPLAIN ANALYZE | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ | ✅ | ✅ 2.0+ | ✅ | ❌ | ❌ |
| EXPLAIN EXTENDED | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ |
| EXPLAIN CODEGEN | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ |
| EXPLAIN PIPELINE | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| EXPLAIN SYNTAX | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| EXPLAIN GRAPH | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ |
| EXPLAIN COSTS | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ |
| FORMAT GRAPHVIZ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| Query Profile (UI) | ✅ | ✅ | ✅ Logview | ✅ Tez UI | ❌ | ✅ FE UI | ✅ Web UI | ✅ | ✅ FE UI | ❌ | ✅ Web UI | ✅ Web UI |
| Dry Run | ✅ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |

### 云数据仓库

| 特性 | Redshift | Synapse | Databricks | Greenplum | Impala | Vertica | Teradata |
|---|---|---|---|---|---|---|---|
| EXPLAIN | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| EXPLAIN ANALYZE | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ |
| EXPLAIN VERBOSE | ✅ | ❌ | ✅ | ✅ | ❌ | ✅ | ❌ |
| PROFILE 语句 | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ | ❌ |
| SUMMARY | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ |

### 分布式 / NewSQL

| 特性 | TiDB | OceanBase | CockroachDB | Spanner | YugabyteDB | PolarDB | openGauss | TDSQL | DamengDB | KingbaseES |
|---|---|---|---|---|---|---|---|---|---|---|
| EXPLAIN | ✅ | ✅ | ✅ | ⚠️ API/Console | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| EXPLAIN ANALYZE | ✅ | ❌ | ✅ | ❌ | ✅ | ✅ | ✅ | ❌ | ❌ | ✅ |
| EXPLAIN (DISTSQL) | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| EXPLAIN (DIST) | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| EXPLAIN PERFORMANCE | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ |

### 特殊用途

| 特性 | TimescaleDB | TDengine | ksqlDB | Materialize | H2 | Derby |
|---|---|---|---|---|---|---|
| EXPLAIN | ✅ | ✅ | ✅ 拓扑 | ✅ 多层次 | ✅ | ❌ |
| EXPLAIN ANALYZE | ✅ | ❌ | ❌ | ❌ | ✅ | ❌ |
| RUNTIMESTATISTICS | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ |
| XPLAIN 模式 | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ 10.5+ |

## 关键差异

- **MySQL 8.0.18+** 引入 EXPLAIN ANALYZE（实际执行并收集统计），FORMAT=TREE 展示迭代器模型
- **PostgreSQL** 提供最丰富的 EXPLAIN 选项组合（ANALYZE, BUFFERS, COSTS, TIMING, WAL, VERBOSE）
- **Oracle** 使用 EXPLAIN PLAN FOR + DBMS_XPLAN，Hint 系统最为完善
- **SQL Server** 不使用 EXPLAIN，而是 SET SHOWPLAN_XML/TEXT/ALL
- **SQLite** 使用 EXPLAIN QUERY PLAN，输出非常简洁
- **Derby** 没有 EXPLAIN 语句，需通过 SYSCS_UTIL 设置运行时统计
- **ClickHouse** 的 EXPLAIN PIPELINE 和 EXPLAIN SYNTAX 是独有功能
- **Spark** 的 EXPLAIN CODEGEN 显示 Tungsten 代码生成
- **MariaDB** 使用 ANALYZE 替代 MySQL 的 EXPLAIN ANALYZE
