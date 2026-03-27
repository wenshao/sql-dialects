-- Oracle: 权限管理
--
-- 参考资料:
--   [1] Oracle SQL Language Reference - GRANT
--       https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/GRANT.html
--   [2] Oracle SQL Language Reference - CREATE USER
--       https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/CREATE-USER.html
--   [3] Oracle SQL Language Reference - REVOKE
--       https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/REVOKE.html

-- 创建用户
CREATE USER alice IDENTIFIED BY password123;
CREATE USER alice IDENTIFIED BY password123
    DEFAULT TABLESPACE users
    TEMPORARY TABLESPACE temp
    QUOTA 100M ON users;

-- 系统权限
GRANT CREATE SESSION TO alice;                    -- 登录权限
GRANT CREATE TABLE TO alice;
GRANT CREATE VIEW TO alice;
GRANT CREATE PROCEDURE TO alice;
GRANT CREATE SEQUENCE TO alice;
GRANT UNLIMITED TABLESPACE TO alice;

-- 对象权限
GRANT SELECT ON users TO alice;
GRANT SELECT, INSERT, UPDATE ON users TO alice;
GRANT ALL ON users TO alice;

-- 列级权限
GRANT UPDATE (email, phone) ON users TO alice;

-- WITH GRANT OPTION（允许转授）
GRANT SELECT ON users TO alice WITH GRANT OPTION;

-- 角色
CREATE ROLE app_read;
CREATE ROLE app_write;
GRANT SELECT ON users TO app_read;
GRANT INSERT, UPDATE, DELETE ON users TO app_write;
GRANT app_read, app_write TO alice;

-- 预定义角色
GRANT CONNECT TO alice;                           -- 基本连接权限
GRANT RESOURCE TO alice;                          -- 创建对象权限
GRANT DBA TO alice;                               -- 完全管理员

-- 设置默认角色
ALTER USER alice DEFAULT ROLE app_read;
ALTER USER alice DEFAULT ROLE ALL EXCEPT app_write;

-- 撤销权限
REVOKE INSERT ON users FROM alice;
REVOKE app_write FROM alice;

-- 查看权限
SELECT * FROM user_sys_privs;                     -- 当前用户的系统权限
SELECT * FROM user_tab_privs;                     -- 当前用户的对象权限
SELECT * FROM user_role_privs;                    -- 当前用户的角色
SELECT * FROM dba_sys_privs WHERE grantee = 'ALICE';
SELECT * FROM role_tab_privs WHERE role = 'APP_READ';

-- 修改密码
ALTER USER alice IDENTIFIED BY new_password;
-- 密码策略（通过 Profile）
CREATE PROFILE strict_profile LIMIT
    PASSWORD_LIFE_TIME 90
    PASSWORD_REUSE_TIME 365
    FAILED_LOGIN_ATTEMPTS 5
    PASSWORD_LOCK_TIME 1;
ALTER USER alice PROFILE strict_profile;

-- 虚拟私有数据库（VPD，行级安全，9i+）
-- 通过策略函数自动给查询附加 WHERE 条件
BEGIN
    DBMS_RLS.ADD_POLICY(
        object_schema => 'HR',
        object_name => 'USERS',
        policy_name => 'user_policy',
        function_schema => 'HR',
        policy_function => 'user_security_fn',
        statement_types => 'SELECT,UPDATE,DELETE'
    );
END;
/

-- 12c+: 多租户权限
-- GRANT SELECT ON users TO alice CONTAINER = ALL;

-- 删除用户
DROP USER alice;
DROP USER alice CASCADE;  -- 级联删除用户的所有对象
