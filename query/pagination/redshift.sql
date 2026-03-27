-- Redshift: 分页
--
-- 参考资料:
--   [1] Redshift SQL Reference
--       https://docs.aws.amazon.com/redshift/latest/dg/cm_chap_SQLCommandRef.html
--   [2] Redshift SQL Functions
--       https://docs.aws.amazon.com/redshift/latest/dg/c_SQL_functions.html
--   [3] Redshift Data Types
--       https://docs.aws.amazon.com/redshift/latest/dg/c_Supported_data_types.html

-- LIMIT / OFFSET（PostgreSQL 风格）
SELECT * FROM users ORDER BY id LIMIT 10 OFFSET 20;

-- LIMIT（不跳过）
SELECT * FROM users ORDER BY id LIMIT 10;

-- TOP（Redshift 也支持 SQL Server 风格的 TOP）
SELECT TOP 10 * FROM users ORDER BY id;

-- ROW_NUMBER() 窗口函数分页
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (ORDER BY id) AS rn
    FROM users
) t
WHERE rn BETWEEN 21 AND 30;

-- CTE + ROW_NUMBER()
WITH paged AS (
    SELECT *, ROW_NUMBER() OVER (ORDER BY id) AS rn
    FROM users
)
SELECT * FROM paged WHERE rn BETWEEN 21 AND 30;

-- 游标分页（Keyset Pagination，性能最佳）
-- 第一页
SELECT * FROM users ORDER BY id LIMIT 10;
-- 后续页（假设上一页最后 id 为 100）
SELECT * FROM users WHERE id > 100 ORDER BY id LIMIT 10;

-- 注意：LIMIT / OFFSET 在大偏移量时性能差（需要扫描跳过的行）
-- 注意：游标分页（Keyset）性能最稳定，推荐大数据集使用
-- 注意：Redshift 同时支持 LIMIT 和 TOP 语法
-- 注意：分布式系统中 OFFSET 需要全局排序，开销较大
