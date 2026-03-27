-- PolarDB: Error Handling
--
-- 参考资料:
--   [1] PolarDB for PostgreSQL Documentation
--       https://www.alibabacloud.com/help/en/polardb/polardb-for-postgresql/
--   [2] PolarDB for MySQL Documentation
--       https://www.alibabacloud.com/help/en/polardb/polardb-for-mysql/

-- ============================================================
-- PolarDB for PostgreSQL: EXCEPTION WHEN
-- ============================================================
CREATE OR REPLACE FUNCTION safe_op(p_a INT, p_b INT)
RETURNS INT AS $$
BEGIN
    RETURN p_a / p_b;
EXCEPTION
    WHEN division_by_zero THEN
        RAISE NOTICE 'Division by zero';
        RETURN NULL;
    WHEN OTHERS THEN
        RAISE NOTICE 'Error: %', SQLERRM;
        RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- PolarDB for MySQL: DECLARE HANDLER
-- ============================================================
DELIMITER //
CREATE PROCEDURE safe_insert(IN p_name VARCHAR(100))
BEGIN
    DECLARE EXIT HANDLER FOR 1062
        SELECT 'Duplicate entry' AS msg;
    INSERT INTO users(username) VALUES(p_name);
END //
DELIMITER ;

-- 注意：PolarDB 有 PostgreSQL 和 MySQL 两个版本
-- 注意：错误处理语法取决于对应的数据库引擎
-- 限制：兼容性取决于版本
