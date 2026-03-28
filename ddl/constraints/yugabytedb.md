# YugabyteDB: 约束

> 参考资料:
> - [YugabyteDB YSQL Reference](https://docs.yugabyte.com/stable/api/ysql/)
> - [YugabyteDB PostgreSQL Compatibility](https://docs.yugabyte.com/stable/explore/ysql-language-features/)

**引擎定位**: 分布式 SQL 数据库，兼容 PostgreSQL 协议。基于 DocDB (RocksDB) 存储，Raft 共识。

## PRIMARY KEY


```sql
CREATE TABLE users (
    id       BIGSERIAL PRIMARY KEY,            -- hash-sharded by default
    username VARCHAR(100) NOT NULL
);

```

Composite primary key
```sql
CREATE TABLE order_items (
    order_id BIGINT NOT NULL,
    item_id  INT NOT NULL,
    PRIMARY KEY (order_id, item_id)
);

```

Hash-sharded primary key (default)
```sql
CREATE TABLE hash_table (
    id   BIGINT,
    data TEXT,
    PRIMARY KEY (id HASH)
);

```

Range-sharded primary key
```sql
CREATE TABLE range_table (
    id   BIGINT,
    data TEXT,
    PRIMARY KEY (id ASC)
);

```

Composite: hash + range
```sql
CREATE TABLE composite_pk (
    tenant_id BIGINT,
    id        BIGINT,
    data      TEXT,
    PRIMARY KEY ((tenant_id) HASH, id ASC)
);

```

## UNIQUE


```sql
CREATE TABLE users2 (
    id       BIGSERIAL PRIMARY KEY,
    email    VARCHAR(255) UNIQUE,
    username VARCHAR(100),
    CONSTRAINT uq_username UNIQUE (username)
);

```

Partial unique
```sql
ALTER TABLE users ADD CONSTRAINT uq_active_email
    UNIQUE (email) WHERE (status = 1);

```

## NOT NULL


```sql
CREATE TABLE orders (
    id     BIGSERIAL PRIMARY KEY,
    amount DECIMAL(10,2) NOT NULL,
    status INT NOT NULL DEFAULT 1
);

ALTER TABLE users ALTER COLUMN email SET NOT NULL;
ALTER TABLE users ALTER COLUMN phone DROP NOT NULL;

```

## CHECK


```sql
CREATE TABLE accounts (
    id      BIGSERIAL PRIMARY KEY,
    balance DECIMAL(10,2) CHECK (balance >= 0),
    age     INT,
    CONSTRAINT chk_age CHECK (age >= 0 AND age <= 150)
);

ALTER TABLE users ADD CONSTRAINT chk_status CHECK (status IN (0, 1, 2));

```

## FOREIGN KEY


```sql
CREATE TABLE orders2 (
    id      BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES users (id),
    amount  DECIMAL(10,2)
);

```

Named foreign key with actions
```sql
ALTER TABLE orders ADD CONSTRAINT fk_orders_user
    FOREIGN KEY (user_id) REFERENCES users (id)
    ON DELETE CASCADE
    ON UPDATE CASCADE;

```

ON DELETE: CASCADE, SET NULL, SET DEFAULT, RESTRICT, NO ACTION
ON UPDATE: CASCADE, SET NULL, SET DEFAULT, RESTRICT, NO ACTION

NOT VALID constraint (add without checking existing data)
```sql
ALTER TABLE orders ADD CONSTRAINT fk_orders_user
    FOREIGN KEY (user_id) REFERENCES users (id) NOT VALID;
ALTER TABLE orders VALIDATE CONSTRAINT fk_orders_user;

```

## DEFAULT


```sql
CREATE TABLE defaults_example (
    id         BIGSERIAL PRIMARY KEY,
    status     INT DEFAULT 1,
    created_at TIMESTAMPTZ DEFAULT now(),
    uuid_col   UUID DEFAULT gen_random_uuid()
);

ALTER TABLE users ALTER COLUMN status SET DEFAULT 0;
ALTER TABLE users ALTER COLUMN status DROP DEFAULT;

```

## EXCLUDE (PostgreSQL-compatible)


Exclusion constraints are supported (requires btree_gist extension)
```sql
CREATE EXTENSION IF NOT EXISTS btree_gist;
CREATE TABLE reservations (
    id       BIGSERIAL PRIMARY KEY,
    room_id  INT,
    during   TSTZRANGE,
    EXCLUDE USING GIST (room_id WITH =, during WITH &&)
);

```

## Drop constraints


```sql
ALTER TABLE users DROP CONSTRAINT chk_age;
ALTER TABLE orders DROP CONSTRAINT fk_orders_user;
ALTER TABLE users DROP CONSTRAINT IF EXISTS uq_email;

```

View constraints
```sql
SELECT * FROM information_schema.table_constraints WHERE table_name = 'users';
SELECT * FROM information_schema.key_column_usage WHERE table_name = 'users';

```

Note: All constraints are enforced across the distributed cluster
Note: Foreign key checks may involve cross-node communication (slight latency)
Note: Unique constraints use distributed secondary indexes
Note: EXCLUDE constraints are supported (unlike CockroachDB)
Note: Constraint validation is distributed across all tablets
