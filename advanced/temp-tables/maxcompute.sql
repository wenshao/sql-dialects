-- MaxCompute (ODPS): 临时表与临时存储
--
-- 参考资料:
--   [1] MaxCompute Documentation
--       https://help.aliyun.com/document_detail/27819.html

-- MaxCompute 不支持 CREATE TEMPORARY TABLE
-- 使用 CTE 或临时项目表

-- ============================================================
-- CTE
-- ============================================================

WITH stats AS (
    SELECT user_id, SUM(amount) AS total FROM orders GROUP BY user_id
)
SELECT u.username, s.total FROM users u JOIN stats s ON u.id = s.user_id;

-- ============================================================
-- 临时表替代方案
-- ============================================================

-- 创建生命周期短的表
CREATE TABLE temp_results LIFECYCLE 1 AS
SELECT user_id, SUM(amount) AS total FROM orders GROUP BY user_id;

-- LIFECYCLE 1 表示 1 天后自动删除

-- 使用后删除
DROP TABLE IF EXISTS temp_results;

-- ============================================================
-- INSERT OVERWRITE（覆盖写入）
-- ============================================================

-- 覆盖中间表
INSERT OVERWRITE TABLE staging_results
SELECT user_id, SUM(amount) AS total FROM orders GROUP BY user_id;

-- 注意：MaxCompute 不支持临时表
-- 注意：LIFECYCLE 设置可以自动清理临时表
-- 注意：CTE 是组织中间结果的推荐方式
-- 注意：INSERT OVERWRITE 可以刷新 Staging 表
