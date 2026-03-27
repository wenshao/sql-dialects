-- Oracle: Error Handling
--
-- 参考资料:
--   [1] Oracle PL/SQL Reference - Exception Handling
--       https://docs.oracle.com/en/database/oracle/oracle-database/23/lnpls/exception-handler.html
--   [2] Oracle PL/SQL Reference - RAISE Statement
--       https://docs.oracle.com/en/database/oracle/oracle-database/23/lnpls/RAISE-statement.html
--   [3] Oracle PL/SQL Reference - Predefined Exceptions
--       https://docs.oracle.com/en/database/oracle/oracle-database/23/lnpls/plsql-error-handling.html

-- ============================================================
-- EXCEPTION WHEN (PL/SQL 异常处理)
-- ============================================================
DECLARE
    v_name VARCHAR2(100);
BEGIN
    SELECT username INTO v_name FROM users WHERE id = 999;
    DBMS_OUTPUT.PUT_LINE('Found: ' || v_name);
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
-- 预定义异常
-- ============================================================
-- NO_DATA_FOUND       (ORA-01403) SELECT INTO 无结果
-- TOO_MANY_ROWS       (ORA-01422) SELECT INTO 多行结果
-- DUP_VAL_ON_INDEX    (ORA-00001) 唯一约束违反
-- ZERO_DIVIDE         (ORA-01476) 除以零
-- VALUE_ERROR         (ORA-06502) 值错误（截断、类型转换）
-- INVALID_CURSOR      (ORA-01001) 无效游标
-- CURSOR_ALREADY_OPEN (ORA-06511) 游标已打开
-- LOGIN_DENIED        (ORA-01017) 登录被拒绝
-- TIMEOUT_ON_RESOURCE (ORA-00051) 等待资源超时
-- STORAGE_ERROR       (ORA-06500) 内存不足

-- ============================================================
-- 自定义异常
-- ============================================================
DECLARE
    e_invalid_amount EXCEPTION;
    v_amount NUMBER := -100;
BEGIN
    IF v_amount <= 0 THEN
        RAISE e_invalid_amount;
    END IF;
EXCEPTION
    WHEN e_invalid_amount THEN
        DBMS_OUTPUT.PUT_LINE('Error: Amount must be positive');
END;
/

-- ============================================================
-- PRAGMA EXCEPTION_INIT (将 Oracle 错误码绑定到异常)
-- ============================================================
DECLARE
    e_deadlock EXCEPTION;
    PRAGMA EXCEPTION_INIT(e_deadlock, -60);  -- ORA-00060: deadlock
    e_fk_violation EXCEPTION;
    PRAGMA EXCEPTION_INIT(e_fk_violation, -2292);  -- ORA-02292
BEGIN
    DELETE FROM departments WHERE id = 10;
EXCEPTION
    WHEN e_fk_violation THEN
        DBMS_OUTPUT.PUT_LINE('Cannot delete: child records exist');
    WHEN e_deadlock THEN
        DBMS_OUTPUT.PUT_LINE('Deadlock detected, please retry');
END;
/

-- ============================================================
-- RAISE_APPLICATION_ERROR (自定义错误码和消息)
-- ============================================================
-- 错误码范围: -20000 到 -20999
CREATE OR REPLACE PROCEDURE validate_order(p_amount NUMBER) AS
BEGIN
    IF p_amount IS NULL THEN
        RAISE_APPLICATION_ERROR(-20001, 'Amount cannot be null');
    ELSIF p_amount <= 0 THEN
        RAISE_APPLICATION_ERROR(-20002, 'Amount must be positive: ' || p_amount);
    ELSIF p_amount > 999999 THEN
        RAISE_APPLICATION_ERROR(-20003, 'Amount exceeds maximum limit');
    END IF;
END;
/

-- ============================================================
-- RAISE (重新抛出异常)
-- ============================================================
CREATE OR REPLACE PROCEDURE process_with_logging AS
BEGIN
    -- 业务操作
    INSERT INTO orders(id, amount) VALUES(1, 100);
EXCEPTION
    WHEN OTHERS THEN
        -- 记录错误
        INSERT INTO error_log(error_code, error_message, created_at)
        VALUES(SQLCODE, SQLERRM, SYSTIMESTAMP);
        COMMIT;  -- 确保日志被保存
        RAISE;   -- 重新抛出原始异常
