-- openGauss/GaussDB: 存储过程和函数
-- PostgreSQL compatible PL/pgSQL with extensions.
--
-- 参考资料:
--   [1] openGauss SQL Reference
--       https://docs.opengauss.org/zh/docs/latest/docs/SQLReference/SQL-reference.html
--   [2] GaussDB Documentation
--       https://support.huaweicloud.com/gaussdb/index.html

-- 创建函数
CREATE OR REPLACE FUNCTION get_user(p_username VARCHAR)
RETURNS TABLE (id BIGINT, username VARCHAR, email VARCHAR, age INTEGER)
AS $$
    SELECT id, username, email, age FROM users WHERE username = p_username;
$$ LANGUAGE sql;

-- 调用
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

-- 存储过程（支持事务控制）
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

    COMMIT;
END;
$$;

-- 调用过程
CALL transfer(1, 2, 100.00);

-- 带 OUT 参数
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

-- 包（openGauss 扩展，Oracle 兼容）
CREATE OR REPLACE PACKAGE user_pkg AS
    PROCEDURE create_user(p_name VARCHAR, p_email VARCHAR);
    FUNCTION get_count() RETURN INTEGER;
END user_pkg;
/

CREATE OR REPLACE PACKAGE BODY user_pkg AS
    PROCEDURE create_user(p_name VARCHAR, p_email VARCHAR) AS
    BEGIN
        INSERT INTO users (username, email) VALUES (p_name, p_email);
    END;

    FUNCTION get_count() RETURN INTEGER AS
        v_cnt INTEGER;
    BEGIN
        SELECT COUNT(*) INTO v_cnt FROM users;
        RETURN v_cnt;
    END;
END user_pkg;
/

-- 删除
DROP FUNCTION IF EXISTS get_user(VARCHAR);
DROP PROCEDURE IF EXISTS transfer(BIGINT, BIGINT, NUMERIC);

-- 注意事项：
-- 基本语法与 PostgreSQL 兼容（PL/pgSQL）
-- openGauss 扩展支持 Oracle 兼容的 Package 语法
-- EXECUTE PROCEDURE 替代 EXECUTE FUNCTION
-- 支持自治事务（PRAGMA AUTONOMOUS_TRANSACTION）
