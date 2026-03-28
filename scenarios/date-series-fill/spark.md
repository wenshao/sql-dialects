# Spark SQL: 日期序列生成与间隙填充 (Date Series Fill)

> 参考资料:
> - [1] Spark SQL - sequence function
>   https://spark.apache.org/docs/latest/api/sql/index.html#sequence


## 1. 核心模式: sequence() + EXPLODE 生成日期序列


Spark SQL 没有 generate_series（PostgreSQL）或递归 CTE 日期生成。
替代方案是 sequence() 函数（生成数组）+ EXPLODE（展开为行）。


```sql
SELECT EXPLODE(SEQUENCE(
    DATE '2024-01-01', DATE '2024-01-10', INTERVAL 1 DAY
)) AS d;

```

 对比:
   PostgreSQL: generate_series('2024-01-01', '2024-01-10', '1 day')
   MySQL:      递归 CTE 或预建数字表
   BigQuery:   GENERATE_DATE_ARRAY('2024-01-01', '2024-01-10')
   ClickHouse: arrayJoin(range(...)) 或 numbers() 表函数
   Spark:      EXPLODE(SEQUENCE(start, end, interval))

 设计分析:
   Spark 通过 ARRAY + EXPLODE 两步组合实现序列生成，不如 PostgreSQL 直接。
   但 SEQUENCE 的好处是它返回 ARRAY——可以在不展开的情况下作为列存储或进一步处理。

## 2. LEFT JOIN 填充缺失日期


假设 daily_sales 表有缺失的日期

```sql
SELECT d AS sale_date, COALESCE(ds.amount, 0) AS amount
FROM (
    SELECT EXPLODE(SEQUENCE(
        DATE '2024-01-01', DATE '2024-01-10', INTERVAL 1 DAY
    )) AS d
) dates
LEFT JOIN daily_sales ds ON ds.sale_date = dates.d
ORDER BY d;

```

## 3. 动态日期范围


从数据中获取范围

```sql
SELECT d AS sale_date, COALESCE(ds.amount, 0) AS amount
FROM (
    SELECT EXPLODE(SEQUENCE(
        (SELECT MIN(sale_date) FROM daily_sales),
        (SELECT MAX(sale_date) FROM daily_sales),
        INTERVAL 1 DAY
    )) AS d
) dates
LEFT JOIN daily_sales ds ON ds.sale_date = dates.d
ORDER BY d;

```

## 4. 用最近已知值填充（Forward Fill）


模拟 IGNORE NULLS 的方法: COUNT 分组法

```sql
WITH filled AS (
    SELECT d AS sale_date, ds.amount,
           COUNT(ds.amount) OVER (ORDER BY d) AS grp
    FROM (
        SELECT EXPLODE(SEQUENCE(DATE '2024-01-01', DATE '2024-01-10',
                               INTERVAL 1 DAY)) AS d
    ) dates
    LEFT JOIN daily_sales ds ON ds.sale_date = dates.d
)
SELECT sale_date,
       FIRST_VALUE(amount) OVER (PARTITION BY grp ORDER BY sale_date) AS filled_amount
FROM filled
ORDER BY sale_date;

```

 原理:
   COUNT(amount) 只在非 NULL 时递增，产生分组标识
   同一分组内的 FIRST_VALUE 就是最近的非 NULL 值
   这是通用的 IGNORE NULLS 模拟方案（因为 Spark 不支持 IGNORE NULLS 子句）

## 5. 累计求和


```sql
SELECT d AS sale_date,
       COALESCE(ds.amount, 0) AS amount,
       SUM(COALESCE(ds.amount, 0)) OVER (ORDER BY d) AS running_total
FROM (
    SELECT EXPLODE(SEQUENCE(DATE '2024-01-01', DATE '2024-01-10',
                           INTERVAL 1 DAY)) AS d
) dates
LEFT JOIN daily_sales ds ON ds.sale_date = dates.d
ORDER BY d;

```

## 6. 月度序列


```sql
SELECT EXPLODE(SEQUENCE(
    DATE '2024-01-01', DATE '2024-12-01', INTERVAL 1 MONTH
)) AS month_start;

```

## 7. 版本演进

Spark 2.4: SEQUENCE 函数引入
Spark 3.0: SEQUENCE + INTERVAL 改进
Spark 3.4: EXPLODE + SEQUENCE 性能优化

限制:
无 generate_series（需用 SEQUENCE + EXPLODE 两步组合）
SEQUENCE 生成数组——大范围序列可能导致内存问题
无 IGNORE NULLS（需用 COUNT 分组法模拟）
Forward Fill 方案比 PostgreSQL 的 IGNORE NULLS 复杂得多

