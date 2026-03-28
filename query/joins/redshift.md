# Redshift: JOIN

> 参考资料:
> - [Redshift SQL Reference](https://docs.aws.amazon.com/redshift/latest/dg/cm_chap_SQLCommandRef.html)
> - [Redshift SQL Functions](https://docs.aws.amazon.com/redshift/latest/dg/c_SQL_functions.html)
> - [Redshift Data Types](https://docs.aws.amazon.com/redshift/latest/dg/c_Supported_data_types.html)


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


DISTKEY 优化的 JOIN
当两个表的 JOIN 键是各自的 DISTKEY 时，相同值在同一切片
无需数据重分布，性能最佳
示例：users DISTKEY(id) JOIN orders DISTKEY(user_id)

广播 JOIN（小表自动广播）
DISTSTYLE ALL 的表会被复制到每个节点
与任何表 JOIN 时都不需要数据移动

查看 JOIN 分布策略
```sql
EXPLAIN SELECT u.username, o.amount
FROM users u JOIN orders o ON u.id = o.user_id;
```

DS_DIST_NONE: 无需重分布（DISTKEY 对齐或 DISTSTYLE ALL）
DS_BCAST_INNER: 广播内表
DS_DIST_ALL_NONE: ALL 表，无需移动
DS_DIST_BOTH: 两表都需要重分布（最慢）

跨数据库 JOIN（Redshift 2021+）
```sql
SELECT u.username, e.event_type
FROM db1.public.users u
JOIN db2.public.events e ON u.id = e.user_id;
```


Redshift Spectrum 外部表 JOIN
```sql
SELECT u.username, e.event_type
FROM users u
JOIN spectrum_schema.external_events e ON u.id = e.user_id;
```


注意：Redshift 不支持 LATERAL JOIN
注意：选择合适的 DISTKEY 可以显著优化 JOIN 性能
注意：小维度表使用 DISTSTYLE ALL 避免 JOIN 时数据移动
注意：可以与 Redshift Spectrum 外部表做 JOIN
注意：EXPLAIN 可以查看 JOIN 的数据分布策略
