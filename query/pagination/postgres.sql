-- PostgreSQL: 分页
--
-- 参考资料:
--   [1] PostgreSQL Documentation - LIMIT and OFFSET
--       https://www.postgresql.org/docs/current/queries-limit.html
--   [2] PostgreSQL Documentation - SELECT
--       https://www.postgresql.org/docs/current/sql-select.html

-- ============================================================
-- LIMIT / OFFSET（所有版本）
-- ============================================================
SELECT * FROM users ORDER BY id LIMIT 10 OFFSET 20;

-- 仅限制行数
SELECT * FROM users ORDER BY id LIMIT 10;

-- ============================================================
-- SQL 标准语法（8.4+）
-- ============================================================
SELECT * FROM users ORDER BY id OFFSET 20 ROWS FETCH FIRST 10 ROWS ONLY;

-- FETCH NEXT 与 FETCH FIRST 等价
SELECT * FROM users ORDER BY id OFFSET 20 ROWS FETCH NEXT 10 ROWS ONLY;

-- ============================================================
-- 窗口函数辅助分页
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
-- 服务端游标（大数据集逐批处理）
-- ============================================================
-- BEGIN;
-- DECLARE user_cursor CURSOR FOR SELECT * FROM users ORDER BY id;
-- FETCH 10 FROM user_cursor;   -- 获取下一批 10 条
-- FETCH 10 FROM user_cursor;   -- 继续获取
-- CLOSE user_cursor;
-- COMMIT;

-- ============================================================
-- 性能说明
-- ============================================================
-- OFFSET 大值性能差：PostgreSQL 仍需扫描跳过的行
-- 推荐为排序列创建索引：
-- CREATE INDEX idx_users_id ON users(id);
-- CREATE INDEX idx_users_created ON users(created_at, id);

-- 注意：LIMIT/OFFSET 是 PostgreSQL 扩展，非 SQL 标准
-- 注意：FETCH FIRST ... ROWS ONLY 是 SQL 标准语法（8.4+）
-- 注意：键集分页需要稳定且唯一的排序键
-- 注意：服务端游标适用于需要逐批处理大量数据的场景
