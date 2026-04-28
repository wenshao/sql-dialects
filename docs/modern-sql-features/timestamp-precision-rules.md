# 时间戳精度与截断规则 (Timestamp Precision and Truncation)

写入 `'2026-04-28 12:34:56.789012345'`，从 PostgreSQL 读出来变成 `12:34:56.789012`，从 Oracle 读出来是 `12:34:56.789012345`，从 SQL Server 读出来是 `12:34:56.7890123`，从 MySQL 读出来是 `12:34:56.789013`——同一个字面量，4 个引擎截掉了不同的位数，还有一个偷偷做了进位。这不是 bug，是 SQL 标准留给实现者的自由度被各家选择了不同的"分钟"。本文系统梳理 45+ 数据库引擎对 `TIMESTAMP(p)` 精度声明、隐式截断 vs 四舍五入、显式 CAST 的规则差异，配套文章见 [`timezone-handling.md`](./timezone-handling.md)（时区语义）和 [`time-series-functions.md`](./time-series-functions.md)（`DATE_TRUNC` 截断到指定单位）。

> 本文聚焦"亚秒精度"的存储与转换语义。`DATE_TRUNC(unit, ts)` 这种**应用层**的时间桶截断（截到分钟、小时、天等），属于时间序列分析话题，单列在 [`time-series-functions.md`](./time-series-functions.md) 中讨论。

## SQL 标准对精度的定义

### SQL:1992 — 引入 TIMESTAMP(p)

SQL:1992 (ISO/IEC 9075:1992) 在 6.1 `<data type>` 中正式定义了带精度参数的时间戳类型：

```sql
TIMESTAMP [ ( <timestamp precision> ) ] [ WITH TIME ZONE ]

<timestamp precision> ::= <unsigned integer>   -- 0 到 9
```

标准的关键规定：

1. **精度范围**：`<timestamp precision>` 取值 0 到 9，表示秒后的小数位数
   - `TIMESTAMP(0)`：精确到秒（无小数）
   - `TIMESTAMP(3)`：精确到毫秒
   - `TIMESTAMP(6)`：精确到微秒
   - `TIMESTAMP(9)`：精确到纳秒
2. **默认精度**：未指定 `(p)` 时默认 6（微秒），等价于 `TIMESTAMP(6)`
3. **隐式赋值**：当源值精度高于目标列声明精度时，**实现自由选择**截断（truncation）或四舍五入（round half to even）
4. **CAST 语义**：`CAST(timestamp_high_p AS TIMESTAMP(low_p))` 同样允许实现自选截断或四舍五入
5. **比较语义**：精度仅影响存储和显示，比较操作把双方提升到较高精度后比较

### SQL:2003 与后续修订

SQL:2003 没有改变精度的范围（仍是 0..9），但对 `EXTRACT(SECOND FROM ts)` 的返回类型做了细化：必须返回 `NUMERIC` 而非整数，以便保留亚秒分量。SQL:2008/2011/2016 维持 0..9 的标准，但**部分实现已超出**——DB2 支持到 12 位（皮秒），Trino 也支持到 12 位。

### 关键术语澄清

- **截断 (Truncation)**：直接丢弃超出精度的低位，例如 `0.789012345` 截到 6 位变成 `0.789012`
- **四舍五入 (Rounding)**：按"四舍六入五成双"（half to even / banker's rounding）或"五入"（half up）规则进位，`0.7890125` 进到 6 位变成 `0.789013` 或 `0.789012`（取决于规则）
- **静默截断 (Silent truncation)**：写入超精度值时不报错，悄悄丢弃低位
- **溢出报错 (Overflow error)**：严格模式下，超精度写入直接拒绝并抛错

## 支持矩阵（综合 45+）

### 1. 最大精度与默认精度

| 引擎 | 类型 | 精度范围 | 默认精度 | 物理粒度 | 引入版本 |
|------|------|---------|---------|---------|---------|
| PostgreSQL | `TIMESTAMP(p)` | 0..6 | 6 | 1 微秒 | 7.0+ |
| MySQL | `DATETIME(p)` / `TIMESTAMP(p)` | 0..6 | 0 | 1 微秒 | 5.6.4+ (2012) |
| MariaDB | `DATETIME(p)` / `TIMESTAMP(p)` | 0..6 | 0 | 1 微秒 | 5.3+ |
| SQLite | `TEXT` / `INTEGER` | 文本 | 文本 | 字符串无固定精度 | -- |
| Oracle | `TIMESTAMP(p)` | 0..9 | 6 | 1 纳秒 | 9i+ |
| SQL Server | `DATETIME2(n)` | 0..7 | 7 | 100 纳秒 | 2008+ |
| SQL Server | `DATETIME` | 固定 | 3 | 3.33 毫秒（1/300 秒） | 2000+ |
| SQL Server | `DATETIMEOFFSET(n)` | 0..7 | 7 | 100 纳秒 | 2008+ |
| DB2 | `TIMESTAMP(p)` | 0..12 | 6 | 1 皮秒 (10^-12 s) | 9.7+ |
| Snowflake | `TIMESTAMP(p)` / `_NTZ` / `_LTZ` / `_TZ` | 0..9 | 9 | 1 纳秒 | GA |
| BigQuery | `TIMESTAMP` / `DATETIME` | 固定 | 6 | 1 微秒 | GA |
| Redshift | `TIMESTAMP(p)` | 固定 6 | 6 | 1 微秒 | GA |
| DuckDB | `TIMESTAMP` / `TIMESTAMP_NS` / `TIMESTAMP_MS` / `TIMESTAMP_S` | 固定档 | 6 (默认) | 1 ns / 1 μs / 1 ms / 1 s | 0.5+ |
| ClickHouse | `DateTime64(p)` | 0..9 | 3 | 10^-p 秒 | GA |
| Trino | `TIMESTAMP(p)` | 0..12 | 3 | 1 皮秒 | 332+ |
| Presto | `TIMESTAMP` | 固定 3 | 3 | 1 毫秒 | GA |
| Spark SQL | `TIMESTAMP` | 固定 6 | 6 | 1 微秒 | 2.0+ |
| Hive | `TIMESTAMP` | 固定 9 | 9 | 1 纳秒 | 0.8+ |
| Flink SQL | `TIMESTAMP(p)` | 0..9 | 6 | 1 纳秒 | 1.10+ |
| Databricks | `TIMESTAMP` | 固定 6 | 6 | 1 微秒 | GA |
| Teradata | `TIMESTAMP(p)` | 0..6 | 6 | 1 微秒 | V2R3+ |
| Greenplum | `TIMESTAMP(p)` | 0..6 | 6 | 1 微秒 | 继承 PG |
| CockroachDB | `TIMESTAMP(p)` | 0..6 | 6 | 1 微秒 | 20.1+ |
| TiDB | `DATETIME(p)` | 0..6 | 0 | 1 微秒 | 兼容 MySQL |
| OceanBase | `TIMESTAMP(p)` (Oracle) / `DATETIME(p)` (MySQL) | 0..9 / 0..6 | 6 / 0 | 模式相关 | GA |
| YugabyteDB | `TIMESTAMP(p)` | 0..6 | 6 | 1 微秒 | 继承 PG |
| SingleStore | `DATETIME(6)` / `TIMESTAMP(6)` | 0 或 6 | 0 | 1 微秒 | 7.0+ |
| Vertica | `TIMESTAMP(p)` | 0..6 | 6 | 1 微秒 | GA |
| Impala | `TIMESTAMP` | 固定 9 | 9 | 1 纳秒 | GA |
| StarRocks | `DATETIME(p)` | 0..6 | 0 | 1 微秒 | 3.0+ |
| Doris | `DATETIME(p)` | 0..6 | 0 | 1 微秒 | 1.2+ |
| MonetDB | `TIMESTAMP(p)` | 0..6 | 6 | 1 微秒 | GA |
| CrateDB | `TIMESTAMP` | 固定 3 | 3 | 1 毫秒 | GA |
| TimescaleDB | `TIMESTAMP(p)` | 0..6 | 6 | 1 微秒 | 继承 PG |
| QuestDB | `TIMESTAMP` | 固定 6 | 6 | 1 微秒 | GA |
| Exasol | `TIMESTAMP` | 固定 3 | 3 | 1 毫秒 | GA |
| SAP HANA | `TIMESTAMP` / `SECONDDATE` | 7 / 0 | 7 / 0 | 100 ns / 1 s | GA |
| Informix | `DATETIME YEAR TO FRACTION(p)` | 0..5 | 3 | 10^-p 秒 | GA |
| Firebird | `TIMESTAMP` | 固定 4 | 4 | 100 微秒 | GA |
| H2 | `TIMESTAMP(p)` | 0..9 | 6 | 1 纳秒 | 1.4+ |
| HSQLDB | `TIMESTAMP(p)` | 0..9 | 6 | 1 纳秒 | 2.0+ |
| Derby | `TIMESTAMP` | 固定 9 | 9 | 1 纳秒 | 10.6+ |
| Amazon Athena | `TIMESTAMP` | 固定 3 | 3 | 1 毫秒（Trino 早期） | 继承 Trino |
| Azure Synapse | `DATETIME2(n)` | 0..7 | 7 | 100 纳秒 | 兼容 SQL Server |
| Google Spanner | `TIMESTAMP` | 固定 9 | 9 | 1 纳秒 | GA |
| Materialize | `TIMESTAMP(p)` | 0..6 | 6 | 1 微秒 | 继承 PG |
| RisingWave | `TIMESTAMP(p)` | 0..6 | 6 | 1 微秒 | 继承 PG |
| InfluxDB (SQL) | `TIMESTAMP` | 固定 9 | 9 | 1 纳秒 | GA |
| Databend | `TIMESTAMP` | 固定 6 | 6 | 1 微秒 | GA |
| Yellowbrick | `TIMESTAMP(p)` | 0..6 | 6 | 1 微秒 | 继承 PG |
| Firebolt | `TIMESTAMP` | 固定 6 | 6 | 1 微秒 | GA |
| MaxCompute | `TIMESTAMP` | 固定 9 | 9 | 1 纳秒 | GA |

