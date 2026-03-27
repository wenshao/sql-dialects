-- MySQL: Views
--
-- 参考资料:
--   [1] MySQL 8.0 Reference Manual - CREATE VIEW
--       https://dev.mysql.com/doc/refman/8.0/en/create-view.html
--   [2] MySQL 8.0 Reference Manual - Updatable Views
--       https://dev.mysql.com/doc/refman/8.0/en/view-updatability.html
--   [3] MySQL 8.0 Reference Manual - WITH CHECK OPTION
--       https://dev.mysql.com/doc/refman/8.0/en/view-check-option.html

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
WITH CASCADED CHECK OPTION;                  -- CASCADED（默认）| LOCAL

-- WITH LOCAL CHECK OPTION
CREATE VIEW premium_users AS
SELECT id, username, email, age
FROM adult_users
WHERE balance > 1000
WITH LOCAL CHECK OPTION;

-- 通过视图 DML
INSERT INTO adult_users (username, email, age) VALUES ('alice', 'alice@b.com', 25);
UPDATE adult_users SET email = 'new@b.com' WHERE id = 1;
DELETE FROM adult_users WHERE id = 1;

-- 不可更新的视图条件：
-- 1. 使用 AGGREGATE 函数（SUM, COUNT, MAX 等）
-- 2. 使用 DISTINCT
-- 3. 使用 GROUP BY / HAVING
-- 4. 使用 UNION / UNION ALL
-- 5. 使用子查询 in SELECT list
-- 6. 使用 JOIN（某些 JOIN 可更新）
-- 7. 不可更新的视图引用
-- 8. ALGORITHM = TEMPTABLE

-- ============================================
-- 物化视图
-- MySQL 不支持物化视图
-- ============================================
-- 替代方案 1：表 + EVENT 定时刷新
CREATE TABLE mv_order_summary (
    user_id     BIGINT PRIMARY KEY,
    order_count INT,
    total_amount DECIMAL(18,2),
    refreshed_at DATETIME DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

CREATE EVENT refresh_mv_order_summary
ON SCHEDULE EVERY 1 HOUR
DO
BEGIN
    TRUNCATE TABLE mv_order_summary;
    INSERT INTO mv_order_summary (user_id, order_count, total_amount)
    SELECT user_id, COUNT(*), SUM(amount)
    FROM orders
    GROUP BY user_id;
END;

-- 替代方案 2：使用触发器维护汇总表

-- ============================================
-- 删除视图
-- ============================================
DROP VIEW active_users;
DROP VIEW IF EXISTS active_users;

-- 限制：
-- 不支持物化视图
-- TEMPTABLE 算法的视图不可更新
-- 视图中不能使用用户变量
-- 视图中不能引用临时表
-- 视图的 SELECT 不能包含 INTO 子句
