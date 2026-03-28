# SAP HANA: Error Handling

> 参考资料:
> - [SAP HANA SQLScript Reference - Exception Handling](https://help.sap.com/docs/SAP_HANA_PLATFORM/de2486ee947e43e684d39702027f8a94/)
> - ============================================================
> - DECLARE EXIT HANDLER (SQLScript)
> - ============================================================

```sql
DO BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        SELECT ::SQL_ERROR_CODE AS error_code,
               ::SQL_ERROR_MESSAGE AS error_message
        FROM DUMMY;
    END;

    INSERT INTO users(id, username) VALUES(1, 'test');
END;
```

## DECLARE CONDITION / HANDLER

```sql
DO BEGIN
    DECLARE duplicate_key CONDITION FOR SQL_ERROR_CODE 301;
    DECLARE EXIT HANDLER FOR duplicate_key
    BEGIN
        SELECT 'Duplicate key' AS error FROM DUMMY;
    END;

    INSERT INTO users(id, username) VALUES(1, 'test');
END;
```

## SIGNAL (主动抛出异常)

```sql
CREATE PROCEDURE validate_amount(IN p_amount DECIMAL(10,2))
LANGUAGE SQLSCRIPT
AS
BEGIN
    IF :p_amount <= 0 THEN
        SIGNAL SQL_ERROR_CODE 10001
            SET MESSAGE_TEXT = 'Amount must be positive';
    END IF;
END;
```

## RESIGNAL

```sql
DO BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        RESIGNAL SQL_ERROR_CODE 10002
            SET MESSAGE_TEXT = 'Wrapped error: ' || ::SQL_ERROR_MESSAGE;
    END;

    SELECT * FROM nonexistent_table;
END;
```

## 存储过程中的完整错误处理

```sql
CREATE PROCEDURE transfer_funds(
    IN p_from INT, IN p_to INT, IN p_amount DECIMAL(10,2)
)
LANGUAGE SQLSCRIPT
AS
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SIGNAL SQL_ERROR_CODE 10003
            SET MESSAGE_TEXT = 'Transfer failed: ' || ::SQL_ERROR_MESSAGE;
    END;

    IF :p_amount <= 0 THEN
        SIGNAL SQL_ERROR_CODE 10001
            SET MESSAGE_TEXT = 'Amount must be positive';
    END IF;

    UPDATE accounts SET balance = balance - :p_amount WHERE id = :p_from;
    UPDATE accounts SET balance = balance + :p_amount WHERE id = :p_to;
    COMMIT;
END;
```

版本说明：
SAP HANA 1.0+ : DECLARE HANDLER, SIGNAL
SAP HANA 2.0+ : RESIGNAL, ::SQL_ERROR_CODE/MESSAGE
注意：SAP HANA 使用 SQLScript 过程语言
注意：使用 ::SQL_ERROR_CODE 和 ::SQL_ERROR_MESSAGE 获取错误信息
注意：SIGNAL 使用 SQL_ERROR_CODE（自定义范围 10000-19999）
限制：不支持 TRY/CATCH 或 EXCEPTION WHEN 语法
