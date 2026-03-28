# SQLite: 日期序列填充

> 参考资料:
> - [SQLite Documentation - Recursive CTEs](https://www.sqlite.org/lang_with.html)
> - [SQLite Documentation - Date Functions](https://www.sqlite.org/lang_datefunc.html)

## 准备数据

```sql
CREATE TABLE daily_sales (sale_date TEXT PRIMARY KEY, amount REAL);
INSERT INTO daily_sales VALUES
    ('2024-01-01',100),('2024-01-02',150),('2024-01-04',200),
    ('2024-01-05',120),('2024-01-08',300),('2024-01-09',250),('2024-01-10',180);
```

## 递归 CTE 生成日期序列（SQLite 3.8.3+）

```sql
WITH RECURSIVE date_series(d) AS (
    SELECT '2024-01-01'
    UNION ALL
    SELECT DATE(d, '+1 day') FROM date_series WHERE d < '2024-01-10'
)
SELECT d AS date FROM date_series;
```

## LEFT JOIN 填充间隙

```sql
WITH RECURSIVE date_series(d) AS (
    SELECT '2024-01-01'
    UNION ALL
    SELECT DATE(d, '+1 day') FROM date_series WHERE d < '2024-01-10'
)
SELECT ds2.d AS date, COALESCE(ds.amount, 0) AS amount
FROM date_series ds2
LEFT JOIN daily_sales ds ON ds.sale_date = ds2.d
ORDER BY ds2.d;
```

## COALESCE 填零 + 累计和

```sql
WITH RECURSIVE date_series(d) AS (
    SELECT '2024-01-01'
    UNION ALL
    SELECT DATE(d, '+1 day') FROM date_series WHERE d < '2024-01-10'
)
SELECT ds2.d AS date, COALESCE(ds.amount, 0) AS amount,
       SUM(COALESCE(ds.amount, 0)) OVER (ORDER BY ds2.d) AS running_total
FROM date_series ds2
LEFT JOIN daily_sales ds ON ds.sale_date = ds2.d
ORDER BY ds2.d;
```

## 用最近已知值填充

```sql
WITH RECURSIVE date_series(d) AS (
    SELECT '2024-01-01'
    UNION ALL
    SELECT DATE(d, '+1 day') FROM date_series WHERE d < '2024-01-10'
),
filled AS (
    SELECT ds2.d, ds.amount,
           COUNT(ds.amount) OVER (ORDER BY ds2.d) AS grp
    FROM date_series ds2
    LEFT JOIN daily_sales ds ON ds.sale_date = ds2.d
)
SELECT d AS date,
       FIRST_VALUE(amount) OVER (PARTITION BY grp ORDER BY d) AS filled_amount
FROM filled ORDER BY d;
```

## 动态日期范围

```sql
WITH RECURSIVE date_series(d) AS (
    SELECT MIN(sale_date) FROM daily_sales
    UNION ALL
    SELECT DATE(d, '+1 day') FROM date_series
    WHERE d < (SELECT MAX(sale_date) FROM daily_sales)
)
SELECT ds2.d AS date, COALESCE(ds.amount, 0) AS amount
FROM date_series ds2
LEFT JOIN daily_sales ds ON ds.sale_date = ds2.d ORDER BY ds2.d;
```

## 多维度日期填充

```sql
WITH RECURSIVE date_series(d) AS (
    SELECT '2024-01-01'
    UNION ALL
    SELECT DATE(d, '+1 day') FROM date_series WHERE d < '2024-01-04'
),
cats AS (SELECT DISTINCT category FROM category_sales)
SELECT ds.d, c.category, COALESCE(cs.amount, 0) AS amount
FROM date_series ds CROSS JOIN cats c
LEFT JOIN category_sales cs ON cs.sale_date = ds.d AND cs.category = c.category
ORDER BY c.category, ds.d;
```

注意：SQLite 使用 DATE(d, '+1 day') 进行日期加减
注意：SQLite 的日期以 TEXT 类型存储（ISO 8601 格式）
注意：递归 CTE 需要 SQLite 3.8.3+
注意：窗口函数需要 SQLite 3.25.0+
