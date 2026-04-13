# 时序数据处理 (Time-Series Functions)

从 IoT 传感器每秒产生数万条读数，到金融市场毫秒级的交易行情，再到运维监控系统的指标采集——时序数据已成为增长最快的数据类别。Gartner 估计全球数据中超过 70% 具有时间维度。然而 SQL 标准至今未定义专门的时序处理语法，各引擎的实现路径完全不同：专用时序数据库（TimescaleDB、QuestDB、InfluxDB）提供原生的时间分桶、间隙填充、连续聚合；通用引擎（PostgreSQL、ClickHouse、DuckDB）通过 DATE_TRUNC、窗口函数和 GENERATE_SERIES 组合来实现等价操作；云数据仓库（BigQuery、Snowflake）则在标准 SQL 之上叠加各自的时序扩展。本文横向对比 49 个 SQL 引擎在时序处理各维度的能力差异，为引擎开发者提供全景参考。

## SQL 标准现状

SQL 标准（ISO/IEC 9075）没有定义专门的时序处理操作。时序分析依赖的 SQL 能力散落在多个标准版本中：

- **SQL:2003**: 窗口函数（LAG、LEAD、SUM OVER、ROWS/RANGE BETWEEN）——时序分析的基础
- **SQL:2011**: TIMESTAMP 精度、INTERVAL 算术、时态表（SYSTEM_TIME / APPLICATION_TIME）
- **SQL:2016**: 行模式匹配（MATCH_RECOGNIZE）——可用于时序模式检测

缺失的关键操作（无标准定义）：
- 时间分桶（time bucketing）
- 间隙填充（gap filling）
- ASOF JOIN（时序近似匹配，详见 [asof-join.md](asof-join.md)）
- 连续聚合（continuous aggregates）
- 数据保留策略（retention policies）
- 插值函数（interpolation）

因此，各引擎各自发展了不同的语法和语义，是跨引擎迁移中最碎片化的领域之一。

---

## 1. 时间分桶 (Time Bucketing)

将时间戳截断或对齐到固定间隔是时序分析最基础的操作。不同引擎提供三种主要方法：`DATE_TRUNC`（截断到日历边界）、`time_bucket`（对齐到任意间隔）、`DATE_BIN`（PostgreSQL 14+ 引入的厂商扩展）。

### 支持矩阵

| 引擎 | DATE_TRUNC | time_bucket | DATE_BIN | 自定义间隔分桶 | 备注 |
|------|-----------|-------------|----------|--------------|------|
| PostgreSQL | 是 (7.0+) | -- | 是 (14+) | DATE_BIN | `DATE_TRUNC('hour', ts)` |
| MySQL | -- | -- | -- | 需表达式模拟 | 用 `FLOOR(UNIX_TIMESTAMP/N)*N` |
| MariaDB | -- | -- | -- | 需表达式模拟 | 同 MySQL |
| SQLite | -- | -- | -- | `strftime` 模拟 | `strftime('%Y-%m-%d %H:00:00', ts)` |
| Oracle | `TRUNC` | -- | -- | TRUNC + 算术 | `TRUNC(ts, 'HH')` 语法不同 |
| SQL Server | -- | -- | -- | `DATEADD+DATEDIFF` | `DATEADD(HOUR, DATEDIFF(HOUR,0,ts), 0)` |
| DB2 | `TRUNC` / `TRUNCATE` | -- | -- | TRUNC + 算术 | `TRUNC(ts, 'HH')` |
| Snowflake | 是 | `TIME_SLICE` | -- | TIME_SLICE | `TIME_SLICE(ts, 15, 'MINUTE')` |
| BigQuery | 是 | -- | -- | 需表达式模拟 | 仅日历边界 `TIMESTAMP_TRUNC`；任意间隔需 `TIMESTAMP_SECONDS(DIV(UNIX_SECONDS(ts),900)*900)` |
| Redshift | 是 | -- | `DATE_BIN` | DATE_BIN | `DATE_BIN(INTERVAL '15 min', ts, '2024-01-01')` |
| DuckDB | 是 | `time_bucket` | `DATE_BIN` | 均支持 | 兼容 TimescaleDB 和 PG 14 语法 |
| ClickHouse | 是 (20.4+) | -- | -- | `toStartOfInterval` | `toStartOfInterval(ts, INTERVAL 15 MINUTE)`；`date_trunc` 为 20.4+ 别名 |
| Trino | 是 | -- | -- | `date_trunc` + 算术 | 仅标准日历边界 |
| Presto | 是 | -- | -- | `date_trunc` + 算术 | 同 Trino |
| Spark SQL | 是 | -- | -- | `window` 函数 | `window(ts, '15 minutes')` 返回 struct |
| Hive | -- | -- | -- | `from_unixtime` 模拟 | 无原生截断函数 |
| Flink SQL | -- | -- | -- | `TUMBLE` 窗口 | 流处理时间窗口，非函数 |
| Databricks | 是 | -- | -- | `window` 函数 | 同 Spark SQL |
| Teradata | -- | -- | -- | `TD_TIMEBUCKET` | 内置分桶函数 |
| Greenplum | 是 | -- | 是 (基于 PG14) | DATE_BIN | 继承 PostgreSQL |
| CockroachDB | 是 | -- | 是 | DATE_BIN | 兼容 PG 14 |
| TiDB | -- | -- | -- | 需表达式 | 兼容 MySQL，无 DATE_TRUNC |
| OceanBase | -- / 是 | -- | -- | 取决于模式 | MySQL 模式无，Oracle 模式有 TRUNC |
| YugabyteDB | 是 | -- | 是 | DATE_BIN | 兼容 PostgreSQL |
| SingleStore | 是 | -- | -- | DATE_TRUNC + 算术 | `DATE_TRUNC('minute', ts)` |
| Vertica | 是 | `TIME_SLICE` | -- | TIME_SLICE | `TIME_SLICE(ts, 15, 'MINUTE')` |
| Impala | 是 | -- | -- | DATE_TRUNC + 算术 | `DATE_TRUNC('hour', ts)` |
| StarRocks | 是 | -- | -- | `date_trunc` | `DATE_TRUNC('minute', ts)` |
| Doris | 是 | -- | -- | `date_trunc` | `DATE_TRUNC(ts, 'minute')` 注意参数顺序 |
| MonetDB | -- | -- | -- | 需算术表达式 | `sys.epoch(ts) / 900 * 900` |
| CrateDB | 是 | -- | -- | `date_trunc` + 算术 | `DATE_TRUNC('hour', ts)` |
| TimescaleDB | 是 | 是 | 是 | time_bucket | **time_bucket 的原创者** |
| QuestDB | 是 | -- | -- | `SAMPLE BY` 子句 | 独特语法：`SAMPLE BY 15m` |
| Exasol | 是 | -- | -- | DATE_TRUNC + 算术 | `DATE_TRUNC('hour', ts)` |
| SAP HANA | -- | -- | -- | `SERIES_GENERATE` | 通过 series 生成分桶 |
| Informix | `TRUNC` | -- | -- | TRUNC + 算术 | 有限支持 |
| Firebird | -- | -- | -- | 需 EXTRACT + 算术 | 无原生支持 |
| H2 | `TRUNCATE` | -- | -- | TRUNCATE + 算术 | `TRUNCATE(ts, 'HH')` |
| HSQLDB | `TRUNC` | -- | -- | 需算术 | 有限支持 |
| Derby | -- | -- | -- | 需 EXTRACT + 算术 | 无原生支持 |
| Amazon Athena | 是 | -- | -- | `date_trunc` + 算术 | 继承 Trino |
| Azure Synapse | -- | -- | -- | `DATEADD+DATEDIFF` | 同 SQL Server |
| Google Spanner | 是 | -- | -- | TIMESTAMP_TRUNC | `TIMESTAMP_TRUNC(ts, HOUR)` |
| Materialize | 是 | -- | 是 | DATE_BIN | 兼容 PostgreSQL |
| RisingWave | 是 | -- | 是 | DATE_BIN / TUMBLE | 支持 PG 语法 + 流窗口 |
| InfluxDB (SQL) | 是 | -- | `DATE_BIN` | DATE_BIN | 基于 DataFusion / Arrow |
| DatabendDB | 是 | -- | -- | `date_trunc` + 算术 | `DATE_TRUNC(HOUR, ts)` |
| Yellowbrick | 是 | -- | -- | DATE_TRUNC + 算术 | 兼容 PostgreSQL |
| Firebolt | 是 | -- | -- | `DATE_TRUNC` + 算术 | `DATE_TRUNC('hour', ts)` |

### 语法对比

```sql
-- 需求: 将时间戳对齐到 15 分钟间隔

-- PostgreSQL 14+ / CockroachDB / YugabyteDB / Materialize / RisingWave / Redshift
SELECT DATE_BIN(INTERVAL '15 minutes', ts, TIMESTAMP '2024-01-01')
FROM readings;

-- TimescaleDB (time_bucket 的发明者)
SELECT time_bucket('15 minutes', ts) FROM readings;
-- 支持偏移: time_bucket('15 minutes', ts, INTERVAL '5 minutes')

-- DuckDB (两种语法均支持)
SELECT time_bucket(INTERVAL '15 minutes', ts) FROM readings;
SELECT DATE_BIN(INTERVAL '15 minutes', ts, TIMESTAMP '2024-01-01') FROM readings;

-- ClickHouse
SELECT toStartOfInterval(ts, INTERVAL 15 MINUTE) FROM readings;
-- 也可: toStartOfFiveMinutes(ts), toStartOfHour(ts) 等预定义函数

-- Snowflake / Vertica
SELECT TIME_SLICE(ts, 15, 'MINUTE') FROM readings;

-- BigQuery (无 TIMESTAMP_BUCKET；日历边界用 TIMESTAMP_TRUNC，任意间隔需手动模拟)
SELECT TIMESTAMP_SECONDS(DIV(UNIX_SECONDS(ts), 900) * 900) AS bucket
FROM readings;
-- 日历对齐: TIMESTAMP_TRUNC(ts, HOUR) 仅支持日历边界

-- QuestDB (独特的 SAMPLE BY 语法)
SELECT ts, avg(temperature)
FROM readings
SAMPLE BY 15m;  -- 直接在查询中指定采样间隔

-- Spark SQL / Databricks
SELECT window(ts, '15 minutes').start AS bucket, avg(temperature)
FROM readings
GROUP BY window(ts, '15 minutes');

-- Flink SQL (流处理窗口)
SELECT TUMBLE_START(ts, INTERVAL '15' MINUTE) AS bucket, AVG(temperature)
FROM readings
GROUP BY TUMBLE(ts, INTERVAL '15' MINUTE);

-- MySQL / MariaDB / TiDB (无原生支持，需表达式模拟)
SELECT FROM_UNIXTIME(FLOOR(UNIX_TIMESTAMP(ts) / 900) * 900) AS bucket,
       AVG(temperature)
FROM readings
GROUP BY bucket;

-- SQL Server / Azure Synapse (DATEADD + DATEDIFF 技巧)
SELECT DATEADD(MINUTE, DATEDIFF(MINUTE, 0, ts) / 15 * 15, 0) AS bucket,
       AVG(temperature)
FROM readings
GROUP BY DATEADD(MINUTE, DATEDIFF(MINUTE, 0, ts) / 15 * 15, 0);

-- Oracle
SELECT TRUNC(ts, 'HH') + FLOOR(EXTRACT(MINUTE FROM ts) / 15) * INTERVAL '15' MINUTE AS bucket,
       AVG(temperature)
FROM readings
GROUP BY TRUNC(ts, 'HH') + FLOOR(EXTRACT(MINUTE FROM ts) / 15) * INTERVAL '15' MINUTE;
```

