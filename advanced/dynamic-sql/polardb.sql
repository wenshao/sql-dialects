-- PolarDB: Dynamic SQL
--
-- 参考资料:
--   [1] PolarDB for PostgreSQL Documentation
--       https://www.alibabacloud.com/help/en/polardb/polardb-for-postgresql/
--   [2] PolarDB for MySQL Documentation
--       https://www.alibabacloud.com/help/en/polardb/polardb-for-mysql/

-- ============================================================
-- PolarDB for PostgreSQL: PREPARE / EXECUTE
-- ============================================================
PREPARE user_query(INT) AS SELECT * FROM users WHERE age > $1;
EXECUTE user_query(25);
DEALLOCATE user_query;

-- PL/pgSQL EXECUTE
CREATE OR REPLACE FUNCTION count_rows(p_table TEXT)
RETURNS BIGINT AS $$
DECLARE
    result BIGINT;
BEGIN
    EXECUTE 'SELECT COUNT(*) FROM ' || quote_ident(p_table) INTO result;
    RETURN result;
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- PolarDB for MySQL: PREPARE / EXECUTE
-- ============================================================
PREPARE stmt FROM 'SELECT * FROM users WHERE id = ?';
SET @user_id = 42;
EXECUTE stmt USING @user_id;
DEALLOCATE PREPARE stmt;

-- 存储过程中的动态 SQL (MySQL 兼容)
DELIMITER //
CREATE PROCEDURE dynamic_count(IN p_table VARCHAR(64))
BEGIN
    SET @sql = CONCAT('SELECT COUNT(*) AS cnt FROM ', p_table);
    PREPARE stmt FROM @sql;
    EXECUTE stmt;
    DEALLOCATE PREPARE stmt;
END //
DELIMITER ;

-- 注意：PolarDB 有 PostgreSQL 和 MySQL 两个版本
-- 注意：PostgreSQL 版兼容 PL/pgSQL 动态 SQL
-- 注意：MySQL 版兼容 MySQL PREPARE/EXECUTE
-- 限制：某些高级功能取决于版本和兼容级别
