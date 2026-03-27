-- SQL Server: 分页查询
--
-- 参考资料:
--   [1] SQL Server T-SQL - OFFSET-FETCH
--       https://learn.microsoft.com/en-us/sql/t-sql/queries/select-order-by-clause-transact-sql
--   [2] SQL Server T-SQL - TOP
--       https://learn.microsoft.com/en-us/sql/t-sql/queries/top-transact-sql

-- ============================================================
-- 1. OFFSET ... FETCH: 标准分页（SQL Server 2012+）
-- ============================================================

SELECT * FROM users ORDER BY id
OFFSET 20 ROWS FETCH NEXT 10 ROWS ONLY;

-- 设计分析（对引擎开发者）:
--   OFFSET-FETCH 是 SQL:2008 标准语法，SQL Server 在 2012 版本才引入。
--   此前，SQL Server 是唯一没有标准分页语法的主流数据库。
--   OFFSET-FETCH 必须配合 ORDER BY 使用（没有 ORDER BY 会报错）。
--
-- 横向对比:
--   MySQL:      LIMIT 10 OFFSET 20（最简洁，最早实现，非标准）
--   PostgreSQL: LIMIT 10 OFFSET 20 或 FETCH FIRST 10 ROWS ONLY（两种都支持）
--   Oracle:     12c+ OFFSET ... FETCH, 之前用 ROWNUM（有嵌套查询陷阱）
--   SQL Server: OFFSET ... FETCH NEXT ... ROWS ONLY（语法最冗长）
--
-- 对引擎开发者的启示:
--   OFFSET 分页在深页时性能极差（需要跳过前 N 行）。
--   所有数据库都有这个问题。推荐使用 Keyset 分页替代（见下文）。

-- ============================================================
-- 2. TOP: SQL Server 传统分页（所有版本）
-- ============================================================

SELECT TOP 10 * FROM users ORDER BY id;

-- TOP WITH TIES: 包含并列行（SQL Server 独有）
SELECT TOP 10 WITH TIES * FROM users ORDER BY age DESC;
-- 如果第 10 和第 11 行 age 相同，两行都返回

-- TOP PERCENT: 按百分比取行
SELECT TOP 10 PERCENT * FROM users ORDER BY id;

-- TOP 的独特设计:
--   (1) TOP 可以用在 INSERT/UPDATE/DELETE 中（其他数据库不支持）
--   (2) TOP 可以接受变量: SELECT TOP (@n) * FROM users ORDER BY id;
--   (3) TOP 不需要 ORDER BY（但不加 ORDER BY 结果不确定）

-- ============================================================
-- 3. ROW_NUMBER() 分页: 2005-2008 的标准方式
-- ============================================================

-- 2012 之前，SQL Server 没有 OFFSET-FETCH，ROW_NUMBER 是唯一的分页方案:
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (ORDER BY id) AS rn FROM users
) t WHERE rn BETWEEN 21 AND 30;

-- CTE 版本（更清晰）:
;WITH paged AS (
    SELECT *, ROW_NUMBER() OVER (ORDER BY id) AS rn FROM users
)
SELECT * FROM paged WHERE rn BETWEEN 21 AND 30;

-- 设计分析:
--   ROW_NUMBER 分页的问题: 即使只要第 1000 页，也需要计算所有行的行号。
--   执行计划中会出现 Top + Sort 操作符，对大数据集效率低。
--   OFFSET-FETCH 在优化器内部也有类似的问题，但实现更高效。

-- ============================================================
-- 4. Keyset 分页（游标分页）: 最佳性能方案
-- ============================================================

-- 第一页:
SELECT TOP 10 * FROM users ORDER BY id;

-- 后续页（使用上一页最后一条的 id）:
SELECT TOP 10 * FROM users WHERE id > @last_id ORDER BY id;

-- 设计分析（对引擎开发者）:
--   Keyset 分页的优势: 时间复杂度 O(log N + K)（索引查找 + 取 K 行）
--   OFFSET 分页的劣势: 时间复杂度 O(N)（跳过 N 行）
--
--   Keyset 分页的限制:
--   (1) 只能前进/后退，不能跳到任意页
--   (2) 需要唯一、有序的键列
--   (3) 如果排序列有重复值，需要复合键: WHERE (age, id) > (@last_age, @last_id)
--
--   SQL Server 中复合键 Keyset 分页:
SELECT TOP 10 * FROM users
WHERE (age > @last_age) OR (age = @last_age AND id > @last_id)
ORDER BY age, id;
--   这比 PostgreSQL 的 (age, id) > (@a, @i) 行比较语法更冗长。

-- ============================================================
-- 5. 总行数 + 分页数据（一次查询）
-- ============================================================

-- 使用 COUNT(*) OVER() 窗口函数避免两次查询:
SELECT *, COUNT(*) OVER () AS total_count
FROM users
ORDER BY id
OFFSET 20 ROWS FETCH NEXT 10 ROWS ONLY;

-- 设计分析:
--   COUNT(*) OVER() 的代价: 即使只取 10 行，也需要扫描全部满足 WHERE 条件的行来计算总数。
--   这是一个经典的权衡: 两次查询 vs 一次查询但全表扫描。
--   对于大表，推荐使用估算行数（sys.dm_db_partition_stats）替代精确计数。

-- 快速获取近似行数:
SELECT SUM(row_count) AS approx_rows
FROM sys.dm_db_partition_stats
WHERE object_id = OBJECT_ID('users') AND index_id <= 1;

-- ============================================================
-- 6. 版本对比总结
-- ============================================================

-- 2000-2005: 只有 TOP（无法跳过行）
-- 2005-2008: ROW_NUMBER() OVER() + CTE/子查询
-- 2012+:     OFFSET ... FETCH NEXT（标准语法）
-- 最佳实践: API 分页用 Keyset 模式，UI 分页用 OFFSET-FETCH