---

## 2. 间隙填充 (Gap Filling)

时序数据中经常出现缺失的时间点（传感器离线、网络中断等）。间隙填充是在查询结果中自动补充缺失时间桶的能力。

### 支持矩阵

| 引擎 | 原生间隙填充 | 语法 | 替代方案 | 备注 |
|------|------------|------|---------|------|
| TimescaleDB | 是 | `time_bucket_gapfill` | -- | **唯一原生 SQL 函数** |
| QuestDB | 是 | `SAMPLE BY ... FILL` | -- | `FILL(NULL)` / `FILL(PREV)` / `FILL(LINEAR)` |
| InfluxDB (SQL) | 部分 | `DATE_BIN_GAPFILL` | -- | 通过 DataFusion 扩展 |
| CrateDB | -- | -- | `generate_series` + JOIN | 手动方式，非原生间隙填充 |
| Flink SQL | 部分 | TUMBLE 窗口 (需自定义触发器) | -- | TUMBLE 默认不为空窗口发送结果，需自定义触发器实现间隙填充 |
| PostgreSQL | -- | -- | `generate_series` + LEFT JOIN | 需手动构造时间序列 |
| MySQL | -- | -- | 递归 CTE / 应用层 | 8.0+ 可用递归 CTE |
| MariaDB | -- | -- | 递归 CTE / `seq_` 表 | `seq_0_to_99` 序列引擎 |
| SQLite | -- | -- | 递归 CTE | 无 generate_series |
| Oracle | -- | -- | `CONNECT BY LEVEL` | 或递归 CTE |
| SQL Server | -- | -- | 递归 CTE / 数字表 | 传统方案 |
| DB2 | -- | -- | 递归 CTE | `WITH RECURSIVE` |
| Snowflake | -- | -- | `GENERATOR` + `ROW_NUMBER` | `TABLE(GENERATOR(ROWCOUNT => N))` |
| BigQuery | -- | -- | `GENERATE_TIMESTAMP_ARRAY` | 直接生成时间戳数组并 UNNEST |
| Redshift | -- | -- | `generate_series` | 支持 PG 语法 |
| DuckDB | -- | -- | `generate_series` + LEFT JOIN | 同 PostgreSQL 模式 |
| ClickHouse | -- | -- | `arrayJoin + range` | `arrayJoin(range(N))` 生成序列 |
| Trino | -- | -- | `UNNEST(sequence(...))` | `sequence(start, end, INTERVAL)` |
| Presto | -- | -- | `UNNEST(sequence(...))` | 同 Trino |
| Spark SQL | -- | -- | `explode(sequence(...))` | `sequence(start, end, INTERVAL)` |
| Hive | -- | -- | UDF / 应用层 | 无原生方案 |
| Databricks | -- | -- | `explode(sequence(...))` | 同 Spark SQL |
| Teradata | -- | -- | `sys_calendar` 表 | 日历表 JOIN |
| Greenplum | -- | -- | `generate_series` + LEFT JOIN | 继承 PostgreSQL |
| CockroachDB | -- | -- | `generate_series` + LEFT JOIN | 兼容 PG |
| TiDB | -- | -- | 递归 CTE (v5.1+) | 性能有限 |
| OceanBase | -- | -- | 递归 CTE / CONNECT BY | 取决于兼容模式 |
| YugabyteDB | -- | -- | `generate_series` + LEFT JOIN | 兼容 PG |
| SingleStore | -- | -- | 递归 CTE | 8.0+ 支持 |
| Vertica | 是 | `TIMESERIES ... AS` 子句 | -- | **原生 TIMESERIES 子句，自动生成缺失时间点** |
| Impala | -- | -- | 应用层 | 无原生方案 |
| StarRocks | -- | -- | 递归 CTE / 数字表 | 需手动处理 |
| Doris | -- | -- | 递归 CTE / 数字表 | 同 StarRocks |
| MonetDB | -- | -- | `generate_series` + LEFT JOIN | 支持 generate_series |
| Exasol | -- | -- | 递归 CTE | 需手动处理 |
| SAP HANA | -- | -- | `SERIES_GENERATE` | 强大的 series 生成能力 |
| Informix | -- | -- | 递归 CTE | 有限支持 |
| Firebird | -- | -- | 递归 CTE | 有限支持 |
| H2 | -- | -- | `SYSTEM_RANGE` + LEFT JOIN | `SYSTEM_RANGE(1, N)` |
| HSQLDB | -- | -- | 递归 CTE | 有限支持 |
| Derby | -- | -- | 递归 CTE | 性能差 |
| Amazon Athena | -- | -- | `UNNEST(sequence(...))` | 继承 Trino |
| Azure Synapse | -- | -- | 递归 CTE / 数字表 | 同 SQL Server |
| Google Spanner | -- | -- | `GENERATE_TIMESTAMP_ARRAY` | 同 BigQuery |
| Materialize | -- | -- | `generate_series` + LEFT JOIN | 兼容 PG |
| RisingWave | -- | -- | 需应用层 | 流处理引擎 |
| DatabendDB | -- | -- | 递归 CTE | 有限支持 |
| Yellowbrick | -- | -- | `generate_series` + LEFT JOIN | 兼容 PG |
| Firebolt | -- | -- | `generate_series` + LEFT JOIN | 支持 generate_series |

> 注: Vertica 的 `TimeSeries` 子句虽然不是函数级间隙填充，但其 `TIMESERIES ... AS` 语法是一种独特的原生时序分析能力，可自动生成缺失时间点。

### 语法对比

```sql
-- 需求: 按 5 分钟分桶聚合温度，自动填充缺失桶

-- TimescaleDB (原生间隙填充)
SELECT time_bucket_gapfill('5 minutes', ts) AS bucket,
       locf(avg(temperature)) AS temperature  -- LOCF: Last Observation Carried Forward
FROM readings
WHERE ts BETWEEN '2024-01-01' AND '2024-01-02'
GROUP BY bucket
ORDER BY bucket;

-- QuestDB
SELECT ts, avg(temperature) AS temperature
FROM readings
WHERE ts BETWEEN '2024-01-01' AND '2024-01-02'
SAMPLE BY 5m FILL(PREV);
-- FILL 选项: NULL, PREV, LINEAR, 常数值

-- InfluxDB (SQL, 基于 DataFusion)
SELECT DATE_BIN_GAPFILL(INTERVAL '5 minutes', ts) AS bucket,
       LOCF(AVG(temperature)) AS temperature
FROM readings
WHERE ts >= '2024-01-01' AND ts < '2024-01-02'
GROUP BY bucket;

-- PostgreSQL / DuckDB / CockroachDB / YugabyteDB (generate_series + LEFT JOIN)
SELECT gs AS bucket, avg(r.temperature) AS temperature
FROM generate_series(
    '2024-01-01'::timestamp,
    '2024-01-02'::timestamp,
    INTERVAL '5 minutes'
) AS gs
LEFT JOIN readings r
    ON r.ts >= gs AND r.ts < gs + INTERVAL '5 minutes'
GROUP BY gs
ORDER BY gs;

-- BigQuery (GENERATE_TIMESTAMP_ARRAY)
SELECT bucket, AVG(r.temperature) AS temperature
FROM UNNEST(GENERATE_TIMESTAMP_ARRAY(
    TIMESTAMP '2024-01-01', TIMESTAMP '2024-01-02', INTERVAL 5 MINUTE
)) AS bucket
LEFT JOIN readings r
    ON r.ts >= bucket AND r.ts < TIMESTAMP_ADD(bucket, INTERVAL 5 MINUTE)
GROUP BY bucket
ORDER BY bucket;

-- Snowflake (GENERATOR)
WITH time_spine AS (
    SELECT DATEADD(MINUTE, SEQ4() * 5, '2024-01-01'::TIMESTAMP) AS bucket
    FROM TABLE(GENERATOR(ROWCOUNT => 288))  -- 24*60/5 = 288
)
SELECT ts.bucket, AVG(r.temperature) AS temperature
FROM time_spine ts
LEFT JOIN readings r
    ON r.ts >= ts.bucket AND r.ts < DATEADD(MINUTE, 5, ts.bucket)
GROUP BY ts.bucket
ORDER BY ts.bucket;

-- ClickHouse (arrayJoin + range)
WITH toDateTime('2024-01-01') AS start,
     toDateTime('2024-01-02') AS end
SELECT start + INTERVAL number * 5 MINUTE AS bucket,
       avg(r.temperature) AS temperature
FROM numbers(toUInt64(dateDiff('minute', start, end) / 5)) AS n
LEFT JOIN readings r
    ON r.ts >= bucket AND r.ts < bucket + INTERVAL 5 MINUTE
GROUP BY bucket
ORDER BY bucket;

-- Vertica (原生 TimeSeries 子句)
SELECT ts, temperature
FROM readings
TIMESERIES ts AS '5 minutes'
    OVER (ORDER BY reading_time);

-- Trino / Amazon Athena (sequence + UNNEST)
SELECT bucket, AVG(r.temperature) AS temperature
FROM UNNEST(sequence(
    TIMESTAMP '2024-01-01',
    TIMESTAMP '2024-01-02',
    INTERVAL '5' MINUTE
)) AS t(bucket)
LEFT JOIN readings r
    ON r.ts >= bucket AND r.ts < bucket + INTERVAL '5' MINUTE
GROUP BY bucket
ORDER BY bucket;

-- SQL Server / Azure Synapse (递归 CTE)
WITH buckets AS (
    SELECT CAST('2024-01-01' AS DATETIME2) AS bucket
    UNION ALL
    SELECT DATEADD(MINUTE, 5, bucket) FROM buckets
    WHERE bucket < '2024-01-02'
)
SELECT b.bucket, AVG(r.temperature) AS temperature
FROM buckets b
LEFT JOIN readings r
    ON r.ts >= b.bucket AND r.ts < DATEADD(MINUTE, 5, b.bucket)
GROUP BY b.bucket
ORDER BY b.bucket
OPTION (MAXRECURSION 10000);
```

---

## 3. 窗口函数在时序分析中的应用

LAG / LEAD 和滑动窗口帧（ROWS/RANGE BETWEEN）是时序分析的核心工具。窗口函数的基础支持已在 [window-function-advanced-syntax.md](window-function-advanced-syntax.md) 中详细对比，本节聚焦于时序分析的典型用法。

### LAG / LEAD 支持矩阵

