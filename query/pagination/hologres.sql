-- Hologres: 分页（兼容 PostgreSQL 语法）
--
-- 参考资料:
--   [1] Hologres SQL - SELECT (LIMIT)
--       https://help.aliyun.com/zh/hologres/user-guide/select
--   [2] Hologres SQL Reference
--       https://help.aliyun.com/zh/hologres/user-guide/overview-27

-- LIMIT / OFFSET
SELECT * FROM users ORDER BY id LIMIT 10 OFFSET 20;

-- SQL 标准语法
SELECT * FROM users ORDER BY id OFFSET 20 ROWS FETCH FIRST 10 ROWS ONLY;

-- 仅 LIMIT
SELECT * FROM users ORDER BY id LIMIT 10;

-- 窗口函数分页
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (ORDER BY id) AS rn
    FROM users
) t
WHERE rn BETWEEN 21 AND 30;

-- 游标分页（推荐大数据量使用）
SELECT * FROM users WHERE id > 100 ORDER BY id LIMIT 10;

-- 注意：Hologres 兼容 PostgreSQL 语法，支持 LIMIT/OFFSET 和 FETCH FIRST
-- 注意：Hologres 行存表的分页查询性能更好（点查场景）
-- 注意：列存表的大 OFFSET 分页性能较差，建议使用游标分页
-- 注意：分页查询建议在主键或分布键上 ORDER BY 以获取最佳性能
