# IBM Db2: CREATE TABLE

> 参考资料:
> - [Db2 SQL Reference](https://www.ibm.com/docs/en/db2/11.5?topic=sql)
> - [Db2 Built-in Functions](https://www.ibm.com/docs/en/db2/11.5?topic=functions-built-in)


```sql
CREATE TABLE users (
    id         BIGINT        NOT NULL GENERATED ALWAYS AS IDENTITY (START WITH 1 INCREMENT BY 1),
    username   VARCHAR(64)   NOT NULL,
    email      VARCHAR(255)  NOT NULL,
    age        INTEGER,
    balance    DECIMAL(10,2) DEFAULT 0.00,
    bio        CLOB,
    created_at TIMESTAMP     NOT NULL DEFAULT CURRENT TIMESTAMP,
    updated_at TIMESTAMP     NOT NULL DEFAULT CURRENT TIMESTAMP,
    PRIMARY KEY (id),
    CONSTRAINT uk_username UNIQUE (username),
    CONSTRAINT uk_email UNIQUE (email)
);
```

## ORGANIZE BY ROW (default, OLTP workloads)

```sql
CREATE TABLE orders (
    order_id   BIGINT NOT NULL GENERATED ALWAYS AS IDENTITY,
    user_id    BIGINT NOT NULL,
    amount     DECIMAL(12,2),
    created_at TIMESTAMP DEFAULT CURRENT TIMESTAMP,
    PRIMARY KEY (order_id)
) ORGANIZE BY ROW;
```

## ORGANIZE BY COLUMN (analytics, columnar storage, BLU Acceleration)

```sql
CREATE TABLE events (
    event_id   BIGINT NOT NULL GENERATED ALWAYS AS IDENTITY,
    event_date DATE,
    event_type VARCHAR(50),
    payload    CLOB
) ORGANIZE BY COLUMN;
```

## Tablespace placement

```sql
CREATE TABLE large_data (
    id    BIGINT NOT NULL GENERATED ALWAYS AS IDENTITY,
    data  VARCHAR(1000)
) IN userspace1 INDEX IN indexspace1 LONG IN lobspace1;
```

## Partitioned table (range partitioning)

```sql
CREATE TABLE sales (
    sale_id    BIGINT NOT NULL,
    sale_date  DATE NOT NULL,
    amount     DECIMAL(12,2),
    region     VARCHAR(50)
)
PARTITION BY RANGE (sale_date) (
    STARTING '2020-01-01' ENDING '2020-12-31',
    STARTING '2021-01-01' ENDING '2021-12-31',
    STARTING '2022-01-01' ENDING '2022-12-31',
    STARTING '2023-01-01' ENDING '2023-12-31'
);
```

## Multi-dimensional clustering (MDC)

```sql
CREATE TABLE mdc_sales (
    sale_id    BIGINT NOT NULL,
    sale_date  DATE NOT NULL,
    region     VARCHAR(50),
    amount     DECIMAL(12,2)
) ORGANIZE BY DIMENSIONS (sale_date, region);
```

## Temporary table (declared, session-scoped)

```sql
DECLARE GLOBAL TEMPORARY TABLE session.temp_results (
    id    BIGINT,
    value DECIMAL(10,2)
) ON COMMIT PRESERVE ROWS NOT LOGGED;
```

## Created global temporary table (definition persists)

```sql
CREATE GLOBAL TEMPORARY TABLE gt_temp (
    id    BIGINT,
    value DECIMAL(10,2)
) ON COMMIT PRESERVE ROWS;
```

## Materialized Query Table (MQT)

```sql
CREATE TABLE city_stats AS (
    SELECT city, COUNT(*) AS cnt, AVG(age) AS avg_age
    FROM users
    GROUP BY city
) DATA INITIALLY DEFERRED REFRESH DEFERRED;
REFRESH TABLE city_stats;
```

## CTAS

```sql
CREATE TABLE users_copy AS (
    SELECT * FROM users
) WITH DATA;
```

## IMPLICITLY HIDDEN columns

```sql
CREATE TABLE audit_data (
    id      BIGINT NOT NULL GENERATED ALWAYS AS IDENTITY,
    name    VARCHAR(100),
    secret  VARCHAR(100) IMPLICITLY HIDDEN
);
```

## Generated column

```sql
CREATE TABLE products (
    price    DECIMAL(10,2),
    tax_rate DECIMAL(4,2),
    total    DECIMAL(10,2) GENERATED ALWAYS AS (price * (1 + tax_rate))
);
```
