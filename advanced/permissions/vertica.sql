-- Vertica: 权限管理

-- ============================================================
-- 用户管理
-- ============================================================

-- 创建用户
CREATE USER alice IDENTIFIED BY 'password123';
CREATE USER alice IDENTIFIED BY 'password123' DEFAULT ROLE app_read;

-- 修改密码
ALTER USER alice IDENTIFIED BY 'new_password';

-- 密码策略
ALTER USER alice PASSWORD EXPIRE;
ALTER USER alice ACCOUNT LOCK;
ALTER USER alice ACCOUNT UNLOCK;

-- 删除用户
DROP USER alice;
DROP USER alice CASCADE;  -- 同时删除拥有的对象

-- ============================================================
-- 角色管理
-- ============================================================

-- 创建角色
CREATE ROLE app_read;
CREATE ROLE app_write;
CREATE ROLE admin_role;

-- 给角色授权
GRANT SELECT ON ALL TABLES IN SCHEMA public TO app_read;
GRANT INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO app_write;
GRANT ALL ON SCHEMA public TO admin_role;

-- 将角色授予用户
GRANT app_read TO alice;
GRANT app_write TO alice;

-- 设置默认角色
ALTER USER alice DEFAULT ROLE app_read;

-- 启用/禁用角色
SET ROLE app_read;
SET ROLE ALL;
SET ROLE NONE;

-- 删除角色
DROP ROLE app_read;

-- ============================================================
-- 表级权限
-- ============================================================

GRANT SELECT ON users TO alice;
GRANT SELECT, INSERT, UPDATE ON users TO alice;
GRANT ALL ON users TO alice;
GRANT ALL ON ALL TABLES IN SCHEMA public TO alice;

-- ============================================================
-- 列级权限
-- ============================================================

GRANT SELECT (username, email) ON users TO alice;

-- ============================================================
-- Schema 权限
-- ============================================================

GRANT USAGE ON SCHEMA myschema TO alice;
GRANT CREATE ON SCHEMA myschema TO alice;

-- ============================================================
-- 数据库权限
-- ============================================================

GRANT CREATE ON DATABASE mydb TO alice;
GRANT TEMP ON DATABASE mydb TO alice;

-- ============================================================
-- 撤销权限
-- ============================================================

REVOKE INSERT ON users FROM alice;
REVOKE ALL ON users FROM alice;
REVOKE app_read FROM alice;

-- ============================================================
-- 查看权限
-- ============================================================

SELECT * FROM v_catalog.grants WHERE grantee = 'alice';
SELECT * FROM v_catalog.roles;

-- 检查用户是否有权限
SELECT HAS_TABLE_PRIVILEGE('alice', 'users', 'SELECT');

-- ============================================================
-- Access Policy（Vertica 独有，行列级安全）
-- ============================================================

-- Row Access Policy（行级安全）
CREATE ACCESS POLICY ON users FOR ROWS
    WHERE username = CURRENT_USER() ENABLE;

-- Column Access Policy（列级掩码）
CREATE ACCESS POLICY ON users FOR COLUMN email
    CASE WHEN ENABLED_ROLE('admin_role') THEN email
         ELSE '***@***.com' END ENABLE;

CREATE ACCESS POLICY ON users FOR COLUMN phone
    CASE WHEN ENABLED_ROLE('admin_role') THEN phone
         ELSE SUBSTR(phone, 1, 3) || '****' || SUBSTR(phone, 8) END ENABLE;

-- 查看 Access Policy
SELECT * FROM v_catalog.access_policy;

-- 删除 Access Policy
DROP ACCESS POLICY ON users FOR ROWS;
DROP ACCESS POLICY ON users FOR COLUMN email;

-- ============================================================
-- 资源池
-- ============================================================

-- 创建资源池
CREATE RESOURCE POOL analyst_pool
    MEMORYSIZE '2G' MAXMEMORYSIZE '4G' PLANNEDCONCURRENCY 10;

-- 将用户分配到资源池
ALTER USER alice RESOURCE POOL analyst_pool;

-- 查看资源池
SELECT * FROM v_catalog.resource_pools;

-- ============================================================
-- 审计
-- ============================================================

-- 查看审计日志
SELECT * FROM v_internal.dc_requests_issued WHERE user_name = 'alice';

-- 注意：Vertica 支持丰富的权限管理
-- 注意：Access Policy 是 Vertica 独有的行列级安全机制
-- 注意：支持角色、默认角色、资源池
-- 注意：Column Access Policy 可以实现数据掩码
-- 注意：ENABLED_ROLE() 在 Policy 中检查用户角色
