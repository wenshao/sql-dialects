# EXPLAIN 输出格式对比 (EXPLAIN Output Formats)

执行计划的"内容"决定了优化器有多聪明，而执行计划的"格式"决定了 DBA 工具链能走多远——同一份计划，纯文本能让人读，JSON 能让程序解析，GRAPHVIZ 能让架构师在白板上画拓扑，XML 能让企业 BI 报告批量比对。本文聚焦 EXPLAIN 的**输出格式**变体（TEXT / JSON / XML / YAML / GRAPHVIZ / Binary）以及与之配套的修饰符（ANALYZE / BUFFERS / TIMING / VERBOSE / SETTINGS / WAL）。如需了解 EXPLAIN 本身的语义、节点类型、代价模型，请参阅同目录下的 `explain-execution-plan.md`。

## 为什么 EXPLAIN 输出格式如此重要

EXPLAIN 在 1980 年代诞生时，输出是给 DBA 用 `lpr` 打印出来贴在墙上的一张表格。今天的 EXPLAIN 输出却需要被五种角色同时消费：

1. **DBA 与开发者**：希望直接在终端 `psql` / `sqlplus` / `mysql` 中读到对齐的纯文本树。
2. **可视化工具**：pgAdmin、DBeaver、SSMS、JetBrains DataGrip、Dalibo PEV、explain.depesz.com 需要结构化数据（通常是 JSON 或 XML）来渲染气泡图、热力图。
3. **APM 与可观测性平台**：Datadog Database Monitoring、SolarWinds DPA、Percona PMM 周期性抓取慢 SQL 的执行计划，要求机读格式以做差异比对。
4. **AI 优化建议系统**：从 Oracle SQL Tuning Advisor 到现代 LLM 调优工具，都需要把计划喂给模型，结构化越好提示越紧凑。
5. **CI/CD 回归基线**：把"昨天的计划 JSON"和"今天的计划 JSON"diff，是发现 plan regression 最廉价的手段。

由于 SQL 标准从未规范 EXPLAIN，每家数据库都自创了语法、关键字与序列化协议，工具链生态因此被强烈地"按方言切片"。理解各引擎能输出什么格式，是写跨数据库工具的第一步。

## SQL 标准的态度：完全不规定

ISO/IEC 9075 系列标准（SQL:1992 至 SQL:2023）从未定义 `EXPLAIN`、`EXPLAIN PLAN` 或任何执行计划的关键字。标准认为执行计划属于实现细节（implementation defined），只在描述游标可优化性、约束传播时偶尔提及"the implementation may choose..."这样的表述。

因此本文涉及的全部语法都是各厂商私有扩展，差异巨大：

| 维度 | 差异举例 |
|------|---------|
| 关键字 | `EXPLAIN` (PostgreSQL/MySQL) vs `EXPLAIN PLAN FOR` (Oracle) vs `SET SHOWPLAN_XML ON` (SQL Server) |
| 修饰符位置 | `EXPLAIN (FORMAT JSON, ANALYZE)` (PG) vs `EXPLAIN FORMAT=JSON` (MySQL) vs `EXPLAIN ANALYZE` (前置/后置) |
| 输出载体 | 直接 SELECT 返回 vs 写入 PLAN_TABLE vs 写入诊断目录 (DB2 db2exfmt) |
| 格式枚举 | TEXT / JSON / XML / YAML / GRAPHVIZ / DOT / TABULAR / FORMATTED / TREE / EXTENDED / CODEGEN |

## 支持矩阵（综合）

下面的矩阵覆盖 50 个数据库引擎，按格式与修饰符能力分别列出。表格中"是"表示原生支持，"--"表示不支持或需要外部工具。版本号给出该能力首次进入 GA 的版本（最佳估计）。

### 1. TEXT / 表格（默认）格式

| 引擎 | 关键字 | 默认形式 | 备注 |
|------|--------|---------|------|
| PostgreSQL | `EXPLAIN` | 树形文本 | 9.0+ `FORMAT TEXT` 显式可选 |
| MySQL | `EXPLAIN` | 表格 | `FORMAT=TRADITIONAL` 别名 |
| MariaDB | `EXPLAIN` | 表格 | 兼容 MySQL 5.x 行为 |
| SQLite | `EXPLAIN QUERY PLAN` | 树形文本 | 字节码细节用 `EXPLAIN` |
| Oracle | `EXPLAIN PLAN FOR` + `DBMS_XPLAN.DISPLAY` | 表格 | 9i+ |
| SQL Server | `SET SHOWPLAN_TEXT ON` | 缩进文本 | 2000+，已不推荐 |
| DB2 | `EXPLAIN PLAN FOR` + `db2exfmt` | 文本报告 | LUW/z/OS 通用 |
| Snowflake | `EXPLAIN USING TEXT` | 缩进文本 | 默认 TABULAR |
| BigQuery | UI / Job stats | 文本/JSON | 无独立 EXPLAIN 关键字 |
| Redshift | `EXPLAIN` | 树形文本 | 派生自 PostgreSQL |
| DuckDB | `EXPLAIN` | 树形 ASCII art | 0.2+ |
| ClickHouse | `EXPLAIN PLAN` | 缩进文本 | 20.6+ |
| Trino | `EXPLAIN (TYPE ..., FORMAT TEXT)` | 树形文本 | 默认 TEXT |
| Presto | `EXPLAIN` | 树形文本 | 同 Trino 早期 |
| Spark SQL | `EXPLAIN` | 物理计划文本 | 默认 simple |
| Hive | `EXPLAIN` | 阶段树文本 | 0.10+ |
| Flink SQL | `EXPLAIN PLAN FOR` | 多段文本 | 1.11+ |
| Databricks | `EXPLAIN` | Spark 物理计划 | 继承 Spark |
| Teradata | `EXPLAIN` | 多行报告 | V2R5+ |
| Greenplum | `EXPLAIN` | 树形文本 | 派生自 PostgreSQL |
| CockroachDB | `EXPLAIN` | 树形表格 | 1.0+ |
| TiDB | `EXPLAIN` | 表格 | 兼容 MySQL |
| OceanBase | `EXPLAIN` | 表格 + 算子树 | 兼容 MySQL/Oracle 双模式 |
| YugabyteDB | `EXPLAIN` | 文本（PG 兼容） | 派生自 PostgreSQL |
| SingleStore | `EXPLAIN` / `PROFILE` | 文本 | MemSQL 时代起 |
| Vertica | `EXPLAIN` | 树形文本 | 早期版本起 |
| Impala | `EXPLAIN` | 文本 | 1.0+ |
| StarRocks | `EXPLAIN` | 算子树文本 | 1.0+ |
| Doris | `EXPLAIN` | 算子树文本 | 0.9+ |
| MonetDB | `EXPLAIN` / `PLAN` | MAL 程序文本 | 早期起 |
| CrateDB | `EXPLAIN` | 文本 | 0.55+ |
| TimescaleDB | `EXPLAIN` | 继承 PG | -- |
| QuestDB | `EXPLAIN` | 文本 | 7.0+ |
| Exasol | `PROFILE` | 表格 | 6.0+ |
| SAP HANA | `EXPLAIN PLAN` + PLAN_TABLE | 表格 | 1.0 SP12+ |
| Informix | `SET EXPLAIN ON` | 文本文件 | 长期支持 |
| Firebird | `SET PLAN ON` | 文本 | 1.0+ |
| H2 | `EXPLAIN` | 文本 | 1.x+ |
| HSQLDB | `EXPLAIN PLAN FOR` | 文本 | 2.0+ |
| Derby | `CALL SYSCS_UTIL.SYSCS_SET_RUNTIMESTATISTICS(1)` | 文本 | 间接 |
| Amazon Athena | `EXPLAIN` | 继承 Trino | 引擎 v2+ |
| Azure Synapse | `EXPLAIN` | XML/文本 | -- |
| Google Spanner | `EXPLAIN` / `EXPLAIN ANALYZE` | 表格 | GA |
| Materialize | `EXPLAIN` | 树形文本 | 0.5+ |
| RisingWave | `EXPLAIN` | 树形文本 | 0.1+ |
| InfluxDB (IOx) | `EXPLAIN` | DataFusion 文本 | 3.0+ |
| Databend | `EXPLAIN` | 算子树文本 | GA |
| Yellowbrick | `EXPLAIN` | 派生自 PG | GA |
| Firebolt | `EXPLAIN` | 文本 | GA |

