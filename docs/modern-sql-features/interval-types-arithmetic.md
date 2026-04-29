# INTERVAL 类型与算术 (INTERVAL Types and Arithmetic)

`'2024-01-31' + INTERVAL '1' MONTH` 等于什么？2 月 29 日、2 月 28 日、3 月 2 日，还是直接报错？这是一个看似无害却跨引擎差异巨大的问题——不同数据库给出 4 种不同答案，正是 INTERVAL 类型与算术语义的核心难题。

## SQL:1992 标准定义

SQL:1992 标准（ISO/IEC 9075:1992, Section 4.5）正式引入 `INTERVAL` 类型，将"时间长度"作为与 `DATE`/`TIME`/`TIMESTAMP` 平行的核心数据类型。标准的关键设计是把 INTERVAL 划分为**两个互不兼容的类**：

```
<interval qualifier> ::=
    <start field> [ TO <end field> ]
  | <single datetime field>

<start field> ::= YEAR | MONTH | DAY | HOUR | MINUTE
<end field>   ::= YEAR | MONTH | DAY | HOUR | MINUTE | SECOND

-- 类 1：年-月间隔（Year-Month Class）
INTERVAL YEAR
INTERVAL MONTH
INTERVAL YEAR TO MONTH

-- 类 2：日-时间隔（Day-Time Class）
INTERVAL DAY
INTERVAL DAY TO HOUR
INTERVAL DAY TO MINUTE
INTERVAL DAY TO SECOND
INTERVAL HOUR TO SECOND
INTERVAL MINUTE TO SECOND
INTERVAL SECOND
```

标准将这两个类设计为**互不可比较、互不可加减、互不可转换**。原因是月份长度可变（28~31 天），无法用秒表示，因此 `INTERVAL '1' MONTH` 与 `INTERVAL '30' DAY` 不等价，引擎必须分别记录。

### 算术语义

```
-- 标准定义的运算（节选自 SQL:1992 §6.14）
DATETIME + INTERVAL  → DATETIME
INTERVAL + DATETIME  → DATETIME
DATETIME - DATETIME  → INTERVAL
DATETIME - INTERVAL  → DATETIME
INTERVAL + INTERVAL  → INTERVAL（同类）
INTERVAL - INTERVAL  → INTERVAL（同类）
INTERVAL * NUMERIC   → INTERVAL
INTERVAL / NUMERIC   → INTERVAL
```

### 非单调月份加法

SQL:1992 §6.14 General Rule 7 规定 INTERVAL 月份加法的语义：当结果月份没有对应日时（如 1 月 31 日 + 1 月 = 2 月 31 日不存在），结果应"截取到该月最后一天"。这导致**月份加法不可逆**（非单调）：

```sql
'2024-01-31' + 1 MONTH = '2024-02-29'   -- 截取到 2 月最后一天（闰年）
'2024-02-29' - 1 MONTH = '2024-01-29'   -- 不是 '2024-01-31'

-- 加 1 个月再减 1 个月，结果可能与原日期不同
```

许多引擎遵循这一规则，但**部分引擎采取不同策略**（如 Oracle 的 `LAST_DAY` 保持、Snowflake 的"last-day-of-month preservation"），导致跨引擎迁移时容易出错。

## 支持矩阵（45+ 引擎）

### 原生 INTERVAL 类型支持

| 引擎 | 原生 INTERVAL 列类型 | YEAR-MONTH 类 | DAY-TIME 类 | INTERVAL 字面量 | EXTRACT 支持 | 版本 |
|------|---------------------|--------------|-------------|----------------|-------------|------|
| PostgreSQL | 是 | 是 | 是 | `INTERVAL '1 year 2 months'` | 是 | 6.x+ |
| Oracle | 是 | `INTERVAL YEAR TO MONTH` | `INTERVAL DAY TO SECOND` | `INTERVAL '1-2' YEAR TO MONTH` | 是 | 9i+ (2001) |
| SQL Server | -- | -- | -- | -- | -- | 不支持 |
| MySQL | -- | 仅表达式 | 仅表达式 | `INTERVAL 1 MONTH` | 是 | 表达式 5.0+ |
| MariaDB | -- | 仅表达式 | 仅表达式 | `INTERVAL 1 MONTH` | 是 | 表达式 5.0+ |
| SQLite | -- | -- | -- | -- (字符串修饰符) | 否 | 不支持 |
| DB2 | 否（labeled durations） | -- | -- | `1 MONTH` 后缀 | 是 | 早期 |
| CockroachDB | 是 | 是 | 是 | 同 PG | 是 | 1.0+ |
| Snowflake | 否（仅表达式） | 是 | 是 | `INTERVAL '1 year 2 months'` | 是 | GA |
| BigQuery | 是 | 是 | 是 | `INTERVAL '1-2 3 4:5:6' YEAR TO SECOND` | `EXTRACT` | 2021 GA |
| ClickHouse | 否（仅表达式） | 是 | 是 | `INTERVAL 1 MONTH` | 是 | 早期 |
| Redshift | 是 | 是 | 是 | 同 PG | 是 | 继承 PG |
| Greenplum | 是 | 是 | 是 | 同 PG | 是 | 继承 PG |
| YugabyteDB | 是 | 是 | 是 | 同 PG | 是 | 继承 PG |
| Trino | 是 | `INTERVAL YEAR TO MONTH` | `INTERVAL DAY TO SECOND` | `INTERVAL '1' DAY` | 是 | 早期 |
| Presto | 是 | 同 Trino | 同 Trino | 同 Trino | 是 | 早期 |
| Spark SQL | 是 | `INTERVAL YEAR TO MONTH` | `INTERVAL DAY TO SECOND` | `INTERVAL '1' YEAR` | 是 | 3.2+ (类型) |
| Hive | 是 | 是 | 是 | `INTERVAL '1' YEAR` | 是 | 1.2+ |
| Flink SQL | 是 | 是 | 是 | `INTERVAL '1' YEAR` | 是 | 1.0+ |
| Databricks | 是 | 是 | 是 | 同 Spark | 是 | 继承 Spark |
| DuckDB | 是 | 是（合并） | 是（合并） | `INTERVAL 1 YEAR` | 是 | 早期 |
| Teradata | 是 | 是 | 是 | `INTERVAL '1' YEAR` | 是 | V2R5+ |
| SAP HANA | -- | -- | -- | 表达式中部分支持 | 是 | -- |
| Vertica | 是 | 是 | 是 | `INTERVAL '1' YEAR` | 是 | GA |
| Impala | 否（仅表达式） | -- | -- | `INTERVAL 1 MONTH` | 是 | 2.0+ |
| TiDB | -- | 仅表达式 | 仅表达式 | 同 MySQL | 是 | 继承 MySQL |
| OceanBase | -- | 仅表达式 | 仅表达式 | 同 MySQL/Oracle | 是 | 多模式 |
| SingleStore (MemSQL) | -- | 仅表达式 | 仅表达式 | 同 MySQL | 是 | GA |
| StarRocks | -- | 仅表达式 | 仅表达式 | `INTERVAL 1 MONTH` | 是 | GA |
| Doris | -- | 仅表达式 | 仅表达式 | `INTERVAL 1 MONTH` | 是 | GA |
| Firebolt | -- | -- | -- | -- | -- | 不支持 |
| MonetDB | 是 | 是 | 是 | `INTERVAL '1' MONTH` | 是 | 早期 |
| Crate DB | -- | -- | -- | -- | -- | 不支持 |
| TimescaleDB | 是 | 是 | 是 | 同 PG | 是 | 继承 PG |
| QuestDB | -- | -- | -- | -- | -- | 不支持 |
| Exasol | 是 | 是 | 是 | `INTERVAL '1' YEAR` | 是 | GA |
| Informix | 是 | 是 | 是 | `INTERVAL ('1') YEAR TO MONTH` | 是 | 早期 |
| Firebird | -- | -- | -- | -- | -- | 不支持（仅 DAY 算术） |
| H2 | 是 | 是 | 是 | `INTERVAL '1' YEAR` | 是 | 1.4+ |
| HSQLDB | 是 | 是 | 是 | `INTERVAL '1' YEAR` | 是 | 2.0+ |
| Derby | -- | -- | -- | -- | -- | 不支持 |
| Amazon Athena | 是 | 是 | 是 | 继承 Trino | 是 | 继承 Trino |
| Azure Synapse | -- | -- | -- | -- | -- | 不支持（同 SQL Server） |
| Google Spanner | 是 | -- | 是（PG 方言） | `INTERVAL` | 是 | GoogleSQL+PG |
| Materialize | 是 | 是 | 是 | 同 PG | 是 | 继承 PG |
| RisingWave | 是 | 是 | 是 | 同 PG | 是 | 继承 PG |
| InfluxDB (SQL) | -- | -- | -- | -- | -- | 不支持 |
| DatabendDB | 是 | 是 | 是 | `INTERVAL 1 MONTH` | 是 | GA |
| Yellowbrick | 是 | 是 | 是 | 同 PG | 是 | 继承 PG |

