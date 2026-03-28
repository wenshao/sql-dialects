# TDSQL: 存储过程

TDSQL distributed MySQL-compatible syntax.

> 参考资料:
> - [TDSQL-C MySQL Documentation](https://cloud.tencent.com/document/product/1003)
> - [TDSQL MySQL Documentation](https://cloud.tencent.com/document/product/557)


## 创建存储过程

```sql
DELIMITER //
CREATE PROCEDURE get_user(IN p_username VARCHAR(64))
BEGIN
    SELECT * FROM users WHERE username = p_username;
END //
DELIMITER ;
```

## 调用

```sql
CALL get_user('alice');
```

## 带输出参数

```sql
DELIMITER //
CREATE PROCEDURE get_user_count(OUT p_count INT)
BEGIN
    SELECT COUNT(*) INTO p_count FROM users;
END //
DELIMITER ;

CALL get_user_count(@cnt);
SELECT @cnt;
```

## INOUT 参数

```sql
DELIMITER //
CREATE PROCEDURE increment(INOUT p_val INT, IN p_step INT)
BEGIN
    SET p_val = p_val + p_step;
END //
DELIMITER ;
```

## 变量和流程控制

```sql
DELIMITER //
CREATE PROCEDURE transfer(
    IN p_from BIGINT, IN p_to BIGINT, IN p_amount DECIMAL(10,2)
)
BEGIN
    DECLARE v_balance DECIMAL(10,2);

    START TRANSACTION;

    SELECT balance INTO v_balance FROM accounts WHERE id = p_from FOR UPDATE;

    IF v_balance < p_amount THEN
        ROLLBACK;
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Insufficient balance';
    END IF;

    UPDATE accounts SET balance = balance - p_amount WHERE id = p_from;
    UPDATE accounts SET balance = balance + p_amount WHERE id = p_to;

    COMMIT;
END //
DELIMITER ;
```

## 游标

```sql
DELIMITER //
CREATE PROCEDURE process_users()
BEGIN
    DECLARE v_done INT DEFAULT FALSE;
    DECLARE v_username VARCHAR(64);
    DECLARE cur CURSOR FOR SELECT username FROM users;
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_done = TRUE;

    OPEN cur;
    read_loop: LOOP
        FETCH cur INTO v_username;
        IF v_done THEN LEAVE read_loop; END IF;
    END LOOP;
    CLOSE cur;
END //
DELIMITER ;
```

## 创建函数

```sql
DELIMITER //
CREATE FUNCTION full_name(first VARCHAR(50), last VARCHAR(50))
RETURNS VARCHAR(101)
DETERMINISTIC
BEGIN
    RETURN CONCAT(first, ' ', last);
END //
DELIMITER ;
```

## 删除

```sql
DROP PROCEDURE IF EXISTS get_user;
DROP FUNCTION IF EXISTS full_name;
```

注意事项：
存储过程语法与 MySQL 完全兼容
存储过程中的 SQL 遵循分片路由规则
分布式事务在存储过程中使用 XA 协议
存储过程在代理层执行，非分片级别