> 统计：约 23 个引擎遵循 SQL 标准的 `TIMESTAMP(p)` 0..9 范围（或其子集），约 12 个引擎使用固定精度（不支持参数化），约 4 个超出标准（DB2 12，Trino 12，SQL Server `DATETIME2` 7，SAP HANA 7）。

### 2. 超精度写入行为：截断 vs 四舍五入 vs 报错

| 引擎 | 默认行为 | 严格模式行为 | 半数规则 |
|------|---------|------------|---------|
| PostgreSQL | 四舍五入 | 同左 | half to even（银行家） |
| MySQL | 四舍五入 (5.6.4+) | `STRICT_*` 模式仍四舍五入 | half away from zero |
| MariaDB | 四舍五入 | 同左 | half away from zero |
| Oracle | 截断 | 同左 | -- (truncate, no rounding) |
| SQL Server `DATETIME2` | 四舍五入 | 同左 | half away from zero |
| SQL Server `DATETIME` | 四舍五入到 1/300 秒 | 同左 | "舍入到 .000/.003/.007" |
| DB2 | 截断 | 同左 | -- |
| Snowflake | 截断 | 同左 | -- |
| BigQuery | 截断到微秒 | 同左 | -- |
| Redshift | 截断 | 同左 | -- |
| DuckDB | 截断 | 同左 | -- |
| ClickHouse | 截断 | 同左 | -- |
| Trino | 四舍五入 | 同左 | half up |
| Spark SQL | 截断到微秒 | 同左 | -- |
| Hive | 截断 | 同左 | -- |
| Flink SQL | 四舍五入 | 同左 | half up |
| Teradata | 截断 | 同左 | -- |
| CockroachDB | 四舍五入（继承 PG） | 同左 | half to even |
| TiDB | 四舍五入（继承 MySQL） | 同左 | half away from zero |
| OceanBase | 截断 (Oracle 模式) / 四舍五入 (MySQL 模式) | 同左 | 模式相关 |
| Vertica | 四舍五入 | 同左 | half to even |
| Impala | 截断到纳秒 | 同左 | -- |
| MonetDB | 截断 | 同左 | -- |
| H2 | 四舍五入 | 同左 | half up |
| HSQLDB | 四舍五入 | 同左 | half up |
| Firebird | 截断到 100 微秒 | 同左 | -- |
| SAP HANA | 截断 | 同左 | -- |
| Informix | 截断 | 同左 | -- |

> 关键观察：**关系数据库主流派系分裂明显**——PostgreSQL/MySQL/SQL Server/Vertica/H2/Trino 选择**四舍五入**；Oracle/DB2/Snowflake/BigQuery/Redshift/DuckDB/ClickHouse 选择**截断**。两派各占约一半。

### 3. 显式 CAST 的精度行为

| 引擎 | `CAST(ts AS TIMESTAMP(p))` 是否合法 | 行为 | 报错时机 |
|------|---------------------------------|------|---------|
| PostgreSQL | 是（p 为 0..6） | 四舍五入到 p | 仅当 p > 6 |
| MySQL | 是（p 为 0..6） | 四舍五入 | 仅当 p > 6 |
| Oracle | 是（p 为 0..9） | 截断 | 仅当 p > 9 |
| SQL Server | `CAST(ts AS DATETIME2(n))` n 为 0..7 | 四舍五入 | n > 7 |
| DB2 | 是（p 为 0..12） | 截断 | p > 12 |
| Snowflake | 是（p 为 0..9） | 截断 | p > 9 |
| BigQuery | -- (`TIMESTAMP` 固定) | 不支持参数 | 语法错误 |
| Redshift | -- | 不支持 `TIMESTAMP(p)` | 语法错误 |
| DuckDB | 仅档位（`TIMESTAMP_NS/MS/S`） | 截断 | 不支持任意 p |
| ClickHouse | 是（p 为 0..9） | 截断 | p > 9 |
| Trino | 是（p 为 0..12） | 四舍五入 | p > 12 |
| Spark SQL | -- (`TIMESTAMP` 固定 6) | 不支持参数 | 语法错误 |

### 4. 时区类型的精度

| 引擎 | 不带时区类型精度 | 带时区类型精度 | 是否一致 |
|------|---------------|---------------|---------|
| PostgreSQL | `TIMESTAMP(0..6)` | `TIMESTAMPTZ(0..6)` | 一致 |
| Oracle | `TIMESTAMP(0..9)` | `TIMESTAMP(0..9) WITH [LOCAL] TIME ZONE` | 一致 |
| SQL Server | `DATETIME2(0..7)` | `DATETIMEOFFSET(0..7)` | 一致 |
| DB2 | `TIMESTAMP(0..12)` | `TIMESTAMP(0..12) WITH TIME ZONE` | 一致 |
| Snowflake | `TIMESTAMP_NTZ(0..9)` | `TIMESTAMP_LTZ/TZ(0..9)` | 一致 |
| MySQL | `DATETIME(0..6)` | `TIMESTAMP(0..6)` | 一致 |
| Trino | `TIMESTAMP(0..12)` | `TIMESTAMP(0..12) WITH TIME ZONE` | 一致 |
| ClickHouse | `DateTime64(0..9)` | `DateTime64(0..9, 'TZ')` | 一致 |
| BigQuery | `DATETIME` (μs 固定) | `TIMESTAMP` (μs 固定) | 一致 |

> 几乎所有支持 `WITH TIME ZONE` 的引擎都让两种类型共享相同的精度参数化范围。

### 5. EPOCH/UNIX 时间戳的精度

`UNIX_TIMESTAMP(now)` 或 `EXTRACT(EPOCH FROM ts)` 等函数返回值的精度：

| 引擎 | 函数 | 返回类型 | 亚秒精度 |
|------|------|---------|---------|
| PostgreSQL | `EXTRACT(EPOCH FROM ts)` | `DOUBLE PRECISION` | μs（受 double 精度限制） |
| MySQL | `UNIX_TIMESTAMP(ts)` | `DECIMAL(14,6)` 或 `BIGINT` | μs |
| Oracle | `(ts - epoch_start) * 86400` | `NUMBER` | 9 位（纳秒） |
| SQL Server | `DATEDIFF(SECOND, ...)` | `INT` | 秒（不含亚秒） |
| SQL Server | `DATEDIFF_BIG(NANOSECOND, ...)` | `BIGINT` | 纳秒 |
| ClickHouse | `toUnixTimestamp64Milli/Micro/Nano` | `Int64` | 毫秒/微秒/纳秒 |
| Snowflake | `DATE_PART(EPOCH_NANOSECOND, ts)` | `NUMBER` | 纳秒 |
| BigQuery | `UNIX_MICROS(ts)` | `INT64` | 微秒 |
| Spark SQL | `unix_timestamp(ts)` | `BIGINT` | 秒（不含亚秒） |
| Trino | `to_unixtime(ts)` | `DOUBLE` | μs（受 double 精度限制） |
| DuckDB | `EXTRACT(EPOCH_NS FROM ts)` | `BIGINT` | 纳秒 |

## 各引擎详解

### PostgreSQL：标准 `TIMESTAMP(p)`，0..6，默认 6，四舍五入

PostgreSQL 是 SQL 标准最严格的实现之一，但在最大精度上选择了"够用就好"——只支持到微秒（6 位）。

