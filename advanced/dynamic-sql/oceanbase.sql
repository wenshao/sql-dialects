-- OceanBase: Dynamic SQL
--
-- 参考资料:
--   [1] OceanBase Documentation - PL
--       https://www.oceanbase.com/docs/common-oceanbase-database-cn
--   [2] OceanBase Documentation - MySQL 模式
--       https://www.oceanbase.com/docs/common-oceanbase-database-cn

-- ============================================================
-- MySQL 模式: PREPARE / EXECUTE / DEALLOCATE PREPARE
-- ============================================================
PREPARE stmt FROM 'SELECT * FROM users WHERE id = ?';
SET @user_id = 42;
EXECUTE stmt USING @user_id;
DEALLOCATE PREPARE stmt;

-- ============================================================
-- Oracle 模式: EXECUTE IMMEDIATE
-- ============================================================
DECLARE
    v_count NUMBER;
BEGIN
    EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM users' INTO v_count;
    DBMS_OUTPUT.PUT_LINE('Count: ' || v_count);
END;
/

-- ============================================================
-- Oracle 模式: 参数化 EXECUTE IMMEDIATE
-- ============================================================
DECLARE
    v_name VARCHAR2(100);
BEGIN
    EXECUTE IMMEDIATE
        'SELECT username FROM users WHERE id = :1'
        INTO v_name
        USING 42;
END;
/

-- ============================================================
-- 存储过程中的动态 SQL (MySQL 模式)
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

-- 注意：OceanBase 支持 MySQL 和 Oracle 两种兼容模式
-- 注意：MySQL 模式使用 PREPARE/EXECUTE，Oracle 模式使用 EXECUTE IMMEDIATE
-- 注意：使用参数绑定防止 SQL 注入
-- 限制：兼容性取决于具体版本
