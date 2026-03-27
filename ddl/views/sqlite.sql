-- SQLite: Views
--
-- 参考资料:
--   [1] SQLite Documentation - CREATE VIEW
--       https://www.sqlite.org/lang_createview.html
--   [2] SQLite Documentation - DROP VIEW
--       https://www.sqlite.org/lang_dropview.html

-- ============================================
-- 基本视图
-- ============================================
CREATE VIEW active_users AS
SELECT id, username, email, created_at
FROM users
WHERE age >= 18;

-- IF NOT EXISTS
CREATE VIEW IF NOT EXISTS active_users AS
SELECT id, username, email, created_at
FROM users
WHERE age >= 18;

-- 临时视图
CREATE TEMPORARY VIEW temp_active_users AS
SELECT id, username, email
FROM users
WHERE age >= 18;

-- ============================================
-- 可更新视图
-- SQLite 不支持可更新视图（不能对视图 INSERT/UPDATE/DELETE）
-- ============================================
-- 替代方案：使用 INSTEAD OF 触发器

CREATE VIEW order_detail AS
SELECT o.id, o.amount, u.username
FROM orders o JOIN users u ON o.user_id = u.id;

-- 通过 INSTEAD OF 触发器使视图可写
CREATE TRIGGER trg_order_detail_insert
INSTEAD OF INSERT ON order_detail
BEGIN
    INSERT INTO orders (id, amount) VALUES (NEW.id, NEW.amount);
END;

CREATE TRIGGER trg_order_detail_update
INSTEAD OF UPDATE ON order_detail
BEGIN
    UPDATE orders SET amount = NEW.amount WHERE id = OLD.id;
END;

CREATE TRIGGER trg_order_detail_delete
INSTEAD OF DELETE ON order_detail
BEGIN
    DELETE FROM orders WHERE id = OLD.id;
END;

-- ============================================
-- 物化视图
-- SQLite 不支持物化视图
-- ============================================
-- 替代方案：使用表 + 手动刷新
CREATE TABLE mv_order_summary (
    user_id     INTEGER PRIMARY KEY,
    order_count INTEGER,
    total_amount REAL
);

-- 刷新（手动执行）
DELETE FROM mv_order_summary;
INSERT INTO mv_order_summary
SELECT user_id, COUNT(*), SUM(amount)
FROM orders
GROUP BY user_id;

-- ============================================
-- 删除视图
-- ============================================
DROP VIEW active_users;
DROP VIEW IF EXISTS active_users;

-- 限制：
-- 不支持 CREATE OR REPLACE VIEW（需要 DROP + CREATE）
-- 不支持物化视图
-- 不支持 WITH CHECK OPTION
-- 视图不可直接更新（需要 INSTEAD OF 触发器）
-- 不支持 ALTER VIEW
