-- Materialize: 分页
--
-- 参考资料:
--   [1] Materialize SQL Reference
--       https://materialize.com/docs/sql/
--   [2] Materialize SQL Functions
--       https://materialize.com/docs/sql/functions/

-- Materialize 支持标准 SQL 分页语法（兼容 PostgreSQL）

-- LIMIT / OFFSET
SELECT * FROM users ORDER BY id LIMIT 10 OFFSET 20;

-- 仅 LIMIT
SELECT * FROM users ORDER BY id LIMIT 10;

-- FETCH FIRST（SQL 标准语法）
SELECT * FROM users ORDER BY id FETCH FIRST 10 ROWS ONLY;
SELECT * FROM users ORDER BY id OFFSET 20 ROWS FETCH NEXT 10 ROWS ONLY;

-- 窗口函数分页
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (ORDER BY id) AS rn
    FROM users
) t
WHERE rn BETWEEN 21 AND 30;

-- 游标分页（推荐大数据量使用）
SELECT * FROM users WHERE id > 100 ORDER BY id LIMIT 10;

-- ============================================================
-- 物化视图分页
-- ============================================================

-- 物化视图支持正常分页
SELECT * FROM order_summary ORDER BY total_amount DESC LIMIT 10;

-- Top-N 物化视图
CREATE MATERIALIZED VIEW top_users AS
SELECT * FROM (
    SELECT username, age,
        ROW_NUMBER() OVER (ORDER BY age DESC) AS rn
    FROM users
) WHERE rn <= 100;

-- 对 Top-N 视图分页
SELECT * FROM top_users ORDER BY rn LIMIT 10 OFFSET 20;

-- ============================================================
-- SUBSCRIBE 分页（流式结果）
-- ============================================================

-- SUBSCRIBE 持续推送变更，没有传统分页
SUBSCRIBE TO order_summary;

-- 使用 AS OF 获取某个时间点的快照
SELECT * FROM users AS OF AT LEAST NOW() - INTERVAL '1 hour'
LIMIT 10;

-- 注意：支持 LIMIT/OFFSET 和 FETCH FIRST 标准语法
-- 注意：游标分页在大数据量下性能更好
-- 注意：物化视图支持正常分页查询
-- 注意：SUBSCRIBE 是流式的，不支持传统分页
