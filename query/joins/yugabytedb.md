# YugabyteDB: JOIN 连接查询

> 参考资料:
> - [YugabyteDB YSQL Reference](https://docs.yugabyte.com/stable/api/ysql/)
> - [YugabyteDB PostgreSQL Compatibility](https://docs.yugabyte.com/stable/explore/ysql-language-features/)

**引擎定位**: 分布式 SQL 数据库，兼容 PostgreSQL 协议。基于 DocDB (RocksDB) 存储，Raft 共识。

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

Self join
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
SELECT * FROM users NATURAL JOIN profiles;

```

LATERAL JOIN (same as PostgreSQL)
```sql
SELECT u.username, top_order.amount
FROM users u
LEFT JOIN LATERAL (
    SELECT amount FROM orders WHERE user_id = u.id ORDER BY amount DESC LIMIT 1
) top_order ON true;

```

Multi-table JOIN
```sql
SELECT u.username, o.amount, p.product_name
FROM users u
JOIN orders o ON u.id = o.user_id
JOIN order_items oi ON o.id = oi.order_id
JOIN products p ON oi.product_id = p.id;

```

UNNEST (array expansion)
```sql
SELECT u.username, tag
FROM users u
CROSS JOIN UNNEST(u.tags) AS tag;

```

Colocated table join (YugabyteDB-specific optimization)
Tables in the same tablegroup are co-located for faster joins
CREATE TABLEGROUP order_group;
CREATE TABLE orders (...) TABLEGROUP order_group;
CREATE TABLE order_items (...) TABLEGROUP order_group;
```sql
SELECT o.id, oi.product_id
FROM orders o
JOIN order_items oi ON o.id = oi.order_id;
```

Co-located tables avoid cross-node communication

JOIN with hash/range sharding awareness
Joins on hash-sharded columns are more efficient when both tables
are sharded on the join key
```sql
SELECT u.username, o.amount
FROM users u                                   -- sharded on id
JOIN orders o ON u.id = o.user_id;             -- sharded on user_id

```

JOIN with geo-partitioned tables
```sql
SELECT u.username, o.amount
FROM geo_users u
JOIN geo_orders o ON u.id = o.user_id AND u.region = o.region;
```

Partition-wise join: each region processes its own data

JOIN with JSONB
```sql
SELECT u.username, o.amount
FROM users u
JOIN orders o ON u.id = o.user_id
WHERE u.metadata @> '{"premium": true}'::JSONB;

```

Note: All PostgreSQL JOIN types supported
Note: Co-located tables (via tablegroups) have faster joins
Note: Joins on sharding keys are more efficient
Note: Geo-partitioned joins can be partition-wise (region-local)
Note: LATERAL JOIN supported (same as PostgreSQL)
Note: Batched nested loop join optimization for distributed queries
