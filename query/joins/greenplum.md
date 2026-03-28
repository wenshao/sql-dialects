# Greenplum: JOIN

> 参考资料:
> - [Greenplum SQL Reference](https://docs.vmware.com/en/VMware-Greenplum/7/greenplum-database/ref_guide-sql_commands-sql_ref.html)
> - [Greenplum Admin Guide](https://docs.vmware.com/en/VMware-Greenplum/7/greenplum-database/admin_guide-intro-about_greenplum.html)


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


NATURAL JOIN
```sql
SELECT * FROM users NATURAL JOIN user_profiles;
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


LATERAL JOIN
```sql
SELECT u.username, recent_orders.*
FROM users u
CROSS JOIN LATERAL (
    SELECT amount, order_date
    FROM orders
    WHERE user_id = u.id
    ORDER BY order_date DESC
    LIMIT 3
) recent_orders;
```


多表 JOIN
```sql
SELECT u.username, o.amount, p.product_name
FROM users u
JOIN orders o ON u.id = o.user_id
JOIN order_items oi ON o.id = oi.order_id
JOIN products p ON oi.product_id = p.id;
```


JOIN 分布优化（Hash Join）
两表按相同键分布时，JOIN 在各 Segment 本地执行
不同分布键时，Greenplum 自动进行数据重分布（Redistribute Motion）

广播小表（Broadcast Motion）
优化器自动判断，小表广播到所有 Segment
可通过 enable_hashjoin, enable_nestloop 等参数调整

Redistribute Motion 控制
```sql
SET gp_segments_for_planner = 8;
```


禁用某种 JOIN 策略
```sql
SET enable_hashjoin = off;
SET enable_mergejoin = off;
SET enable_nestloop = off;
```


查看查询计划
```sql
EXPLAIN SELECT u.username, o.amount
FROM users u JOIN orders o ON u.id = o.user_id;
```


注意：Greenplum 兼容 PostgreSQL JOIN 语法
注意：分布键相同的表 JOIN 性能最好（本地 JOIN）
注意：不同分布键的表 JOIN 需要数据重分布（有网络开销）
注意：支持 LATERAL JOIN（PostgreSQL 9.3+）
