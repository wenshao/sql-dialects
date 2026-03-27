-- YugabyteDB: Stored Procedures and Functions (YSQL, v2.x+)
--
-- 参考资料:
--   [1] YugabyteDB YSQL Reference
--       https://docs.yugabyte.com/stable/api/ysql/
--   [2] YugabyteDB PostgreSQL Compatibility
--       https://docs.yugabyte.com/stable/explore/ysql-language-features/

-- YugabyteDB supports PostgreSQL-compatible functions and procedures

-- ============================================================
-- SQL Functions
-- ============================================================

CREATE OR REPLACE FUNCTION get_user(p_username VARCHAR)
RETURNS TABLE (id BIGINT, username VARCHAR, email VARCHAR, age INTEGER)
AS $$
    SELECT id, username, email, age FROM users WHERE username = p_username;
$$ LANGUAGE sql;

SELECT * FROM get_user('alice');

-- ============================================================
-- PL/pgSQL Functions
-- ============================================================

CREATE OR REPLACE FUNCTION get_user_count()
RETURNS INTEGER AS $$
DECLARE
    v_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO v_count FROM users;
    RETURN v_count;
END;
$$ LANGUAGE plpgsql;

SELECT get_user_count();

-- Function with OUT parameters
CREATE OR REPLACE FUNCTION get_stats(
    OUT min_age INTEGER, OUT max_age INTEGER, OUT avg_age NUMERIC
)
AS $$
    SELECT MIN(age), MAX(age), AVG(age) FROM users;
$$ LANGUAGE sql;

SELECT * FROM get_stats();

-- Function returning SETOF (multiple rows)
CREATE OR REPLACE FUNCTION active_users()
RETURNS SETOF users AS $$
    SELECT * FROM users WHERE status = 1;
$$ LANGUAGE sql;

SELECT * FROM active_users();

-- Exception handling
CREATE OR REPLACE FUNCTION safe_divide(a NUMERIC, b NUMERIC)
RETURNS NUMERIC AS $$
BEGIN
    RETURN a / b;
EXCEPTION
    WHEN division_by_zero THEN
        RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- Stored Procedures (same as PostgreSQL 11+)
-- ============================================================

CREATE OR REPLACE PROCEDURE transfer(
    p_from BIGINT, p_to BIGINT, p_amount NUMERIC
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

    COMMIT;  -- procedures can COMMIT/ROLLBACK (functions cannot)
END;
$$;

CALL transfer(1, 2, 100.00);

-- Procedure with INOUT parameters
CREATE OR REPLACE PROCEDURE increment_counter(INOUT counter INTEGER)
LANGUAGE plpgsql
AS $$
BEGIN
    counter := counter + 1;
END;
$$;

CALL increment_counter(5);  -- returns 6

-- ============================================================
-- Drop functions/procedures
-- ============================================================

DROP FUNCTION IF EXISTS get_user(VARCHAR);
DROP PROCEDURE IF EXISTS transfer(BIGINT, BIGINT, NUMERIC);

-- Note: Full PL/pgSQL support (same as PostgreSQL 11)
-- Note: Procedures support transaction control (COMMIT/ROLLBACK)
-- Note: Functions cannot control transactions
-- Note: LANGUAGE sql and LANGUAGE plpgsql supported
-- Note: No PL/Python or PL/V8 extension languages
-- Note: Functions and procedures work across distributed tablets
-- Note: FOR UPDATE locks work in distributed transactions
