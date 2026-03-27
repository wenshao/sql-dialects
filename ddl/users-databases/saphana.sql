-- SAP HANA: 数据库、模式与用户管理
--
-- 参考资料:
--   [1] SAP HANA Documentation - CREATE SCHEMA
--       https://help.sap.com/docs/SAP_HANA_PLATFORM/4fe29514fd584807ac9f2a04f6754767/20d4ecad7519101497d192700ce5f3df.html
--   [2] SAP HANA Documentation - CREATE USER
--       https://help.sap.com/docs/SAP_HANA_PLATFORM/4fe29514fd584807ac9f2a04f6754767/20d5ddb075191014b594f7b11ff08ee2.html

-- ============================================================
-- SAP HANA 命名层级:
-- - 单租户: system > schema > object
-- - 多租户 (MDC): system > database(tenant) > schema > object
-- 每个用户自动拥有同名 schema
-- ============================================================

-- ============================================================
-- 1. 数据库管理（多租户 MDC）
-- ============================================================

-- 创建租户数据库（需要在 SYSTEMDB 执行）
CREATE DATABASE myapp SYSTEM USER PASSWORD 'Secret123!';

-- 修改租户数据库
ALTER DATABASE myapp CLEAR LOG;

-- 删除租户数据库
DROP DATABASE myapp;

-- 连接到租户数据库
-- 使用不同端口或通过 SQL 的多租户路由

-- ============================================================
-- 2. 模式管理
-- ============================================================

CREATE SCHEMA myschema;
CREATE SCHEMA myschema OWNED BY myuser;

-- 修改模式
ALTER SCHEMA myschema OWNER TO newowner;
-- RENAME SCHEMA 不支持，需要导出/导入

-- 删除模式
DROP SCHEMA myschema;
DROP SCHEMA myschema CASCADE;                   -- 级联删除

-- 设置当前模式
SET SCHEMA myschema;

-- 查看当前模式
SELECT CURRENT_SCHEMA FROM DUMMY;

-- ============================================================
-- 3. 用户管理
-- ============================================================

CREATE USER myuser PASSWORD 'Secret123!';

CREATE USER myuser PASSWORD 'Secret123!'
    NO FORCE_FIRST_PASSWORD_CHANGE;             -- 不要求首次修改密码

CREATE USER myuser PASSWORD 'Secret123!'
    VALID FROM '2024-01-01'
    VALID UNTIL '2026-12-31';

-- 受限用户（只能通过 HTTP 访问）
CREATE RESTRICTED USER api_user PASSWORD 'Secret123!';

-- 修改用户
ALTER USER myuser PASSWORD 'NewSecret456!';
ALTER USER myuser ACTIVATE;                     -- 激活
ALTER USER myuser DEACTIVATE;                   -- 停用
ALTER USER myuser RESET CONNECT ATTEMPTS;       -- 重置登录失败计数
ALTER USER myuser SET PARAMETER CLIENT = 'RFC';

-- 删除用户
DROP USER myuser;
DROP USER myuser CASCADE;

-- ============================================================
-- 4. 角色管理
-- ============================================================

CREATE ROLE analyst;
CREATE ROLE developer;

-- 系统角色
-- CONTENT_ADMIN, MODELING, MONITORING, PUBLIC, SAP_INTERNAL_HANA_SUPPORT

GRANT analyst TO myuser;
GRANT developer TO myuser WITH ADMIN OPTION;    -- 可以再授予他人

REVOKE analyst FROM myuser;
DROP ROLE analyst;

-- ============================================================
-- 5. 权限管理
-- ============================================================

-- 系统权限
GRANT CREATE SCHEMA TO myuser;
GRANT USER ADMIN TO admin_user;                 -- 管理用户
GRANT CATALOG READ TO analyst;                  -- 读取系统目录

-- 模式权限
GRANT SELECT ON SCHEMA myschema TO analyst;
GRANT INSERT, UPDATE, DELETE ON SCHEMA myschema TO developer;
GRANT ALL PRIVILEGES ON SCHEMA myschema TO myuser;

-- 对象权限
GRANT SELECT ON myschema.users TO analyst;
GRANT ALL PRIVILEGES ON myschema.users TO developer;

-- 收回权限
REVOKE SELECT ON myschema.users FROM analyst;

-- 结构化权限（SAP HANA 特有）
CREATE STRUCTURED PRIVILEGE my_analytic_priv
    FOR SELECT ON myschema.my_view
    WHERE region = 'APAC'
    RESTRICT;

GRANT STRUCTURED PRIVILEGE my_analytic_priv TO analyst;

-- ============================================================
-- 6. 查询元数据
-- ============================================================

SELECT CURRENT_SCHEMA, CURRENT_USER, SESSION_USER FROM DUMMY;

SELECT SCHEMA_NAME, SCHEMA_OWNER FROM SCHEMAS;
SELECT USER_NAME, USER_DEACTIVATED, CREATOR FROM USERS;
SELECT ROLE_NAME FROM ROLES;

SELECT * FROM GRANTED_PRIVILEGES WHERE GRANTEE = 'MYUSER';
SELECT * FROM GRANTED_ROLES WHERE GRANTEE = 'MYUSER';

-- 系统视图
SELECT * FROM M_DATABASES;                      -- 多租户数据库列表
SELECT * FROM M_SCHEMA_MEMORY;                  -- 模式内存使用
