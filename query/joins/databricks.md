# Databricks SQL: JOIN

> 参考资料:
> - [Databricks SQL Language Reference](https://docs.databricks.com/en/sql/language-manual/index.html)
> - [Databricks SQL - Built-in Functions](https://docs.databricks.com/en/sql/language-manual/sql-ref-functions-builtin.html)
> - [Delta Lake Documentation](https://docs.delta.io/latest/index.html)


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


USING
```sql
SELECT * FROM users JOIN orders USING (user_id);
```


NATURAL JOIN
```sql
SELECT * FROM users NATURAL JOIN orders;
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


LATERAL JOIN（Databricks 2023+）
```sql
SELECT u.username, latest.amount
FROM users u
JOIN LATERAL (
    SELECT amount FROM orders WHERE user_id = u.id ORDER BY created_at DESC LIMIT 1
) latest;
```


LEFT JOIN LATERAL
```sql
SELECT u.username, latest.amount
FROM users u
LEFT JOIN LATERAL (
    SELECT amount FROM orders WHERE user_id = u.id ORDER BY created_at DESC LIMIT 1
) latest;
```


SEMI JOIN
```sql
SELECT * FROM users u
WHERE EXISTS (SELECT 1 FROM orders o WHERE o.user_id = u.id);
```


等价写法
```sql
SELECT * FROM users u
LEFT SEMI JOIN orders o ON u.id = o.user_id;
```


ANTI JOIN
```sql
SELECT * FROM users u
WHERE NOT EXISTS (SELECT 1 FROM orders o WHERE o.user_id = u.id);
```


等价写法
```sql
SELECT * FROM users u
LEFT ANTI JOIN orders o ON u.id = o.user_id;
```


数组展开（EXPLODE，类似 LATERAL FLATTEN）
```sql
SELECT u.username, tag
FROM users u
LATERAL VIEW EXPLODE(u.tags) t AS tag;
```


LATERAL VIEW OUTER（保留没有数组的行）
```sql
SELECT u.username, tag
FROM users u
LATERAL VIEW OUTER EXPLODE(u.tags) t AS tag;
```


Map 展开
```sql
SELECT u.username, key, value
FROM users u
LATERAL VIEW EXPLODE(u.properties) t AS key, value;
```


POSEXPLODE（带位置索引）
```sql
SELECT u.username, pos, tag
FROM users u
LATERAL VIEW POSEXPLODE(u.tags) t AS pos, tag;
```


JOIN 优化提示
广播 JOIN（强制小表广播到每个执行器）
```sql
SELECT /*+ BROADCAST(countries) */ u.username, c.name
FROM users u
JOIN countries c ON u.country_code = c.code;
```


Shuffle Hash Join 提示
```sql
SELECT /*+ SHUFFLE_HASH(orders) */ u.username, o.amount
FROM users u
JOIN orders o ON u.id = o.user_id;
```


Sort Merge Join 提示
```sql
SELECT /*+ MERGE(orders) */ u.username, o.amount
FROM users u
JOIN orders o ON u.id = o.user_id;
```


自适应查询执行（AQE，默认开启）
Photon 引擎自动优化 JOIN 策略

跨 Catalog JOIN（Unity Catalog）
```sql
SELECT u.username, o.amount
FROM catalog1.schema1.users u
JOIN catalog2.schema2.orders o ON u.id = o.user_id;
```


注意：Databricks 支持 LEFT SEMI JOIN 和 LEFT ANTI JOIN 语法
注意：LATERAL VIEW EXPLODE 用于展开数组/Map 类型
注意：JOIN 提示（BROADCAST / SHUFFLE_HASH / MERGE）可手动控制策略
注意：Photon 引擎对 JOIN 有显著性能提升
注意：AQE（自适应查询执行）自动优化 JOIN 和数据倾斜
注意：Unity Catalog 支持跨 Catalog 的 JOIN
