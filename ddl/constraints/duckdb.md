# DuckDB: 约束

> 参考资料:
> - [DuckDB - SQL Reference](https://duckdb.org/docs/sql/introduction)
> - [DuckDB - Functions](https://duckdb.org/docs/sql/functions/overview)
> - [DuckDB - Data Types](https://duckdb.org/docs/sql/data_types/overview)

**引擎定位**: 嵌入式 OLAP 分析引擎，类似 SQLite 的定位。列式存储 + 向量化执行，PostgreSQL 兼容语法。

```sql
CREATE TABLE users (
    id BIGINT PRIMARY KEY
);
```

Composite primary key
```sql
CREATE TABLE order_items (
    order_id BIGINT NOT NULL,
    item_id  BIGINT NOT NULL,
    PRIMARY KEY (order_id, item_id)
);

```

UNIQUE
```sql
CREATE TABLE users (
    id    BIGINT PRIMARY KEY,
    email VARCHAR UNIQUE
);
```

Named unique constraint
```sql
CREATE TABLE users (
    id    BIGINT,
    email VARCHAR,
    UNIQUE (email)
);

```

NOT NULL
```sql
CREATE TABLE users (
    id       BIGINT NOT NULL,
    username VARCHAR NOT NULL,
    email    VARCHAR NOT NULL
);

```

DEFAULT
```sql
CREATE TABLE users (
    id         BIGINT PRIMARY KEY,
    status     INTEGER DEFAULT 1,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

```

CHECK
```sql
CREATE TABLE users (
    id  BIGINT PRIMARY KEY,
    age INTEGER CHECK (age >= 0 AND age <= 200)
);
```

Named check constraint
```sql
CREATE TABLE users (
    id  BIGINT PRIMARY KEY,
    age INTEGER,
    CONSTRAINT chk_age CHECK (age >= 0 AND age <= 200)
);
```

Multi-column check
```sql
CREATE TABLE events (
    start_date DATE,
    end_date   DATE,
    CHECK (end_date > start_date)
);

```

FOREIGN KEY (v0.8+, enforced)
```sql
CREATE TABLE orders (
    id      BIGINT PRIMARY KEY,
    user_id BIGINT REFERENCES users(id)
);
```

With actions
```sql
CREATE TABLE orders (
    id      BIGINT PRIMARY KEY,
    user_id BIGINT,
    FOREIGN KEY (user_id) REFERENCES users(id)
        ON DELETE CASCADE
        ON UPDATE CASCADE
);
```

Actions: CASCADE / SET NULL / SET DEFAULT / RESTRICT / NO ACTION

Composite foreign key
```sql
CREATE TABLE order_details (
    order_id BIGINT,
    item_id  BIGINT,
    FOREIGN KEY (order_id, item_id) REFERENCES order_items(order_id, item_id)
);

```

Generated columns as constraints
```sql
CREATE TABLE products (
    price    DECIMAL(10,2) NOT NULL CHECK (price > 0),
    quantity INTEGER NOT NULL CHECK (quantity >= 0),
    total    DECIMAL(10,2) GENERATED ALWAYS AS (price * quantity)
);

```

Note: DuckDB enforces PRIMARY KEY, UNIQUE, NOT NULL, CHECK, and FOREIGN KEY
Note: No EXCLUDE constraints (PostgreSQL-specific)
Note: No DEFERRABLE constraints
Note: No NOT VALID / VALIDATE CONSTRAINT (constraints are always validated)
Note: ALTER TABLE ADD CONSTRAINT supported for UNIQUE constraints (v0.8+)
Note: Some constraint types can only be defined at table creation time
