-- 达梦 (DM): Error Handling
--
-- 参考资料:
--   [1] 达梦数据库 PL/SQL 编程指南
--       https://eco.dameng.com/document/dm/zh-cn/pm/pl-sql.html

-- ============================================================
-- EXCEPTION WHEN (兼容 Oracle PL/SQL)
-- ============================================================
DECLARE
    v_name VARCHAR2(100);
BEGIN
    SELECT username INTO v_name FROM users WHERE id = 999;
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        DBMS_OUTPUT.PUT_LINE('User not found');
    WHEN TOO_MANY_ROWS THEN
        DBMS_OUTPUT.PUT_LINE('Multiple rows returned');
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Error: ' || SQLCODE || ' - ' || SQLERRM);
END;
/

-- ============================================================
-- RAISE_APPLICATION_ERROR
-- ============================================================
CREATE OR REPLACE PROCEDURE validate_amount(p_amount NUMBER) AS
BEGIN
    IF p_amount <= 0 THEN
        RAISE_APPLICATION_ERROR(-20001, 'Amount must be positive');
    END IF;
END;
/

-- ============================================================
-- 自定义异常
-- ============================================================
DECLARE
    e_invalid EXCEPTION;
BEGIN
    RAISE e_invalid;
EXCEPTION
    WHEN e_invalid THEN
        DBMS_OUTPUT.PUT_LINE('Custom exception caught');
END;
/

-- 注意：达梦兼容 Oracle PL/SQL 异常处理语法
-- 注意：支持预定义异常、自定义异常、RAISE_APPLICATION_ERROR
-- 限制：兼容性取决于具体版本
