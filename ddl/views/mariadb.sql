-- MariaDB: Views
--
-- 参考资料:
--   [1] MariaDB Documentation - CREATE VIEW
--       https://mariadb.com/kb/en/create-view/
--   [2] MariaDB Documentation - Updatable Views
--       https://mariadb.com/kb/en/updatable-views/
--   [3] MariaDB Documentation - WITH CHECK OPTION
--       https://mariadb.com/kb/en/view-algorithms/

-- ============================================
-- 基本视图
-- ============================================
CREATE VIEW active_users AS
SELECT id, username, email, created_at
FROM users
WHERE age >= 18;

-- CREATE OR REPLACE VIEW
CREATE OR REPLACE VIEW active_users AS
SELECT id, username, email, created_at
FROM users
WHERE age >= 18;

-- IF NOT EXISTS
CREATE VIEW IF NOT EXISTS active_users AS
SELECT id, username, email, created_at
FROM users
WHERE age >= 18;

-- 指定算法和安全性
CREATE
    ALGORITHM = MERGE                        -- MERGE | TEMPTABLE | UNDEFINED
    DEFINER = 'admin'@'localhost'
    SQL SECURITY DEFINER                     -- DEFINER | INVOKER
VIEW active_users AS
SELECT id, username, email, created_at
FROM users
WHERE age >= 18;

-- ============================================
-- 可更新视图 + WITH CHECK OPTION
-- ============================================
CREATE VIEW adult_users AS
SELECT id, username, email, age
FROM users
WHERE age >= 18
WITH CHECK OPTION;                           -- 默认 CASCADED

-- WITH LOCAL CHECK OPTION
CREATE VIEW premium_users AS
SELECT id, username, email, age
FROM adult_users
WHERE balance > 1000
WITH LOCAL CHECK OPTION;

-- 通过视图进行 DML
INSERT INTO adult_users (username, email, age) VALUES ('alice', 'alice@b.com', 25);
UPDATE adult_users SET email = 'new@b.com' WHERE id = 1;
DELETE FROM adult_users WHERE id = 1;

-- ============================================
-- 物化视图
-- MariaDB 不支持原生物化视图
-- ============================================
-- 替代方案 1：表 + 定时事件（EVENT）
CREATE TABLE mv_order_summary (
    user_id     BIGINT PRIMARY KEY,
    order_count INT,
    total_amount DECIMAL(18,2)
) ENGINE=InnoDB;

DELIMITER //
CREATE EVENT refresh_mv_order_summary
ON SCHEDULE EVERY 1 HOUR
DO
BEGIN
    TRUNCATE TABLE mv_order_summary;
    INSERT INTO mv_order_summary
    SELECT user_id, COUNT(*), SUM(amount)
    FROM orders
    GROUP BY user_id;
END //
DELIMITER ;

-- 替代方案 2：使用触发器维护汇总表

-- ============================================
-- 删除视图
-- ============================================
DROP VIEW active_users;
DROP VIEW IF EXISTS active_users;

-- 限制：
-- 不支持物化视图（使用 EVENT + 表替代）
-- TEMPTABLE 算法的视图不可更新
-- 带聚合、DISTINCT、GROUP BY、UNION 的视图不可更新
-- 多表 JOIN 视图的可更新性有限