```sql
-- 类型声明
CREATE TABLE events (
    id BIGSERIAL PRIMARY KEY,
    ts0 TIMESTAMP(0),       -- 精确到秒
    ts3 TIMESTAMP(3),       -- 毫秒
    ts6 TIMESTAMP(6),       -- 微秒（默认）
    ts  TIMESTAMP           -- 等价于 TIMESTAMP(6)
);

-- 写入超精度：四舍五入（half to even）
INSERT INTO events (ts0, ts3, ts6, ts) VALUES
    ('2026-04-28 12:34:56.789012345',
     '2026-04-28 12:34:56.789012345',
     '2026-04-28 12:34:56.789012345',
     '2026-04-28 12:34:56.789012345');

SELECT * FROM events;
-- ts0: 2026-04-28 12:34:57          -- .789... 进位到 +1 秒
-- ts3: 2026-04-28 12:34:56.789       -- .789012345 进到 .789（.789012... < .7895）
-- ts6: 2026-04-28 12:34:56.789012   -- .789012345 进到 .789012（.345 < .5）
-- ts:  2026-04-28 12:34:56.789012   -- 同 ts6

-- 半数规则：half to even
-- .7895 进到 .790（.789 是奇数，向偶进）
-- .7905 进到 .790（.790 是偶数，保留）
SELECT '12:34:56.7895'::TIMESTAMP(3);   -- 12:34:56.790
SELECT '12:34:56.7905'::TIMESTAMP(3);   -- 12:34:56.790

-- 精度超出范围会报错
CREATE TABLE bad (ts TIMESTAMP(7));
-- ERROR: TIMESTAMP(7)(WITH TIME ZONE) precision must not be greater than 6

-- TIMESTAMP 比较时双方提升到 max(p1, p2)
SELECT '12:34:56.789'::TIMESTAMP(3) = '12:34:56.789000'::TIMESTAMP(6);  -- true

-- EXTRACT(EPOCH ...) 返回 double，亚秒位数有限
SELECT EXTRACT(EPOCH FROM TIMESTAMP '2026-04-28 12:34:56.789012');
-- 1777639896.789012   -- 6 位亚秒（受 double 精度影响）
```

**实现内幕**：PostgreSQL 在 `src/backend/utils/adt/timestamp.c` 中将 `TIMESTAMP` 存储为 64 位整数（自 2000-01-01 以来的微秒数），物理粒度 1 微秒。`TIMESTAMP(0..5)` 的截断/进位通过乘除 10 的幂在 SQL 层面完成，存储仍然是 8 字节整数。

### Oracle：`TIMESTAMP(p)`，0..9，默认 6，截断（truncate）

Oracle 是少数支持纳秒精度的"商用王者"，且选择**截断**而非四舍五入——这是 Oracle 与 SQL Server/PostgreSQL 最显著的语义差异之一。

```sql
-- 类型声明
CREATE TABLE events (
    id NUMBER(19) PRIMARY KEY,
    ts0 TIMESTAMP(0),
    ts3 TIMESTAMP(3),
    ts6 TIMESTAMP(6),
    ts9 TIMESTAMP(9),
    ts  TIMESTAMP   -- 等价于 TIMESTAMP(6)
);

-- 写入超精度：截断（不进位）
INSERT INTO events (ts0, ts3, ts6, ts9) VALUES
    (TIMESTAMP '2026-04-28 12:34:56.789012345',
     TIMESTAMP '2026-04-28 12:34:56.789012345',
     TIMESTAMP '2026-04-28 12:34:56.789012345',
     TIMESTAMP '2026-04-28 12:34:56.789012345');

-- 注意：Oracle 的字面量超精度会报错 "ORA-01821: date format not recognized"
-- 推荐方式：使用 TO_TIMESTAMP 或先 CAST
INSERT INTO events (ts3) VALUES
    (CAST(TIMESTAMP '2026-04-28 12:34:56.789012345' AS TIMESTAMP(3)));
-- ts3: 2026-04-28 12:34:56.789   -- 截断 .789012345 → .789（不进位）

-- CAST 显式截断
SELECT CAST(TIMESTAMP '2026-04-28 12:34:56.789999999' AS TIMESTAMP(3))
FROM DUAL;
-- 2026-04-28 12:34:56.789   -- .789999999 截到 3 位 = .789（不变成 .790）

-- 与 PostgreSQL 的关键差异
-- PG:    .789999 截到 3 位 = .790（四舍五入进位）
-- Oracle: .789999 截到 3 位 = .789（直接截断）

-- TIMESTAMP WITH TIME ZONE 与 LOCAL 同样支持 0..9
CREATE TABLE evtz (
    ts TIMESTAMP(9) WITH TIME ZONE,
    lts TIMESTAMP(9) WITH LOCAL TIME ZONE
);

-- 转 EPOCH（Oracle 没有原生函数，需手算）
SELECT (CAST(SYSTIMESTAMP AS DATE) - DATE '1970-01-01') * 86400
FROM DUAL;   -- 仅秒精度

-- 保留亚秒：
SELECT EXTRACT(SECOND FROM SYSTIMESTAMP) FROM DUAL;
-- 56.789012345   -- 数值类型，最多 9 位
```

**实现内幕**：Oracle 内部将 `TIMESTAMP(p)` 存储为 11 字节（年/月/日/时/分/秒 + 4 字节 frac_seconds）；frac_seconds 是 0..999_999_999 的整数（纳秒）。物理粒度始终是 1 纳秒，精度 `p` 仅是显示掩码——存储 `12:34:56.789012345` 到 `TIMESTAMP(3)` 时，在写入路径上做截断后变成 `12:34:56.789000000`（低 6 位强制为 0）。

### SQL Server：`DATETIME2(n)`，0..7，默认 7，四舍五入

SQL Server 是唯一最大精度为 **7**（100 纳秒）的主流引擎——这源于 .NET CLR 的 `DateTime` 类型也是 100 纳秒粒度（"tick"）。

```sql
-- 类型声明
CREATE TABLE Events (
    Id INT IDENTITY PRIMARY KEY,
    Ts0 DATETIME2(0),       -- 精确到秒
    Ts3 DATETIME2(3),       -- 毫秒
    Ts7 DATETIME2(7),       -- 100 纳秒（最大）
    Ts  DATETIME2,          -- 等价于 DATETIME2(7)
    Old DATETIME            -- 老类型，固定 1/300 秒粒度
);

-- 写入超精度：四舍五入（half away from zero）
INSERT INTO Events (Ts3, Ts7) VALUES
    ('2026-04-28 12:34:56.7890125',
     '2026-04-28 12:34:56.78901234567');
SELECT * FROM Events;
-- Ts3: 2026-04-28 12:34:56.789   -- .7890125 → .789（half-away，但 .0125 < .005? 实际进位行为见下）
-- Ts7: 2026-04-28 12:34:56.7890123   -- 截到 7 位

-- 关键：SQL Server 的 DATETIME2 在多数场景下"四舍五入到偶数"（与 PG 类似）
-- 但官方文档措辞为"四舍五入"，无具体规则——实际行为是 round half away from zero
SELECT CAST('2026-04-28 12:34:56.5' AS DATETIME2(0));
-- 2026-04-28 12:34:57   -- 进位

SELECT CAST('2026-04-28 12:34:56.4999999' AS DATETIME2(0));
-- 2026-04-28 12:34:56   -- 不进位

-- DATETIME2(7) 的物理粒度是 100 纳秒（即"7 位整数表示纳秒/100"）
-- 写入 .12345678 → .1234568（第 8 位 8 进位到第 7 位）
SELECT CAST('2026-04-28 12:34:56.12345678' AS DATETIME2(7));
-- 2026-04-28 12:34:56.1234568

-- 老 DATETIME 类型：1/300 秒粒度（即只有 .000 / .003 / .007 三种结尾）
INSERT INTO Events (Old) VALUES ('2026-04-28 12:34:56.999');
SELECT Old FROM Events;
-- 2026-04-28 12:34:57.000   -- .999 round 到 .000（即下一秒），不会保留 .999

-- 写入 .001 / .002 / .004 / .005 ... 都会被映射到最近的合法值
SELECT CAST('2026-04-28 12:34:56.001' AS DATETIME);  -- 2026-04-28 12:34:56.000
SELECT CAST('2026-04-28 12:34:56.002' AS DATETIME);  -- 2026-04-28 12:34:56.003
SELECT CAST('2026-04-28 12:34:56.004' AS DATETIME);  -- 2026-04-28 12:34:56.003
SELECT CAST('2026-04-28 12:34:56.005' AS DATETIME);  -- 2026-04-28 12:34:56.007

-- DATEDIFF_BIG 支持纳秒精度（DATEDIFF 限于 INT）
SELECT DATEDIFF_BIG(NANOSECOND, '2026-04-28', GETDATE());
```

**实现内幕**：`DATETIME2(n)` 物理存储 6-8 字节，精度 7 时使用全 8 字节（3 字节日期 + 5 字节时间）。`DATETIME2(0..2)` 节省 1-2 字节，`DATETIME2(3..4)` 用 7 字节，`DATETIME2(5..7)` 用 8 字节。100 纳秒的"tick"是 .NET `DateTime.Ticks` 的设计延续。

### DB2：`TIMESTAMP(p)`，0..12，默认 6，截断

DB2 是**唯一支持到 12 位（皮秒）精度**的主流商用数据库，远超 SQL 标准的 0..9 范围。

