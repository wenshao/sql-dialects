# OceanBase: DELETE

> 参考资料:
> - [OceanBase SQL Reference (MySQL Mode)](https://www.oceanbase.com/docs/common-oceanbase-database-cn)
> - [OceanBase SQL Reference (Oracle Mode)](https://www.oceanbase.com/docs/common-oceanbase-database-cn)

**引擎定位**: 分布式关系型数据库，兼容 MySQL/Oracle 双模式。基于 LSM-Tree 存储，Paxos 共识。

## MySQL Mode


Basic delete (same as MySQL)
```sql
DELETE FROM users WHERE username = 'alice';

```

DELETE with LIMIT / ORDER BY
```sql
DELETE FROM users WHERE status = 0 ORDER BY created_at LIMIT 100;

```

Multi-table delete (same as MySQL)
```sql
DELETE u FROM users u
JOIN blacklist b ON u.email = b.email;

```

DELETE from multiple tables simultaneously
```sql
DELETE u, o FROM users u
JOIN orders o ON u.id = o.user_id
WHERE u.status = 0;

```

DELETE with CTE
```sql
WITH inactive AS (
    SELECT id FROM users WHERE last_login < '2023-01-01'
)
DELETE u FROM users u JOIN inactive i ON u.id = i.id;

```

TRUNCATE (same as MySQL)
```sql
TRUNCATE TABLE users;

```

DELETE IGNORE
```sql
DELETE IGNORE FROM users WHERE id = 1;

```

Parallel DML hint (OceanBase-specific)
```sql
DELETE /*+ ENABLE_PARALLEL_DML PARALLEL(4) */ FROM users
WHERE last_login < '2023-01-01';

```

Subquery delete
```sql
DELETE FROM users WHERE id IN (SELECT user_id FROM blacklist);

```

## Oracle Mode


Basic delete
```sql
DELETE FROM users WHERE username = 'alice';

```

DELETE with RETURNING (Oracle mode)
```sql
DELETE FROM users WHERE username = 'alice'
RETURNING id, username, email INTO :v_id, :v_name, :v_email;

```

Subquery delete
```sql
DELETE FROM users WHERE id IN (SELECT user_id FROM blacklist);

```

Correlated subquery delete
```sql
DELETE FROM users u
WHERE EXISTS (SELECT 1 FROM blacklist b WHERE b.user_id = u.id);

```

TRUNCATE (Oracle syntax)
```sql
TRUNCATE TABLE users;

```

Multi-table delete with MERGE (delete matched rows)
```sql
MERGE INTO users t
USING blacklist s ON (t.email = s.email)
WHEN MATCHED THEN DELETE;
```

Note: MERGE ... DELETE supported in Oracle mode 4.0+

Limitations:
MySQL mode: mostly identical to MySQL
Oracle mode: DELETE with RETURNING supported
Large deletes should be batched for performance
Partition-level delete: DROP PARTITION is faster than DELETE for removing all data
  ALTER TABLE logs DROP PARTITION p2023;
