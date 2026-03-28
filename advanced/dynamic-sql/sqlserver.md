# SQL Server: 动态 SQL

> 参考资料:
> - [SQL Server - sp_executesql](https://learn.microsoft.com/en-us/sql/relational-databases/system-stored-procedures/sp-executesql-transact-sql)

## EXEC: 基础动态 SQL（不安全）

```sql
EXEC('SELECT * FROM users WHERE id = 1');

DECLARE @sql NVARCHAR(MAX) = N'SELECT * FROM users WHERE status = ''active''';
EXEC(@sql);
```

EXEC 的致命缺陷: 不支持参数化——必须拼接字符串
这是 SQL 注入的主要来源:
```sql
DECLARE @table NVARCHAR(128) = N'users';
EXEC(N'SELECT COUNT(*) FROM ' + @table);  -- 如果 @table 来自用户输入，非常危险
```

## sp_executesql: 推荐方式（参数化、计划缓存）

```sql
DECLARE @sql NVARCHAR(MAX) = N'SELECT * FROM users WHERE age > @min_age AND status = @status';
DECLARE @params NVARCHAR(MAX) = N'@min_age INT, @status NVARCHAR(20)';
EXEC sp_executesql @sql, @params, @min_age = 18, @status = N'active';
```

设计分析（对引擎开发者）:
  sp_executesql vs EXEC 的核心差异:
  (1) 参数绑定: sp_executesql 支持参数化——值通过参数传递，不拼接到 SQL 中
  (2) 执行计划缓存: 参数化的 SQL 共享执行计划（不同参数值重用同一计划）
      EXEC 的字符串不同 → 不同的计划 → 缓存膨胀
  (3) 安全性: 参数值不被解释为 SQL 代码 → 防止注入

横向对比:
  PostgreSQL: EXECUTE format('SELECT * FROM %I WHERE id = $1', table_name) USING id_val
  MySQL:      PREPARE stmt FROM 'SELECT * FROM users WHERE id = ?'; EXECUTE stmt USING @id
  Oracle:     EXECUTE IMMEDIATE sql_text USING bind_var

对引擎开发者的启示:
  sp_executesql 的设计模式——分离 SQL 模板和参数——是所有动态 SQL 引擎的最佳实践。
  参数声明字符串 (@params) 的设计虽然冗长，但类型安全性最高。

## 输出参数（从动态 SQL 中获取结果）

```sql
DECLARE @sql NVARCHAR(MAX) = N'SELECT @cnt = COUNT(*) FROM users WHERE age > @min_age';
DECLARE @params NVARCHAR(MAX) = N'@min_age INT, @cnt INT OUTPUT';
DECLARE @count INT;
EXEC sp_executesql @sql, @params, @min_age = 18, @cnt = @count OUTPUT;
SELECT @count AS user_count;
```

## QUOTENAME: 标识符安全转义

QUOTENAME 用于安全处理表名、列名等标识符
它在标识符两边加方括号，并转义内部的 ]
```sql
SELECT QUOTENAME('users');           -- [users]
SELECT QUOTENAME('table; DROP TABLE users--'); -- [table; DROP TABLE users--]

-- 安全的动态 SQL 存储过程:
CREATE PROCEDURE dbo.SearchUsers
    @column   NVARCHAR(128),
    @value    NVARCHAR(255),
    @order_by NVARCHAR(128) = 'id'
AS
BEGIN
    -- 验证表名存在（白名单验证）
    IF NOT EXISTS (SELECT 1 FROM sys.columns
                   WHERE object_id = OBJECT_ID('users') AND name = @column)
    BEGIN
        THROW 50001, 'Invalid column name', 1;
        RETURN;
    END;

    DECLARE @sql NVARCHAR(MAX) = N'SELECT * FROM users WHERE '
        + QUOTENAME(@column) + N' = @val ORDER BY ' + QUOTENAME(@order_by);
    EXEC sp_executesql @sql, N'@val NVARCHAR(255)', @val = @value;
END;
```

设计分析:
  QUOTENAME 用于标识符（表名、列名），参数绑定用于值。
  两者结合是 SQL Server 中防止注入的完整方案:
  标识符 → QUOTENAME + 白名单验证
  值     → sp_executesql 参数绑定

横向对比:
  PostgreSQL: format('%I', identifier) 用于标识符, $1 用于参数
  MySQL:      无内置 QUOTENAME（需要手动加反引号）

## 动态 SQL 与作用域

动态 SQL 在独立的作用域中执行——变量和临时表不共享
```sql
DECLARE @x INT = 42;
EXEC sp_executesql N'SELECT @x';  -- 错误: @x 不在动态 SQL 的作用域中
```

临时表的作用域行为:
在动态 SQL 内创建的临时表，外部不可见
解决方案: 先创建临时表，再在动态 SQL 中填充
```sql
CREATE TABLE #temp_results (id INT, name NVARCHAR(100));
EXEC sp_executesql N'INSERT INTO #temp_results SELECT id, name FROM users WHERE age > @a',
                   N'@a INT', @a = 18;
SELECT * FROM #temp_results;
DROP TABLE #temp_results;
```

对引擎开发者的启示:
  动态 SQL 的作用域隔离是安全性和灵活性的权衡。
  完全隔离（SQL Server）更安全，但增加了数据传递的复杂度。
  PostgreSQL 的 EXECUTE 在同一函数作用域内——变量直接可见，更方便。

## 动态 PIVOT（最常见的动态 SQL 场景）

```sql
DECLARE @cols NVARCHAR(MAX);
DECLARE @pivot_sql NVARCHAR(MAX);

SELECT @cols = STRING_AGG(QUOTENAME(category), ', ')
FROM (SELECT DISTINCT category FROM products) AS cats;

SET @pivot_sql = N'SELECT * FROM (
    SELECT product_name, category, amount FROM sales
) AS src PIVOT (SUM(amount) FOR category IN (' + @cols + N')) AS pvt';

EXEC sp_executesql @pivot_sql;
```

## 动态 DDL

```sql
CREATE PROCEDURE dbo.CreateArchiveTable @year INT AS
BEGIN
    DECLARE @sql NVARCHAR(MAX);
    DECLARE @table_name NVARCHAR(128) = CONCAT('orders_', @year);

    SET @sql = N'SELECT * INTO ' + QUOTENAME(@table_name)
             + N' FROM orders WHERE YEAR(order_date) = @yr';
    EXEC sp_executesql @sql, N'@yr INT', @yr = @year;
END;
```

## 最佳实践总结

(1) 总是使用 sp_executesql 而非 EXEC()
(2) 值用参数绑定，标识符用 QUOTENAME + 白名单验证
(3) 注意作用域: 动态 SQL 中的变量和临时表对外部不可见
(4) 嵌套动态 SQL 最大深度 32
(5) sp_executesql 的执行计划缓存是重要的性能优势
(6) 版本: sp_executesql 从 SQL Server 2000+ 可用