### 2. JSON 格式

| 引擎 | 语法 | 首个版本 | 备注 |
|------|------|---------|------|
| PostgreSQL | `EXPLAIN (FORMAT JSON)` | 9.0 (2010) | 最完整的 JSON 实现 |
| MySQL | `EXPLAIN FORMAT=JSON` | 5.6 (2013) | 包含 cost 与 used_columns |
| MariaDB | `EXPLAIN FORMAT=JSON` | 10.1+ | 与 MySQL 兼容但字段有差异 |
| SQLite | -- | -- | 不支持 |
| Oracle | `DBMS_XPLAN.DISPLAY_CURSOR(format=>'JSON')` | 12c+ (有限) | 主要靠 SQL Monitor JSON Report |
| SQL Server | -- | -- | 仅 XML，非 JSON |
| DB2 | -- | -- | 主要 db2exfmt 文本报告 |
| Snowflake | `EXPLAIN USING JSON` | GA | 与 UI Profile 数据同源 |
| BigQuery | jobs.get REST API | GA | 通过 API 而非 EXPLAIN 语句 |
| Redshift | -- | -- | 仅文本 |
| DuckDB | `EXPLAIN (FORMAT JSON)` | 0.7+ | 支持 ANALYZE+JSON |
| ClickHouse | `EXPLAIN PLAN json=1` | 21.x+ | 算子树 JSON |
| Trino | `EXPLAIN (FORMAT JSON)` | 0.150+ | 节点字段丰富 |
| Presto | `EXPLAIN (FORMAT JSON)` | 0.150+ | 同 Trino 早期 |
| Spark SQL | `EXPLAIN FORMATTED` (类 JSON) / API | 3.0+ | 严格 JSON 需 `df.queryExecution.toJSON` |
| Hive | -- | -- | 不支持 |
| Flink SQL | `EXPLAIN PLAN FOR` (JSON via REST) | 1.13+ | JobGraph JSON |
| Databricks | 同 Spark | 3.0+ | -- |
| Teradata | -- | -- | XML（QCD）为主 |
| Greenplum | `EXPLAIN (FORMAT JSON)` | 6.0+ | 继承 PG 9.x |
| CockroachDB | -- | -- | `EXPLAIN (DISTSQL)` 输出 URL |
| TiDB | `EXPLAIN FORMAT='tidb_json'` | 4.0+ | 也支持 dot/verbose |
| OceanBase | -- | -- | 主要文本/EXTENDED |
| YugabyteDB | `EXPLAIN (FORMAT JSON)` | 2.0+ | 继承 PG |
| SingleStore | `EXPLAIN JSON` | 7.0+ | -- |
| Vertica | -- | -- | 文本 + 系统表 |
| Impala | -- | -- | 文本 |
| StarRocks | `EXPLAIN COSTS` (扩展) | 2.5+ | 非严格 JSON |
| Doris | -- | -- | 主要文本 |
| MonetDB | -- | -- | -- |
| CrateDB | `EXPLAIN` (返回 JSON 列) | 4.2+ | -- |
| TimescaleDB | `EXPLAIN (FORMAT JSON)` | 继承 PG | -- |
| QuestDB | -- | -- | -- |
| Exasol | -- | -- | -- |
| SAP HANA | -- | -- | PLAN_TABLE 列式 |
| Informix | -- | -- | -- |
| Firebird | -- | -- | -- |
| H2 | -- | -- | -- |
| HSQLDB | -- | -- | -- |
| Derby | -- | -- | -- |
| Amazon Athena | `EXPLAIN (FORMAT JSON)` | engine v2+ | 继承 Trino |
| Azure Synapse | -- | -- | XML |
| Google Spanner | -- | -- | -- |
| Materialize | `EXPLAIN AS JSON` | 0.26+ | -- |
| RisingWave | `EXPLAIN (FORMAT JSON)` | 1.0+ | -- |
| InfluxDB (IOx) | -- | -- | -- |
| Databend | -- | -- | -- |
| Yellowbrick | `EXPLAIN (FORMAT JSON)` | GA | 继承 PG |
| Firebolt | -- | -- | -- |

### 3. XML 格式

| 引擎 | 语法 | 首个版本 | 备注 |
|------|------|---------|------|
| PostgreSQL | `EXPLAIN (FORMAT XML)` | 9.0 (2010) | -- |
| MySQL | `EXPLAIN FORMAT=XML` | 5.6 (2013) | 5.7 起淡出，被 JSON 取代 |
| MariaDB | -- | -- | 不支持 XML |
| SQL Server | `SET SHOWPLAN_XML ON` / `STATISTICS XML` | 2005+ | XML 是 SSMS 图形化的源 |
| Oracle | `DBMS_XPLAN.DISPLAY(format=>'XML')` | 10g+ | 配合 SQL Monitor |
| DB2 | `EXPLAIN_XML` 表 / `db2exfmt -fmt XML` | 9.5+ | -- |
| Snowflake | -- | -- | -- |
| Trino | -- | -- | -- |
| Spark SQL | -- | -- | -- |
| Greenplum | `EXPLAIN (FORMAT XML)` | 6.0+ | 继承 PG |
| CockroachDB | -- | -- | -- |
| TiDB | -- | -- | -- |
| YugabyteDB | `EXPLAIN (FORMAT XML)` | 继承 PG | -- |
| Azure Synapse | `EXPLAIN` (XML 默认) | GA | -- |
| TimescaleDB | `EXPLAIN (FORMAT XML)` | 继承 PG | -- |
| Yellowbrick | `EXPLAIN (FORMAT XML)` | GA | 继承 PG |

> 仅约 8 个引擎原生支持 XML 输出。SQL Server 是唯一把 XML 当作"权威机读格式"的主流引擎，因为 SSMS 图形化计划文件 (.sqlplan) 本质就是 XML。

### 4. YAML 格式

| 引擎 | 语法 | 首个版本 | 备注 |
|------|------|---------|------|
| PostgreSQL | `EXPLAIN (FORMAT YAML)` | 9.0 (2010) | 与 JSON 同期 |
| Greenplum | `EXPLAIN (FORMAT YAML)` | 6.0+ | 继承 PG |
| YugabyteDB | `EXPLAIN (FORMAT YAML)` | 继承 PG | -- |
| TimescaleDB | `EXPLAIN (FORMAT YAML)` | 继承 PG | -- |
| Yellowbrick | `EXPLAIN (FORMAT YAML)` | GA | 继承 PG |
| 其他全部 | -- | -- | 不支持 |