> 注：约 25+ 引擎支持原生 INTERVAL 列类型；其余引擎仅在表达式上下文中支持 INTERVAL 关键字（如 MySQL/MariaDB/ClickHouse/Snowflake）；SQL Server/SQLite/Firebolt/CrateDB 等完全不支持 INTERVAL，需要使用 DATEADD/DATEDIFF 等函数模拟。

### INTERVAL 算术与 TIMESTAMP

| 引擎 | TS + INTERVAL | TS - INTERVAL | TS - TS → INTERVAL | INT * INTERVAL | EXTRACT FROM INTERVAL |
|------|--------------|---------------|--------------------|--------------|----------------------|
| PostgreSQL | 是 | 是 | 是 | 是 | 是 |
| Oracle | 是 | 是 | 是（仅 DAY-TIME） | 是 | 是 |
| SQL Server | 用 DATEADD | 用 DATEADD | 用 DATEDIFF | -- | 不适用 |
| MySQL | 是 | 是 | 用 TIMESTAMPDIFF | -- | 不适用（值是数值） |
| MariaDB | 是 | 是 | 用 TIMESTAMPDIFF | -- | 不适用 |
| SQLite | datetime 修饰符 | datetime 修饰符 | julianday() 减法 | -- | 不适用 |
| DB2 | 是 | 是 | 是（labeled） | -- | 是 |
| BigQuery | 是 | 是 | 是 | 是 | 是 |
| Snowflake | 是 | 是 | 用 DATEDIFF | 是 | -- |
| Trino | 是 | 是 | 是 | 是 | 是 |
| ClickHouse | 是 | 是 | 用 dateDiff | -- | 不适用 |
| DuckDB | 是 | 是 | 是 | 是 | 是 |
| Spark SQL | 是 | 是 | 是 | 是 | 是 |
| Flink SQL | 是 | 是 | 是 | -- | 是 |
| Hive | 是 | 是 | 是 | -- | 是 |

### ISO 8601 持续时间字面量解析

ISO 8601 定义了 `P[n]Y[n]M[n]DT[n]H[n]M[n]S` 格式的持续时间字面量（如 `P1Y2M3DT4H5M6S`），是跨语言/跨系统交换 INTERVAL 值的标准格式。

| 引擎 | ISO 8601 解析 | 输入函数/转换 | 备注 |
|------|--------------|--------------|------|
| PostgreSQL | 是 | `INTERVAL 'P1Y2M3D'` | `IntervalStyle` 影响输出格式 |
| Oracle | 是 | `TO_DSINTERVAL('P3DT4H5M6S')` | DAY-TIME 专用，YEAR-MONTH 用 `TO_YMINTERVAL` |
| SQL Server | -- | -- | 不支持 |
| MySQL | -- | -- | 不支持 ISO 8601 字面量 |
| MariaDB | -- | -- | 不支持 |
| BigQuery | 部分 | `INTERVAL '1-2 3 4:5:6' YEAR TO SECOND` | 自有格式（非 ISO 8601） |
| Snowflake | -- | -- | 不支持 ISO 8601 字面量 |
| ClickHouse | -- | -- | 不支持 |
| DuckDB | -- | 用字符串拼装 | 不直接支持 ISO 8601 |
| Spark SQL | 是 | `INTERVAL 'P1Y2M3D'`（Hive 风格） | 部分版本 |
| Trino | -- | -- | 用引擎自有格式 |
| Hive | 是 | 类似 PG | -- |
| Flink SQL | -- | -- | 部分版本支持 |
| Databricks | 是 | 同 Spark | -- |

总体而言，**只有 PostgreSQL、Oracle 和部分 Spark/Hive 直接接受 ISO 8601 字符串**作为 INTERVAL 字面量；其他引擎需要应用层把 ISO 8601 拆解为各字段后构造表达式。

## 各引擎语法详解

### PostgreSQL（最完整的标准实现）

PostgreSQL 自 6.x 起支持 INTERVAL 类型，是最贴近 SQL 标准的实现，但有一处显著扩展：**允许 YEAR-MONTH 与 DAY-TIME 字段混合在同一 INTERVAL 中**（标准上是两个独立类）。

```sql
-- 创建 INTERVAL 列
CREATE TABLE rentals (
    id INT,
    duration INTERVAL,
    duration_year_month INTERVAL YEAR TO MONTH,
    duration_day_second INTERVAL DAY TO SECOND
);

-- 字面量：多种风格
SELECT INTERVAL '1 year 2 months';                       -- PG 风格
SELECT INTERVAL '1-2' YEAR TO MONTH;                     -- 标准风格
SELECT INTERVAL '3 days 4 hours 5 minutes 6 seconds';
SELECT INTERVAL '3 4:5:6' DAY TO SECOND;                 -- 标准风格
SELECT INTERVAL 'P1Y2M3DT4H5M6S';                        -- ISO 8601
SELECT INTERVAL 'P0001-02-03T04:05:06';                  -- ISO 8601 备选格式

-- 微秒精度（PG 自 8.4 起内部存储为 8 字节微秒数 + 4 字节 days + 4 字节 months）
SELECT INTERVAL '0.000001 second';                       -- 1 微秒
SELECT INTERVAL '1.234567 seconds';                      -- 6 位小数

-- 算术
SELECT TIMESTAMP '2024-01-15 10:00:00' + INTERVAL '1 month';
-- 结果: 2024-02-15 10:00:00

SELECT TIMESTAMP '2024-01-31 10:00:00' + INTERVAL '1 month';
-- 结果: 2024-02-29 10:00:00（闰年截取到月末）

SELECT TIMESTAMP '2024-01-31' - TIMESTAMP '2024-01-15';
-- 结果: 16 days

-- 乘除
SELECT INTERVAL '1 hour' * 3.5;     -- '03:30:00'
SELECT INTERVAL '1 day' / 2;        -- '12:00:00'

-- 提取
SELECT EXTRACT(YEAR FROM INTERVAL '1 year 6 months');           -- 1
SELECT EXTRACT(MONTH FROM INTERVAL '1 year 6 months');          -- 6
SELECT EXTRACT(EPOCH FROM INTERVAL '1 day 2 hours');            -- 93600

-- 输出格式（受 IntervalStyle 影响）
SET IntervalStyle = 'postgres';      -- 默认: '1 year 2 mons'
SET IntervalStyle = 'postgres_verbose';  -- '@ 1 year 2 mons'
SET IntervalStyle = 'sql_standard';  -- '+1-2 +0 0:00:00'
SET IntervalStyle = 'iso_8601';      -- 'P1Y2M'

-- justify_* 函数：规范化跨度
SELECT justify_hours(INTERVAL '36 hours');       -- '1 day 12:00:00'
SELECT justify_days(INTERVAL '40 days');         -- '1 mon 10 days'
SELECT justify_interval(INTERVAL '40 days 36 hours'); -- '1 mon 11 days 12:00:00'
-- 注意：justify_* 用 30 天 = 1 月 的近似换算，仅适合显示，不可逆
```

