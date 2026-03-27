-- Azure Synapse Analytics: Error Handling
--
-- 参考资料:
--   [1] Synapse SQL Error Handling
--       https://learn.microsoft.com/en-us/azure/synapse-analytics/sql/develop-error-handling

-- ============================================================
-- TRY...CATCH (与 SQL Server 兼容)
-- ============================================================
BEGIN TRY
    INSERT INTO users(id, username) VALUES(1, 'test');
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS ErrorNumber,
           ERROR_SEVERITY() AS Severity,
           ERROR_STATE() AS State,
           ERROR_MESSAGE() AS Message;
END CATCH;

-- ============================================================
-- THROW                                               -- (T-SQL)
-- ============================================================
BEGIN TRY
    DECLARE @amt DECIMAL(10,2) = -1;
    IF @amt <= 0
        THROW 50001, N'Amount must be positive', 1;
END TRY
BEGIN CATCH
    SELECT ERROR_MESSAGE() AS msg;
END CATCH;

-- ============================================================
-- 事务与错误处理
-- ============================================================
BEGIN TRY
    BEGIN TRANSACTION;
    INSERT INTO orders(id, amount) VALUES(1, 100);
    COMMIT;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK;
    THROW;
END CATCH;

-- 注意：Synapse 支持 SQL Server 风格的 TRY/CATCH
-- 注意：Serverless SQL Pool 不支持存储过程
-- 限制：部分 SQL Server 错误处理功能可能不可用
