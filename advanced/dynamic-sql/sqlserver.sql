-- SQL Server: Dynamic SQL
--
-- 参考资料:
--   [1] SQL Server T-SQL - sp_executesql
--       https://learn.microsoft.com/en-us/sql/relational-databases/system-stored-procedures/sp-executesql-transact-sql
--   [2] SQL Server T-SQL - EXECUTE
--       https://learn.microsoft.com/en-us/sql/t-sql/language-elements/execute-transact-sql
--   [3] SQL Server Dynamic SQL best practices
--       https://learn.microsoft.com/en-us/sql/relational-databases/performance/dynamic-sql

-- ============================================================
-- EXEC / EXECUTE (基本动态 SQL)
-- ============================================================
-- 直接执行字符串
EXEC('SELECT * FROM users WHERE id = 1');

-- 使用变量
DECLARE @sql NVARCHAR(MAX);
SET @sql = N'SELECT * FROM users WHERE status = ''active''';
EXEC(@sql);

-- 拼接（不推荐，有注入风险）
DECLARE @table NVARCHAR(128) = N'users';
EXEC(N'SELECT COUNT(*) FROM ' + @table);

-- ============================================================
-- sp_executesql (推荐方式，支持参数化)
-- ============================================================
-- 基本参数化查询
DECLARE @sql NVARCHAR(MAX) = N'SELECT * FROM users WHERE age > @min_age AND status = @status';
DECLARE @params NVARCHAR(MAX) = N'@min_age INT, @status NVARCHAR(20)';
EXEC sp_executesql @sql, @params, @min_age = 18, @status = N'active';

-- 带输出参数
DECLARE @sql NVARCHAR(MAX) = N'SELECT @cnt = COUNT(*) FROM users WHERE age > @min_age';
DECLARE @params NVARCHAR(MAX) = N'@min_age INT, @cnt INT OUTPUT';
DECLARE @count INT;
EXEC sp_executesql @sql, @params, @min_age = 18, @cnt = @count OUTPUT;
SELECT @count AS user_count;

-- ============================================================
-- 存储过程中的动态 SQL
-- ============================================================
CREATE PROCEDURE dbo.SearchUsers
    @column   NVARCHAR(128),
    @value    NVARCHAR(255),
    @order_by NVARCHAR(128) = 'id'
AS
BEGIN
    DECLARE @sql NVARCHAR(MAX);
    DECLARE @params NVARCHAR(MAX);

    -- 使用 QUOTENAME 防止标识符注入
    SET @sql = N'SELECT * FROM users WHERE '
             + QUOTENAME(@column) + N' = @val ORDER BY '
             + QUOTENAME(@order_by);
    SET @params = N'@val NVARCHAR(255)';

    EXEC sp_executesql @sql, @params, @val = @value;
END;

-- ============================================================
-- 动态 DDL
-- ============================================================
CREATE PROCEDURE dbo.CreateArchiveTable
    @year INT
AS
BEGIN
    DECLARE @sql NVARCHAR(MAX);
    DECLARE @table_name NVARCHAR(128) = CONCAT('orders_', @year);

    SET @sql = N'SELECT * INTO ' + QUOTENAME(@table_name)
             + N' FROM orders WHERE YEAR(order_date) = @yr';
    EXEC sp_executesql @sql, N'@yr INT', @yr = @year;
END;

-- ============================================================
-- 动态 SQL 与临时表
-- ============================================================
-- 临时表在 EXEC/sp_executesql 内创建后，在外部不可见
-- 解决方案：先创建临时表，再在动态 SQL 中填充
CREATE TABLE #temp_results (id INT, name NVARCHAR(100));
EXEC sp_executesql N'INSERT INTO #temp_results SELECT id, name FROM users WHERE age > @a',
                   N'@a INT', @a = 18;
SELECT * FROM #temp_results;
DROP TABLE #temp_results;

-- ============================================================
-- 动态 SQL 防止 SQL 注入的最佳实践
-- ============================================================
-- 1. 使用 sp_executesql 而非 EXEC()
-- 2. 使用 QUOTENAME() 处理标识符（表名、列名）
-- 3. 使用参数化查询处理值
-- 4. 验证输入（白名单）
CREATE PROCEDURE dbo.SafeDynamicQuery
    @table_name NVARCHAR(128),
    @filter_val NVARCHAR(255)
AS
BEGIN
    -- 验证表名存在
    IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = @table_name)
    BEGIN
        RAISERROR('Invalid table name', 16, 1);
        RETURN;
    END;

    DECLARE @sql NVARCHAR(MAX) = N'SELECT * FROM ' + QUOTENAME(@table_name) + N' WHERE name = @val';
    EXEC sp_executesql @sql, N'@val NVARCHAR(255)', @val = @filter_val;
END;

-- ============================================================
-- 动态 PIVOT
-- ============================================================
DECLARE @cols NVARCHAR(MAX);
DECLARE @sql NVARCHAR(MAX);

SELECT @cols = STRING_AGG(QUOTENAME(category), ', ')
FROM (SELECT DISTINCT category FROM products) AS cats;

SET @sql = N'SELECT * FROM (
    SELECT product_name, category, amount FROM sales
) AS src PIVOT (SUM(amount) FOR category IN (' + @cols + N')) AS pvt';

EXEC sp_executesql @sql;

-- 版本说明：
--   SQL Server 2000+ : sp_executesql 可用
--   SQL Server 2012+ : CONCAT 函数
--   SQL Server 2017+ : STRING_AGG 函数
-- 注意：sp_executesql 比 EXEC() 更安全，且支持执行计划缓存
-- 注意：QUOTENAME() 用于标识符，参数绑定用于值
-- 注意：动态 SQL 在 sp_executesql 中运行于不同的作用域
-- 限制：嵌套动态 SQL 最大深度 32
-- 限制：单个批处理最大 65,536 * 网络包大小
