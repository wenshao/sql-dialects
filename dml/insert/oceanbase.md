# OceanBase: INSERT

> 参考资料:
> - [OceanBase SQL Reference (MySQL Mode)](https://www.oceanbase.com/docs/common-oceanbase-database-cn)
> - [OceanBase SQL Reference (Oracle Mode)](https://www.oceanbase.com/docs/common-oceanbase-database-cn)

**引擎定位**: 分布式关系型数据库，兼容 MySQL/Oracle 双模式。基于 LSM-Tree 存储，Paxos 共识。

## MySQL Mode (same as MySQL with minor differences)


Basic insert
```sql
INSERT INTO users (username, email, age) VALUES ('alice', 'alice@example.com', 25);

```

Multi-row insert
```sql
INSERT INTO users (username, email, age) VALUES
    ('alice', 'alice@example.com', 25),
    ('bob', 'bob@example.com', 30),
    ('charlie', 'charlie@example.com', 35);

```

INSERT IGNORE
```sql
INSERT IGNORE INTO users (username, email, age) VALUES ('alice', 'alice@example.com', 25);

```

INSERT ... SELECT
```sql
INSERT INTO users_archive (username, email, age)
SELECT username, email, age FROM users WHERE age > 60;

```

INSERT ... ON DUPLICATE KEY UPDATE
```sql
INSERT INTO users (username, email, age) VALUES ('alice', 'alice@example.com', 25)
ON DUPLICATE KEY UPDATE email = VALUES(email), age = VALUES(age);

```

SET syntax
```sql
INSERT INTO users SET username = 'alice', email = 'alice@example.com', age = 25;

```

LAST_INSERT_ID()
```sql
INSERT INTO users (username, email) VALUES ('alice', 'alice@example.com');
SELECT LAST_INSERT_ID();

```

REPLACE INTO (same as MySQL)
```sql
REPLACE INTO users (username, email, age) VALUES ('alice', 'alice@example.com', 25);

```

## Oracle Mode


Basic insert
```sql
INSERT INTO users (id, username, email, age)
VALUES (seq_users.NEXTVAL, 'alice', 'alice@example.com', 25);

```

Multi-row insert (Oracle INSERT ALL)
```sql
INSERT ALL
    INTO users (id, username, email) VALUES (seq_users.NEXTVAL, 'alice', 'alice@example.com')
    INTO users (id, username, email) VALUES (seq_users.NEXTVAL, 'bob', 'bob@example.com')
SELECT * FROM DUAL;

```

Conditional insert (Oracle INSERT ALL with WHEN)
```sql
INSERT ALL
    WHEN age < 18 THEN INTO minor_users (id, username) VALUES (id, username)
    WHEN age >= 18 THEN INTO adult_users (id, username) VALUES (id, username)
SELECT id, username, age FROM temp_users;

```

INSERT ... SELECT (Oracle mode)
```sql
INSERT INTO users_archive (id, username, email, age)
SELECT seq_archive.NEXTVAL, username, email, age FROM users WHERE age > 60;

```

INSERT with RETURNING (Oracle mode, 4.0+)
Note: limited support compared to full Oracle
```sql
INSERT INTO users (id, username, email)
VALUES (seq_users.NEXTVAL, 'alice', 'alice@example.com')
RETURNING id INTO :new_id;

```

Hints for insert performance
```sql
INSERT /*+ ENABLE_PARALLEL_DML PARALLEL(4) */ INTO target_table
SELECT * FROM source_table;

```

Limitations:
MySQL mode: mostly identical to MySQL
Oracle mode: INSERT ALL syntax supported
Large batch inserts should consider partitioned tables for performance
Transaction size limits may apply for very large inserts
