-- Greenplum: 权限管理

-- Greenplum 基于 PostgreSQL，支持完整的权限体系

-- ============================================================
-- 用户/角色管理
-- ============================================================

-- 创建用户（能登录的角色）
CREATE ROLE alice LOGIN PASSWORD 'password123';
CREATE USER alice WITH PASSWORD 'password123';

-- 创建组角色（不能登录）
CREATE ROLE app_read;
CREATE ROLE app_write;

-- 修改密码
ALTER ROLE alice WITH PASSWORD 'new_password';
ALTER ROLE alice VALID UNTIL '2025-01-01';

-- 删除
DROP ROLE alice;
DROP ROLE IF EXISTS alice;

-- ============================================================
-- 表级权限
-- ============================================================

GRANT SELECT ON users TO alice;
GRANT SELECT, INSERT, UPDATE ON users TO alice;
GRANT ALL PRIVILEGES ON users TO alice;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO alice;

-- 列级权限
GRANT SELECT (username, email) ON users TO alice;
GRANT UPDATE (email) ON users TO alice;

-- ============================================================
-- Schema 权限
-- ============================================================

GRANT USAGE ON SCHEMA myschema TO alice;
GRANT CREATE ON SCHEMA myschema TO alice;
GRANT ALL ON SCHEMA myschema TO alice;

-- ============================================================
-- 数据库权限
-- ============================================================

GRANT CONNECT ON DATABASE mydb TO alice;
GRANT CREATE ON DATABASE mydb TO alice;
GRANT ALL ON DATABASE mydb TO alice;

-- ============================================================
-- 序列/函数权限
-- ============================================================

GRANT USAGE ON SEQUENCE users_id_seq TO alice;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO alice;
GRANT EXECUTE ON FUNCTION my_function(INT) TO alice;

-- ============================================================
-- 角色继承
-- ============================================================

GRANT SELECT ON ALL TABLES IN SCHEMA public TO app_read;
GRANT INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO app_write;
GRANT app_read TO alice;
GRANT app_write TO alice;

-- ============================================================
-- 默认权限
-- ============================================================

ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO app_read;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE ON SEQUENCES TO app_read;

-- ============================================================
-- 撤销权限
-- ============================================================

REVOKE INSERT ON users FROM alice;
REVOKE ALL PRIVILEGES ON users FROM alice;
REVOKE app_read FROM alice;

-- ============================================================
-- 查看权限
-- ============================================================

SELECT * FROM information_schema.role_table_grants WHERE grantee = 'alice';

-- ============================================================
-- 行级安全（RLS）
-- ============================================================

ALTER TABLE users ENABLE ROW LEVEL SECURITY;
CREATE POLICY user_policy ON users
    USING (username = current_user);
CREATE POLICY user_insert_policy ON users
    FOR INSERT
    WITH CHECK (username = current_user);

-- ============================================================
-- 资源队列（Greenplum 特有）
-- ============================================================

CREATE RESOURCE QUEUE analyst_queue WITH (ACTIVE_STATEMENTS=10, MEMORY_LIMIT='2GB');
ALTER ROLE alice RESOURCE QUEUE analyst_queue;

-- 资源组（Greenplum 6+）
-- CREATE RESOURCE GROUP analyst_group WITH (
--     CPU_RATE_LIMIT=20, MEMORY_LIMIT=30, CONCURRENCY=10
-- );
-- ALTER ROLE alice RESOURCE GROUP analyst_group;

-- 注意：Greenplum 兼容 PostgreSQL 权限语法
-- 注意：支持行级安全（RLS）
-- 注意：支持资源队列/资源组控制资源使用
-- 注意：SUPERUSER 可以绕过所有权限检查