> YAML 是 PostgreSQL 系独有的"奢侈品"。它的优势是比 JSON 更适合人类直接阅读（无需大量引号与括号），缺点是大多数解析库都不内置，下游工具支持差。这也解释了为什么仅有 PG 系移植该能力。

### 5. GRAPHVIZ / DOT 格式

| 引擎 | 语法 | 首个版本 | 备注 |
|------|------|---------|------|
| Trino | `EXPLAIN (FORMAT GRAPHVIZ)` | 0.150+ | 输出 DOT，可用 `dot` 渲染 |
| Presto | `EXPLAIN (FORMAT GRAPHVIZ)` | 0.150+ | 同 Trino 早期 |
| Amazon Athena | `EXPLAIN (FORMAT GRAPHVIZ)` | engine v2+ | 继承 Trino |
| TiDB | `EXPLAIN FORMAT='dot'` | 4.0+ | 输出 DOT |
| CockroachDB | `EXPLAIN (DISTSQL)` 中含 URL | 2.0+ | 通过外部页面渲染 |
| Apache Calcite (Drill 等) | `EXPLAIN PLAN ... AS DOT` | -- | 间接 |
| 其他 | -- | -- | 通常需要中间脚本把 JSON 转 DOT |

### 6. Binary / 私有二进制格式

| 引擎 | 形式 | 备注 |
|------|------|------|
| SQL Server | .sqlplan / Query Store binary | XML 压缩或 SQL Server 二进制内部 |
| Oracle | SQL Monitor Active Report (HTML+JS) | 不是严格二进制，但二次加密 |
| DB2 | EXPLAIN 表中的 BLOB 列 | OPERATOR/STREAM/OBJECT 表 |
| Snowflake | Query Profile UI | 后端二进制，前端 JSON |
| BigQuery | jobs.get protobuf | gRPC/protobuf 二进制 |

### 7. ANALYZE 修饰符（实际执行）

ANALYZE 让 EXPLAIN 真正运行 SQL 并采集运行时统计（实际行数、实际时间、循环次数）。注意：ANALYZE 会实际执行查询，对 INSERT/UPDATE/DELETE 必须包裹在事务中并 ROLLBACK，否则会改动数据。

| 引擎 | 关键字 | 首个版本 | 备注 |
|------|--------|---------|------|
| PostgreSQL | `EXPLAIN ANALYZE` | 7.x | 历史悠久 |
| MySQL | `EXPLAIN ANALYZE` | 8.0.18 (2019) | 仅支持 SELECT |
| MariaDB | `ANALYZE FORMAT=JSON` | 10.1+ | 关键字位置不同 |
| SQLite | -- | -- | 不支持 |
| Oracle | `DBMS_XPLAN.DISPLAY_CURSOR(format=>'ALLSTATS LAST')` | 10g+ | 间接，需 STATISTICS_LEVEL=ALL |
| SQL Server | `SET STATISTICS PROFILE ON` / `SET STATISTICS XML ON` | 2000+ | 实际计划即 ANALYZE |
| DB2 | `EXPLAIN PLAN WITH SNAPSHOT` | 9.5+ | section actuals |
| Snowflake | UI Profile | GA | 无独立语法 |
| BigQuery | UI Execution details | GA | -- |
| Redshift | -- | -- | `STL_*` 系统表查询代替 |
| DuckDB | `EXPLAIN ANALYZE` | 0.2+ | -- |
| ClickHouse | `EXPLAIN PIPELINE`（结构）/ `EXPLAIN ESTIMATE`（数据） | 20.6+ | 无单一 ANALYZE |
| Trino | `EXPLAIN ANALYZE` | 0.150+ | 实际执行 |
| Presto | `EXPLAIN ANALYZE` | 0.150+ | -- |
| Spark SQL | -- | -- | 通过 `df.collect()` 后看 Spark UI |
| Flink SQL | -- | -- | 通过 Flink Web UI |
| TiDB | `EXPLAIN ANALYZE` | 3.0+ | 含每算子时间分布 |
| OceanBase | `EXPLAIN EXTENDED_NOADDR` + `last_plan_stat` | -- | 间接 |
| CockroachDB | `EXPLAIN ANALYZE` | 2.1+ | 含 statement diagnostics 包 |
| YugabyteDB | `EXPLAIN ANALYZE` | 2.0+ | 继承 PG |
| Vertica | `PROFILE` | 6.0+ | 不同关键字 |
| SingleStore | `PROFILE` | 7.0+ | 不同关键字 |
| Impala | `SUMMARY` / `PROFILE` | 1.4+ | 不同关键字 |
| Greenplum | `EXPLAIN ANALYZE` | 5.0+ | 继承 PG |
| Materialize | `EXPLAIN PHYSICAL PLAN` | 0.7+ | -- |
| Google Spanner | `EXPLAIN ANALYZE` | GA | -- |
| Athena | `EXPLAIN ANALYZE` | engine v2+ | 继承 Trino |

### 8. BUFFERS（I/O 细分）

| 引擎 | 关键字 | 首个版本 | 暴露的 I/O 维度 |
|------|--------|---------|---------------|
| PostgreSQL | `EXPLAIN (ANALYZE, BUFFERS)` | 9.0 (2010) | shared/local/temp 各自的 hit/read/dirtied/written |
| Greenplum | `EXPLAIN (ANALYZE, BUFFERS)` | 6.0+ | 继承 PG |
| TimescaleDB | `EXPLAIN (ANALYZE, BUFFERS)` | 继承 PG | 同上 |
| YugabyteDB | `EXPLAIN (ANALYZE, BUFFERS)` | 2.0+ | DocDB read/write counts |
| CockroachDB | `EXPLAIN ANALYZE (VERBOSE)` | 2.1+ | KV bytes read |
| TiDB | `EXPLAIN ANALYZE` | 3.0+ | TiKV/TiFlash 扫描字节、key 数 |
| Yellowbrick | `EXPLAIN (ANALYZE, BUFFERS)` | GA | 继承 PG |
| Trino | `EXPLAIN ANALYZE` (verbose) | -- | 输入字节数 |
| Oracle | `STATISTICS_LEVEL=ALL` | -- | physical reads / consistent gets |
| SQL Server | `SET STATISTICS IO ON` | 2000+ | 不在 EXPLAIN 内，但语义相近 |
| 其他大多数 | -- | -- | 通常通过性能视图取得 |

### 9. TIMING

| 引擎 | 关键字 | 备注 |
|------|--------|------|
| PostgreSQL | `EXPLAIN (ANALYZE, TIMING)` | 9.2+ 可关闭以减少开销 |
| MySQL | `EXPLAIN ANALYZE` (默认含时间) | 不可关闭 |
| Trino | `EXPLAIN ANALYZE` (默认含 CPU/Wall) | -- |
| TiDB | `EXPLAIN ANALYZE` (默认) | -- |
| CockroachDB | `EXPLAIN ANALYZE` (默认) | -- |
| 其他 | -- | 多数引擎 timing 不可独立开关 |

### 10. VERBOSE

