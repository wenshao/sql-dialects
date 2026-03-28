# Materialize: 间隙检测与岛屿问题 (Gap Detection & Islands)

> 参考资料:
> - [Materialize Documentation - Window Functions](https://materialize.com/docs/sql/functions/#window-functions)
> - [Materialize Documentation - generate_series](https://materialize.com/docs/sql/functions/generate_series/)
> - ============================================================
> - 准备数据
> - ============================================================

```sql
CREATE TABLE orders (id INT, info TEXT);
INSERT INTO orders VALUES (1,'a'),(2,'b'),(3,'c'),(5,'e'),(6,'f'),
    (10,'j'),(11,'k'),(12,'l'),(15,'o');

CREATE TABLE daily_sales (sale_date DATE, amount NUMERIC(10,2));
INSERT INTO daily_sales VALUES
    ('2024-01-01',100),('2024-01-02',150),('2024-01-04',200),
    ('2024-01-05',120),('2024-01-08',300),('2024-01-09',250),
    ('2024-01-10',180);
```

## 使用 LAG/LEAD 查找数值间隙


```sql
SELECT id AS gap_start_after, next_id AS gap_end_before, next_id - id - 1 AS gap_size
FROM (SELECT id, LEAD(id) OVER (ORDER BY id) AS next_id FROM orders) t
WHERE next_id - id > 1;
```

## 查找日期间隙


```sql
SELECT sale_date, next_date, next_date - sale_date - 1 AS missing_days
FROM (
    SELECT sale_date, LEAD(sale_date) OVER (ORDER BY sale_date) AS next_date
    FROM daily_sales
) t WHERE next_date - sale_date > 1;
```

## 岛屿问题


```sql
SELECT MIN(id) AS island_start, MAX(id) AS island_end, COUNT(*) AS island_size
FROM (SELECT id, id - ROW_NUMBER() OVER (ORDER BY id) AS grp FROM orders) t
GROUP BY grp ORDER BY island_start;
```

## 自连接方法


```sql
SELECT a.id + 1 AS gap_start, MIN(b.id) - 1 AS gap_end
FROM orders a JOIN orders b ON b.id > a.id
GROUP BY a.id HAVING MIN(b.id) > a.id + 1 ORDER BY gap_start;
```

## 使用 generate_series（Materialize 兼容 PostgreSQL）


```sql
SELECT s AS missing_id
FROM generate_series(
    (SELECT MIN(id) FROM orders),
    (SELECT MAX(id) FROM orders)
) AS t(s)
LEFT JOIN orders o ON o.id = t.s
WHERE o.id IS NULL ORDER BY s;
```

## 增量维护的物化视图


## Materialize 的核心优势：间隙检测结果可以增量维护

```sql
CREATE MATERIALIZED VIEW gap_report AS
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
FROM gaps WHERE next_id - id > 1;
```

## 查询物化视图（结果实时更新）

```sql
SELECT * FROM gap_report ORDER BY range_start;
```

注意：Materialize 兼容 PostgreSQL 语法，支持 generate_series
注意：Materialize 的物化视图是增量维护的，数据变化时自动更新
注意：Materialize 不支持递归 CTE
注意：使用 CREATE MATERIALIZED VIEW 可以让间隙检测结果实时可查
