# KingbaseES (人大金仓): Error Handling

> 参考资料:
> - [KingbaseES PL/SQL 参考手册](https://help.kingbase.com.cn/)


## EXCEPTION WHEN (兼容 Oracle/PostgreSQL)

```sql
DECLARE
    v_name VARCHAR2(100);
BEGIN
    SELECT username INTO v_name FROM users WHERE id = 999;
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        DBMS_OUTPUT.PUT_LINE('Not found');
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Error: ' || SQLCODE || ' - ' || SQLERRM);
END;
/
```

## RAISE / RAISE_APPLICATION_ERROR

```sql
CREATE OR REPLACE PROCEDURE validate(p_val NUMBER) AS
BEGIN
    IF p_val <= 0 THEN
        RAISE_APPLICATION_ERROR(-20001, 'Value must be positive');
    END IF;
END;
/
```

## PL/pgSQL 模式

```sql
CREATE OR REPLACE FUNCTION safe_op(p_val INT)
RETURNS TEXT AS $$
BEGIN
    PERFORM 1 / p_val;
    RETURN 'OK';
EXCEPTION
    WHEN division_by_zero THEN
        RETURN 'Division by zero';
END;
$$ LANGUAGE plpgsql;
```

注意：KingbaseES 同时兼容 Oracle 和 PostgreSQL 异常处理语法
注意：具体语法取决于兼容模式设置
限制：部分高级功能取决于版本
