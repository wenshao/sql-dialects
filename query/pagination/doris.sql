-- Apache Doris: 分页
--
-- 参考资料:
--   [1] Doris SQL Manual
--       https://doris.apache.org/docs/sql-manual/sql-statements/
--   [2] Doris Data Types
--       https://doris.apache.org/docs/sql-manual/data-types/
--   [3] Doris Functions
--       https://doris.apache.org/docs/sql-manual/sql-functions/

-- LIMIT / OFFSET
SELECT * FROM users ORDER BY id LIMIT 10 OFFSET 20;

-- 简写形式：LIMIT offset, count（MySQL 兼容）
SELECT * FROM users ORDER BY id LIMIT 20, 10;

-- 窗口函数辅助分页
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (ORDER BY id) AS rn
    FROM users
) t
WHERE rn BETWEEN 21 AND 30;

-- 性能优化：游标分页（避免大 OFFSET 性能问题）
-- 已知上一页最后一条 id = 100
SELECT * FROM users WHERE id > 100 ORDER BY id LIMIT 10;

-- Top-N 查询
SELECT * FROM users ORDER BY created_at DESC LIMIT 10;

-- 分组后 Top-N
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY city ORDER BY age DESC) AS rn
    FROM users
) t WHERE rn <= 3;

-- 注意：Doris 兼容 MySQL 分页语法
-- 注意：大 OFFSET 值会导致性能问题（需要扫描并跳过大量行）
-- 注意：推荐使用游标分页（基于上一页最后一条记录的 ID）
