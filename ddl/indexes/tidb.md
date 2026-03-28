# TiDB: 索引

> 参考资料:
> - [TiDB SQL Reference](https://docs.pingcap.com/tidb/stable/sql-statement-overview)
> - [TiDB - MySQL Compatibility](https://docs.pingcap.com/tidb/stable/mysql-compatibility)
> - [TiDB - Functions and Operators](https://docs.pingcap.com/tidb/stable/functions-and-operators-overview)

**引擎定位**: 分布式 HTAP 数据库，兼容 MySQL 协议。基于 TiKV 行存 + TiFlash 列存，Raft 共识。

```sql
CREATE INDEX idx_age ON users (age);
CREATE UNIQUE INDEX uk_email ON users (email);
CREATE INDEX idx_city_age ON users (city, age);

```

Clustered vs Non-Clustered primary key (5.0+)
Clustered: row data stored with PK (better for PK lookups)
Non-clustered: separate _tidb_rowid, PK is a unique index
```sql
CREATE TABLE t1 (id BIGINT PRIMARY KEY CLUSTERED);
CREATE TABLE t2 (id BIGINT PRIMARY KEY NONCLUSTERED);

```

Expression index (5.0+, similar to MySQL 8.0 functional index)
```sql
CREATE INDEX idx_upper_name ON users ((UPPER(username)));
CREATE INDEX idx_json_name ON users ((CAST(data->>'$.name' AS CHAR(64))));

```

Invisible index (same as MySQL 8.0)
```sql
CREATE INDEX idx_age ON users (age) INVISIBLE;
ALTER TABLE users ALTER INDEX idx_age VISIBLE;

```

Multi-valued index on JSON arrays (6.6+)
```sql
CREATE INDEX idx_tags ON events ((CAST(data->'$.tags' AS CHAR(64) ARRAY)));

```

Prefix index (same as MySQL)
```sql
CREATE INDEX idx_email_prefix ON users (email(20));

```

Composite index with descending order
```sql
CREATE INDEX idx_created_desc ON orders (user_id ASC, created_at DESC);

```

Add index (online, non-blocking)
TiDB adds indexes asynchronously in the background
Use ADMIN SHOW DDL JOBS to monitor progress
```sql
ALTER TABLE users ADD INDEX idx_city (city);

```

Drop index
```sql
DROP INDEX idx_age ON users;
ALTER TABLE users DROP INDEX idx_age;

```

View index info
```sql
SHOW INDEX FROM users;
SHOW CREATE TABLE users;

```

Limitations:
FULLTEXT index: NOT supported
SPATIAL index: NOT supported
HASH index: NOT supported (USING HASH is parsed but ignored)
Index hints (USE INDEX, FORCE INDEX, IGNORE INDEX) are supported
Max key length: 3072 bytes (same as MySQL with utf8mb4)
Index creation is online but may consume significant I/O on large tables
The optimizer may choose different indexes than MySQL for the same query

TiDB-specific optimizer hints for index selection
```sql
SELECT /*+ USE_INDEX(users, idx_age) */ * FROM users WHERE age > 25;
SELECT /*+ IGNORE_INDEX(users, idx_age) */ * FROM users WHERE age > 25;
SELECT /*+ USE_INDEX_MERGE(users, idx_age, idx_city) */ * FROM users
    WHERE age > 25 OR city = 'Beijing';

```

Index merge (5.4+): optimizer can combine multiple indexes
Enabled by default, controlled by tidb_enable_index_merge
