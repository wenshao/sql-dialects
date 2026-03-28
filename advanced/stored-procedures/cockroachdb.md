# CockroachDB: 存储过程

> 参考资料:
> - [CockroachDB - SQL Statements](https://www.cockroachlabs.com/docs/stable/sql-statements)
> - [CockroachDB - Functions and Operators](https://www.cockroachlabs.com/docs/stable/functions-and-operators)
> - [CockroachDB - Data Types](https://www.cockroachlabs.com/docs/stable/data-types)

**引擎定位**: 分布式 SQL 数据库，兼容 PostgreSQL 协议。基于 Pebble (RocksDB) 存储，Raft 共识，支持 Geo-Partitioning。

## User-defined functions (v22.2+)


Simple SQL function
```sql
CREATE OR REPLACE FUNCTION get_user(p_username VARCHAR)
RETURNS TABLE (id UUID, username VARCHAR, email VARCHAR, age INT)
AS $$
    SELECT id, username, email, age FROM users WHERE username = p_username;
$$ LANGUAGE sql;

SELECT * FROM get_user('alice');

```

PL/pgSQL function (v23.1+)
```sql
CREATE OR REPLACE FUNCTION get_user_count()
RETURNS INT AS $$
DECLARE
    v_count INT;
BEGIN
    SELECT COUNT(*) INTO v_count FROM users;
    RETURN v_count;
END;
$$ LANGUAGE plpgsql;

SELECT get_user_count();

```

Function with multiple return values
```sql
CREATE OR REPLACE FUNCTION get_stats(
    OUT min_age INT, OUT max_age INT, OUT avg_age NUMERIC
)
AS $$
    SELECT MIN(age), MAX(age), AVG(age) FROM users;
$$ LANGUAGE sql;

SELECT * FROM get_stats();

```

Function returning SETOF (multiple rows)
```sql
CREATE OR REPLACE FUNCTION active_users()
RETURNS SETOF users AS $$
    SELECT * FROM users WHERE status = 1;
$$ LANGUAGE sql;

SELECT * FROM active_users();

```

PL/pgSQL with exception handling (v23.1+)
```sql
CREATE OR REPLACE FUNCTION safe_divide(a NUMERIC, b NUMERIC)
RETURNS NUMERIC AS $$
BEGIN
    RETURN a / b;
EXCEPTION
    WHEN division_by_zero THEN
        RETURN NULL;
END;
$$ LANGUAGE plpgsql;

```

## Stored procedures (v23.2+)


Basic procedure
```sql
CREATE OR REPLACE PROCEDURE update_status(p_user_id UUID, p_status INT)
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE users SET status = p_status, updated_at = now()
    WHERE id = p_user_id;
END;
$$;

CALL update_status('550e8400-e29b-41d4-a716-446655440000', 1);

```

Procedure with transaction control
```sql
CREATE OR REPLACE PROCEDURE transfer(
    p_from UUID, p_to UUID, p_amount NUMERIC
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_balance NUMERIC;
BEGIN
    SELECT balance INTO v_balance FROM accounts WHERE id = p_from FOR UPDATE;

    IF v_balance < p_amount THEN
        RAISE EXCEPTION 'Insufficient balance: % < %', v_balance, p_amount;
    END IF;

    UPDATE accounts SET balance = balance - p_amount WHERE id = p_from;
    UPDATE accounts SET balance = balance + p_amount WHERE id = p_to;

    COMMIT;
END;
$$;

CALL transfer('id1', 'id2', 100.00);

```

## Drop functions/procedures


```sql
DROP FUNCTION IF EXISTS get_user(VARCHAR);
DROP PROCEDURE IF EXISTS transfer(UUID, UUID, NUMERIC);

```

Note: User-defined functions supported (v22.2+)
Note: Stored procedures with CALL supported (v23.2+)
Note: PL/pgSQL language supported (v23.1+)
Note: No triggers (cannot CREATE TRIGGER)
Note: LANGUAGE sql and LANGUAGE plpgsql supported
Note: No PL/Python, PL/V8, or other extension languages
Note: Functions work across distributed nodes
Note: Procedures can control transactions (COMMIT/ROLLBACK)
