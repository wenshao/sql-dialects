# IBM DB2: 间隙检测与岛屿问题 (Gap Detection & Islands)

> 参考资料:
> - [DB2 Documentation - OLAP Specifications](https://www.ibm.com/docs/en/db2/11.5?topic=functions-olap-specification)
> - [DB2 Documentation - Recursive Common Table Expressions](https://www.ibm.com/docs/en/db2/11.5?topic=queries-recursive-common-table-expressions)
> - ============================================================
> - 准备数据
> - ============================================================

```sql
CREATE TABLE orders (id INTEGER NOT NULL PRIMARY KEY, info VARCHAR(100));
INSERT INTO orders VALUES (1,'a'),(2,'b'),(3,'c'),(5,'e'),(6,'f'),
    (10,'j'),(11,'k'),(12,'l'),(15,'o');

CREATE TABLE daily_sales (sale_date DATE NOT NULL PRIMARY KEY, amount DECIMAL(10,2));
INSERT INTO daily_sales VALUES
    ('2024-01-01',100),('2024-01-02',150),('2024-01-04',200),
    ('2024-01-05',120),('2024-01-08',300),('2024-01-09',250),
    ('2024-01-10',180);
```

## 使用 LAG/LEAD 查找数值间隙（DB2 9.7+）


```sql
SELECT id AS gap_start_after, next_id AS gap_end_before, next_id - id - 1 AS gap_size
FROM (SELECT id, LEAD(id) OVER (ORDER BY id) AS next_id FROM orders) t
WHERE next_id - id > 1;
```

## 查找日期间隙


```sql
SELECT sale_date, next_date, DAYS(next_date) - DAYS(sale_date) - 1 AS missing_days
FROM (
    SELECT sale_date, LEAD(sale_date) OVER (ORDER BY sale_date) AS next_date
    FROM daily_sales
) t WHERE DAYS(next_date) - DAYS(sale_date) > 1;
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

## 递归 CTE 生成序列（DB2 早期版本就支持递归 CTE）


```sql
WITH seq(n) AS (
    SELECT MIN(id) FROM orders
    UNION ALL
    SELECT n + 1 FROM seq WHERE n < (SELECT MAX(id) FROM orders)
)
SELECT s.n AS missing_id
FROM seq s LEFT JOIN orders o ON o.id = s.n
WHERE o.id IS NULL ORDER BY s.n;
```

## 日期序列

```sql
WITH date_seq(d) AS (
    SELECT MIN(sale_date) FROM daily_sales
    UNION ALL
    SELECT d + 1 DAY FROM date_seq WHERE d < (SELECT MAX(sale_date) FROM daily_sales)
)
SELECT d AS missing_date
FROM date_seq LEFT JOIN daily_sales ds ON ds.sale_date = date_seq.d
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

注意：DB2 是最早支持递归 CTE 的数据库之一
注意：DB2 使用 DAYS() 函数计算日期差值
注意：DB2 的日期加减用 + N DAYS 语法
注意：LAG/LEAD 从 DB2 9.7 开始支持