| 引擎 | 关键字 | 备注 |
|------|--------|------|
| PostgreSQL | `EXPLAIN (VERBOSE)` | 8.x+ 输出输出列、schema 限定名 |
| Greenplum | `EXPLAIN (VERBOSE)` | 同 PG |
| Trino | `EXPLAIN (TYPE LOGICAL)` 中含 verbose | -- |
| Oracle | `DBMS_XPLAN.DISPLAY(format=>'ALL')` | 含 OUTLINE / PROJECTION |
| TiDB | `EXPLAIN FORMAT='verbose'` | 4.0+ |
| Spark SQL | `EXPLAIN EXTENDED` / `EXPLAIN FORMATTED` | 见下文 |
| ClickHouse | `EXPLAIN PLAN actions=1, indexes=1, header=1` | 子选项 |

### 11. SETTINGS

| 引擎 | 关键字 | 首个版本 | 备注 |
|------|--------|---------|------|
| PostgreSQL | `EXPLAIN (SETTINGS)` | 12 (2019) | 输出非默认的 GUC |
| Greenplum | `EXPLAIN (SETTINGS)` | 7.0+ | 继承 PG |
| YugabyteDB | `EXPLAIN (SETTINGS)` | 继承 PG | -- |
| TimescaleDB | `EXPLAIN (SETTINGS)` | 继承 PG | -- |
| Yellowbrick | `EXPLAIN (SETTINGS)` | GA | 继承 PG |
| 其他全部 | -- | -- | 不支持 |

### 12. WAL（仅 PostgreSQL 系）

| 引擎 | 关键字 | 首个版本 | 备注 |
|------|--------|---------|------|
| PostgreSQL | `EXPLAIN (ANALYZE, WAL)` | 13 (2020) | 仅写入操作有 WAL 记录 |
| YugabyteDB | -- | -- | 用 DocDB write counts 代替 |
| TimescaleDB | `EXPLAIN (ANALYZE, WAL)` | 继承 PG 13 | -- |
| Yellowbrick | `EXPLAIN (ANALYZE, WAL)` | GA | 继承 PG |
| Greenplum | -- | -- | 7.0 才合并 PG 13，待跟进 |

> 统计：WAL 选项是 PostgreSQL 13 引入的新特性，几乎只有 PG 直系派生才支持。它对调试 INSERT/UPDATE/DELETE 的 WAL 放大问题至关重要。

## 各引擎详解

### PostgreSQL（格式最完整、文档最详尽）

PostgreSQL 是 EXPLAIN 输出格式的"事实标准制定者"。9.0 在 2010 年一次性引入了 TEXT/JSON/XML/YAML 四种格式以及 BUFFERS 选项，奠定了之后十年的工具生态。

```sql
-- 默认文本树
EXPLAIN SELECT * FROM orders WHERE customer_id = 42;

-- 显式指定 TEXT
EXPLAIN (FORMAT TEXT) SELECT * FROM orders WHERE customer_id = 42;

-- JSON：最常用的机读格式
EXPLAIN (FORMAT JSON) SELECT * FROM orders WHERE customer_id = 42;

-- XML：企业 BI 与 .NET 工具偏爱
EXPLAIN (FORMAT XML) SELECT * FROM orders WHERE customer_id = 42;

-- YAML：人机两用
EXPLAIN (FORMAT YAML) SELECT * FROM orders WHERE customer_id = 42;

-- ANALYZE：实际执行
EXPLAIN (ANALYZE) SELECT * FROM orders WHERE customer_id = 42;

-- 全副武装：实际执行 + I/O 细分 + WAL + 不显示 cost + 设置变更
EXPLAIN (ANALYZE, BUFFERS, WAL, COSTS OFF, SETTINGS, FORMAT JSON)
SELECT * FROM orders WHERE customer_id = 42;

-- VERBOSE：输出列名 / schema 限定名 / 触发器细节
EXPLAIN (ANALYZE, VERBOSE) SELECT * FROM orders WHERE customer_id = 42;

-- 关闭 TIMING 以减少高频测量开销（在某些 OS 上 gettimeofday 很贵）
EXPLAIN (ANALYZE, TIMING OFF) SELECT * FROM orders WHERE customer_id = 42;

-- DML 必须用事务包裹以避免实际写入
BEGIN;
EXPLAIN (ANALYZE, BUFFERS, WAL)
UPDATE orders SET status = 'shipped' WHERE id = 1;
ROLLBACK;
```

PostgreSQL EXPLAIN 选项的发展时间线：

| 选项 | 引入版本 | 年份 |
|------|---------|------|
| `ANALYZE` | 7.0 | 2000 |
| `VERBOSE` | 8.0 | 2005 |
| `BUFFERS`, `FORMAT TEXT/JSON/XML/YAML` | 9.0 | 2010 |
| `TIMING` | 9.2 | 2012 |
| `SUMMARY` | 9.5 | 2016 |
| `SETTINGS` | 12 | 2019 |
| `WAL` | 13 | 2020 |
| `GENERIC_PLAN` | 16 | 2023 |

### Oracle（DBMS_XPLAN 系列与 SQL Monitor）

Oracle 的 EXPLAIN 体系比 PostgreSQL 更加割裂——既有"静态计划"，又有"实际计划"，还有"实时监控"，分别对应不同的工具：

```sql
-- 1. 静态计划：估算的，不实际执行
EXPLAIN PLAN FOR
SELECT * FROM orders WHERE customer_id = 42;

SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY());
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY(format=>'ALL'));
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY(format=>'BASIC'));
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY(format=>'TYPICAL'));
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY(format=>'ADVANCED'));

-- 2. 实际游标计划：从共享池取
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY_CURSOR(
    sql_id => 'a1b2c3d4',
    format => 'ALLSTATS LAST'
));

-- 3. AWR 历史计划
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY_AWR('a1b2c3d4'));

-- 4. SQL 计划基线
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY_SQL_PLAN_BASELINE('SQL_PLAN_xxx'));

-- 5. SQL Monitor：长查询的实时监控（HTML / Active Report / Text）
SELECT DBMS_SQLTUNE.REPORT_SQL_MONITOR(
    sql_id     => 'a1b2c3d4',
    type       => 'ACTIVE',     -- HTML5 + JS 可交互
    report_level => 'ALL'
) FROM dual;

-- type 参数取值：'TEXT'、'HTML'、'XML'、'ACTIVE'
```

Oracle 的 SQL Monitor Active Report 是一份自包含的 HTML，把执行计划渲染成可点击的树，每个算子上都附带实时进度条（CPU、IO、行数），是商业数据库里最先进的 EXPLAIN UI。但也因此，几乎没法被第三方工具解析——这是 Oracle"用 UI 锁定客户"策略的缩影。

### SQL Server（XML 是一等公民）

SQL Server 把 XML 作为执行计划的权威格式：SSMS 的图形化执行计划、Plan Explorer、Query Store 都基于同一份 XML schema（`showplanxml.xsd`，目前 1.539 版本，公开发布）。

