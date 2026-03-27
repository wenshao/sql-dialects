-- DB2: Views
--
-- 参考资料:
--   [1] IBM DB2 Documentation - CREATE VIEW
--       https://www.ibm.com/docs/en/db2/11.5?topic=statements-create-view
--   [2] IBM DB2 Documentation - Materialized Query Tables (MQT)
--       https://www.ibm.com/docs/en/db2/11.5?topic=tables-materialized-query
--   [3] IBM DB2 Documentation - Updatable Views
--       https://www.ibm.com/docs/en/db2/11.5?topic=views-updatable-deletable

-- ============================================
-- 基本视图
-- ============================================
CREATE VIEW active_users AS
SELECT id, username, email, created_at
FROM users
WHERE age >= 18;

-- CREATE OR REPLACE VIEW（DB2 11.1+）
CREATE OR REPLACE VIEW active_users AS
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
WITH CASCADED CHECK OPTION;
-- CASCADED：检查当前视图及所有基础视图的条件
-- LOCAL：仅检查当前视图的条件

CREATE VIEW premium_adults AS
SELECT id, username, email, age, balance
FROM adult_users
WHERE balance > 1000
WITH LOCAL CHECK OPTION;

-- ============================================
-- 物化查询表 (MQT / Materialized Query Table)
-- DB2 使用 MQT 代替物化视图
-- ============================================

-- REFRESH DEFERRED：手动刷新
CREATE TABLE mv_order_summary AS (
    SELECT user_id, COUNT(*) AS order_count, SUM(amount) AS total_amount
    FROM orders
    GROUP BY user_id
) DATA INITIALLY DEFERRED
  REFRESH DEFERRED
  MAINTAINED BY SYSTEM;

-- 刷新 MQT
REFRESH TABLE mv_order_summary;

-- REFRESH IMMEDIATE：自动维护（DML 时自动更新）
CREATE TABLE mv_order_live AS (
    SELECT user_id, COUNT(*) AS order_count, SUM(amount) AS total_amount
    FROM orders
    GROUP BY user_id
) DATA INITIALLY DEFERRED
  REFRESH IMMEDIATE
  MAINTAINED BY SYSTEM;

-- DATA INITIALLY IMMEDIATE：创建时立即填充
CREATE TABLE mv_prefilled AS (
    SELECT user_id, COUNT(*) AS cnt
    FROM orders
    GROUP BY user_id
) DATA INITIALLY IMMEDIATE
  REFRESH DEFERRED
  MAINTAINED BY SYSTEM;

-- 在 MQT 上创建索引
CREATE INDEX idx_mqt_user ON mv_order_summary (user_id);

-- ============================================
-- 删除视图
-- ============================================
DROP VIEW active_users;
DROP TABLE mv_order_summary;              -- MQT 用 DROP TABLE

-- 限制：
-- DB2 使用 MQT 而非标准 MATERIALIZED VIEW 语法
-- REFRESH IMMEDIATE 有较多限制（不支持复杂查询、外连接等）
-- WITH CHECK OPTION 支持 LOCAL 和 CASCADED
-- MQT 在优化器中可被自动使用（query rewrite）
