# Azure Synapse Analytics: Dynamic SQL

> 参考资料:
> - [Synapse SQL - sp_executesql](https://learn.microsoft.com/en-us/azure/synapse-analytics/sql/develop-dynamic-sql)
> - [Synapse SQL - T-SQL Reference](https://learn.microsoft.com/en-us/azure/synapse-analytics/sql/overview-features)


## EXEC / EXECUTE (基本动态 SQL)

```sql
DECLARE @sql NVARCHAR(MAX) = N'SELECT * FROM users WHERE status = ''active''';
EXEC(@sql);
```


## sp_executesql (推荐，支持参数化)

```sql
DECLARE @sql NVARCHAR(MAX) = N'SELECT * FROM users WHERE age > @min_age AND status = @status';
DECLARE @params NVARCHAR(MAX) = N'@min_age INT, @status NVARCHAR(20)';
EXEC sp_executesql @sql, @params, @min_age = 18, @status = N'active';
```


带输出参数
```sql
DECLARE @cnt INT;
EXEC sp_executesql
    N'SELECT @cnt = COUNT(*) FROM users WHERE age > @a',
    N'@a INT, @cnt INT OUTPUT',
    @a = 18, @cnt = @cnt OUTPUT;
SELECT @cnt;
```


## 存储过程中的动态 SQL

```sql
CREATE PROCEDURE dbo.DynamicSearch
    @table_name NVARCHAR(128),
    @filter_val NVARCHAR(255)
AS
BEGIN
    DECLARE @sql NVARCHAR(MAX);
    SET @sql = N'SELECT * FROM ' + QUOTENAME(@table_name) + N' WHERE name = @val';
    EXEC sp_executesql @sql, N'@val NVARCHAR(255)', @val = @filter_val;
END;
```


## 动态 CTAS (常用于 Synapse)

```sql
DECLARE @sql NVARCHAR(MAX);
SET @sql = N'CREATE TABLE archive_2024
WITH (DISTRIBUTION = HASH(id))
AS SELECT * FROM orders WHERE YEAR(order_date) = 2024';
EXEC(@sql);
```


版本说明：
Synapse SQL : EXEC / sp_executesql (与 SQL Server 兼容)
注意：语法与 SQL Server 基本一致
注意：使用 QUOTENAME() 防止标识符注入
注意：使用 sp_executesql 参数化防止值注入
限制：Serverless SQL Pool 不支持存储过程
限制：某些 SQL Server 特性在 Synapse 中不可用
