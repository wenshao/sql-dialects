-- MySQL: 分页
--
-- 参考资料:
--   [1] MySQL 8.0 Reference Manual - SELECT ... LIMIT
--       https://dev.mysql.com/doc/refman/8.0/en/select.html
--   [2] MySQL 8.0 Reference Manual - LIMIT Optimization
--       https://dev.mysql.com/doc/refman/8.0/en/limit-optimization.html

-- LIMIT / OFFSET（所有版本）
SELECT * FROM users ORDER BY id LIMIT 10 OFFSET 20;

-- 简写形式：LIMIT offset, count
SELECT * FROM users ORDER BY id LIMIT 20, 10;

-- 8.0+: 窗口函数辅助分页
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (ORDER BY id) AS rn
    FROM users
) t
WHERE rn BETWEEN 21 AND 30;

-- 性能优化：游标分页（避免大 OFFSET 性能问题）
-- 已知上一页最后一条 id = 100
SELECT * FROM users WHERE id > 100 ORDER BY id LIMIT 10;
