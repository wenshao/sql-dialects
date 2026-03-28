# YugabyteDB: ALTER TABLE

> 参考资料:
> - [YugabyteDB YSQL Reference](https://docs.yugabyte.com/stable/api/ysql/)
> - [YugabyteDB PostgreSQL Compatibility](https://docs.yugabyte.com/stable/explore/ysql-language-features/)

**引擎定位**: 分布式 SQL 数据库，兼容 PostgreSQL 协议。基于 DocDB (RocksDB) 存储，Raft 共识。

```sql
ALTER TABLE users ADD COLUMN phone VARCHAR(20);
ALTER TABLE users ADD COLUMN IF NOT EXISTS phone VARCHAR(20);

```

Add column with default and constraint
```sql
ALTER TABLE users ADD COLUMN status INT NOT NULL DEFAULT 1;

```

Drop column
```sql
ALTER TABLE users DROP COLUMN phone;
ALTER TABLE users DROP COLUMN IF EXISTS phone;

```

Rename column
```sql
ALTER TABLE users RENAME COLUMN username TO user_name;

```

Change column type
```sql
ALTER TABLE users ALTER COLUMN age TYPE BIGINT;
ALTER TABLE users ALTER COLUMN bio TYPE VARCHAR(500);

```

Set/drop default
```sql
ALTER TABLE users ALTER COLUMN status SET DEFAULT 0;
ALTER TABLE users ALTER COLUMN status DROP DEFAULT;

```

Set/drop NOT NULL
```sql
ALTER TABLE users ALTER COLUMN email SET NOT NULL;
ALTER TABLE users ALTER COLUMN phone DROP NOT NULL;

```

Rename table
```sql
ALTER TABLE users RENAME TO members;

```

Add constraints
```sql
ALTER TABLE orders ADD CONSTRAINT fk_orders_user
    FOREIGN KEY (user_id) REFERENCES users (id);
ALTER TABLE users ADD CONSTRAINT chk_age CHECK (age >= 0 AND age <= 150);
ALTER TABLE users ADD CONSTRAINT uq_email UNIQUE (email);

```

Drop constraint
```sql
ALTER TABLE orders DROP CONSTRAINT fk_orders_user;
ALTER TABLE users DROP CONSTRAINT IF EXISTS chk_age;

```

Validate constraint
```sql
ALTER TABLE orders ADD CONSTRAINT fk_orders_user
    FOREIGN KEY (user_id) REFERENCES users (id) NOT VALID;
ALTER TABLE orders VALIDATE CONSTRAINT fk_orders_user;

```

Set schema
```sql
ALTER TABLE users SET SCHEMA myschema;

```

Set tablespace (for geo-partitioning)
```sql
ALTER TABLE users SET TABLESPACE us_east_ts;

```

Set tablegroup
```sql
ALTER TABLE users SET TABLEGROUP order_group;
ALTER TABLE users SET TABLEGROUP NONE;

```

Attach/detach partitions
```sql
ALTER TABLE geo_orders ATTACH PARTITION geo_orders_asia
    FOR VALUES IN ('asia');
ALTER TABLE geo_orders DETACH PARTITION geo_orders_asia;

```

Tablet splitting (YugabyteDB-specific)
Manual tablet split via yb-admin CLI:
yb-admin split_tablet <tablet_id>

Enable/disable row-level security
```sql
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE users DISABLE ROW LEVEL SECURITY;

```

Set storage parameters
```sql
ALTER TABLE users SET (parallel_workers = 4);

```

Note: ALTER TABLE operations are online but may be slower than PostgreSQL
Note: Changing primary key requires table recreation
Note: Supports most PostgreSQL ALTER TABLE operations
Note: Tablespace changes trigger data redistribution across nodes
Note: Tablegroup changes require moving data between tablets
