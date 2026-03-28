# Azure Synapse: JOIN

> 参考资料:
> - [Synapse SQL Features](https://learn.microsoft.com/en-us/azure/synapse-analytics/sql/overview-features)
> - [Synapse T-SQL Differences](https://learn.microsoft.com/en-us/azure/synapse-analytics/sql/overview-features)


INNER JOIN
```sql
SELECT u.username, o.amount
FROM users u
INNER JOIN orders o ON u.id = o.user_id;
```


LEFT JOIN
```sql
SELECT u.username, o.amount
FROM users u
LEFT JOIN orders o ON u.id = o.user_id;
```


RIGHT JOIN
```sql
SELECT u.username, o.amount
FROM users u
RIGHT JOIN orders o ON u.id = o.user_id;
```


FULL OUTER JOIN
```sql
SELECT u.username, o.amount
FROM users u
FULL OUTER JOIN orders o ON u.id = o.user_id;
```


CROSS JOIN
```sql
SELECT u.username, r.role_name
FROM users u
CROSS JOIN roles r;
```


自连接
```sql
SELECT e.username AS employee, m.username AS manager
FROM users e
LEFT JOIN users m ON e.manager_id = m.id;
```


多表 JOIN
```sql
SELECT u.username, o.amount, p.product_name
FROM users u
JOIN orders o ON u.id = o.user_id
JOIN order_items oi ON o.id = oi.order_id
JOIN products p ON oi.product_id = p.id;
```


子查询 JOIN
```sql
SELECT u.username, t.total
FROM users u
JOIN (
    SELECT user_id, SUM(amount) AS total
    FROM orders GROUP BY user_id
) t ON u.id = t.user_id;
```


CROSS APPLY（类似 LATERAL JOIN，T-SQL 语法）
```sql
SELECT u.username, latest.amount
FROM users u
CROSS APPLY (
    SELECT TOP 1 amount
    FROM orders WHERE user_id = u.id
    ORDER BY created_at DESC
) latest;
```


OUTER APPLY
```sql
SELECT u.username, latest.amount
FROM users u
OUTER APPLY (
    SELECT TOP 1 amount
    FROM orders WHERE user_id = u.id
    ORDER BY created_at DESC
) latest;
```


分布优化的 JOIN
HASH 分布的表在 JOIN 键上对齐时，无需数据移动
示例：users DISTRIBUTION = HASH(id) JOIN orders DISTRIBUTION = HASH(user_id)

REPLICATE 表 JOIN（小维度表）
REPLICATE 表在每个节点有完整拷贝，JOIN 时无需数据移动
```sql
CREATE TABLE countries (code CHAR(2), name NVARCHAR(100))
WITH (DISTRIBUTION = REPLICATE);

SELECT u.username, c.name AS country
FROM users u
JOIN countries c ON u.country_code = c.code;
```


查看 JOIN 的数据移动
```sql
EXPLAIN SELECT u.username, o.amount
FROM users u JOIN orders o ON u.id = o.user_id;
```

ShuffleMove: 按 JOIN 键重分布（有开销）
BroadcastMove: 广播小表（有开销）
无 Move: HASH 键对齐或 REPLICATE 表（最优）

Serverless 池的 JOIN
```sql
SELECT a.*, b.*
FROM OPENROWSET(BULK '...path1...', FORMAT = 'PARQUET') AS a
JOIN OPENROWSET(BULK '...path2...', FORMAT = 'PARQUET') AS b
ON a.id = b.user_id;
```


注意：选择合适的 DISTRIBUTION 对 JOIN 性能至关重要
注意：REPLICATE 分布适合小维度表（< 2GB），避免 JOIN 时数据移动
注意：CROSS APPLY / OUTER APPLY 等价于其他数据库的 LATERAL JOIN
注意：60 个固定分布，HASH 键不对齐会导致数据 Shuffle
注意：统计信息对查询优化器选择 JOIN 策略很重要
