-- MySQL: 存储过程（5.0+）
--
-- 参考资料:
--   [1] MySQL 8.0 Reference Manual - CREATE PROCEDURE
--       https://dev.mysql.com/doc/refman/8.0/en/create-procedure.html
--   [2] MySQL 8.0 Reference Manual - CREATE FUNCTION
--       https://dev.mysql.com/doc/refman/8.0/en/create-function.html
--   [3] MySQL 8.0 Reference Manual - Stored Program Syntax
--       https://dev.mysql.com/doc/refman/8.0/en/sql-compound-statements.html

-- 创建存储过程
DELIMITER //
CREATE PROCEDURE get_user(IN p_username VARCHAR(64))
BEGIN
    SELECT * FROM users WHERE username = p_username;
END //
DELIMITER ;

-- 调用
CALL get_user('alice');

-- 带输出参数
DELIMITER //
CREATE PROCEDURE get_user_count(OUT p_count INT)
BEGIN
    SELECT COUNT(*) INTO p_count FROM users;
END //
DELIMITER ;

CALL get_user_count(@cnt);
SELECT @cnt;

-- INOUT 参数
DELIMITER //
CREATE PROCEDURE increment(INOUT p_val INT, IN p_step INT)
BEGIN
    SET p_val = p_val + p_step;
END //
DELIMITER ;

SET @v = 10;
CALL increment(@v, 5);
SELECT @v;  -- 15

-- 变量和流程控制
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
    ELSE
        UPDATE accounts SET balance = balance - p_amount WHERE id = p_from;
        UPDATE accounts SET balance = balance + p_amount WHERE id = p_to;
        COMMIT;
    END IF;
END //
DELIMITER ;

-- 游标
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
        -- 处理每一行
    END LOOP;
    CLOSE cur;
END //
DELIMITER ;

-- 删除存储过程
DROP PROCEDURE IF EXISTS get_user;

-- 创建函数
DELIMITER //
CREATE FUNCTION full_name(first VARCHAR(50), last VARCHAR(50))
RETURNS VARCHAR(101)
DETERMINISTIC
BEGIN
    RETURN CONCAT(first, ' ', last);
END //
DELIMITER ;

SELECT full_name('Alice', 'Smith');
