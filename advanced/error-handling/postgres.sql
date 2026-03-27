-- PostgreSQL: Error Handling
--
-- 参考资料:
--   [1] PostgreSQL Documentation - PL/pgSQL Error Handling
--       https://www.postgresql.org/docs/current/plpgsql-control-structures.html#PLPGSQL-ERROR-TRAPPING
--   [2] PostgreSQL Documentation - Error Codes
--       https://www.postgresql.org/docs/current/errcodes-appendix.html
--   [3] PostgreSQL Documentation - RAISE
--       https://www.postgresql.org/docs/current/plpgsql-errors-and-messages.html

-- ============================================================
-- EXCEPTION WHEN (PL/pgSQL 异常捕获)
-- ============================================================
CREATE OR REPLACE FUNCTION safe_divide(a NUMERIC, b NUMERIC)
RETURNS NUMERIC AS $$
BEGIN
    RETURN a / b;
EXCEPTION
    WHEN division_by_zero THEN
        RAISE NOTICE 'Division by zero, returning NULL';
        RETURN NULL;
    WHEN numeric_value_out_of_range THEN
        RAISE NOTICE 'Numeric overflow';
        RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- 多个异常条件
-- ============================================================
CREATE OR REPLACE FUNCTION safe_insert(p_name VARCHAR, p_email VARCHAR)
RETURNS VOID AS $$
BEGIN
    INSERT INTO users(username, email) VALUES(p_name, p_email);
EXCEPTION
    WHEN unique_violation THEN
        RAISE NOTICE 'Duplicate entry: % or %', p_name, p_email;
    WHEN not_null_violation THEN
        RAISE NOTICE 'NULL value not allowed';
    WHEN check_violation THEN
        RAISE NOTICE 'Check constraint failed';
    WHEN OTHERS THEN
        RAISE NOTICE 'Unexpected error: %, %', SQLSTATE, SQLERRM;
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- RAISE (抛出消息和异常)
-- ============================================================
-- 消息级别：DEBUG, LOG, INFO, NOTICE, WARNING, EXCEPTION
CREATE OR REPLACE FUNCTION validate_age(p_age INT)
RETURNS VOID AS $$
BEGIN
    IF p_age < 0 THEN
        RAISE EXCEPTION 'Age cannot be negative: %', p_age
            USING ERRCODE = 'check_violation';
    ELSIF p_age > 200 THEN
        RAISE WARNING 'Suspicious age value: %', p_age;
    ELSE
        RAISE NOTICE 'Age is valid: %', p_age;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- RAISE EXCEPTION 带详细信息
-- ============================================================
CREATE OR REPLACE FUNCTION custom_error_demo()
RETURNS VOID AS $$
BEGIN
    RAISE EXCEPTION 'Custom error occurred'
        USING ERRCODE = '45000',
              DETAIL = 'Additional details about the error',
              HINT = 'Try a different approach',
              COLUMN = 'username',
              TABLE = 'users';
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- SQLSTATE 条件匹配
-- ============================================================
CREATE OR REPLACE FUNCTION handle_by_sqlstate()
RETURNS VOID AS $$
BEGIN
    -- 模拟操作
    INSERT INTO users(id, username) VALUES(1, 'test');
EXCEPTION
    WHEN SQLSTATE '23505' THEN  -- unique_violation
        RAISE NOTICE 'Duplicate key (SQLSTATE 23505)';
    WHEN SQLSTATE '23503' THEN  -- foreign_key_violation
        RAISE NOTICE 'Foreign key violation (SQLSTATE 23503)';
    WHEN SQLSTATE '23502' THEN  -- not_null_violation
        RAISE NOTICE 'Not null violation (SQLSTATE 23502)';
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- GET STACKED DIAGNOSTICS (获取异常详细信息)           -- 9.2+
-- ============================================================
CREATE OR REPLACE FUNCTION log_error_details()
RETURNS VOID AS $$
DECLARE
    v_state TEXT;
    v_msg   TEXT;
    v_detail TEXT;
    v_hint  TEXT;
    v_context TEXT;
BEGIN
    -- 触发错误
    PERFORM 1/0;
EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS
        v_state   = RETURNED_SQLSTATE,
        v_msg     = MESSAGE_TEXT,
        v_detail  = PG_EXCEPTION_DETAIL,
        v_hint    = PG_EXCEPTION_HINT,
        v_context = PG_EXCEPTION_CONTEXT;

    RAISE NOTICE 'State: %, Message: %, Detail: %, Hint: %, Context: %',
        v_state, v_msg, v_detail, v_hint, v_context;

    -- 记录到日志表
    INSERT INTO error_log(sqlstate, message, detail, created_at)
    VALUES(v_state, v_msg, v_detail, NOW());
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- ASSERT (断言，用于调试)                              -- 9.5+
-- ============================================================
CREATE OR REPLACE FUNCTION process_order(p_amount NUMERIC)
RETURNS VOID AS $$
BEGIN
    ASSERT p_amount > 0, 'Amount must be positive';
    ASSERT p_amount <= 999999, 'Amount exceeds maximum';
    -- 处理订单
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- 嵌套异常处理（事务子块）
-- ============================================================
CREATE OR REPLACE FUNCTION nested_exception_demo()
RETURNS TEXT AS $$
DECLARE
    result TEXT := '';
BEGIN
    -- 外层块
    BEGIN
        INSERT INTO users(id, username) VALUES(1, 'alice');
        result := result || 'Insert 1 OK. ';
    EXCEPTION WHEN unique_violation THEN
        result := result || 'Insert 1 skipped (dup). ';
    END;

    -- 每个 BEGIN...EXCEPTION 块有独立的子事务
    BEGIN
        INSERT INTO users(id, username) VALUES(2, 'bob');
        result := result || 'Insert 2 OK. ';
    EXCEPTION WHEN unique_violation THEN
        result := result || 'Insert 2 skipped (dup). ';
    END;

    RETURN result;
END;
$$ LANGUAGE plpgsql;

-- 版本说明：
--   PostgreSQL 8.0+  : EXCEPTION WHEN, RAISE
--   PostgreSQL 9.2+  : GET STACKED DIAGNOSTICS
--   PostgreSQL 9.5+  : ASSERT
-- 注意：EXCEPTION 块会创建隐式子事务（SAVEPOINT）
-- 注意：EXCEPTION 块有性能开销，不应在高频循环中使用
-- 注意：WHEN OTHERS 捕获所有异常（但不包括 QUERY_CANCELED 和 ASSERT_FAILURE）
-- 注意：SQLSTATE 和 SQLERRM 在 EXCEPTION 块中自动可用
-- 限制：不支持 TRY/CATCH 语法
-- 限制：ASSERT 默认启用，可通过 plpgsql.check_asserts 关闭
