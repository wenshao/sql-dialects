# Firebird: Error Handling

> 参考资料:
> - [Firebird Documentation - Exception Handling](https://firebirdsql.org/file/documentation/html/en/refdocs/fblangref40/firebird-40-language-reference.html#fblangref40-psql-exception)
> - [Firebird Documentation - WHEN ... DO](https://firebirdsql.org/file/documentation/html/en/refdocs/fblangref40/firebird-40-language-reference.html#fblangref40-psql-when)


## WHEN ... DO (PSQL 异常处理)

```sql
CREATE OR REPLACE PROCEDURE safe_insert(p_id INTEGER, p_name VARCHAR(100))
AS
BEGIN
    INSERT INTO users(id, username) VALUES(:p_id, :p_name);
    WHEN SQLCODE -803 DO  -- 唯一约束违反
    BEGIN
        UPDATE users SET username = :p_name WHERE id = :p_id;
    END
    WHEN ANY DO
    BEGIN
        EXCEPTION;  -- 重新抛出
    END
END;
```

## 使用 GDSCODE 条件

```sql
CREATE OR REPLACE PROCEDURE error_demo
AS
    DECLARE v_msg VARCHAR(200);
BEGIN
    INSERT INTO users(id, username) VALUES(1, 'test');
    WHEN GDSCODE unique_key_violation DO
    BEGIN
        v_msg = 'Duplicate key error';
    END
    WHEN GDSCODE foreign_key DO
    BEGIN
        v_msg = 'Foreign key error';
    END
END;
```

## EXCEPTION (自定义异常)

```sql
CREATE EXCEPTION e_invalid_amount 'Invalid amount: must be positive';
```

## 使用自定义异常

```sql
CREATE OR REPLACE PROCEDURE validate_order(p_amount DECIMAL(10,2))
AS
BEGIN
    IF (p_amount <= 0) THEN
        EXCEPTION e_invalid_amount;
    IF (p_amount > 999999) THEN
        EXCEPTION e_invalid_amount 'Amount exceeds maximum limit';
END;
```

## 在异常处理中获取错误信息

```sql
CREATE OR REPLACE PROCEDURE error_info_demo
AS
    DECLARE v_sqlcode INTEGER;
    DECLARE v_gdscode INTEGER;
    DECLARE v_msg VARCHAR(500);
BEGIN
    WHEN ANY DO
    BEGIN
        v_sqlcode = SQLCODE;
        v_gdscode = GDSCODE;
        v_msg = RDB$GET_CONTEXT('SYSTEM', 'LAST_ERROR_MESSAGE');
    END
END;
```

版本说明：
Firebird 1.0+ : WHEN ... DO, EXCEPTION, SQLCODE
Firebird 2.0+ : GDSCODE 条件
Firebird 3.0+ : RDB$GET_CONTEXT 错误信息
注意：Firebird 使用 WHEN ... DO 而非 EXCEPTION WHEN 或 TRY/CATCH
注意：EXCEPTION (不带名称) 用于重新抛出当前异常
注意：自定义异常通过 CREATE EXCEPTION 创建
限制：错误处理位于 BEGIN...END 块末尾
