# Azure Synapse Analytics: 间隙检测与岛屿问题 (Gap Detection & Islands)

> 参考资料:
> - [Synapse SQL Documentation - Window Functions](https://learn.microsoft.com/en-us/azure/synapse-analytics/sql/query-data-storage)
> - [Microsoft Docs - OVER clause](https://learn.microsoft.com/en-us/sql/t-sql/queries/select-over-clause-transact-sql)


## 准备数据


```sql
CREATE TABLE orders (id INT, info NVARCHAR(100));
INSERT INTO orders VALUES (1,'a'),(2,'b'),(3,'c'),(5,'e'),(6,'f'),
    (10,'j'),(11,'k'),(12,'l'),(15,'o');

CREATE TABLE daily_sales (sale_date DATE, amount DECIMAL(10,2));
INSERT INTO daily_sales VALUES
    ('2024-01-01',100),('2024-01-02',150),('2024-01-04',200),
    ('2024-01-05',120),('2024-01-08',300),('2024-01-09',250),
    ('2024-01-10',180);
```


## 1. 使用 LAG/LEAD 查找数值间隙


```sql
SELECT id AS gap_start_after, next_id AS gap_end_before, next_id - id - 1 AS gap_size
FROM (SELECT id, LEAD(id) OVER (ORDER BY id) AS next_id FROM orders) t
WHERE next_id - id > 1;
```


## 2. 查找日期间隙


```sql
SELECT sale_date, next_date, DATEDIFF(DAY, sale_date, next_date) - 1 AS missing_days
FROM (
    SELECT sale_date, LEAD(sale_date) OVER (ORDER BY sale_date) AS next_date
    FROM daily_sales
) t WHERE DATEDIFF(DAY, sale_date, next_date) > 1;
```


## 3. 岛屿问题


```sql
SELECT MIN(id) AS island_start, MAX(id) AS island_end, COUNT(*) AS island_size
FROM (SELECT id, id - ROW_NUMBER() OVER (ORDER BY id) AS grp FROM orders) t
GROUP BY grp ORDER BY island_start;
```


## 4. 自连接方法


```sql
SELECT a.id + 1 AS gap_start, MIN(b.id) - 1 AS gap_end
FROM orders a JOIN orders b ON b.id > a.id
GROUP BY a.id HAVING MIN(b.id) > a.id + 1 ORDER BY gap_start;
```


## 5. 使用数字表生成序列


```sql
;WITH E1(N) AS (SELECT 1 UNION ALL SELECT 1 UNION ALL SELECT 1 UNION ALL SELECT 1
                UNION ALL SELECT 1 UNION ALL SELECT 1 UNION ALL SELECT 1 UNION ALL SELECT 1),
     E2(N) AS (SELECT 1 FROM E1 a CROSS JOIN E1 b),
     E4(N) AS (SELECT 1 FROM E2 a CROSS JOIN E2 b),
     nums(n) AS (SELECT ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) FROM E4)
SELECT n AS missing_id
FROM nums
WHERE n BETWEEN (SELECT MIN(id) FROM orders) AND (SELECT MAX(id) FROM orders)
  AND n NOT IN (SELECT id FROM orders)
ORDER BY n;
```


## 6. 综合示例


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


注意：Synapse 兼容 T-SQL 语法
注意：Synapse 专用 SQL 池不支持递归 CTE
注意：使用交叉连接数字表替代 generate_series
注意：DATEDIFF(DAY, start, end) 用于日期差值计算
