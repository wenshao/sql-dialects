-- Derby: Views
--
-- 参考资料:
--   [1] Apache Derby Documentation - CREATE VIEW
--       https://db.apache.org/derby/docs/10.16/ref/rrefsqlj15446.html
--   [2] Apache Derby Documentation - Views
--       https://db.apache.org/derby/docs/10.16/devguide/cdevspecial41021.html

-- ============================================
-- 基本视图
-- ============================================
CREATE VIEW active_users AS
SELECT id, username, email, created_at
FROM users
WHERE age >= 18;

-- ============================================
-- 可更新视图 + WITH CHECK OPTION
-- Derby 支持可更新的单表视图
-- ============================================
CREATE VIEW adult_users AS
SELECT id, username, email, age
FROM users
WHERE age >= 18
WITH CHECK OPTION;

-- 通过视图插入和更新
INSERT INTO adult_users (id, username, email, age) VALUES (1, 'alice', 'alice@example.com', 25);
UPDATE adult_users SET email = 'newemail@example.com' WHERE id = 1;

-- ============================================
-- 物化视图
-- Derby 不支持物化视图
-- ============================================
-- 替代方案：手动创建汇总表 + 触发器维护
CREATE TABLE mv_order_summary (
    user_id     BIGINT PRIMARY KEY,
    order_count INTEGER,
    total_amount DECIMAL(18,2)
);
-- 使用应用层或定时任务维护

-- ============================================
-- 删除视图
-- ============================================
DROP VIEW active_users;

-- 限制：
-- 不支持 CREATE OR REPLACE VIEW
-- 不支持 IF NOT EXISTS
-- 不支持物化视图
-- 不支持 CASCADE 删除
-- 可更新视图仅限于简单单表查询
-- 不支持在视图上创建触发器