| 引擎 | LAG/LEAD | IGNORE NULLS | 默认值参数 | 版本 |
|------|---------|-------------|-----------|------|
| PostgreSQL | 是 | -- | 是（第3参数） | 8.4+ |
| MySQL | 是 | -- | 是（第3参数） | 8.0+ |
| MariaDB | 是 | -- | 是（第3参数） | 10.2+ |
| SQLite | 是 | -- | 是（第3参数） | 3.25+ |
| Oracle | 是 | 是 | 是 | 8i+ |
| SQL Server | 是 | -- | 是 | 2012+ |
| DB2 | 是 | 是 | 是 | 9.7+ |
| Snowflake | 是 | 是 | 是 | GA |
| BigQuery | 是 | 是 | 是 | GA |
| Redshift | 是 | 是 | 是 | GA |
| DuckDB | 是 | 是 | 是 | 0.3+ |
| ClickHouse | 是(21.11+，早期用 lagInFrame/leadInFrame) | -- | -- | 21.11+ |
| Trino | 是 | 是 | 是 | GA |
| Presto | 是 | 是 | 是 | GA |
| Spark SQL | 是 | 是 | 是 | 1.4+ |
| Hive | 是 | -- | 是 | 0.11+ |
| Flink SQL | 是 | -- | 是 | 1.0+ |
| Databricks | 是 | 是 | 是 | GA |
| Teradata | 是 | 是 | -- | 14+ |
| Greenplum | 是 | -- | 是 | 5.0+ |
| CockroachDB | 是 | -- | 是 | 2.0+ |
| TiDB | 是 | -- | 是 | 3.0+ |
| OceanBase | 是 | 是 | 是 | GA |
| YugabyteDB | 是 | -- | 是 | 2.0+ |
| SingleStore | 是 | -- | 是 | 7.0+ |
| Vertica | 是 | 是 | 是 | 7.0+ |
| Impala | 是 | -- | 是 | 2.0+ |
| StarRocks | 是 | -- | 是 | 1.19+ |
| Doris | 是 | -- | 是 | 0.15+ |
| MonetDB | 是 | -- | 是 | Jun2020+ |
| CrateDB | 是 | -- | -- | 4.0+ |
| TimescaleDB | 是 | -- | 是 | 继承 PG |
| QuestDB | 是 | -- | -- | 6.0+ |
| Exasol | 是 | -- | 是 | 6.0+ |
| SAP HANA | 是 | 是 | 是 | 1.0+ |
| Informix | 是 | -- | -- | 12.10+ |
| Firebird | 是 | -- | 是 | 3.0+ |
| H2 | 是 | -- | 是 | 1.4+ |
| HSQLDB | 是 | -- | 是 | 2.3+ |
| Derby | -- | -- | -- | -- |
| Amazon Athena | 是 | 是 | 是 | 继承 Trino |
| Azure Synapse | 是 | -- | 是 | GA |
| Google Spanner | 是 | -- | 是 | GA |
| Materialize | 是 | -- | 是 | GA |
| RisingWave | 是 | -- | 是 | GA |
| InfluxDB (SQL) | 是 | -- | 是 | 3.0+ |
| DatabendDB | 是 | -- | 是 | GA |
| Yellowbrick | 是 | -- | 是 | GA |
| Firebolt | 是 | -- | 是 | GA |

> 注: IGNORE NULLS 对时序分析非常重要——它可以实现 Last Observation Carried Forward (LOCF) 语义，在不支持的引擎中需要额外的子查询或 CTE 来模拟。

### 时序分析典型用法

```sql
-- 1. 计算时间差 (事件间隔)
SELECT ts,
       ts - LAG(ts) OVER (ORDER BY ts) AS time_since_last_event
FROM events;

-- 2. 计算变化率 (同比/环比)
SELECT ts, value,
       value - LAG(value) OVER (ORDER BY ts) AS delta,
       (value - LAG(value) OVER (ORDER BY ts)) / NULLIF(LAG(value) OVER (ORDER BY ts), 0) AS pct_change
FROM metrics;

-- 3. LOCF (Last Observation Carried Forward) — 用于稀疏时序数据
-- 支持 IGNORE NULLS 的引擎 (Oracle, Snowflake, BigQuery, DuckDB, Trino 等):
SELECT ts,
       LAST_VALUE(temperature IGNORE NULLS) OVER (ORDER BY ts ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS filled_temp
FROM readings;

-- 不支持 IGNORE NULLS 的引擎 (PostgreSQL, MySQL, ClickHouse 等):
-- 需要通过分组技巧模拟
WITH groups AS (
    SELECT ts, temperature,
           COUNT(temperature) OVER (ORDER BY ts) AS grp
    FROM readings
)
SELECT ts, MAX(temperature) OVER (PARTITION BY grp ORDER BY ts) AS filled_temp
FROM groups;
```

---

## 4. 移动平均与滑动窗口 (Moving Averages)

### 窗口帧支持矩阵

| 引擎 | ROWS BETWEEN | RANGE BETWEEN | GROUPS BETWEEN | 时间 RANGE | 备注 |
|------|-------------|--------------|---------------|-----------|------|
| PostgreSQL | 是 | 是 | 是 (11+) | 是 | RANGE + INTERVAL |
| MySQL | 是 | 是 | -- | -- | 8.0+，RANGE 仅限数值 |
| MariaDB | 是 | 是 | -- | -- | 10.2+ |
| SQLite | 是 | 是 | 是 | -- | 3.28+ |
| Oracle | 是 | 是 | -- | 是 | RANGE + INTERVAL |
| SQL Server | 是 | 是 | -- | -- | 2012+，RANGE 受限 |
| DB2 | 是 | 是 | -- | 是 | RANGE + INTERVAL |
| Snowflake | 是 | 是 | -- | -- | RANGE 仅限数值 |
| BigQuery | 是 | 是 | -- | -- | RANGE 仅限数值 |
| Redshift | 是 | 是 | -- | -- | RANGE 受限 |
| DuckDB | 是 | 是 | 是 | 是 | RANGE + INTERVAL |
| ClickHouse | 是 | 是 | -- | -- | 22.1+ 增强 |
| Trino | 是 | 是 | 是 | -- | 411+ GROUPS |
| Spark SQL | 是 | 是 | -- | 是 | RANGE + INTERVAL (3.0+) |
| Flink SQL | 是 | 是 | -- | 是 | RANGE + INTERVAL |
| TimescaleDB | 是 | 是 | 是 | 是 | 继承 PG |
| QuestDB | 是 | -- | -- | -- | 有限窗口帧支持 |
| Materialize | 是 | 是 | -- | -- | 继承 PG 子集 |
| RisingWave | 是 | 是 | -- | -- | 继承 PG 子集 |

### 语法对比

```sql
-- 1. 简单移动平均 (SMA): 最近 7 个数据点
SELECT ts, value,
       AVG(value) OVER (ORDER BY ts ROWS BETWEEN 6 PRECEDING AND CURRENT ROW) AS sma_7
FROM readings;
-- 几乎所有支持窗口函数的引擎都支持此语法

-- 2. 基于时间的移动平均: 过去 1 小时
-- PostgreSQL / DuckDB / Oracle / DB2 / Spark SQL / Flink SQL / TimescaleDB
SELECT ts, value,
       AVG(value) OVER (ORDER BY ts RANGE BETWEEN INTERVAL '1 hour' PRECEDING AND CURRENT ROW) AS ma_1h
FROM readings;

-- ClickHouse (窗口函数支持 RANGE INTERVAL)
SELECT ts, value,
       avg(value) OVER (ORDER BY ts RANGE BETWEEN INTERVAL 1 HOUR PRECEDING AND CURRENT ROW) AS ma_1h
FROM readings;

-- MySQL / SQL Server / Snowflake / BigQuery (不支持 RANGE INTERVAL)
-- 需要 ROWS BETWEEN 或自连接模拟
-- 如果数据间隔固定 (每分钟一条)，可用 ROWS:
SELECT ts, value,
       AVG(value) OVER (ORDER BY ts ROWS BETWEEN 59 PRECEDING AND CURRENT ROW) AS ma_1h
FROM readings;  -- 假设每分钟一条数据

-- 3. 指数移动平均 (EMA): 大多数引擎不原生支持，需递归 CTE
-- PostgreSQL / DuckDB 递归 CTE 实现:
WITH RECURSIVE ema AS (
    SELECT ts, value, value AS ema_value, 1 AS rn
    FROM (SELECT ts, value, ROW_NUMBER() OVER (ORDER BY ts) AS rn FROM readings) t
    WHERE rn = 1
    UNION ALL
    SELECT r.ts, r.value,
           0.2 * r.value + 0.8 * ema.ema_value,  -- alpha = 0.2
           ema.rn + 1
    FROM ema
    JOIN (SELECT ts, value, ROW_NUMBER() OVER (ORDER BY ts) AS rn FROM readings) r
        ON r.rn = ema.rn + 1
)
SELECT ts, value, ema_value FROM ema;
```

---

## 5. ASOF JOIN (时序近似匹配)

ASOF JOIN 是时序数据处理中最具特色的 JOIN 变体，详细内容请参见 [asof-join.md](asof-join.md)。此处仅列出支持矩阵概要。

### 支持矩阵

| 引擎 | 原生 ASOF JOIN | 语法 | 备注 |
|------|--------------|------|------|
| DuckDB | 是 | `ASOF JOIN ... ON ... AND ts >= ts` | 完整支持 |
| ClickHouse | 是 | `ASOF JOIN ... ON ... AND ts >= ts` | 18.12+ |
| Snowflake | 是 | `ASOF JOIN ... MATCH_CONDITION(>=)` | 2024 |
| QuestDB | 是 | `ASOF JOIN` / `LT JOIN` / `SPLICE JOIN` | 多种变体 |
| Databricks | 部分 | DataFrame API `asof_join` | SQL 语法不直接支持 |
| Spark SQL | 部分 | DataFrame API | SQL 不直接支持 |
| Trino | 是 | `ASOF JOIN` | 414+ |
| PostgreSQL | -- | LATERAL JOIN 模拟 | 需手动改写 |
| TimescaleDB | -- | LATERAL JOIN 模拟 | 需手动改写 |
| MySQL | -- | 子查询模拟 | 需手动改写 |
| Oracle | -- | LATERAL / 子查询 | 需手动改写 |
| SQL Server | -- | CROSS APPLY | 需手动改写 |
| BigQuery | -- | 窗口函数模拟 | 需手动改写 |
| Redshift | -- | 子查询模拟 | 需手动改写 |
| Flink SQL | -- | 时态表 JOIN (不同语义) | `FOR SYSTEM_TIME AS OF` |
| CrateDB | -- | 子查询模拟 | 需手动改写 |
| 其他引擎 | -- | 需子查询/LATERAL/窗口函数模拟 | -- |

---

## 6. 按时间间隔降采样 (Downsampling)

将高频数据聚合为低频数据是时序处理最常见的操作，通常结合时间分桶 + GROUP BY 实现。

### 支持矩阵