### Oracle（严格的双类分离）

Oracle 9i (2001) 引入两个独立类型：`INTERVAL YEAR TO MONTH` 和 `INTERVAL DAY TO SECOND`。**两个类型互不兼容**，符合 SQL:1992 标准。

```sql
-- 列定义
CREATE TABLE projects (
    id NUMBER,
    duration_ym INTERVAL YEAR(2) TO MONTH,
    duration_ds INTERVAL DAY(3) TO SECOND(6)
);

-- YEAR-MONTH 类
SELECT INTERVAL '1-2' YEAR TO MONTH FROM DUAL;        -- 1 年 2 月
SELECT INTERVAL '14' MONTH FROM DUAL;                  -- 等价于 1 年 2 月
SELECT INTERVAL '5' YEAR FROM DUAL;

-- DAY-TIME 类
SELECT INTERVAL '3 4:5:6.789' DAY TO SECOND FROM DUAL;
SELECT INTERVAL '100' DAY(3) FROM DUAL;                -- 需要精度声明
SELECT INTERVAL '4 5' DAY TO HOUR FROM DUAL;

-- 转换函数（Oracle 特有）
SELECT TO_YMINTERVAL('01-02') FROM DUAL;               -- '01-02' YEAR TO MONTH
SELECT TO_YMINTERVAL('P1Y2M') FROM DUAL;               -- ISO 8601
SELECT TO_DSINTERVAL('3 04:05:06.789') FROM DUAL;
SELECT TO_DSINTERVAL('P3DT4H5M6.789S') FROM DUAL;      -- ISO 8601

-- NUMTOYMINTERVAL / NUMTODSINTERVAL：从数值构造
SELECT NUMTOYMINTERVAL(14, 'MONTH') FROM DUAL;         -- '1-2'
SELECT NUMTODSINTERVAL(86400, 'SECOND') FROM DUAL;     -- '1 0:0:0'

-- 算术
SELECT TIMESTAMP '2024-01-15 10:00:00' + INTERVAL '1' MONTH FROM DUAL;
-- 2024-02-15 10:00:00

SELECT TIMESTAMP '2024-01-31 10:00:00' + INTERVAL '1' MONTH FROM DUAL;
-- ORA-01839: date not valid for month specified（Oracle 严格）
-- Oracle 在 INTERVAL 月份加法上比 PG 严格，超界会报错
-- 解决方案：用 ADD_MONTHS（月末日截取）

SELECT ADD_MONTHS(TIMESTAMP '2024-01-31', 1) FROM DUAL;
-- 2024-02-29

-- 关键限制：YEAR-MONTH 与 DAY-TIME 不可互相加减
SELECT INTERVAL '1-2' YEAR TO MONTH + INTERVAL '3' DAY FROM DUAL;
-- ORA-30081: invalid data type for datetime/interval arithmetic
```

Oracle 的核心特点：（1）两个 INTERVAL 类完全独立；（2）`+ INTERVAL n MONTH` 在日期跨界时会报错而非截取，需要 `ADD_MONTHS` 截取到月末。

### SQL Server（无 INTERVAL 类型，全靠 DATEADD/DATEDIFF）

SQL Server 至今（2025 SQL Server 2022）**没有 INTERVAL 数据类型**，所有时间间隔运算用函数完成。

```sql
-- DATEADD: 加间隔（参数顺序 = 单位, 数量, 日期）
SELECT DATEADD(MONTH, 1, '2024-01-15');              -- 2024-02-15
SELECT DATEADD(MONTH, 1, '2024-01-31');              -- 2024-02-29（截取到月末）
SELECT DATEADD(DAY, 30, '2024-01-15');               -- 2024-02-14
SELECT DATEADD(MICROSECOND, 1, GETDATE());

-- DATEDIFF: 返回差值（整数）
SELECT DATEDIFF(DAY, '2024-01-01', '2024-12-31');    -- 365
SELECT DATEDIFF(MONTH, '2024-01-15', '2025-03-15');  -- 14
SELECT DATEDIFF(SECOND, '2024-01-01 00:00:00', '2024-01-01 00:01:30');  -- 90

-- DATEDIFF_BIG: 返回 BIGINT（避免大间隔溢出）
SELECT DATEDIFF_BIG(MICROSECOND, '2020-01-01', '2024-01-01');

-- 没有 INTERVAL 字面量，但可以用字符串字面量代替（仅作 DATEADD 参数辅助）
DECLARE @months INT = 3;
SELECT DATEADD(MONTH, @months, GETDATE());

-- 替代方案：用字符串构造时间间隔
DECLARE @duration TIME = '02:30:00';     -- 2.5 小时
SELECT DATEADD(MILLISECOND,
               DATEDIFF(MILLISECOND, '00:00:00', @duration),
               GETDATE());

-- 局限：
-- 1. 没有 INTERVAL 列类型，需要用两列（数量 + 单位）或 INT 秒数
-- 2. DATEADD 的 datepart 参数是关键字（不是变量），动态拼接需用 SQL 字符串
-- 3. 不支持 ISO 8601 持续时间字面量
```

### MySQL / MariaDB（INTERVAL 仅在表达式中）

MySQL 自 5.0 起支持 `INTERVAL` 关键字，但**只能用于表达式**，**不能作为列类型**：

```sql
-- 字面量（仅表达式上下文有效）
SELECT NOW() + INTERVAL 1 MONTH;
SELECT NOW() + INTERVAL '1 2' YEAR_MONTH;            -- 1 年 2 月
SELECT NOW() + INTERVAL '3 4:5:6' DAY_SECOND;        -- 3 天 4:5:6
SELECT NOW() + INTERVAL 1.5 HOUR;                    -- 注意：浮点会被截断为整数

-- DATE_ADD / DATE_SUB（与 INTERVAL 表达式等价）
SELECT DATE_ADD('2024-01-15', INTERVAL 1 MONTH);     -- 2024-02-15
SELECT DATE_ADD('2024-01-31', INTERVAL 1 MONTH);     -- 2024-02-29

-- 受支持的单位
-- MICROSECOND, SECOND, MINUTE, HOUR, DAY, WEEK, MONTH, QUARTER, YEAR
-- SECOND_MICROSECOND, MINUTE_MICROSECOND, MINUTE_SECOND
-- HOUR_MICROSECOND, HOUR_SECOND, HOUR_MINUTE
-- DAY_MICROSECOND, DAY_SECOND, DAY_MINUTE, DAY_HOUR
-- YEAR_MONTH

-- 注意：MySQL 没有 INTERVAL 列类型
CREATE TABLE rentals (
    id INT,
    duration INTERVAL  -- 错误：MySQL 不支持
);
-- 解决方案：用 INT 存秒数，或用两列（unit, qty）

-- 间隔差：用 TIMESTAMPDIFF（注意：单位在前）
SELECT TIMESTAMPDIFF(MONTH, '2024-01-15', '2025-03-15');  -- 14
SELECT TIMESTAMPDIFF(DAY, '2024-01-01', '2024-12-31');    -- 365

-- 截取到月末的语义：MySQL 跟 SQL 标准一致
SELECT '2024-01-31' + INTERVAL 1 MONTH;              -- 2024-02-29
SELECT '2023-01-31' + INTERVAL 1 MONTH;              -- 2023-02-28
```

