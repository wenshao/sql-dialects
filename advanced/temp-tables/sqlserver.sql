-- SQL Server: 临时表 vs 表变量 vs 表值参数
--
-- 参考资料:
--   [1] SQL Server - Temporary Tables
--       https://learn.microsoft.com/en-us/sql/t-sql/statements/create-table-transact-sql#temporary-tables
--   [2] SQL Server - Table Variables
--       https://learn.microsoft.com/en-us/sql/t-sql/data-types/table-transact-sql

-- ============================================================
-- 1. 本地临时表（# 前缀）: 当前会话可见
-- ============================================================

CREATE TABLE #temp_users (id BIGINT, username NVARCHAR(100), age INT);

-- SELECT INTO 快速创建（最常用的方式）
SELECT user_id, SUM(amount) AS total, COUNT(*) AS cnt
INTO #temp_orders
FROM orders WHERE order_date >= '2024-01-01'
GROUP BY user_id;

-- 可以创建索引（临时表与永久表能力相同）
CREATE INDEX IX_temp ON #temp_users(age);
CREATE CLUSTERED INDEX IX_temp_orders ON #temp_orders(user_id);

DROP TABLE IF EXISTS #temp_users;
DROP TABLE IF EXISTS #temp_orders;

-- ============================================================
-- 2. 全局临时表（## 前缀）: 所有会话可见
-- ============================================================

CREATE TABLE ##global_config (
    [key] NVARCHAR(100) PRIMARY KEY,
    value NVARCHAR(1000)
);
-- 创建它的会话断开且无其他引用时自动删除

-- ============================================================
-- 3. 表变量（@table）: T-SQL 独有概念
-- ============================================================

DECLARE @user_table TABLE (
    id BIGINT,
    username NVARCHAR(100),
    total_orders INT
);

INSERT INTO @user_table
SELECT u.id, u.username, COUNT(o.id)
FROM users u LEFT JOIN orders o ON u.id = o.user_id
GROUP BY u.id, u.username;

SELECT * FROM @user_table WHERE total_orders > 5;

-- ============================================================
-- 4. 临时表 vs 表变量: 核心差异（对引擎开发者）
-- ============================================================

-- 设计分析:
--   临时表（#table）和表变量（@table）在 SQL Server 中行为差异很大:
--
--   临时表（#table）:
--     + 支持所有索引类型（聚集、非聚集、唯一、过滤）
--     + 有统计信息（优化器能准确估算行数）
--     + 支持并行执行
--     + 参与事务（ROLLBACK 会回滚临时表中的数据）
--     - 创建/删除有 DDL 开销
--     - 可能导致存储过程重编译
--
--   表变量（@table）:
--     + 不产生存储过程重编译
--     + 不参与事务（ROLLBACK 不影响表变量数据）
--     + 轻量级（适合小数据集）
--     - 2019 之前优化器总假设只有 1 行（导致灾难性的执行计划）
--     - 不支持非聚集索引（但可以有主键和唯一约束）
--     - 不支持并行执行（2019 之前）
--     - 不能 SELECT INTO
--
-- 经验法则:
--   小数据集（< 100 行）: 表变量
--   大数据集或需要索引: 临时表
--   不确定时: 用临时表（更安全）
--
-- 2019 重大改进:
--   Table Variable Deferred Compilation: 表变量的行数估算延迟到首次执行时
--   这修复了"总假设 1 行"的问题，但不是所有场景都有效。

-- 横向对比:
--   PostgreSQL: 只有临时表（CREATE TEMP TABLE），无表变量概念
--   MySQL:      只有临时表（CREATE TEMPORARY TABLE），无表变量
--   Oracle:     全局临时表（CREATE GLOBAL TEMPORARY TABLE）+ PL/SQL 集合类型
--
-- 对引擎开发者的启示:
--   表变量的核心价值是"不参与事务"——这在某些场景下很有用
--   （如: 在回滚的事务中保留错误日志）。但其性能问题严重限制了适用范围。
--   临时表是更通用的解决方案。

-- ============================================================
-- 5. 内存优化表变量（2014+）
-- ============================================================

DECLARE @fast_table TABLE (
    id INT NOT NULL PRIMARY KEY NONCLUSTERED,
    value NVARCHAR(100)
) WITH (MEMORY_OPTIMIZED = ON);

-- 内存优化表变量完全在内存中操作——无 tempdb I/O，无闩锁（latch-free）。
-- 但要求数据库已启用 In-Memory OLTP 特性。

-- ============================================================
-- 6. 表值参数 (TVP): 向存储过程传递表数据
-- ============================================================

CREATE TYPE dbo.UserIdList AS TABLE (user_id BIGINT NOT NULL);

CREATE PROCEDURE dbo.GetUsersByIds @ids dbo.UserIdList READONLY
AS BEGIN
    SELECT u.* FROM users u INNER JOIN @ids i ON u.id = i.user_id;
END;

DECLARE @my_ids dbo.UserIdList;
INSERT INTO @my_ids VALUES (1), (2), (3);
EXEC GetUsersByIds @ids = @my_ids;

-- TVP 必须是 READONLY——不能在存储过程中修改
-- 这是设计限制: 修改 TVP 需要在 tempdb 中创建副本，违背了 TVP 的轻量级设计

-- ============================================================
-- 7. CTE 作为轻量级"临时表"
-- ============================================================

;WITH order_stats AS (
    SELECT user_id, SUM(amount) AS total, COUNT(*) AS cnt
    FROM orders GROUP BY user_id
)
SELECT u.username, o.total, o.cnt
FROM users u JOIN order_stats o ON u.id = o.user_id
WHERE o.total > 1000;

-- CTE vs 临时表: CTE 不物化（可能重复执行），临时表物化（只执行一次）

-- ============================================================
-- 8. tempdb 管理（对 DBA 重要）
-- ============================================================

-- 所有临时表、表变量（非内存优化）、排序溢出都存储在 tempdb 中
SELECT SUM(unallocated_extent_page_count) * 8 / 1024 AS free_mb,
       SUM(user_object_reserved_page_count) * 8 / 1024 AS user_mb,
       SUM(internal_object_reserved_page_count) * 8 / 1024 AS internal_mb
FROM sys.dm_db_file_space_usage;

-- 2019+: 内存优化 tempdb 元数据（减少 tempdb 争用）
-- ALTER SERVER CONFIGURATION SET MEMORY_OPTIMIZED TEMPDB_METADATA = ON;
