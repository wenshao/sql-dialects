-- SQL Server: 临时表与临时存储
--
-- 参考资料:
--   [1] Microsoft Docs - Temporary Tables
--       https://learn.microsoft.com/en-us/sql/t-sql/statements/create-table-transact-sql#temporary-tables
--   [2] Microsoft Docs - Table Variables
--       https://learn.microsoft.com/en-us/sql/t-sql/data-types/table-transact-sql
--   [3] Microsoft Docs - Table-Valued Parameters
--       https://learn.microsoft.com/en-us/sql/relational-databases/tables/use-table-valued-parameters-database-engine

-- ============================================================
-- 本地临时表（#）
-- ============================================================

-- 创建本地临时表（当前会话可见）
CREATE TABLE #temp_users (
    id BIGINT,
    username NVARCHAR(100),
    email NVARCHAR(200),
    age INT
);

-- 从查询创建
SELECT user_id, SUM(amount) AS total, COUNT(*) AS cnt
INTO #temp_orders
FROM orders
WHERE order_date >= '2024-01-01'
GROUP BY user_id;

-- 使用临时表
INSERT INTO #temp_users (id, username, email, age)
SELECT id, username, email, age FROM users WHERE status = 1;

SELECT u.username, t.total
FROM #temp_users u
JOIN #temp_orders t ON u.id = t.user_id;

-- 创建索引
CREATE INDEX IX_temp_users_age ON #temp_users(age);
CREATE CLUSTERED INDEX IX_temp_orders_user ON #temp_orders(user_id);

-- 删除
DROP TABLE IF EXISTS #temp_users;
DROP TABLE IF EXISTS #temp_orders;

-- ============================================================
-- 全局临时表（##）
-- ============================================================

-- 创建全局临时表（所有会话可见）
CREATE TABLE ##global_config (
    key NVARCHAR(100) PRIMARY KEY,
    value NVARCHAR(1000)
);

-- 所有会话都可以访问
INSERT INTO ##global_config VALUES ('version', '2.0');
SELECT * FROM ##global_config;

-- 当创建它的会话断开且没有其他会话引用时自动删除
DROP TABLE IF EXISTS ##global_config;

-- ============================================================
-- 表变量（@）
-- ============================================================

-- 声明表变量
DECLARE @user_table TABLE (
    id BIGINT,
    username NVARCHAR(100),
    total_orders INT
);

INSERT INTO @user_table
SELECT u.id, u.username, COUNT(o.id)
FROM users u
LEFT JOIN orders o ON u.id = o.user_id
GROUP BY u.id, u.username;

SELECT * FROM @user_table WHERE total_orders > 5;

-- 表变量特点：
-- 1. 作用域是批处理或存储过程
-- 2. 不参与事务（ROLLBACK 不影响）
-- 3. 不产生重编译
-- 4. 不能创建非聚集索引（但可以有主键和唯一约束）
-- 5. 优化器假定只有 1 行（2019 之前）

-- 2014+: 内存优化表变量
DECLARE @fast_table TABLE (
    id INT NOT NULL PRIMARY KEY NONCLUSTERED,
    value NVARCHAR(100)
) WITH (MEMORY_OPTIMIZED = ON);

-- ============================================================
-- 临时表 vs 表变量对比
-- ============================================================

-- 临时表（#table）：
-- + 支持索引、统计信息、并行
-- + 有精确的行数估算
-- - 有锁和日志开销
-- - 可能导致存储过程重编译

-- 表变量（@table）：
-- + 不产生重编译
-- + 不参与事务（ROLLBACK 不回滚）
-- + 轻量级
-- - 2019 前优化器总假定 1 行
-- - 不支持并行操作（2019 前）

-- 经验法则：小数据集用表变量，大数据集用临时表

-- ============================================================
-- 表值参数（TVP）
-- ============================================================

-- 创建表类型
CREATE TYPE dbo.UserIdList AS TABLE (
    user_id BIGINT NOT NULL
);

-- 在存储过程中使用
CREATE PROCEDURE GetUsersByIds
    @ids dbo.UserIdList READONLY
AS
BEGIN
    SELECT u.* FROM users u
    INNER JOIN @ids i ON u.id = i.user_id;
END;

-- 调用
DECLARE @my_ids dbo.UserIdList;
INSERT INTO @my_ids VALUES (1), (2), (3);
EXEC GetUsersByIds @ids = @my_ids;

-- ============================================================
-- CTE（公共表表达式）
-- ============================================================

WITH OrderStats AS (
    SELECT user_id, SUM(amount) AS total,
           COUNT(*) AS cnt, AVG(amount) AS avg_amount
    FROM orders GROUP BY user_id
)
SELECT u.username, o.total, o.cnt, o.avg_amount
FROM users u JOIN OrderStats o ON u.id = o.user_id
WHERE o.total > 1000;

-- 递归 CTE
WITH OrgChart AS (
    SELECT id, name, manager_id, 0 AS level
    FROM employees WHERE manager_id IS NULL
    UNION ALL
    SELECT e.id, e.name, e.manager_id, o.level + 1
    FROM employees e JOIN OrgChart o ON e.manager_id = o.id
)
SELECT * FROM OrgChart
OPTION (MAXRECURSION 100);

-- ============================================================
-- tempdb 管理
-- ============================================================

-- 查看 tempdb 使用情况
SELECT SUM(unallocated_extent_page_count) * 8 / 1024 AS free_mb,
       SUM(internal_object_reserved_page_count) * 8 / 1024 AS internal_mb,
       SUM(user_object_reserved_page_count) * 8 / 1024 AS user_mb
FROM sys.dm_db_file_space_usage;

-- 查看哪些会话在使用 tempdb
SELECT session_id,
       internal_objects_alloc_page_count,
       user_objects_alloc_page_count
FROM sys.dm_db_session_space_usage
WHERE internal_objects_alloc_page_count > 0
   OR user_objects_alloc_page_count > 0;

-- ============================================================
-- 内存优化临时表（2016+）
-- ============================================================

-- 系统级内存优化 tempdb 元数据（2019+）
-- ALTER SERVER CONFIGURATION SET MEMORY_OPTIMIZED TEMPDB_METADATA = ON;

-- 注意：# 前缀创建本地临时表，## 前缀创建全局临时表
-- 注意：表变量用 DECLARE @table TABLE 声明
-- 注意：临时表存储在 tempdb 中
-- 注意：2019+ 版本表变量支持延迟编译（更准确的行数估算）
-- 注意：SELECT INTO 可以快速创建临时表
-- 注意：TVP（表值参数）用于向存储过程传递表数据
