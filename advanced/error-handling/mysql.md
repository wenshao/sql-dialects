# MySQL: 错误处理

> 参考资料:
> - [MySQL 8.0 Reference Manual - DECLARE HANDLER](https://dev.mysql.com/doc/refman/8.0/en/declare-handler.html)
> - [MySQL 8.0 Reference Manual - SIGNAL / RESIGNAL](https://dev.mysql.com/doc/refman/8.0/en/signal.html)
> - [MySQL 8.0 Reference Manual - GET DIAGNOSTICS](https://dev.mysql.com/doc/refman/8.0/en/get-diagnostics.html)

## DECLARE HANDLER (异常处理器)

```sql
DELIMITER //
CREATE PROCEDURE safe_insert(IN p_name VARCHAR(100), IN p_email VARCHAR(255))
BEGIN
    -- 声明处理器
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SELECT 'Error occurred' AS message;
    END;

    START TRANSACTION;
    INSERT INTO users(username, email) VALUES(p_name, p_email);
    COMMIT;
    SELECT 'Success' AS message;
END //
DELIMITER ;
```

## CONTINUE HANDLER (继续执行)

```sql
DELIMITER //
CREATE PROCEDURE batch_insert()
BEGIN
    DECLARE i INT DEFAULT 1;
    DECLARE dup_found INT DEFAULT 0;

    DECLARE CONTINUE HANDLER FOR 1062  -- 重复键错误码
        SET dup_found = dup_found + 1;

    WHILE i <= 100 DO
        INSERT IGNORE INTO users(id, username)
        VALUES(i, CONCAT('user_', i));
        SET i = i + 1;
    END WHILE;

    SELECT CONCAT('Completed. Duplicates skipped: ', dup_found) AS result;
END //
DELIMITER ;
```

## 命名条件

```sql
DELIMITER //
CREATE PROCEDURE named_condition_demo()
BEGIN
    DECLARE duplicate_entry CONDITION FOR 1062;
    DECLARE table_not_found CONDITION FOR SQLSTATE '42S02';

    DECLARE EXIT HANDLER FOR duplicate_entry
    BEGIN
        SELECT 'Duplicate key error' AS error_msg;
    END;

    DECLARE EXIT HANDLER FOR table_not_found
    BEGIN
        SELECT 'Table does not exist' AS error_msg;
    END;

    INSERT INTO users(id, username) VALUES(1, 'test');
END //
DELIMITER ;
```

## SIGNAL (主动抛出异常)                               -- 5.5+

```sql
DELIMITER //
CREATE PROCEDURE validate_age(IN p_age INT)
BEGIN
    IF p_age < 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Age cannot be negative',
                MYSQL_ERRNO = 1644;
    ELSEIF p_age > 200 THEN
        SIGNAL SQLSTATE '01000'
            SET MESSAGE_TEXT = 'Suspicious age value';  -- 警告
    END IF;

    INSERT INTO users(age) VALUES(p_age);
END //
DELIMITER ;
```

## RESIGNAL (修改并重抛异常)                           -- 5.5+

```sql
DELIMITER //
CREATE PROCEDURE resignal_demo()
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        -- 修改错误信息并重新抛出
        RESIGNAL SET MESSAGE_TEXT = 'Custom wrapper: operation failed';
    END;
```

触发错误
```sql
    INSERT INTO users(id, username) VALUES(NULL, NULL);
END //
DELIMITER ;
```

## GET DIAGNOSTICS (获取错误详细信息)                   -- 5.6+

```sql
DELIMITER //
CREATE PROCEDURE diagnostics_demo()
BEGIN
    DECLARE v_errno INT;
    DECLARE v_msg VARCHAR(255);
    DECLARE v_sqlstate CHAR(5);
    DECLARE v_count INT;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS v_count = NUMBER;
        GET DIAGNOSTICS CONDITION 1
            v_sqlstate = RETURNED_SQLSTATE,
            v_errno = MYSQL_ERRNO,
            v_msg = MESSAGE_TEXT;

        SELECT v_sqlstate AS sqlstate,
               v_errno AS error_code,
               v_msg AS error_message,
               v_count AS condition_count;
```

记录错误日志
```sql
        INSERT INTO error_log(sqlstate, errno, message, created_at)
        VALUES(v_sqlstate, v_errno, v_msg, NOW());
    END;
```

触发错误
```sql
    INSERT INTO users(id) VALUES(NULL);
END //
DELIMITER ;
```

## 多层嵌套处理器

```sql
DELIMITER //
CREATE PROCEDURE nested_handler_demo()
BEGIN
    DECLARE outer_handler_called BOOLEAN DEFAULT FALSE;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        SET outer_handler_called = TRUE;
        SELECT 'Outer handler caught error' AS msg;
    END;
```

内层块有自己的处理器
```sql
    BEGIN
        DECLARE CONTINUE HANDLER FOR 1062
        BEGIN
            SELECT 'Inner handler: duplicate key ignored' AS msg;
        END;

        INSERT INTO users(id, username) VALUES(1, 'test');
        INSERT INTO users(id, username) VALUES(1, 'test');  -- 重复，内层处理
    END;
```

这里的错误由外层处理器处理
```sql
    INSERT INTO nonexistent_table(id) VALUES(1);
END //
DELIMITER ;
```

## 自定义错误码和消息

```sql
DELIMITER //
CREATE PROCEDURE validate_order(IN p_amount DECIMAL(10,2))
BEGIN
    IF p_amount <= 0 THEN
        SIGNAL SQLSTATE '45001'
            SET MESSAGE_TEXT = 'Order amount must be positive',
                MYSQL_ERRNO = 5001;
    ELSEIF p_amount > 999999.99 THEN
        SIGNAL SQLSTATE '45002'
            SET MESSAGE_TEXT = 'Order amount exceeds maximum limit',
                MYSQL_ERRNO = 5002;
    END IF;
END //
DELIMITER ;
```

版本说明：
  MySQL 5.0+ : DECLARE HANDLER
  MySQL 5.5+ : SIGNAL / RESIGNAL
  MySQL 5.6+ : GET DIAGNOSTICS
注意：HANDLER 类型：CONTINUE（继续）, EXIT（退出当前 BEGIN...END 块）
注意：HANDLER 条件：SQLSTATE, MySQL错误码, 命名条件, SQLWARNING, NOT FOUND, SQLEXCEPTION
注意：SIGNAL 自定义错误使用 SQLSTATE '45000' 到 '45999'
注意：RESIGNAL 不带参数会原样重抛当前异常
限制：不支持 TRY/CATCH 语法
限制：不支持 EXCEPTION WHEN 语法
