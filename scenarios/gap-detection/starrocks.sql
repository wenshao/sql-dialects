-- StarRocks: 间隙检测与岛屿问题
--
-- 参考资料:
--   [1] StarRocks Documentation - Window Functions
--       https://docs.starrocks.io/docs/sql-reference/sql-functions/

-- 与 Doris 方案完全相同(同源)。

-- 间隙检测
SELECT id AS gap_after, next_id AS gap_before, next_id - id - 1 AS gap_size
FROM (SELECT id, LEAD(id) OVER (ORDER BY id) AS next_id FROM orders) t
WHERE next_id - id > 1;

-- 岛屿问题
SELECT MIN(id) AS start, MAX(id) AS end, COUNT(*) AS size
FROM (SELECT id, id - ROW_NUMBER() OVER (ORDER BY id) AS grp FROM orders) t
GROUP BY grp ORDER BY start;
