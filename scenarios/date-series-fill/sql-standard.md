# SQL 标准: 日期序列生成与间隙填充

> 参考资料:
> - [ISO/IEC 9075 SQL:1999 - WITH RECURSIVE](https://www.iso.org/standard/26197.html)
> - [ISO/IEC 9075 SQL:2003 - Window Functions](https://www.iso.org/standard/34133.html)

## 1. 递归 CTE 生成日期序列（SQL:1999）

```sql
WITH RECURSIVE date_series(d) AS (
    SELECT DATE '2024-01-01'
    UNION ALL
    SELECT d + INTERVAL '1' DAY FROM date_series WHERE d < DATE '2024-01-10'
)
SELECT d AS date FROM date_series;
```

## 2. LEFT JOIN 填充间隙

```sql
WITH RECURSIVE date_series(d) AS (
    SELECT DATE '2024-01-01'
    UNION ALL
    SELECT d + INTERVAL '1' DAY FROM date_series WHERE d < DATE '2024-01-10'
)
SELECT ds2.d AS date, COALESCE(ds.amount, 0) AS amount
FROM date_series ds2
LEFT JOIN daily_sales ds ON ds.sale_date = ds2.d
ORDER BY ds2.d;
```

## 3. COALESCE 填零 + 窗口函数累计和

SUM(COALESCE(amount, 0)) OVER (ORDER BY date) AS running_total

## 4. 用最近已知值填充

标准 SQL 没有统一的 IGNORE NULLS 支持
使用 COUNT 分组法模拟

## 5-6. 多维度填充

日期序列 CROSS JOIN 维度表 LEFT JOIN 事实表

- **注意：WITH RECURSIVE 是 SQL:1999 标准**
- **注意：COALESCE 是 SQL-92 标准函数**
- **注意：窗口函数是 SQL:2003 标准**
- **注意：IGNORE NULLS 不是所有数据库都支持**
- **注意：generate_series / GENERATE_DATE_ARRAY 不是 SQL 标准**