```sql
-- 类型声明
CREATE TABLE EVENTS (
    ID INTEGER NOT NULL PRIMARY KEY,
    TS0 TIMESTAMP(0),
    TS6 TIMESTAMP(6),       -- 默认
    TS9 TIMESTAMP(9),       -- 纳秒
    TS12 TIMESTAMP(12),     -- 皮秒（10^-12 秒）
    TS  TIMESTAMP           -- 等价于 TIMESTAMP(6)
);

-- 写入：截断（不进位）
INSERT INTO EVENTS (TS6, TS12) VALUES
    ('2026-04-28-12.34.56.789012345678901',
     '2026-04-28-12.34.56.789012345678901');
-- TS6:  2026-04-28-12.34.56.789012   （截到 6 位）
-- TS12: 2026-04-28-12.34.56.789012345678   （截到 12 位）

-- 注意 DB2 的字面量分隔符是 '-' 和 '.'，不是 SQL 标准的 ':'
-- 但 ISO 标准格式 'YYYY-MM-DD HH:MM:SS.fff' 也接受

-- CAST 截断
VALUES CAST('2026-04-28-12.34.56.789999999' AS TIMESTAMP(6));
-- 2026-04-28-12.34.56.789999   （截到 6 位，不进位）

-- DB2 9.7+ 引入了可变精度，10.5+ 再扩展到 12
-- 在 9.7 之前，TIMESTAMP 固定 6 位（微秒）

-- TIMESTAMP WITH TIME ZONE（10.1+）同样支持 0..12
CREATE TABLE EVTZ (TS TIMESTAMP(12) WITH TIME ZONE);
```

**实现内幕**：DB2 LUW 的 `TIMESTAMP(p)` 存储长度随 p 变化：
- `TIMESTAMP(0..2)`：7 字节
- `TIMESTAMP(3..4)`：8 字节
- `TIMESTAMP(5..6)`：10 字节（默认）
- `TIMESTAMP(7..9)`：11 字节
- `TIMESTAMP(10..12)`：13 字节

这种"按精度变长"的设计是 DB2 独特的存储节省策略，在 9.7+ 引入。

### MySQL：`DATETIME(p)` / `TIMESTAMP(p)`，0..6，默认 0，四舍五入

MySQL 直到 5.6.4（2012 年）才引入亚秒精度——在此之前所有时间戳都是整秒精度。这是 MySQL 长期落后于 PostgreSQL 的"知名痛点"。

```sql
-- 类型声明
CREATE TABLE events (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    ts0 DATETIME(0),        -- 默认精度（向后兼容）
    ts3 DATETIME(3),
    ts6 DATETIME(6),        -- 微秒（最大）
    ts  DATETIME            -- 等价于 DATETIME(0)，注意默认是 0 而非 6！
);

-- 关键：MySQL 默认精度是 0（整秒），与 PostgreSQL/Oracle/DB2 默认 6 不同！
-- 这是为了向后兼容 5.6.4 之前的行为

-- 写入超精度：四舍五入（half away from zero）
INSERT INTO events (ts0, ts3, ts6) VALUES
    ('2026-04-28 12:34:56.789012345',
     '2026-04-28 12:34:56.789012345',
     '2026-04-28 12:34:56.789012345');

SELECT * FROM events;
-- ts0: 2026-04-28 12:34:57   （进位：.789... > .5）
-- ts3: 2026-04-28 12:34:56.789   （.789012345 → .789）
-- ts6: 2026-04-28 12:34:56.789012   （.789012345 → .789012）

-- 半数规则：half away from zero
SELECT CAST('2026-04-28 12:34:56.5' AS DATETIME(0));  -- 2026-04-28 12:34:57

-- 严格模式（STRICT_TRANS_TABLES / STRICT_ALL_TABLES）
-- 不影响精度截断行为，仅影响其他类型转换
SET sql_mode = 'STRICT_ALL_TABLES';
INSERT INTO events (ts3) VALUES ('2026-04-28 12:34:56.789999999');
-- 仍然成功，ts3 = 2026-04-28 12:34:56.790（四舍五入）

-- 函数 NOW(p) 返回指定精度的当前时间
SELECT NOW(), NOW(3), NOW(6);
-- NOW():  2026-04-28 12:34:56
-- NOW(3): 2026-04-28 12:34:56.789
-- NOW(6): 2026-04-28 12:34:56.789012

-- TIMESTAMP 类型与 DATETIME 类型的精度规则相同（均 0..6）
-- 区别仅在时区语义（TIMESTAMP 是隐式 LOCAL）

-- UNIX_TIMESTAMP 返回亚秒
SELECT UNIX_TIMESTAMP('2026-04-28 12:34:56.789');
-- 1777639896.789   （DECIMAL(14,6) 类型）
```

**实现内幕**：MySQL 5.6.4 引入了 `DATETIME` 的"压缩存储"格式，最多 8 字节（5 字节日期时间 + 0..3 字节亚秒），具体长度按精度：
- `DATETIME(0)`：5 字节
- `DATETIME(1..2)`：6 字节
- `DATETIME(3..4)`：7 字节
- `DATETIME(5..6)`：8 字节

`TIMESTAMP(p)` 类似，但只有 4 字节秒数 + 0..3 字节亚秒（总长 4..7 字节）。

### Snowflake：`TIMESTAMP(p)`，0..9，默认 9，截断

Snowflake 是少数**默认精度为 9**（纳秒）的引擎——这是面向数据仓库工作负载、追求"无损存储原始数据"的设计选择。

```sql
-- 类型声明
CREATE TABLE events (
    id NUMBER PRIMARY KEY,
    ts3 TIMESTAMP(3),
    ts6 TIMESTAMP(6),
    ts9 TIMESTAMP(9),       -- 默认
    ts  TIMESTAMP            -- 等价于 TIMESTAMP_NTZ(9)
);

-- 三种 TIMESTAMP 变体
CREATE TABLE multi (
    ntz TIMESTAMP_NTZ(9),    -- 不带时区
    ltz TIMESTAMP_LTZ(9),    -- 本地时区（按会话 TZ 显示）
    tz  TIMESTAMP_TZ(9)      -- 带原始时区
);

-- 写入超精度：截断（不进位）
INSERT INTO events (ts3, ts9) VALUES
    ('2026-04-28 12:34:56.789999999',
     '2026-04-28 12:34:56.789012345678');

SELECT * FROM events;
-- ts3: 2026-04-28 12:34:56.789   （截断 .789999999 → .789）
-- ts9: 2026-04-28 12:34:56.789012345   （截断到 9 位）

-- 注意：写入超过 9 位的字面量在 Snowflake 会先解析后截断
-- '.789012345678' 12 位 → 解析时先截到 9 位 .789012345 再写入

-- 默认精度 9（与 PG 默认 6 / MySQL 默认 0 不同）
CREATE TABLE evt_default (ts TIMESTAMP);
INSERT INTO evt_default VALUES (CURRENT_TIMESTAMP);
DESCRIBE TABLE evt_default;
-- ts | TIMESTAMP_NTZ(9) | ...    （默认 9）

-- 默认 TIMESTAMP 类型可由会话参数 TIMESTAMP_TYPE_MAPPING 控制
ALTER SESSION SET TIMESTAMP_TYPE_MAPPING = 'TIMESTAMP_LTZ';
CREATE TABLE evt_ltz (ts TIMESTAMP);
DESCRIBE TABLE evt_ltz;
-- ts | TIMESTAMP_LTZ(9) | ...

-- DATE_PART(EPOCH_NANOSECOND, ...) 返回纳秒精度
SELECT DATE_PART('EPOCH_NANOSECOND',
                 '2026-04-28 12:34:56.789012345'::TIMESTAMP);
-- 1777639896789012345

-- CAST 显式精度
SELECT CAST('2026-04-28 12:34:56.789999' AS TIMESTAMP(3));
-- 2026-04-28 12:34:56.789   （截断）
```

**实现内幕**：Snowflake 内部所有 `TIMESTAMP_*` 类型都存储为 `TIMESTAMP_NTZ(9)` + 可选的时区元数据。物理粒度始终是纳秒，精度 `p` 仅在显示和 CAST 时生效。这种"全员纳秒"的设计简化了内部 join/比较逻辑。

### BigQuery：`TIMESTAMP` / `DATETIME` 固定微秒精度

BigQuery 只支持微秒精度（6 位），且**不允许参数化**——这是 Google 在简洁性与统一性之间的取舍。

```sql
-- 类型声明（无 (p) 参数）
CREATE TABLE dataset.events (
    id INT64,
    ts TIMESTAMP,           -- 始终微秒（6 位）
    dt DATETIME             -- 始终微秒
);

-- 写入超精度：截断到微秒（不报错）
INSERT INTO dataset.events VALUES
    (1, TIMESTAMP '2026-04-28 12:34:56.789012345 UTC',
     DATETIME '2026-04-28 12:34:56.789012345');

SELECT * FROM dataset.events;
-- ts: 2026-04-28 12:34:56.789012 UTC   （截到 6 位）
-- dt: 2026-04-28 12:34:56.789012

-- TIMESTAMP(p) 语法不支持
CREATE TABLE bad (ts TIMESTAMP(3));
-- ERROR: Unrecognized name: TIMESTAMP(3)

-- 取微秒/毫秒精度需要显式函数
SELECT TIMESTAMP_MICROS(CAST(UNIX_MICROS(ts) AS INT64)) AS micros,
       TIMESTAMP_MILLIS(CAST(UNIX_MILLIS(ts) AS INT64)) AS millis
FROM dataset.events;

-- 与 Snowflake/Oracle 的差异：BigQuery 无法存储纳秒
-- 纳秒精度数据写入会丢失 3 位（.789012|345 → .789012）

-- TIMESTAMP_TRUNC 截断到指定单位（不是改变精度）
SELECT TIMESTAMP_TRUNC(ts, MICROSECOND) FROM dataset.events;  -- 同 ts
SELECT TIMESTAMP_TRUNC(ts, MILLISECOND) FROM dataset.events;  -- .789000
SELECT TIMESTAMP_TRUNC(ts, SECOND) FROM dataset.events;       -- .000000
```

