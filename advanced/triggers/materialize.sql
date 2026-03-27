-- Materialize: 触发器

-- Materialize 不支持触发器
-- 物化视图的增量维护本身就是"触发器"效果

-- ============================================================
-- 物化视图（替代触发器）
-- ============================================================

-- 当 users 数据变化时自动更新统计
CREATE MATERIALIZED VIEW user_stats AS
SELECT city, COUNT(*) AS cnt, AVG(age) AS avg_age
FROM users GROUP BY city;
-- users 的任何变化都会自动反映到 user_stats

-- 复杂的级联更新
CREATE MATERIALIZED VIEW order_summary AS
SELECT u.username, SUM(o.amount) AS total, COUNT(*) AS cnt
FROM users u JOIN orders o ON u.id = o.user_id
GROUP BY u.username;
-- users 或 orders 的变化都会自动更新 order_summary

-- 条件监控（类似条件触发器）
CREATE MATERIALIZED VIEW anomaly_alerts AS
SELECT * FROM sensor_readings
WHERE value > 100 OR value < -50;

-- ============================================================
-- SUBSCRIBE（实时事件推送）
-- ============================================================

-- SUBSCRIBE 持续推送变更（类似 AFTER 触发器的回调）
SUBSCRIBE TO user_stats;
SUBSCRIBE TO anomaly_alerts;

-- 应用层消费 SUBSCRIBE 输出并执行回调逻辑

-- ============================================================
-- WEBHOOK SOURCE（外部事件触发）
-- ============================================================

CREATE SOURCE webhook_events
FROM WEBHOOK BODY FORMAT JSON;

-- webhook 事件触发物化视图更新

-- 注意：Materialize 不支持触发器
-- 注意：物化视图的增量维护 = 自动触发器
-- 注意：SUBSCRIBE 用于推送变更到应用层
-- 注意：多级物化视图形成级联更新链
