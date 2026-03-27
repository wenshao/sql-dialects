-- Oracle: 权限管理
--
-- 参考资料:
--   [1] Oracle SQL Language Reference - GRANT
--       https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/GRANT.html
--   [2] Oracle Database Security Guide
--       https://docs.oracle.com/en/database/oracle/oracle-database/23/dbseg/

-- ============================================================
-- 1. Oracle 权限体系概览
-- ============================================================

-- Oracle 有三种权限类型:
-- 1. 系统权限: 操作数据库对象的能力（CREATE TABLE, CREATE SESSION 等）
-- 2. 对象权限: 操作特定对象的能力（SELECT ON users, INSERT ON orders 等）
-- 3. 角色: 权限的命名集合（可嵌套）

-- ============================================================
-- 2. 用户创建（user = schema，Oracle 独有的绑定关系）
-- ============================================================

CREATE USER alice IDENTIFIED BY password123
    DEFAULT TABLESPACE users
    TEMPORARY TABLESPACE temp
    QUOTA 100M ON users;

-- ============================================================
-- 3. 系统权限
-- ============================================================

GRANT CREATE SESSION TO alice;                 -- 必须! 没有这个权限无法登录
GRANT CREATE TABLE TO alice;
GRANT CREATE VIEW TO alice;
GRANT CREATE PROCEDURE TO alice;
GRANT CREATE SEQUENCE TO alice;
GRANT UNLIMITED TABLESPACE TO alice;

-- ANY 权限（跨 schema 操作）
GRANT CREATE ANY TABLE TO alice;               -- 在任何 schema 创建表
GRANT SELECT ANY TABLE TO alice;               -- 查询任何表

-- 设计分析:
--   Oracle 的系统权限有 200+ 种，是最细粒度的权限体系。
--   CREATE SESSION 是显式要求的，其他数据库通常连接即可查询。
--
-- 横向对比:
--   Oracle:     200+ 系统权限，CREATE SESSION 显式授予
--   PostgreSQL: CONNECT 权限（数据库级）+ CREATE 权限（schema 级）
--   MySQL:      GRANT 支持全局/库/表/列级别
--   SQL Server: LOGIN + DATABASE USER 两层体系

-- ============================================================
-- 4. 对象权限
-- ============================================================

GRANT SELECT ON users TO alice;
GRANT SELECT, INSERT, UPDATE ON users TO alice;
GRANT ALL ON users TO alice;

-- 列级权限（Oracle 支持列级 GRANT，这是细粒度的安全控制）
GRANT UPDATE (email, phone) ON users TO alice;

-- WITH GRANT OPTION（允许转授权限）
GRANT SELECT ON users TO alice WITH GRANT OPTION;

-- ============================================================
-- 5. 角色
-- ============================================================

CREATE ROLE app_read;
CREATE ROLE app_write;

GRANT SELECT ON users TO app_read;
GRANT INSERT, UPDATE, DELETE ON users TO app_write;
GRANT app_read, app_write TO alice;

-- 预定义角色
GRANT CONNECT TO alice;                        -- 基本连接权限
GRANT RESOURCE TO alice;                       -- 创建对象权限
GRANT DBA TO alice;                            -- 完全管理员

-- 默认角色控制
ALTER USER alice DEFAULT ROLE app_read;
ALTER USER alice DEFAULT ROLE ALL EXCEPT app_write;

-- ============================================================
-- 6. 撤销权限
-- ============================================================

REVOKE INSERT ON users FROM alice;
REVOKE app_write FROM alice;

-- Oracle 权限撤销的级联行为:
-- 系统权限: 不级联（撤销 A 的权限不影响 A 授予 B 的权限）
-- 对象权限: 级联（撤销 A 的 GRANT OPTION 会级联撤销 A 授出的权限）
-- 这与 PostgreSQL 不同（PostgreSQL 需要显式 CASCADE）

-- ============================================================
-- 7. VPD: 虚拟私有数据库（9i+，Oracle 独有的行级安全）
-- ============================================================

-- VPD 通过策略函数自动给每个查询附加 WHERE 条件
-- 用户无感知，无需修改 SQL

BEGIN
    DBMS_RLS.ADD_POLICY(
        object_schema => 'HR',
        object_name   => 'USERS',
        policy_name   => 'user_policy',
        function_schema => 'HR',
        policy_function => 'user_security_fn',
        statement_types => 'SELECT,UPDATE,DELETE'
    );
END;
/

-- 策略函数示例:
CREATE OR REPLACE FUNCTION user_security_fn(
    p_schema IN VARCHAR2, p_table IN VARCHAR2
) RETURN VARCHAR2 AS
BEGIN
    -- 每个用户只能看到自己的数据
    RETURN 'owner = SYS_CONTEXT(''USERENV'', ''SESSION_USER'')';
END;
/

-- 设计分析:
--   VPD 是 Oracle 在安全领域最重要的创新之一。
--   它在引擎层面（解析器/优化器之间）注入 WHERE 条件，
--   用户无法绕过（不像应用层过滤可以被绕过）。
--
-- 横向对比:
--   Oracle:     VPD / DBMS_RLS（最成熟，9i+）
--   PostgreSQL: Row-Level Security (RLS, 9.5+)
--               CREATE POLICY ... USING (owner = current_user)
--   SQL Server: Row-Level Security (2016+)
--   MySQL:      无原生行级安全
--
-- 对引擎开发者的启示:
--   行级安全是企业级数据库的必备功能。
--   实现方式: 在查询解析后、优化前注入额外的 WHERE 条件。
--   关键: 策略必须在引擎层面强制执行，不能依赖应用层。

-- ============================================================
-- 8. Profile: 资源限制
-- ============================================================

CREATE PROFILE strict_profile LIMIT
    PASSWORD_LIFE_TIME 90
    PASSWORD_REUSE_TIME 365
    FAILED_LOGIN_ATTEMPTS 5
    PASSWORD_LOCK_TIME 1;
ALTER USER alice PROFILE strict_profile;

-- ============================================================
-- 9. 数据字典查询
-- ============================================================

SELECT * FROM user_sys_privs;                  -- 当前用户的系统权限
SELECT * FROM user_tab_privs;                  -- 当前用户的对象权限
SELECT * FROM user_role_privs;                 -- 当前用户的角色
SELECT * FROM dba_sys_privs WHERE grantee = 'ALICE';
SELECT * FROM role_tab_privs WHERE role = 'APP_READ';

-- ============================================================
-- 10. 12c+ 多租户权限
-- ============================================================

-- 公共用户（跨所有 PDB）
-- GRANT SELECT ON users TO alice CONTAINER = ALL;

-- 删除用户
DROP USER alice CASCADE;

-- ============================================================
-- 11. 对引擎开发者的总结
-- ============================================================
-- 1. Oracle 200+ 系统权限是最细粒度的，但也最复杂。最小可行方案: 表级 GRANT。
-- 2. VPD（行级安全）是企业级数据库的核心需求，应在引擎层面实现。
-- 3. CREATE SESSION 的显式要求增加了安全性但降低了用户体验。
-- 4. 角色嵌套和默认角色控制提供了灵活的权限管理。
-- 5. Oracle 的权限撤销级联行为（对象权限级联、系统权限不级联）是特殊设计。