| 引擎 | 降采样方式 | 语法示例 | 备注 |
|------|----------|---------|------|
| TimescaleDB | time_bucket + GROUP BY | `GROUP BY time_bucket('1 hour', ts)` | 最直观 |
| QuestDB | SAMPLE BY | `SAMPLE BY 1h` | 最简洁 |
| InfluxDB (SQL) | DATE_BIN + GROUP BY | `GROUP BY DATE_BIN(INTERVAL '1 hour', ts)` | 标准化 |
| ClickHouse | toStartOfInterval + GROUP BY | `GROUP BY toStartOfInterval(ts, INTERVAL 1 HOUR)` | 高性能 |
| PostgreSQL | DATE_TRUNC / DATE_BIN + GROUP BY | `GROUP BY DATE_TRUNC('hour', ts)` | 标准方式 |
| DuckDB | time_bucket / DATE_BIN + GROUP BY | `GROUP BY time_bucket(INTERVAL '1 hour', ts)` | 兼容多种语法 |
| Snowflake | TIME_SLICE / DATE_TRUNC + GROUP BY | `GROUP BY TIME_SLICE(ts, 1, 'HOUR')` | 灵活 |
| BigQuery | TIMESTAMP_TRUNC (仅日历边界) | `GROUP BY TIMESTAMP_TRUNC(ts, HOUR)` | 任意间隔需 `TIMESTAMP_SECONDS(DIV(UNIX_SECONDS(ts),N)*N)` |
| Spark SQL | window 函数 + GROUP BY | `GROUP BY window(ts, '1 hour')` | 返回 struct |
| Flink SQL | TUMBLE + GROUP BY | `GROUP BY TUMBLE(ts, INTERVAL '1' HOUR)` | 流/批统一 |
| 其他通用引擎 | DATE_TRUNC 或表达式模拟 | 见时间分桶章节 | -- |

### QuestDB 的 SAMPLE BY: 时序降采样的极简语法

```sql
-- QuestDB: 最简洁的时序聚合语法
-- 按 1 小时聚合，支持多种聚合函数
SELECT ts, avg(temperature), max(temperature), min(temperature), count(*)
FROM readings
SAMPLE BY 1h;

-- 支持对齐到日历边界
SELECT ts, avg(temperature)
FROM readings
SAMPLE BY 1d ALIGN TO CALENDAR;

-- 支持时区
SELECT ts, avg(temperature)
FROM readings
SAMPLE BY 1d ALIGN TO CALENDAR TIME ZONE 'Asia/Shanghai';

-- 结合 FILL 实现降采样 + 间隙填充
SELECT ts, avg(temperature)
FROM readings
SAMPLE BY 1h FILL(PREV);
```

---

## 7. 连续聚合 / 物化汇总 (Continuous Aggregates)

连续聚合是预计算时间分桶聚合并自动保持更新的能力，对高频时序数据的查询性能至关重要。

### 支持矩阵

| 引擎 | 连续聚合 | 语法 | 增量更新 | 备注 |
|------|---------|------|---------|------|
| TimescaleDB | 是 | `CREATE MATERIALIZED VIEW ... WITH (timescaledb.continuous)` | 是 | **时序连续聚合的标杆** |
| Materialize | 是 | `CREATE MATERIALIZED VIEW` | 实时增量 | 毫秒级延迟 |
| RisingWave | 是 | `CREATE MATERIALIZED VIEW` | 实时增量 | 流处理引擎 |
| ClickHouse | 部分 | `CREATE MATERIALIZED VIEW ... TO ...` | INSERT 触发 | 只处理新插入数据 |
| Flink SQL | 是 | 持续查询 / `CREATE TABLE AS SELECT` | 实时增量 | 流处理原生能力 |
| StarRocks | 是 | 异步物化视图 | 定期/实时 | 支持自动刷新 |
| Doris | 是 | 异步物化视图 | 定期/实时 | 同 StarRocks |
| QuestDB | -- | 无原生支持 | -- | 需外部调度 |
| InfluxDB (SQL) | -- | 无原生支持 | -- | v2 任务可定期聚合 |
| PostgreSQL | -- | `MATERIALIZED VIEW` + `pg_cron` | 全量刷新 | 无增量刷新 |
| Snowflake | 部分 | `MATERIALIZED VIEW` | 自动增量 | 限制多（仅单表、受限聚合） |
| BigQuery | 部分 | `MATERIALIZED VIEW` | 自动增量 | 支持 GROUP BY 聚合 |
| Redshift | 部分 | `MATERIALIZED VIEW` | 部分增量 | AUTO REFRESH |
| 其他通用引擎 | -- | 手动刷新或定时任务 | -- | 需外部调度 |

### TimescaleDB 连续聚合语法

```sql
-- 创建连续聚合 (TimescaleDB 2.0+)
CREATE MATERIALIZED VIEW readings_hourly
WITH (timescaledb.continuous) AS
SELECT time_bucket('1 hour', ts) AS bucket,
       sensor_id,
       avg(temperature) AS avg_temp,
       max(temperature) AS max_temp,
       min(temperature) AS min_temp,
       count(*) AS num_readings
FROM readings
GROUP BY bucket, sensor_id;

-- 配置自动刷新策略
SELECT add_continuous_aggregate_policy('readings_hourly',
    start_offset    => INTERVAL '3 hours',   -- 刷新起始偏移
    end_offset      => INTERVAL '1 hour',    -- 刷新结束偏移
    schedule_interval => INTERVAL '1 hour'   -- 刷新频率
);

-- 分层聚合: 小时 → 天
CREATE MATERIALIZED VIEW readings_daily
WITH (timescaledb.continuous) AS
SELECT time_bucket('1 day', bucket) AS bucket,
       sensor_id,
       avg(avg_temp) AS avg_temp,
       max(max_temp) AS max_temp,
       min(min_temp) AS min_temp,
       sum(num_readings) AS num_readings
FROM readings_hourly
GROUP BY 1, 2;

-- 查询连续聚合 (与普通视图无异)
SELECT * FROM readings_hourly
WHERE bucket >= NOW() - INTERVAL '7 days'
AND sensor_id = 'sensor-001';
```

---

## 8. 数据保留策略 (Retention Policies)

时序数据的生命周期管理——自动删除过期数据——是专用时序引擎的重要能力。

### 支持矩阵

| 引擎 | 原生保留策略 | 实现方式 | 自动执行 | 备注 |
|------|------------|---------|---------|------|
| TimescaleDB | 是 | `add_retention_policy` | 是 (后台作业) | 基于 chunk 级别删除，极高效 |
| QuestDB | 是 | `ALTER TABLE ... DROP PARTITION` | 手动/脚本调度 | 按分区删除过期数据 |
| InfluxDB | 是 | 保留策略 (retention policy) | 是 | v1 原生概念，v2/v3 通过 bucket 配置 |
| ClickHouse | 是 | `TTL` 表达式 | 是 (后台合并) | `TTL ts + INTERVAL 30 DAY` |
| CrateDB | 是 | 分区 + 策略 | 部分 | 需配合分区表 |
| Cassandra (CQL) | 是 | `TTL` 列级/行级 | 是 (compaction) | 行级 TTL |
| PostgreSQL | -- | 分区 + DROP / pg_partman | 需外部调度 | `DROP PARTITION` 高效 |
| MySQL | -- | 分区 + DROP / EVENT | 需 EVENT 调度 | 分区级 DROP |
| MariaDB | -- | 分区 + DROP / EVENT | 需 EVENT 调度 | 同 MySQL |
| Oracle | -- | 分区 + ILM (Information Lifecycle Mgmt) | 部分自动 | 企业级 ILM |
| SQL Server | -- | 分区 + SQL Agent | 需 Agent 作业 | 滑动窗口模式 |
| Snowflake | -- | TIME_TRAVEL 保留 + 任务 | 需 TASK 调度 | 默认 1-90 天 Time Travel |
| BigQuery | -- | 表/分区过期 | 是 | `expiration_timestamp` / 分区过期 |
| Redshift | -- | 无原生保留 | 需外部 | 需手动 DELETE/VACUUM |
| DuckDB | -- | 无 | -- | 嵌入式，无后台作业 |
| Flink SQL | -- | 状态 TTL | 是 | 流处理状态保留 |
| Spark SQL | -- | 无原生保留 | 需外部 | 通过 Delta Lake vacuum |
| Databricks | -- | Delta Lake `VACUUM` | 可配置 | `delta.deletedFileRetentionDuration` |
| Teradata | -- | 分区 + Temporal 约束 | 部分 | Temporal Constraint |
| 其他通用引擎 | -- | 分区 + 外部调度 | -- | 需应用层或调度器 |

### 语法对比

```sql
-- TimescaleDB: 声明式保留策略
SELECT add_retention_policy('readings', INTERVAL '30 days');
-- 自动删除 30 天前的数据 (chunk 级别，无需逐行 DELETE)

-- 查看保留策略
SELECT * FROM timescaledb_information.jobs
WHERE proc_name = 'policy_retention';

-- 移除保留策略
SELECT remove_retention_policy('readings');

-- ClickHouse: TTL 表达式 (DDL 级)
CREATE TABLE readings (
    ts DateTime,
    sensor_id String,
    temperature Float64
) ENGINE = MergeTree()
ORDER BY (sensor_id, ts)
TTL ts + INTERVAL 30 DAY;  -- 30 天后自动删除

-- 多级 TTL (热温冷架构)
ALTER TABLE readings
    MODIFY TTL
        ts + INTERVAL 7 DAY TO VOLUME 'warm',     -- 7 天后移至温存储
        ts + INTERVAL 30 DAY TO VOLUME 'cold',     -- 30 天后移至冷存储
        ts + INTERVAL 365 DAY DELETE;               -- 1 年后删除

-- BigQuery: 分区过期
CREATE TABLE readings (
    ts TIMESTAMP,
    sensor_id STRING,
    temperature FLOAT64
)
PARTITION BY DATE(ts)
OPTIONS (
    partition_expiration_days = 30  -- 分区 30 天后自动删除
);

-- PostgreSQL: 分区 + pg_cron (需手动设置)
-- 1. 创建分区表
CREATE TABLE readings (ts TIMESTAMP, sensor_id TEXT, temperature DOUBLE PRECISION)
PARTITION BY RANGE (ts);
-- 2. 定期 DROP 过期分区 (通过 pg_cron 或 pg_partman)
SELECT cron.schedule('retention', '0 * * * *',
    $$DROP TABLE IF EXISTS readings_old_partition$$);
```

---

## 9. 插值函数 (Interpolation)

对缺失的时序数据点进行估值填充，常见方法包括 LOCF（前值填充）和线性插值。

### 支持矩阵

