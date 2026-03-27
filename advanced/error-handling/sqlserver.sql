-- SQL Server: Error Handling
--
-- 参考资料:
--   [1] SQL Server T-SQL - TRY...CATCH
--       https://learn.microsoft.com/en-us/sql/t-sql/language-elements/try-catch-transact-sql
--   [2] SQL Server T-SQL - THROW
--       https://learn.microsoft.com/en-us/sql/t-sql/language-elements/throw-transact-sql
--   [3] SQL Server T-SQL - RAISERROR
--       https://learn.microsoft.com/en-us/sql/t-sql/language-elements/raiserror-transact-sql

-- ============================================================
-- TRY...CATCH (核心错误处理)
-- ============================================================
BEGIN TRY
    INSERT INTO users(id, username) VALUES(1, 'test');
    PRINT 'Insert succeeded';
END TRY
BEGIN CATCH
    PRINT 'Error occurred: ' + ERROR_MESSAGE();
END CATCH;

-- ============================================================
-- 错误信息函数
-- ============================================================
BEGIN TRY
    SELECT 1/0;
END TRY
BEGIN CATCH
    SELECT
        ERROR_NUMBER()    AS ErrorNumber,
        ERROR_SEVERITY()  AS ErrorSeverity,
        ERROR_STATE()     AS ErrorState,
        ERROR_PROCEDURE() AS ErrorProcedure,
        ERROR_LINE()      AS ErrorLine,
        ERROR_MESSAGE()   AS ErrorMessage;
END CATCH;

-- ============================================================
-- TRY...CATCH 与事务
-- ============================================================
BEGIN TRY
    BEGIN TRANSACTION;
        INSERT INTO orders(user_id, amount) VALUES(1, 100.00);
        INSERT INTO order_items(order_id, product_id) VALUES(SCOPE_IDENTITY(), 42);
    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;

    -- 记录错误日志
    INSERT INTO error_log(error_number, error_message, error_time)
    VALUES(ERROR_NUMBER(), ERROR_MESSAGE(), GETDATE());

    -- 重新抛出（不吞没错误）
    THROW;
END CATCH;

-- ============================================================
-- THROW (抛出异常)                                    -- 2012+
-- ============================================================
-- 抛出自定义错误
THROW 50001, N'Custom error: invalid operation', 1;

-- 在 CATCH 块中重抛
BEGIN TRY
    SELECT 1/0;
END TRY
BEGIN CATCH
    PRINT 'Logging error...';
    THROW;  -- 重抛原始错误
END CATCH;

-- ============================================================
-- RAISERROR (旧式错误抛出)
-- ============================================================
-- 基本用法
RAISERROR(N'Error: %s (code %d)', 16, 1, N'invalid input', 42);

-- 严重级别说明
-- 0-10  : 信息性消息（不触发 CATCH）
-- 11-16 : 用户可修复的错误
-- 17-19 : 资源/软件错误
-- 20-25 : 系统级致命错误（断开连接）

-- RAISERROR WITH NOWAIT（立即发送消息）
RAISERROR(N'Step 1 complete', 0, 1) WITH NOWAIT;

-- ============================================================
-- 自定义错误消息 (sp_addmessage)
-- ============================================================
EXEC sp_addmessage @msgnum = 50001,
                   @severity = 16,
                   @msgtext = N'Invalid user: %s. Age must be > %d';

-- 使用自定义消息
RAISERROR(50001, 16, 1, N'john', 18);

-- ============================================================
-- 存储过程中的错误处理
-- ============================================================
CREATE PROCEDURE dbo.TransferFunds
    @from_account INT,
    @to_account INT,
    @amount DECIMAL(10,2)
AS
BEGIN
    SET NOCOUNT ON;

    IF @amount <= 0
        THROW 50001, N'Transfer amount must be positive', 1;

    BEGIN TRY
        BEGIN TRANSACTION;

        UPDATE accounts SET balance = balance - @amount
        WHERE id = @from_account;

        IF @@ROWCOUNT = 0
            THROW 50002, N'Source account not found', 1;

        UPDATE accounts SET balance = balance + @amount
        WHERE id = @to_account;

        IF @@ROWCOUNT = 0
            THROW 50003, N'Target account not found', 1;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;

-- ============================================================
-- 嵌套 TRY...CATCH
-- ============================================================
BEGIN TRY
    BEGIN TRY
        -- 内层操作
        SELECT 1/0;
    END TRY
    BEGIN CATCH
        -- 内层捕获
        IF ERROR_NUMBER() = 8134  -- 除以零
            PRINT 'Division by zero caught in inner block';
        ELSE
            THROW;  -- 重抛给外层
    END CATCH;

    -- 继续执行
    PRINT 'Continuing after inner block';
END TRY
BEGIN CATCH
    PRINT 'Outer catch: ' + ERROR_MESSAGE();
END CATCH;

-- ============================================================
-- XACT_ABORT 与错误处理
-- ============================================================
SET XACT_ABORT ON;  -- 任何错误自动回滚整个事务
BEGIN TRY
    BEGIN TRANSACTION;
    -- 多个操作...
    COMMIT;
END TRY
BEGIN CATCH
    -- XACT_ABORT ON 时，事务已被回滚
    -- 但 @@TRANCOUNT 可能仍 > 0 (事务处于不可提交状态)
    IF XACT_STATE() <> 0
        ROLLBACK;
    THROW;
END CATCH;

-- 版本说明：
--   SQL Server 2005+ : TRY...CATCH
--   SQL Server 2005+ : RAISERROR (增强)
--   SQL Server 2012+ : THROW
-- 注意：THROW 比 RAISERROR 更简洁，推荐使用
-- 注意：THROW 不带参数只能在 CATCH 块中使用（重抛）
-- 注意：严重级别 0-10 的 RAISERROR 不会触发 CATCH
-- 注意：TRY...CATCH 不捕获编译错误和对象名解析错误
-- 限制：TRY...CATCH 不能跨批处理
-- 限制：不支持 EXCEPTION WHEN 或 DECLARE HANDLER