MariaDB 完全继承 MySQL 的 INTERVAL 表达式语义。

### SQLite（无 INTERVAL 概念）

SQLite 没有 INTERVAL 类型，也没有 INTERVAL 关键字。日期算术依赖 `date()` / `datetime()` 函数的字符串"修饰符"：

```sql
-- 加间隔
SELECT date('2024-01-15', '+1 month');       -- 2024-02-15
SELECT date('2024-01-31', '+1 month');       -- 2024-03-02（注意：SQLite 不截取到月末！）
SELECT datetime('now', '+30 minutes', '+1 day');

-- 减间隔
SELECT date('2024-01-15', '-1 month');

-- 多个修饰符
SELECT datetime('2024-01-15 10:00:00', '+1 month', '+3 days', '+2 hours');

-- 间隔差：用 julianday() 转儒略日后做减法
SELECT julianday('2024-12-31') - julianday('2024-01-01');   -- 365
SELECT (julianday('2024-12-31') - julianday('2024-01-01')) * 86400;  -- 秒

-- 关键差异：SQLite 月份溢出会"溢出到下一月"
-- '2024-01-31' + 1 月 = 2024-03-02 (即 2024-02-31 → 溢出 2 天)
-- 这与 PostgreSQL/MySQL/Oracle 的"截取到月末"行为不同
```

### CockroachDB（PG 兼容 + 微秒精度）

CockroachDB 完全继承 PostgreSQL 的 INTERVAL 类型与算术，包括微秒精度和混合年-月-日字段。

```sql
-- 同 PostgreSQL
SELECT INTERVAL '1 year 2 months 3 days 4:5:6';
SELECT TIMESTAMPTZ '2024-01-31' + INTERVAL '1 month';   -- 2024-02-29
SELECT EXTRACT(EPOCH FROM INTERVAL '1 day');            -- 86400
```

### ClickHouse（INTERVAL 仅在算术中）

ClickHouse 的 `INTERVAL` 是表达式关键字，**不是数据类型**：

```sql
-- 算术（INTERVAL 必须紧跟在 + 或 - 之后）
SELECT now() + INTERVAL 1 DAY;
SELECT now() + INTERVAL 1 MONTH;
SELECT now() - INTERVAL 30 SECOND;

-- 单位：NANOSECOND, MICROSECOND, MILLISECOND, SECOND, MINUTE, HOUR,
--       DAY, WEEK, MONTH, QUARTER, YEAR

-- 不能存为列类型
CREATE TABLE t (i INTERVAL DAY) ENGINE = Memory;       -- 错误

-- 替代方案：用 toIntervalXxx 函数构造
SELECT now() + toIntervalDay(1);
SELECT now() + toIntervalMonth(1) + toIntervalDay(15);

-- 间隔差：用 dateDiff
SELECT dateDiff('day', '2024-01-01', '2024-12-31');     -- 365
SELECT dateDiff('month', '2024-01-15', '2025-03-15');   -- 14

-- 月份加法语义：ClickHouse 跟标准一致（截取到月末）
SELECT toDate('2024-01-31') + INTERVAL 1 MONTH;         -- 2024-02-29
```

### BigQuery（2021 GA 的 INTERVAL 类型）

BigQuery 在 2021 年正式 GA `INTERVAL` 类型，是较晚才引入此类型的云仓库之一：

```sql
-- 字面量（BigQuery 自有格式：'YYYY-MM DD HH:MM:SS' YEAR TO SECOND）
SELECT INTERVAL '1-2 3 4:5:6' YEAR TO SECOND;
SELECT INTERVAL '1' YEAR;
SELECT INTERVAL 1 DAY;                                 -- 简化形式

-- 列类型
CREATE TABLE dataset.events (
    duration INTERVAL
);

-- 算术
SELECT TIMESTAMP '2024-01-15' + INTERVAL '1' MONTH;
SELECT TIMESTAMP '2024-01-15' + INTERVAL 1 MONTH;
SELECT TIMESTAMP '2024-01-31' + INTERVAL '1' MONTH;    -- 2024-02-29

-- INTERVAL - INTERVAL
SELECT INTERVAL '2-6' YEAR TO MONTH - INTERVAL '0-3' YEAR TO MONTH;

-- INTERVAL * INT64
SELECT INTERVAL '1' DAY * 7;                           -- 7 days

-- EXTRACT
SELECT EXTRACT(YEAR FROM INTERVAL '5-2' YEAR TO MONTH);     -- 5
SELECT EXTRACT(MONTH FROM INTERVAL '5-2' YEAR TO MONTH);    -- 2

-- 间隔差
SELECT TIMESTAMP_DIFF(TIMESTAMP '2024-12-31', TIMESTAMP '2024-01-01', DAY);
```

### Snowflake（INTERVAL 关键字，无列类型）

Snowflake 支持 `INTERVAL` 关键字用于表达式，但**没有 INTERVAL 列类型**：

```sql
-- 字面量（仅用于算术）
SELECT CURRENT_TIMESTAMP() + INTERVAL '1 month';
SELECT CURRENT_TIMESTAMP() + INTERVAL '1 year, 2 months, 3 days';
SELECT CURRENT_TIMESTAMP() + INTERVAL '5 minutes 30 seconds';

-- 不能存为列
CREATE TABLE t (duration INTERVAL);   -- 错误

-- 替代：用 TIMESTAMPDIFF / TIMESTAMPADD（与 SQL Server 类似）
SELECT TIMESTAMPADD(MONTH, 1, CURRENT_TIMESTAMP());
SELECT TIMESTAMPDIFF(DAY, '2024-01-01', '2024-12-31');     -- 365

-- DATEADD / DATEDIFF（更常用）
SELECT DATEADD(MONTH, 1, '2024-01-31');                    -- 2024-02-29
SELECT DATEDIFF(MONTH, '2024-01-15', '2025-03-15');        -- 14

-- 间隔加月底处理：与标准一致（截取月末）
SELECT '2024-01-31'::DATE + INTERVAL '1 month';            -- 2024-02-29
```

### DB2（labeled durations）

DB2 用一种独特的 "labeled duration" 语法，看起来像 INTERVAL 但实际是后缀关键字：

```sql
-- 字面量（数值 + 单位关键字）
SELECT CURRENT TIMESTAMP + 1 YEAR FROM SYSIBM.SYSDUMMY1;
SELECT CURRENT TIMESTAMP + 1 MONTH + 5 DAYS FROM SYSIBM.SYSDUMMY1;
SELECT CURRENT TIMESTAMP - 30 MINUTES FROM SYSIBM.SYSDUMMY1;

-- 单位：YEAR(S), MONTH(S), DAY(S), HOUR(S), MINUTE(S), SECOND(S),
--       MICROSECOND(S)

-- 月底处理（DB2 标准截取）
SELECT DATE('2024-01-31') + 1 MONTH FROM SYSIBM.SYSDUMMY1; -- 2024-02-29

-- DB2 没有真正的 INTERVAL 数据类型（labeled durations 只能用于表达式）
-- 但 DB2 LUW 11.5 起支持 TIMESTAMPDIFF
SELECT TIMESTAMPDIFF(64, CHAR(TIMESTAMP('2024-12-31') - TIMESTAMP('2024-01-01')))
FROM SYSIBM.SYSDUMMY1;
-- 64 = days, 4 = months, 2 = seconds, 等等（DB2 文档查表）

-- ISO 8601 不直接支持，需要用 VARCHAR_FORMAT/TIMESTAMP_FORMAT 解析
```

