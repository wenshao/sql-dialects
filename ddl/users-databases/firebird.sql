-- Firebird: 数据库、模式与用户管理
--
-- 参考资料:
--   [1] Firebird Documentation - CREATE DATABASE
--       https://firebirdsql.org/file/documentation/html/en/refdocs/fblangref40/firebird-40-language-reference.html#fblangref40-ddl-db-create
--   [2] Firebird Documentation - CREATE USER
--       https://firebirdsql.org/file/documentation/html/en/refdocs/fblangref40/firebird-40-language-reference.html#fblangref40-security-user-create

-- ============================================================
-- Firebird 特性：
-- - 数据库 = 一个文件（类似 SQLite）
-- - 没有 schema 概念（所有对象在同一命名空间）
-- - 有内建的用户管理
-- - 命名层级: server > database > object
-- ============================================================

-- ============================================================
-- 1. 数据库管理
-- ============================================================

-- 创建数据库（ISQL 工具中执行）
CREATE DATABASE 'C:\data\myapp.fdb'
    USER 'SYSDBA' PASSWORD 'masterkey'
    PAGE_SIZE 16384
    DEFAULT CHARACTER SET UTF8;

-- 连接数据库
-- CONNECT 'C:\data\myapp.fdb' USER 'SYSDBA' PASSWORD 'masterkey';

-- 删除数据库（当前连接的数据库）
DROP DATABASE;

-- 修改数据库
ALTER DATABASE SET DEFAULT CHARACTER SET UTF8;
ALTER DATABASE SET LINGER TO 60;                -- 连接保持（Firebird 3.0+）

-- 数据库备份/恢复通过 gbak 工具
-- $ gbak -b myapp.fdb myapp.fbk
-- $ gbak -c myapp.fbk myapp_restored.fdb

-- ============================================================
-- 2. 用户管理
-- ============================================================

-- Firebird 3.0+ 使用 SQL 管理用户
CREATE USER myuser PASSWORD 'secret123';

CREATE USER myuser PASSWORD 'secret123'
    FIRSTNAME 'Alice'
    LASTNAME 'Smith'
    GRANT ADMIN ROLE;                           -- 授予管理员角色

-- 修改用户
ALTER USER myuser PASSWORD 'newsecret';
ALTER USER myuser FIRSTNAME 'Bob';
ALTER USER myuser INACTIVE;                     -- 禁用（Firebird 3.0+）
ALTER USER myuser ACTIVE;                       -- 启用

-- 删除用户
DROP USER myuser;

-- ============================================================
-- 3. 角色管理
-- ============================================================

CREATE ROLE analyst;
CREATE ROLE developer;

GRANT analyst TO myuser;
GRANT developer TO myuser WITH ADMIN OPTION;    -- 可以再授予他人

REVOKE analyst FROM myuser;
DROP ROLE analyst;

-- ============================================================
-- 4. 权限管理
-- ============================================================

GRANT SELECT ON TABLE users TO myuser;
GRANT INSERT, UPDATE, DELETE ON TABLE users TO myuser;
GRANT ALL ON TABLE users TO myuser;
GRANT SELECT ON TABLE users TO analyst;

-- 存储过程权限
GRANT EXECUTE ON PROCEDURE my_proc TO myuser;

-- 角色权限
GRANT SELECT ON TABLE users TO ROLE analyst;

-- 收回权限
REVOKE SELECT ON TABLE users FROM myuser;
REVOKE ALL ON TABLE users FROM myuser;

-- ============================================================
-- 5. 查询元数据
-- ============================================================

SELECT CURRENT_USER, CURRENT_ROLE FROM RDB$DATABASE;

-- 列出用户
SELECT SEC$USER_NAME, SEC$ACTIVE FROM SEC$USERS;

-- 列出角色
SELECT RDB$ROLE_NAME FROM RDB$ROLES;

-- 列出表
SELECT RDB$RELATION_NAME FROM RDB$RELATIONS
WHERE RDB$SYSTEM_FLAG = 0;

-- 查看权限
SELECT RDB$USER, RDB$PRIVILEGE, RDB$RELATION_NAME
FROM RDB$USER_PRIVILEGES
WHERE RDB$USER = 'MYUSER';

-- 数据库信息
SELECT MON$DATABASE_NAME, MON$PAGE_SIZE, MON$ODS_MAJOR
FROM MON$DATABASE;
