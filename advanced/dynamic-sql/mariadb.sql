-- MariaDB: Dynamic SQL
--
-- 参考资料:
--   [1] MariaDB Knowledge Base - PREPARE
--       https://mariadb.com/kb/en/prepare-statement/
--   [2] MariaDB Knowledge Base - EXECUTE
--       https://mariadb.com/kb/en/execute-statement/
--   [3] MariaDB Knowledge Base - EXECUTE IMMEDIATE
--       https://mariadb.com/kb/en/execute-immediate/

-- ============================================================
-- PREPARE / EXECUTE / DEALLOCATE PREPARE
-- ============================================================
PREPARE stmt FROM 'SELECT * FROM users WHERE id = ?';
SET @user_id = 42;
EXECUTE stmt USING @user_id;
DEALLOCATE PREPARE stmt;

-- ============================================================
-- EXECUTE IMMEDIATE (MariaDB 10.2.3+)
-- ============================================================
-- MariaDB 独有功能，MySQL 不支持
EXECUTE IMMEDIATE 'SELECT * FROM users WHERE id = 1';

-- 带参数
EXECUTE IMMEDIATE 'SELECT * FROM users WHERE age > ? AND status = ?'
    USING 18, 'active';

-- 在存储过程中使用
DELIMITER //
CREATE PROCEDURE dynamic_count(IN p_table VARCHAR(64))
BEGIN
    EXECUTE IMMEDIATE CONCAT('SELECT COUNT(*) AS cnt FROM ', p_table);
END //
DELIMITER ;

-- ============================================================
-- 存储过程中的动态 SQL
-- ============================================================
DELIMITER //
CREATE PROCEDURE search_by_column(
    IN p_table VARCHAR(64),
    IN p_column VARCHAR(64),
    IN p_value VARCHAR(255)
)
BEGIN
    SET @sql = CONCAT('SELECT * FROM `', p_table, '` WHERE `', p_column, '` = ?');
    SET @val = p_value;
    PREPARE stmt FROM @sql;
    EXECUTE stmt USING @val;
    DEALLOCATE PREPARE stmt;
END //
DELIMITER ;

-- ============================================================
-- 参数化动态 SQL（防止 SQL 注入）
-- ============================================================
DELIMITER //
CREATE PROCEDURE safe_search(IN p_name VARCHAR(100), IN p_age INT)
BEGIN
    SET @sql = 'SELECT * FROM users WHERE username = ? AND age > ?';
    SET @n = p_name;
    SET @a = p_age;
    PREPARE stmt FROM @sql;
    EXECUTE stmt USING @n, @a;
    DEALLOCATE PREPARE stmt;
END //
DELIMITER ;

-- ============================================================
-- 动态 DDL
-- ============================================================
DELIMITER //
CREATE PROCEDURE create_monthly_table(IN p_year INT, IN p_month INT)
BEGIN
    EXECUTE IMMEDIATE CONCAT(
        'CREATE TABLE IF NOT EXISTS logs_', p_year, '_', LPAD(p_month, 2, '0'),
        ' LIKE logs'
    );
END //
DELIMITER ;

-- 版本说明：
--   MariaDB 5.x+    : PREPARE / EXECUTE / DEALLOCATE PREPARE
--   MariaDB 10.2.3+ : EXECUTE IMMEDIATE
-- 注意：EXECUTE IMMEDIATE 是 MariaDB 相对 MySQL 的独有功能
-- 注意：PREPARE 只能使用用户变量 (@var)，不能使用局部变量
-- 注意：始终使用参数绑定 (?) 防止 SQL 注入
-- 限制：PREPARE 中的 SQL 类型有限制（不支持所有语句类型）
