# OceanBase: UPDATE

> 参考资料:
> - [OceanBase SQL Reference (MySQL Mode)](https://www.oceanbase.com/docs/common-oceanbase-database-cn)
> - [OceanBase SQL Reference (Oracle Mode)](https://www.oceanbase.com/docs/common-oceanbase-database-cn)

**引擎定位**: 分布式关系型数据库，兼容 MySQL/Oracle 双模式。基于 LSM-Tree 存储，Paxos 共识。

## MySQL Mode


Basic update (same as MySQL)
```sql
UPDATE users SET age = 26 WHERE username = 'alice';

```

Multi-column update
```sql
UPDATE users SET email = 'new@example.com', age = 26 WHERE username = 'alice';

```

UPDATE with LIMIT
```sql
UPDATE users SET status = 0 WHERE status = 1 ORDER BY created_at LIMIT 100;

```

Multi-table update (same as MySQL)
```sql
UPDATE users u
JOIN orders o ON u.id = o.user_id
SET u.status = 1
WHERE o.amount > 1000;

```

WITH CTE
```sql
WITH vip AS (
    SELECT user_id FROM orders GROUP BY user_id HAVING SUM(amount) > 10000
)
UPDATE users u JOIN vip v ON u.id = v.user_id SET u.status = 2;

```

Subquery update
```sql
UPDATE users SET age = (SELECT AVG(age) FROM users) WHERE age IS NULL;

```

Parallel DML hint (OceanBase-specific, 4.0+)
```sql
UPDATE /*+ ENABLE_PARALLEL_DML PARALLEL(4) */ users
SET status = 0
WHERE last_login < '2023-01-01';

```

## Oracle Mode


Basic update
```sql
UPDATE users SET age = 26 WHERE username = 'alice';

```

Multi-column update
```sql
UPDATE users SET (email, age) = (SELECT 'new@example.com', 26 FROM DUAL)
WHERE username = 'alice';
```

Or simpler:
```sql
UPDATE users SET email = 'new@example.com', age = 26 WHERE username = 'alice';

```

Correlated subquery update (Oracle style)
```sql
UPDATE users u SET u.order_count = (
    SELECT COUNT(*) FROM orders o WHERE o.user_id = u.id
);

```

UPDATE with RETURNING (Oracle mode)
```sql
UPDATE users SET age = 26 WHERE username = 'alice'
RETURNING id, age INTO :v_id, :v_age;

```

MERGE statement (Oracle mode, for upsert-like behavior)
```sql
MERGE INTO users t
USING (SELECT 'alice' AS username, 'alice@example.com' AS email, 25 AS age FROM DUAL) s
ON (t.username = s.username)
WHEN MATCHED THEN
    UPDATE SET t.email = s.email, t.age = s.age
WHEN NOT MATCHED THEN
    INSERT (id, username, email, age) VALUES (seq_users.NEXTVAL, s.username, s.email, s.age);

```

Limitations:
MySQL mode: mostly identical to MySQL
Oracle mode: UPDATE with RETURNING supported
Partition-level UPDATE on partition key may move rows between partitions
Large updates should be batched to avoid timeout