```sql
-- 文本格式（已不推荐，2008 起标记为 deprecated）
SET SHOWPLAN_TEXT ON;
GO
SELECT * FROM Sales.SalesOrderDetail WHERE OrderQty > 5;
GO
SET SHOWPLAN_TEXT OFF;

-- ALL 文本：含估算 IO/CPU
SET SHOWPLAN_ALL ON;
GO
SELECT * FROM Sales.SalesOrderDetail WHERE OrderQty > 5;
GO
SET SHOWPLAN_ALL OFF;

-- XML 估算计划：不执行
SET SHOWPLAN_XML ON;
GO
SELECT * FROM Sales.SalesOrderDetail WHERE OrderQty > 5;
GO
SET SHOWPLAN_XML OFF;

-- XML 实际计划：执行并返回 XML
SET STATISTICS XML ON;
GO
SELECT * FROM Sales.SalesOrderDetail WHERE OrderQty > 5;
GO
SET STATISTICS XML OFF;

-- 文本实际计划
SET STATISTICS PROFILE ON;
GO
SELECT * FROM Sales.SalesOrderDetail WHERE OrderQty > 5;
GO
SET STATISTICS PROFILE OFF;

-- I/O 与时间统计
SET STATISTICS IO ON;
SET STATISTICS TIME ON;
GO
SELECT * FROM Sales.SalesOrderDetail WHERE OrderQty > 5;
GO

-- Query Store：自动捕获，可视化
ALTER DATABASE AdventureWorks SET QUERY_STORE = ON;
SELECT * FROM sys.query_store_plan;
```

XML 计划的优势：可被 XPath/XQuery 直接查询：

```sql
-- 找出所有计划中包含 Hash Match 算子的查询
SELECT TOP 10
    qs.execution_count,
    qp.query_plan
FROM sys.dm_exec_query_stats qs
CROSS APPLY sys.dm_exec_query_plan(qs.plan_handle) qp
WHERE qp.query_plan.exist('
    declare default element namespace "http://schemas.microsoft.com/sqlserver/2004/07/showplan";
    //RelOp[@PhysicalOp="Hash Match"]
') = 1;
```

### MySQL（从表格到 TREE 的进化）

MySQL 的 EXPLAIN 输出经历了三个主要阶段：

**阶段 1：传统表格（5.0–5.5）**

```sql
EXPLAIN SELECT * FROM orders WHERE customer_id = 42;
-- 11 列固定表格：id / select_type / table / type / possible_keys / key /
--                key_len / ref / rows / Extra / partitions
```

**阶段 2：JSON（5.6, 2013）**

```sql
EXPLAIN FORMAT=JSON
SELECT * FROM orders o JOIN customers c ON o.customer_id = c.id
WHERE c.region = 'APAC';
```

JSON 输出了表格无法表达的细节：嵌套循环结构、cost 估算、used_columns、attached_condition、possible_keys 排名等。

**阶段 3：TREE 与 ANALYZE（8.0.16 / 8.0.18, 2019）**

```sql
-- TREE 格式：火山模型迭代器树（8.0.16+）
EXPLAIN FORMAT=TREE
SELECT * FROM orders o JOIN customers c ON o.customer_id = c.id
WHERE c.region = 'APAC';

-- 输出形如：
-- -> Nested loop inner join  (cost=4.70 rows=2)
--     -> Filter: (c.region = 'APAC')  (cost=2.05 rows=2)
--         -> Table scan on c  (cost=2.05 rows=10)
--     -> Index lookup on o using customer_id (customer_id=c.id)  (cost=1.10 rows=1)

-- EXPLAIN ANALYZE：实际执行（8.0.18+），底层即 TREE 格式
EXPLAIN ANALYZE
SELECT * FROM orders o JOIN customers c ON o.customer_id = c.id
WHERE c.region = 'APAC';

-- 输出含 actual time, rows, loops：
-- -> Nested loop inner join  (cost=4.70 rows=2) (actual time=0.158..0.241 rows=3 loops=1)
```

MySQL `EXPLAIN ANALYZE` 的关键限制：

1. 仅支持 SELECT，不支持 UPDATE/DELETE/INSERT。
2. 输出格式固定为 TREE，不能选 JSON/TABLE。
3. 会真正执行查询，需注意时间与资源占用。
4. 8.1 起引入 `FORMAT=JSON` 与 ANALYZE 组合，但仍属预览。

### DB2（最复杂的 EXPLAIN 表族）

DB2 没有把 EXPLAIN 输出绑在 SQL 结果上，而是写入一组系统目录表（PLAN_TABLE 族）：

```sql
-- 1. 创建 EXPLAIN 表（一次性）
CALL SYSPROC.SYSINSTALLOBJECTS('EXPLAIN','C',CAST(NULL AS VARCHAR(128)),CURRENT SCHEMA);

-- 2. 写入计划
EXPLAIN PLAN FOR
SELECT * FROM orders WHERE customer_id = 42;

-- 3. 用 db2exfmt 工具格式化（命令行）
-- $ db2exfmt -d sample -e schema -g TIC -w -1 -n % -s % -# 0

-- 4. 直接查询 EXPLAIN 表
SELECT operator_type, total_cost
FROM EXPLAIN_OPERATOR
WHERE explain_time = (SELECT MAX(explain_time) FROM EXPLAIN_OPERATOR);

-- 5. 现代化：EXPLAIN_FROM_ACTIVITY (来自 WLM 监控)
CALL EXPLAIN_FROM_ACTIVITY(?, ?, ?, ?, ?, ?, ?, ?);
```

`db2exfmt` 是 DB2 独有的批处理格式化器，可生成包含 access plan graph 的纯文本报告，是 DB2 DBA 日常工具。

### ClickHouse（按主题切分的多种 EXPLAIN）

ClickHouse 把 EXPLAIN 拆成五个独立子命令，每个查询树的不同维度：

```sql
-- 1. AST：抽象语法树（解析后）
EXPLAIN AST SELECT * FROM hits WHERE UserID = 42;

-- 2. SYNTAX：语法重写后的 SQL
EXPLAIN SYNTAX SELECT count(distinct UserID) FROM hits;
-- 可看到 distinct + count → uniqExact 重写

-- 3. PLAN：逻辑算子树（默认）
EXPLAIN PLAN SELECT * FROM hits WHERE UserID = 42;
EXPLAIN PLAN actions=1, indexes=1, header=1
SELECT * FROM hits WHERE UserID = 42;

-- 4. PIPELINE：物理流水线（向量化执行细节）
EXPLAIN PIPELINE SELECT count() FROM hits;
EXPLAIN PIPELINE graph=1 SELECT count() FROM hits;
-- graph=1 输出 DOT，可渲染

-- 5. ESTIMATE：预估扫描的行/字节/分片
EXPLAIN ESTIMATE SELECT * FROM hits WHERE EventDate = '2023-01-01';

-- JSON 输出
EXPLAIN PLAN json=1 SELECT * FROM hits WHERE UserID = 42;
```

ClickHouse 没有"ANALYZE"概念（因为 OLAP 引擎单查询就是 ms 级，可直接跑）。如果要看真实运行时统计，使用 `system.query_log`：

```sql
SELECT query_duration_ms, read_rows, read_bytes, memory_usage
FROM system.query_log
WHERE query LIKE '%hits%' AND type = 'QueryFinish'
ORDER BY event_time DESC LIMIT 10;
```

### DuckDB（树形 ASCII art + JSON）

DuckDB 的 EXPLAIN 默认输出是终端美化过的 Unicode box-drawing 树：

