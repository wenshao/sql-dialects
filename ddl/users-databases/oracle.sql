-- Oracle: 数据库、模式与用户管理
--
-- 参考资料:
--   [1] Oracle Documentation - CREATE USER
--       https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/CREATE-USER.html
--   [2] Oracle Documentation - CREATE TABLESPACE
--       https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/CREATE-TABLESPACE.html

-- ============================================================
-- Oracle 命名层级: instance > database > schema(=user) > object
-- 特殊：Oracle 中 schema 和 user 是一一对应的
-- 一个用户就是一个模式，创建用户即创建模式
-- Oracle 12c+ 引入 CDB/PDB（多租户）架构
-- ============================================================

-- ============================================================
-- 1. 数据库管理（传统模式）
-- ============================================================

-- 传统 Oracle 中，CREATE DATABASE 只在安装时执行一次
-- 由 DBA 通过 DBCA 工具或手动创建
-- CREATE DATABASE 非日常操作，此处省略

-- ============================================================
-- 2. 可插拔数据库 PDB（Oracle 12c+）
-- ============================================================

-- PDB（Pluggable Database）是多租户架构中的逻辑数据库
CREATE PLUGGABLE DATABASE mypdb
    ADMIN USER pdb_admin IDENTIFIED BY secret123
    FILE_NAME_CONVERT = ('/pdbseed/', '/mypdb/');

-- 打开 PDB
ALTER PLUGGABLE DATABASE mypdb OPEN;

-- 关闭 PDB
ALTER PLUGGABLE DATABASE mypdb CLOSE;

-- 删除 PDB
DROP PLUGGABLE DATABASE mypdb INCLUDING DATAFILES;

-- 克隆 PDB
CREATE PLUGGABLE DATABASE mypdb_clone FROM mypdb;

-- 切换到 PDB
ALTER SESSION SET CONTAINER = mypdb;

-- ============================================================
-- 3. 用户/模式管理
-- ============================================================

-- 创建用户（同时创建同名模式）
CREATE USER myuser IDENTIFIED BY secret123
    DEFAULT TABLESPACE users
    TEMPORARY TABLESPACE temp
    QUOTA 500M ON users                         -- 表空间配额
    PROFILE default;

-- Oracle 12c+ 公共用户（CDB 级别）
CREATE USER c##common_user IDENTIFIED BY secret123 CONTAINER = ALL;

-- 修改用户
ALTER USER myuser IDENTIFIED BY newsecret;
ALTER USER myuser ACCOUNT LOCK;
ALTER USER myuser ACCOUNT UNLOCK;
ALTER USER myuser PASSWORD EXPIRE;
ALTER USER myuser QUOTA UNLIMITED ON users;
ALTER USER myuser DEFAULT TABLESPACE data;

-- 删除用户
DROP USER myuser;
DROP USER myuser CASCADE;                       -- 级联删除所有对象

-- 设置当前模式（访问其他用户的对象）
ALTER SESSION SET CURRENT_SCHEMA = other_user;

-- ============================================================
-- 4. 表空间管理
-- ============================================================

CREATE TABLESPACE app_data
    DATAFILE '/u01/oradata/app_data01.dbf' SIZE 1G
    AUTOEXTEND ON NEXT 100M MAXSIZE 10G
    EXTENT MANAGEMENT LOCAL
    SEGMENT SPACE MANAGEMENT AUTO;

CREATE TEMPORARY TABLESPACE app_temp
    TEMPFILE '/u01/oradata/app_temp01.dbf' SIZE 500M;

-- 删除
DROP TABLESPACE app_data INCLUDING CONTENTS AND DATAFILES;

-- ============================================================
-- 5. 角色与权限管理
-- ============================================================

-- 系统权限
GRANT CREATE SESSION TO myuser;                 -- 必须！允许登录
GRANT CREATE TABLE TO myuser;
GRANT CREATE VIEW, CREATE SEQUENCE TO myuser;
GRANT CREATE ANY TABLE TO myuser;               -- 在任何模式创建表
GRANT UNLIMITED TABLESPACE TO myuser;

-- 对象权限
GRANT SELECT ON hr.employees TO myuser;
GRANT INSERT, UPDATE ON hr.employees TO myuser;
GRANT SELECT ON hr.employees TO myuser WITH GRANT OPTION;

-- 角色
CREATE ROLE analyst;
GRANT SELECT ANY TABLE TO analyst;
GRANT analyst TO myuser;

-- 预定义角色
GRANT CONNECT TO myuser;                        -- 基本连接
GRANT RESOURCE TO myuser;                       -- 创建对象
GRANT DBA TO myuser;                            -- DBA 权限

-- 收回权限
REVOKE CREATE TABLE FROM myuser;
REVOKE SELECT ON hr.employees FROM myuser;

-- Profile（资源限制）
CREATE PROFILE app_profile LIMIT
    SESSIONS_PER_USER 10
    CPU_PER_SESSION UNLIMITED
    IDLE_TIME 30
    FAILED_LOGIN_ATTEMPTS 5
    PASSWORD_LIFE_TIME 90
    PASSWORD_REUSE_TIME 365;

ALTER USER myuser PROFILE app_profile;

-- ============================================================
-- 6. 查询元数据
-- ============================================================

-- 当前用户信息
SELECT SYS_CONTEXT('USERENV', 'CURRENT_USER') AS current_user,
       SYS_CONTEXT('USERENV', 'CURRENT_SCHEMA') AS current_schema,
       SYS_CONTEXT('USERENV', 'DB_NAME') AS db_name,
       SYS_CONTEXT('USERENV', 'CON_NAME') AS container_name
FROM DUAL;

-- 列出用户
SELECT username, account_status, default_tablespace, created
FROM dba_users WHERE oracle_maintained = 'N';

-- 列出角色
SELECT role FROM dba_roles;

-- 查看用户权限
SELECT privilege FROM dba_sys_privs WHERE grantee = 'MYUSER';
SELECT * FROM dba_tab_privs WHERE grantee = 'MYUSER';
SELECT * FROM dba_role_privs WHERE grantee = 'MYUSER';

-- 列出表空间
SELECT tablespace_name, status, contents FROM dba_tablespaces;

-- 列出 PDB
SELECT pdb_name, status FROM cdb_pdbs;