### DuckDB（PG 兼容 + 简洁字面量）

DuckDB 几乎完全兼容 PostgreSQL 的 INTERVAL 语法，且支持简洁的 `INTERVAL n UNIT` 形式：

```sql
SELECT INTERVAL 1 MONTH;
SELECT INTERVAL '1 month 2 days';
SELECT INTERVAL '1' YEAR TO MONTH;

-- 加减
SELECT TIMESTAMP '2024-01-15' + INTERVAL 1 MONTH;
SELECT TIMESTAMP '2024-01-31' + INTERVAL 1 MONTH;       -- 2024-02-29

-- 微秒精度
SELECT INTERVAL 1 MICROSECOND;

-- 间隔差
SELECT date_diff('month', '2024-01-15', '2025-03-15');  -- 14
SELECT date_diff('day', DATE '2024-01-01', DATE '2024-12-31');  -- 365

-- EXTRACT
SELECT EXTRACT(MILLISECOND FROM INTERVAL 1.5 SECOND);    -- 1500

-- INTERVAL 列类型
CREATE TABLE t (d INTERVAL);
INSERT INTO t VALUES (INTERVAL 1 DAY);
```

### Trino / Presto（标准的两类分离）

Trino 和 Presto 严格遵循 SQL:1992 的两类划分：

```sql
-- 字面量（标准格式）
SELECT INTERVAL '1' YEAR;
SELECT INTERVAL '1-2' YEAR TO MONTH;
SELECT INTERVAL '3' DAY;
SELECT INTERVAL '3 4:5:6.123' DAY TO SECOND;

-- 算术
SELECT TIMESTAMP '2024-01-15' + INTERVAL '1' MONTH;
SELECT TIMESTAMP '2024-01-31' + INTERVAL '1' MONTH;     -- 2024-02-29

-- 严格的类分离：以下会报错
-- SELECT INTERVAL '1' MONTH + INTERVAL '1' DAY;        -- 错误：两类不能混用

-- 间隔差
SELECT date_diff('day', DATE '2024-01-01', DATE '2024-12-31');

-- 列类型
CREATE TABLE t (
    ym INTERVAL YEAR TO MONTH,
    ds INTERVAL DAY TO SECOND
);
```

### Spark SQL / Databricks（自 3.2 起规范化）

Spark SQL 自 3.2 起将 INTERVAL 分为 `INTERVAL YEAR TO MONTH` 和 `INTERVAL DAY TO SECOND` 两个独立类型（之前是混合 CalendarInterval）：

```sql
-- 字面量
SELECT INTERVAL '1' YEAR;
SELECT INTERVAL '1-2' YEAR TO MONTH;
SELECT INTERVAL '3 4:5:6' DAY TO SECOND;
SELECT INTERVAL 1 MONTH;                            -- 简化形式
SELECT INTERVAL 'P1Y2M3DT4H5M6S';                   -- ISO 8601（部分版本）

-- 算术
SELECT TIMESTAMP '2024-01-15' + INTERVAL '1' MONTH;
SELECT TIMESTAMP '2024-01-31' + INTERVAL '1' MONTH; -- 2024-02-29

-- INTERVAL * 数值
SELECT INTERVAL '1' DAY * 7;

-- 间隔差
SELECT datediff(DATE '2024-12-31', DATE '2024-01-01');  -- 365

-- 注意：Spark 早期（3.0 及以前）使用单一 CalendarInterval，
-- 跨版本迁移需注意类型差异
```

### Hive（INTERVAL 自 1.2 起）

```sql
SELECT INTERVAL '1' YEAR;
SELECT INTERVAL '1-2' YEAR TO MONTH;
SELECT INTERVAL '3 4:5:6' DAY TO SECOND;

-- 算术
SELECT timestamp '2024-01-15 10:00:00' + INTERVAL '1' MONTH;
SELECT timestamp '2024-01-31 10:00:00' + INTERVAL '1' MONTH; -- 2024-02-29

-- 列类型
CREATE TABLE t (d INTERVAL DAY TO SECOND);
```

### Flink SQL（流处理中的 INTERVAL）

Flink SQL 完全支持 INTERVAL 类型，且在窗口函数（HOP、TUMBLE、SESSION）中是关键参数：

```sql
-- 字面量
SELECT INTERVAL '1' YEAR;
SELECT INTERVAL '1' DAY;
SELECT INTERVAL '10' MINUTE;
SELECT INTERVAL '1' YEAR TO MONTH;
SELECT INTERVAL '1' DAY TO SECOND;

-- 在窗口中作为参数
SELECT * FROM TABLE(
    TUMBLE(TABLE orders, DESCRIPTOR(rowtime), INTERVAL '10' MINUTES)
);

-- 算术
SELECT rowtime + INTERVAL '1' DAY FROM orders;
```

### Teradata

```sql
SELECT CURRENT_TIMESTAMP + INTERVAL '1' YEAR;
SELECT CURRENT_TIMESTAMP + INTERVAL '1-2' YEAR TO MONTH;
SELECT CURRENT_TIMESTAMP + INTERVAL '3 4:5:6.789' DAY TO SECOND;

-- 列类型
CREATE TABLE t (
    duration INTERVAL DAY(3) TO SECOND(6)
);

-- 月份溢出语义
SELECT DATE '2024-01-31' + INTERVAL '1' MONTH;
-- Teradata 严格：超界报错（与 Oracle 类似）
-- 解决：用 ADD_MONTHS
SELECT ADD_MONTHS(DATE '2024-01-31', 1);          -- 2024-02-29
```

### Vertica（PG 兼容）

```sql
-- 同 PostgreSQL
SELECT INTERVAL '1 year 2 months 3 days';
SELECT INTERVAL '1' YEAR TO MONTH;
SELECT INTERVAL 'P1Y2M3D';                        -- ISO 8601

-- 算术
SELECT TIMESTAMP '2024-01-31' + INTERVAL '1 month';   -- 2024-02-29

-- 列类型
CREATE TABLE t (d INTERVAL);
```

### Other engines

```sql
-- Greenplum / YugabyteDB / RisingWave / Materialize / TimescaleDB
-- 全部继承 PostgreSQL 的 INTERVAL 语法

-- Redshift（继承 PG，但受限）
SELECT INTERVAL '1 month';
SELECT TIMESTAMP '2024-01-31' + INTERVAL '1 month';   -- 2024-02-29
-- Redshift 历史上 INTERVAL 列存储有限，建议用 BIGINT 秒数

-- TiDB（兼容 MySQL）
SELECT NOW() + INTERVAL 1 MONTH;
SELECT TIMESTAMPDIFF(DAY, '2024-01-01', '2024-12-31');

-- OceanBase（多模式：MySQL/Oracle 模式）
-- MySQL 模式: SELECT NOW() + INTERVAL 1 MONTH;
-- Oracle 模式: SELECT SYSDATE + INTERVAL '1' MONTH;

-- Impala
SELECT NOW() + INTERVAL 1 MONTH;
SELECT NOW() + INTERVAL 1 MONTH + INTERVAL 5 DAY;

-- StarRocks / Doris / DatabendDB
-- 类似 ClickHouse/MySQL，仅在表达式中使用 INTERVAL 关键字
SELECT NOW() + INTERVAL 1 MONTH;

-- MonetDB
SELECT INTERVAL '1' MONTH;
SELECT TIMESTAMP '2024-01-31' + INTERVAL '1' MONTH;

-- Exasol
SELECT INTERVAL '1' YEAR;
SELECT TIMESTAMP '2024-01-31' + INTERVAL '1' MONTH;

-- Informix
SELECT EXTEND(CURRENT, YEAR TO SECOND) + INTERVAL ('1') YEAR TO YEAR FROM dual;

-- H2 / HSQLDB
SELECT INTERVAL '1' YEAR;
SELECT TIMESTAMP '2024-01-31' + INTERVAL '1' MONTH;

-- Spanner（PG 方言）
SELECT '2024-01-15'::TIMESTAMP + INTERVAL '1 month';
-- Spanner GoogleSQL 用 TIMESTAMP_ADD：
SELECT TIMESTAMP_ADD(TIMESTAMP '2024-01-15', INTERVAL 1 MONTH);

-- SAP HANA
SELECT ADD_MONTHS(CURRENT_TIMESTAMP, 1) FROM DUMMY;
SELECT ADD_SECONDS(CURRENT_TIMESTAMP, 60) FROM DUMMY;
-- HANA 不支持 INTERVAL 字面量，全用 ADD_*  函数
```

