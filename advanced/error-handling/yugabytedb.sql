-- YugabyteDB: Error Handling
--
-- 参考资料:
--   [1] YugabyteDB Documentation - PL/pgSQL
--       https://docs.yugabyte.com/preview/api/ysql/user-defined-subprograms-and-anon-blocks/

-- ============================================================
-- EXCEPTION WHEN (PostgreSQL 兼容)
-- ============================================================
CREATE OR REPLACE FUNCTION safe_insert(p_name VARCHAR, p_email VARCHAR)
RETURNS TEXT AS $$
BEGIN
    INSERT INTO users(username, email) VALUES(p_name, p_email);
    RETURN 'Success';
EXCEPTION
    WHEN unique_violation THEN
        RETURN 'Duplicate entry';
    WHEN not_null_violation THEN
        RETURN 'NULL not allowed';
    WHEN OTHERS THEN
        RETURN 'Error: ' || SQLERRM;
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- RAISE
-- ============================================================
CREATE OR REPLACE FUNCTION validate(p_val INT)
RETURNS VOID AS $$
BEGIN
    IF p_val < 0 THEN
        RAISE EXCEPTION 'Value cannot be negative: %', p_val
            USING ERRCODE = 'check_violation';
    END IF;
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- GET STACKED DIAGNOSTICS
-- ============================================================
CREATE OR REPLACE FUNCTION error_details()
RETURNS TEXT AS $$
DECLARE
    v_state TEXT;
    v_msg TEXT;
BEGIN
    PERFORM 1/0;
    RETURN 'OK';
EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS
        v_state = RETURNED_SQLSTATE,
        v_msg = MESSAGE_TEXT;
    RETURN 'Error ' || v_state || ': ' || v_msg;
END;
$$ LANGUAGE plpgsql;

-- 注意：YugabyteDB 兼容 PostgreSQL 错误处理
-- 注意：分布式环境下事务冲突可能产生额外的错误类型
-- 限制：与 PostgreSQL 基本一致
