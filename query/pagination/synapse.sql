-- Azure Synapse: 分页
--
-- 参考资料:
--   [1] Synapse SQL Features
--       https://learn.microsoft.com/en-us/azure/synapse-analytics/sql/overview-features
--   [2] Synapse T-SQL Differences
--       https://learn.microsoft.com/en-us/azure/synapse-analytics/sql/overview-features

-- OFFSET / FETCH（T-SQL 2012+ 标准语法）
SELECT * FROM users ORDER BY id OFFSET 20 ROWS FETCH NEXT 10 ROWS ONLY;

-- TOP（所有版本，不支持跳过）
SELECT TOP 10 * FROM users ORDER BY id;

-- TOP WITH TIES（包含并列行）
SELECT TOP 10 WITH TIES * FROM users ORDER BY age;

-- ROW_NUMBER() 窗口函数分页
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (ORDER BY id) AS rn
    FROM users
) t
WHERE t.rn BETWEEN 21 AND 30;

-- CTE + ROW_NUMBER()
WITH paged AS (
    SELECT *, ROW_NUMBER() OVER (ORDER BY id) AS rn
    FROM users
)
SELECT * FROM paged WHERE rn BETWEEN 21 AND 30;

-- 游标分页（Keyset Pagination）
-- 第一页
SELECT TOP 10 * FROM users ORDER BY id;
-- 后续页
SELECT TOP 10 * FROM users WHERE id > 100 ORDER BY id;

-- 注意：OFFSET / FETCH 需要 ORDER BY 子句
-- 注意：大偏移量时 OFFSET 性能差，推荐游标分页
-- 注意：TOP 不需要 ORDER BY（但结果不确定）
-- 注意：MPP 架构下分页需要全局排序，有数据移动开销
-- 注意：Serverless 池也支持 OFFSET / FETCH 分页
