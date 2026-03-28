# Snowflake: 日期时间类型

> 参考资料:
> - [1] Snowflake SQL Reference - Date & Time Data Types
>   https://docs.snowflake.com/en/sql-reference/data-types-datetime


## 1. 类型概述


DATE:           日期，0001-01-01 ~ 9999-12-31
TIME(p):        时间（无日期），精度 0-9，默认 9（纳秒）
TIMESTAMP_NTZ:  日期时间，无时区（Not Time Zone aware）
TIMESTAMP_LTZ:  日期时间，本地时区（Local Time Zone，内部 UTC）
TIMESTAMP_TZ:   日期时间，带时区偏移（Time Zone，存 UTC + 偏移量）
TIMESTAMP:      别名，默认映射到 NTZ（可通过参数修改）


```sql
CREATE TABLE events (
    id           INTEGER,
    event_date   DATE,
    event_time   TIME,
    local_dt     TIMESTAMP_NTZ,           -- 无时区
    session_dt   TIMESTAMP_LTZ,           -- 本地时区
    created_at   TIMESTAMP_TZ             -- 带时区偏移
);

```

## 2. 语法设计分析（对 SQL 引擎开发者）


### 2.1 三种 TIMESTAMP: Snowflake 的精细设计

NTZ (No Time Zone):
存储字面值，不做时区转换。'2024-01-15 10:00:00' 永远是这个值。
适合: 业务时间（下单时间、生日等不需要时区转换的场景）

LTZ (Local Time Zone):
内部存储 UTC，显示时按 session TIMEZONE 参数转换。
适合: 系统时间（审计时间、日志时间等需要跨时区一致性的场景）
ALTER SESSION SET TIMEZONE = 'Asia/Shanghai';

TZ (Time Zone):
存储 UTC 值 + 时区偏移量（如 +08:00）。
适合: 需要记录"在哪个时区发生"的事件。

默认映射:

```sql
ALTER SESSION SET TIMESTAMP_TYPE_MAPPING = 'TIMESTAMP_NTZ';  -- 默认
```

 这意味着 TIMESTAMP 列默认是 NTZ 类型

 三种类型的常见 Bug:
   NTZ 列存储 UTC 时间后，session 切换时区 → 显示的值不变（可能误解为本地时间）
   LTZ 列在不同 session 中显示不同值 → 用户困惑
   NTZ 和 LTZ 比较时发生隐式转换 → 结果可能不正确

 对比:
   PostgreSQL: TIMESTAMP / TIMESTAMPTZ（推荐总是用 TIMESTAMPTZ，只有两种）
   MySQL:      DATETIME(无时区) / TIMESTAMP(UTC+session转换)
   Oracle:     TIMESTAMP / TIMESTAMP WITH TIME ZONE / TIMESTAMP WITH LOCAL TIME ZONE
   BigQuery:   DATETIME(无时区) / TIMESTAMP(UTC)

 对引擎开发者的启示:
   PostgreSQL 的"两种就够"策略更受开发者欢迎。
   三种 TIMESTAMP 虽然语义精确，但增加了认知负担和 Bug 风险。
   如果必须支持三种，需要非常清晰的默认值和隐式转换文档。

## 3. 构造与获取


```sql
SELECT CURRENT_DATE();           SELECT CURRENT_TIME();
SELECT CURRENT_TIMESTAMP();      SELECT LOCALTIMESTAMP();
SELECT SYSDATE();                -- 真实当前时间（非事务时间）

SELECT DATE_FROM_PARTS(2024, 1, 15);
SELECT TIMESTAMP_FROM_PARTS(2024, 1, 15, 10, 30, 0);
SELECT TIMESTAMP_TZ_FROM_PARTS(2024, 1, 15, 10, 30, 0, 0, 'Asia/Shanghai');

SELECT TO_DATE('2024-01-15', 'YYYY-MM-DD');
SELECT TO_TIMESTAMP('2024-01-15 10:30:00', 'YYYY-MM-DD HH24:MI:SS');
SELECT TRY_TO_DATE('invalid');  -- 安全解析

```

## 4. 日期运算


```sql
SELECT DATEADD(DAY, 7, '2024-01-15'::DATE);
SELECT DATEDIFF(DAY, '2024-01-01', '2024-12-31');

SELECT EXTRACT(YEAR FROM CURRENT_DATE());
SELECT YEAR(CURRENT_DATE());    -- 便捷函数
SELECT DATE_TRUNC('MONTH', CURRENT_TIMESTAMP());
SELECT LAST_DAY(CURRENT_DATE());

```

## 5. 时区转换


```sql
SELECT CONVERT_TIMEZONE('UTC', 'Asia/Shanghai', CURRENT_TIMESTAMP());

```

## 6. Unix 时间戳


```sql
SELECT DATE_PART(EPOCH_SECOND, CURRENT_TIMESTAMP());
SELECT TO_TIMESTAMP(1705312800);

```

## 横向对比: 日期时间类型

| 特性             | Snowflake       | BigQuery     | PostgreSQL  | MySQL |
|------|------|------|------|------|
| TIMESTAMP 种类   | 3种(NTZ/LTZ/TZ) | 2种(DT/TS)   | 2种(TS/TSZ) | 2种(DT/TS) |
| 默认 TIMESTAMP   | NTZ(可配置)     | UTC          | 无时区      | UTC+session |
| 精度             | 纳秒(9位)       | 微秒(6位)    | 微秒(6位)   | 微秒(6位) |
| TIME 类型        | 支持            | 支持         | 支持        | 支持 |
| 安全解析         | TRY_TO_DATE     | SAFE.PARSE   | 无原生      | STR_TO_DATE |
| 时区函数         | CONVERT_TZ      | N/A(UTC)     | AT TIME ZONE| CONVERT_TZ |
| 2038 年问题      | 无              | 无           | 无          | TIMESTAMP有 |

