-- SQL Server: CREATE TABLE
--
-- 参考资料:
--   [1] SQL Server T-SQL - CREATE TABLE
--       https://learn.microsoft.com/en-us/sql/t-sql/statements/create-table-transact-sql
--   [2] SQL Server T-SQL - Data Types
--       https://learn.microsoft.com/en-us/sql/t-sql/data-types/data-types-transact-sql
--   [3] SQL Server T-SQL - IDENTITY
--       https://learn.microsoft.com/en-us/sql/t-sql/statements/create-table-transact-sql-identity-property

CREATE TABLE users (
    id         BIGINT        NOT NULL IDENTITY(1,1),
    username   NVARCHAR(64)  NOT NULL,
    email      NVARCHAR(255) NOT NULL,
    age        INT,
    balance    DECIMAL(10,2) DEFAULT 0.00,
    bio        NVARCHAR(MAX),
    created_at DATETIME2     NOT NULL DEFAULT GETDATE(),
    updated_at DATETIME2     NOT NULL DEFAULT GETDATE(),
    CONSTRAINT pk_users PRIMARY KEY (id),
    CONSTRAINT uk_username UNIQUE (username),
    CONSTRAINT uk_email UNIQUE (email)
);

-- SQL Server 没有 ON UPDATE CURRENT_TIMESTAMP，需要用触发器
CREATE TRIGGER trg_users_updated_at
ON users
AFTER UPDATE
AS
BEGIN
    UPDATE users
    SET updated_at = GETDATE()
    FROM users u
    INNER JOIN inserted i ON u.id = i.id;
END;
