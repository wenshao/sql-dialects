# Snowflake: 间隙检测与岛屿问题

> 参考资料:
> - [1] Snowflake Documentation - Window Functions
>   https://docs.snowflake.com/en/sql-reference/functions-analytic


## 示例数据

```sql
CREATE OR REPLACE TEMPORARY TABLE orders (id INT, info VARCHAR(100));
INSERT INTO orders VALUES (1,'a'),(2,'b'),(3,'c'),(5,'e'),(6,'f'),
    (10,'j'),(11,'k'),(12,'l'),(15,'o');

CREATE OR REPLACE TEMPORARY TABLE daily_sales (sale_date DATE, amount NUMBER(10,2));
INSERT INTO daily_sales VALUES
    ('2024-01-01',100),('2024-01-02',150),('2024-01-04',200),
    ('2024-01-05',120),('2024-01-08',300),('2024-01-09',250),('2024-01-10',180);

```

## 1. LAG/LEAD 查找数值间隙


```sql
SELECT id AS gap_start_after, next_id AS gap_end_before, next_id - id - 1 AS gap_size
FROM (SELECT id, LEAD(id) OVER (ORDER BY id) AS next_id FROM orders)
WHERE next_id - id > 1;

```

## 2. 日期间隙检测


```sql
SELECT sale_date, next_date, DATEDIFF('DAY', sale_date, next_date) - 1 AS missing_days
FROM (
    SELECT sale_date, LEAD(sale_date) OVER (ORDER BY sale_date) AS next_date
    FROM daily_sales
)
WHERE DATEDIFF('DAY', sale_date, next_date) > 1;

```

## 3. 岛屿问题（Islands）


经典 ROW_NUMBER 差值法:

```sql
SELECT MIN(id) AS island_start, MAX(id) AS island_end, COUNT(*) AS island_size
FROM (
    SELECT id, id - ROW_NUMBER() OVER (ORDER BY id) AS grp FROM orders
)
GROUP BY grp ORDER BY island_start;
```

 原理: 连续的 id 减去连续的 ROW_NUMBER 得到相同的差值 → 同一组

## 4. GENERATOR 生成完整序列查找缺失值


```sql
WITH params AS (
    SELECT MIN(id) AS min_id, MAX(id) AS max_id FROM orders
),
seq AS (
    SELECT ROW_NUMBER() OVER (ORDER BY 1) - 1 + p.min_id AS n
    FROM TABLE(GENERATOR(ROWCOUNT => 10000)), params p
    QUALIFY n <= p.max_id
)
SELECT s.n AS missing_id
FROM seq s LEFT JOIN orders o ON o.id = s.n
WHERE o.id IS NULL ORDER BY s.n;

```

日期序列查找缺失日期:

```sql
WITH params AS (
    SELECT MIN(sale_date) AS min_d, MAX(sale_date) AS max_d FROM daily_sales
),
date_seq AS (
    SELECT DATEADD('DAY', ROW_NUMBER() OVER (ORDER BY 1) - 1, p.min_d) AS d
    FROM TABLE(GENERATOR(ROWCOUNT => 10000)), params p
    QUALIFY d <= p.max_d
)
SELECT ds.d AS missing_date
FROM date_seq ds LEFT JOIN daily_sales s ON s.sale_date = ds.d
WHERE s.sale_date IS NULL ORDER BY ds.d;

```

## 5. 综合: 间隙与岛屿合并输出


```sql
WITH islands AS (
    SELECT id, id - ROW_NUMBER() OVER (ORDER BY id) AS grp FROM orders
),
gaps AS (
    SELECT id, LEAD(id) OVER (ORDER BY id) AS next_id FROM orders
)
SELECT 'Island' AS type, MIN(id) AS range_start, MAX(id) AS range_end, COUNT(*) AS size
FROM islands GROUP BY grp
UNION ALL
SELECT 'Gap', id + 1, next_id - 1, next_id - id - 1
FROM gaps WHERE next_id - id > 1
ORDER BY range_start;

```

## 横向对比

| 方法         | Snowflake        | PostgreSQL       | MySQL |
|------|------|------|------|
| 间隙检测     | LAG/LEAD         | LAG/LEAD         | LAG/LEAD(8.0+) |
| 完整序列     | GENERATOR        | generate_series  | 递归CTE |
| 岛屿问题     | ROW_NUMBER差值   | ROW_NUMBER差值   | ROW_NUMBER(8.0+) |
| 日期序列     | GENERATOR+DATEADD| generate_series  | 递归CTE |