| 引擎 | LOCF | 线性插值 | 语法 | 备注 |
|------|------|---------|------|------|
| TimescaleDB | 是 | 是 | `locf(agg)` / `interpolate(agg)` | 配合 `time_bucket_gapfill` |
| QuestDB | 是 | 是 | `FILL(PREV)` / `FILL(LINEAR)` | 配合 `SAMPLE BY` |
| InfluxDB (SQL) | 是 | -- | `LOCF(agg)` | 配合 `DATE_BIN_GAPFILL` |
| Vertica | 是 | 是 | `TS_FIRST_VALUE` / `TS_LAST_VALUE` | 配合 `TIMESERIES` 子句 |
| SAP HANA | 是 | 是 | `SERIES_GENERATE` + 插值 | 原生 series 处理 |
| CrateDB | -- | -- | 需窗口函数模拟 | 手动实现 |
| PostgreSQL | -- | -- | 窗口函数 + IGNORE NULLS 模拟 | 无 IGNORE NULLS，需分组技巧 |
| DuckDB | -- | -- | 窗口函数 + IGNORE NULLS | 支持 IGNORE NULLS |
| Snowflake | -- | -- | 窗口函数 + IGNORE NULLS | 支持 IGNORE NULLS |
| BigQuery | -- | -- | 窗口函数 + IGNORE NULLS | 支持 IGNORE NULLS |
| Oracle | -- | -- | 窗口函数 + IGNORE NULLS | 最早支持 IGNORE NULLS |
| ClickHouse | -- | -- | 需自定义逻辑 | 无 IGNORE NULLS |
| MySQL | -- | -- | 需复杂子查询 | 无 IGNORE NULLS |
| SQL Server | -- | -- | 窗口函数 (2022+ IGNORE NULLS) | 2022 之前需分组技巧 |
| Flink SQL | -- | -- | 需 UDF | 流处理中不常用 |
| Spark SQL | -- | -- | 窗口函数 + IGNORE NULLS | 支持 IGNORE NULLS |
| Trino | -- | -- | 窗口函数 + IGNORE NULLS | 支持 IGNORE NULLS |
| 其他引擎 | -- | -- | 需手动实现 | 通常通过窗口函数或应用层 |

### 语法对比

```sql
-- TimescaleDB: 原生 LOCF 和线性插值
-- LOCF (Last Observation Carried Forward)
SELECT time_bucket_gapfill('5 minutes', ts) AS bucket,
       locf(avg(temperature)) AS temperature
FROM readings
WHERE ts BETWEEN '2024-01-01' AND '2024-01-02'
GROUP BY bucket;

-- 线性插值
SELECT time_bucket_gapfill('5 minutes', ts) AS bucket,
       interpolate(avg(temperature)) AS temperature
FROM readings
WHERE ts BETWEEN '2024-01-01' AND '2024-01-02'
GROUP BY bucket;

-- QuestDB: FILL 变体
SELECT ts, avg(temperature)
FROM readings
SAMPLE BY 5m FILL(PREV);      -- LOCF

SELECT ts, avg(temperature)
FROM readings
SAMPLE BY 5m FILL(LINEAR);    -- 线性插值

SELECT ts, avg(temperature)
FROM readings
SAMPLE BY 5m FILL(25.0);      -- 常数填充

SELECT ts, avg(temperature)
FROM readings
SAMPLE BY 5m FILL(NULL);      -- 显式 NULL 填充

-- 支持 IGNORE NULLS 的引擎通用 LOCF 模式 (Oracle, Snowflake, BigQuery, DuckDB, Trino, Spark SQL):
SELECT ts, value,
       LAST_VALUE(value IGNORE NULLS) OVER (
           ORDER BY ts
           ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
       ) AS locf_value
FROM readings;

-- 线性插值通用 SQL 实现 (适用于大多数引擎):
WITH bounds AS (
    SELECT ts, value,
           LAST_VALUE(value IGNORE NULLS) OVER (ORDER BY ts ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS prev_val,
           LAST_VALUE(ts) OVER (
               ORDER BY ts
               ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
           ) AS prev_ts,
           FIRST_VALUE(value IGNORE NULLS) OVER (ORDER BY ts ROWS BETWEEN CURRENT ROW AND UNBOUNDED FOLLOWING) AS next_val,
           FIRST_VALUE(ts) OVER (
               ORDER BY ts
               ROWS BETWEEN CURRENT ROW AND UNBOUNDED FOLLOWING
           ) AS next_ts
    FROM readings
)
SELECT ts,
       CASE WHEN value IS NOT NULL THEN value
            ELSE prev_val + (next_val - prev_val) *
                 EXTRACT(EPOCH FROM ts - prev_ts) /
                 NULLIF(EXTRACT(EPOCH FROM next_ts - prev_ts), 0)
       END AS interpolated_value
FROM bounds;
```

---

## 10. 时序相关数据类型 (Time-Series Data Types)

### TIMESTAMP 精度支持

| 引擎 | 最大精度 | 默认精度 | TIMESTAMP WITH TIME ZONE | INTERVAL 类型 | 备注 |
|------|---------|---------|------------------------|-------------|------|
| PostgreSQL | 微秒 (us) | 微秒 | 是 (`TIMESTAMPTZ`) | 是 (完整) | 2 种 INTERVAL |
| MySQL | 微秒 (us) | 秒 | 是 (`TIMESTAMP`) | -- | `DATETIME(6)` 指定精度 |
| MariaDB | 微秒 (us) | 秒 | 是 (`TIMESTAMP`) | -- | 同 MySQL |
| SQLite | 无原生类型 | -- | -- | -- | TEXT/REAL/INTEGER 存储 |
| Oracle | 纳秒 (ns) | 微秒 (6位) | 是 (`TIMESTAMP WITH TIME ZONE`) | 是 (YEAR-MONTH / DAY-SECOND) | `TIMESTAMP(9)` |
| SQL Server | 100 纳秒 | 7 位 | 是 (`DATETIMEOFFSET`) | -- | `DATETIME2(7)` |
| DB2 | 皮秒 (ps) | 微秒 | 是 | 是 | `TIMESTAMP(12)` 最大 |
| Snowflake | 纳秒 (ns) | 纳秒 (9位) | 是 (`TIMESTAMP_TZ`) | -- | 无 INTERVAL 类型 |
| BigQuery | 微秒 (us) | 微秒 | 是 (`TIMESTAMP`) | -- | DATETIME 无时区 |
| Redshift | 微秒 (us) | 微秒 | 是 (`TIMESTAMPTZ`) | 是 | 兼容 PG |
| DuckDB | 微秒 (us) | 微秒 | 是 (`TIMESTAMPTZ`) | 是 | 也有 TIMESTAMP_NS |
| ClickHouse | 纳秒 (ns) | 秒 | 是 (`DateTime64(9)`) | -- | `DateTime64(N)` 指定精度 |
| Trino | 皮秒 (ps) | 毫秒 (3位) | 是 | 是 | `TIMESTAMP(12)` 最大 |
| QuestDB | 微秒 (us) | 微秒 | 是 (隐式 UTC) | -- | 时间戳是核心类型 |
| TimescaleDB | 微秒 (us) | 微秒 | 是 | 是 | 继承 PostgreSQL |
| InfluxDB (SQL) | 纳秒 (ns) | 纳秒 | 是 (隐式 UTC) | 是 | 纳秒是 InfluxDB 核心精度 |
| CrateDB | 毫秒 (ms) | 毫秒 | 是 | -- | TIMESTAMP 内部为 long |
| Spark SQL | 微秒 (us) | 微秒 | -- | 是 | 3.4+ 支持 TIMESTAMP_NTZ |
| Flink SQL | 纳秒 (ns) | 毫秒 | 是 | 是 | `TIMESTAMP(9)` |
| SAP HANA | 100 纳秒 | 100ns | 是 (`TIMESTAMP`) | -- | 7 位精度 |
| Teradata | 微秒 (us) | 微秒 (6位) | 是 (`TIMESTAMP WITH TIME ZONE`) | 是 | `TIMESTAMP(6)` |
| Exasol | 毫秒 (ms) | 毫秒 | -- | 是 | TIMESTAMP 仅 3 位 |
| 其他引擎 | 多数微秒 | 各异 | 多数支持 | 部分支持 | -- |

> 注: 对于高频时序数据（金融 tick 数据、网络包分析），纳秒精度至关重要。支持纳秒的引擎有 Oracle、DB2、Snowflake、ClickHouse、Trino、InfluxDB、Flink SQL。SQL Server 与 SAP HANA 为 100 纳秒精度（7 位），未达真正纳秒。

### INTERVAL 算术

```sql
-- PostgreSQL / DuckDB / TimescaleDB
SELECT ts + INTERVAL '1 hour 30 minutes' FROM readings;
SELECT ts - INTERVAL '7 days' FROM readings;
SELECT ts2 - ts1 AS duration FROM events;  -- 返回 INTERVAL

-- Oracle
SELECT ts + INTERVAL '1' HOUR + INTERVAL '30' MINUTE FROM readings;
SELECT (ts2 - ts1) DAY TO SECOND FROM events;  -- 返回 INTERVAL DAY TO SECOND

-- ClickHouse
SELECT ts + INTERVAL 90 MINUTE FROM readings;
SELECT dateDiff('second', ts1, ts2) AS duration_seconds FROM events;

-- SQL Server
SELECT DATEADD(MINUTE, 90, ts) FROM readings;
SELECT DATEDIFF(SECOND, ts1, ts2) AS duration_seconds FROM events;

-- MySQL
SELECT ts + INTERVAL 90 MINUTE FROM readings;
SELECT TIMESTAMPDIFF(SECOND, ts1, ts2) AS duration_seconds FROM events;
```

---

## 11. 超表 / 时间分区表 (Hypertables / Time-Partitioned Tables)

自动按时间维度分区是时序引擎的核心存储优化。

### 支持矩阵

| 引擎 | 自动时间分区 | 语法 | 分区粒度 | 备注 |
|------|------------|------|---------|------|
| TimescaleDB | 是 | `create_hypertable` | 自动 chunk | **超表概念的原创者**，透明分区 |
| QuestDB | 是 | `CREATE TABLE ... PARTITION BY` | 天/月/年 | `PARTITION BY DAY` |
| InfluxDB | 是 | 自动 | 内部分片 | 完全自动，用户无需配置 |
| ClickHouse | 是 | `PARTITION BY toYYYYMM(ts)` | 表达式指定 | MergeTree 分区 |
| CrateDB | 是 | `PARTITIONED BY` | 表达式指定 | `PARTITIONED BY (date_trunc('month', ts))` |
| PostgreSQL | 部分 | `PARTITION BY RANGE (ts)` | 手动定义 | 10+ 声明式分区，需手动建子表 |
| MySQL | 部分 | `PARTITION BY RANGE (ts)` | 手动定义 | 需手动管理分区 |
| MariaDB | 部分 | `PARTITION BY RANGE (ts)` | 手动定义 | 同 MySQL |
| Oracle | 部分 | `PARTITION BY RANGE (ts)` / 自动 | 手动或间隔 | **INTERVAL 分区**自动扩展 |
| SQL Server | 部分 | 分区函数 + 分区方案 | 手动定义 | 需手动管理 |
| DB2 | 部分 | `PARTITION BY RANGE (ts)` | 手动定义 | 范围分区 |
| Snowflake | 自动 | 自动微分区 (micro-partitions) | 自动 | 基于插入顺序自动聚类 |
| BigQuery | 部分 | `PARTITION BY DATE(ts)` | 天/小时/月/年 | 需显式声明 |
| Redshift | 部分 | 排序键 (SORTKEY) | 自动范围扫描 | 非传统分区，但排序键优化类似效果 |
| DuckDB | -- | -- | -- | 嵌入式引擎，无分区概念 |
| Trino | -- | 联邦引擎 | -- | 依赖底层存储分区 |
| Spark SQL | 部分 | `PARTITIONED BY` | 目录级 | Hive 风格文件分区 |
| Flink SQL | 部分 | `PARTITIONED BY` | 连接器决定 | 依赖 connector |
| Databricks | 部分 | `PARTITIONED BY` / Z-ORDER | 目录级 | Delta Lake 分区 + 优化 |
| StarRocks | 部分 | `PARTITION BY RANGE (ts)` | 手动或动态 | 动态分区 (3.1+) |
| Doris | 部分 | `PARTITION BY RANGE (ts)` | 手动或动态 | 动态分区策略 |
| Vertica | 自动 | 自动分区 / PARTITION BY | 自动或手动 | 自动范围分区 |
| CockroachDB | 部分 | `PARTITION BY RANGE (ts)` | 手动定义 | 地理感知分区 |
| TiDB | 部分 | `PARTITION BY RANGE (ts)` | 手动定义 | 兼容 MySQL 语法 |
| SAP HANA | 部分 | `PARTITION BY RANGE (ts)` | 手动定义 | 支持多级分区 |
| SingleStore | 部分 | `PARTITION BY RANGE (ts)` | 手动定义 | columnstore + 排序键 |
| Greenplum | 部分 | `PARTITION BY RANGE (ts)` | 手动定义 | 继承 PG 分区 |
| Teradata | 部分 | `PARTITION BY RANGE_N (ts)` | 手动定义 | 专用分区语法 |
| Exasol | -- | -- | -- | 自动分布 |
| 其他小型引擎 | -- | -- | -- | 多数不支持分区 |

