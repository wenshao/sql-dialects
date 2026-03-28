# Hive: 日期序列生成与间隙填充

> 参考资料:
> - [1] Apache Hive Language Manual - UDF
>   https://cwiki.apache.org/confluence/display/Hive/LanguageManual+UDF
> - [2] Apache Hive - LATERAL VIEW
>   https://cwiki.apache.org/confluence/display/Hive/LanguageManual+LateralView


## 1. Hive 没有 generate_series

需要使用 posexplode + split(space(n)) 技巧生成数字序列。
这是 Hive 社区最常用的序列生成方法。

生成 0..9 的序列

```sql
SELECT pos AS n
FROM (SELECT 1) dummy
LATERAL VIEW POSEXPLODE(SPLIT(SPACE(9), ' ')) t AS pos, val;

```

生成连续日期序列: 2024-01-01 到 2024-01-10

```sql
SELECT DATE_ADD('2024-01-01', pos) AS dt
FROM (SELECT 1) dummy
LATERAL VIEW POSEXPLODE(SPLIT(SPACE(9), ' ')) t AS pos, val;

```

生成更长的序列（如 365 天）

```sql
SELECT DATE_ADD('2024-01-01', pos) AS dt
FROM (SELECT 1) dummy
LATERAL VIEW POSEXPLODE(SPLIT(SPACE(364), ' ')) t AS pos, val;

```

 设计分析: 为什么 SPLIT(SPACE(n), ' ') 能生成序列?
 SPACE(9) = '         ' (9个空格)
 SPLIT('         ', ' ') = ARRAY('', '', '', '', '', '', '', '', '', '') (10个元素)
 POSEXPLODE 返回 (0, ''), (1, ''), ..., (9, '')
 我们只用 pos（位置），忽略 val（空字符串）

## 2. LEFT JOIN 填零

```sql
WITH date_series AS (
    SELECT DATE_ADD('2024-01-01', pos) AS dt
    FROM (SELECT 1) dummy
    LATERAL VIEW POSEXPLODE(SPLIT(SPACE(30), ' ')) t AS pos, val
)
SELECT ds.dt, COALESCE(s.amount, 0) AS amount
FROM date_series ds
LEFT JOIN daily_sales s ON ds.dt = s.sale_date
ORDER BY ds.dt;

```

## 3. 用最近已知值填充 (Forward Fill)

Hive 不支持 IGNORE NULLS，使用 COUNT 分组法模拟

```sql
WITH filled AS (
    SELECT dt, amount,
           COUNT(amount) OVER (ORDER BY dt) AS grp
    FROM (
        SELECT ds.dt, s.amount
        FROM date_series ds LEFT JOIN daily_sales s ON ds.dt = s.sale_date
    ) joined
)
SELECT dt, FIRST_VALUE(amount) OVER (PARTITION BY grp ORDER BY dt) AS filled_amount
FROM filled;

```

 COUNT 分组法原理:
 NULL 行的 COUNT(amount) 与前一个非 NULL 行相同 → 同一分组
 FIRST_VALUE 取分组内第一个值（即最近的非 NULL 值）

## 4. 累计和

```sql
SELECT dt,
    COALESCE(amount, 0) AS daily_amount,
    SUM(COALESCE(amount, 0)) OVER (ORDER BY dt) AS running_total
FROM date_series ds
LEFT JOIN daily_sales s ON ds.dt = s.sale_date;

```

## 5. 跨引擎对比: 序列生成

 引擎          序列生成方式                       日期序列
 PostgreSQL    generate_series(1, n)              generate_series(date, date, interval)
 MySQL         递归 CTE (8.0+)                   递归 CTE + DATE_ADD
 Hive          POSEXPLODE(SPLIT(SPACE(n)))        DATE_ADD + POSEXPLODE
 Spark SQL     sequence(start, end, step)          sequence + explode
 BigQuery      GENERATE_DATE_ARRAY                GENERATE_DATE_ARRAY
 Trino         SEQUENCE(1, n)                     sequence + unnest

## 6. 对引擎开发者的启示

### 1. generate_series 是基本的用户需求: Hive 缺少此功能导致用户使用 hack 方法

### 2. POSEXPLODE + SPACE 技巧说明了 UDTF 的灵活性: 用现有原语组合出新能力

### 3. IGNORE NULLS 窗口函数选项应该被支持: 缺少此功能导致 forward fill 需要复杂的变通

