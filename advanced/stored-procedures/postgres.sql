-- PostgreSQL: 存储过程和函数
--
-- 参考资料:
--   [1] PostgreSQL Documentation - CREATE FUNCTION
--       https://www.postgresql.org/docs/current/sql-createfunction.html
--   [2] PostgreSQL Documentation - CREATE PROCEDURE
--       https://www.postgresql.org/docs/current/sql-createprocedure.html
--   [3] PostgreSQL Documentation - PL/pgSQL
--       https://www.postgresql.org/docs/current/plpgsql.html

-- 创建函数（所有版本）
CREATE OR REPLACE FUNCTION get_user(p_username VARCHAR)
RETURNS TABLE (id BIGINT, username VARCHAR, email VARCHAR, age INTEGER)
AS $$
    SELECT id, username, email, age FROM users WHERE username = p_username;
$$ LANGUAGE sql;

-- 调用函数
SELECT * FROM get_user('alice');

-- PL/pgSQL 函数
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

-- 11+: 存储过程（支持事务控制）
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

    COMMIT;  -- 过程内可以 COMMIT/ROLLBACK（函数不行）
END;
$$;

-- 调用过程
CALL transfer(1, 2, 100.00);

-- 带 OUT 参数的函数
CREATE OR REPLACE FUNCTION get_stats(
    OUT min_age INTEGER, OUT max_age INTEGER, OUT avg_age NUMERIC
)
AS $$
    SELECT MIN(age), MAX(age), AVG(age) FROM users;
$$ LANGUAGE sql;

SELECT * FROM get_stats();

-- 返回多行
CREATE OR REPLACE FUNCTION active_users()
RETURNS SETOF users AS $$
    SELECT * FROM users WHERE status = 1;
$$ LANGUAGE sql;

-- 异常处理
CREATE OR REPLACE FUNCTION safe_divide(a NUMERIC, b NUMERIC)
RETURNS NUMERIC AS $$
BEGIN
    RETURN a / b;
EXCEPTION
    WHEN division_by_zero THEN
        RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- 多种语言支持
-- LANGUAGE sql         -- 纯 SQL
-- LANGUAGE plpgsql     -- PL/pgSQL
-- LANGUAGE plpython3u  -- Python
-- LANGUAGE plv8        -- JavaScript

-- 删除
DROP FUNCTION IF EXISTS get_user(VARCHAR);
DROP PROCEDURE IF EXISTS transfer(BIGINT, BIGINT, NUMERIC);
