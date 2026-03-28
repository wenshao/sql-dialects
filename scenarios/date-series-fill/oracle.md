# Oracle: 日期序列填充

> 参考资料:
> - [Oracle Documentation - Hierarchical Queries (CONNECT BY)](https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/Hierarchical-Queries.html)

## 准备数据

```sql
CREATE TABLE daily_sales (
    sale_date DATE PRIMARY KEY,
    amount    NUMBER(10,2)
);
INSERT ALL
    INTO daily_sales VALUES (DATE '2024-01-01', 100)
    INTO daily_sales VALUES (DATE '2024-01-02', 150)
    INTO daily_sales VALUES (DATE '2024-01-04', 200)
    INTO daily_sales VALUES (DATE '2024-01-05', 120)
    INTO daily_sales VALUES (DATE '2024-01-08', 300)
    INTO daily_sales VALUES (DATE '2024-01-09', 250)
    INTO daily_sales VALUES (DATE '2024-01-10', 180)
SELECT 1 FROM DUAL;
```

## CONNECT BY LEVEL 生成日期序列（Oracle 独有技巧）

```sql
SELECT DATE '2024-01-01' + LEVEL - 1 AS d
FROM DUAL
CONNECT BY LEVEL <= DATE '2024-01-10' - DATE '2024-01-01' + 1;
```

按月生成
```sql
SELECT ADD_MONTHS(DATE '2024-01-01', LEVEL - 1) AS month_start
FROM DUAL CONNECT BY LEVEL <= 12;
```

设计分析:
  CONNECT BY LEVEL 是 Oracle 最经典的序列生成技巧。
  原本用于层次查询的 CONNECT BY 被创造性地用于生成数字/日期序列。
  DATE + NUMBER 的算术语义（1 = 1天）使日期序列生成非常简洁。

横向对比:
  Oracle:     CONNECT BY LEVEL（独有，简洁但语义不直观）
  PostgreSQL: generate_series(start, end, interval)（专用函数，最清晰）
  MySQL:      递归 CTE（8.0+）
  SQL Server: 递归 CTE 或 master..spt_values

## LEFT JOIN 填充间隙

```sql
SELECT seq.d AS date_val, COALESCE(ds.amount, 0) AS amount
FROM (
    SELECT DATE '2024-01-01' + LEVEL - 1 AS d
    FROM DUAL CONNECT BY LEVEL <= 10
) seq
LEFT JOIN daily_sales ds ON ds.sale_date = seq.d
ORDER BY seq.d;
```

## 填零 + 累计和

```sql
SELECT seq.d AS date_val,
       COALESCE(ds.amount, 0) AS amount,
       SUM(COALESCE(ds.amount, 0)) OVER (ORDER BY seq.d) AS running_total
FROM (
    SELECT DATE '2024-01-01' + LEVEL - 1 AS d
    FROM DUAL CONNECT BY LEVEL <= 10
) seq
LEFT JOIN daily_sales ds ON ds.sale_date = seq.d
ORDER BY seq.d;
```

## LAST_VALUE IGNORE NULLS 填充（Oracle 首创特性）

用最近已知值填充间隙（Forward Fill）
```sql
SELECT seq.d AS date_val,
       LAST_VALUE(ds.amount IGNORE NULLS)
           OVER (ORDER BY seq.d ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
           AS filled_amount
FROM (
    SELECT DATE '2024-01-01' + LEVEL - 1 AS d
    FROM DUAL CONNECT BY LEVEL <= 10
) seq
LEFT JOIN daily_sales ds ON ds.sale_date = seq.d
ORDER BY seq.d;
```

IGNORE NULLS 是 Oracle 首创的窗口函数修饰符（8i+）。
其他数据库（PostgreSQL、SQL Server 2022 之前）没有这个能力，
需要复杂的子查询替代。

## 递归 CTE 方法（11g R2+）

```sql
WITH date_series(d) AS (
    SELECT DATE '2024-01-01' FROM DUAL
    UNION ALL
    SELECT d + 1 FROM date_series WHERE d < DATE '2024-01-10'
)
SELECT ds2.d AS date_val, COALESCE(ds.amount, 0) AS amount
FROM date_series ds2
LEFT JOIN daily_sales ds ON ds.sale_date = ds2.d
ORDER BY ds2.d;
```

## MODEL 子句（Oracle 10g+ 独有的高级间隙填充）

```sql
SELECT date_val, amount FROM daily_sales
MODEL
    DIMENSION BY (sale_date AS date_val)
    MEASURES (amount)
    RULES (
        amount[FOR date_val FROM DATE '2024-01-01' TO DATE '2024-01-10'
               INCREMENT INTERVAL '1' DAY] =
            COALESCE(amount[CV(date_val)], 0)
    )
ORDER BY date_val;
```

MODEL 子句的设计:
  Oracle 独有的"电子表格式"SQL 扩展。
  DIMENSION BY: 行标识（类似 Excel 行号）
  MEASURES: 可计算的值（类似 Excel 单元格）
  RULES: 计算规则（类似 Excel 公式）
  FOR ... FROM ... TO ... INCREMENT: 自动填充范围

## 对引擎开发者的总结

1. CONNECT BY LEVEL 是 Oracle 的经典序列生成技巧，新引擎用 generate_series。
2. IGNORE NULLS 是 Oracle 首创的窗口函数修饰符，对间隙填充极其实用。
3. MODEL 子句提供了 SQL 中的"电子表格"能力，但学习成本高，实际使用率低。
4. 日期算术（DATE + NUMBER = DATE）使 Oracle 的日期序列生成特别简洁。