```sql
EXPLAIN SELECT count(*) FROM orders WHERE customer_id = 42;
-- ┌───────────────────────────┐
-- │      AGGREGATE            │
-- │   ────────────────────    │
-- │      count_star()         │
-- └─────────────┬─────────────┘
-- ┌─────────────┴─────────────┐
-- │           SEQ_SCAN        │
-- │   ────────────────────    │
-- │       Filter: customer_id │
-- └───────────────────────────┘

-- ANALYZE：实际执行
EXPLAIN ANALYZE SELECT count(*) FROM orders WHERE customer_id = 42;

-- JSON 输出
EXPLAIN (FORMAT JSON) SELECT count(*) FROM orders WHERE customer_id = 42;
```

DuckDB 的 ANALYZE 输出会在每个算子上叠加实际行数与 wall time。

### Snowflake（UI 优先，文本与 JSON 为辅）

Snowflake 的"权威"执行计划是 Snowsight UI 中的 Query Profile（DAG 图，节点上有时间饼图）。SQL 层面：

```sql
-- 默认：表格形式
EXPLAIN SELECT * FROM orders WHERE customer_id = 42;
EXPLAIN USING TABULAR SELECT * FROM orders WHERE customer_id = 42;

-- 文本树
EXPLAIN USING TEXT SELECT * FROM orders WHERE customer_id = 42;

-- JSON：与 UI Profile 同源
EXPLAIN USING JSON SELECT * FROM orders WHERE customer_id = 42;

-- 历史查询的实际 Profile（无独立 EXPLAIN ANALYZE）
SELECT GET_QUERY_OPERATOR_STATS('01abc123-...');
```

Snowflake 没有 EXPLAIN ANALYZE，因为执行计划与运行时统计是分离的：跑完查询后通过 `QUERY_HISTORY` + `GET_QUERY_OPERATOR_STATS` 拿到实际指标。

### BigQuery（无 EXPLAIN 关键字）

BigQuery 完全没有 `EXPLAIN` 语法。"计划"等价于一次 dry run：

```sql
-- 通过 jobs.insert API + dryRun=true
-- 或通过 bq CLI：
-- $ bq query --dry_run --use_legacy_sql=false 'SELECT * FROM dataset.t'

-- 实际执行后，stages 在 jobs.get API 的 statistics.query.queryPlan 字段
-- UI 中显示为 "Execution details" 标签页的瀑布图
```

BigQuery 的"执行计划"实际上是事后 DAG（Dremel stages），更接近 Spark UI。

### Trino / Presto（最完整的 EXPLAIN 类型矩阵）

Trino 的 EXPLAIN 同时支持"类型"与"格式"两个维度的笛卡尔积：

```sql
-- TYPE：LOGICAL / DISTRIBUTED / VALIDATE / IO
EXPLAIN (TYPE LOGICAL) SELECT * FROM orders;
EXPLAIN (TYPE DISTRIBUTED) SELECT * FROM orders;
EXPLAIN (TYPE IO, FORMAT JSON) SELECT * FROM orders;
EXPLAIN (TYPE VALIDATE) SELECT * FROM orders;

-- FORMAT：TEXT / GRAPHVIZ / JSON
EXPLAIN (FORMAT TEXT) SELECT * FROM orders;
EXPLAIN (FORMAT GRAPHVIZ) SELECT * FROM orders;
EXPLAIN (FORMAT JSON) SELECT * FROM orders;

-- 组合
EXPLAIN (TYPE DISTRIBUTED, FORMAT GRAPHVIZ) SELECT * FROM orders;

-- 实际执行
EXPLAIN ANALYZE SELECT * FROM orders;
EXPLAIN ANALYZE VERBOSE SELECT * FROM orders;
```

GRAPHVIZ 输出可直接管道给 `dot`：

```bash
trino --execute "EXPLAIN (FORMAT GRAPHVIZ) SELECT * FROM orders" | dot -Tpng -o plan.png
```

### Spark SQL（FORMATTED / EXTENDED / CODEGEN / COST）

Spark SQL 的 EXPLAIN 在 3.0（2020）之后变化最大，引入了 FORMATTED 输出：

```sql
-- 默认：物理计划
EXPLAIN SELECT * FROM orders WHERE customer_id = 42;

-- 全部四阶段：parsed / analyzed / optimized / physical
EXPLAIN EXTENDED SELECT * FROM orders WHERE customer_id = 42;

-- 含估算 cost（基于 CBO）
EXPLAIN COST SELECT * FROM orders WHERE customer_id = 42;

-- 显示生成的 codegen Java 源码
EXPLAIN CODEGEN SELECT * FROM orders WHERE customer_id = 42;

-- 3.0 引入：分层格式化
EXPLAIN FORMATTED SELECT * FROM orders WHERE customer_id = 42;
-- 输出分两部分：
-- 1. 简化的物理计划（每节点带 (n) 编号）
-- 2. 各节点详细 metadata（逐节点段落）
```

`EXPLAIN FORMATTED` 是 Spark 对 PostgreSQL 风格"结构化文本"的回应，比 EXTENDED 更易阅读。

### 其他引擎扼要

```sql
-- TiDB（最丰富的格式选项之一）
EXPLAIN FORMAT='row' SELECT * FROM t WHERE id = 1;        -- 默认表格
EXPLAIN FORMAT='brief' SELECT * FROM t WHERE id = 1;
EXPLAIN FORMAT='dot' SELECT * FROM t WHERE id = 1;        -- DOT 图
EXPLAIN FORMAT='tidb_json' SELECT * FROM t WHERE id = 1;
EXPLAIN FORMAT='verbose' SELECT * FROM t WHERE id = 1;
EXPLAIN ANALYZE SELECT * FROM t WHERE id = 1;

-- CockroachDB
EXPLAIN SELECT * FROM t WHERE id = 1;
EXPLAIN (VERBOSE) SELECT * FROM t WHERE id = 1;
EXPLAIN (TYPES) SELECT * FROM t WHERE id = 1;
EXPLAIN (DISTSQL) SELECT * FROM t WHERE id = 1;   -- 返回 URL，浏览器渲染
EXPLAIN ANALYZE SELECT * FROM t WHERE id = 1;
EXPLAIN ANALYZE (DEBUG) SELECT * FROM t WHERE id = 1;  -- 生成 statement bundle ZIP

-- YugabyteDB（PG 兼容）
EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) SELECT * FROM t WHERE id = 1;
-- BUFFERS 输出 DocDB read counts

-- Vertica
EXPLAIN SELECT * FROM t WHERE id = 1;
EXPLAIN LOCAL VERBOSE SELECT * FROM t WHERE id = 1;
PROFILE SELECT * FROM t WHERE id = 1;  -- 实际执行 + 写入 v_monitor.execution_engine_profiles

-- SingleStore
EXPLAIN SELECT * FROM t WHERE id = 1;
EXPLAIN JSON SELECT * FROM t WHERE id = 1;
PROFILE SELECT * FROM t WHERE id = 1;  -- 实际执行
SHOW PROFILE;

-- Impala
EXPLAIN SELECT * FROM t WHERE id = 1;
SET EXPLAIN_LEVEL=3;   -- 0..3，3 最详细
SUMMARY;               -- 上次查询的 per-operator summary
PROFILE;               -- 上次查询完整 profile

-- Greenplum / HAWQ
EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON, SETTINGS) SELECT * FROM t;
-- 继承 PG，输出含每个 segment 的 slice 信息

-- Materialize（流式视图引擎）
EXPLAIN PLAN FOR SELECT * FROM t;
EXPLAIN OPTIMIZED PLAN FOR SELECT * FROM t;
EXPLAIN PHYSICAL PLAN FOR SELECT * FROM t;
EXPLAIN AS JSON FOR SELECT * FROM t;
EXPLAIN TIMESTAMP FOR SELECT * FROM t;   -- 物化视图独有

-- Flink SQL
EXPLAIN PLAN FOR SELECT * FROM t;
EXPLAIN ESTIMATED_COST, CHANGELOG_MODE, JSON_EXECUTION_PLAN FOR SELECT * FROM t;
```