## YEAR-MONTH 与 DAY-TIME 类的不兼容性

SQL:1992 把 INTERVAL 划分为两个互不兼容的类，根本原因是**月份长度可变**：

```
1 月 = 31 天
2 月 = 28 或 29 天
4 月 = 30 天
...
```

这意味着 `INTERVAL '1' MONTH` **无法转换为固定的秒/天数**，因此：

1. `INTERVAL YEAR TO MONTH` 内部存储为"总月数"（如 14 个月）
2. `INTERVAL DAY TO SECOND` 内部存储为"总微秒数"（或秒 + 微秒）
3. 两个类**不能相加减、不能比较、不能转换**

### 各引擎对类分离的态度

| 引擎 | 严格分离 | 备注 |
|------|---------|------|
| Oracle | 是 | 类型签名严格区分，跨类报错 |
| Trino/Presto | 是 | 严格遵循标准 |
| Spark SQL（3.2+） | 是 | 新版规范化 |
| BigQuery | 是 | 按字段范围声明类 |
| Hive | 是 | 标准实现 |
| PostgreSQL | 否（混合） | 单一 INTERVAL 类型可同时存年月日 |
| DuckDB | 否（混合） | 兼容 PG |
| MySQL/MariaDB | 不适用 | 仅表达式，无独立类型 |
| ClickHouse | 不适用 | 仅表达式 |

PostgreSQL 的"混合"模型在实践中更方便（如 `INTERVAL '1 year 2 months 3 days'`），但牺牲了部分标准兼容性。从 PostgreSQL 迁移到 Oracle 需要拆分为两个独立列。

### 跨引擎语义陷阱：30 天 ≠ 1 个月

```sql
-- PostgreSQL（混合模式）
SELECT INTERVAL '30 days' = INTERVAL '1 month';    -- false
SELECT INTERVAL '30 days' < INTERVAL '1 month';    -- 取决于 IntervalStyle

-- Oracle（严格分离）
SELECT INTERVAL '30' DAY = INTERVAL '1' MONTH;
-- ORA-30081: invalid data type for datetime/interval arithmetic

-- 用户经常错误地认为 30 天 = 1 月，导致结果不一致
```

## 月份加法的边界情况：'2024-01-31' + 1 month

这是 INTERVAL 算术中**最容易踩坑**的语义差异。各引擎对"超过目标月最大日"的处理策略不同：

| 引擎 | `'2024-01-31' + 1 月` | 策略 |
|------|---------------------|------|
| PostgreSQL | `'2024-02-29'` | 截取到目标月最后一天（标准） |
| Oracle (`+ INTERVAL`) | ORA-01839 错误 | 严格：目标日不存在则报错 |
| Oracle (`ADD_MONTHS`) | `'2024-02-29'` | 月末截取 |
| SQL Server (`DATEADD`) | `'2024-02-29'` | 月末截取 |
| MySQL | `'2024-02-29'` | 月末截取 |
| MariaDB | `'2024-02-29'` | 月末截取 |
| SQLite | `'2024-03-02'` | 溢出到下月 |
| BigQuery | `'2024-02-29'` | 月末截取 |
| Snowflake | `'2024-02-29'` | 月末截取（默认） |
| ClickHouse | `'2024-02-29'` | 月末截取 |
| DuckDB | `'2024-02-29'` | 月末截取 |
| Trino/Presto | `'2024-02-29'` | 月末截取 |
| Spark SQL | `'2024-02-29'` | 月末截取 |
| Hive | `'2024-02-29'` | 月末截取 |
| DB2 | `'2024-02-29'` | 月末截取 |
| Teradata (`+ INTERVAL`) | 错误 | 严格 |
| Teradata (`ADD_MONTHS`) | `'2024-02-29'` | 月末截取 |
| Vertica | `'2024-02-29'` | 月末截取 |
| Redshift | `'2024-02-29'` | 月末截取 |

### Snowflake 的"月末保持"语义（last-day-of-month preservation）

Snowflake 还有一个独特的会话参数 `LAST_DAY_OF_MONTH` 和 `WEEK_OF_YEAR_POLICY`，控制特殊语义：

```sql
-- DEFAULT: 标准月末截取
SELECT DATE '2024-01-31' + INTERVAL '1 month';   -- 2024-02-29

-- 参数 ADD_MONTHS_END_OF_MONTH_POLICY = 'PRESERVE'（部分库会启用）：
-- 月末日期 + 月份 → 仍然是月末日
SELECT ADD_MONTHS('2024-01-31', 1);              -- 2024-02-29 (月末)
SELECT ADD_MONTHS('2024-02-29', 1);              -- 2024-03-31 (月末，而非 3-29)
```

### 非单调性（不可逆）

无论哪种策略，月份加法**都不是单调可逆**的：

```sql
-- 加 1 月再减 1 月，不一定回到原日期
SELECT (DATE '2024-01-31' + INTERVAL '1 month') - INTERVAL '1 month';
-- 结果可能是 '2024-01-29'（PG/MySQL/Snowflake）
-- 或 '2024-01-31'（Snowflake LAST_DAY_OF_MONTH 策略）

-- 此特性导致月份加法不能用于"对称"区间运算
SELECT * FROM events
WHERE event_time >= start_date - INTERVAL '1 month'
  AND event_time <  start_date + INTERVAL '1 month';
-- 区间长度可能不是 2 个月（取决于 start_date 是否在月末）
```

### 闰年陷阱

```sql
-- 闰日加 1 年
SELECT DATE '2024-02-29' + INTERVAL '1 year';
-- PostgreSQL: 2025-02-28（截取）
-- Oracle (+ INTERVAL): ORA-01839 错误
-- Oracle (ADD_MONTHS, 12): 2025-02-28
-- MySQL: 2025-02-28
-- SQL Server (DATEADD): 2025-02-28
-- BigQuery: 2025-02-28
-- SQLite: 2025-03-01（溢出）
```

### 统一处理建议

对跨引擎应用，强烈推荐：

1. **避免在月末日期上做月份加减**——若必须，先 `DATE_TRUNC('month', x)` 归一到月初
2. **使用绝对天数代替月份**（如 `INTERVAL '30 days'`），但仅在业务允许的情况下
3. **统一使用 `ADD_MONTHS` 函数**而非 `+ INTERVAL`，因为多数引擎的 `ADD_MONTHS` 行为更可预期
4. **跨引擎迁移时**对所有月份加法做单元测试，重点关注 1/31、3/31、5/31、7/31、8/31、10/31、12/31 这些"长月末"

## ISO 8601 持续时间支持

ISO 8601 持续时间格式 `P[n]Y[n]M[n]DT[n]H[n]M[n]S` 是跨语言/跨系统通用的字符串格式：