### ClickHouse：`DateTime64(p)`，0..9，默认 3，截断

ClickHouse 的 `DateTime64` 是面向时间序列分析的设计，精度可参数化但**默认毫秒**（3 位）。

```sql
-- 类型声明
CREATE TABLE events (
    id UInt64,
    ts0 DateTime,           -- 整秒（DateTime 不带 64）
    ts3 DateTime64(3),      -- 毫秒（默认）
    ts6 DateTime64(6),      -- 微秒
    ts9 DateTime64(9),      -- 纳秒（最大）
    ts  DateTime64           -- 等价于 DateTime64(3)
) ENGINE = MergeTree() ORDER BY id;

-- 写入超精度：截断
INSERT INTO events VALUES
    (1, '2026-04-28 12:34:56', '2026-04-28 12:34:56.789999999',
     '2026-04-28 12:34:56.789012999', '2026-04-28 12:34:56.789012345');

SELECT * FROM events;
-- ts0: 2026-04-28 12:34:56
-- ts3: 2026-04-28 12:34:56.789       （截断 .789999999 → .789）
-- ts6: 2026-04-28 12:34:56.789012   （截断）
-- ts9: 2026-04-28 12:34:56.789012345

-- DateTime64(p, 'TZ') 带时区
CREATE TABLE evtz (
    ts DateTime64(9, 'Asia/Shanghai')
) ENGINE = MergeTree() ORDER BY ts;

-- 函数转换
SELECT toDateTime64('2026-04-28 12:34:56.789', 3);  -- DateTime64(3)
SELECT toDateTime64('2026-04-28 12:34:56.789', 6);  -- 微秒（补 0）

-- toUnixTimestamp64Milli/Micro/Nano
SELECT toUnixTimestamp64Nano(toDateTime64('2026-04-28 12:34:56.789012345', 9));
-- 1777639896789012345

-- 注意：DateTime64 物理上存为 Int64
-- 精度 3 时表示毫秒数，精度 9 时表示纳秒数
-- 时间范围会因精度变小（精度 9 时仅能表达 1900-2262）
```

**实现内幕**：ClickHouse 将 `DateTime64(p)` 存为 `Int64`，其值为"自 epoch 起的 10^-p 秒数"。精度 9（纳秒）时 `Int64` 范围是 ±2^63，对应约 ±292 年（1677..2262）；精度 3（毫秒）时可表达约 ±5.85 亿年。

### Trino：`TIMESTAMP(p)`，0..12，默认 3，四舍五入

Trino（原 PrestoSQL）是少数支持到**皮秒精度**（12 位）的查询引擎，且选择**四舍五入**——与 PostgreSQL 一致。

```sql
-- 类型声明
CREATE TABLE events (
    id BIGINT,
    ts3 TIMESTAMP(3),       -- 默认毫秒
    ts6 TIMESTAMP(6),
    ts9 TIMESTAMP(9),
    ts12 TIMESTAMP(12),     -- 皮秒
    ts  TIMESTAMP            -- 等价于 TIMESTAMP(3)
);

-- 写入超精度：四舍五入（half up）
INSERT INTO events VALUES
    (1, TIMESTAMP '2026-04-28 12:34:56.789999',
     TIMESTAMP '2026-04-28 12:34:56.789012',
     TIMESTAMP '2026-04-28 12:34:56.789012345',
     TIMESTAMP '2026-04-28 12:34:56.789012345678');

SELECT * FROM events;
-- ts3:  2026-04-28 12:34:56.790       （四舍五入 .789999 → .790）
-- ts6:  2026-04-28 12:34:56.789012
-- ts9:  2026-04-28 12:34:56.789012345
-- ts12: 2026-04-28 12:34:56.789012345678

-- 注意：早期 Presto / Athena 固定精度为 3（毫秒）
-- Trino 332+ 引入可变精度
-- Trino 类型与 Athena 不完全兼容：Athena V2 引擎仍多为毫秒

-- to_unixtime 返回 double（受精度限制）
SELECT to_unixtime(TIMESTAMP '2026-04-28 12:34:56.789012');
-- 1.777639896789012E9

-- 转纳秒需用专门函数
SELECT to_unixtime_nanos(TIMESTAMP '2026-04-28 12:34:56.789012345');
-- 1777639896789012345
```

### DuckDB：档位化精度（NS / μs / MS / S）

DuckDB 不使用 `TIMESTAMP(p)` 参数化语法，而是提供**4 个独立类型**：

```sql
CREATE TABLE events (
    id BIGINT,
    ts_s   TIMESTAMP_S,     -- 秒粒度（4 字节）
    ts_ms  TIMESTAMP_MS,    -- 毫秒粒度
    ts_us  TIMESTAMP,       -- 默认：微秒（8 字节）
    ts_ns  TIMESTAMP_NS     -- 纳秒粒度
);

-- 写入超精度：截断
INSERT INTO events VALUES
    (1, '2026-04-28 12:34:56.789012345',
     '2026-04-28 12:34:56.789012345',
     '2026-04-28 12:34:56.789012345',
     '2026-04-28 12:34:56.789012345');

SELECT * FROM events;
-- ts_s:  2026-04-28 12:34:56              （截到秒）
-- ts_ms: 2026-04-28 12:34:56.789           （截到毫秒）
-- ts_us: 2026-04-28 12:34:56.789012        （截到微秒）
-- ts_ns: 2026-04-28 12:34:56.789012345     （截到纳秒）

-- 默认 TIMESTAMP 是 TIMESTAMP_US（微秒）
SELECT typeof(NOW());
-- TIMESTAMP WITH TIME ZONE   （即 TIMESTAMPTZ_US）

-- TIMESTAMPTZ 与 TIMESTAMP 的精度档位类似
-- 但 DuckDB 不支持 TIMESTAMPTZ_NS / TIMESTAMPTZ_MS / TIMESTAMPTZ_S
-- TIMESTAMPTZ 始终是微秒

-- EXTRACT(EPOCH_NS ...) 返回纳秒
SELECT EXTRACT(EPOCH_NS FROM TIMESTAMP_NS '2026-04-28 12:34:56.789012345');
-- 1777639896789012345
```

### Spark SQL / Databricks：固定微秒，截断

Spark SQL 将 `TIMESTAMP` 固定为微秒精度（6 位），不支持 `TIMESTAMP(p)` 参数化。

```sql
-- 类型声明（无参数）
CREATE TABLE events (
    id BIGINT,
    ts TIMESTAMP                    -- 固定微秒
);

-- 写入超精度：截断到微秒（多余位被丢弃）
INSERT INTO events VALUES
    (1, TIMESTAMP '2026-04-28 12:34:56.789012345');
-- ts: 2026-04-28 12:34:56.789012   （截到 6 位）

-- TIMESTAMP_NTZ（Spark 3.4+）也是固定微秒
CREATE TABLE evntz (ts TIMESTAMP_NTZ);

-- TIMESTAMP(p) 语法不支持
-- CREATE TABLE bad (ts TIMESTAMP(3));   -- ParseException

-- date_trunc 是 SQL 单位截断（不是精度变更）
SELECT date_trunc('millisecond', ts) FROM events;
-- 仍是 TIMESTAMP，但 .789012 → .789000

-- unix_timestamp 仅秒精度
SELECT unix_timestamp(ts) FROM events;     -- BIGINT，秒
-- 取亚秒需要：
SELECT unix_micros(ts) FROM events;         -- 微秒（Spark 3.1+）
```

### Hive：固定纳秒精度

Hive `TIMESTAMP` 自 0.8 起就支持**纳秒精度**（9 位），但实际可用性受 SerDe 限制。

```sql
-- 类型声明（无参数）
CREATE TABLE events (
    id BIGINT,
    ts TIMESTAMP                    -- 固定纳秒（理论上）
);

-- 写入超精度：截断
INSERT INTO events VALUES
    (1, '2026-04-28 12:34:56.789012345678');
-- ts: 2026-04-28 12:34:56.789012345   （截到 9 位）

-- 文件格式影响实际精度
-- - TextFile / SequenceFile: 字符串解析，全 9 位
-- - ORC: 整数+纳秒分量，全 9 位
-- - Parquet 1.x（旧）: INT96，纳秒
-- - Parquet 2.x（新）: INT64，按 isAdjustedToUTC + unit (ms/us/ns) 决定
```

### 其他引擎（精度细节）

