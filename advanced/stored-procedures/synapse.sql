-- Azure Synapse: 存储过程（T-SQL 子集）
--
-- 参考资料:
--   [1] Synapse SQL Features
--       https://learn.microsoft.com/en-us/azure/synapse-analytics/sql/overview-features
--   [2] Synapse T-SQL Differences
--       https://learn.microsoft.com/en-us/azure/synapse-analytics/sql/overview-features

-- 创建存储过程
CREATE PROCEDURE get_user
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

-- 带业务逻辑的存储过程
CREATE PROCEDURE upsert_users
AS
BEGIN
    -- Synapse 2022+ 支持 MERGE；以下为传统的 UPDATE + INSERT 方式
    -- 1. 更新已存在的行
    UPDATE u
    SET u.email = s.email, u.age = s.age
    FROM users u
    INNER JOIN staging_users s ON u.id = s.id;

    -- 2. 插入新行
    INSERT INTO users (id, username, email, age)
    SELECT s.id, s.username, s.email, s.age
    FROM staging_users s
    LEFT JOIN users u ON s.id = u.id
    WHERE u.id IS NULL;
END;

-- 错误处理
CREATE PROCEDURE safe_transfer
    @from_id BIGINT,
    @to_id BIGINT,
    @amount DECIMAL(10,2)
AS
BEGIN
    DECLARE @balance DECIMAL(10,2);

    BEGIN TRY
        SELECT @balance = balance FROM accounts WHERE id = @from_id;

        IF @balance < @amount
        BEGIN
            RAISERROR('Insufficient balance', 16, 1);
            RETURN;
        END

        UPDATE accounts SET balance = balance - @amount WHERE id = @from_id;
        UPDATE accounts SET balance = balance + @amount WHERE id = @to_id;
    END TRY
    BEGIN CATCH
        DECLARE @msg NVARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR(@msg, 16, 1);
    END CATCH
END;

-- 条件逻辑
CREATE PROCEDURE set_user_status
    @user_id BIGINT,
    @new_status INT
AS
BEGIN
    IF NOT EXISTS (SELECT 1 FROM users WHERE id = @user_id)
    BEGIN
        RAISERROR('User not found', 16, 1);
        RETURN;
    END

    UPDATE users SET status = @new_status WHERE id = @user_id;
END;

-- 循环（WHILE）
CREATE PROCEDURE batch_process
AS
BEGIN
    DECLARE @batch_size INT = 1000;
    DECLARE @rows_affected INT = 1;

    WHILE @rows_affected > 0
    BEGIN
        UPDATE TOP (@batch_size) users
        SET status = 1
        WHERE status = 0;

        SET @rows_affected = @@ROWCOUNT;
    END
END;

-- CTAS 存储过程（Synapse 推荐模式）
CREATE PROCEDURE rebuild_summary
AS
BEGIN
    IF OBJECT_ID('dbo.users_summary_new') IS NOT NULL
        DROP TABLE dbo.users_summary_new;

    CREATE TABLE users_summary_new
    WITH (DISTRIBUTION = HASH(city), CLUSTERED COLUMNSTORE INDEX)
    AS
    SELECT city, COUNT(*) AS cnt, AVG(CAST(age AS DECIMAL)) AS avg_age
    FROM users
    GROUP BY city;

    IF OBJECT_ID('dbo.users_summary') IS NOT NULL
        RENAME OBJECT users_summary TO users_summary_old;

    RENAME OBJECT users_summary_new TO users_summary;

    IF OBJECT_ID('dbo.users_summary_old') IS NOT NULL
        DROP TABLE users_summary_old;
END;

-- 删除存储过程
DROP PROCEDURE IF EXISTS get_user;

-- 查看存储过程
SELECT * FROM sys.procedures;
SELECT OBJECT_DEFINITION(OBJECT_ID('get_user'));

-- 注意：Synapse 存储过程使用 T-SQL 子集
-- 注意：不支持 TRY...CATCH 中的事务控制（BEGIN TRAN / COMMIT / ROLLBACK）
-- 注意：不支持临时存储过程（#temp_proc）
-- 注意：不支持 EXECUTE AS（执行上下文切换）
-- 注意：不支持游标（CURSOR）
-- 注意：CTAS + RENAME 是 Synapse 中常见的存储过程模式
-- 注意：Serverless 池不支持创建存储过程
