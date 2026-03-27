-- TDSQL: Dynamic SQL
--
-- 参考资料:
--   [1] TDSQL Documentation
--       https://cloud.tencent.com/document/product/557

-- ============================================================
-- PREPARE / EXECUTE / DEALLOCATE PREPARE (MySQL 兼容)
-- ============================================================
PREPARE stmt FROM 'SELECT * FROM users WHERE id = ?';
SET @user_id = 42;
EXECUTE stmt USING @user_id;
DEALLOCATE PREPARE stmt;

-- ============================================================
-- 存储过程中的动态 SQL
-- ============================================================
DELIMITER //
CREATE PROCEDURE dynamic_count(IN p_table VARCHAR(64))
BEGIN
    SET @sql = CONCAT('SELECT COUNT(*) AS cnt FROM ', p_table);
    PREPARE stmt FROM @sql;
    EXECUTE stmt;
    DEALLOCATE PREPARE stmt;
END //
DELIMITER ;

-- ============================================================
-- 参数化动态 SQL（防止 SQL 注入）
-- ============================================================
DELIMITER //
CREATE PROCEDURE safe_search(IN p_name VARCHAR(100))
BEGIN
    SET @sql = 'SELECT * FROM users WHERE username = ?';
    SET @val = p_name;
    PREPARE stmt FROM @sql;
    EXECUTE stmt USING @val;
    DEALLOCATE PREPARE stmt;
END //
DELIMITER ;

-- 注意：TDSQL 兼容 MySQL 协议和语法
-- 注意：PREPARE/EXECUTE 语法与 MySQL 一致
-- 限制：兼容性取决于具体版本
-- 限制：分布式场景下某些动态 DDL 可能有限制