```sql
-- Vertica（PG 后裔，0..6，四舍五入）
CREATE TABLE events (ts TIMESTAMP(3));
INSERT INTO events VALUES ('2026-04-28 12:34:56.789999');
-- ts: 2026-04-28 12:34:56.790   （进位）

-- Teradata（0..6，截断）
CREATE TABLE events (ts TIMESTAMP(6));
-- 默认 6，与 PG 一致

-- CockroachDB（继承 PG，0..6，四舍五入）
CREATE TABLE events (ts TIMESTAMP(3));
INSERT INTO events VALUES ('2026-04-28 12:34:56.789999');
-- ts: 2026-04-28 12:34:56.790

-- TiDB（兼容 MySQL，0..6，四舍五入）
CREATE TABLE events (ts DATETIME(3));
INSERT INTO events VALUES ('2026-04-28 12:34:56.789999');
-- ts: 2026-04-28 12:34:56.790

-- StarRocks / Doris（0..6，截断）
CREATE TABLE events (ts DATETIME(3));
INSERT INTO events VALUES ('2026-04-28 12:34:56.789999');
-- ts: 2026-04-28 12:34:56.789   （截断，不进位）

-- Impala（固定 9，截断）
CREATE TABLE events (ts TIMESTAMP);
-- 始终纳秒，超精度截断

-- SAP HANA（TIMESTAMP 固定 7，SECONDDATE 整秒）
CREATE TABLE events (ts TIMESTAMP);   -- 100ns 粒度
INSERT INTO events VALUES ('2026-04-28 12:34:56.78901234567');
-- ts: 2026-04-28 12:34:56.7890123   （截到 7 位）

-- Firebird（固定 4 位 = 100 微秒）
-- 这是 Firebird 独特的"亚秒为 1/10000 秒"语义
CREATE TABLE events (ts TIMESTAMP);
INSERT INTO events VALUES ('2026-04-28 12:34:56.789012');
-- ts: 2026-04-28 12:34:56.7890   （截到 4 位）

-- H2 / HSQLDB（0..9，四舍五入）
CREATE TABLE events (ts TIMESTAMP(6));
INSERT INTO events VALUES ('2026-04-28 12:34:56.789999');
-- ts: 2026-04-28 12:34:56.790000   （进位）

-- QuestDB（固定微秒 epoch）
CREATE TABLE events (ts TIMESTAMP) timestamp(ts);
-- 内部存为 long，微秒 epoch；写入纳秒会截断

-- InfluxDB SQL（固定纳秒）
-- 时间序列原生设计，所有 TIMESTAMP 都是纳秒精度
```

## 写入溢出 vs CAST 行为对比

### 写入超精度的处理

| 场景 | PostgreSQL | Oracle | SQL Server | DB2 | MySQL | Snowflake |
|------|-----------|--------|-----------|-----|-------|-----------|
| 字面量超精度 | 四舍五入 | 截断 | 四舍五入 | 截断 | 四舍五入 | 截断 |
| 字符串解析超精度 | 四舍五入 | 解析报错（>9 位） | 四舍五入 | 截断 | 四舍五入 | 截断 |
| 类型转换超精度 | 四舍五入 | 截断 | 四舍五入 | 截断 | 四舍五入 | 截断 |
| 半数（如 .5） | 银行家（half-even） | 不适用（截断） | half-away-from-zero | 不适用 | half-away-from-zero | 不适用 |

```sql
-- 测试用例：写入 '12:34:56.7895' 到 TIMESTAMP(3)（半数情况）

-- PostgreSQL: 银行家舍入 → 12:34:56.790（.789 是奇数，向偶进）
-- Oracle:     截断       → 12:34:56.789
-- SQL Server: half-away  → 12:34:56.790
-- MySQL:      half-away  → 12:34:56.790
-- DB2:        截断       → 12:34:56.789
-- Snowflake:  截断       → 12:34:56.789

-- 测试用例：写入 '12:34:56.7905' 到 TIMESTAMP(3)
-- PostgreSQL: 银行家舍入 → 12:34:56.790（.790 是偶数，保留）
-- 与 .7895 进位结果**相同**——这是银行家舍入的核心特征
```

### CAST 与隐式转换行为对比

```sql
-- 显式 CAST：精度变更
-- PostgreSQL
SELECT CAST(TIMESTAMP '2026-04-28 12:34:56.789999' AS TIMESTAMP(3));
-- 2026-04-28 12:34:56.790   （四舍五入）

-- Oracle
SELECT CAST(TIMESTAMP '2026-04-28 12:34:56.789999999' AS TIMESTAMP(3))
FROM DUAL;
-- 2026-04-28 12:34:56.789   （截断）

-- 隐式转换（INSERT 进入低精度列）
-- PostgreSQL: 同 CAST，四舍五入
-- Oracle: 同 CAST，截断
-- SQL Server: 同 CAST，四舍五入
-- DB2: 同 CAST，截断

-- 关键警告：从高精度列读出后插入低精度列
-- PG: 数据可能因进位而"+1 微秒"
-- Oracle/DB2: 数据保持单调递减性（截断不会增大）
-- 这影响了"先聚合后写入"的业务正确性
```

## DATE_TRUNC vs CAST 精度变更

`DATE_TRUNC(unit, ts)` 与 `CAST(ts AS TIMESTAMP(p))` 都能"减少时间戳精度"，但语义完全不同：

```sql
-- 输入: 2026-04-28 12:34:56.789012345

-- DATE_TRUNC: 截断到时间单位边界（清零低位）
SELECT DATE_TRUNC('second', ts) FROM evts;
-- 2026-04-28 12:34:56.000000000   （亚秒全清零）
SELECT DATE_TRUNC('millisecond', ts) FROM evts;
-- 2026-04-28 12:34:56.789000000   （保留毫秒，清零更低）
SELECT DATE_TRUNC('microsecond', ts) FROM evts;
-- 2026-04-28 12:34:56.789012000   （保留微秒，清零纳秒）

-- CAST 到低精度: 改变类型，可能进位（依引擎）
SELECT CAST(ts AS TIMESTAMP(3)) FROM evts;
-- PG/Trino:  2026-04-28 12:34:56.789   （四舍五入：. 012345 < .5，不进位）
-- Oracle/DB2: 2026-04-28 12:34:56.789   （截断）

-- 假设输入 .789999999
SELECT DATE_TRUNC('millisecond', ts);    -- .789（永远不进位）
SELECT CAST(ts AS TIMESTAMP(3));         -- PG: .790（进位）/ Oracle: .789（不进位）

-- 关键差异：
-- DATE_TRUNC: 总是"向下取整"到指定单位，类似 floor()
-- CAST(p):    可能进位（PG/MySQL/SQL Server）或截断（Oracle/DB2/Snowflake）
```

### DATE_TRUNC 的精度参数支持

`DATE_TRUNC(unit, ts)` 中的 `unit` 在不同引擎可指定到何种程度：

| 引擎 | 支持单位 | 亚秒单位 |
|------|---------|---------|
| PostgreSQL | `microseconds`/`milliseconds`/`second`/`minute`/.../`century`/`millennium` | μs / ms |
| Oracle | `MI`/`HH`/`DD`/`MM`/`YYYY` (TRUNC 函数) | -- |
| SQL Server | `DATETRUNC` (2022+) `microsecond`/`millisecond`/.../`year` | μs / ms |
| DB2 | `TRUNC_TIMESTAMP`(..., 'MI'/'HH'/...) | -- |
| Snowflake | `MILLISECOND`/`MICROSECOND`/`NANOSECOND`/.../`YEAR` | ms / μs / ns |
| BigQuery | `TIMESTAMP_TRUNC` `MICROSECOND`/`MILLISECOND`/.../`YEAR` | μs / ms |
| Trino | `date_trunc('millisecond'/'second'/...)` | ms |
| Spark SQL | `date_trunc('MICROSECOND'/'MILLISECOND'/'SECOND'/...)` | μs / ms |
| ClickHouse | `toStartOfXxx` 函数族 | 见 toStartOfNanosecond/Microsecond/Millisecond |
| DuckDB | `date_trunc('microsecond'/...)` | μs / ms / ns |

详见 [`time-series-functions.md`](./time-series-functions.md)。

## 跨引擎写入示例对比

```sql
-- 输入字面量: '2026-04-28 12:34:56.789999999'（9 位亚秒）
-- 目标列: TIMESTAMP(3)（毫秒）

-- 引擎          结果                          规则
-- ---------------------------------------------------------------
-- PostgreSQL    2026-04-28 12:34:56.790        四舍五入（半数 banker's）
-- MySQL         2026-04-28 12:34:56.790        四舍五入（half-away）
-- Oracle        2026-04-28 12:34:56.789        截断
-- SQL Server    2026-04-28 12:34:56.790        四舍五入（half-away）
-- DB2           2026-04-28 12:34:56.789        截断
-- Snowflake     2026-04-28 12:34:56.789        截断
-- BigQuery      不支持 TIMESTAMP(3)            语法错误
-- Redshift      不支持 TIMESTAMP(p)            语法错误（固定 6）
-- DuckDB        TIMESTAMP_MS: .789             截断
-- ClickHouse    DateTime64(3): .789            截断
-- Trino         2026-04-28 12:34:56.790        四舍五入
-- Spark SQL     不支持 TIMESTAMP(3)            语法错误
-- Hive          不支持 TIMESTAMP(3)            语法错误（固定 9）

-- 输入字面量: '2026-04-28 12:34:56.7895'（半数情况）
-- 目标列: TIMESTAMP(3)

-- 引擎          结果                          原因
-- ---------------------------------------------------------------
-- PostgreSQL    .790                           半数向偶（.789 奇数→.790）
-- MySQL         .790                           半数向远离零进位
-- Oracle        .789                           截断
-- SQL Server    .790                           半数向远离零进位
```

