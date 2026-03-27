-- SQL Server: 触发器（DML + DDL）
--
-- 参考资料:
--   [1] SQL Server T-SQL - CREATE TRIGGER
--       https://learn.microsoft.com/en-us/sql/t-sql/statements/create-trigger-transact-sql

-- ============================================================
-- 1. DML 触发器: AFTER 和 INSTEAD OF
-- ============================================================

-- SQL Server 没有 BEFORE 触发器！只有 AFTER 和 INSTEAD OF。
-- 这是 SQL Server 与所有其他主流数据库的重要区别。

-- AFTER INSERT
CREATE TRIGGER trg_users_after_insert ON users AFTER INSERT AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO audit_log (table_name, action, record_id, created_at)
    SELECT 'users', 'INSERT', id, GETDATE() FROM inserted;
END;

-- AFTER UPDATE
CREATE TRIGGER trg_users_after_update ON users AFTER UPDATE AS
BEGIN
    SET NOCOUNT ON;
    IF UPDATE(email)  -- UPDATE() 检测哪些列被修改
    BEGIN
        INSERT INTO email_change_log (user_id, old_email, new_email)
        SELECT d.id, d.email, i.email
        FROM deleted d JOIN inserted i ON d.id = i.id;
    END;
END;

-- AFTER DELETE
CREATE TRIGGER trg_users_after_delete ON users AFTER DELETE AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO users_archive SELECT *, GETDATE() FROM deleted;
END;

-- 设计分析（对引擎开发者）:
--   SQL Server 触发器的独特设计:
--   (1) 语句级（不是行级）: inserted/deleted 表可能包含多行
--       其他数据库（PostgreSQL/MySQL）支持 FOR EACH ROW 行级触发器
--   (2) 没有 BEFORE 触发器: 不能在 INSERT/UPDATE 之前修改数据
--       替代方案: INSTEAD OF 触发器（但语义完全不同——它替换整个操作）
--   (3) inserted/deleted 伪表: UPDATE 时两者都有值（deleted=旧值, inserted=新值）
--
-- 横向对比:
--   PostgreSQL: BEFORE/AFTER + FOR EACH ROW/STATEMENT（最灵活）
--               NEW/OLD 记录（行级触发器中），TRANSITION TABLE（语句级）
--   MySQL:      BEFORE/AFTER + FOR EACH ROW（只有行级）
--               NEW/OLD 关键字引用行数据
--   Oracle:     BEFORE/AFTER + FOR EACH ROW/STATEMENT
--               :NEW/:OLD 绑定变量
--
-- 对引擎开发者的启示:
--   SQL Server 缺少 BEFORE 触发器是一个功能缺失:
--   场景: 插入前自动填充计算字段、验证复杂业务规则、修改即将插入的数据
--   INSTEAD OF 不是 BEFORE 的替代——它完全替换原操作，触发器必须自己执行 INSERT。

-- ============================================================
-- 2. INSTEAD OF 触发器（SQL Server 独有能力: 可用在表上）
-- ============================================================

CREATE TRIGGER trg_view_insert ON user_view INSTEAD OF INSERT AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO users (username, email) SELECT username, email FROM inserted;
END;

-- SQL Server 的 INSTEAD OF 可以用在普通表上（不只是视图）
-- 其他数据库的 INSTEAD OF 通常只能用在视图上

-- ============================================================
-- 3. 多事件触发器
-- ============================================================

CREATE TRIGGER trg_users_audit ON users AFTER INSERT, UPDATE, DELETE AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @action NVARCHAR(10);
    IF EXISTS (SELECT 1 FROM inserted) AND EXISTS (SELECT 1 FROM deleted)
        SET @action = 'UPDATE';
    ELSE IF EXISTS (SELECT 1 FROM inserted)
        SET @action = 'INSERT';
    ELSE
        SET @action = 'DELETE';

    INSERT INTO audit_log (table_name, action, created_at)
    VALUES ('users', @action, GETDATE());
END;

-- 判断操作类型的技巧:
--   INSERT: inserted 有行, deleted 没有
--   DELETE: deleted 有行, inserted 没有
--   UPDATE: 两者都有行

-- ============================================================
-- 4. DDL 触发器（2005+）
-- ============================================================

-- 数据库级 DDL 触发器
CREATE TRIGGER trg_ddl_audit ON DATABASE
FOR CREATE_TABLE, ALTER_TABLE, DROP_TABLE AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO ddl_log (event_type, object_name, event_date, login_name)
    VALUES (
        EVENTDATA().value('(/EVENT_INSTANCE/EventType)[1]', 'NVARCHAR(100)'),
        EVENTDATA().value('(/EVENT_INSTANCE/ObjectName)[1]', 'NVARCHAR(256)'),
        GETDATE(), SUSER_SNAME()
    );
END;

-- EVENTDATA() 返回 XML 格式的事件信息——这是 SQL Server 独有的 DDL 审计机制
-- 横向对比:
--   PostgreSQL: EVENT TRIGGER（DDL 事件触发器，9.3+）
--   MySQL:      不支持 DDL 触发器
--   Oracle:     DDL 触发器 + DICTIONARY 事件

-- ============================================================
-- 5. 触发器管理
-- ============================================================

DISABLE TRIGGER trg_users_after_insert ON users;
ENABLE TRIGGER trg_users_after_insert ON users;
DISABLE TRIGGER ALL ON users;

DROP TRIGGER IF EXISTS trg_users_after_insert;  -- 2016+

-- 查看触发器
SELECT name, is_disabled, is_instead_of_trigger
FROM sys.triggers WHERE parent_id = OBJECT_ID('users');

-- ============================================================
-- 6. 触发器与性能
-- ============================================================

-- 触发器的性能影响:
--   (1) 触发器在原事务内执行——延长了事务持锁时间
--   (2) 触发器中的错误会导致整个语句回滚
--   (3) 嵌套触发器（触发器 A 触发触发器 B）默认开启（最多 32 层）
--
-- SET NOCOUNT ON 在触发器中是必须的:
--   不设置时，触发器中的 DML 会返回"受影响行数"消息，
--   这可能导致应用层误解结果集。

-- 对引擎开发者的启示:
--   触发器是数据库中最容易导致性能问题和维护困难的特性。
--   现代替代方案:
--   (1) 审计: SQL Server 2016+ 的 Temporal Tables（自动版本管理）
--   (2) 级联: 外键的 CASCADE 操作
--   (3) 计算字段: 计算列（COMPUTED COLUMN）
--   (4) 变更捕获: CDC（Change Data Capture）

-- 版本演进:
-- 2005+ : DDL 触发器, EVENTDATA()
-- 2005+ : DML 触发器增强（多事件）
-- 2016+ : DROP TRIGGER IF EXISTS
-- 注意: 没有 BEFORE 触发器
-- 注意: 触发器是语句级（inserted/deleted 可能包含多行）
-- 注意: SET NOCOUNT ON 在触发器中必须设置