END;
/

-- ============================================================
-- DBMS_UTILITY.FORMAT_ERROR_STACK / FORMAT_ERROR_BACKTRACE
-- ============================================================
CREATE OR REPLACE PROCEDURE detailed_error_handling AS
BEGIN
    -- 触发错误
    EXECUTE IMMEDIATE 'SELECT * FROM nonexistent_table';
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Error Stack:');
        DBMS_OUTPUT.PUT_LINE(DBMS_UTILITY.FORMAT_ERROR_STACK);
        DBMS_OUTPUT.PUT_LINE('Error Backtrace:');
        DBMS_OUTPUT.PUT_LINE(DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
        DBMS_OUTPUT.PUT_LINE('Call Stack:');
        DBMS_OUTPUT.PUT_LINE(DBMS_UTILITY.FORMAT_CALL_STACK);
END;
/

-- ============================================================
-- 嵌套块与异常传播
-- ============================================================
DECLARE
    v_result NUMBER;
BEGIN
    -- 外层块
    BEGIN
        -- 内层块
        v_result := 1 / 0;
    EXCEPTION
        WHEN ZERO_DIVIDE THEN
            DBMS_OUTPUT.PUT_LINE('Inner: caught division by zero');
            v_result := 0;
    END;

    DBMS_OUTPUT.PUT_LINE('Continuing with result: ' || v_result);

    BEGIN
        INSERT INTO users(id, username) VALUES(1, 'test');
    EXCEPTION
        WHEN DUP_VAL_ON_INDEX THEN
            DBMS_OUTPUT.PUT_LINE('Inner: duplicate key, skipping');
    END;
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Outer: unexpected error');
END;
/

-- ============================================================
-- 存储过程完整错误处理模式
-- ============================================================
CREATE OR REPLACE PROCEDURE transfer_funds(
    p_from_account NUMBER,
    p_to_account   NUMBER,
    p_amount       NUMBER
) AS
    e_insufficient_funds EXCEPTION;
    PRAGMA EXCEPTION_INIT(e_insufficient_funds, -20010);
    v_balance NUMBER;
BEGIN
    -- 验证
    IF p_amount <= 0 THEN
        RAISE_APPLICATION_ERROR(-20001, 'Amount must be positive');
    END IF;

    -- 检查余额
    SELECT balance INTO v_balance FROM accounts WHERE id = p_from_account;
    IF v_balance < p_amount THEN
        RAISE_APPLICATION_ERROR(-20010, 'Insufficient funds');
    END IF;

    -- 转账
    UPDATE accounts SET balance = balance - p_amount WHERE id = p_from_account;
    UPDATE accounts SET balance = balance + p_amount WHERE id = p_to_account;

    COMMIT;
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        ROLLBACK;
        RAISE_APPLICATION_ERROR(-20002, 'Account not found');
    WHEN e_insufficient_funds THEN
        ROLLBACK;
        RAISE;
    WHEN OTHERS THEN
        ROLLBACK;
        INSERT INTO error_log(error_code, error_message, created_at)
        VALUES(SQLCODE, SQLERRM, SYSTIMESTAMP);
        COMMIT;
        RAISE;
END;
/

-- 版本说明：
--   Oracle 7+     : EXCEPTION WHEN, 预定义异常
--   Oracle 8i+    : RAISE_APPLICATION_ERROR
--   Oracle 10g+   : DBMS_UTILITY.FORMAT_ERROR_BACKTRACE
--   Oracle 12c+   : UTL_CALL_STACK 包
-- 注意：WHEN OTHERS 应始终是最后一个异常处理器
-- 注意：RAISE_APPLICATION_ERROR 错误码范围 -20000 到 -20999
-- 注意：SQLCODE 返回错误号，SQLERRM 返回错误消息
-- 注意：异常处理器中的 COMMIT/ROLLBACK 不影响外部事务
-- 限制：不支持 TRY/CATCH 语法
-- 限制：不支持 DECLARE HANDLER 语法
-- 限制：不能在 SQL 语句中直接使用异常处理