## PostgreSQL EXPLAIN 深度剖析

### 一份典型的 JSON 输出

```sql
EXPLAIN (ANALYZE, BUFFERS, SETTINGS, WAL, FORMAT JSON)
SELECT c.name, sum(o.total)
FROM customers c JOIN orders o ON o.customer_id = c.id
WHERE c.region = 'APAC'
GROUP BY c.name
ORDER BY sum(o.total) DESC
LIMIT 10;
```

简化后的输出结构（删除重复字段）：

```json
[
  {
    "Plan": {
      "Node Type": "Limit",
      "Startup Cost": 1234.56,
      "Total Cost": 1234.78,
      "Plan Rows": 10,
      "Plan Width": 40,
      "Actual Startup Time": 5.123,
      "Actual Total Time": 5.234,
      "Actual Rows": 10,
      "Actual Loops": 1,
      "Shared Hit Blocks": 120,
      "Shared Read Blocks": 5,
      "Shared Dirtied Blocks": 0,
      "Shared Written Blocks": 0,
      "Local Hit Blocks": 0,
      "Temp Read Blocks": 0,
      "Temp Written Blocks": 0,
      "WAL Records": 0,
      "WAL FPI": 0,
      "WAL Bytes": 0,
      "Plans": [
        {
          "Node Type": "Sort",
          "Sort Key": ["(sum(o.total)) DESC"],
          "Sort Method": "top-N heapsort",
          "Sort Space Used": 27,
          "Sort Space Type": "Memory",
          "Plans": [
            {
              "Node Type": "HashAggregate",
              "Group Key": ["c.name"],
              "Plans": [
                {
                  "Node Type": "Hash Join",
                  "Hash Cond": "(o.customer_id = c.id)",
                  "Plans": [
                    {"Node Type": "Seq Scan", "Relation Name": "orders"},
                    {"Node Type": "Hash", "Plans": [
                      {"Node Type": "Seq Scan", "Relation Name": "customers",
                       "Filter": "(region = 'APAC'::text)"}
                    ]}
                  ]
                }
              ]
            }
          ]
        }
      ]
    },
    "Settings": {
      "work_mem": "64MB",
      "random_page_cost": "1.1"
    },
    "Planning": {
      "Shared Hit Blocks": 12,
      "Shared Read Blocks": 0
    },
    "Planning Time": 0.234,
    "Triggers": [],
    "Execution Time": 5.456
  }
]
```

JSON 字段的关键洞察：

1. **Plan 是嵌套递归结构**：每个节点有零到多个 `Plans` 子节点。
2. **运行时字段全部以 "Actual" 前缀**：方便 diff "估算 vs 实际"。
3. **BUFFERS 字段独立分维度**：shared / local / temp 各自的 hit / read / dirtied / written，便于定位是缓存命中问题还是物理读问题。
4. **WAL 字段仅在写入时非零**：`WAL FPI`（full-page image）特别能暴露 checkpoint 后的写放大。
5. **Settings 块只列出非默认值**：极大方便 reproducibility（"为什么开发环境快，生产环境慢？"）。
6. **Planning vs Execution 分离**：可单独看 planner 自己消耗了多少时间——长 SQL 在 PG 中 planner 时间可能就是几十毫秒。

### BUFFERS 的解读

```
Shared Hit Blocks: 120      ← 共享缓冲池命中（无 I/O）
Shared Read Blocks: 5       ← 物理读（OS 缓存或磁盘）
Shared Dirtied Blocks: 0    ← 写脏（含 hint bit 更新）
Shared Written Blocks: 0    ← 直接写出（缓冲池满时）
Local Hit/Read Blocks: ...  ← 临时表（会话私有）
Temp Read/Written Blocks: ...← 排序/哈希溢写到磁盘
```

诊断技巧：

- 大量 `Shared Read` → 缓冲池小或 query pattern 不友好。
- 大量 `Temp Written` → `work_mem` 不足，排序/哈希落盘。
- 大量 `Shared Dirtied` 但只是 SELECT → hint bits 首次更新，第二次跑会消失。

### Auto-EXPLAIN 扩展

```sql
LOAD 'auto_explain';
SET auto_explain.log_min_duration = '1s';
SET auto_explain.log_analyze = true;
SET auto_explain.log_buffers = true;
SET auto_explain.log_format = 'json';
SET auto_explain.log_settings = true;
-- 之后所有执行时间 > 1s 的查询会自动写入 PG 日志（JSON 格式）
```

这是生产环境慢查询溯源的最佳工具。

## MySQL EXPLAIN FORMAT=TREE vs JSON 演进

MySQL 的 EXPLAIN 输出格式经历了一个长达十年的演进，从"行内静态表格"逐步走向"算子树 + 实际指标"。

### 三种格式的对比

```sql
-- 1. TRADITIONAL（默认）：5.0 起的 11 列表格
EXPLAIN SELECT c.name, sum(o.total)
FROM customers c JOIN orders o ON o.customer_id = c.id
WHERE c.region = 'APAC' GROUP BY c.name;

-- +----+-------------+-------+--------+---------------+-------+...
-- | id | select_type | table | type   | possible_keys | key   |
-- +----+-------------+-------+--------+---------------+-------+
-- |  1 | SIMPLE      | c     | ALL    | PRIMARY       | NULL  |
-- |  1 | SIMPLE      | o     | ref    | customer_id   | cust* |
-- +----+-------------+-------+--------+---------------+-------+

-- 2. JSON（5.6, 2013）：嵌套结构 + cost
EXPLAIN FORMAT=JSON SELECT c.name, sum(o.total)
FROM customers c JOIN orders o ON o.customer_id = c.id
WHERE c.region = 'APAC' GROUP BY c.name;

-- {
--   "query_block": {
--     "select_id": 1,
--     "cost_info": { "query_cost": "4.70" },
--     "grouping_operation": {
--       "using_filesort": false,
--       "nested_loop": [
--         { "table": { "table_name": "c", "access_type": "ALL", ...}},
--         { "table": { "table_name": "o", "access_type": "ref", ...}}
--       ]
--     }
--   }
-- }

-- 3. TREE（8.0.16, 2019）：火山模型迭代器树
EXPLAIN FORMAT=TREE SELECT c.name, sum(o.total)
FROM customers c JOIN orders o ON o.customer_id = c.id
WHERE c.region = 'APAC' GROUP BY c.name;

-- -> Group aggregate: sum(o.total)
--     -> Nested loop inner join  (cost=4.70 rows=2)
--         -> Filter: (c.region = 'APAC')  (cost=2.05 rows=2)
--             -> Table scan on c  (cost=2.05 rows=10)
--         -> Index lookup on o using customer_id (customer_id=c.id)
```

### 为什么需要 TREE 格式

