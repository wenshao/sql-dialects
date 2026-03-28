# TiDB: 存储过程

> 参考资料:
> - [TiDB SQL Reference](https://docs.pingcap.com/tidb/stable/sql-statement-overview)
> - [TiDB - MySQL Compatibility](https://docs.pingcap.com/tidb/stable/mysql-compatibility)
> - [TiDB - Functions and Operators](https://docs.pingcap.com/tidb/stable/functions-and-operators-overview)

**引擎定位**: 分布式 HTAP 数据库，兼容 MySQL 协议。基于 TiKV 行存 + TiFlash 列存，Raft 共识。

```sql
DELIMITER //
CREATE PROCEDURE get_user(IN p_username VARCHAR(64))
BEGIN
    SELECT * FROM users WHERE username = p_username;
END //
DELIMITER ;

```

Call (same as MySQL)
```sql
CALL get_user('alice');

```

OUT parameter (supported)
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

INOUT parameter (supported)
```sql
DELIMITER //
CREATE PROCEDURE increment(INOUT p_val INT, IN p_step INT)
BEGIN
    SET p_val = p_val + p_step;
END //
DELIMITER ;

```

Variable declaration (supported)
```sql
DELIMITER //
CREATE PROCEDURE check_balance(IN p_user_id BIGINT)
BEGIN
    DECLARE v_balance DECIMAL(10,2);
    SELECT balance INTO v_balance FROM accounts WHERE id = p_user_id;
    IF v_balance < 0 THEN
        SELECT 'Negative balance' AS warning;
    END IF;
END //
DELIMITER ;

```

IF / ELSEIF / ELSE (supported)
```sql
DELIMITER //
CREATE PROCEDURE categorize(IN p_age INT, OUT p_cat VARCHAR(20))
BEGIN
    IF p_age < 18 THEN
        SET p_cat = 'minor';
    ELSEIF p_age < 65 THEN
        SET p_cat = 'adult';
    ELSE
        SET p_cat = 'senior';
    END IF;
END //
DELIMITER ;

```

WHILE loop (supported)
```sql
DELIMITER //
CREATE PROCEDURE count_loop(IN p_max INT)
BEGIN
    DECLARE v_i INT DEFAULT 0;
    WHILE v_i < p_max DO
        SET v_i = v_i + 1;
    END WHILE;
    SELECT v_i;
END //
DELIMITER ;

```

Create function (supported with limitations)
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

Drop (same as MySQL)
```sql
DROP PROCEDURE IF EXISTS get_user;
DROP FUNCTION IF EXISTS full_name;

```

Limitations:
Cursors: supported since 7.0+ (not available in earlier versions)
SIGNAL/RESIGNAL: limited support
Complex flow control (nested loops, REPEAT, LOOP): supported but may have edge cases
Stored procedures cannot contain DDL statements in transactions
Dynamic SQL (PREPARE/EXECUTE) inside procedures: limited support
No INSTEAD OF triggers
Performance may differ from MySQL for complex procedures
HANDLER (CONTINUE/EXIT): basic support
Recursive stored procedure calls: limited depth
Temporary tables inside procedures: supported
Transaction control (START TRANSACTION, COMMIT, ROLLBACK) inside procedures: supported
