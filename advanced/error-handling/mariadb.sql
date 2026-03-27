-- MariaDB: Error Handling
--
-- 参考资料:
--   [1] MariaDB Knowledge Base - DECLARE HANDLER
--       https://mariadb.com/kb/en/declare-handler/
--   [2] MariaDB Knowledge Base - SIGNAL
--       https://mariadb.com/kb/en/signal/
--   [3] MariaDB Knowledge Base - GET DIAGNOSTICS
--       https://mariadb.com/kb/en/get-diagnostics/

-- ============================================================
-- DECLARE HANDLER (与 MySQL 兼容)
-- ============================================================
DELIMITER //
CREATE PROCEDURE safe_insert(IN p_name VARCHAR(100))
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1
            @sqlstate = RETURNED_SQLSTATE,
            @errno = MYSQL_ERRNO,
            @msg = MESSAGE_TEXT;
        SELECT @sqlstate, @errno, @msg;
    END;

    DECLARE CONTINUE HANDLER FOR 1062
        SELECT 'Duplicate key ignored' AS warning;

    INSERT INTO users(username) VALUES(p_name);
END //
DELIMITER ;

-- ============================================================
-- SIGNAL / RESIGNAL                                   -- 5.5+
-- ============================================================
DELIMITER //
CREATE PROCEDURE validate_input(IN p_age INT)
BEGIN
    IF p_age < 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Age cannot be negative';
    END IF;
END //
DELIMITER ;

-- ============================================================
-- GET DIAGNOSTICS                                     -- 10.0+
-- ============================================================
DELIMITER //
CREATE PROCEDURE diag_demo()
BEGIN
    DECLARE v_msg TEXT;
    DECLARE v_sqlstate CHAR(5);

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1
            v_sqlstate = RETURNED_SQLSTATE,
            v_msg = MESSAGE_TEXT;
        SELECT CONCAT('Error [', v_sqlstate, ']: ', v_msg) AS error_info;
    END;

    INSERT INTO nonexistent_table VALUES(1);
END //
DELIMITER ;

-- 版本说明：
--   MariaDB 5.5+ : SIGNAL / RESIGNAL
--   MariaDB 10.0+: GET DIAGNOSTICS (增强)
-- 注意：与 MySQL 错误处理语法基本一致
-- 注意：MariaDB 特有的错误码可能与 MySQL 不同
-- 限制：不支持 TRY/CATCH
