# OceanBase: UPSERT

> 参考资料:
> - [OceanBase SQL Reference (MySQL Mode)](https://www.oceanbase.com/docs/common-oceanbase-database-cn)
> - [OceanBase SQL Reference (Oracle Mode)](https://www.oceanbase.com/docs/common-oceanbase-database-cn)

**引擎定位**: 分布式关系型数据库，兼容 MySQL/Oracle 双模式。基于 LSM-Tree 存储，Paxos 共识。

## MySQL Mode


ON DUPLICATE KEY UPDATE (same as MySQL)
```sql
INSERT INTO users (username, email, age)
VALUES ('alice', 'alice@example.com', 25)
ON DUPLICATE KEY UPDATE
    email = VALUES(email),
    age = VALUES(age);

```

Row alias syntax (4.0+, same as MySQL 8.0.19+)
```sql
INSERT INTO users (username, email, age)
VALUES ('alice', 'alice@example.com', 25) AS new
ON DUPLICATE KEY UPDATE
    email = new.email,
    age = new.age;

```

REPLACE INTO (same as MySQL)
```sql
REPLACE INTO users (username, email, age)
VALUES ('alice', 'alice@example.com', 25);

```

INSERT IGNORE (same as MySQL)
```sql
INSERT IGNORE INTO users (username, email, age)
VALUES ('alice', 'alice@example.com', 25);

```

Multi-row upsert
```sql
INSERT INTO users (username, email, age) VALUES
    ('alice', 'alice@example.com', 25),
    ('bob', 'bob@example.com', 30)
ON DUPLICATE KEY UPDATE
    email = VALUES(email),
    age = VALUES(age);

```

## Oracle Mode


MERGE (Oracle-standard upsert)
```sql
MERGE INTO users t
USING (SELECT 'alice' AS username, 'alice@example.com' AS email, 25 AS age FROM DUAL) s
ON (t.username = s.username)
WHEN MATCHED THEN
    UPDATE SET t.email = s.email, t.age = s.age
WHEN NOT MATCHED THEN
    INSERT (id, username, email, age)
    VALUES (seq_users.NEXTVAL, s.username, s.email, s.age);

```

MERGE with DELETE clause (4.0+)
```sql
MERGE INTO users t
USING new_users s ON (t.username = s.username)
WHEN MATCHED THEN
    UPDATE SET t.email = s.email, t.age = s.age
    DELETE WHERE t.status = 0
WHEN NOT MATCHED THEN
    INSERT (id, username, email, age)
    VALUES (seq_users.NEXTVAL, s.username, s.email, s.age);

```

MERGE from subquery
```sql
MERGE INTO user_stats t
USING (
    SELECT user_id, COUNT(*) AS cnt, SUM(amount) AS total
    FROM orders GROUP BY user_id
) s ON (t.user_id = s.user_id)
WHEN MATCHED THEN
    UPDATE SET t.order_count = s.cnt, t.total_amount = s.total
WHEN NOT MATCHED THEN
    INSERT (user_id, order_count, total_amount) VALUES (s.user_id, s.cnt, s.total);

```

Limitations:
MySQL mode: same as MySQL (ON DUPLICATE KEY UPDATE, REPLACE, INSERT IGNORE)
Oracle mode: MERGE is the standard upsert pattern
Foreign keys are enforced during upsert operations
MERGE in Oracle mode is fully supported in 4.0+
