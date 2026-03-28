# DB2: Error Handling

> 参考资料:
> - [IBM DB2 Documentation - DECLARE HANDLER](https://www.ibm.com/docs/en/db2/11.5?topic=statements-declare-handler)
> - [IBM DB2 Documentation - SIGNAL](https://www.ibm.com/docs/en/db2/11.5?topic=statements-signal)
> - [IBM DB2 Documentation - GET DIAGNOSTICS](https://www.ibm.com/docs/en/db2/11.5?topic=statements-get-diagnostics)
> - ============================================================
> - DECLARE HANDLER
> - ============================================================

```sql
BEGIN
    DECLARE v_msg VARCHAR(200);
    DECLARE CONTINUE HANDLER FOR SQLSTATE '23505'
    BEGIN
        SET v_msg = 'Duplicate key violation ignored';
    END;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT;
        INSERT INTO error_log(message) VALUES(v_msg);
    END;

    INSERT INTO users(id, username) VALUES(1, 'test');
END@
```

## SIGNAL (抛出异常)

```sql
CREATE OR REPLACE PROCEDURE validate_amount(IN p_amount DECIMAL(10,2))
LANGUAGE SQL
BEGIN
    IF p_amount <= 0 THEN
        SIGNAL SQLSTATE '75000'
            SET MESSAGE_TEXT = 'Amount must be positive';
    END IF;
END@
```

## RESIGNAL (重抛异常)

```sql
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        RESIGNAL;
    END;

    INSERT INTO users(id) VALUES(NULL);
END@
```

## GET DIAGNOSTICS

```sql
BEGIN
    DECLARE v_sqlcode INT;
    DECLARE v_sqlstate CHAR(5);
    DECLARE v_msg VARCHAR(500);
    DECLARE v_rows INT;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1
            v_sqlstate = RETURNED_SQLSTATE,
            v_msg = MESSAGE_TEXT;
    END;

    INSERT INTO users(id, username) VALUES(1, 'test');
    GET DIAGNOSTICS v_rows = ROW_COUNT;
END@
```

## SQLCODE / SQLSTATE 条件

```sql
BEGIN
    DECLARE not_found CONDITION FOR SQLSTATE '02000';
    DECLARE CONTINUE HANDLER FOR not_found
        SET @not_found_flag = 1;

    DECLARE CONTINUE HANDLER FOR SQLWARNING
        SET @warning_flag = 1;
```

## 操作

```sql
END@
```

版本说明：
DB2 全版本 : DECLARE HANDLER, SIGNAL, GET DIAGNOSTICS
注意：DB2 遵循 SQL 标准的错误处理模型
注意：支持 CONTINUE, EXIT, UNDO 三种处理器
注意：SQLSTATE 前两位为类别（00=成功, 01=警告, 02=未找到）
限制：不支持 TRY/CATCH
限制：不支持 EXCEPTION WHEN (Oracle 风格)
