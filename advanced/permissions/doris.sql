-- Apache Doris: 权限管理

-- ============================================================
-- 用户管理
-- ============================================================

-- 创建用户
CREATE USER alice IDENTIFIED BY 'password123';
CREATE USER alice@'192.168.1.%' IDENTIFIED BY 'password123';  -- 限制 IP

-- 修改密码
SET PASSWORD FOR alice = PASSWORD('new_password');
ALTER USER alice IDENTIFIED BY 'new_password';

-- 删除用户
DROP USER alice;

-- 查看用户
SHOW ALL GRANTS;

-- ============================================================
-- 角色管理
-- ============================================================

-- 创建角色
CREATE ROLE app_read;
CREATE ROLE app_write;
CREATE ROLE admin_role;

-- 给角色授权
GRANT SELECT_PRIV ON db.* TO ROLE app_read;
GRANT LOAD_PRIV, ALTER_PRIV ON db.* TO ROLE app_write;

-- 将角色授予用户
GRANT app_read TO alice;
GRANT app_write TO alice;

-- 删除角色
DROP ROLE app_read;

-- ============================================================
-- 数据库级权限
-- ============================================================

GRANT SELECT_PRIV ON db.* TO alice;
GRANT ALL ON db.* TO alice;

-- ============================================================
-- 表级权限
-- ============================================================

GRANT SELECT_PRIV ON db.users TO alice;
GRANT LOAD_PRIV ON db.users TO alice;      -- INSERT / Stream Load
GRANT ALTER_PRIV ON db.users TO alice;
GRANT DROP_PRIV ON db.users TO alice;

-- ============================================================
-- 全局权限
-- ============================================================

GRANT ADMIN_PRIV ON *.* TO alice;          -- 管理员权限
GRANT NODE_PRIV ON *.* TO alice;           -- 节点管理权限
GRANT GRANT_PRIV ON *.* TO alice;          -- 授权权限

-- ============================================================
-- 资源权限（2.0+）
-- ============================================================

-- Catalog 权限
GRANT USAGE_PRIV ON CATALOG hive_catalog TO alice;

-- Resource 权限
GRANT USAGE_PRIV ON RESOURCE 'spark_resource' TO alice;

-- Workload Group 权限（2.1+）
GRANT USAGE_PRIV ON WORKLOAD GROUP 'normal' TO alice;

-- ============================================================
-- 撤销权限
-- ============================================================

REVOKE SELECT_PRIV ON db.users FROM alice;
REVOKE ALL ON db.* FROM alice;
REVOKE app_read FROM alice;

-- ============================================================
-- 查看权限
-- ============================================================

SHOW GRANTS FOR alice;
SHOW ALL GRANTS;
SHOW ROLES;

-- ============================================================
-- 行级权限（Row Policy，2.1+）
-- ============================================================

-- CREATE ROW POLICY policy_name ON db.table
-- AS RESTRICTIVE TO alice
-- USING (city = 'Beijing');

-- ============================================================
-- 权限类型说明
-- ============================================================

-- SELECT_PRIV: 查询权限
-- LOAD_PRIV: 导入权限（INSERT, Stream Load 等）
-- ALTER_PRIV: ALTER TABLE 权限
-- CREATE_PRIV: 创建表/数据库权限
-- DROP_PRIV: 删除表/数据库权限
-- ADMIN_PRIV: 管理员权限（所有操作）
-- NODE_PRIV: 节点管理权限
-- GRANT_PRIV: 授权权限
-- USAGE_PRIV: 使用 Catalog/Resource 权限

-- 注意：Doris 权限模型基于 MySQL 协议
-- 注意：支持用户、角色、IP 白名单
-- 注意：2.0+ 支持 Catalog 级权限
-- 注意：2.1+ 支持行级权限（Row Policy）
