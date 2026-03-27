-- SAP HANA: Views
--
-- 参考资料:
--   [1] SAP HANA SQL Reference - CREATE VIEW
--       https://help.sap.com/docs/SAP_HANA_PLATFORM/4fe29514fd584807ac9f2a04f6754767/20d5fa9b75191014b2fe92141b7df228.html
--   [2] SAP HANA Documentation - SQL Views
--       https://help.sap.com/docs/SAP_HANA_PLATFORM/4fe29514fd584807ac9f2a04f6754767/20d5fa9b75191014b2fe92141b7df228.html
--   [3] SAP HANA Documentation - Calculation Views
--       https://help.sap.com/docs/SAP_HANA_PLATFORM

-- ============================================
-- 基本视图 (SQL View)
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

-- 带列别名的视图
CREATE VIEW order_summary (user_id, order_count, total_amount) AS
SELECT user_id, COUNT(*), SUM(amount)
FROM orders
GROUP BY user_id;

-- ============================================
-- 可更新视图 + WITH CHECK OPTION
-- SAP HANA 支持简单视图的 DML
-- ============================================
CREATE VIEW adult_users AS
SELECT id, username, email, age
FROM users
WHERE age >= 18
WITH CHECK OPTION;

-- 通过视图 DML
INSERT INTO adult_users VALUES (1, 'alice', 'alice@b.com', 25);
UPDATE adult_users SET email = 'new@b.com' WHERE id = 1;
DELETE FROM adult_users WHERE id = 1;

-- ============================================
-- 物化视图
-- SAP HANA 不支持传统的物化视图
-- ============================================
-- 替代方案：
-- 1. SAP HANA 内存计算引擎本身就是"物化"的（列式存储）
-- 2. Calculation View（通过 SAP HANA Studio 或 Web IDE 创建）
-- 3. 使用表 + 定时刷新

-- SAP HANA 的 Calculation View 是图形化建模的分析视图
-- 功能远超传统物化视图，但通过 IDE 创建，非 SQL DDL

-- ============================================
-- 删除视图
-- ============================================
DROP VIEW active_users;
DROP VIEW active_users CASCADE;

-- 限制：
-- 不支持 IF NOT EXISTS
-- 不支持物化视图（使用 Calculation View 替代）
-- Calculation View 通过 SAP HANA Studio 创建，非 SQL
-- 支持 WITH CHECK OPTION
-- SAP HANA 列式存储本身提供了物化视图类似的性能优势