### 语法对比

```sql
-- TimescaleDB: 超表 (最透明的时序分区)
-- 1. 创建普通表
CREATE TABLE readings (
    ts TIMESTAMPTZ NOT NULL,
    sensor_id TEXT NOT NULL,
    temperature DOUBLE PRECISION,
    humidity DOUBLE PRECISION
);
-- 2. 转换为超表 (自动按时间分 chunk)
SELECT create_hypertable('readings', 'ts');
-- 可选: 指定 chunk 间隔
SELECT create_hypertable('readings', 'ts', chunk_time_interval => INTERVAL '1 day');
-- 之后的 INSERT/SELECT 操作完全透明，与普通表无异

-- QuestDB: 建表即分区
CREATE TABLE readings (
    ts TIMESTAMP,
    sensor_id SYMBOL,   -- SYMBOL: QuestDB 特有的字典编码类型
    temperature DOUBLE,
    humidity DOUBLE
) TIMESTAMP(ts) PARTITION BY DAY WAL;
-- TIMESTAMP(ts): 声明时间列
-- PARTITION BY DAY: 按天分区
-- WAL: Write-Ahead Log 模式

-- ClickHouse: MergeTree 分区
CREATE TABLE readings (
    ts DateTime,
    sensor_id String,
    temperature Float64,
    humidity Float64
) ENGINE = MergeTree()
PARTITION BY toYYYYMM(ts)
ORDER BY (sensor_id, ts);

-- Oracle: INTERVAL 分区 (自动扩展)
CREATE TABLE readings (
    ts TIMESTAMP NOT NULL,
    sensor_id VARCHAR2(50),
    temperature NUMBER
)
PARTITION BY RANGE (ts)
INTERVAL (NUMTODSINTERVAL(1, 'DAY'))
(PARTITION p_init VALUES LESS THAN (TIMESTAMP '2024-01-01 00:00:00'));
-- 新数据插入时自动创建分区

-- BigQuery: 分区表
CREATE TABLE readings (
    ts TIMESTAMP,
    sensor_id STRING,
    temperature FLOAT64
)
PARTITION BY DATE(ts)
OPTIONS (
    require_partition_filter = TRUE,  -- 强制查询必须包含分区过滤
    partition_expiration_days = 365
);

-- PostgreSQL 10+: 声明式分区 (需手动建子表)
CREATE TABLE readings (
    ts TIMESTAMPTZ NOT NULL,
    sensor_id TEXT,
    temperature DOUBLE PRECISION
) PARTITION BY RANGE (ts);

CREATE TABLE readings_2024_01 PARTITION OF readings
    FOR VALUES FROM ('2024-01-01') TO ('2024-02-01');
CREATE TABLE readings_2024_02 PARTITION OF readings
    FOR VALUES FROM ('2024-02-01') TO ('2024-03-01');
-- 需用 pg_partman 扩展来自动管理分区生命周期
```

---

## 12. 时序存储优化 (列式存储与压缩)

### 支持矩阵

| 引擎 | 列式存储 | 时序压缩 | 压缩算法 | 压缩比 (典型) | 备注 |
|------|---------|---------|---------|-------------|------|
| TimescaleDB | 是 (压缩后) | 原生 | Gorilla (浮点), Delta-delta (时间戳), LZ4/ZSTD | 10-20x | `ALTER TABLE ... SET (compress)` |
| QuestDB | 是 | 原生 | 自适应 | 5-15x | 列式 + 时间排序 |
| InfluxDB | 是 | 原生 | Gorilla, RLE, Delta, Simple8b | 10-100x | IOx (v3) 基于 Arrow/Parquet |
| ClickHouse | 是 | 原生 | LZ4/ZSTD + Delta/DoubleDelta/Gorilla/T64 | 10-40x | 细粒度列级编码 |
| CrateDB | 是 | 原生 | Lucene 编码 | 5-10x | 基于 Lucene 存储 |
| DuckDB | 是 | 原生 | 多种轻量级编码 | 5-20x | Parquet 原生支持 |
| Snowflake | 是 | 自动 | 专有 | 高 | 自动微分区 + 压缩 |
| BigQuery | 是 | 自动 | Capacitor 格式 | 高 | 完全托管 |
| Redshift | 是 | 自动/手动 | AZ64, LZO, ZSTD, Delta 等 | 3-10x | `ENCODE` 指定编码 |
| Vertica | 是 | 原生 | RLE, Delta, LZO 等 | 5-15x | 列式先驱 |
| StarRocks | 是 | 原生 | LZ4, ZSTD, ZLIB | 5-10x | 列式 OLAP |
| Doris | 是 | 原生 | LZ4, ZSTD, ZLIB | 5-10x | 同 StarRocks |
| SingleStore | 是 | 原生 (columnstore) | 多种 | 5-10x | 行列混合存储 |
| SAP HANA | 是 | 原生 | 字典, RLE, 位压缩 | 5-15x | 内存列存 |
| Teradata | 部分 | 块级 | 块级压缩 | 3-5x | 行存为主 |
| PostgreSQL | -- | -- | TOAST 压缩 | 有限 | 行存引擎，无列式原生支持 |
| MySQL | -- | 页级 | InnoDB 页压缩 | 2-3x | 行存引擎 |
| Oracle | 部分 | HCC (Exadata) | Hybrid Columnar | 10-50x (HCC) | 企业级高级压缩 |
| SQL Server | 部分 | 列存储索引 | 列级压缩 | 5-10x | Columnstore Index |
| Spark SQL | 是 (Parquet) | Parquet 原生 | Snappy, GZIP, ZSTD | 5-15x | 依赖文件格式 |
| Flink SQL | -- | 依赖 connector | -- | -- | 流处理引擎 |
| Materialize | -- | 内存 | -- | -- | 内存中维护 |

### TimescaleDB 压缩配置

```sql
-- 启用原生压缩 (TimescaleDB)
ALTER TABLE readings SET (
    timescaledb.compress,
    timescaledb.compress_segmentby = 'sensor_id',     -- 按 sensor_id 分段
    timescaledb.compress_orderby = 'ts DESC'          -- 按时间降序排列
);

-- 添加自动压缩策略: 7 天前的数据自动压缩
SELECT add_compression_policy('readings', INTERVAL '7 days');

-- 手动压缩特定 chunk
SELECT compress_chunk(c) FROM show_chunks('readings', older_than => INTERVAL '7 days') c;

-- 查看压缩效果
SELECT
    pg_size_pretty(before_compression_total_bytes) AS before,
    pg_size_pretty(after_compression_total_bytes) AS after,
    round(before_compression_total_bytes::numeric /
          NULLIF(after_compression_total_bytes, 0), 1) AS ratio
FROM hypertable_compression_stats('readings');
-- 典型结果: before=10GB, after=600MB, ratio=16.7

-- ClickHouse 列级压缩编码
CREATE TABLE readings (
    ts DateTime CODEC(DoubleDelta, LZ4),           -- 时间戳: DoubleDelta 编码
    sensor_id LowCardinality(String),               -- 低基数字符串字典编码
    temperature Float64 CODEC(Gorilla, LZ4),        -- 浮点数: Gorilla 编码
    humidity Float64 CODEC(Gorilla, LZ4)
) ENGINE = MergeTree()
PARTITION BY toYYYYMM(ts)
ORDER BY (sensor_id, ts);
```

---

## 13. 各引擎时序处理详细语法

### TimescaleDB — 通用关系型数据库上最完整的时序扩展

TimescaleDB 是 PostgreSQL 的扩展，在完全兼容 PostgreSQL SQL 的基础上增加了超表、连续聚合、压缩、保留策略等时序专用能力。

```sql
-- 完整时序分析流水线示例
-- 1. 建表 + 超表
CREATE TABLE sensor_data (
    ts TIMESTAMPTZ NOT NULL,
    sensor_id TEXT NOT NULL,
    temperature DOUBLE PRECISION,
    humidity DOUBLE PRECISION,
    battery_pct DOUBLE PRECISION
);
SELECT create_hypertable('sensor_data', 'ts',
    chunk_time_interval => INTERVAL '1 day');

-- 2. 压缩策略
ALTER TABLE sensor_data SET (
    timescaledb.compress,
    timescaledb.compress_segmentby = 'sensor_id',
    timescaledb.compress_orderby = 'ts DESC'
);
SELECT add_compression_policy('sensor_data', INTERVAL '7 days');

-- 3. 保留策略
SELECT add_retention_policy('sensor_data', INTERVAL '90 days');

-- 4. 连续聚合 (实时分钟级 → 小时级)
CREATE MATERIALIZED VIEW sensor_hourly
WITH (timescaledb.continuous) AS
SELECT time_bucket('1 hour', ts) AS bucket,
       sensor_id,
       avg(temperature) AS avg_temp,
       max(temperature) AS max_temp,
       min(temperature) AS min_temp,
       avg(humidity) AS avg_humidity,
       avg(battery_pct) AS avg_battery
FROM sensor_data
GROUP BY bucket, sensor_id;

SELECT add_continuous_aggregate_policy('sensor_hourly',
    start_offset => INTERVAL '3 hours',
    end_offset => INTERVAL '1 hour',
    schedule_interval => INTERVAL '1 hour');

-- 5. 时序分析查询
-- 按 15 分钟分桶 + 间隙填充 + LOCF
SELECT time_bucket_gapfill('15 minutes', ts) AS bucket,
       sensor_id,
       locf(avg(temperature)) AS temperature,
       interpolate(avg(humidity)) AS humidity
FROM sensor_data
WHERE ts BETWEEN NOW() - INTERVAL '24 hours' AND NOW()
  AND sensor_id = 'sensor-001'
GROUP BY bucket, sensor_id
ORDER BY bucket;

-- 6. 移动平均
SELECT ts, temperature,
       avg(temperature) OVER (
           PARTITION BY sensor_id
           ORDER BY ts
           RANGE BETWEEN INTERVAL '1 hour' PRECEDING AND CURRENT ROW
       ) AS ma_1h
FROM sensor_data
WHERE sensor_id = 'sensor-001';

-- 7. 异常检测 (超出 3 倍标准差)
WITH stats AS (
    SELECT sensor_id,
           avg(temperature) AS mean,
           stddev(temperature) AS sd
    FROM sensor_data
    WHERE ts > NOW() - INTERVAL '7 days'
    GROUP BY sensor_id
)
SELECT d.ts, d.sensor_id, d.temperature,
       ABS(d.temperature - s.mean) / NULLIF(s.sd, 0) AS z_score
FROM sensor_data d
JOIN stats s ON d.sensor_id = s.sensor_id
WHERE ABS(d.temperature - s.mean) > 3 * s.sd
  AND d.ts > NOW() - INTERVAL '24 hours';
```

