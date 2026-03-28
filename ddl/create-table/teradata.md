# Teradata: CREATE TABLE

> 参考资料:
> - [Teradata SQL Reference](https://docs.teradata.com/r/Teradata-VantageTM-SQL-Functions-Expressions-and-Predicates)
> - [Teradata Database Documentation](https://docs.teradata.com/)


MULTISET table (allows duplicate rows, default)
```sql
CREATE MULTISET TABLE users (
    id         INTEGER       NOT NULL,
    username   VARCHAR(64)   NOT NULL,
    email      VARCHAR(255)  NOT NULL,
    age        INTEGER,
    balance    DECIMAL(10,2) DEFAULT 0.00,
    bio        CLOB,
    created_at TIMESTAMP(0)  NOT NULL DEFAULT CURRENT_TIMESTAMP(0),
    updated_at TIMESTAMP(0)  NOT NULL DEFAULT CURRENT_TIMESTAMP(0)
)
PRIMARY INDEX (id);
```


SET table (no duplicate rows allowed)
```sql
CREATE SET TABLE unique_users (
    id         INTEGER       NOT NULL,
    username   VARCHAR(64)   NOT NULL,
    email      VARCHAR(255)  NOT NULL
)
UNIQUE PRIMARY INDEX (id);
```


PRIMARY INDEX determines data distribution across AMPs
UNIQUE PRIMARY INDEX (UPI): guarantees uniqueness, one-AMP access
NON-UNIQUE PRIMARY INDEX (NUPI): allows duplicates, may hash to same AMP
```sql
CREATE TABLE orders (
    order_id   INTEGER       NOT NULL,
    user_id    INTEGER       NOT NULL,
    amount     DECIMAL(12,2),
    created_at TIMESTAMP(0)  DEFAULT CURRENT_TIMESTAMP(0)
)
PRIMARY INDEX (user_id);  -- distribute by user_id for co-located joins
```


Partitioned Primary Index (PPI)
```sql
CREATE TABLE events (
    event_id   INTEGER       NOT NULL,
    event_date DATE          NOT NULL,
    event_type VARCHAR(50),
    payload    VARCHAR(10000)
)
PRIMARY INDEX (event_id)
PARTITION BY RANGE_N(event_date BETWEEN DATE '2020-01-01' AND DATE '2030-12-31' EACH INTERVAL '1' MONTH);
```


No Primary Index (NoPI) table -- for staging/loading
```sql
CREATE MULTISET TABLE staging_data (
    col1 VARCHAR(100),
    col2 VARCHAR(100)
)
NO PRIMARY INDEX;
```


VOLATILE table (session-scoped temporary)
```sql
CREATE VOLATILE TABLE temp_results (
    id    INTEGER,
    value DECIMAL(10,2)
)
PRIMARY INDEX (id)
ON COMMIT PRESERVE ROWS;
```


GLOBAL TEMPORARY table (definition persists, data is session-scoped)
```sql
CREATE GLOBAL TEMPORARY TABLE gt_temp (
    id    INTEGER,
    value DECIMAL(10,2)
)
PRIMARY INDEX (id)
ON COMMIT PRESERVE ROWS;
```


Column-partitioned table (Teradata 14.10+)
```sql
CREATE TABLE large_data (
    id     INTEGER NOT NULL,
    col1   VARCHAR(100),
    col2   DECIMAL(10,2),
    col3   DATE
)
PRIMARY INDEX (id)
PARTITION BY COLUMN;
```


Temporal table (bi-temporal)
```sql
CREATE TABLE employees (
    emp_id       INTEGER NOT NULL,
    emp_name     VARCHAR(100),
    department   VARCHAR(50),
    valid_period PERIOD(DATE) NOT NULL AS VALIDTIME,
    tx_period    PERIOD(TIMESTAMP(6)) NOT NULL AS TRANSACTIONTIME
)
PRIMARY INDEX (emp_id);
```


WITH DATA / WITH NO DATA (CTAS)
```sql
CREATE TABLE users_copy AS (
    SELECT * FROM users
) WITH DATA
PRIMARY INDEX (id);

CREATE TABLE users_empty AS (
    SELECT * FROM users WHERE 1=0
) WITH NO DATA
PRIMARY INDEX (id);
```
