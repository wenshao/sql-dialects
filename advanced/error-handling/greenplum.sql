-- Greenplum: Error Handling
--
-- 参考资料:
--   [1] Greenplum Documentation - PL/pgSQL
--       https://docs.vmware.com/en/VMware-Greenplum/7/greenplum-database/ref_guide-extensions-pl_sql.html

-- ============================================================
-- EXCEPTION WHEN (PostgreSQL 兼容)
-- ============================================================
CREATE OR REPLACE FUNCTION safe_divide(a NUMERIC, b NUMERIC)
RETURNS NUMERIC AS $$
BEGIN
    RETURN a / b;
EXCEPTION
    WHEN division_by_zero THEN
        RAISE NOTICE 'Division by zero';
        RETURN NULL;
    WHEN OTHERS THEN
        RAISE NOTICE 'Error: %', SQLERRM;
        RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- RAISE (抛出消息和异常)
-- ============================================================
CREATE OR REPLACE FUNCTION validate_input(p_val INT)
RETURNS VOID AS $$
BEGIN
    IF p_val < 0 THEN
        RAISE EXCEPTION 'Value cannot be negative: %', p_val
            USING ERRCODE = 'check_violation';
    END IF;
END;
$$ LANGUAGE plpgsql;

-- 注意：Greenplum 基于 PostgreSQL，错误处理语法一致
-- 注意：支持 EXCEPTION WHEN, RAISE, GET STACKED DIAGNOSTICS
-- 限制：部分 PostgreSQL 新版特性可能不支持