### QuestDB — 为时序而生的 SQL 引擎

```sql
-- QuestDB 特有语法

-- SAMPLE BY: 时间聚合的核心语法
SELECT ts, sensor_id,
       avg(temperature), max(temperature), min(temperature),
       count()
FROM sensor_data
WHERE ts IN '2024-01-01'     -- QuestDB 特有的时间过滤语法
SAMPLE BY 1h
FILL(PREV)                   -- 间隙填充
ALIGN TO CALENDAR WITH OFFSET '00:00';

-- LATEST ON: 每个分组的最新值 (QuestDB 特有)
SELECT * FROM sensor_data
LATEST ON ts PARTITION BY sensor_id;
-- 等效于: 每个 sensor_id 的最新一条记录
-- 比 ROW_NUMBER() + WHERE rn = 1 高效得多

-- WHERE ... IN 时间范围 (QuestDB 特有简写)
SELECT * FROM sensor_data
WHERE ts IN '2024-01';           -- 整个一月
SELECT * FROM sensor_data
WHERE ts IN '2024-01-15T10';     -- 1月15日10点整个小时

-- ASOF JOIN (QuestDB 原生)
SELECT * FROM trades
ASOF JOIN quotes ON (symbol);

-- LT JOIN (严格小于的 ASOF)
SELECT * FROM trades
LT JOIN quotes ON (symbol);

-- DESIGNATED TIMESTAMP
CREATE TABLE trades (
    ts TIMESTAMP,
    symbol SYMBOL,
    price DOUBLE,
    qty INT
) TIMESTAMP(ts) PARTITION BY DAY WAL
DEDUP UPSERT KEYS(ts, symbol);  -- 按 ts+symbol 去重
```

### ClickHouse — 高性能分析引擎的时序能力

```sql
-- ClickHouse 时序分析模式

-- 1. 时间分桶聚合
SELECT toStartOfInterval(ts, INTERVAL 15 MINUTE) AS bucket,
       sensor_id,
       avg(temperature) AS avg_temp,
       quantile(0.95)(temperature) AS p95_temp,   -- 分位数
       count() AS cnt
FROM sensor_data
WHERE ts >= now() - INTERVAL 24 HOUR
GROUP BY bucket, sensor_id
ORDER BY bucket;

-- 2. 预定义时间截断函数 (ClickHouse 独有)
SELECT toStartOfMinute(ts),      -- 分钟
       toStartOfFiveMinutes(ts), -- 5 分钟
       toStartOfFifteenMinutes(ts), -- 15 分钟
       toStartOfHour(ts),        -- 小时
       toStartOfDay(ts),         -- 天
       toStartOfWeek(ts),        -- 周
       toStartOfMonth(ts),       -- 月
       toStartOfQuarter(ts),     -- 季度
       toStartOfYear(ts)         -- 年
FROM sensor_data LIMIT 1;

-- 3. 物化视图自动聚合 (INSERT 触发)
CREATE MATERIALIZED VIEW sensor_hourly_mv
ENGINE = AggregatingMergeTree()
PARTITION BY toYYYYMM(bucket)
ORDER BY (sensor_id, bucket)
AS SELECT
    toStartOfHour(ts) AS bucket,
    sensor_id,
    avgState(temperature) AS avg_temp,
    maxState(temperature) AS max_temp,
    minState(temperature) AS min_temp,
    countState() AS cnt
FROM sensor_data
GROUP BY bucket, sensor_id;

-- 查询聚合视图
SELECT bucket, sensor_id,
       avgMerge(avg_temp) AS avg_temp,
       maxMerge(max_temp) AS max_temp
FROM sensor_hourly_mv
WHERE bucket >= now() - INTERVAL 7 DAY
GROUP BY bucket, sensor_id;

-- 4. TTL 数据保留
ALTER TABLE sensor_data MODIFY TTL ts + INTERVAL 90 DAY;

-- 5. 列级压缩编码
ALTER TABLE sensor_data
    MODIFY COLUMN ts CODEC(DoubleDelta, LZ4),
    MODIFY COLUMN temperature CODEC(Gorilla, LZ4);
```

### Flink SQL — 流处理引擎的时序窗口

```sql
-- Flink SQL: 流处理时间窗口

-- TUMBLE 窗口 (固定窗口, 无重叠)
SELECT
    TUMBLE_START(ts, INTERVAL '15' MINUTE) AS window_start,
    TUMBLE_END(ts, INTERVAL '15' MINUTE) AS window_end,
    sensor_id,
    AVG(temperature) AS avg_temp,
    COUNT(*) AS cnt
FROM sensor_data
GROUP BY TUMBLE(ts, INTERVAL '15' MINUTE), sensor_id;

-- HOP 窗口 (滑动窗口)
-- 窗口大小 1 小时, 每 15 分钟滑动一次
SELECT
    HOP_START(ts, INTERVAL '15' MINUTE, INTERVAL '1' HOUR) AS window_start,
    sensor_id,
    AVG(temperature) AS avg_temp
FROM sensor_data
GROUP BY HOP(ts, INTERVAL '15' MINUTE, INTERVAL '1' HOUR), sensor_id;

-- CUMULATE 窗口 (累积窗口, Flink 1.13+)
-- 从每小时零分开始, 每 15 分钟扩展一次, 最大 1 小时
SELECT
    CUMULATE_START(ts, INTERVAL '15' MINUTE, INTERVAL '1' HOUR) AS window_start,
    CUMULATE_END(ts, INTERVAL '15' MINUTE, INTERVAL '1' HOUR) AS window_end,
    sensor_id,
    AVG(temperature) AS avg_temp
FROM sensor_data
GROUP BY CUMULATE(ts, INTERVAL '15' MINUTE, INTERVAL '1' HOUR), sensor_id;

-- 时态表 JOIN (Temporal Join)
-- 用最新维度数据关联流数据
SELECT s.ts, s.sensor_id, s.temperature,
       c.location, c.building
FROM sensor_data AS s
JOIN sensor_config FOR SYSTEM_TIME AS OF s.ts AS c
    ON s.sensor_id = c.sensor_id;
```

### BigQuery — 云数仓的时序扩展

```sql
-- BigQuery 时序分析

-- 1. 时间分桶 (BigQuery 无 TIMESTAMP_BUCKET，任意间隔需手动模拟)
SELECT TIMESTAMP_SECONDS(DIV(UNIX_SECONDS(ts), 900) * 900) AS bucket,
       sensor_id,
       AVG(temperature) AS avg_temp,
       APPROX_QUANTILES(temperature, 100)[OFFSET(95)] AS p95_temp
FROM sensor_data
WHERE ts >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 24 HOUR)
GROUP BY bucket, sensor_id;

-- 2. 间隙填充 (GENERATE_TIMESTAMP_ARRAY)
SELECT bucket, AVG(s.temperature) AS avg_temp
FROM UNNEST(GENERATE_TIMESTAMP_ARRAY(
    TIMESTAMP '2024-01-01', TIMESTAMP '2024-01-02', INTERVAL 15 MINUTE
)) AS bucket
LEFT JOIN sensor_data s
    ON s.ts >= bucket AND s.ts < TIMESTAMP_ADD(bucket, INTERVAL 15 MINUTE)
GROUP BY bucket
ORDER BY bucket;

-- 3. LOCF (LAST_VALUE IGNORE NULLS)
SELECT ts, sensor_id,
       LAST_VALUE(temperature IGNORE NULLS) OVER (
           PARTITION BY sensor_id
           ORDER BY ts
           ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
       ) AS filled_temp
FROM sensor_data;

-- 4. 分区表 + 过期
CREATE TABLE sensor_data (
    ts TIMESTAMP,
    sensor_id STRING,
    temperature FLOAT64
)
PARTITION BY DATE(ts)
CLUSTER BY sensor_id
OPTIONS (partition_expiration_days = 365);
```

### Snowflake — 云数仓中最完善的时序支持

```sql
-- Snowflake 时序分析

-- 1. TIME_SLICE 时间分桶
SELECT TIME_SLICE(ts, 15, 'MINUTE') AS bucket,
       sensor_id,
       AVG(temperature) AS avg_temp
FROM sensor_data
GROUP BY bucket, sensor_id;

-- 2. ASOF JOIN (2024 新增)
SELECT t.ts, t.symbol, t.price, q.bid, q.ask
FROM trades t
ASOF JOIN quotes q
    MATCH_CONDITION(t.ts >= q.ts)
    ON t.symbol = q.symbol;

-- 3. 间隙填充 (GENERATOR)
WITH time_spine AS (
    SELECT DATEADD(MINUTE, SEQ4() * 15, '2024-01-01'::TIMESTAMP) AS bucket
    FROM TABLE(GENERATOR(ROWCOUNT => 96))  -- 24 小时 / 15 分钟 = 96
)
SELECT ts.bucket, AVG(s.temperature)
FROM time_spine ts
LEFT JOIN sensor_data s
    ON s.ts >= ts.bucket AND s.ts < DATEADD(MINUTE, 15, ts.bucket)
GROUP BY ts.bucket;

-- 4. LOCF (LAST_VALUE IGNORE NULLS)
SELECT ts, sensor_id,
       LAST_VALUE(temperature IGNORE NULLS) OVER (
           PARTITION BY sensor_id ORDER BY ts
           ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
       ) AS filled_temp
FROM sensor_data;

-- 5. Time Travel (数据版本查询)
SELECT * FROM sensor_data AT(TIMESTAMP => '2024-01-15 10:00:00'::TIMESTAMP);
SELECT * FROM sensor_data AT(OFFSET => -3600);  -- 1 小时前的数据
```

### DuckDB — 嵌入式分析引擎

