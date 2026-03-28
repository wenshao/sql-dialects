# openGauss: 日期序列生成与间隙填充 (Date Series Fill)

> 参考资料:
> - [openGauss Documentation - SQL Reference](https://docs.opengauss.org/en/docs/latest/docs/SQLReference/)
> - [openGauss Documentation - Window Functions](https://docs.opengauss.org/en/docs/latest/docs/SQLReference/)


## 准备数据


```sql
CREATE TABLE daily_sales (sale_date DATE PRIMARY KEY, amount NUMERIC(10,2));
INSERT INTO daily_sales VALUES
    ('2024-01-01',100),('2024-01-02',150),('2024-01-04',200),
    ('2024-01-05',120),('2024-01-08',300),('2024-01-09',250),('2024-01-10',180);
```

## 使用 generate_series 生成日期序列


```sql
SELECT d::DATE AS date
FROM generate_series(
    '2024-01-01'::DATE, '2024-01-10'::DATE, INTERVAL '1 day'
) AS t(d);
```

## LEFT JOIN 填充间隙


```sql
SELECT d::DATE AS date, COALESCE(ds.amount, 0) AS amount
FROM generate_series(
    '2024-01-01'::DATE, '2024-01-10'::DATE, INTERVAL '1 day'
) AS t(d)
LEFT JOIN daily_sales ds ON ds.sale_date = t.d::DATE
ORDER BY d;
```

## COALESCE 填零 + 累计和


```sql
SELECT d::DATE AS date, COALESCE(ds.amount, 0) AS amount,
       SUM(COALESCE(ds.amount, 0)) OVER (ORDER BY d) AS running_total
FROM generate_series('2024-01-01'::DATE, '2024-01-10'::DATE, INTERVAL '1 day') AS t(d)
LEFT JOIN daily_sales ds ON ds.sale_date = t.d::DATE
ORDER BY d;
```

## 用最近已知值填充


```sql
WITH filled AS (
    SELECT d::DATE AS date, ds.amount,
           COUNT(ds.amount) OVER (ORDER BY d) AS grp
    FROM generate_series('2024-01-01'::DATE, '2024-01-10'::DATE, INTERVAL '1 day') AS t(d)
    LEFT JOIN daily_sales ds ON ds.sale_date = t.d::DATE
)
SELECT date, FIRST_VALUE(amount) OVER (PARTITION BY grp ORDER BY date) AS filled_amount
FROM filled ORDER BY date;
```

## 动态日期范围


```sql
SELECT d::DATE AS date, COALESCE(ds.amount, 0) AS amount
FROM generate_series(
    (SELECT MIN(sale_date) FROM daily_sales),
    (SELECT MAX(sale_date) FROM daily_sales),
    INTERVAL '1 day'
) AS t(d)
LEFT JOIN daily_sales ds ON ds.sale_date = t.d::DATE ORDER BY d;
```

## 多维度日期填充


```sql
SELECT d::DATE AS date, c.category, COALESCE(cs.amount, 0) AS amount
FROM generate_series('2024-01-01'::DATE, '2024-01-04'::DATE, INTERVAL '1 day') AS t(d)
CROSS JOIN (SELECT DISTINCT category FROM category_sales) c
LEFT JOIN category_sales cs ON cs.sale_date = t.d::DATE AND cs.category = c.category
ORDER BY c.category, d;
```

注意：openGauss 兼容 PostgreSQL，支持 generate_series
注意：generate_series 支持 DATE、TIMESTAMP、INTEGER 类型
注意：使用 COALESCE 进行空值替换
注意：使用 COUNT 分组法模拟 IGNORE NULLS（如不原生支持）
