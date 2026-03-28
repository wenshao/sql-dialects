# Spanner: 间隔检测

> 参考资料:
> - [Spanner Documentation - Analytic Functions](https://cloud.google.com/spanner/docs/reference/standard-sql/analytic-function-concepts)
> - [Spanner Documentation - GENERATE_ARRAY](https://cloud.google.com/spanner/docs/reference/standard-sql/array_functions)

**引擎定位**: Google 全球分布式数据库，TrueTime 外部一致性。基于 Colossus 存储，支持跨洲强一致事务。

## 准备数据


```sql
CREATE TABLE orders (id INT64 NOT NULL, info STRING(100)) PRIMARY KEY (id);
CREATE TABLE daily_sales (sale_date DATE NOT NULL, amount NUMERIC) PRIMARY KEY (sale_date);

```

## 使用 LAG/LEAD 查找数值间隙


```sql
SELECT id AS gap_start_after, next_id AS gap_end_before, next_id - id - 1 AS gap_size
FROM (SELECT id, LEAD(id) OVER (ORDER BY id) AS next_id FROM orders)
WHERE next_id - id > 1;

```

## 查找日期间隙


```sql
SELECT sale_date, next_date,
       DATE_DIFF(next_date, sale_date, DAY) - 1 AS missing_days
FROM (
    SELECT sale_date, LEAD(sale_date) OVER (ORDER BY sale_date) AS next_date
    FROM daily_sales
) WHERE DATE_DIFF(next_date, sale_date, DAY) > 1;

```

## 岛屿问题


```sql
SELECT MIN(id) AS island_start, MAX(id) AS island_end, COUNT(*) AS island_size
FROM (SELECT id, id - ROW_NUMBER() OVER (ORDER BY id) AS grp FROM orders)
GROUP BY grp ORDER BY island_start;

```

## 自连接方法


```sql
SELECT a.id + 1 AS gap_start, MIN(b.id) - 1 AS gap_end
FROM orders a JOIN orders b ON b.id > a.id
GROUP BY a.id HAVING MIN(b.id) > a.id + 1 ORDER BY gap_start;

```

## 使用 GENERATE_ARRAY + UNNEST


```sql
SELECT n AS missing_id
FROM UNNEST(GENERATE_ARRAY(
    (SELECT MIN(id) FROM orders),
    (SELECT MAX(id) FROM orders)
)) AS n
LEFT JOIN orders o ON o.id = n
WHERE o.id IS NULL ORDER BY n;

SELECT d AS missing_date
FROM UNNEST(GENERATE_DATE_ARRAY(
    (SELECT MIN(sale_date) FROM daily_sales),
    (SELECT MAX(sale_date) FROM daily_sales),
    INTERVAL 1 DAY
)) AS d
LEFT JOIN daily_sales ds ON ds.sale_date = d
WHERE ds.sale_date IS NULL ORDER BY d;

```

## 综合示例


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

**注意:** Spanner 使用 GoogleSQL（标准 SQL 方言）
**注意:** GENERATE_ARRAY / GENERATE_DATE_ARRAY + UNNEST 生成序列
**注意:** Spanner 不支持递归 CTE
**注意:** DATE_DIFF(end, start, DAY) 计算日期差值
