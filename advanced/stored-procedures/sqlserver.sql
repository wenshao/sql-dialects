-- SQL Server: 存储过程和函数（T-SQL）
--
-- 参考资料:
--   [1] SQL Server T-SQL - CREATE PROCEDURE
--       https://learn.microsoft.com/en-us/sql/t-sql/statements/create-procedure-transact-sql
--   [2] SQL Server T-SQL - CREATE FUNCTION
--       https://learn.microsoft.com/en-us/sql/t-sql/statements/create-function-transact-sql

-- 创建存储过程
CREATE OR ALTER PROCEDURE get_user    -- 2016 SP1+: CREATE OR ALTER
    @username NVARCHAR(64)
AS
BEGIN
    SELECT * FROM users WHERE username = @username;
END;

-- 调用
EXEC get_user 'alice';
EXEC get_user @username = 'alice';

-- OUTPUT 参数
CREATE PROCEDURE get_user_count
    @count INT OUTPUT
AS
BEGIN
    SELECT @count = COUNT(*) FROM users;
END;

DECLARE @cnt INT;
EXEC get_user_count @cnt OUTPUT;
SELECT @cnt;

-- 带事务和错误处理
CREATE PROCEDURE transfer
    @from_id BIGINT,
    @to_id BIGINT,
    @amount DECIMAL(10,2)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @balance DECIMAL(10,2);

    BEGIN TRY
        BEGIN TRAN;

        SELECT @balance = balance FROM accounts WITH (UPDLOCK) WHERE id = @from_id;

        IF @balance < @amount
        BEGIN
            RAISERROR('Insufficient balance', 16, 1);
            RETURN;
        END

        UPDATE accounts SET balance = balance - @amount WHERE id = @from_id;
        UPDATE accounts SET balance = balance + @amount WHERE id = @to_id;

        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;  -- 2012+
    END CATCH
END;

-- 函数（标量函数）
CREATE FUNCTION dbo.full_name(@first NVARCHAR(50), @last NVARCHAR(50))
RETURNS NVARCHAR(101)
AS
BEGIN
    RETURN @first + N' ' + @last;
END;

SELECT dbo.full_name('Alice', 'Smith');  -- 必须加 schema 前缀

-- 表值函数（内联）
CREATE FUNCTION dbo.active_users()
RETURNS TABLE
AS
RETURN (SELECT * FROM users WHERE status = 1);

SELECT * FROM dbo.active_users();

-- 表值函数（多语句）
CREATE FUNCTION dbo.get_user_stats()
RETURNS @stats TABLE (city NVARCHAR(64), cnt INT, avg_age DECIMAL(5,2))
AS
BEGIN
    INSERT INTO @stats
    SELECT city, COUNT(*), AVG(CAST(age AS DECIMAL))
    FROM users GROUP BY city;
    RETURN;
END;

-- 游标
DECLARE @username NVARCHAR(64);
DECLARE cur CURSOR FOR SELECT username FROM users;
OPEN cur;
FETCH NEXT FROM cur INTO @username;
WHILE @@FETCH_STATUS = 0
BEGIN
    PRINT @username;
    FETCH NEXT FROM cur INTO @username;
END
CLOSE cur;
DEALLOCATE cur;

-- 临时存储过程
CREATE PROCEDURE #temp_proc AS SELECT 1;   -- 会话级
CREATE PROCEDURE ##global_proc AS SELECT 1; -- 全局临时

-- 删除
DROP PROCEDURE IF EXISTS get_user;  -- 2016+
DROP FUNCTION IF EXISTS dbo.full_name;