传统表格格式有一个根本缺陷：**它是行级的**，每行代表一个表/子查询的访问方式，但**无法表达算子之间的父子关系与执行顺序**。例如多表 JOIN 中，"先扫 A 再 NLJ B 再 hash join C"这样的拓扑在表格里只能凭 id 顺序间接推断。

TREE 格式直接借鉴 PostgreSQL 的树形输出与 Volcano model 命名（"Nested loop inner join"、"Index lookup"），让算子树一目了然。这是 MySQL 8.0 优化器重写（"Iterator Executor"）的副产品——执行器内部本来就是迭代器树，输出树形才合理。

### EXPLAIN ANALYZE 的语义

```sql
EXPLAIN ANALYZE SELECT c.name, sum(o.total)
FROM customers c JOIN orders o ON o.customer_id = c.id
WHERE c.region = 'APAC' GROUP BY c.name;

-- -> Group aggregate: sum(o.total)
--    (cost=4.70 rows=2) (actual time=0.412..0.418 rows=3 loops=1)
--     -> Nested loop inner join
--        (cost=4.70 rows=2) (actual time=0.158..0.395 rows=8 loops=1)
--         -> Filter: (c.region = 'APAC')
--            (cost=2.05 rows=2) (actual time=0.083..0.118 rows=3 loops=1)
--             -> Table scan on c
--                (cost=2.05 rows=10) (actual time=0.075..0.103 rows=10 loops=1)
--         -> Index lookup on o using customer_id (customer_id=c.id)
--            (cost=1.10 rows=1) (actual time=0.082..0.087 rows=3 loops=3)
```

每个节点的 `(actual time=START..END rows=N loops=L)`：

- `START`：返回第一行的时间（毫秒）
- `END`：返回最后一行的时间
- `rows`：每次迭代的平均行数
- `loops`：父节点驱动该节点的次数

注意：`rows × loops` ≈ 总输出行数。看到 `rows=1 loops=1000000`（百万次迭代）是 NLJ 退化的明显信号。

### MariaDB 的差异

MariaDB 走了不同的路径，关键字位置差异：

```sql
-- MariaDB：用 ANALYZE 而非 EXPLAIN ANALYZE
ANALYZE SELECT * FROM orders WHERE customer_id = 42;

-- ANALYZE FORMAT=JSON 含 r_rows / r_filtered 等实际指标
ANALYZE FORMAT=JSON SELECT * FROM orders WHERE customer_id = 42;
```

MariaDB 的 JSON 字段以 `r_` 前缀表示运行时实际值（r_rows、r_filtered、r_total_time_ms），与 PG 的 "Actual" 前缀理念相似。

## 关键发现

1. **SQL 标准缺席使生态严重碎片化**。每家厂商的 EXPLAIN 都是私有方言：关键字、修饰符位置、输出载体、格式枚举无一相同。这是写跨数据库工具（DataGrip、DBeaver、ORM）的最大成本来源。

2. **PostgreSQL 9.0（2010）是分水岭**。PG 一次性引入 TEXT/JSON/XML/YAML 四种格式 + BUFFERS，奠定了之后十年 EXPLAIN 工具生态的范式。后来的 PG 衍生（Greenplum、Yellowbrick、YugabyteDB、TimescaleDB、CockroachDB-PG-mode）几乎都直接继承。

3. **JSON 已成事实标准**。约 15 个引擎原生支持 JSON 输出，是除 TEXT 之外覆盖最广的格式。Dalibo PEV、explain.depesz.com、PEV2、VividCortex、Datadog 都以 JSON 为输入。

4. **XML 退守 SQL Server**。XML 在 SQL Server 中是一等公民（SSMS 图形化计划、Query Store 都基于 XML），但在其他引擎中正在被 JSON 取代。MySQL 5.5 引入 XML 后，5.6 引入 JSON，到 8.0 几乎不再有人用 XML。

5. **YAML 是 PostgreSQL 系独有的奢侈品**。仅 PG 及其直系继承支持。优势是无需大量引号即可人读，但下游工具支持差，使用率远低于 JSON。

6. **GRAPHVIZ/DOT 集中在 MPP / 联邦查询引擎**。Trino、Presto、TiDB、Athena、CockroachDB 都倾向输出 DOT，因为分布式计划本质就是 DAG，纯文本树无法表达 stage 之间的多对多关系。

7. **ANALYZE 修饰符并非到处都叫 ANALYZE**。Vertica/SingleStore 用 `PROFILE`，Impala 用 `SUMMARY`/`PROFILE`，Snowflake/BigQuery 干脆没有独立语法（依赖 UI），Oracle 通过 `DBMS_XPLAN.DISPLAY_CURSOR(format=>'ALLSTATS LAST')` 间接实现。

8. **BUFFERS 是 PostgreSQL 系独家**。PG 9.0 引入的 BUFFERS 选项把 I/O 拆成 hit/read/dirtied/written × shared/local/temp 共 12 个维度，至今仍是最细的 I/O 自省能力。SQL Server 的 `SET STATISTICS IO` 类似但在 EXPLAIN 之外。

9. **WAL 选项是写放大调优的杀手锏**。PG 13 (2020) 引入的 WAL 选项让 INSERT/UPDATE/DELETE 的 WAL 字节数和 full-page image 数量直接出现在 EXPLAIN 中，是定位 checkpoint 风暴和 hot update 模式的金标准。仅 PG 系独有。

10. **MySQL EXPLAIN 的演进史值得每个 SQL 工具开发者学习**。从 5.0 的 11 列表格 → 5.6 的 JSON → 8.0.16 的 TREE → 8.0.18 的 EXPLAIN ANALYZE，整整 19 年时间，每一步都对应优化器/执行器架构升级（cost model、iterator executor）。

11. **Oracle 的 SQL Monitor Active Report 是商业之最**。自包含 HTML5 + JS 的可交互执行计划是任何开源引擎都未达到的高度，但也因此几乎不可被第三方工具机读，是"用 UI 锁定客户"策略的典型。

12. **SETTINGS 选项是可复现性的关键**。PG 12 引入的 SETTINGS 子选项会把所有非默认 GUC 列入 JSON，让"为什么这条 SQL 在开发库上 10ms 而在生产库上 10s"的排查从猜测变成 diff。但仅 PG 系支持，跨引擎复现性仍然是开放问题。

13. **EXPLAIN 与可观测性平台的边界正在模糊**。Auto-EXPLAIN（PG）、Query Store（SQL Server）、AWR（Oracle）、Query History（Snowflake）都在做"自动捕获并持久化执行计划"。未来 EXPLAIN 不再是开发期工具，而是 always-on 的运行时遥测来源。

14. **DML 计划必须包裹事务并 ROLLBACK**。`EXPLAIN ANALYZE INSERT/UPDATE/DELETE` 在 PG/MySQL/Trino 等都会真正执行写入。安全模式：

    ```sql
    BEGIN;
    EXPLAIN (ANALYZE, BUFFERS, WAL) UPDATE orders SET status = 'shipped' WHERE id = 1;
    ROLLBACK;
    ```

15. **统计**：约 50 个调研引擎中，约 15 个支持 JSON、约 8 个支持 XML、约 6 个支持 YAML（全部 PG 系）、约 6 个支持 GRAPHVIZ/DOT。同时支持 4 种以上格式的只有 PostgreSQL 及其直系继承，这也是 PG 在 EXPLAIN 工具生态上一骑绝尘的根本原因。
