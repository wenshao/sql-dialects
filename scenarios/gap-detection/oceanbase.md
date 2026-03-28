# OceanBase: 间隔检测

> 参考资料:
> - [OceanBase Documentation - Window Functions](https://www.oceanbase.com/docs/common-oceanbase-database-cn-1000000001576792)
> - [OceanBase Documentation - Recursive CTE](https://www.oceanbase.com/docs/common-oceanbase-database-cn-1000000001577057)

**引擎定位**: 分布式关系型数据库，兼容 MySQL/Oracle 双模式。基于 LSM-Tree 存储，Paxos 共识。

## 准备数据


```sql
CREATE TABLE orders (id INT PRIMARY KEY, info VARCHAR(100));
INSERT INTO orders VALUES (1,'a'),(2,'b'),(3,'c'),(5,'e'),(6,'f'),
    (10,'j'),(11,'k'),(12,'l'),(15,'o');

CREATE TABLE daily_sales (sale_date DATE PRIMARY KEY, amount DECIMAL(10,2));
INSERT INTO daily_sales VALUES
    ('2024-01-01',100),('2024-01-02',150),('2024-01-04',200),
    ('2024-01-05',120),('2024-01-08',300),('2024-01-09',250),
    ('2024-01-10',180);

```

## 使用 LAG/LEAD 查找数值间隙


OceanBase MySQL 模式
```sql
SELECT id AS gap_start_after, next_id AS gap_end_before, next_id - id - 1 AS gap_size
FROM (SELECT id, LEAD(id) OVER (ORDER BY id) AS next_id FROM orders) t
WHERE next_id - id > 1;

```

## 查找日期间隙


MySQL 模式
```sql
SELECT sale_date, next_date, DATEDIFF(next_date, sale_date) - 1 AS missing_days
FROM (
    SELECT sale_date, LEAD(sale_date) OVER (ORDER BY sale_date) AS next_date
    FROM daily_sales
) t WHERE DATEDIFF(next_date, sale_date) > 1;

```

Oracle 模式
SELECT sale_date, next_date, next_date - sale_date - 1 AS missing_days
FROM (SELECT sale_date, LEAD(sale_date) OVER (ORDER BY sale_date) AS next_date
       FROM daily_sales)
WHERE next_date - sale_date > 1;

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

## 递归 CTE / CONNECT BY


MySQL 模式：递归 CTE
```sql
WITH RECURSIVE seq AS (
    SELECT MIN(id) AS n FROM orders
    UNION ALL
    SELECT n + 1 FROM seq WHERE n < (SELECT MAX(id) FROM orders)
)
SELECT s.n AS missing_id
FROM seq s LEFT JOIN orders o ON o.id = s.n
WHERE o.id IS NULL ORDER BY s.n;

```

Oracle 模式：CONNECT BY
SELECT LEVEL + (SELECT MIN(id) - 1 FROM orders) AS missing_id
FROM DUAL
CONNECT BY LEVEL <= (SELECT MAX(id) - MIN(id) + 1 FROM orders)
MINUS
SELECT id FROM orders;

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

**注意:** OceanBase 支持 MySQL 和 Oracle 两种模式
**注意:** MySQL 模式使用 DATEDIFF，Oracle 模式日期直接相减
**注意:** Oracle 模式支持 CONNECT BY 语法
**注意:** 两种模式都支持窗口函数和递归 CTE
