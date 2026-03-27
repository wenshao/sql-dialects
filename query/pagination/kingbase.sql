-- KingbaseES (人大金仓): 分页 (Pagination)
--
-- 参考资料:
--   [1] KingbaseES V8 SQL 语言参考 - SELECT
--       https://help.kingbase.com.cn/v8/development-manual/sql-reference/sql-statement/select.html
--   [2] KingbaseES V8 开发者指南 - 游标
--       https://help.kingbase.com.cn/v8/development-manual/plsql/cursor.html
--   [3] KingbaseES 兼容性说明
--       https://help.kingbase.com.cn/v8/overview/compatibility.html

-- ============================================================
-- 1. LIMIT / OFFSET（传统分页）
-- ============================================================

-- 基本分页: 跳过前 20 行，取 10 行
SELECT * FROM users ORDER BY id LIMIT 10 OFFSET 20;

-- 仅取前 N 行
SELECT * FROM users ORDER BY id LIMIT 10;

-- 带总行数的分页（一次查询获取数据和总数）
SELECT *, COUNT(*) OVER() AS total_count
FROM users ORDER BY id LIMIT 10 OFFSET 20;

-- ============================================================
-- 2. FETCH FIRST（SQL 标准语法，兼容 PostgreSQL）
-- ============================================================

-- SQL 标准 OFFSET / FETCH 语法
SELECT * FROM users ORDER BY id OFFSET 20 ROWS FETCH FIRST 10 ROWS ONLY;

-- FETCH NEXT（等价于 FETCH FIRST）
SELECT * FROM users ORDER BY id OFFSET 20 ROWS FETCH NEXT 10 ROWS ONLY;

-- 仅取前 N 行（标准语法）
SELECT * FROM users ORDER BY id FETCH FIRST 10 ROWS ONLY;

-- ============================================================
-- 3. OFFSET 的性能问题: 为什么大偏移量很慢
-- ============================================================

-- OFFSET 1000000 意味着数据库必须:
--   (1) 执行查询计划获取前 1000010 行
--   (2) 丢弃前 1000000 行
--   (3) 返回后 10 行
-- 时间复杂度: O(OFFSET + LIMIT)，而非 O(LIMIT)
-- 这不是 KingbaseES 的缺陷，而是 OFFSET 语义的固有局限

-- ============================================================
-- 4. 键集分页（Keyset Pagination）: 高性能替代方案
-- ============================================================

-- 第一页
SELECT * FROM users ORDER BY id LIMIT 10;

-- 后续页（已知上一页最后一条 id = 100）
SELECT * FROM users WHERE id > 100 ORDER BY id LIMIT 10;
-- 时间复杂度: O(LIMIT)，与页数无关！

-- 多列排序的键集分页（使用 ROW 值比较）
SELECT * FROM users
WHERE (created_at, id) > ('2025-01-01', 100)
ORDER BY created_at, id
LIMIT 10;
-- KingbaseES 完全兼容 PostgreSQL 的 ROW 值比较语法

-- 索引支持:
CREATE INDEX idx_users_created_id ON users (created_at, id);

-- ============================================================
-- 5. 窗口函数辅助分页
-- ============================================================

-- ROW_NUMBER 分页（适合需要精确行号的场景）
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (ORDER BY id) AS rn FROM users
) t WHERE rn BETWEEN 21 AND 30;

-- 分组后 Top-N
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY city ORDER BY age DESC) AS rn
    FROM users
) t WHERE rn <= 3;

-- 注意: 窗口函数方式需要计算所有行的 ROW_NUMBER，性能不如键集分页

-- ============================================================
-- 6. 服务端游标（大数据集逐批处理）
-- ============================================================

-- 游标在事务中声明，逐批 FETCH
BEGIN;
DECLARE user_cursor CURSOR FOR SELECT * FROM users ORDER BY id;
FETCH 100 FROM user_cursor;         -- 获取前 100 行
FETCH 100 FROM user_cursor;         -- 获取下一批 100 行
CLOSE user_cursor;
COMMIT;

-- ============================================================
-- 7. KingbaseES 特有说明
-- ============================================================

-- KingbaseES 与 PostgreSQL 的分页兼容性:
--   LIMIT / OFFSET:     完全兼容
--   FETCH FIRST:        完全兼容
--   ROW 值比较:         完全兼容（键集分页核心特性）
--   DECLARE CURSOR:     完全兼容
--   WITH TIES:          视版本而定（需 KingbaseES V8R6+）
--
-- KingbaseES 的两种兼容模式:
--   PG 模式:  使用 LIMIT / OFFSET + FETCH FIRST（默认）
--   Oracle 模式: 使用 ROWNUM + FETCH FIRST（兼容 Oracle 应用迁移）
--     SELECT * FROM (
--         SELECT t.*, ROWNUM AS rn FROM users t WHERE ROWNUM <= 30
--     ) WHERE rn > 20;

-- ============================================================
-- 8. 版本演进
-- ============================================================
-- KingbaseES V8R3:  LIMIT / OFFSET，FETCH FIRST
-- KingbaseES V8R6:  增强窗口函数支持，ROW 值比较优化
-- KingbaseES V9:    WITH TIES 支持（视版本发布情况）

-- ============================================================
-- 9. 横向对比: 分页语法差异
-- ============================================================

-- 语法对比:
--   KingbaseES:  LIMIT n OFFSET m + FETCH FIRST（同 PostgreSQL）
--   PostgreSQL:  LIMIT n OFFSET m + FETCH FIRST（KingbaseES 的上游）
--   MySQL:       LIMIT n OFFSET m / LIMIT m, n（不支持 FETCH FIRST）
--   Oracle:      FETCH FIRST (12c+)，传统用 ROWNUM
--   SQL Server:  TOP n / OFFSET-FETCH (2012+)
--
-- 性能对比:
--   KingbaseES 作为 PostgreSQL 兼容数据库，分页性能特征与 PostgreSQL 一致
--   大 OFFSET 场景下推荐使用键集分页
--   游标方案适合批量数据导出场景
