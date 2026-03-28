# IBM Db2: Constraints

> 参考资料:
> - [Db2 SQL Reference](https://www.ibm.com/docs/en/db2/11.5?topic=sql)
> - [Db2 Built-in Functions](https://www.ibm.com/docs/en/db2/11.5?topic=functions-built-in)
> - PRIMARY KEY

```sql
CREATE TABLE users (
    id BIGINT NOT NULL GENERATED ALWAYS AS IDENTITY PRIMARY KEY
);
CREATE TABLE order_items (
    order_id BIGINT NOT NULL,
    item_id  BIGINT NOT NULL,
    PRIMARY KEY (order_id, item_id)
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
    ON UPDATE RESTRICT;
```

## NOT NULL

```sql
ALTER TABLE users ALTER COLUMN email SET NOT NULL;
ALTER TABLE users ALTER COLUMN email DROP NOT NULL;
```

## DEFAULT

```sql
ALTER TABLE users ALTER COLUMN status SET DEFAULT 1;
ALTER TABLE users ALTER COLUMN status DROP DEFAULT;
```

## CHECK

```sql
ALTER TABLE users ADD CONSTRAINT chk_age CHECK (age >= 0 AND age <= 200);
ALTER TABLE events ADD CONSTRAINT chk_dates CHECK (end_date > start_date);
```

## Informational constraints (not enforced, used by optimizer)

```sql
ALTER TABLE users ADD CONSTRAINT uk_phone UNIQUE (phone) NOT ENFORCED;
ALTER TABLE orders ADD CONSTRAINT fk_user
    FOREIGN KEY (user_id) REFERENCES users (id)
    NOT ENFORCED
    ENABLE QUERY OPTIMIZATION;
```

## Functional dependency (for query optimization)

```sql
ALTER TABLE users ADD CONSTRAINT fd_city_state
    CHECK (city DETERMINED BY state) NOT ENFORCED;
```

## Drop constraint

```sql
ALTER TABLE users DROP CONSTRAINT uk_email;
ALTER TABLE users DROP PRIMARY KEY;
ALTER TABLE users DROP UNIQUE uk_email;
ALTER TABLE users DROP FOREIGN KEY fk_orders_user;
ALTER TABLE users DROP CHECK chk_age;
```

## View constraints

```sql
SELECT * FROM SYSCAT.TABCONST WHERE TABNAME = 'USERS';
SELECT * FROM SYSCAT.REFERENCES WHERE TABNAME = 'ORDERS';
SELECT * FROM SYSCAT.CHECKS WHERE TABNAME = 'USERS';
SELECT * FROM SYSCAT.KEYCOLUSE WHERE CONSTNAME = 'UK_EMAIL';
```

## Set integrity (after load or import, check pending constraints)

```sql
SET INTEGRITY FOR users IMMEDIATE CHECKED;
SET INTEGRITY FOR users OFF;
```
