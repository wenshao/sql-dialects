# SAP HANA: Constraints

> 参考资料:
> - [SAP HANA SQL Reference](https://help.sap.com/docs/SAP_HANA_PLATFORM/4fe29514fd584807ac9f2a04f6754767/)
> - [SAP HANA SQLScript Reference](https://help.sap.com/docs/SAP_HANA_PLATFORM/de2486ee947e43e684d39702027f8a94/)
> - PRIMARY KEY

```sql
CREATE COLUMN TABLE users (
    id BIGINT NOT NULL GENERATED ALWAYS AS IDENTITY,
    PRIMARY KEY (id)
);
CREATE COLUMN TABLE order_items (
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
    ON UPDATE CASCADE;
```

## NOT NULL

Must be defined at CREATE TABLE or via ALTER TABLE column redefinition

```sql
ALTER TABLE users ALTER (email NVARCHAR(255) NOT NULL);
ALTER TABLE users ALTER (email NVARCHAR(255) NULL);
```

## DEFAULT

```sql
ALTER TABLE users ALTER (status INTEGER DEFAULT 1);
ALTER TABLE users ALTER (status INTEGER DEFAULT NULL);
```

## CHECK

```sql
ALTER TABLE users ADD CONSTRAINT chk_age CHECK (age >= 0 AND age <= 200);
ALTER TABLE events ADD CONSTRAINT chk_dates CHECK (end_date > start_date);
```

## Multiple constraints on creation

```sql
CREATE COLUMN TABLE products (
    product_id BIGINT NOT NULL,
    name       NVARCHAR(200) NOT NULL,
    price      DECIMAL(10,2) CHECK (price > 0),
    quantity   INTEGER CHECK (quantity >= 0),
    PRIMARY KEY (product_id)
);
```

## Drop constraint

```sql
ALTER TABLE users DROP CONSTRAINT uk_email;
ALTER TABLE orders DROP CONSTRAINT fk_orders_user;
```

Enable / disable constraint enforcement
Note: SAP HANA enforces constraints by default
Foreign keys can be created as NOT ENFORCED for performance

```sql
ALTER TABLE orders ADD CONSTRAINT fk_user
    FOREIGN KEY (user_id) REFERENCES users (id)
    NOT ENFORCED;
```

## Validate foreign key

```sql
ALTER TABLE orders VALIDATE CONSTRAINT fk_user;
```

## View constraints

```sql
SELECT * FROM CONSTRAINTS WHERE TABLE_NAME = 'USERS';
SELECT * FROM REFERENTIAL_CONSTRAINTS WHERE TABLE_NAME = 'ORDERS';
```

## System-versioned temporal constraint (PERIOD)

```sql
ALTER TABLE employees ADD (
    valid_from TIMESTAMP GENERATED ALWAYS AS ROW START,
    valid_to   TIMESTAMP GENERATED ALWAYS AS ROW END,
    PERIOD FOR SYSTEM_TIME (valid_from, valid_to)
);
```
