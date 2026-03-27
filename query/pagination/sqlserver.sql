-- SQL Server: 分页
--
-- 参考资料:
--   [1] SQL Server T-SQL - ORDER BY / OFFSET-FETCH
--       https://learn.microsoft.com/en-us/sql/t-sql/queries/select-order-by-clause-transact-sql
--   [2] SQL Server T-SQL - TOP
--       https://learn.microsoft.com/en-us/sql/t-sql/queries/top-transact-sql

-- 2012+: OFFSET / FETCH（推荐）
SELECT * FROM users ORDER BY id OFFSET 20 ROWS FETCH NEXT 10 ROWS ONLY;

-- 传统方式：TOP（所有版本，但不支持跳过）
SELECT TOP 10 * FROM users ORDER BY id;

-- 2005+: ROW_NUMBER()
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (ORDER BY id) AS rn
    FROM users
) t
WHERE rn BETWEEN 21 AND 30;

-- 2005+: CTE + ROW_NUMBER()
WITH paged AS (
    SELECT *, ROW_NUMBER() OVER (ORDER BY id) AS rn
    FROM users
)
SELECT * FROM paged WHERE rn BETWEEN 21 AND 30;

-- 游标分页
SELECT TOP 10 * FROM users WHERE id > 100 ORDER BY id;
