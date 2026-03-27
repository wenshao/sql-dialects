-- Vertica: Error Handling
--
-- 参考资料:
--   [1] Vertica Documentation - PL/vSQL Exception Handling
--       https://www.vertica.com/docs/latest/HTML/Content/Authoring/ProgrammersGuide/StoredProcedures/ExceptionHandling.htm

-- ============================================================
-- EXCEPTION WHEN (PL/vSQL)                            -- 11.0+
-- ============================================================
CREATE OR REPLACE PROCEDURE safe_op()
LANGUAGE PLvSQL
AS $$
BEGIN
    PERFORM 1/0;
EXCEPTION
    WHEN division_by_zero THEN
        RAISE NOTICE 'Division by zero caught';
    WHEN OTHERS THEN
        RAISE NOTICE 'Error: %', SQLERRM;
END;
$$;

-- ============================================================
-- RAISE
-- ============================================================
CREATE OR REPLACE PROCEDURE validate(p_val INT)
LANGUAGE PLvSQL
AS $$
BEGIN
    IF p_val < 0 THEN
        RAISE EXCEPTION 'Value must be non-negative: %', p_val;
    END IF;
END;
$$;

-- 版本说明：
--   Vertica 11.0+ : PL/vSQL 存储过程和异常处理
-- 注意：PL/vSQL 语法类似 PostgreSQL PL/pgSQL
-- 限制：功能比 PostgreSQL 有限
