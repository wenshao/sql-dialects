# KingbaseES (人大金仓): 日期序列生成与间隙填充 (Date Series Fill)

> 参考资料:
> - [KingbaseES (人大金仓) Documentation - CTE](https://help.kingbase.com.cn/v8/development/sql-plsql/sql/)
> - [KingbaseES (人大金仓) Documentation - Date Functions](https://help.kingbase.com.cn/v8/development/sql-plsql/sql/)
> - ============================================================
> - 准备数据
> - ============================================================

```sql
CREATE TABLE daily_sales (sale_date DATE PRIMARY KEY, amount DECIMAL(10,2));
INSERT INTO daily_sales VALUES
    ('2024-01-01',100),('2024-01-02',150),('2024-01-04',200),
    ('2024-01-05',120),('2024-01-08',300),('2024-01-09',250),('2024-01-10',180);
```

## 递归 CTE 生成日期序列


```sql
WITH RECURSIVE date_series AS (
    SELECT DATE '2024-01-01' AS d
    UNION ALL
    SELECT d + INTERVAL 1 DAY FROM date_series WHERE d < '2024-01-10'
)
SELECT d AS date FROM date_series;
```

## LEFT JOIN 填充间隙


```sql
WITH RECURSIVE date_series AS (
    SELECT DATE '2024-01-01' AS d
    UNION ALL
    SELECT d + INTERVAL 1 DAY FROM date_series WHERE d < '2024-01-10'
)
SELECT ds2.d AS date, COALESCE(ds.amount, 0) AS amount
FROM date_series ds2
LEFT JOIN daily_sales ds ON ds.sale_date = ds2.d ORDER BY ds2.d;
```

## COALESCE 填零 + 累计和


```sql
WITH RECURSIVE date_series AS (
    SELECT DATE '2024-01-01' AS d
    UNION ALL
    SELECT d + INTERVAL 1 DAY FROM date_series WHERE d < '2024-01-10'
)
SELECT ds2.d AS date, COALESCE(ds.amount, 0) AS amount,
       SUM(COALESCE(ds.amount, 0)) OVER (ORDER BY ds2.d) AS running_total
FROM date_series ds2
LEFT JOIN daily_sales ds ON ds.sale_date = ds2.d ORDER BY ds2.d;
```

## 用最近已知值填充


```sql
WITH RECURSIVE date_series AS (
    SELECT DATE '2024-01-01' AS d
    UNION ALL
    SELECT d + INTERVAL 1 DAY FROM date_series WHERE d < '2024-01-10'
),
filled AS (
    SELECT ds2.d, ds.amount, COUNT(ds.amount) OVER (ORDER BY ds2.d) AS grp
    FROM date_series ds2 LEFT JOIN daily_sales ds ON ds.sale_date = ds2.d
)
SELECT d AS date, FIRST_VALUE(amount) OVER (PARTITION BY grp ORDER BY d) AS filled_amount
FROM filled ORDER BY d;
```

## 动态日期范围


```sql
WITH RECURSIVE date_series AS (
    SELECT MIN(sale_date) AS d FROM daily_sales
    UNION ALL
    SELECT d + INTERVAL 1 DAY FROM date_series
    WHERE d < (SELECT MAX(sale_date) FROM daily_sales)
)
SELECT ds2.d, COALESCE(ds.amount, 0) AS amount
FROM date_series ds2 LEFT JOIN daily_sales ds ON ds.sale_date = ds2.d ORDER BY ds2.d;
```

## 多维度日期填充


```sql
WITH RECURSIVE date_series AS (
    SELECT DATE '2024-01-01' AS d
    UNION ALL
    SELECT d + INTERVAL 1 DAY FROM date_series WHERE d < '2024-01-04'
)
SELECT ds.d, c.category, COALESCE(cs.amount, 0) AS amount
FROM date_series ds
CROSS JOIN (SELECT DISTINCT category FROM category_sales) c
LEFT JOIN category_sales cs ON cs.sale_date = ds.d AND cs.category = c.category
ORDER BY c.category, ds.d;
```

注意：KingbaseES (人大金仓) 支持递归 CTE
注意：使用 COALESCE 进行空值替换
注意：不支持 IGNORE NULLS，需用 COUNT 分组法模拟
注意：递归深度可能有默认限制
