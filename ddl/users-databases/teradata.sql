-- Teradata: 数据库、模式与用户管理
--
-- 参考资料:
--   [1] Teradata Documentation - CREATE DATABASE
--       https://docs.teradata.com/r/SQL-Data-Definition-Language/CREATE-DATABASE
--   [2] Teradata Documentation - CREATE USER
--       https://docs.teradata.com/r/SQL-Data-Definition-Language/CREATE-USER

-- ============================================================
-- Teradata 特殊: DATABASE 和 USER 都是存储容器
-- USER 就是一个有密码的 DATABASE
-- 命名层级: system(DBS) > database/user > object
-- 没有独立的 schema 层
-- ============================================================

-- ============================================================
-- 1. 数据库管理
-- ============================================================

CREATE DATABASE myapp
    FROM dbc                                    -- 父数据库
    AS PERMANENT = 1000000000                   -- 永久空间（字节）
    SPOOL = 500000000                           -- Spool 空间
    TEMPORARY = 200000000;                      -- 临时空间

CREATE DATABASE myapp
    FROM dbc
    AS PERMANENT = 10G
    SPOOL = 5G
    TEMPORARY = 2G
    NO FALLBACK                                 -- 无回退保护
    ACCOUNT ('$M');

-- 修改数据库
MODIFY DATABASE myapp AS PERMANENT = 20G;
MODIFY DATABASE myapp AS SPOOL = 10G;

-- 删除数据库（必须先删除所有对象）
DELETE DATABASE myapp ALL;                      -- 删除所有对象
DROP DATABASE myapp;

-- ============================================================
-- 2. 用户管理
-- ============================================================

-- Teradata 中 USER 是带密码的 DATABASE
CREATE USER myuser
    FROM dbc
    AS PASSWORD = 'secret123'
    PERMANENT = 500000000
    SPOOL = 200000000
    TEMPORARY = 100000000
    DEFAULT DATABASE = myapp
    ACCOUNT ('$M');

-- 修改用户
MODIFY USER myuser AS PASSWORD = 'newsecret';
MODIFY USER myuser AS DEFAULT DATABASE = other_db;
MODIFY USER myuser AS PERMANENT = 1G;

-- 删除用户
DELETE USER myuser ALL;
DROP USER myuser;

-- 设置默认数据库
DATABASE myapp;                                 -- 切换默认数据库

-- ============================================================
-- 3. 角色管理
-- ============================================================

CREATE ROLE analyst;
CREATE ROLE developer;

GRANT analyst TO myuser;
SET ROLE analyst;
SET ROLE ALL;

REVOKE analyst FROM myuser;
DROP ROLE analyst;

-- ============================================================
-- 4. 权限管理
-- ============================================================

-- 数据库权限
GRANT CREATE TABLE ON myapp TO myuser;
GRANT CREATE VIEW ON myapp TO myuser;
GRANT DROP TABLE ON myapp TO myuser;

-- 表权限
GRANT SELECT ON myapp.users TO myuser;
GRANT INSERT, UPDATE, DELETE ON myapp.users TO myuser;
GRANT ALL ON myapp.users TO myuser WITH GRANT OPTION;

-- 列权限
GRANT SELECT (id, username) ON myapp.users TO myuser;

-- 收回
REVOKE SELECT ON myapp.users FROM myuser;

-- 查看权限
SHOW GRANTS ON myapp TO myuser;

-- Profile（资源控制）
CREATE PROFILE limited_profile AS
    SPOOL = 1000000000
    TEMPORARY = 500000000
    DEFAULT DATABASE = myapp
    ACCOUNT ('$M');

-- ============================================================
-- 5. 查询元数据
-- ============================================================

SELECT DATABASE;                                -- 当前数据库
SELECT USER;                                    -- 当前用户

-- 列出数据库和用户
SELECT DatabaseName, OwnerName, PermSpace, SpoolSpace
FROM DBC.DatabasesV
WHERE DBKind = 'D';                             -- D=Database, U=User

-- 列出用户
SELECT DatabaseName, OwnerName, PermSpace
FROM DBC.DatabasesV
WHERE DBKind = 'U';

-- 查看权限
SELECT * FROM DBC.AllRightsV
WHERE UserName = 'myuser';

-- 查看角色
SELECT * FROM DBC.RoleMembersV;

-- 空间使用
SELECT DatabaseName, CurrentPerm, MaxPerm, PeakSpool
FROM DBC.DiskSpaceV
WHERE DatabaseName = 'myapp';
