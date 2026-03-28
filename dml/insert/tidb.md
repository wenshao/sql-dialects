# TiDB: INSERT

> 参考资料:
> - [TiDB SQL Reference](https://docs.pingcap.com/tidb/stable/sql-statement-overview)
> - [TiDB - MySQL Compatibility](https://docs.pingcap.com/tidb/stable/mysql-compatibility)
> - [TiDB - Functions and Operators](https://docs.pingcap.com/tidb/stable/functions-and-operators-overview)

**引擎定位**: 分布式 HTAP 数据库，兼容 MySQL 协议。基于 TiKV 行存 + TiFlash 列存，Raft 共识。

```sql
INSERT INTO users (username, email, age) VALUES ('alice', 'alice@example.com', 25);

```

Multi-row insert (same as MySQL, but batch size affects TiKV transaction)
```sql
INSERT INTO users (username, email, age) VALUES
    ('alice', 'alice@example.com', 25),
    ('bob', 'bob@example.com', 30),
    ('charlie', 'charlie@example.com', 35);

```

INSERT IGNORE (same as MySQL)
```sql
INSERT IGNORE INTO users (username, email, age) VALUES ('alice', 'alice@example.com', 25);

```

INSERT ... SELECT (same as MySQL)
```sql
INSERT INTO users_archive (username, email, age)
SELECT username, email, age FROM users WHERE age > 60;

```

INSERT ... ON DUPLICATE KEY UPDATE (same as MySQL)
```sql
INSERT INTO users (username, email, age) VALUES ('alice', 'alice@example.com', 25)
ON DUPLICATE KEY UPDATE email = VALUES(email), age = VALUES(age);

```

AUTO_RANDOM: do NOT specify the AUTO_RANDOM column value
The value is automatically generated with randomized high bits
```sql
INSERT INTO users (username, email) VALUES ('alice', 'alice@example.com');
```

To explicitly set AUTO_RANDOM value (not recommended):
```sql
SET @@allow_auto_random_explicit_insert = ON;
INSERT INTO users (id, username, email) VALUES (12345, 'alice', 'alice@example.com');

```

LAST_INSERT_ID() works for AUTO_INCREMENT
For AUTO_RANDOM, use LAST_INSERT_ID() to get the generated value
```sql
INSERT INTO users (username, email) VALUES ('bob', 'bob@example.com');
SELECT LAST_INSERT_ID();

```

Batch insert performance considerations:
TiDB has a default transaction size limit (txn-total-size-limit, default 100MB)
For large inserts, use LOAD DATA or batch into smaller transactions

LOAD DATA (same syntax as MySQL, but behavior differs)
```sql
LOAD DATA LOCAL INFILE '/path/to/data.csv'
INTO TABLE users
FIELDS TERMINATED BY ','
LINES TERMINATED BY '\n'
(username, email, age);

```

TiDB Lightning: recommended for bulk data loading (external tool)
Much faster than INSERT or LOAD DATA for large datasets

SET syntax (same as MySQL)
```sql
INSERT INTO users SET username = 'alice', email = 'alice@example.com', age = 25;

```

Limitations:
Large transactions may hit txn-total-size-limit
Very large batch inserts should be split into smaller batches
INSERT ... SELECT across large datasets may cause OOM if not paginated
REPLACE INTO works but may cause issues with AUTO_RANDOM columns
