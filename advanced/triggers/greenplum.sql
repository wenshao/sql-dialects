-- Greenplum: 触发器
--
-- 参考资料:
--   [1] Greenplum SQL Reference
--       https://docs.vmware.com/en/VMware-Greenplum/7/greenplum-database/ref_guide-sql_commands-sql_ref.html
--   [2] Greenplum Admin Guide
--       https://docs.vmware.com/en/VMware-Greenplum/7/greenplum-database/admin_guide-intro-about_greenplum.html

-- Greenplum 基于 PostgreSQL，支持触发器

-- ============================================================
-- 触发器函数（必须先创建函数）
-- ============================================================

CREATE OR REPLACE FUNCTION trg_update_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- 创建触发器
-- ============================================================

CREATE TRIGGER trg_users_updated_at
    BEFORE UPDATE ON users
    FOR EACH ROW
    EXECUTE FUNCTION trg_update_timestamp();

-- ============================================================
-- AFTER 触发器
-- ============================================================

CREATE OR REPLACE FUNCTION trg_audit_insert()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO audit_log (table_name, action, record_id, created_at)
    VALUES (TG_TABLE_NAME, TG_OP, NEW.id, NOW());
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_users_audit
    AFTER INSERT OR UPDATE OR DELETE ON users
    FOR EACH ROW
    EXECUTE FUNCTION trg_audit_insert();

-- ============================================================
-- 触发器变量
-- ============================================================

-- TG_OP: 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE'
-- TG_TABLE_NAME: 表名
-- TG_WHEN: 'BEFORE', 'AFTER', 'INSTEAD OF'
-- OLD: 旧行（UPDATE/DELETE）
-- NEW: 新行（INSERT/UPDATE）

-- ============================================================
-- 条件触发器（WHEN 子句）
-- ============================================================

CREATE TRIGGER trg_users_email_changed
    AFTER UPDATE ON users
    FOR EACH ROW
    WHEN (OLD.email IS DISTINCT FROM NEW.email)
    EXECUTE FUNCTION notify_email_change();

-- ============================================================
-- 语句级触发器
-- ============================================================

CREATE TRIGGER trg_users_truncate
    AFTER TRUNCATE ON users
    FOR EACH STATEMENT
    EXECUTE FUNCTION log_truncate();

-- ============================================================
-- INSTEAD OF（在视图上）
-- ============================================================

CREATE TRIGGER trg_view_insert
    INSTEAD OF INSERT ON user_view
    FOR EACH ROW
    EXECUTE FUNCTION handle_view_insert();

-- ============================================================
-- 管理触发器
-- ============================================================

-- 删除
DROP TRIGGER IF EXISTS trg_users_updated_at ON users;

-- 启用/禁用
ALTER TABLE users DISABLE TRIGGER trg_users_audit;
ALTER TABLE users ENABLE TRIGGER trg_users_audit;
ALTER TABLE users DISABLE TRIGGER ALL;

-- ============================================================
-- 事件触发器（DDL 事件）
-- ============================================================

CREATE EVENT TRIGGER trg_ddl ON ddl_command_end
    EXECUTE FUNCTION log_ddl_changes();

-- 注意：Greenplum 兼容 PostgreSQL 触发器语法
-- 注意：触发器在每个 Segment 上独立执行
-- 注意：分布式环境下触发器性能可能受影响
-- 注意：AO 表的触发器行为可能与 Heap 表不同
