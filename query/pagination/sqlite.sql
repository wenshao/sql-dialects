-- SQLite: 分页
--
-- 参考资料:
--   [1] SQLite Documentation - SELECT (LIMIT/OFFSET)
--       https://www.sqlite.org/lang_select.html

-- ============================================================
-- LIMIT / OFFSET（所有版本）
-- ============================================================
SELECT * FROM users ORDER BY id LIMIT 10 OFFSET 20;

-- 简写形式：LIMIT offset, count
SELECT * FROM users ORDER BY id LIMIT 20, 10;

-- 仅限制行数
SELECT * FROM users ORDER BY id LIMIT 10;

-- ============================================================
-- 3.25.0+: 窗口函数辅助分页
-- ============================================================
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (ORDER BY id) AS rn
    FROM users
) t
WHERE rn BETWEEN 21 AND 30;

-- 带总行数的分页查询
SELECT *, COUNT(*) OVER() AS total_count
FROM users
ORDER BY id
LIMIT 10 OFFSET 20;

-- ============================================================
-- 键集分页（Keyset Pagination / Cursor-based）
-- 性能优于 OFFSET，适用于大数据集
-- ============================================================
-- 第一页
SELECT * FROM users ORDER BY id LIMIT 10;

-- 后续页（已知上一页最后一条 id = 100）
SELECT * FROM users WHERE id > 100 ORDER BY id LIMIT 10;

-- 多列排序的键集分页
SELECT * FROM users
WHERE (created_at, id) > ('2025-01-01', 100)
ORDER BY created_at, id
LIMIT 10;

-- ============================================================
-- 性能说明
-- ============================================================
-- OFFSET 大值性能差：SQLite 仍需扫描跳过的行
-- 推荐为排序列创建索引：
-- CREATE INDEX idx_users_id ON users(id);
-- CREATE INDEX idx_users_created ON users(created_at, id);

-- 注意：SQLite 中 LIMIT -1 表示无限制（返回所有行）
-- 注意：OFFSET 不能单独使用，必须搭配 LIMIT
-- 注意：键集分页需要稳定且唯一的排序键
