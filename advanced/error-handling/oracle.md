# Oracle: 错误处理

> 参考资料:
> - [Oracle PL/SQL Reference - Exception Handling](https://docs.oracle.com/en/database/oracle/oracle-database/23/lnpls/exception-handler.html)
> - [Oracle PL/SQL Reference - Predefined Exceptions](https://docs.oracle.com/en/database/oracle/oracle-database/23/lnpls/plsql-error-handling.html)

## EXCEPTION WHEN（PL/SQL 异常处理）

```sql
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
```

## 预定义异常（Oracle 独有的异常体系）

NO_DATA_FOUND       (ORA-01403) SELECT INTO 无结果
TOO_MANY_ROWS       (ORA-01422) SELECT INTO 多行
DUP_VAL_ON_INDEX    (ORA-00001) 唯一约束违反
ZERO_DIVIDE         (ORA-01476) 除以零
VALUE_ERROR         (ORA-06502) 值截断/类型转换错误
INVALID_CURSOR      (ORA-01001) 无效游标
CURSOR_ALREADY_OPEN (ORA-06511) 游标已打开
LOGIN_DENIED        (ORA-01017) 登录被拒绝
TIMEOUT_ON_RESOURCE (ORA-00051) 等待资源超时

设计分析: Oracle 异常模型 vs 其他数据库
  Oracle PL/SQL: EXCEPTION WHEN ... THEN（声明式异常处理）
  PostgreSQL:    EXCEPTION WHEN ... THEN（语法相同!）
  MySQL:         DECLARE HANDLER FOR ... （处理器模式）
  SQL Server:    TRY ... CATCH（块级异常处理）

Oracle 的异常处理基于 Ada 语言的设计（PL/SQL 源自 Ada），
与 Java/Python 的 try-catch 不同: 异常处理器在 BEGIN...END 块的尾部。

## 自定义异常

```sql
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
```

## PRAGMA EXCEPTION_INIT（将 ORA 错误码绑定到异常名）

```sql
DECLARE
    e_deadlock EXCEPTION;
    PRAGMA EXCEPTION_INIT(e_deadlock, -60);         -- ORA-00060
    e_fk_violation EXCEPTION;
    PRAGMA EXCEPTION_INIT(e_fk_violation, -2292);   -- ORA-02292
BEGIN
    DELETE FROM departments WHERE id = 10;
EXCEPTION
    WHEN e_fk_violation THEN
        DBMS_OUTPUT.PUT_LINE('Cannot delete: child records exist');
    WHEN e_deadlock THEN
        DBMS_OUTPUT.PUT_LINE('Deadlock detected, please retry');
END;
/
```

PRAGMA EXCEPTION_INIT 是 Oracle 独有的机制:
将数值错误码映射为命名异常，使异常处理代码更可读。
其他数据库直接使用错误码或状态码（如 PostgreSQL 的 SQLSTATE）。

## RAISE_APPLICATION_ERROR（自定义错误码和消息）

错误码范围: -20000 到 -20999（Oracle 保留给用户的范围）
```sql
CREATE OR REPLACE PROCEDURE validate_order(p_amount NUMBER) AS
BEGIN
    IF p_amount IS NULL THEN
        RAISE_APPLICATION_ERROR(-20001, 'Amount cannot be null');
    ELSIF p_amount <= 0 THEN
        RAISE_APPLICATION_ERROR(-20002, 'Amount must be positive');
    ELSIF p_amount > 999999 THEN
        RAISE_APPLICATION_ERROR(-20003, 'Amount exceeds maximum');
    END IF;
END;
/
```

横向对比:
  Oracle:     RAISE_APPLICATION_ERROR(-20xxx, msg) -- 固定错误码范围
  PostgreSQL: RAISE EXCEPTION 'msg' USING ERRCODE = 'P0001' -- SQLSTATE 自定义
  MySQL:      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'msg'
  SQL Server: THROW 50001, 'msg', 1 -- 错误号 >= 50000

## 错误栈和回溯

```sql
CREATE OR REPLACE PROCEDURE detailed_error_handling AS
BEGIN
    EXECUTE IMMEDIATE 'SELECT * FROM nonexistent_table';
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Error Stack: ' || DBMS_UTILITY.FORMAT_ERROR_STACK);
        DBMS_OUTPUT.PUT_LINE('Backtrace: ' || DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
        DBMS_OUTPUT.PUT_LINE('Call Stack: ' || DBMS_UTILITY.FORMAT_CALL_STACK);
END;
/
```

FORMAT_ERROR_STACK: 错误消息
FORMAT_ERROR_BACKTRACE: 错误发生的代码行号（10g+，调试利器）
FORMAT_CALL_STACK: 调用链

12c+: UTL_CALL_STACK 包提供更结构化的调用栈访问

## 嵌套块与异常传播

```sql
DECLARE
    v_result NUMBER;
BEGIN
    -- 内层块捕获并处理异常
    BEGIN
        v_result := 1 / 0;
    EXCEPTION
        WHEN ZERO_DIVIDE THEN
            v_result := 0;                     -- 恢复并继续
    END;

    DBMS_OUTPUT.PUT_LINE('Continuing with: ' || v_result);
```

另一个内层块
```sql
    BEGIN
        INSERT INTO users(id, username) VALUES(1, 'test');
    EXCEPTION
        WHEN DUP_VAL_ON_INDEX THEN
            DBMS_OUTPUT.PUT_LINE('Duplicate, skipping');
    END;
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Outer: unexpected error');
END;
/
```

## RAISE 重新抛出 + 日志记录模式

```sql
CREATE OR REPLACE PROCEDURE process_with_logging AS
BEGIN
    INSERT INTO orders(id, amount) VALUES(1, 100);
EXCEPTION
    WHEN OTHERS THEN
        -- 使用自治事务记录错误（主事务回滚不影响日志）
        log_error(SQLERRM);                   -- 调用自治事务过程
        RAISE;                                 -- 重新抛出原始异常
END;
/
```

## '' = NULL 对错误处理的影响

检查空字符串参数:
IF p_name = '' THEN RAISE_APPLICATION_ERROR(...); END IF;
永远不会触发! 因为 '' = NULL，比较结果是 UNKNOWN
正确写法: IF p_name IS NULL THEN ...

## 对引擎开发者的总结

1. Oracle 的 EXCEPTION WHEN 模型源自 Ada，与 TRY/CATCH 风格不同。
2. PRAGMA EXCEPTION_INIT 将数值错误码映射为命名异常，提高可读性。
3. RAISE_APPLICATION_ERROR 的 -20000~-20999 范围是 Oracle 独有的约定。
4. FORMAT_ERROR_BACKTRACE (10g+) 是调试的关键工具（提供行号）。
5. 自治事务 + RAISE 组合是"记录错误后继续传播"的标准模式。
6. WHEN OTHERS 应始终是最后一个处理器，且通常应 RAISE 重新抛出。
