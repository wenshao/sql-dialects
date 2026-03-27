-- Trino (formerly PrestoSQL): 权限管理
--
-- 参考资料:
--   [1] Trino - GRANT
--       https://trino.io/docs/current/sql/grant.html
--   [2] Trino - Security
--       https://trino.io/docs/current/security.html

-- Trino 权限管理取决于配置的 Access Control 插件

-- ============================================================
-- 访问控制模式
-- ============================================================

-- 1. file: 基于文件的访问控制（rules.json）
-- 2. read-only: 只允许读操作
-- 3. allow-all: 允许所有操作（默认）
-- 4. opa: Open Policy Agent 集成
-- 5. 自定义插件（如 Apache Ranger）

-- 配置文件（etc/access-control.properties）：
-- access-control.name=file
-- security.config-file=etc/rules.json

-- ============================================================
-- 文件模式的规则配置（rules.json）
-- ============================================================

-- 示例 rules.json:
-- {
--     "catalogs": [
--         {"user": "admin", "catalog": ".*", "allow": "all"},
--         {"user": "analyst.*", "catalog": "hive", "allow": "read-only"},
--         {"user": ".*", "catalog": "system", "allow": "read-only"}
--     ],
--     "schemas": [
--         {"user": "admin", "schema": ".*", "owner": true},
--         {"user": "analyst.*", "schema": "mydb\\.public", "owner": false}
--     ],
--     "tables": [
--         {"user": "analyst.*", "table": ".*", "privileges": ["SELECT"]},
--         {"user": "engineer.*", "table": ".*", "privileges": ["SELECT","INSERT","DELETE"]}
--     ]
-- }

-- ============================================================
-- SQL 权限管理（Connector 级别）
-- ============================================================

-- 部分 Connector 支持 SQL 级别的权限管理

-- Hive Connector（使用 Hive 授权）
GRANT SELECT ON hive.mydb.users TO USER alice;
GRANT SELECT, INSERT ON hive.mydb.users TO ROLE analyst;

REVOKE SELECT ON hive.mydb.users FROM USER alice;

-- 创建角色
CREATE ROLE analyst IN hive;
GRANT ROLE analyst TO USER alice IN hive;

-- ============================================================
-- 系统权限
-- ============================================================

-- SHOW SCHEMAS / SHOW TABLES 权限
-- 通过 rules.json 中的 schemas 和 tables 规则控制

-- 示例：控制谁可以创建 schema
-- {"user": "admin", "schema": ".*", "owner": true}
-- owner: true 表示可以 CREATE/DROP schema

-- ============================================================
-- 列级权限（rules.json）
-- ============================================================

-- {
--     "tables": [{
--         "user": "analyst",
--         "table": "users",
--         "privileges": ["SELECT"],
--         "columns": ["id", "username", "email"]
--     }]
-- }

-- 列掩码（Column Mask）
-- {
--     "tables": [{
--         "user": "analyst",
--         "table": "users",
--         "privileges": ["SELECT"],
--         "columns": [{
--             "name": "email",
--             "mask": "'***'"
--         }]
--     }]
-- }

-- ============================================================
-- 行级过滤（Row Filter）
-- ============================================================

-- {
--     "tables": [{
--         "user": "analyst",
--         "table": "orders",
--         "privileges": ["SELECT"],
--         "filter": "region = 'US'"
--     }]
-- }

-- ============================================================
-- Apache Ranger 集成
-- ============================================================

-- Trino 可以通过 Ranger 插件实现企业级权限管理
-- 配置: access-control.name=ranger
-- 支持细粒度的行级过滤和列级掩码

-- ============================================================
-- 身份认证
-- ============================================================

-- 密码认证
-- http-server.authentication.type=PASSWORD
-- password-authenticator.name=file
-- 或
-- password-authenticator.name=ldap

-- Kerberos 认证
-- http-server.authentication.type=KERBEROS

-- OAuth2 认证
-- http-server.authentication.type=OAUTH2

-- ============================================================
-- 查看权限
-- ============================================================

SHOW GRANTS ON TABLE hive.mydb.users;
SHOW ROLES IN hive;
SHOW ROLE GRANTS IN hive;

-- 注意：Trino 本身不存储用户信息
-- 注意：权限管理通过 Access Control 插件实现
-- 注意：推荐企业环境使用 Apache Ranger 或 OPA
-- 注意：Connector 级别的权限由底层系统管理
-- 注意：文件模式适合简单场景，规则更新需要刷新配置
