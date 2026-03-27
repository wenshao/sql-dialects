-- SQLite: 分页
--
-- 参考资料:
--   [1] SQLite Documentation - SELECT (LIMIT/OFFSET)
--       https://www.sqlite.org/lang_select.html

-- ============================================================
-- 1. LIMIT / OFFSET（标准分页）
-- ============================================================

SELECT * FROM users ORDER BY id LIMIT 10;              -- 前 10 行
SELECT * FROM users ORDER BY id LIMIT 10 OFFSET 20;    -- 第 3 页（每页 10 行）
SELECT * FROM users ORDER BY id LIMIT 20, 10;           -- 等价语法（MySQL 兼容）

-- ============================================================
-- 2. 游标分页（Cursor-based / Keyset Pagination）
-- ============================================================

-- OFFSET 分页的问题: OFFSET 越大越慢（需要跳过前 N 行）
-- 游标分页: 使用上一页的最后一个值作为起点

-- 第一页:
SELECT * FROM users ORDER BY id LIMIT 10;
-- 假设最后一行 id = 10

-- 第二页:
SELECT * FROM users WHERE id > 10 ORDER BY id LIMIT 10;
-- 使用索引直接定位，不需要跳过前 10 行

-- 复合排序的游标分页:
SELECT * FROM users
WHERE (created_at, id) > ('2024-01-15', 100)
ORDER BY created_at, id
LIMIT 10;

-- 设计分析:
--   游标分页在 SQLite 中特别重要:
--   (a) SQLite 没有查询缓存（每次查询从头扫描）
--   (b) 大 OFFSET 意味着大量无用的 B-Tree 遍历
--   (c) 嵌入式场景通常是列表滚动加载，天然适合游标分页

-- ============================================================
-- 3. SQLite 分页的特殊语法
-- ============================================================

-- LIMIT -1: 不限制行数（返回所有行）
SELECT * FROM users ORDER BY id LIMIT -1 OFFSET 10;
-- → 跳过前 10 行，返回所有剩余行

-- LIMIT 值可以是表达式:
-- SELECT * FROM users LIMIT (SELECT setting_value FROM config WHERE key = 'page_size');

-- ============================================================
-- 4. 对比与引擎开发者启示
-- ============================================================
-- SQLite 分页的特点:
--   (1) LIMIT/OFFSET → 标准语法
--   (2) LIMIT m, n → MySQL 兼容语法
--   (3) LIMIT -1 → 无限制（SQLite 特有）
--   (4) 游标分页 → WHERE id > last_id 模式
--
-- 对比:
--   MySQL: LIMIT offset, count
--   PostgreSQL: LIMIT count OFFSET offset + FETCH FIRST
--   ClickHouse: LIMIT count OFFSET offset
--   BigQuery: LIMIT count OFFSET offset
--
-- 对引擎开发者的启示:
--   LIMIT/OFFSET 是必需语法，但应该鼓励游标分页。
--   OFFSET 的性能问题是所有数据库的通病:
--   B-Tree 引擎需要遍历 OFFSET 行，列存引擎需要跳过 OFFSET 行。
--   游标分页利用索引直接定位，性能恒定。
