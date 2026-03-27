-- SQL Server: 触发器
--
-- 参考资料:
--   [1] SQL Server T-SQL - CREATE TRIGGER
--       https://learn.microsoft.com/en-us/sql/t-sql/statements/create-trigger-transact-sql
--   [2] SQL Server - DML Triggers
--       https://learn.microsoft.com/en-us/sql/relational-databases/triggers/dml-triggers

-- AFTER INSERT（默认类型）
CREATE TRIGGER trg_users_after_insert
ON users
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO audit_log (table_name, action, record_id, created_at)
    SELECT 'users', 'INSERT', id, GETDATE()
    FROM inserted;  -- inserted 表包含新插入的行
END;

-- AFTER UPDATE
CREATE TRIGGER trg_users_after_update
ON users
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    -- 用 UPDATE() 函数检测哪些列被修改了
    IF UPDATE(email)
    BEGIN
        INSERT INTO email_change_log (user_id, old_email, new_email)
        SELECT d.id, d.email, i.email
        FROM deleted d  -- deleted 表包含更新前的行
        JOIN inserted i ON d.id = i.id;
    END
END;

-- AFTER DELETE
CREATE TRIGGER trg_users_after_delete
ON users
AFTER DELETE
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO users_archive (id, username, email, deleted_at)
    SELECT id, username, email, GETDATE()
    FROM deleted;
END;

-- INSTEAD OF（用于视图或表）
CREATE TRIGGER trg_view_insert
ON user_view
INSTEAD OF INSERT
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO users (username, email)
    SELECT username, email FROM inserted;
END;

-- 多事件触发器
CREATE TRIGGER trg_users_audit
ON users
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @action NVARCHAR(10);
    IF EXISTS (SELECT 1 FROM inserted) AND EXISTS (SELECT 1 FROM deleted)
        SET @action = 'UPDATE';
    ELSE IF EXISTS (SELECT 1 FROM inserted)
        SET @action = 'INSERT';
    ELSE
        SET @action = 'DELETE';

    -- 记录审计
    INSERT INTO audit_log (table_name, action, created_at)
    VALUES ('users', @action, GETDATE());
END;

-- DDL 触发器（2005+）
CREATE TRIGGER trg_ddl_audit
ON DATABASE
FOR CREATE_TABLE, ALTER_TABLE, DROP_TABLE
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO ddl_log (event_type, object_name, event_date, login_name)
    VALUES (
        EVENTDATA().value('(/EVENT_INSTANCE/EventType)[1]', 'NVARCHAR(100)'),
        EVENTDATA().value('(/EVENT_INSTANCE/ObjectName)[1]', 'NVARCHAR(256)'),
        GETDATE(),
        SUSER_SNAME()
    );
END;

-- 启用/禁用
DISABLE TRIGGER trg_users_after_insert ON users;
ENABLE TRIGGER trg_users_after_insert ON users;
DISABLE TRIGGER ALL ON users;

-- 删除
DROP TRIGGER IF EXISTS trg_users_after_insert;  -- 2016+

-- 查看触发器
SELECT * FROM sys.triggers WHERE parent_id = OBJECT_ID('users');

-- 注意：SQL Server 触发器是语句级的（inserted/deleted 可能包含多行）
-- 注意：没有 BEFORE 触发器（只有 AFTER 和 INSTEAD OF）
-- 注意：INSTEAD OF 可以用在表上（其他数据库通常只能用在视图上）
