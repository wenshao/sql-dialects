# DuckDB: 日期序列填充

> 参考资料:
> - [DuckDB Documentation - generate_series](https://duckdb.org/docs/sql/functions/nested#generate_series)
> - [DuckDB Documentation - Date Functions](https://duckdb.org/docs/sql/functions/date)

**引擎定位**: 嵌入式 OLAP 分析引擎，类似 SQLite 的定位。列式存储 + 向量化执行，PostgreSQL 兼容语法。

## 准备数据


```sql
CREATE TABLE daily_sales (sale_date DATE PRIMARY KEY, amount DECIMAL(10,2));
INSERT INTO daily_sales VALUES
    ('2024-01-01',100),('2024-01-02',150),('2024-01-04',200),
    ('2024-01-05',120),('2024-01-08',300),('2024-01-09',250),('2024-01-10',180);

```

## generate_series 生成日期序列


```sql
SELECT d::DATE AS date
FROM generate_series(DATE '2024-01-01', DATE '2024-01-10', INTERVAL 1 DAY) t(d);

```

range 函数（DuckDB 特有，不包含终点）
```sql
SELECT d::DATE AS date
FROM range(DATE '2024-01-01', DATE '2024-01-11', INTERVAL 1 DAY) t(d);

```

## LEFT JOIN 填充间隙


```sql
SELECT d::DATE AS date, COALESCE(ds.amount, 0) AS amount
FROM generate_series(DATE '2024-01-01', DATE '2024-01-10', INTERVAL 1 DAY) t(d)
LEFT JOIN daily_sales ds ON ds.sale_date = t.d::DATE
ORDER BY d;

```

## COALESCE + 累计和


```sql
SELECT d::DATE AS date, COALESCE(ds.amount, 0) AS amount,
       SUM(COALESCE(ds.amount, 0)) OVER (ORDER BY d) AS running_total
FROM generate_series(DATE '2024-01-01', DATE '2024-01-10', INTERVAL 1 DAY) t(d)
LEFT JOIN daily_sales ds ON ds.sale_date = t.d::DATE
ORDER BY d;

```

## 用最近已知值填充


DuckDB 支持某些窗口函数中的 IGNORE NULLS
```sql
WITH filled AS (
    SELECT d::DATE AS date, ds.amount,
           COUNT(ds.amount) OVER (ORDER BY d) AS grp
    FROM generate_series(DATE '2024-01-01', DATE '2024-01-10', INTERVAL 1 DAY) t(d)
    LEFT JOIN daily_sales ds ON ds.sale_date = t.d::DATE
)
SELECT date, FIRST_VALUE(amount) OVER (PARTITION BY grp ORDER BY date) AS filled_amount
FROM filled ORDER BY date;

```

## 5-6. 动态范围 + 多维度


```sql
SELECT d::DATE AS date, COALESCE(ds.amount, 0) AS amount
FROM generate_series(
    (SELECT MIN(sale_date) FROM daily_sales),
    (SELECT MAX(sale_date) FROM daily_sales),
    INTERVAL 1 DAY
) t(d)
LEFT JOIN daily_sales ds ON ds.sale_date = t.d::DATE
ORDER BY d;

```

**注意:** DuckDB 原生支持 generate_series（类似 PostgreSQL）
**注意:** DuckDB 还支持 range 函数（不包含终点）
**注意:** DuckDB 的日期算术运算非常灵活
**注意:** DuckDB 列式存储对 LEFT JOIN + 聚合有很好的优化
