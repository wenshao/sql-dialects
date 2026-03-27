-- TiDB: Dynamic SQL
--
-- 参考资料:
--   [1] TiDB Documentation - PREPARE
--       https://docs.pingcap.com/tidb/stable/sql-statement-prepare
--   [2] TiDB Documentation - EXECUTE
--       https://docs.pingcap.com/tidb/stable/sql-statement-execute
--   [3] TiDB Documentation - DEALLOCATE
--       https://docs.pingcap.com/tidb/stable/sql-statement-deallocate

-- ============================================================
-- PREPARE / EXECUTE / DEALLOCATE PREPARE (MySQL 兼容)
-- ============================================================
PREPARE stmt FROM 'SELECT * FROM users WHERE id = ?';
SET @user_id = 42;
EXECUTE stmt USING @user_id;
DEALLOCATE PREPARE stmt;

-- 多参数
PREPARE stmt FROM 'SELECT * FROM users WHERE age > ? AND status = ?';
SET @age = 18;
SET @status = 'active';
EXECUTE stmt USING @age, @status;
DEALLOCATE PREPARE stmt;

-- ============================================================
-- 存储过程中的动态 SQL (MySQL 兼容)
-- ============================================================
DELIMITER //
CREATE PROCEDURE dynamic_count(IN p_table VARCHAR(64))
BEGIN
    SET @sql = CONCAT('SELECT COUNT(*) AS cnt FROM `', p_table, '`');
    PREPARE stmt FROM @sql;
    EXECUTE stmt;
    DEALLOCATE PREPARE stmt;
END //
DELIMITER ;

-- ============================================================
-- 参数化查询（防止 SQL 注入）
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
CREATE PROCEDURE create_archive(IN p_year INT)
BEGIN
    SET @sql = CONCAT('CREATE TABLE IF NOT EXISTS orders_', p_year, ' LIKE orders');
    PREPARE stmt FROM @sql;
    EXECUTE stmt;
    DEALLOCATE PREPARE stmt;
END //
DELIMITER ;

-- 版本说明：
--   TiDB 全版本 : PREPARE / EXECUTE / DEALLOCATE PREPARE
-- 注意：TiDB 兼容 MySQL 协议，动态 SQL 语法一致
-- 注意：使用参数占位符 (?) 防止 SQL 注入
-- 注意：PREPARE 只能使用用户变量 (@var)
-- 限制：不支持 EXECUTE IMMEDIATE
-- 限制：某些 MySQL 存储过程特性可能不完全兼容
