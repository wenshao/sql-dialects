# SQL Server: 错误处理

> 参考资料:
> - [SQL Server T-SQL - TRY...CATCH](https://learn.microsoft.com/en-us/sql/t-sql/language-elements/try-catch-transact-sql)
> - [SQL Server T-SQL - THROW / RAISERROR](https://learn.microsoft.com/en-us/sql/t-sql/language-elements/throw-transact-sql)

## TRY...CATCH 基本结构

```sql
BEGIN TRY
    INSERT INTO users(id, username) VALUES(1, 'test');
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER()    AS ErrorNumber,
           ERROR_SEVERITY()  AS Severity,
           ERROR_STATE()     AS State,
           ERROR_PROCEDURE() AS Procedure,
           ERROR_LINE()      AS Line,
           ERROR_MESSAGE()   AS Message;
END CATCH;
```

设计分析（对引擎开发者）:
  T-SQL 的 TRY/CATCH 是结构化错误处理（2005 引入）。
  之前只有 @@ERROR 全局变量——每条语句后都要检查，极易遗漏。

横向对比:
  PostgreSQL: BEGIN ... EXCEPTION WHEN ... THEN ...（PL/pgSQL 块）
              支持按错误类型分支: WHEN unique_violation THEN ...
  MySQL:      DECLARE HANDLER FOR SQLSTATE ... （类似 COBOL 风格）
  Oracle:     EXCEPTION WHEN ... THEN ...（PL/SQL 块）
              支持命名异常: WHEN NO_DATA_FOUND, DUP_VAL_ON_INDEX

  SQL Server 的 TRY/CATCH 不支持按错误类型分支——必须在 CATCH 中用
  IF/CASE 检查 ERROR_NUMBER()。这不如 PostgreSQL/Oracle 的设计优雅。

## XACT_ABORT: SQL Server 最关键的设置

```sql
SET XACT_ABORT ON;  -- 任何运行时错误自动回滚整个事务

-- XACT_ABORT 的重要性（对引擎开发者必须理解）:
--   默认 XACT_ABORT OFF 时:
--     错误只终止当前语句，事务保持打开状态。
--     后续语句继续执行！这导致"部分提交"——数据不一致。
--   SET XACT_ABORT ON 时:
--     任何运行时错误立即回滚整个事务并终止批处理。

-- 经典的"部分提交"危险场景:
-- SET XACT_ABORT OFF;  -- 默认
-- BEGIN TRANSACTION;
--     INSERT INTO orders (...) VALUES (...);  -- 成功
--     INSERT INTO order_items (...) VALUES (...);  -- 失败！
--     INSERT INTO audit_log (...) VALUES (...);  -- 继续执行！
-- COMMIT;  -- 提交了部分数据！

-- 横向对比:
--   PostgreSQL: 事务中的任何错误都会将事务标记为"已中止"（不能继续）
--   MySQL:      取决于存储引擎和错误类型（行为不一致）
--   Oracle:     错误只终止当前语句，事务继续（同 SQL Server 默认）
--
-- 对引擎开发者的启示:
--   PostgreSQL 的"错误即中止"是最安全的默认行为。
--   SQL Server 的 XACT_ABORT OFF 默认值是一个危险的设计决策。
--   最佳实践: 所有存储过程第一行应该是 SET XACT_ABORT ON。
```

## TRY/CATCH + 事务的标准模式

```sql
SET XACT_ABORT ON;
BEGIN TRY
    BEGIN TRANSACTION;
        INSERT INTO orders(user_id, amount) VALUES(1, 100.00);
        INSERT INTO order_items(order_id, product_id) VALUES(SCOPE_IDENTITY(), 42);
    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;
    -- 记录错误
    INSERT INTO error_log(error_number, error_message, error_time)
    VALUES(ERROR_NUMBER(), ERROR_MESSAGE(), GETDATE());
    THROW;  -- 重新抛出
END CATCH;
```

XACT_STATE() vs @@TRANCOUNT:
  @@TRANCOUNT: 事务嵌套深度（> 0 表示有活动事务）
  XACT_STATE(): 事务状态
    1  = 可提交的活动事务
    0  = 无活动事务
    -1 = 不可提交的活动事务（XACT_ABORT 触发后）
XACT_STATE() = -1 时只能 ROLLBACK（不能 COMMIT）

## THROW vs RAISERROR

THROW（2012+, 推荐）
```sql
THROW 50001, N'Custom error: invalid operation', 1;
-- 在 CATCH 中重抛（无参数）:
BEGIN TRY SELECT 1/0; END TRY
BEGIN CATCH THROW; END CATCH;  -- 保留原始错误信息
```

RAISERROR（旧式，仍有独特用途）
```sql
RAISERROR(N'Error: %s (code %d)', 16, 1, N'invalid input', 42);
```

严重级别: 0-10 信息性（不触发 CATCH）, 11-19 用户错误, 20+ 致命错误

RAISERROR WITH NOWAIT: 立即发送消息到客户端（THROW 不支持）
```sql
RAISERROR(N'Processing step 1...', 0, 1) WITH NOWAIT;
```

在长时间运行的脚本中显示进度——THROW 不能替代这个功能

THROW vs RAISERROR 对比:
  THROW: 更简洁, 无格式化, 总是严重级别 16, 自动中止批处理
  RAISERROR: 支持格式化 (%s %d), 可选严重级别, 不自动中止, 支持 WITH NOWAIT

## 自定义错误消息

```sql
EXEC sp_addmessage @msgnum = 50001, @severity = 16,
    @msgtext = N'Invalid user: %s. Age must be > %d';
RAISERROR(50001, 16, 1, N'john', 18);
```

## 存储过程中的错误处理模式

```sql
CREATE PROCEDURE dbo.TransferFunds
    @from_id INT, @to_id INT, @amount DECIMAL(10,2)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @amount <= 0
        THROW 50001, N'Transfer amount must be positive', 1;

    BEGIN TRY
        BEGIN TRANSACTION;
            UPDATE accounts SET balance = balance - @amount WHERE id = @from_id;
            IF @@ROWCOUNT = 0 THROW 50002, N'Source account not found', 1;

            UPDATE accounts SET balance = balance + @amount WHERE id = @to_id;
            IF @@ROWCOUNT = 0 THROW 50003, N'Target account not found', 1;
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
```

## TRY/CATCH 不能捕获的错误

以下错误类型不会被 TRY/CATCH 捕获:
  (1) 编译错误（如表名不存在——在执行前解析阶段就失败）
  (2) 语句级重编译错误
  (3) 严重级别 20+ 的致命错误（断开连接）
  (4) 客户端中断（Attention 信号）

对引擎开发者的启示:
  编译错误不被捕获是一个实际限制——如果动态 SQL 引用了不存在的表，
  TRY/CATCH 无法捕获。这是因为 SQL Server 在执行前编译整个批处理。
  解决方案: 将可能失败的代码放在 sp_executesql 中（独立的编译上下文）。

## 嵌套 TRY/CATCH

```sql
BEGIN TRY
    BEGIN TRY
        SELECT 1/0;
    END TRY
    BEGIN CATCH
        IF ERROR_NUMBER() = 8134
            PRINT 'Division by zero caught in inner block';
        ELSE
            THROW;  -- 重抛给外层
    END CATCH;
    PRINT 'Continuing after inner block';
END TRY
BEGIN CATCH
    PRINT 'Outer catch: ' + ERROR_MESSAGE();
END CATCH;
```

版本演进:
2005+ : TRY...CATCH, ERROR_*() 函数
2012+ : THROW（推荐替代 RAISERROR）
> **注意**: TRY/CATCH 不能跨批处理（不能跨 GO）
> **注意**: THROW 无参数只能在 CATCH 中使用（重抛）
核心建议: 每个存储过程第一行 SET XACT_ABORT ON