```
P1Y2M3DT4H5M6S = 1 年 2 月 3 天 4 小时 5 分 6 秒
PT0.5S         = 0.5 秒
P30D           = 30 天
P1W            = 1 周（部分引擎）
```

### 直接支持 ISO 8601 字面量的引擎

```sql
-- PostgreSQL（IntervalStyle = 'iso_8601' 时也输出此格式）
SELECT INTERVAL 'P1Y2M3DT4H5M6S';
SELECT INTERVAL 'P0001-02-03T04:05:06';            -- 备选格式

-- Oracle
SELECT TO_YMINTERVAL('P1Y2M') FROM DUAL;
SELECT TO_DSINTERVAL('P3DT4H5M6.789S') FROM DUAL;

-- Spark SQL（部分版本）
SELECT INTERVAL 'P1Y2M3DT4H5M6S';

-- Hive
SELECT INTERVAL 'P1Y2M3D';

-- Vertica
SELECT INTERVAL 'P1Y2M3D';
```

### 不直接支持的引擎（需要手工拆解）

```sql
-- MySQL/MariaDB：拆为多个 INTERVAL
SELECT NOW() + INTERVAL 1 YEAR + INTERVAL 2 MONTH + INTERVAL 3 DAY
              + INTERVAL 4 HOUR + INTERVAL 5 MINUTE + INTERVAL 6 SECOND;

-- SQL Server：DATEADD 链式
SELECT DATEADD(SECOND, 6,
       DATEADD(MINUTE, 5,
       DATEADD(HOUR, 4,
       DATEADD(DAY, 3,
       DATEADD(MONTH, 2,
       DATEADD(YEAR, 1, GETDATE()))))));

-- Snowflake
SELECT CURRENT_TIMESTAMP + INTERVAL '1 year, 2 months, 3 days, 4 hours, 5 minutes, 6 seconds';

-- BigQuery
SELECT CURRENT_TIMESTAMP() + INTERVAL '1-2 3 4:5:6' YEAR TO SECOND;

-- ClickHouse
SELECT now() + toIntervalYear(1)
              + toIntervalMonth(2)
              + toIntervalDay(3)
              + toIntervalHour(4)
              + toIntervalMinute(5)
              + toIntervalSecond(6);

-- DuckDB（用 INTERVAL 字符串拼装）
SELECT NOW() + INTERVAL '1 year 2 months 3 days 4 hours 5 minutes 6 seconds';
```

### 双向转换的关键点

ISO 8601 解析在 API/网关层最常见。各引擎的解析严格度不同：

| 引擎 | 接受 `P1Y` | 接受 `P30D` | 接受 `P1.5D` | 接受 `P1W` |
|------|-----------|------------|--------------|-----------|
| PostgreSQL | 是 | 是 | 是 | 是 |
| Oracle | 是 | 是 | 是 | -- |
| Vertica | 是 | 是 | 是 | -- |
| Spark | 是 | 是 | -- | -- |

应用层最通用的做法是**用 Java/Python/Go 的标准库解析 ISO 8601**，再拆为各字段后构造引擎特定的 INTERVAL 表达式。

## EXTRACT 从 INTERVAL 取值

SQL 标准的 `EXTRACT(field FROM interval)` 用于从 INTERVAL 中提取某个字段的数值：

```sql
-- PostgreSQL
SELECT EXTRACT(YEAR  FROM INTERVAL '5 years 3 months');     -- 5
SELECT EXTRACT(MONTH FROM INTERVAL '5 years 3 months');     -- 3
SELECT EXTRACT(DAY   FROM INTERVAL '40 days');              -- 40
SELECT EXTRACT(HOUR  FROM INTERVAL '36 hours');             -- 36
SELECT EXTRACT(EPOCH FROM INTERVAL '1 day');                -- 86400.0
SELECT EXTRACT(EPOCH FROM INTERVAL '1 month');              -- 2592000.0（按 30 天近似！）

-- Oracle（YEAR-MONTH）
SELECT EXTRACT(YEAR  FROM INTERVAL '5-3' YEAR TO MONTH) FROM DUAL;   -- 5
SELECT EXTRACT(MONTH FROM INTERVAL '5-3' YEAR TO MONTH) FROM DUAL;   -- 3

-- Oracle（DAY-TIME）
SELECT EXTRACT(DAY    FROM INTERVAL '3 4:5:6' DAY TO SECOND) FROM DUAL;   -- 3
SELECT EXTRACT(HOUR   FROM INTERVAL '3 4:5:6' DAY TO SECOND) FROM DUAL;   -- 4
SELECT EXTRACT(SECOND FROM INTERVAL '3 4:5:6.789' DAY TO SECOND) FROM DUAL; -- 6.789

-- BigQuery
SELECT EXTRACT(YEAR  FROM INTERVAL '5-3' YEAR TO MONTH);    -- 5
SELECT EXTRACT(MONTH FROM INTERVAL '5-3' YEAR TO MONTH);    -- 3

-- Trino
SELECT EXTRACT(YEAR  FROM INTERVAL '5-3' YEAR TO MONTH);
SELECT EXTRACT(SECOND FROM INTERVAL '3 4:5:6.789' DAY TO SECOND);

-- Snowflake：不支持 EXTRACT FROM INTERVAL（INTERVAL 不是值）
-- 替代：用 DATEDIFF
SELECT DATEDIFF(MONTH, '2024-01-15', '2025-03-15');   -- 14（月数）
```

### EXTRACT EPOCH 的陷阱

```sql
-- PG / DuckDB：EPOCH 是"假定 30 天 = 1 月，365.25 天 = 1 年"
SELECT EXTRACT(EPOCH FROM INTERVAL '1 year');     -- 31557600.0（= 365.25 * 86400）
SELECT EXTRACT(EPOCH FROM INTERVAL '1 month');    -- 2592000.0（= 30 * 86400）

-- 这意味着 EPOCH 是近似值，不可逆！
-- INTERVAL '12 months' 与 INTERVAL '1 year' 的 EPOCH 不同：
SELECT EXTRACT(EPOCH FROM INTERVAL '12 months');  -- 31104000（= 360 * 86400）
SELECT EXTRACT(EPOCH FROM INTERVAL '1 year');     -- 31557600
```

## 关键发现

### 1. INTERVAL 类型支持极度分化（46+ 引擎）

调研的 46+ 引擎中，约 **25 个有原生 INTERVAL 列类型**（PG 系、Oracle、BigQuery、Trino、Spark 3.2+、DuckDB、Vertica、Teradata 等），**约 12 个仅支持表达式中的 INTERVAL 关键字**（MySQL、MariaDB、TiDB、ClickHouse、Snowflake、Impala、StarRocks、Doris、SingleStore、DatabendDB、OceanBase、SAP HANA），**约 9 个完全不支持 INTERVAL**（SQL Server、Azure Synapse、SQLite、Firebolt、CrateDB、QuestDB、Derby、Firebird、InfluxDB SQL）。

### 2. SQL:1992 的"两类分离"是标准但 PG 打破了它

SQL:1992 的 INTERVAL YEAR TO MONTH 和 INTERVAL DAY TO SECOND 是不可加减的两个独立类，Oracle、Trino、Spark 3.2+、BigQuery、Hive 严格遵循。**PostgreSQL 在内部用 `(months, days, microseconds)` 三字段表示**，允许 `INTERVAL '1 year 2 months 3 days'` 这种混合形式，牺牲了与标准的兼容性换取了实用性。从 PG 迁移到 Oracle 通常需要拆字段。

### 3. SQL Server 至今没有 INTERVAL（25+ 年）

