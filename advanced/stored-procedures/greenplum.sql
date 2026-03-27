-- Greenplum: 存储过程和函数
--
-- 参考资料:
--   [1] Greenplum SQL Reference
--       https://docs.vmware.com/en/VMware-Greenplum/7/greenplum-database/ref_guide-sql_commands-sql_ref.html
--   [2] Greenplum Admin Guide
--       https://docs.vmware.com/en/VMware-Greenplum/7/greenplum-database/admin_guide-intro-about_greenplum.html

-- Greenplum 基于 PostgreSQL，支持完整的存储过程和函数

-- ============================================================
-- 创建函数（SQL 语言）
-- ============================================================

CREATE OR REPLACE FUNCTION get_user(p_username VARCHAR)
RETURNS TABLE (id BIGINT, username VARCHAR, email VARCHAR, age INTEGER)
AS $$
    SELECT id, username, email, age FROM users WHERE username = p_username;
$$ LANGUAGE sql;

SELECT * FROM get_user('alice');

-- ============================================================
-- PL/pgSQL 函数
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

-- ============================================================
-- 存储过程（PostgreSQL 11+ / Greenplum 7+）
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

    COMMIT;
END;
$$;

CALL transfer(1, 2, 100.00);

-- ============================================================
-- 带 OUT 参数的函数
-- ============================================================

CREATE OR REPLACE FUNCTION get_stats(
    OUT min_age INTEGER, OUT max_age INTEGER, OUT avg_age NUMERIC
)
AS $$
    SELECT MIN(age), MAX(age), AVG(age) FROM users;
$$ LANGUAGE sql;

SELECT * FROM get_stats();

-- ============================================================
-- 返回多行
-- ============================================================

CREATE OR REPLACE FUNCTION active_users()
RETURNS SETOF users AS $$
    SELECT * FROM users WHERE status = 1;
$$ LANGUAGE sql;

-- ============================================================
-- 异常处理
-- ============================================================

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
-- 多种语言支持
-- ============================================================

-- LANGUAGE sql         -- 纯 SQL
-- LANGUAGE plpgsql     -- PL/pgSQL
-- LANGUAGE plpython3u  -- Python（需要安装扩展）

-- Python 函数（需要 plpython3u 扩展）
-- CREATE OR REPLACE FUNCTION py_upper(s TEXT) RETURNS TEXT AS $$
--     return s.upper()
-- $$ LANGUAGE plpython3u;

-- ============================================================
-- 删除
-- ============================================================

DROP FUNCTION IF EXISTS get_user(VARCHAR);
DROP PROCEDURE IF EXISTS transfer(BIGINT, BIGINT, NUMERIC);

-- 注意：Greenplum 兼容 PostgreSQL 存储过程语法
-- 注意：PROCEDURE 支持事务控制（COMMIT/ROLLBACK）
-- 注意：FUNCTION 不能控制事务
-- 注意：在 MPP 架构下，函数在所有 Segment 上执行
-- 注意：VOLATILE / STABLE / IMMUTABLE 标记影响优化
