-- PostgreSQL: 触发器
--
-- 参考资料:
--   [1] PostgreSQL Documentation - CREATE TRIGGER
--       https://www.postgresql.org/docs/current/sql-createtrigger.html
--   [2] PostgreSQL Documentation - Trigger Functions
--       https://www.postgresql.org/docs/current/plpgsql-trigger.html

-- 触发器函数（必须先创建函数）
CREATE OR REPLACE FUNCTION trg_update_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;  -- BEFORE 触发器必须返回 NEW（或 NULL 取消操作）
END;
$$ LANGUAGE plpgsql;

-- 创建触发器
CREATE TRIGGER trg_users_updated_at
    BEFORE UPDATE ON users
    FOR EACH ROW
    EXECUTE FUNCTION trg_update_timestamp();

-- AFTER 触发器
CREATE OR REPLACE FUNCTION trg_audit_insert()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        INSERT INTO audit_log (table_name, action, record_id, new_data)
        VALUES (TG_TABLE_NAME, TG_OP, OLD.id, to_jsonb(OLD));
        RETURN OLD;
    ELSE
        INSERT INTO audit_log (table_name, action, record_id, new_data)
        VALUES (TG_TABLE_NAME, TG_OP, NEW.id, to_jsonb(NEW));
        RETURN NEW;
    END IF;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_users_audit
    AFTER INSERT OR UPDATE OR DELETE ON users
    FOR EACH ROW
    EXECUTE FUNCTION trg_audit_insert();

-- 触发器变量
-- TG_OP: 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE'
-- TG_TABLE_NAME: 表名
-- TG_WHEN: 'BEFORE', 'AFTER', 'INSTEAD OF'
-- OLD: 旧行（UPDATE/DELETE）
-- NEW: 新行（INSERT/UPDATE）

-- 条件触发器（WHEN 子句，9.0+）
CREATE TRIGGER trg_users_email_changed
    AFTER UPDATE ON users
    FOR EACH ROW
    WHEN (OLD.email IS DISTINCT FROM NEW.email)
    EXECUTE FUNCTION notify_email_change();

-- 语句级触发器（不是 FOR EACH ROW）
CREATE TRIGGER trg_users_truncate
    AFTER TRUNCATE ON users
    FOR EACH STATEMENT
    EXECUTE FUNCTION log_truncate();

-- INSTEAD OF（在视图上）
CREATE TRIGGER trg_view_insert
    INSTEAD OF INSERT ON user_view
    FOR EACH ROW
    EXECUTE FUNCTION handle_view_insert();

-- 11+: 分区表上的行级触发器自动继承到分区
-- 15+: MERGE 操作也会触发触发器

-- 删除触发器
DROP TRIGGER IF EXISTS trg_users_updated_at ON users;

-- 启用/禁用
ALTER TABLE users DISABLE TRIGGER trg_users_audit;
ALTER TABLE users ENABLE TRIGGER trg_users_audit;
ALTER TABLE users DISABLE TRIGGER ALL;

-- 事件触发器（9.3+，DDL 事件）
CREATE EVENT TRIGGER trg_ddl ON ddl_command_end
    EXECUTE FUNCTION log_ddl_changes();
