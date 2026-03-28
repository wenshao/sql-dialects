# OceanBase: 索引

> 参考资料:
> - [OceanBase SQL Reference (MySQL Mode)](https://www.oceanbase.com/docs/common-oceanbase-database-cn)
> - [OceanBase SQL Reference (Oracle Mode)](https://www.oceanbase.com/docs/common-oceanbase-database-cn)

**引擎定位**: 分布式关系型数据库，兼容 MySQL/Oracle 双模式。基于 LSM-Tree 存储，Paxos 共识。

## MySQL Mode


Basic indexes (same as MySQL)
```sql
CREATE INDEX idx_age ON users (age);
CREATE UNIQUE INDEX uk_email ON users (email);
CREATE INDEX idx_city_age ON users (city, age);

```

Prefix index (same as MySQL)
```sql
CREATE INDEX idx_email_prefix ON users (email(20));

```

Descending index
```sql
CREATE INDEX idx_created_desc ON orders (user_id ASC, created_at DESC);

```

Fulltext index (4.0+)
```sql
CREATE FULLTEXT INDEX idx_ft_bio ON users (bio);

```

Global vs Local index on partitioned tables
Local index: each partition has its own index (default)
```sql
CREATE INDEX idx_local ON logs (message) LOCAL;
```

Global index: single index spanning all partitions
```sql
CREATE INDEX idx_global ON logs (user_id) GLOBAL;
```

Global index avoids scanning all partitions for non-partition-key queries

Spatial index (4.0+, MySQL mode)
```sql
CREATE SPATIAL INDEX idx_location ON places (geo_point);

```

Function-based index (4.0+)
```sql
CREATE INDEX idx_upper_name ON users ((UPPER(username)));

```

Index on partitioned table with specific partition storage
```sql
CREATE INDEX idx_status ON logs (status)
    GLOBAL PARTITION BY HASH(status) PARTITIONS 4;

```

Online index creation (non-blocking)
```sql
ALTER TABLE users ADD INDEX idx_city (city);

```

Drop index
```sql
DROP INDEX idx_age ON users;

```

View indexes
```sql
SHOW INDEX FROM users;

```

## Oracle Mode


Standard index
```sql
CREATE INDEX idx_age ON users (age);

```

Unique index
```sql
CREATE UNIQUE INDEX uk_email ON users (email);

```

Composite index
```sql
CREATE INDEX idx_city_age ON users (city, age);

```

Function-based index
```sql
CREATE INDEX idx_upper_name ON users (UPPER(username));

```

Local index (partition-level)
```sql
CREATE INDEX idx_local ON events (event_date) LOCAL;

```

Global index
```sql
CREATE INDEX idx_global ON events (id) GLOBAL;

```

Reverse key index (Oracle compatible)
Reverses bytes of indexed column to distribute sequential values
```sql
CREATE INDEX idx_id_rev ON orders (id) REVERSE;

```

Drop index (Oracle syntax)
```sql
DROP INDEX idx_age;

```

Rebuild index
```sql
ALTER INDEX idx_age REBUILD;

```

Limitations:
HASH index type (USING HASH) not supported
Invisible indexes supported in 4.0+ (MySQL mode)
Index creation is online but performance impact during creation
Global indexes have higher maintenance cost but better query performance