## 关键发现

1. **派系分裂**：`TIMESTAMP(p)` 的写入舍入规则两派各占半数——PostgreSQL/MySQL/SQL Server/Trino/Vertica/H2/HSQLDB 选择**四舍五入**；Oracle/DB2/Snowflake/BigQuery/Redshift/DuckDB/ClickHouse/Hive/Spark/Teradata 选择**截断**。这一选择会影响"重复写入同一字面量是否产生相同结果"和"聚合后写入是否单调"等业务正确性。

2. **最大精度的"军备竞赛"**：SQL 标准定义 0..9（纳秒），但 DB2 和 Trino 已扩展到 12（皮秒），SQL Server 限制为 7（100 纳秒），PostgreSQL 仅到 6（微秒）。BigQuery/Spark/Redshift 固定为 6，Hive/Impala/Spanner/Snowflake 默认/固定到 9。

3. **默认精度的多样性**：PostgreSQL/Oracle/DB2/Teradata 默认 6（微秒，符合 SQL 标准），MySQL/TiDB/StarRocks/Doris 默认 0（整秒，向后兼容），SQL Server `DATETIME2` 默认 7，Snowflake/Hive/Impala/Spanner 默认 9，ClickHouse `DateTime64` 默认 3，Presto/Trino 默认 3。这导致"未指定精度时写入纳秒数据"在不同引擎产生 0..6 位不同的截断结果。

4. **半数规则的隐藏陷阱**：PostgreSQL 选择**银行家舍入（half to even）**——`.5` 向最近偶数进位；MySQL/SQL Server 选择**远离零进位（half away from zero）**——`.5` 总是进位。这导致"小数末位含 .5 的批量数据"在 PG 与 SQL Server 中聚合结果不同。

5. **物理粒度 vs 显示精度**：Oracle/Snowflake 内部所有 TIMESTAMP 都按最大粒度（纳秒）存储，精度参数仅控制显示和写入截断。SQL Server `DATETIME2` 和 PostgreSQL `TIMESTAMP(p)` 则按精度变长存储（节省空间）。DB2 是按精度变长的极致——支持 11 个不同长度（7..13 字节）。

6. **MySQL 历史包袱**：MySQL 5.6.4（2012）才支持亚秒精度，且默认精度为 0（整秒）——这是兼容老应用的妥协。这意味着 MySQL 的"DATETIME 自动有微秒"是错觉：不显式指定 `(6)` 仍是整秒。

7. **SQL Server `DATETIME` 的"1/300 秒"陷阱**：老类型 `DATETIME` 使用 1/300 秒粒度（约 3.33 ms），导致 `.001` 与 `.002` 不可表达，会被映射到 `.000` 或 `.003`。`DATETIME2`（2008+）解决了这个问题但需要显式声明。

8. **CAST 与 INSERT 行为统一**：所有主流引擎的隐式转换（INSERT 到低精度列）与显式 CAST 行为一致——选择截断的引擎在两种场景都截断，选择四舍五入的引擎在两种场景都进位。

9. **`DATE_TRUNC` 总是 floor**：与 `CAST(p)` 不同，`DATE_TRUNC(unit, ts)` 在所有引擎中都是"向下取整"（floor），永远不进位。这是面向时间桶聚合的设计需求——保证 "桶 [12:34:00, 12:35:00) 的所有事件都映射到 12:34:00"。

10. **EXTRACT(EPOCH ...)的精度损失**：PostgreSQL/Trino 用 `DOUBLE` 返回 epoch，存在浮点精度损失（仅约 15-17 位有效数字）。Oracle/Snowflake/ClickHouse 提供专门的 `*_NS / *_NANO` 函数返回整数纳秒。生产代码中跨毫秒计算建议用整数函数。

11. **存储格式与精度的耦合**：DB2 按精度变长存储（7..13 字节），PostgreSQL/Oracle/Snowflake 固定长度（8..11 字节），ClickHouse `DateTime64(p)` 固定 8 字节但精度越高时间范围越窄（精度 9 时仅 ±292 年）。这一选择影响存储成本和数据范围。

12. **时区类型与精度独立**：所有支持 `WITH TIME ZONE` 的主流引擎都让两种类型共享同一精度参数化范围。但物理存储略有差异：DB2 的 `TIMESTAMP(p) WITH TIME ZONE` 在数据后追加 2 字节时区偏移；PostgreSQL `TIMESTAMPTZ` 仅存 UTC（无时区元数据），与 `TIMESTAMP(p)` 大小相同。

13. **Parquet/ORC 等文件格式的精度协商**：当 Hive/Spark 写 Parquet 时，需要在文件 schema 中声明 `unit`（ms/us/ns）和 `isAdjustedToUTC`。早期 Parquet `INT96` 类型固定纳秒；新格式 `TIMESTAMP_LOGICAL_TYPE` 可指定。读时若引擎精度低于文件精度，会按引擎规则截断/进位。

14. **CAST 报错时机的差异**：DB2/Trino 接受 `TIMESTAMP(12)`，PostgreSQL 拒绝 `TIMESTAMP(7)+`，SQL Server 拒绝 `DATETIME2(8)+`。跨数据库迁移 DDL 时这是隐藏的语法错误源。

15. **批量加载的隐式约束**：从 CSV 等文本格式批量加载时，超精度位会被引擎按各自规则截断或进位——但 `STRICT` 模式或 `ERROR ON OVERFLOW` 等设置在多数引擎下不影响精度截断（仅影响范围溢出）。这意味着精度损失通常**静默发生**，不抛错。

## 设计争议

### 截断 vs 四舍五入哪个对？

**截断派**（Oracle/DB2/Snowflake）的论据：
- 单调性：`t1 < t2` 的两个高精度时间戳，截断后仍满足 `t1' <= t2'`，永远不会"翻转"
- 信息保留：截断的低位是"被丢弃的信息"，进位则"创造了新信息"——后者违反"无损存储原则"
- 一致性：所有 SQL 字面量到 SQL 时间戳的转换语义一致（永远 floor）

**四舍五入派**（PostgreSQL/MySQL/SQL Server）的论据：
- 数值近似最优：四舍五入的最大误差是半个 ULP（单位最小精度），截断的最大误差是一个 ULP——四舍五入误差更小
- 与浮点数语义一致：IEEE 754 默认规则就是 round-half-to-even，TIMESTAMP 转换跟齐有助于跨类型转换的可预测性
- 用户期望：用户输入 `.7895` 到毫秒列，多数人期望 `.790` 而非 `.789`

实际上两派各有道理——这就是为什么 SQL 标准明文允许实现自由选择。

### 默认精度选 0 / 6 / 9 哪个合适？

- **默认 0**（MySQL/StarRocks/Doris）：兼容老代码，但"未声明精度的列丢失亚秒"是常见 bug
- **默认 6**（PostgreSQL/Oracle/DB2/标准）：平衡精度与存储，主流选择
- **默认 9**（Snowflake/Hive/Spanner/Impala）：仓库场景"先存原始数据，后续按需截断"的设计

对于新引擎设计，默认 6 是最稳妥的选择，但允许用户配置默认值（如 Snowflake 的 `TIMESTAMP_TYPE_MAPPING`）会更灵活。

### 是否应该支持超出 SQL 标准 0..9？

DB2 / Trino 支持到 12 位（皮秒）的实用价值有限——硬件时钟分辨率通常在纳秒级（`clock_gettime` 的纳秒精度），10^-12 秒的精度无实际意义。但这两个引擎的设计决定有其考虑：
- DB2：与 z/OS 上的高精度时钟（STCK 指令）配合
- Trino：作为联邦查询引擎，需要表达上游存储的最大精度（如某些科学数据集）

对多数业务系统，纳秒精度（9 位）已足够；皮秒精度更多是"理论扩展"。

### 引擎应该缺省四舍五入还是截断？

新引擎设计建议：
- 业务/OLTP 场景：选择**四舍五入**，与 PG/MySQL/SQL Server 兼容，符合用户直觉
- 数据仓库/OLAP 场景：选择**截断**，与 Snowflake/BigQuery/ClickHouse 一致，保证单调性
- 时间序列场景：选择**截断**且默认高精度（9 位），与 Snowflake/InfluxDB/QuestDB 一致

无论选择哪种，**必须在文档中明确说明半数规则**（half-even / half-away-from-zero / 截断）——这是跨引擎数据一致性的关键。

### 隐式截断是否应该报错？

多数引擎选择"静默截断/进位"，仅有少数（SQL:2003 标准 `OVERFLOW`）支持配置严格模式。这一选择源于：
- 兼容性：写入逻辑无法预知列精度，强报错会导致大量遗留代码失败
- 性能：每次写入校验精度有 CPU 开销