```sql
-- DuckDB 时序分析 (兼容性最好的嵌入式引擎)

-- 1. time_bucket (兼容 TimescaleDB 语法)
SELECT time_bucket(INTERVAL '15 minutes', ts) AS bucket,
       sensor_id,
       avg(temperature) AS avg_temp,
       quantile_cont(temperature, 0.95) AS p95_temp
FROM sensor_data
GROUP BY bucket, sensor_id;

-- 2. DATE_BIN (兼容 PG 14 语法)
SELECT DATE_BIN(INTERVAL '15 minutes', ts, TIMESTAMP '2024-01-01') AS bucket,
       avg(temperature)
FROM sensor_data
GROUP BY bucket;

-- 3. ASOF JOIN
SELECT t.ts, t.symbol, t.price, q.bid, q.ask
FROM trades t
ASOF JOIN quotes q
    ON t.symbol = q.symbol
    AND t.ts >= q.ts;

-- 4. RANGE BETWEEN INTERVAL (基于时间的移动平均)
SELECT ts, temperature,
       avg(temperature) OVER (
           ORDER BY ts
           RANGE BETWEEN INTERVAL '1 hour' PRECEDING AND CURRENT ROW
       ) AS ma_1h
FROM sensor_data;

-- 5. generate_series 间隙填充
SELECT gs AS bucket, avg(s.temperature)
FROM generate_series(
    TIMESTAMP '2024-01-01',
    TIMESTAMP '2024-01-02',
    INTERVAL '15 minutes'
) AS t(gs)
LEFT JOIN sensor_data s
    ON s.ts >= gs AND s.ts < gs + INTERVAL '15 minutes'
GROUP BY gs;

-- 6. 直接查询 Parquet 文件 (时序数据归档)
SELECT time_bucket(INTERVAL '1 hour', ts) AS bucket,
       avg(temperature)
FROM read_parquet('s3://bucket/sensor_data/*.parquet')
WHERE ts >= '2024-01-01'
GROUP BY bucket;
```

### InfluxDB (SQL) — 时序数据库的 SQL 接口

```sql
-- InfluxDB v3 (IOx) SQL 接口，基于 Apache DataFusion

-- 1. DATE_BIN 时间分桶
SELECT DATE_BIN(INTERVAL '15 minutes', time) AS bucket,
       sensor_id,
       AVG(temperature) AS avg_temp,
       MAX(temperature) AS max_temp
FROM sensor_data
WHERE time >= now() - INTERVAL '24 hours'
GROUP BY bucket, sensor_id
ORDER BY bucket;

-- 2. DATE_BIN_GAPFILL 间隙填充
SELECT DATE_BIN_GAPFILL(INTERVAL '15 minutes', time) AS bucket,
       sensor_id,
       LOCF(AVG(temperature)) AS avg_temp
FROM sensor_data
WHERE time >= '2024-01-01T00:00:00Z' AND time < '2024-01-02T00:00:00Z'
GROUP BY bucket, sensor_id
ORDER BY bucket;

-- 3. 窗口函数
SELECT time, temperature,
       temperature - LAG(temperature) OVER (
           PARTITION BY sensor_id ORDER BY time
       ) AS delta
FROM sensor_data
WHERE time >= now() - INTERVAL '1 hour';
```

---

## 14. 通用引擎 vs 时序专用引擎对比

### 能力矩阵总览

| 能力 | TimescaleDB | QuestDB | InfluxDB | ClickHouse | PostgreSQL | DuckDB | Snowflake | BigQuery | Flink SQL |
|------|------------|---------|----------|-----------|-----------|--------|-----------|---------|----------|
| 时间分桶 | time_bucket (原生) | SAMPLE BY (原生) | DATE_BIN (原生) | toStartOf* (原生) | DATE_TRUNC / DATE_BIN | time_bucket / DATE_BIN | TIME_SLICE | TIMESTAMP_TRUNC (仅日历) | TUMBLE |
| 间隙填充 | time_bucket_gapfill | FILL() | DATE_BIN_GAPFILL | 手动 | 手动 | 手动 | 手动 | 手动 | 窗口语义 |
| 插值 | locf() / interpolate() | FILL(PREV/LINEAR) | LOCF() | 手动 | 手动 | 手动 | 手动 | 手动 | 手动 |
| ASOF JOIN | 手动 (LATERAL) | 原生 | 手动 | 原生 | 手动 | 原生 | 原生 | 手动 | 时态表 JOIN |
| 连续聚合 | 原生 | 无 | 无 | MV (INSERT 触发) | 手动 MV | 无 | 有限 MV | 有限 MV | 持续查询 |
| 保留策略 | 原生 | 分区 DROP | 原生 | TTL | 手动 | 无 | 无 | 分区过期 | 状态 TTL |
| 自动分区 | 超表 (自动) | PARTITION BY (自动) | 自动 | PARTITION BY (手动) | 手动 | 无 | 自动 | 需声明 | 依赖 connector |
| 压缩 | 原生时序压缩 | 原生 | 原生 (Parquet) | 列级编码 | TOAST | 列式 | 自动 | 自动 | N/A |
| LATEST ON | 手动 | 原生 | 手动 | argMax | 手动 | 手动 | 手动 | 手动 | 手动 |

### 设计哲学差异

```
时序专用引擎 (TimescaleDB, QuestDB, InfluxDB):
┌──────────────────────────────────────────────┐
│ 设计目标: 时序数据的最优体验                    │
│ ──────────                                    │
│ • 数据模型假设时间维度始终存在                   │
│ • 存储层为时序数据优化 (时间排序, 列压缩)         │
│ • 查询层提供时序原语 (分桶, 填充, 插值)           │
│ • 运维层内置生命周期管理 (保留, 压缩, 分层)       │
│                                                │
│ 优势: 开箱即用, 查询简洁, 存储高效               │
│ 劣势: JOIN 能力有限, 事务支持弱, 生态较小         │
│       (TimescaleDB 例外: 完整 PG 兼容)           │
└──────────────────────────────────────────────┘

通用分析引擎 (ClickHouse, DuckDB, Snowflake, BigQuery):
┌──────────────────────────────────────────────┐
│ 设计目标: 通用 OLAP, 时序是子场景                │
│ ──────────                                    │
│ • 列式存储天然适合时序数据的压缩和扫描             │
│ • 窗口函数 + DATE_TRUNC 组合可覆盖大部分场景      │
│ • 缺少时序专用语法糖 (间隙填充、插值需手动)        │
│ • 无内置生命周期管理 (ClickHouse TTL 例外)        │
│                                                │
│ 优势: 通用性强, 生态丰富, JOIN/子查询灵活          │
│ 劣势: 时序查询冗长, 间隙填充需大量样板代码          │
└──────────────────────────────────────────────┘

通用 OLTP 引擎 (PostgreSQL, MySQL, SQL Server, Oracle):
┌──────────────────────────────────────────────┐
│ 设计目标: 事务处理, 时序分析为附加能力             │
│ ──────────                                    │
│ • 行存引擎对大范围时序扫描不利                    │
│ • 窗口函数和 DATE_TRUNC 提供基本时序能力          │
│ • 可通过扩展增强 (PG → TimescaleDB)              │
│ • 分区管理需大量手动操作                         │
│                                                │
│ 优势: 事务保证, 完整 SQL, 成熟生态                │
│ 劣势: 大规模时序数据性能差, 运维成本高             │
└──────────────────────────────────────────────┘
```

### 性能特征参考

下表为典型场景的性能量级参考（具体数值因硬件配置、数据规模、查询复杂度而异）：

| 场景 | 时序专用引擎 | 通用 OLAP | 通用 OLTP |
|------|------------|----------|----------|
| 高频写入 (100 万行/秒) | 原生优化 | 批量写入可达 | 通常成为瓶颈 |
| 时间范围扫描 (10 亿行表查 1 天) | 分区剪枝, 毫秒级 | 列式扫描, 秒级 | 索引扫描或全表, 分钟级 |
| 按设备聚合最近 1 小时 | 毫秒~秒级 | 秒级 | 秒~分钟级 |
| 间隙填充 + 插值 | 原生函数, 简单快速 | 需手动 JOIN, 中等 | 需复杂 CTE, 较慢 |
| 存储效率 (1 亿行 IoT 数据) | 10-20x 压缩 | 5-15x 压缩 | 1-3x 压缩 |

---

## 15. 关键发现

**1. 时序 SQL 极度碎片化**: 没有 SQL 标准定义时序处理操作，49 个引擎中没有两个引擎的时间分桶语法完全相同。`DATE_TRUNC` 是最广泛的共同基础，但它仅支持日历边界，不支持任意间隔（如 15 分钟、4 小时）。

**2. 间隙填充是最大的鸿沟**: 仅 TimescaleDB（`time_bucket_gapfill`）、QuestDB（`FILL`）、InfluxDB（`DATE_BIN_GAPFILL`）和 Vertica（`TIMESERIES`）提供原生间隙填充。其他所有引擎都需要 `generate_series` + `LEFT JOIN` 或递归 CTE 的笨重模式，代码量膨胀 5-10 倍。

**3. TimescaleDB 是功能最完整的时序 SQL 方案**: 在 PostgreSQL 基础上增加了 time_bucket、time_bucket_gapfill、locf、interpolate、连续聚合、压缩、保留策略、超表——覆盖了时序处理的全部维度，同时保留完整的 PostgreSQL SQL 兼容性。

**4. QuestDB 的 SAMPLE BY 是最简洁的时序语法**: 用一个 `SAMPLE BY 1h FILL(PREV)` 子句同时完成时间分桶、聚合和间隙填充，其他引擎需要 10-20 行才能达到同样效果。代价是 SQL 兼容性较低。

**5. ClickHouse 的 TTL 是通用引擎中最好的保留策略**: 在 DDL 层声明 `TTL ts + INTERVAL 30 DAY`，后台自动执行，无需外部调度。支持多级 TTL 实现热温冷架构。

**6. IGNORE NULLS 决定了 LOCF 的实现难度**: 支持 `LAST_VALUE(col IGNORE NULLS) OVER (...)` 的引擎（Oracle、Snowflake、BigQuery、DuckDB、Trino、Spark SQL、SQL Server 2022+）可以一行实现 LOCF；不支持的引擎（PostgreSQL、MySQL、ClickHouse）需要复杂的分组窗口技巧。

**7. ASOF JOIN 在加速普及**: 2020 年仅 ClickHouse 和 QuestDB 支持 SQL 原生 ASOF JOIN。到 2025 年，DuckDB、Snowflake、Trino 都已加入支持行列，但 PostgreSQL、MySQL、Oracle、SQL Server 仍需手动模拟。

**8. 流处理引擎走不同路径**: Flink SQL、Materialize、RisingWave 通过 TUMBLE/HOP/CUMULATE 窗口和持续查询实现时序分析，语义模型与批处理引擎截然不同。它们的连续聚合是实时增量的，但受限于流处理的约束（如有限的 JOIN 能力）。

**9. TIMESTAMP 精度差异影响高频场景**: 金融 tick 数据和网络包分析需要纳秒精度，但 PostgreSQL（微秒）、MySQL（微秒，需显式声明）、BigQuery（微秒）、CrateDB（毫秒）、Exasol（毫秒）的精度不足。ClickHouse `DateTime64(9)`、Oracle `TIMESTAMP(9)`、InfluxDB（纳秒）可满足需求。

**10. 引擎选型建议**:
- 已有 PostgreSQL，需要时序能力 → **TimescaleDB**（零迁移成本）
- 超高频写入 + 实时分析 → **QuestDB**（写入性能极致）
- 已有 ClickHouse 分析平台 → 利用 **TTL + MV** 组合
- 云原生 + 托管服务 → **BigQuery** 或 **Snowflake**（功能够用，运维省心）
- 嵌入式分析 / 数据科学 → **DuckDB**（兼容性最好的单机引擎）
- 实时流 + 时序 → **Flink SQL** 或 **RisingWave**