SQL Server 1989 年发布以来从未引入 INTERVAL 类型，所有时间间隔运算依赖 `DATEADD` / `DATEDIFF` 等函数。Azure Synapse 和 Microsoft Fabric SQL 沿用此设计。这是与 SQL:1992 标准最大的偏离。

### 4. BigQuery 直到 2021 才有 INTERVAL 类型

BigQuery 作为云数据仓库标杆之一，**INTERVAL 类型 2021 年才 GA**。这反映了云仓库设计早期更关注列存性能而非完整类型系统。Snowflake 至今仍未引入 INTERVAL 列类型，仅保留 INTERVAL 表达式。

### 5. '2024-01-31' + 1 月 有 4 种结果

* **截取月末**（`2024-02-29`）：PG、MySQL、SQL Server、Snowflake、BigQuery、ClickHouse、Trino、Spark、DuckDB 等多数引擎
* **报错**：Oracle 的 `+ INTERVAL`、Teradata 的 `+ INTERVAL`
* **溢出到下月**（`2024-03-02`）：SQLite
* **月末保持**（`2024-03-31`）：Snowflake `ADD_MONTHS` 在月末日期保持月末

跨引擎应用必须为月末日期的 INTERVAL 加法做专门测试。

### 6. ISO 8601 持续时间字面量是少数引擎特性

只有 **PostgreSQL、Oracle、Spark（部分版本）、Hive、Vertica** 直接接受 ISO 8601 字符串作为 INTERVAL 字面量。MySQL、ClickHouse、Snowflake、BigQuery 等需要应用层先解析 ISO 8601 格式再拼装为引擎特有的 INTERVAL 表达式。

### 7. EXTRACT EPOCH 的"30 天 = 1 月"近似可能误导

PG 和 DuckDB 的 `EXTRACT(EPOCH FROM INTERVAL '1 month')` 返回 2592000（30 * 86400），是为兼容旧脚本的近似值。这意味着 `INTERVAL '12 months'` 与 `INTERVAL '1 year'` 的 EPOCH 不相等（前者 31104000，后者 31557600）。在做秒级精确换算时务必避免使用月份字段。

### 8. 微秒精度普遍但纳秒罕见

绝大多数支持 INTERVAL 的引擎使用**微秒级精度**（PG、Oracle、SQL Server、MySQL 5.6.4+、BigQuery、Snowflake、ClickHouse 自 21.7+）。**纳秒级精度仅 ClickHouse、Spark、Flink、DuckDB** 等少数引擎支持。这与底层时间戳类型的精度直接相关。

### 9. 自动单位规范化（justify_*）是 PG 特有

PostgreSQL 的 `justify_hours / justify_days / justify_interval` 函数把超过 24 小时的小时数、超过 30 天的天数等"规范化"到更高级单位。这种**有损但便于显示**的转换其他引擎几乎都不支持，迁移时需用应用层逻辑替代。

### 10. INTERVAL × 数值仅约半数引擎支持

`INTERVAL × INT` 和 `INTERVAL / INT`（如 `INTERVAL '1' DAY * 7`）在 PG、Oracle、BigQuery、DuckDB、Spark、Trino 等支持，但 MySQL、ClickHouse、Snowflake、SQL Server 等不直接支持，需要用 `INTERVAL n*7 DAY` 形式或函数模拟。

## 总结对比矩阵

### INTERVAL 能力总览

| 能力 | PG | Oracle | SQL Server | MySQL | SQLite | BigQuery | Snowflake | ClickHouse | Trino | DuckDB | Spark |
|------|----|----|------|------|------|--------|---------|-----------|------|------|------|
| 原生 INTERVAL 列 | 是 | 是 | -- | -- | -- | 是 | -- | -- | 是 | 是 | 是 |
| YEAR-MONTH 类 | 混合 | 是 | -- | 表达式 | -- | 是 | 表达式 | 表达式 | 是 | 混合 | 是 |
| DAY-TIME 类 | 混合 | 是 | -- | 表达式 | 修饰符 | 是 | 表达式 | 表达式 | 是 | 混合 | 是 |
| INT * INTERVAL | 是 | 是 | -- | -- | -- | 是 | 是 | -- | 是 | 是 | 是 |
| EXTRACT FROM | 是 | 是 | -- | 不适用 | 不适用 | 是 | -- | 不适用 | 是 | 是 | 是 |
| ISO 8601 字面量 | 是 | 是 | -- | -- | -- | -- | -- | -- | -- | -- | 部分 |
| 月末截取 | 是 | ADD_MONTHS | 是 | 是 | 溢出 | 是 | 是 | 是 | 是 | 是 | 是 |
| 微秒精度 | 是 | 是 | 是 | 是 | -- | 是 | 是 | 是 | 是 | 是 | 是 |
| 纳秒精度 | -- | -- | -- | -- | -- | -- | -- | 是 | -- | 是 | 是 |
| INTERVAL 比较 | 是 | 同类 | 不适用 | 不适用 | 不适用 | 是 | -- | 不适用 | 是 | 是 | 是 |

### 工程选型建议

| 场景 | 推荐方法 | 原因 |
|------|---------|------|
| 严格的标准 INTERVAL | Oracle / Trino | 严格分离两类，类型安全 |
| 灵活的混合 INTERVAL | PostgreSQL / DuckDB | 单一类型，年月日时秒可混合 |
| 流处理窗口参数 | Flink SQL INTERVAL | 窗口函数原生集成 |
| 跨语言交换 | ISO 8601 + PG/Oracle | 标准格式，可直接解析 |
| 无 INTERVAL 引擎兼容 | DATEADD/DATEDIFF | SQL Server/Snowflake 通用模式 |
| 大数据预聚合时间桶 | 整数秒 + 应用层换算 | 列存友好，无类型解析 |
| 业务"月末日"敏感场景 | DATE_TRUNC + 数值天数 | 避免月份加法非单调陷阱 |

## 参考资料

- SQL:1992 标准: ISO/IEC 9075:1992, Section 4.5（datetime types and intervals）, Section 6.14（datetime/interval arithmetic）
- PostgreSQL: [Date/Time Types - Interval](https://www.postgresql.org/docs/current/datatype-datetime.html#DATATYPE-INTERVAL-INPUT)
- Oracle: [Datetime/Interval Arithmetic](https://docs.oracle.com/en/database/oracle/oracle-database/19/sqlrf/Data-Types.html#GUID-7690645A-0EE3-46CA-90DE-C96DF5A01F8F)
- SQL Server: [DATEADD](https://learn.microsoft.com/en-us/sql/t-sql/functions/dateadd-transact-sql) / [DATEDIFF](https://learn.microsoft.com/en-us/sql/t-sql/functions/datediff-transact-sql)
- MySQL: [Date and Time Functions - Temporal Intervals](https://dev.mysql.com/doc/refman/8.0/en/date-and-time-functions.html)
- BigQuery: [Interval type](https://cloud.google.com/bigquery/docs/reference/standard-sql/data-types#interval_type)（GA 2021）
- Snowflake: [Date and Time Operators](https://docs.snowflake.com/en/sql-reference/functions-date-time)
- DuckDB: [Interval Types](https://duckdb.org/docs/sql/data_types/interval)
- ClickHouse: [INTERVAL operator](https://clickhouse.com/docs/en/sql-reference/operators/#operator-interval)
- Trino: [Date and Time Operators](https://trino.io/docs/current/functions/datetime.html)
- Spark SQL: [Year-Month / Day-Time Interval Types](https://spark.apache.org/docs/latest/sql-ref-datatypes.html)
- Apache Hive: [Hive Data Types - Interval](https://cwiki.apache.org/confluence/display/Hive/LanguageManual+Types)
- ISO 8601: Date and time format - Durations
