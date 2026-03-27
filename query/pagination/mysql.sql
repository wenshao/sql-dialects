-- MySQL: 分页
--
-- 参考资料:
--   [1] MySQL 8.0 Reference Manual - SELECT ... LIMIT
--       https://dev.mysql.com/doc/refman/8.0/en/select.html
--   [2] MySQL 8.0 Reference Manual - LIMIT Optimization
--       https://dev.mysql.com/doc/refman/8.0/en/limit-optimization.html

-- ============================================================
-- LIMIT / OFFSET（所有版本）
-- ============================================================
SELECT * FROM users ORDER BY id LIMIT 10 OFFSET 20;

-- 简写形式：LIMIT offset, count
SELECT * FROM users ORDER BY id LIMIT 20, 10;

-- 仅限制行数
SELECT * FROM users ORDER BY id LIMIT 10;

-- ============================================================
-- 8.0+: 窗口函数辅助分页
-- ============================================================
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (ORDER BY id) AS rn
    FROM users
) t
WHERE rn BETWEEN 21 AND 30;

-- 带总行数的分页查询（8.0+）
SELECT *, COUNT(*) OVER() AS total_count
FROM users
ORDER BY id
LIMIT 10 OFFSET 20;

-- ============================================================
-- SQL_CALC_FOUND_ROWS（已废弃但仍可用）
-- ============================================================
-- SELECT SQL_CALC_FOUND_ROWS * FROM users ORDER BY id LIMIT 10 OFFSET 20;
-- SELECT FOUND_ROWS();    -- 返回不带 LIMIT 时的总行数
-- 注意：MySQL 8.0.17+ 已废弃，建议使用 COUNT(*) OVER() 替代

-- ============================================================
-- 键集分页（Keyset / Cursor-based Pagination）
-- 性能优于 OFFSET，适用于大数据集
-- ============================================================
-- 第一页
SELECT * FROM users ORDER BY id LIMIT 10;

-- 后续页（已知上一页最后一条 id = 100）
SELECT * FROM users WHERE id > 100 ORDER BY id LIMIT 10;

-- 多列排序的键集分页
SELECT * FROM users
WHERE created_at > '2025-01-01'
   OR (created_at = '2025-01-01' AND id > 100)
ORDER BY created_at, id
LIMIT 10;

-- ============================================================
-- 延迟关联（Deferred Join，优化大 OFFSET）
-- ============================================================
SELECT u.* FROM users u
JOIN (SELECT id FROM users ORDER BY id LIMIT 10 OFFSET 100000) AS t
ON u.id = t.id;

-- ============================================================
-- 性能说明
-- ============================================================
-- OFFSET 大值性能差：MySQL 仍需扫描跳过的行
-- 推荐为排序列创建索引：
-- CREATE INDEX idx_users_id ON users(id);
-- CREATE INDEX idx_users_created ON users(created_at, id);

-- 注意：LIMIT offset, count 中 offset 在前、count 在后（易混淆）
-- 注意：LIMIT count OFFSET offset 更清晰（推荐）
-- 注意：键集分页需要稳定且唯一的排序键
-- 注意：延迟关联可大幅优化大 OFFSET 场景
