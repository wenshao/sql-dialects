# 日期时间函数名映射：各 SQL 方言全对比

> 参考资料:
> - [MySQL 8.0 - Date and Time Functions](https://dev.mysql.com/doc/refman/8.0/en/date-and-time-functions.html)
> - [PostgreSQL - Date/Time Functions](https://www.postgresql.org/docs/current/functions-datetime.html)
> - [SQL Server - Date and Time Functions](https://learn.microsoft.com/en-us/sql/t-sql/functions/date-and-time-data-types-and-functions-transact-sql)
> - [BigQuery - Date Functions](https://cloud.google.com/bigquery/docs/reference/standard-sql/date_functions)
> - [Snowflake - Date & Time Functions](https://docs.snowflake.com/en/sql-reference/functions-date-time)

日期时间处理是 SQL 跨引擎迁移中最危险的领域。函数名不同还好办（编译期报错），真正致命的是**参数顺序不同**——同名函数 `DATEADD`/`DATEDIFF` 在不同引擎中参数位置完全相反，编译通过但结果错误，往往上线后才发现。

本文覆盖 16 个主流引擎：MySQL, PostgreSQL, SQL Server, Oracle, SQLite, BigQuery, Snowflake, ClickHouse, DuckDB, Trino, Hive, Spark SQL, Redshift, StarRocks, Doris, MaxCompute。

---

## 1. 日期加减（DATE_ADD / DATEADD / + INTERVAL）

> **迁移陷阱 #1**: `DATEADD` 参数顺序在 SQL Server 和 MaxCompute 中完全相反。

### 语法分类

| 模式 | 语法 | 引擎 |
|------|------|------|
| A: DATEADD(unit, delta, date) | `DATEADD(DAY, 7, date_col)` | SQL Server, Snowflake, Redshift |
| B: DATEADD(date, delta, unit) | `DATEADD(date_col, 7, 'dd')` | MaxCompute |
| C: DATE_ADD(date, INTERVAL) | `DATE_ADD(date_col, INTERVAL 7 DAY)` | MySQL, BigQuery, StarRocks, Doris |
| D: DATE_ADD('unit', delta, date) | `DATE_ADD('day', 7, date_col)` | Trino |
| E: DATE_ADD(date, days) | `DATE_ADD(date_col, 7)` | Hive, Spark SQL |
| F: date + INTERVAL | `date_col + INTERVAL '7 day'` | PostgreSQL, DuckDB, ClickHouse |
| G: date + integer | `date_col + 7` | Oracle（天数）, SQLite（需 DATE 函数） |

### 各引擎详细语法

```sql
-- SQL Server: DATEADD(unit, delta, date) —— unit 在最前
SELECT DATEADD(DAY, 7, '2024-01-01');
SELECT DATEADD(MONTH, -3, GETDATE());

-- Snowflake: 同 SQL Server 语法
SELECT DATEADD(DAY, 7, '2024-01-01');
SELECT DATEADD('DAY', 7, '2024-01-01');  -- 字符串形式也行

-- Redshift: 同 SQL Server 语法
SELECT DATEADD(DAY, 7, '2024-01-01');

-- ⚠️ MaxCompute: DATEADD(date, delta, unit) —— date 在最前，unit 在最后！
SELECT DATEADD('2024-01-01', 7, 'dd');
SELECT DATEADD(date_col, -3, 'mm');
-- 与 SQL Server 的 DATEADD(DAY, 7, date) 参数位置完全相反！

-- MySQL: DATE_ADD + INTERVAL 关键字
SELECT DATE_ADD('2024-01-01', INTERVAL 7 DAY);
SELECT DATE_SUB('2024-01-01', INTERVAL 3 MONTH);
-- 也支持: SELECT '2024-01-01' + INTERVAL 7 DAY;

-- BigQuery: 同 MySQL 风格
SELECT DATE_ADD('2024-01-01', INTERVAL 7 DAY);
SELECT DATETIME_ADD(datetime_col, INTERVAL 1 HOUR);  -- 注意用 DATETIME_ADD
SELECT TIMESTAMP_ADD(ts_col, INTERVAL 1 HOUR);       -- 注意用 TIMESTAMP_ADD

-- StarRocks / Doris: 同 MySQL 风格
SELECT DATE_ADD('2024-01-01', INTERVAL 7 DAY);
-- 也支持: SELECT DAYS_ADD('2024-01-01', 7);

-- Trino: DATE_ADD('unit', delta, date) —— 单引号包裹 unit
SELECT DATE_ADD('day', 7, DATE '2024-01-01');
SELECT DATE_ADD('hour', 3, TIMESTAMP '2024-01-01 10:00:00');

-- Hive / Spark SQL: DATE_ADD(date, days_integer) —— 仅支持天数！
SELECT DATE_ADD('2024-01-01', 7);
-- 加月份要用 ADD_MONTHS:
SELECT ADD_MONTHS('2024-01-01', 3);

-- PostgreSQL: INTERVAL 算术
SELECT DATE '2024-01-01' + INTERVAL '7 days';
SELECT CURRENT_DATE + 7;  -- 直接加整数（天数）
SELECT CURRENT_TIMESTAMP + INTERVAL '3 hours';

-- DuckDB: 同 PostgreSQL 风格（不支持 SQL Server 三参数 DATEADD）
SELECT DATE '2024-01-01' + INTERVAL 7 DAY;
-- 或 DATE_ADD(date, INTERVAL n unit) 两参数形式

-- ClickHouse: INTERVAL 算术或专用函数
SELECT toDate('2024-01-01') + INTERVAL 7 DAY;
SELECT addDays(toDate('2024-01-01'), 7);      -- 专用函数
SELECT addMonths(toDate('2024-01-01'), 3);
-- 注意: ClickHouse 不支持 SQL Server 风格的 DATEADD(unit, delta, date) 三参数形式

-- Oracle: date + integer（天数）或 INTERVAL
SELECT SYSDATE + 7 FROM DUAL;                       -- 加 7 天
SELECT SYSDATE + INTERVAL '3' MONTH FROM DUAL;
SELECT ADD_MONTHS(SYSDATE, 3) FROM DUAL;
-- ⚠️ Oracle ADD_MONTHS 月末对齐：2月28日+1月=3月31日（输入为月末则结果也为月末）
-- MySQL/PG/SQL Server 使用 Clamping：2月28日+1月=3月28日（财务系统致命差异！）

-- SQLite: DATE 函数 + modifier
SELECT DATE('2024-01-01', '+7 days');
SELECT DATE('now', '-3 months');
SELECT DATETIME('now', '+2 hours');
```

### 参数顺序速查表

| 引擎 | 第 1 参数 | 第 2 参数 | 第 3 参数 | 示例 |
|------|-----------|-----------|-----------|------|
| **SQL Server** | unit | delta | date | `DATEADD(DAY, 7, d)` |
| **Snowflake** | unit | delta | date | `DATEADD(DAY, 7, d)` |
| **Redshift** | unit | delta | date | `DATEADD(DAY, 7, d)` |
| **MaxCompute** | date | delta | unit | `DATEADD(d, 7, 'dd')` |
| **MySQL** | date | INTERVAL expr | - | `DATE_ADD(d, INTERVAL 7 DAY)` |
| **BigQuery** | date | INTERVAL expr | - | `DATE_ADD(d, INTERVAL 7 DAY)` |
| **StarRocks** | date | INTERVAL expr | - | `DATE_ADD(d, INTERVAL 7 DAY)` |
| **Doris** | date | INTERVAL expr | - | `DATE_ADD(d, INTERVAL 7 DAY)` |
| **Trino** | 'unit' | delta | date | `DATE_ADD('day', 7, d)` |
| **Hive** | date | days_int | - | `DATE_ADD(d, 7)` |
| **Spark SQL** | date | days_int | - | `DATE_ADD(d, 7)` |
| **PostgreSQL** | (算术) | - | - | `d + INTERVAL '7 day'` |
| **DuckDB** | (算术) | - | - | `d + INTERVAL 7 DAY` |
| **ClickHouse** | (算术/函数) | - | - | `d + INTERVAL 7 DAY` |
| **Oracle** | (算术) | - | - | `d + 7` 或 `ADD_MONTHS(d,3)` |
| **SQLite** | (函数) | - | - | `DATE(d, '+7 days')` |

---

## 2. 日期差（DATEDIFF / DATE_DIFF）

> **迁移陷阱 #2**: `DATEDIFF` 同名函数在不同引擎中 start/end 位置相反，unit 参数有的在前有的在后，有的不支持 unit。

### 语法分类

| 模式 | 语法 | 引擎 | 返回值 |
|------|------|------|--------|
| A: DATEDIFF(end, start) | `DATEDIFF('2024-01-08', '2024-01-01')` → 7 | MySQL, Hive, Spark, StarRocks, Doris | 天数（仅天数） |
| B: DATEDIFF(unit, start, end) | `DATEDIFF(DAY, '2024-01-01', '2024-01-08')` → 7 | SQL Server, Snowflake, Redshift | 指定 unit 的差值 |
| C: DATEDIFF(end, start, unit) | `DATEDIFF('2024-01-08', '2024-01-01', 'dd')` → 7 | MaxCompute | 指定 unit 的差值 |
| D: DATE_DIFF(end, start, unit) | `DATE_DIFF('2024-01-08', '2024-01-01', DAY)` → 7 | BigQuery | 指定 unit 的差值 |
| E: DATE_DIFF('unit', start, end) | `DATE_DIFF('day', start, end)` → 7 | Trino, DuckDB | 指定 unit 的差值 |
| F: end - start | `DATE '2024-01-08' - DATE '2024-01-01'` → 7 | PostgreSQL, Oracle | 天数（整数） |
| G: JULIANDAY 差值 | `JULIANDAY('2024-01-08') - JULIANDAY('2024-01-01')` | SQLite | 天数（浮点） |
| H: 专用函数 | `dateDiff('day', start, end)` | ClickHouse | 指定 unit 的差值 |

### 各引擎详细语法

```sql
-- ⚠️ MySQL: DATEDIFF(end, start) —— 只算天数，end 在前
SELECT DATEDIFF('2024-01-08', '2024-01-01');  -- 7
SELECT DATEDIFF('2024-01-01', '2024-01-08');  -- -7
-- 要算月差: SELECT TIMESTAMPDIFF(MONTH, '2024-01-01', '2024-04-01');  -- 3
-- 注意 TIMESTAMPDIFF 的顺序: (unit, start, end) 与 DATEDIFF(end, start) 不同！

-- ⚠️ SQL Server: DATEDIFF(unit, start, end) —— start 在前，有 unit
SELECT DATEDIFF(DAY, '2024-01-01', '2024-01-08');   -- 7
SELECT DATEDIFF(MONTH, '2024-01-01', '2024-04-01'); -- 3
SELECT DATEDIFF(YEAR, '2020-12-31', '2021-01-01');  -- 1（跨年即算！）
-- ⚠️ SQL Server DATEDIFF 是 "边界跨越" 语义，不是完整间隔
-- ⚠️ DATEDIFF 返回 INT（4 字节），毫秒差超过 ~24.8 天会溢出！用 DATEDIFF_BIG (2016+) 替代

-- Snowflake: 同 SQL Server 语法
SELECT DATEDIFF(DAY, '2024-01-01', '2024-01-08');  -- 7
SELECT DATEDIFF('DAY', '2024-01-01', '2024-01-08'); -- 字符串形式也行

-- Redshift: 同 SQL Server 语法
SELECT DATEDIFF(DAY, '2024-01-01', '2024-01-08');  -- 7

-- ⚠️ MaxCompute: DATEDIFF(end, start, unit) —— end 在前，unit 在最后
SELECT DATEDIFF('2024-01-08', '2024-01-01', 'dd');  -- 7
SELECT DATEDIFF('2024-04-01', '2024-01-01', 'mm');  -- 3
-- 与 SQL Server 的参数顺序完全不同！

-- BigQuery: DATE_DIFF（注意有下划线）
SELECT DATE_DIFF(DATE '2024-01-08', DATE '2024-01-01', DAY);  -- 7
SELECT DATETIME_DIFF(dt1, dt2, HOUR);
SELECT TIMESTAMP_DIFF(ts1, ts2, SECOND);

-- Trino / DuckDB: DATE_DIFF('unit', start, end)
SELECT DATE_DIFF('day', DATE '2024-01-01', DATE '2024-01-08');  -- 7
SELECT DATE_DIFF('month', DATE '2024-01-01', DATE '2024-04-01');  -- 3

-- Hive / Spark SQL: DATEDIFF(end, start) —— 同 MySQL，仅天数
SELECT DATEDIFF('2024-01-08', '2024-01-01');  -- 7
-- Spark 3.3+: 按单位计算用 TIMESTAMPDIFF(unit, start, end)
SELECT TIMESTAMPDIFF(MONTH, '2024-01-01', '2024-04-01');  -- 3
-- 注意: DATEDIFF 本身始终只返回天数，不支持 unit 参数

-- StarRocks / Doris: DATEDIFF(end, start) —— 同 MySQL，仅天数
SELECT DATEDIFF('2024-01-08', '2024-01-01');  -- 7
-- 也支持: SELECT TIMESTAMPDIFF(MONTH, '2024-01-01', '2024-04-01');

-- PostgreSQL: 直接相减
SELECT DATE '2024-01-08' - DATE '2024-01-01';  -- 7 (integer)
SELECT AGE(TIMESTAMP '2024-04-01', TIMESTAMP '2024-01-01');  -- '3 mons' (interval)
SELECT EXTRACT(EPOCH FROM (ts1 - ts2));  -- 秒数差

-- Oracle: 直接相减
SELECT DATE '2024-01-08' - DATE '2024-01-01' FROM DUAL;  -- 7 (number)
SELECT MONTHS_BETWEEN(DATE '2024-04-01', DATE '2024-01-01') FROM DUAL;  -- 3

-- ClickHouse: dateDiff('unit', start, end)
SELECT dateDiff('day', toDate('2024-01-01'), toDate('2024-01-08'));  -- 7
SELECT dateDiff('month', toDate('2024-01-01'), toDate('2024-04-01'));  -- 3

-- SQLite: 用 JULIANDAY 相减
SELECT JULIANDAY('2024-01-08') - JULIANDAY('2024-01-01');  -- 7.0
SELECT CAST(JULIANDAY('2024-01-08') - JULIANDAY('2024-01-01') AS INTEGER);  -- 7
```

### DATEDIFF 参数顺序速查表

| 引擎 | 第 1 参数 | 第 2 参数 | 第 3 参数 | 仅天数？ |
|------|-----------|-----------|-----------|----------|
| **MySQL** | end_date | start_date | - | 是 |
| **Hive** | end_date | start_date | - | 是 |
| **Spark SQL** | end_date | start_date | - | 是（2.x） |
| **StarRocks** | end_date | start_date | - | 是 |
| **Doris** | end_date | start_date | - | 是 |
| **SQL Server** | unit | start_date | end_date | 否 |
| **Snowflake** | unit | start_date | end_date | 否 |
| **Redshift** | unit | start_date | end_date | 否 |
| **MaxCompute** | end_date | start_date | unit | 否 |
| **BigQuery** | end_date | start_date | unit | 否 |
| **Trino** | 'unit' | start_date | end_date | 否 |
| **DuckDB** | 'unit' | start_date | end_date | 否 |
| **ClickHouse** | 'unit' | start_date | end_date | 否 |
| **PostgreSQL** | (相减) | - | - | - |
| **Oracle** | (相减) | - | - | - |
| **SQLite** | (JULIANDAY) | - | - | - |

---

## 3. 部分提取（EXTRACT / YEAR() / DATEPART / TO_CHAR）

### 语法分类

| 模式 | 语法 | 引擎 |
|------|------|------|
| A: EXTRACT(unit FROM date) | SQL 标准 | PostgreSQL, MySQL 5.5+, BigQuery, Snowflake, Trino, DuckDB, Hive, Spark, StarRocks, Doris, Redshift, ClickHouse |
| B: YEAR()/MONTH()/DAY() | 专用函数 | MySQL, SQL Server, Oracle, Hive, Spark, Snowflake, StarRocks, Doris, ClickHouse |
| C: DATEPART(unit, date) | 微软风格 | SQL Server, Snowflake, Redshift |
| D: TO_CHAR(date, 'YYYY') | 格式化提取 | Oracle, PostgreSQL |
| E: strftime('%Y', date) | C 风格 | SQLite |

### 各引擎支持对比

| 引擎 | EXTRACT | YEAR() 等 | DATEPART | strftime | TO_CHAR |
|------|---------|-----------|----------|----------|---------|
| MySQL | 是 | 是 | 否 | 否 | 否 |
| PostgreSQL | 是 | 否(注1) | 否 | 否 | 是 |
| SQL Server | 否 | 是 | 是 | 否 | 否(FORMAT) |
| Oracle | 是(受限) | 否(注2) | 否 | 否 | 是 |
| SQLite | 否 | 否 | 否 | 是 | 否 |
| BigQuery | 是 | 否(用 EXTRACT) | 否 | 否 | 否(FORMAT_DATE) |
| Snowflake | 是 | 是 | 是 | 否 | 是 |
| ClickHouse | 是 | 是(toYear等) | 否 | 否 | 否(formatDateTime) |
| DuckDB | 是 | 是 | 是 | 是 | 否 |
| Trino | 是 | 是 | 否 | 否 | 否(DATE_FORMAT) |
| Hive | 是(2.2+) | 是 | 否 | 否 | 否(DATE_FORMAT) |
| Spark SQL | 是 | 是 | 否 | 否 | 否(DATE_FORMAT) |
| Redshift | 是 | 否 | 是 | 否 | 是 |
| StarRocks | 是 | 是 | 否 | 否 | 否 |
| Doris | 是 | 是 | 否 | 否 | 否 |
| MaxCompute | 是 | 是 | 否 | 否 | 否 |

> 注1: PostgreSQL 有 `EXTRACT(YEAR FROM d)` 但没有独立的 `YEAR(d)` 函数。
> 注2: Oracle EXTRACT 从 DATE 仅支持 YEAR/MONTH/DAY；提取 HOUR/MINUTE/SECOND 需要 TIMESTAMP 类型。

```sql
-- EXTRACT 标准语法（大多数引擎）
SELECT EXTRACT(YEAR FROM date_col);
SELECT EXTRACT(MONTH FROM date_col);
SELECT EXTRACT(DOW FROM date_col);  -- 星期几（PostgreSQL）
SELECT EXTRACT(DAYOFWEEK FROM date_col);  -- 星期几（BigQuery; MySQL 用 DAYOFWEEK() 函数）

-- SQL Server: DATEPART 或专用函数
SELECT DATEPART(YEAR, date_col);
SELECT YEAR(date_col);
SELECT MONTH(date_col);

-- Oracle: EXTRACT 或 TO_CHAR
SELECT EXTRACT(YEAR FROM SYSDATE) FROM DUAL;
SELECT TO_CHAR(SYSDATE, 'YYYY') FROM DUAL;  -- 返回字符串
SELECT TO_NUMBER(TO_CHAR(SYSDATE, 'MM')) FROM DUAL;

-- SQLite: strftime
SELECT strftime('%Y', date_col);  -- 年（字符串）
SELECT CAST(strftime('%Y', date_col) AS INTEGER);  -- 年（整数）
SELECT strftime('%m', date_col);  -- 月
SELECT strftime('%w', date_col);  -- 星期几（0=周日）

-- ClickHouse: 专用函数
SELECT toYear(date_col);
SELECT toMonth(date_col);
SELECT toDayOfWeek(date_col);  -- 1=周一（ISO）
SELECT EXTRACT(YEAR FROM date_col);  -- 也支持 EXTRACT
```

### 星期几返回值差异（另一个迁移陷阱）

| 引擎 | 函数 | 周日 | 周一 | 周六 |
|------|------|------|------|------|
| MySQL | DAYOFWEEK() | 1 | 2 | 7 |
| PostgreSQL | EXTRACT(DOW) | 0 | 1 | 6 |
| PostgreSQL | EXTRACT(ISODOW) | 7 | 1 | 6 |
| SQL Server | DATEPART(dw) | 1* | 2* | 7* |
| Oracle | TO_CHAR(d,'D') | 1* | 2* | 7* |
| ClickHouse | toDayOfWeek() | 7 | 1 | 6 |
| SQLite | strftime('%w') | 0 | 1 | 6 |
| BigQuery | EXTRACT(DAYOFWEEK) | 1 | 2 | 7 |

> *SQL Server 和 Oracle 的星期几起始日受 `SET DATEFIRST` / `NLS_TERRITORY` 影响。
>
> **⚠️ 周数计算（WEEK OF YEAR）是另一个灾难**：MySQL `WEEK()` 有 8 种 mode（`default_week_format` 控制），SQL Server `DATEPART(wk)` 受 `@@DATEFIRST` 影响，PostgreSQL 默认 ISO 周（周一起始，第 1 周含 1 月 4 日）。跨引擎迁移周统计报表时，**必须显式对齐一周的起始日和第 1 周的定义**。

---

## 4. 当前时间（CURRENT_DATE / NOW() / GETDATE() / SYSDATE）

### 语法分类

| 函数 | 语义 | 引擎 |
|------|------|------|
| `CURRENT_DATE` | 当前日期（无括号） | PostgreSQL, MySQL, BigQuery, Snowflake, Trino, DuckDB, Hive, Spark, Redshift, StarRocks, Doris, ClickHouse, Oracle(9i+) |
| `CURRENT_DATE()` | 当前日期（有括号） | MySQL(兼容), ClickHouse, DuckDB |
| `CURRENT_TIMESTAMP` | 当前时间戳（无括号） | SQL 标准，几乎所有引擎 |
| `NOW()` | 当前时间戳 | MySQL, PostgreSQL, Snowflake, ClickHouse, DuckDB, StarRocks, Doris, Trino |
| `GETDATE()` | 当前时间戳 | SQL Server |
| `SYSDATE` | 当前时间戳（无括号） | Oracle |
| `SYSDATE()` | 当前时间戳（有括号） | MySQL |

### 括号问题

```sql
-- PostgreSQL: CURRENT_DATE 不加括号（SQL 标准语法）
SELECT CURRENT_DATE;         -- 正确
SELECT CURRENT_DATE();       -- ⚠️ 错误！

-- MySQL: 两种都行
SELECT CURRENT_DATE;         -- 正确
SELECT CURRENT_DATE();       -- 正确

-- Oracle: 无括号
SELECT SYSDATE FROM DUAL;    -- 正确
SELECT SYSDATE() FROM DUAL;  -- ⚠️ 错误！

-- SQL Server: 必须有括号
SELECT GETDATE();             -- 正确
SELECT CURRENT_TIMESTAMP;     -- 正确（SQL 标准，无括号）
```

### 事务时间 vs 墙钟时间

> **迁移陷阱**: 同一事务内多次调用，有些引擎返回相同时间（事务时间），有些返回实时变化的时间（墙钟时间）。

| 引擎 | 函数 | 行为 | 备注 |
|------|------|------|------|
| PostgreSQL | `CURRENT_TIMESTAMP` | 事务时间 | 同一事务内不变 |
| PostgreSQL | `CLOCK_TIMESTAMP()` | 墙钟时间 | 每次调用都变 |
| PostgreSQL | `NOW()` | 事务时间 | = CURRENT_TIMESTAMP |
| PostgreSQL | `STATEMENT_TIMESTAMP()` | 语句时间 | 同一语句内不变 |
| MySQL | `NOW()` | 语句时间 | 同一语句内不变 |
| MySQL | `SYSDATE()` | 墙钟时间 | 每次调用都变 |
| Oracle | `SYSDATE` | 墙钟时间 | 每次调用都变 |
| Oracle | `SYSTIMESTAMP` | 墙钟时间 | 含时区 |
| SQL Server | `GETDATE()` | 语句时间 | - |
| SQL Server | `SYSDATETIME()` | 语句时间 | 更高精度 |
| Snowflake | `CURRENT_TIMESTAMP()` | 语句时间 | - |
| BigQuery | `CURRENT_TIMESTAMP()` | 查询时间 | 整个查询恒定 |
| ClickHouse | `NOW()` | 查询时间 | 整个查询恒定 |
| ClickHouse | `nowInBlock()` | 块级时间 | 每个 block 不同 |
| Trino | `CURRENT_TIMESTAMP` | 查询时间 | - |
| Hive/Spark | `CURRENT_TIMESTAMP` | 查询时间 | - |

---

## 5. 格式化与解析（TO_CHAR / DATE_FORMAT / FORMAT）

### 格式化函数对比

| 引擎 | 函数 | 格式字符串示例 | 格式体系 |
|------|------|---------------|----------|
| Oracle | `TO_CHAR(d, fmt)` | `'YYYY-MM-DD HH24:MI:SS'` | Oracle 格式 |
| PostgreSQL | `TO_CHAR(d, fmt)` | `'YYYY-MM-DD HH24:MI:SS'` | Oracle 兼容 |
| Redshift | `TO_CHAR(d, fmt)` | `'YYYY-MM-DD HH24:MI:SS'` | Oracle 兼容 |
| Snowflake | `TO_CHAR(d, fmt)` | `'YYYY-MM-DD HH24:MI:SS'` | Oracle 兼容 |
| MySQL | `DATE_FORMAT(d, fmt)` | `'%Y-%m-%d %H:%i:%s'` | strftime 系 |
| Hive | `DATE_FORMAT(d, fmt)` | `'yyyy-MM-dd HH:mm:ss'` | Java SimpleDateFormat |
| Spark SQL | `DATE_FORMAT(d, fmt)` | `'yyyy-MM-dd HH:mm:ss'` | Java SimpleDateFormat |
| SQL Server | `FORMAT(d, fmt)` | `'yyyy-MM-dd HH:mm:ss'` | .NET format |
| SQL Server | `CONVERT(VARCHAR, d, style)` | `CONVERT(VARCHAR, d, 120)` | 样式编号 |
| BigQuery | `FORMAT_DATE(fmt, d)` | `'%Y-%m-%d'` | strftime 系 |
| BigQuery | `FORMAT_TIMESTAMP(fmt, ts)` | `'%Y-%m-%d %H:%M:%S'` | strftime 系 |
| ClickHouse | `formatDateTime(d, fmt)` | `'%Y-%m-%d %H:%i:%S'` | MySQL 格式系（⚠️ %M=月份名，%i=分钟） |
| DuckDB | `strftime(fmt, d)` | `'%Y-%m-%d %H:%M:%S'` | strftime 系 |
| Trino | `DATE_FORMAT(d, fmt)` | `'%Y-%m-%d %H:%i:%s'` | MySQL 兼容(strftime 变体) |
| SQLite | `strftime(fmt, d)` | `'%Y-%m-%d %H:%M:%S'` | strftime |
| StarRocks | `DATE_FORMAT(d, fmt)` | `'%Y-%m-%d %H:%i:%s'` | MySQL 兼容 |
| Doris | `DATE_FORMAT(d, fmt)` | `'%Y-%m-%d %H:%i:%s'` | MySQL 兼容 |
| MaxCompute | `DATE_FORMAT(d, fmt)` | `'yyyy-MM-dd HH:mm:ss'` | Java SimpleDateFormat |

### 三大格式字符串体系对比

| 含义 | Oracle/PG (`YYYY`) | strftime (`%Y`) | Java (`yyyy`) |
|------|-------------------|-----------------|---------------|
| 四位年 | `YYYY` | `%Y` | `yyyy` |
| 两位年 | `YY` | `%y` | `yy` |
| 月（数字,补零） | `MM` | `%m` | `MM` |
| 月（英文缩写） | `MON` | `%b` | `MMM` |
| 日（补零） | `DD` | `%d` | `dd` |
| 时（24h） | `HH24` | `%H` | `HH` |
| 时（12h） | `HH` / `HH12` | `%I` | `hh` |
| 分 | `MI` | `%M` / `%i`(MySQL) | `mm` |
| 秒 | `SS` | `%S` | `ss` |
| AM/PM | `AM` | `%p` | `a` |

> **注意**: strftime 体系内部也有差异！MySQL 用 `%i` 表示分钟，标准 strftime 用 `%M`。BigQuery 用标准 `%M`。**ClickHouse v23.4+ 的 `%M` 输出完整月份名（January 等），分钟应用 `%i`**——与 MySQL 格式系一致。

### 解析函数对比（字符串 → 日期）

| 引擎 | 函数 | 示例 |
|------|------|------|
| Oracle | `TO_DATE(str, fmt)` | `TO_DATE('2024-01-01', 'YYYY-MM-DD')` |
| PostgreSQL | `TO_DATE(str, fmt)` / `TO_TIMESTAMP(str, fmt)` | `TO_TIMESTAMP('2024-01-01 12:00', 'YYYY-MM-DD HH24:MI')` |
| MySQL | `STR_TO_DATE(str, fmt)` | `STR_TO_DATE('2024-01-01', '%Y-%m-%d')` |
| SQL Server | `CONVERT(DATETIME, str, style)` / `TRY_PARSE` | `CONVERT(DATETIME, '2024-01-01', 120)` |
| Snowflake | `TO_DATE(str, fmt)` / `TRY_TO_DATE` | `TO_DATE('2024-01-01', 'YYYY-MM-DD')` |
| BigQuery | `PARSE_DATE(fmt, str)` | `PARSE_DATE('%Y-%m-%d', '2024-01-01')` |
| ClickHouse | `parseDateTimeBestEffort(str)` / `toDate(str)` | `parseDateTimeBestEffort('2024-01-01 12:00')` |
| DuckDB | `strptime(str, fmt)` | `strptime('2024-01-01', '%Y-%m-%d')` |
| Trino | `DATE_PARSE(str, fmt)` | `DATE_PARSE('2024-01-01', '%Y-%m-%d')` |
| Hive | `TO_DATE(str)` | `TO_DATE('2024-01-01 12:00:00')` |
| Spark SQL | `TO_DATE(str, fmt)` | `TO_DATE('2024-01-01', 'yyyy-MM-dd')` |
| StarRocks | `STR_TO_DATE(str, fmt)` | `STR_TO_DATE('2024-01-01', '%Y-%m-%d')` |
| Doris | `STR_TO_DATE(str, fmt)` | `STR_TO_DATE('2024-01-01', '%Y-%m-%d')` |
| SQLite | (隐式转换) | `DATE('2024-01-01')` |
| MaxCompute | `TO_DATE(str, fmt)` | `TO_DATE('2024-01-01', 'yyyy-MM-dd')` |

> **BigQuery 解析陷阱**: `PARSE_DATE(fmt, str)` 的参数顺序是 **fmt 在前、str 在后**，与 `FORMAT_DATE(fmt, date)` 一致但与大多数引擎的 `TO_DATE(str, fmt)` 相反。

---

## 6. 时区处理（TIMESTAMP vs TIMESTAMPTZ / AT TIME ZONE / CONVERT_TZ）

### 类型支持

| 引擎 | 有 TIMESTAMPTZ 类型？ | 存储方式 | 备注 |
|------|---------------------|---------|------|
| PostgreSQL | 是 `TIMESTAMPTZ` | 内部存 UTC | 输出时按 `timezone` 设置转换 |
| Oracle | 是 `TIMESTAMP WITH TIME ZONE` | 存原始时区 | 也有 `WITH LOCAL TIME ZONE` |
| SQL Server | 是 `DATETIMEOFFSET` | 存 offset | 不支持时区名，只支持 offset |
| Snowflake | 是 `TIMESTAMP_TZ` | 存 UTC + offset | 也有 `TIMESTAMP_LTZ`(local), `TIMESTAMP_NTZ`(无时区) |
| BigQuery | 是 `TIMESTAMP` | 始终 UTC | `DATETIME` 类型无时区 |
| ClickHouse | 是 `DateTime('tz')` | 存 UTC | 类型定义时绑定时区 |
| DuckDB | 是 `TIMESTAMPTZ` | 存 UTC | 同 PostgreSQL |
| Trino | 是 `TIMESTAMP WITH TIME ZONE` | 存 UTC + 时区 | - |
| Redshift | 是 `TIMESTAMPTZ` | 存 UTC | 同 PostgreSQL |
| MySQL | 否（TIMESTAMP 存 UTC，DATETIME 无时区） | `CONVERT_TZ()` | TIMESTAMP 以 UTC 存储，输入输出按 session time_zone 转换；DATETIME 是纯墙钟值 |
| Hive/Spark | 否（Spark 3.4+ 有） | - | 通常依赖 session 时区 |
| StarRocks | 否 | - | `DATETIME` 无时区语义 |
| Doris | 否 | - | `DATETIME` 无时区语义 |
| SQLite | 否 | TEXT 存储 | 无时区支持 |
| MaxCompute | 否 | - | `DATETIME` 无时区语义 |

### 时区转换语法

```sql
-- PostgreSQL: AT TIME ZONE（SQL 标准）
SELECT TIMESTAMP '2024-01-01 12:00' AT TIME ZONE 'Asia/Shanghai';
SELECT CURRENT_TIMESTAMP AT TIME ZONE 'UTC';
-- TIMESTAMPTZ AT TIME ZONE → TIMESTAMP（去掉时区）
-- TIMESTAMP AT TIME ZONE → TIMESTAMPTZ（添加时区）

-- SQL Server: AT TIME ZONE（SQL Server 2016+）
SELECT GETDATE() AT TIME ZONE 'China Standard Time';
SELECT CONVERT(DATETIME, SYSDATETIMEOFFSET() AT TIME ZONE 'UTC');

-- MySQL: CONVERT_TZ（⚠️ 命名时区需已加载时区表，否则返回 NULL）
SELECT CONVERT_TZ('2024-01-01 12:00:00', '+08:00', 'UTC');           -- offset 形式始终可用
SELECT CONVERT_TZ(NOW(), @@session.time_zone, 'US/Eastern');         -- 命名时区需 mysql_tzinfo_to_sql

-- Oracle: FROM_TZ + AT TIME ZONE
SELECT FROM_TZ(TIMESTAMP '2024-01-01 12:00:00', 'Asia/Shanghai')
       AT TIME ZONE 'UTC' FROM DUAL;

-- BigQuery: 函数式
SELECT TIMESTAMP('2024-01-01 12:00:00', 'Asia/Shanghai');
SELECT DATETIME(CURRENT_TIMESTAMP(), 'Asia/Shanghai');

-- Snowflake: CONVERT_TIMEZONE
SELECT CONVERT_TIMEZONE('Asia/Shanghai', 'UTC', '2024-01-01 12:00:00'::TIMESTAMP);
SELECT CONVERT_TIMEZONE('UTC', CURRENT_TIMESTAMP());  -- 2 参数形式

-- ClickHouse: toTimeZone
SELECT toTimeZone(now(), 'Asia/Shanghai');
SELECT toDateTime('2024-01-01 12:00:00', 'Asia/Shanghai');

-- DuckDB: AT TIME ZONE（同 PostgreSQL）
SELECT TIMESTAMP '2024-01-01 12:00' AT TIME ZONE 'Asia/Shanghai';

-- Trino: AT TIME ZONE
SELECT TIMESTAMP '2024-01-01 12:00:00' AT TIME ZONE 'Asia/Shanghai';
SELECT WITH_TIMEZONE(TIMESTAMP '2024-01-01 12:00:00', 'Asia/Shanghai');
```

---

## 7. 日期截断（DATE_TRUNC / TRUNC / DATETRUNC / toStartOf*）

> **迁移陷阱**: `DATE_TRUNC` 的参数顺序在不同引擎中不一致。

### 语法分类

| 模式 | 语法 | 引擎 |
|------|------|------|
| A: DATE_TRUNC('unit', date) | unit 在前 | PostgreSQL, Snowflake, Redshift, DuckDB, Trino, Spark SQL(3.0+) |
| B: DATE_TRUNC(date, unit) | date 在前 | BigQuery |
| C: TRUNC(date [, fmt]) | Oracle 风格 | Oracle |
| D: DATETRUNC(unit, date) | 无下划线变体 | SQL Server (2022+) |
| E: toStartOfMonth(date) 等 | 专用函数族 | ClickHouse |
| F: DATE_TRUNC('unit', date) 模拟 | 函数/UDF | Hive (需 UDF), MySQL (无原生支持) |

### 各引擎详细语法

```sql
-- PostgreSQL: DATE_TRUNC('unit', date) —— unit 在前（字符串）
SELECT DATE_TRUNC('month', TIMESTAMP '2024-03-15 14:30:00');
-- → 2024-03-01 00:00:00
SELECT DATE_TRUNC('quarter', CURRENT_DATE);
SELECT DATE_TRUNC('week', CURRENT_DATE);

-- Snowflake: 同 PostgreSQL
SELECT DATE_TRUNC('MONTH', '2024-03-15'::DATE);
SELECT DATE_TRUNC('QUARTER', CURRENT_TIMESTAMP());

-- Redshift: 同 PostgreSQL
SELECT DATE_TRUNC('month', GETDATE());

-- DuckDB: 同 PostgreSQL
SELECT DATE_TRUNC('month', DATE '2024-03-15');

-- Trino: 同 PostgreSQL
SELECT DATE_TRUNC('month', DATE '2024-03-15');

-- Spark SQL 3.0+: 同 PostgreSQL
SELECT DATE_TRUNC('month', '2024-03-15');

-- ⚠️ BigQuery: DATE_TRUNC(date, unit) —— date 在前，unit 在后！
SELECT DATE_TRUNC(DATE '2024-03-15', MONTH);
SELECT DATETIME_TRUNC(DATETIME '2024-03-15 14:30:00', MONTH);
SELECT TIMESTAMP_TRUNC(CURRENT_TIMESTAMP(), MONTH);
-- 与 PostgreSQL 参数顺序相反！

-- SQL Server 2022+: DATETRUNC（无下划线）
SELECT DATETRUNC(MONTH, '2024-03-15');
-- 旧版本用变通方案:
SELECT DATEADD(MONTH, DATEDIFF(MONTH, 0, date_col), 0);

-- Oracle: TRUNC
SELECT TRUNC(SYSDATE, 'MM') FROM DUAL;   -- 月初
SELECT TRUNC(SYSDATE, 'Q') FROM DUAL;    -- 季初
SELECT TRUNC(SYSDATE, 'YYYY') FROM DUAL; -- 年初
SELECT TRUNC(SYSDATE) FROM DUAL;         -- 当天零点（默认截断到天）

-- ClickHouse: toStartOf* 函数族
SELECT toStartOfMonth(toDate('2024-03-15'));
SELECT toStartOfQuarter(toDate('2024-03-15'));
SELECT toStartOfYear(toDate('2024-03-15'));
SELECT toStartOfWeek(toDate('2024-03-15'));      -- 周日为周首日
SELECT toStartOfISOYear(toDate('2024-03-15'));
SELECT toStartOfHour(now());
SELECT toStartOfMinute(now());
-- 也支持: SELECT DATE_TRUNC('month', toDate('2024-03-15'));

-- MySQL: 无原生 DATE_TRUNC，需手工拼接
SELECT DATE_FORMAT('2024-03-15', '%Y-%m-01');  -- 月初（注意：返回 STRING 非 DATE！需 CAST）
SELECT MAKEDATE(YEAR('2024-03-15'), 1);                -- 年初
SELECT DATE_SUB('2024-03-15',
       INTERVAL DAYOFMONTH('2024-03-15')-1 DAY);       -- 月初(另一种)
-- MySQL 8.0 仍然没有 DATE_TRUNC

-- Hive: 需要 TRUNC (Hive 2.1+)
SELECT TRUNC('2024-03-15', 'MM');  -- 月初
SELECT TRUNC('2024-03-15', 'YY');  -- 年初

-- StarRocks / Doris: DATE_TRUNC
SELECT DATE_TRUNC('month', '2024-03-15');  -- 同 PostgreSQL 风格

-- MaxCompute: TRUNC
SELECT TRUNC('2024-03-15', 'MM');
```

### DATE_TRUNC 参数顺序速查表

| 引擎 | 第 1 参数 | 第 2 参数 |
|------|-----------|-----------|
| PostgreSQL | 'unit' | date |
| Snowflake | 'unit' | date |
| Redshift | 'unit' | date |
| DuckDB | 'unit' | date |
| Trino | 'unit' | date |
| Spark SQL | 'unit' | date |
| StarRocks | 'unit' | date |
| Doris | 'unit' | date |
| **BigQuery** | **date** | **unit** |
| SQL Server 2022+ | unit | date |
| Oracle | date | fmt |
| Hive | date | fmt |
| ClickHouse | 'unit' 或 专用函数 | date |
| MySQL | (无原生支持) | - |
| MaxCompute | date | fmt |
| SQLite | (无原生支持) | - |

---

## 8. 横向总结：最危险的迁移陷阱

### 陷阱 1: DATEADD/DATEDIFF 参数顺序反转

这是跨引擎迁移中**最危险**的问题，因为语法完全合法、编译通过、但结果错误。

```sql
-- SQL Server 原始代码:
SELECT DATEDIFF(DAY, start_date, end_date);   -- start 在前
-- 直接粘贴到 MySQL（假设 MySQL 也有 DATEDIFF）:
SELECT DATEDIFF(start_date, end_date);        -- MySQL 只有两个参数，end 在前
-- 结果正负号相反！

-- SQL Server 原始代码:
SELECT DATEADD(DAY, 7, hire_date);            -- unit, delta, date
-- MaxCompute 也叫 DATEADD，但:
SELECT DATEADD(hire_date, 7, 'dd');           -- date, delta, unit
-- 如果不注意参数顺序，结果完全错误
```

### 陷阱 2: 同名函数的语义差异

```sql
-- DATEDIFF 的 "边界跨越" vs "完整间隔":
-- SQL Server:
SELECT DATEDIFF(YEAR, '2024-12-31', '2025-01-01');  -- 1（跨了年边界）
-- 实际只差 1 天，但 SQL Server 认为跨了 1 个年边界

-- PostgreSQL:
SELECT AGE('2025-01-01', '2024-12-31');  -- '1 day'
SELECT EXTRACT(YEAR FROM AGE('2025-01-01', '2024-12-31'));  -- 0
-- PostgreSQL 认为没有跨 1 整年
```

### 陷阱 3: 星期几编号不统一

周日在 MySQL/BigQuery 中是 1，在 PostgreSQL 中是 0，在 ClickHouse 中是 7。无法通过简单的函数名替换迁移。

### 陷阱 4: 事务时间 vs 墙钟时间

```sql
-- PostgreSQL:
BEGIN;
SELECT NOW();           -- 12:00:00（事务开始时间）
-- ... 执行 10 秒 ...
SELECT NOW();           -- 12:00:00（仍然是事务开始时间！）
SELECT CLOCK_TIMESTAMP(); -- 12:00:10（实际时间）
COMMIT;

-- MySQL:
-- NOW() 是语句时间（同一语句内不变）
-- SYSDATE() 是墙钟时间
-- 如果从 PostgreSQL 迁移到 MySQL，NOW() 的粒度从"事务级"变成了"语句级"
```

### 陷阱 5: 格式字符串体系混淆

```sql
-- 分钟在三大体系中的表示:
-- Oracle/PG: MI     (注意不是 MM，MM 是月份！)
-- strftime:  %M     (MySQL 用 %i)
-- Java:      mm     (注意不是 MM，MM 是月份！)

-- 如果混淆 MM 和 mm/MI，会把"月份"当成"分钟"，或反过来
-- 这种 bug 在测试中极难发现——只有在跨月/跨年的边界才会暴露
```

### 陷阱 6: DATE_TRUNC 参数顺序

```sql
-- PostgreSQL（及大多数引擎）:
SELECT DATE_TRUNC('month', date_col);  -- unit 在前

-- BigQuery:
SELECT DATE_TRUNC(date_col, MONTH);    -- date 在前

-- 从 PostgreSQL 迁移到 BigQuery 时，如果只改函数名不改参数顺序，
-- BigQuery 通常会直接报类型错误（首参期望 date 表达式而非字符串）
```

### 迁移安全检查清单

| 检查项 | 风险等级 | 说明 |
|--------|---------|------|
| DATEADD 参数顺序 | 极高 | SQL Server ↔ MaxCompute 完全相反 |
| DATEDIFF start/end 顺序 | 极高 | MySQL(end,start) vs SQL Server(unit,start,end) |
| DATEDIFF 语义（边界 vs 完整） | 高 | SQL Server 是边界跨越，其他多为完整间隔 |
| DATE_TRUNC 参数顺序 | 高 | BigQuery 与其他引擎相反 |
| 格式字符串体系 | 高 | Oracle/strftime/Java 三套体系不兼容 |
| 星期几编号 | 中 | 0-based vs 1-based，周日 vs 周一起始 |
| NOW() 语义 | 中 | 事务时间 vs 语句时间 vs 墙钟时间 |
| TIMESTAMP 时区行为 | 中 | 有无 TIMESTAMPTZ 差异很大 |
| 括号有无 | 低 | CURRENT_DATE vs CURRENT_DATE() |

**建议**: 在跨引擎迁移时，永远不要依赖 DATEADD/DATEDIFF 的函数名相同就直接复制。应该逐个确认参数顺序，最好用简单的已知输入验证输出。