但"静默"也带来 bug——用户写入纳秒数据到微秒列，损失了 3 位却毫不知情。建议引擎在 EXPLAIN/审计日志中标注精度截断事件，但不在运行时报错。

## 对引擎开发者的实现建议

### 1. 物理存储设计

```
方案 A: 固定粒度，可变精度（PG/Snowflake 风格）
  - 内部存储：始终 8 字节 Int64，单位为最大粒度（μs 或 ns）
  - 精度 p：仅在 INSERT/CAST 时校验和截断，存储不变
  - 优点：join/比较/排序逻辑统一，无需按精度分支
  - 缺点：存储无优化（低精度仍占满字节）

方案 B: 可变粒度，可变精度（DB2 风格）
  - 内部存储：按精度选择存储长度（7..13 字节）
  - 精度 p：决定物理存储大小和粒度
  - 优点：低精度场景节省存储
  - 缺点：跨精度比较需要单位归一化

方案 C: 档位化（DuckDB 风格）
  - 提供 N 种独立类型（NS/μs/MS/S）
  - 用户显式选择
  - 优点：实现简单，无参数解析
  - 缺点：用户体验差（无 TIMESTAMP(p) 语法）

新引擎建议：方案 A，与现代主流（Snowflake/PG）兼容。
```

### 2. 写入路径的精度截断

```rust
// 伪代码：写入时的精度处理
fn cast_to_precision(ts_ns: i64, p: u8) -> i64 {
    let divisor = 10_i64.pow(9 - p as u32);
    if ROUNDING_MODE == Truncate {
        (ts_ns / divisor) * divisor
    } else if ROUNDING_MODE == HalfAwayFromZero {
        let half = divisor / 2;
        if ts_ns >= 0 {
            ((ts_ns + half) / divisor) * divisor
        } else {
            ((ts_ns - half) / divisor) * divisor
        }
    } else if ROUNDING_MODE == HalfToEven {
        let q = ts_ns / divisor;
        let r = ts_ns % divisor;
        let half = divisor / 2;
        if r.abs() > half {
            (q + r.signum()) * divisor
        } else if r.abs() < half {
            q * divisor
        } else {
            // 半数情况：向偶数进位
            if q % 2 == 0 { q * divisor } else { (q + r.signum()) * divisor }
        }
    }
}
```

### 3. 比较操作的精度处理

```
方案 A: 提升到较高精度后比较
  TIMESTAMP(3) 与 TIMESTAMP(6) 比较 → 双方提升到 ns，整数比较
  优点：语义清晰，与 SQL 标准一致
  缺点：每次比较有乘法开销

方案 B: 全员存储为最高精度（如 ns）
  比较时直接 Int64 比较，无开销
  优点：性能最优
  缺点：低精度场景存储浪费
```

### 4. EXPLAIN/审计的精度元信息

```
查询 EXPLAIN 输出中标注精度截断点：
  > SELECT * FROM events WHERE ts > '2026-04-28 12:34:56.789999';
  Plan:
    Filter: (ts > '2026-04-28 12:34:56.789999'::TIMESTAMP)
    [Note: 字面量解析为 TIMESTAMP(6)，列 ts 为 TIMESTAMP(3)，
     比较前字面量截断为 .789（截断模式）或 .790（四舍五入模式）]
```

### 5. 与文件格式的精度协商

```
读 Parquet/ORC 时：
  - 读取文件 schema 中的 unit (NANOS/MICROS/MILLIS) 和 isAdjustedToUTC
  - 与目标列精度比较：
    文件精度 > 列精度：按引擎规则截断/进位
    文件精度 < 列精度：补 0 至列精度
    文件精度 = 列精度：直接读取

写 Parquet/ORC 时：
  - 列精度直接映射到文件 unit（μs → MICROS，ns → NANOS）
  - 如不匹配（列精度 4 写 Parquet）：选择更高精度（如 ms 或 μs），元数据标注实际精度
```

### 6. 测试用例建议

```
精度测试矩阵：
  1. 字面量超精度写入（如 9 位写入 TIMESTAMP(3)）
     - 截断模式：验证低位被丢弃
     - 进位模式：验证半数规则（.5 向偶 / 向远离零）
  2. CAST 精度变更
     - 高到低：同字面量超精度规则
     - 低到高：补 0 验证
  3. 比较操作
     - 不同精度列比较：TIMESTAMP(3) vs TIMESTAMP(6)
     - 与字面量比较：精度提升后比较
  4. 边界值
     - .999999999 截到 .000（进位到下一秒）
     - .000000000 截到 .000（无变化）
     - 负值（如纪元前时间）
  5. 时区+精度组合
     - TIMESTAMP(3) WITH TIME ZONE 写入和读取
     - 跨时区比较精度保留
  6. 文件格式往返
     - 写 Parquet → 读回，精度无损
     - 跨精度往返（写 ns 读 μs）
```

## 总结对比矩阵

### 精度能力总览

| 引擎 | 类型 | 范围 | 默认 | 行为 | 半数规则 |
|------|------|------|------|------|---------|
| PostgreSQL | `TIMESTAMP(p)` | 0..6 | 6 | 进位 | half-even |
| MySQL | `DATETIME(p)` | 0..6 | 0 | 进位 | half-away |
| Oracle | `TIMESTAMP(p)` | 0..9 | 6 | 截断 | -- |
| SQL Server | `DATETIME2(n)` | 0..7 | 7 | 进位 | half-away |
| DB2 | `TIMESTAMP(p)` | 0..12 | 6 | 截断 | -- |
| Snowflake | `TIMESTAMP(p)` | 0..9 | 9 | 截断 | -- |
| BigQuery | `TIMESTAMP` | 固定 6 | 6 | 截断 | -- |
| Trino | `TIMESTAMP(p)` | 0..12 | 3 | 进位 | half-up |
| ClickHouse | `DateTime64(p)` | 0..9 | 3 | 截断 | -- |
| DuckDB | `TIMESTAMP_*` | 档位 | μs | 截断 | -- |
| Spark SQL | `TIMESTAMP` | 固定 6 | 6 | 截断 | -- |
| Hive | `TIMESTAMP` | 固定 9 | 9 | 截断 | -- |

### 引擎选型建议（按精度需求）

| 场景 | 推荐引擎 | 原因 |
|------|---------|------|
| OLTP，业务时间戳 | PostgreSQL/MySQL/SQL Server | 默认 6 或 7，进位语义符合用户直觉 |
| 数据仓库，原始数据 | Snowflake/Oracle | 默认 9，截断保单调，无信息"创造" |
| 时间序列，纳秒事件 | InfluxDB/QuestDB/ClickHouse | 原生纳秒，存储优化 |
| 跨引擎数据交换 | 存到 6（μs） | 多数引擎兼容的最大公约数 |
| 高频交易 | DB2/Snowflake | 纳秒及以上精度 |
| 极高精度科学计算 | DB2/Trino | 12 位（皮秒）唯二选择 |
| 简化业务逻辑 | DuckDB | 档位化避免精度参数 |

## 参考资料

- SQL:1992 标准：ISO/IEC 9075:1992，6.1 `<data type>` (TIMESTAMP)
- SQL:2003 标准：ISO/IEC 9075-2:2003，6.1 (datetime types)
- PostgreSQL: [Date/Time Types](https://www.postgresql.org/docs/current/datatype-datetime.html)
- MySQL: [Fractional Seconds in Time Values](https://dev.mysql.com/doc/refman/8.0/en/fractional-seconds.html)
- Oracle: [TIMESTAMP Data Type](https://docs.oracle.com/en/database/oracle/oracle-database/19/sqlrf/Data-Types.html#GUID-A340C2B7-9DBA-4F38-95EA-D9E5D5F39C95)
- SQL Server: [datetime2](https://learn.microsoft.com/en-us/sql/t-sql/data-types/datetime2-transact-sql)
- DB2: [TIMESTAMP Data Type](https://www.ibm.com/docs/en/db2/11.5?topic=list-datetime-values)
- Snowflake: [Date & Time Data Types](https://docs.snowflake.com/en/sql-reference/data-types-datetime)
- BigQuery: [Timestamp Type](https://cloud.google.com/bigquery/docs/reference/standard-sql/data-types#timestamp_type)
- ClickHouse: [DateTime64](https://clickhouse.com/docs/en/sql-reference/data-types/datetime64)
- Trino: [TIMESTAMP](https://trino.io/docs/current/language/types.html#timestamp)
- Spark SQL: [Timestamp Type](https://spark.apache.org/docs/latest/sql-ref-datatypes.html)
- DuckDB: [Timestamp Types](https://duckdb.org/docs/sql/data_types/timestamp)
- 配套：[`timezone-handling.md`](./timezone-handling.md)（时区语义）
- 配套：[`time-series-functions.md`](./time-series-functions.md)（DATE_TRUNC 单位截断）
- 配套：[`datetime-functions-mapping.md`](./datetime-functions-mapping.md)（日期/时间函数命名映射）
