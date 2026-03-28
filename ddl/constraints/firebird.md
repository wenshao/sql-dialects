# Firebird: Constraints

> 参考资料:
> - [Firebird SQL Reference](https://firebirdsql.org/en/reference-manuals/)
> - [Firebird Release Notes](https://firebirdsql.org/file/documentation/release_notes/html/en/4_0/rlsnotes40.html)


## PRIMARY KEY

```sql
CREATE TABLE users (
    id BIGINT NOT NULL PRIMARY KEY
);
CREATE TABLE order_items (
    order_id BIGINT NOT NULL,
    item_id  BIGINT NOT NULL,
    PRIMARY KEY (order_id, item_id)
);
```

## Named primary key

```sql
CREATE TABLE products (
    product_id INTEGER NOT NULL,
    CONSTRAINT pk_products PRIMARY KEY (product_id)
);
```

## UNIQUE

```sql
ALTER TABLE users ADD CONSTRAINT uk_email UNIQUE (email);
```

## FOREIGN KEY

```sql
ALTER TABLE orders ADD CONSTRAINT fk_orders_user
    FOREIGN KEY (user_id) REFERENCES users (id)
    ON DELETE CASCADE
    ON UPDATE CASCADE;
```

NOT NULL
Must be defined at CREATE TABLE or via domain
ALTER TABLE cannot directly add NOT NULL to existing column in older versions
2.0+: use ALTER TABLE ... ALTER ... NOT NULL

```sql
ALTER TABLE users ALTER email SET NOT NULL;
ALTER TABLE users ALTER email DROP NOT NULL;
```

## DEFAULT

```sql
ALTER TABLE users ALTER status SET DEFAULT 1;
ALTER TABLE users ALTER status DROP DEFAULT;
```

## CHECK constraint (table level)

```sql
ALTER TABLE users ADD CONSTRAINT chk_age CHECK (age >= 0 AND age <= 200);
ALTER TABLE events ADD CONSTRAINT chk_dates CHECK (end_date > start_date);
```

## CHECK with domain (reusable constraints)

```sql
CREATE DOMAIN d_positive_amount AS DECIMAL(12,2)
    CHECK (VALUE > 0);
CREATE TABLE invoices (
    id     INTEGER NOT NULL PRIMARY KEY,
    amount d_positive_amount
);
```

## Column-level constraints

```sql
CREATE TABLE accounts (
    id       INTEGER NOT NULL PRIMARY KEY,
    balance  DECIMAL(12,2) DEFAULT 0.00 NOT NULL CHECK (balance >= 0),
    email    VARCHAR(255) NOT NULL UNIQUE,
    owner_id INTEGER REFERENCES users (id) ON DELETE SET NULL
);
```

## Drop constraint

```sql
ALTER TABLE users DROP CONSTRAINT uk_email;
ALTER TABLE orders DROP CONSTRAINT fk_orders_user;
ALTER TABLE users DROP CONSTRAINT chk_age;
```

Using index for constraint
Firebird automatically creates indexes for PK, UNIQUE, and FK (referencing side)
View constraints

```sql
SELECT * FROM RDB$RELATION_CONSTRAINTS WHERE RDB$RELATION_NAME = 'USERS';
SELECT * FROM RDB$CHECK_CONSTRAINTS WHERE RDB$CONSTRAINT_NAME = 'CHK_AGE';
SELECT * FROM RDB$REF_CONSTRAINTS WHERE RDB$CONSTRAINT_NAME = 'FK_ORDERS_USER';
```

Note: FK referencing columns should be indexed manually for DELETE performance
Note: constraint names are auto-generated if not specified (INTEG_xxx)
Note: domain-level CHECK constraints can be modified with ALTER DOMAIN
