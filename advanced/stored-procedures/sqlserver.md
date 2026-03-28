# SQL Server: 存储过程

> 参考资料:
> - [SQL Server T-SQL - CREATE PROCEDURE](https://learn.microsoft.com/en-us/sql/t-sql/statements/create-procedure-transact-sql)
> - [SQL Server T-SQL - CREATE FUNCTION](https://learn.microsoft.com/en-us/sql/t-sql/statements/create-function-transact-sql)

## 存储过程基本语法

```sql
CREATE OR ALTER PROCEDURE dbo.GetUser  -- CREATE OR ALTER（2016 SP1+）
    @username NVARCHAR(64)
AS
BEGIN
    SET NOCOUNT ON;  -- 禁止返回"受影响的行数"消息（性能优化）
    SELECT * FROM users WHERE username = @username;
END;
```

调用
```sql
EXEC GetUser 'alice';
EXEC GetUser @username = 'alice';  -- 命名参数
```

## OUTPUT 参数

```sql
CREATE PROCEDURE dbo.GetUserCount @count INT OUTPUT
AS BEGIN
    SELECT @count = COUNT(*) FROM users;
END;

DECLARE @cnt INT;
EXEC GetUserCount @cnt OUTPUT;
SELECT @cnt;
```

## 带事务和错误处理的存储过程（标准模板）

```sql
CREATE PROCEDURE dbo.TransferFunds
    @from_id BIGINT, @to_id BIGINT, @amount DECIMAL(10,2)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;  -- 关键: 错误时自动回滚

    IF @amount <= 0 THROW 50001, N'Amount must be positive', 1;

    BEGIN TRY
        BEGIN TRANSACTION;
            DECLARE @balance DECIMAL(10,2);
            SELECT @balance = balance FROM accounts WITH (UPDLOCK) WHERE id = @from_id;
            IF @balance < @amount THROW 50002, N'Insufficient balance', 1;

            UPDATE accounts SET balance = balance - @amount WHERE id = @from_id;
            UPDATE accounts SET balance = balance + @amount WHERE id = @to_id;
        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH;
END;
```

## 函数类型: 标量函数 vs 表值函数（对引擎开发者）

标量函数（返回单个值）
```sql
CREATE FUNCTION dbo.FullName(@first NVARCHAR(50), @last NVARCHAR(50))
RETURNS NVARCHAR(101)
AS BEGIN
    RETURN @first + N' ' + @last;
END;
```

调用时必须加 schema 前缀: SELECT dbo.FullName('Alice', 'Smith');

设计分析（标量函数的性能陷阱）:
  SQL Server 的标量 UDF 在 2019 之前有严重的性能问题:
  (1) 逐行调用（不能并行执行）
  (2) 不能内联到查询计划中（每行一次函数调用）
  (3) 禁用并行执行（整个查询变为串行）
  SELECT dbo.FullName(first_name, last_name) FROM users;  -- 100万行 = 100万次函数调用

  2019+: Scalar UDF Inlining（标量函数内联）
  优化器将简单的标量函数内联到查询中，消除逐行调用开销。
  但只有满足条件的函数才能内联（不能有循环、游标、临时表等）。

内联表值函数（ITVF, 推荐）
```sql
CREATE FUNCTION dbo.ActiveUsers()
RETURNS TABLE AS
RETURN (SELECT * FROM users WHERE status = 1);

SELECT * FROM dbo.ActiveUsers();
```

ITVF 没有标量 UDF 的性能问题——它被优化器完全内联（像视图一样展开）。
这是 SQL Server 中最推荐的函数类型。

多语句表值函数（MSTVF, 不推荐）
```sql
CREATE FUNCTION dbo.GetUserStats()
RETURNS @stats TABLE (city NVARCHAR(64), cnt INT, avg_age DECIMAL(5,2))
AS BEGIN
    INSERT INTO @stats
    SELECT city, COUNT(*), AVG(CAST(age AS DECIMAL))
    FROM users GROUP BY city;
    RETURN;
END;
```

MSTVF 有与标量 UDF 类似的问题——优化器假设它返回 1 行（导致错误的计划）
2019+: Table Variable Deferred Compilation 改善了行数估算

## 函数 vs 存储过程: 选择策略

存储过程:
  + 可以执行 DML（INSERT/UPDATE/DELETE）
  + 可以有事务控制
  + 可以调用其他存储过程
  + 支持 TRY/CATCH
  - 不能在 SELECT 中调用

函数:
  + 可以在 SELECT/WHERE/JOIN 中使用
  + ITVF 可以被优化器内联
  - 不能执行 DML（只读）
  - 不能有事务控制
  - 不能调用存储过程
  - 标量 UDF 在 2019 之前有严重性能问题

## 游标（应尽量避免）

```sql
DECLARE @username NVARCHAR(64);
DECLARE cur CURSOR LOCAL FAST_FORWARD FOR
    SELECT username FROM users;
OPEN cur;
FETCH NEXT FROM cur INTO @username;
WHILE @@FETCH_STATUS = 0
BEGIN
    PRINT @username;
    FETCH NEXT FROM cur INTO @username;
END;
CLOSE cur;
DEALLOCATE cur;
```

FAST_FORWARD = 只进只读（性能最好的游标类型）
游标性能差的原因: 逐行处理，无法利用集合操作的优化。
替代方案: 窗口函数、CROSS APPLY、递归 CTE

## 临时存储过程

```sql
CREATE PROCEDURE #temp_proc AS SELECT 1;    -- 会话级（# 前缀）
CREATE PROCEDURE ##global_proc AS SELECT 1; -- 全局（## 前缀）
```

## 删除

```sql
DROP PROCEDURE IF EXISTS GetUser;     -- 2016+
DROP FUNCTION IF EXISTS dbo.FullName; -- 2016+

-- 版本演进:
-- 2005+ : TRY/CATCH, 表值函数
-- 2012+ : THROW
-- 2016+ : CREATE OR ALTER, DROP IF EXISTS
-- 2019+ : Scalar UDF Inlining, Table Variable Deferred Compilation
```
