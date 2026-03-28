-- MariaDB: 错误处理
-- 与 MySQL 语法一致, 在存储程序中使用
--
-- 参考资料:
--   [1] MariaDB Knowledge Base - DECLARE HANDLER
--       https://mariadb.com/kb/en/declare-handler/

-- ============================================================
-- 1. DECLARE HANDLER
-- ============================================================
DELIMITER //
CREATE PROCEDURE safe_insert(IN p_username VARCHAR(64), IN p_email VARCHAR(255))
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SELECT 'Error occurred, transaction rolled back' AS message;
    END;

    DECLARE EXIT HANDLER FOR 1062  -- Duplicate key
    BEGIN
        SELECT 'Duplicate entry' AS message;
    END;

    START TRANSACTION;
    INSERT INTO users (username, email) VALUES (p_username, p_email);
    COMMIT;
    SELECT 'Success' AS message;
END //
DELIMITER ;

-- ============================================================
-- 2. SIGNAL / RESIGNAL (10.0+)
-- ============================================================
DELIMITER //
CREATE PROCEDURE validate_age(IN p_age INT)
BEGIN
    IF p_age < 0 OR p_age > 200 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Invalid age value',
            MYSQL_ERRNO = 1644;
    END IF;
END //
DELIMITER ;

-- ============================================================
-- 3. GET DIAGNOSTICS
-- ============================================================
DELIMITER //
CREATE PROCEDURE check_insert()
BEGIN
    DECLARE v_errno INT;
    DECLARE v_msg TEXT;

    DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1
            v_errno = MYSQL_ERRNO,
            v_msg = MESSAGE_TEXT;
        SELECT v_errno AS error_code, v_msg AS error_message;
    END;

    INSERT INTO users (username, email) VALUES ('test', 'test@test.com');
END //
DELIMITER ;

-- ============================================================
-- 4. Oracle 兼容模式的异常处理 (10.3+)
-- ============================================================
-- SET sql_mode=ORACLE;
-- EXCEPTION WHEN NO_DATA_FOUND THEN ...
-- EXCEPTION WHEN DUP_VAL_ON_INDEX THEN ...
-- MariaDB 独有: 支持 Oracle 风格的命名异常

-- ============================================================
-- 5. 对引擎开发者的启示
-- ============================================================
-- MySQL/MariaDB 的错误处理基于 SQLSTATE + 错误号:
--   SQLSTATE: 5 字符标准错误代码 (SQL 标准)
--   MYSQL_ERRNO: MySQL/MariaDB 特有的数字错误号
-- 对比 PostgreSQL: RAISE EXCEPTION / RAISE NOTICE (更灵活)
-- 对比 Oracle: EXCEPTION WHEN ... THEN (更结构化)
-- 实现要点: 需要在执行器中维护异常处理器栈 (handler stack)
