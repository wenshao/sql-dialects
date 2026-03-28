# ClickHouse: JOIN

> 参考资料:
> - [1] ClickHouse SQL Reference - JOIN
>   https://clickhouse.com/docs/en/sql-reference/statements/select/join
> - [2] ClickHouse SQL Reference - SELECT
>   https://clickhouse.com/docs/en/sql-reference/statements/select


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

ARRAY JOIN（ClickHouse 特有，展开数组列）

```sql
SELECT username, tag
FROM users
ARRAY JOIN tags AS tag;

```

LEFT ARRAY JOIN（保留无数据的行）

```sql
SELECT username, tag
FROM users
LEFT ARRAY JOIN tags AS tag;

```

ARRAY JOIN 多列（同步展开多个数组）

```sql
SELECT username, tag, score
FROM users
ARRAY JOIN tags AS tag, scores AS score;

```

ARRAY JOIN + arrayEnumerate（带位置信息）

```sql
SELECT username, tag, num
FROM users
ARRAY JOIN tags AS tag, arrayEnumerate(tags) AS num;

```

ASOF JOIN（时间序列最近匹配）

```sql
SELECT s.symbol, s.price, t.trade_price
FROM stock_prices s
ASOF LEFT JOIN trades t ON s.symbol = t.symbol AND s.timestamp >= t.timestamp;

```

GLOBAL JOIN（分布式表跨节点 JOIN）

```sql
SELECT u.username, o.amount
FROM users u
GLOBAL INNER JOIN orders o ON u.id = o.user_id;

```

SEMI JOIN / ANTI JOIN

```sql
SELECT u.*
FROM users u
LEFT SEMI JOIN orders o ON u.id = o.user_id;    -- 有匹配的行
SELECT u.*
FROM users u
LEFT ANTI JOIN orders o ON u.id = o.user_id;    -- 无匹配的行

```

ANY JOIN（每行最多匹配一条，避免行膨胀）

```sql
SELECT u.username, o.amount
FROM users u
ANY LEFT JOIN orders o ON u.id = o.user_id;

```

JOIN 算法设置
SET join_algorithm = 'hash';          -- 默认：哈希连接
SET join_algorithm = 'partial_merge'; -- 部分合并连接（低内存）
SET join_algorithm = 'full_sorting_merge'; -- 全排序归并

多表 JOIN

```sql
SELECT u.username, o.amount, p.product_name
FROM users u
JOIN orders o ON u.id = o.user_id
JOIN order_items oi ON o.id = oi.order_id
JOIN products p ON oi.product_id = p.id;

```

注意：ClickHouse 不支持 NATURAL JOIN
注意：ClickHouse 不支持 LATERAL JOIN
注意：JOIN 默认使用 ALL 语义（返回所有匹配），可用 ANY 限制

