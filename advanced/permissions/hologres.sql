-- Hologres: 权限管理
--
-- 参考资料:
--   [1] Hologres - Account Management
--       https://help.aliyun.com/zh/hologres/user-guide/user-authorization
--   [2] Hologres SQL Reference
--       https://help.aliyun.com/zh/hologres/user-guide/overview-27

-- Hologres 兼容 PostgreSQL 权限语法 + 阿里云 RAM

-- ============================================================
-- 阿里云 RAM 集成
-- ============================================================

-- Hologres 用户对应阿里云 RAM 用户或 RAM 角色
-- 需要先在阿里云 RAM 中创建用户

-- 实例级别权限通过阿里云控制台管理：
-- 超级管理员（Superuser）
-- 普通用户

-- ============================================================
-- 创建用户（映射 RAM 用户）
-- ============================================================

-- 创建用户（使用阿里云 UID）
CREATE USER "p4_uid";  -- RAM 用户的 UID
CREATE USER "RAM$主账号:子账号";

-- 授予 Superuser 权限
ALTER USER "p4_uid" SUPERUSER;

-- 取消 Superuser
ALTER USER "p4_uid" NOSUPERUSER;

-- 删除用户
DROP USER "p4_uid";

-- ============================================================
-- 角色管理
-- ============================================================

-- Hologres 内置用户组（角色）：
-- admin: 拥有实例内所有数据库的开发权限
-- developer: 拥有当前数据库的开发权限
-- viewer: 拥有当前数据库的只读权限
-- 自定义角色

-- 简化权限管理 (SPM - Simple Permission Model)
-- 通过内置角色快速管理权限

-- 开启 SPM
CALL hg_spm_enable();

-- 将用户加入角色组
CALL hg_spm_grant('mydb_admin', 'p4_uid');      -- 管理员
CALL hg_spm_grant('mydb_developer', 'p4_uid');   -- 开发者
CALL hg_spm_grant('mydb_viewer', 'p4_uid');      -- 只读

-- 移除用户
CALL hg_spm_revoke('mydb_viewer', 'p4_uid');

-- ============================================================
-- PostgreSQL 标准权限（兼容语法）
-- ============================================================

-- 数据库权限
GRANT CONNECT ON DATABASE mydb TO "p4_uid";
GRANT CREATE ON DATABASE mydb TO "p4_uid";

-- Schema 权限
GRANT USAGE ON SCHEMA public TO "p4_uid";
GRANT CREATE ON SCHEMA public TO "p4_uid";

-- 表权限
GRANT SELECT ON TABLE users TO "p4_uid";
GRANT SELECT, INSERT, UPDATE ON TABLE users TO "p4_uid";
GRANT ALL PRIVILEGES ON TABLE users TO "p4_uid";

-- 所有表
GRANT SELECT ON ALL TABLES IN SCHEMA public TO "p4_uid";

-- ============================================================
-- 列级权限
-- ============================================================

GRANT SELECT (username, email) ON TABLE users TO "p4_uid";
GRANT UPDATE (email) ON TABLE users TO "p4_uid";

-- ============================================================
-- 默认权限（对将来创建的对象自动授权）
-- ============================================================

ALTER DEFAULT PRIVILEGES IN SCHEMA public
GRANT SELECT ON TABLES TO "p4_uid";

ALTER DEFAULT PRIVILEGES IN SCHEMA public
GRANT USAGE ON SEQUENCES TO "p4_uid";

-- ============================================================
-- 创建自定义角色
-- ============================================================

CREATE ROLE analyst;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO analyst;

-- 将角色授予用户
GRANT analyst TO "p4_uid";

-- ============================================================
-- 撤销权限
-- ============================================================

REVOKE SELECT ON TABLE users FROM "p4_uid";
REVOKE ALL PRIVILEGES ON TABLE users FROM "p4_uid";
REVOKE analyst FROM "p4_uid";

-- ============================================================
-- 行级安全（RLS）
-- ============================================================

-- 启用行级安全
ALTER TABLE users ENABLE ROW LEVEL SECURITY;

-- 创建策略
CREATE POLICY user_policy ON users
    USING (department = current_user);

CREATE POLICY admin_policy ON users
    TO admin
    USING (true);

-- 删除策略
DROP POLICY user_policy ON users;

-- ============================================================
-- 查看权限
-- ============================================================

-- 兼容 PostgreSQL 查询
SELECT * FROM information_schema.role_table_grants
WHERE grantee = 'p4_uid';

-- 查看用户
SELECT * FROM pg_roles;

-- 查看权限
\dp users  -- psql 命令

-- 注意：Hologres 用户必须先在阿里云 RAM 中创建
-- 注意：推荐使用 SPM（Simple Permission Model）简化权限管理
-- 注意：兼容 PostgreSQL 标准权限语法
-- 注意：支持列级权限和行级安全（RLS）
-- 注意：默认权限（DEFAULT PRIVILEGES）可以减少管理工作
