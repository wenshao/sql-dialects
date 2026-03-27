-- Vertica: 分页
--
-- 参考资料:
--   [1] Vertica SQL Reference
--       https://www.vertica.com/docs/latest/HTML/Content/Authoring/SQLReferenceManual/SQLReferenceManual.htm
--   [2] Vertica Functions
--       https://www.vertica.com/docs/latest/HTML/Content/Authoring/SQLReferenceManual/Functions/Functions.htm

-- LIMIT / OFFSET
SELECT * FROM users ORDER BY id LIMIT 10 OFFSET 20;

-- FETCH FIRST（SQL:2008 标准）
SELECT * FROM users ORDER BY id
OFFSET 20 ROWS FETCH FIRST 10 ROWS ONLY;

-- FETCH NEXT
SELECT * FROM users ORDER BY id
OFFSET 20 ROWS FETCH NEXT 10 ROWS ONLY;

-- 窗口函数辅助分页
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (ORDER BY id) AS rn
    FROM users
) t
WHERE rn BETWEEN 21 AND 30;

-- 性能优化：游标分页
-- 已知上一页最后一条 id = 100
SELECT * FROM users WHERE id > 100 ORDER BY id LIMIT 10;

-- Top-N 查询（Vertica 对 Top-N 有特殊优化）
SELECT * FROM users ORDER BY created_at DESC LIMIT 10;

-- 分组后 Top-N
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY city ORDER BY age DESC) AS rn
    FROM users
) t WHERE rn <= 3;

-- Top-K Projection（预计算排行）
-- CREATE PROJECTION top_orders AS
-- SELECT id, user_id, amount, order_date
-- FROM orders ORDER BY amount DESC LIMIT 1000;

-- 注意：Vertica 支持 LIMIT/OFFSET 和 FETCH FIRST 语法
-- 注意：大 OFFSET 值会导致性能问题
-- 注意：Vertica 的 Top-K Projection 可以加速 Top-N 查询
-- 注意：推荐使用游标分页避免大 OFFSET
