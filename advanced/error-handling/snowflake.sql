-- Snowflake: Error Handling
--
-- 参考资料:
--   [1] Snowflake Documentation - Exception Handling
--       https://docs.snowflake.com/en/developer-guide/snowflake-scripting/exceptions
--   [2] Snowflake Documentation - RAISE
--       https://docs.snowflake.com/en/sql-reference/snowflake-scripting/raise

-- ============================================================
-- EXCEPTION WHEN (Snowflake Scripting)
-- ============================================================
CREATE OR REPLACE PROCEDURE safe_divide(a FLOAT, b FLOAT)
RETURNS FLOAT
LANGUAGE SQL
AS
$$
DECLARE
    result FLOAT;
BEGIN
    result := a / b;
    RETURN result;
EXCEPTION
    WHEN EXPRESSION_ERROR THEN
        RETURN NULL;
    WHEN OTHER THEN
        RAISE;
END;
$$;

-- ============================================================
-- RAISE (抛出异常)
-- ============================================================
CREATE OR REPLACE PROCEDURE validate_input(amount FLOAT)
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
DECLARE
    my_exception EXCEPTION (-20001, 'Amount must be positive');
BEGIN
    IF (amount <= 0) THEN
        RAISE my_exception;
    END IF;
    RETURN 'Valid';
EXCEPTION
    WHEN my_exception THEN
        RETURN 'Error: ' || SQLERRM;
END;
$$;

-- ============================================================
-- 内置异常类型
-- ============================================================
-- EXPRESSION_ERROR    : 表达式求值错误
-- STATEMENT_ERROR     : 语句执行错误
-- OTHER               : 其他所有错误

-- ============================================================
-- SQLCODE / SQLERRM / SQLSTATE
-- ============================================================
CREATE OR REPLACE PROCEDURE error_info_demo()
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
BEGIN
    SELECT * FROM nonexistent_table;
    RETURN 'OK';
EXCEPTION
    WHEN OTHER THEN
        RETURN 'SQLCODE=' || SQLCODE || ', SQLERRM=' || SQLERRM || ', SQLSTATE=' || SQLSTATE;
END;
$$;

-- ============================================================
-- 自定义异常
-- ============================================================
CREATE OR REPLACE PROCEDURE order_processing(amount FLOAT)
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
DECLARE
    e_too_small EXCEPTION (-20001, 'Order amount too small');
    e_too_large EXCEPTION (-20002, 'Order amount too large');
BEGIN
    IF (amount < 1.0) THEN
        RAISE e_too_small;
    ELSIF (amount > 999999.0) THEN
        RAISE e_too_large;
    END IF;
    RETURN 'Order accepted';
EXCEPTION
    WHEN e_too_small THEN
        RETURN SQLERRM;
    WHEN e_too_large THEN
        RETURN SQLERRM;
    WHEN OTHER THEN
        RAISE;
END;
$$;

-- 版本说明：
--   Snowflake Scripting (2021+) : EXCEPTION WHEN, RAISE
-- 注意：Snowflake 使用 EXCEPTION WHEN 语法（类似 Oracle/PostgreSQL）
-- 注意：自定义异常使用 DECLARE ... EXCEPTION (code, message) 声明
-- 注意：WHEN OTHER 捕获所有未列出的异常
-- 注意：SQLCODE, SQLERRM, SQLSTATE 在异常块中可用
-- 限制：只有 3 种内置异常类型
