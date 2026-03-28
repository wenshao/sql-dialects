# Trino: JOIN 连接查询

> 参考资料:
> - [Trino - SELECT (JOIN)](https://trino.io/docs/current/sql/select.html)
> - [Trino - SQL Statement List](https://trino.io/docs/current/sql.html)

**引擎定位**: 分布式查询引擎（前身 Presto），不存储数据。通过 Connector 查询异构数据源（Hive/Iceberg/RDBMS）。

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

UNNEST：展开数组
```sql
SELECT u.username, tag
FROM users u
CROSS JOIN UNNEST(u.tags) AS t(tag);

```

UNNEST + LEFT JOIN
```sql
SELECT u.username, tag
FROM users u
LEFT JOIN UNNEST(u.tags) AS t(tag) ON TRUE;

```

UNNEST 带序号（WITH ORDINALITY）
```sql
SELECT u.username, tag, pos
FROM users u
CROSS JOIN UNNEST(u.tags) WITH ORDINALITY AS t(tag, pos);

```

UNNEST MAP 类型
```sql
SELECT u.username, k, v
FROM users u
CROSS JOIN UNNEST(u.properties) AS t(k, v);

```

LATERAL（子查询可以引用外部表的列）
```sql
SELECT u.username, latest.amount
FROM users u
JOIN LATERAL (
    SELECT amount FROM orders WHERE user_id = u.id ORDER BY created_at DESC LIMIT 1
) latest ON TRUE;

```

LEFT JOIN LATERAL
```sql
SELECT u.username, latest.amount
FROM users u
LEFT JOIN LATERAL (
    SELECT amount FROM orders WHERE user_id = u.id ORDER BY created_at DESC LIMIT 1
) latest ON TRUE;

```

TABLESAMPLE（取决于连接器支持）
```sql
SELECT u.username, o.amount
FROM users u TABLESAMPLE SYSTEM (10)
JOIN orders o ON u.id = o.user_id;

```

多表 JOIN
```sql
SELECT u.username, o.amount, p.product_name
FROM users u
JOIN orders o ON u.id = o.user_id
JOIN order_items oi ON o.id = oi.order_id
JOIN products p ON oi.product_id = p.id;

```

**注意:** Trino 语法高度符合 SQL 标准
**注意:** JOIN 行为取决于底层连接器（Hive、MySQL、PostgreSQL 等）
