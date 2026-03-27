-- Apache Doris: 数据库、模式与用户管理
--
-- 参考资料:
--   [1] Apache Doris Documentation - CREATE DATABASE
--       https://doris.apache.org/docs/sql-manual/sql-statements/database/CREATE-DATABASE
--   [2] Apache Doris Documentation - CREATE USER
--       https://doris.apache.org/docs/sql-manual/sql-statements/account/CREATE-USER

-- ============================================================
-- Doris 兼容 MySQL 协议
-- 命名层级: cluster > database > table
-- 没有独立的 schema 层
-- ============================================================

-- ============================================================
-- 1. 数据库管理
-- ============================================================

CREATE DATABASE myapp;
CREATE DATABASE IF NOT EXISTS myapp;

CREATE DATABASE myapp
PROPERTIES (
    'replication_allocation' = 'tag.location.default:3'  -- 3 副本
);

-- 修改数据库
ALTER DATABASE myapp SET PROPERTIES (
    'replication_allocation' = 'tag.location.default:2'
);
ALTER DATABASE myapp RENAME new_myapp;

-- 删除数据库
DROP DATABASE myapp;
DROP DATABASE IF EXISTS myapp;
DROP DATABASE myapp FORCE;                      -- 强制删除

-- 恢复（回收站机制）
RECOVER DATABASE myapp;

-- 切换数据库
USE myapp;

SHOW DATABASES;

-- ============================================================
-- 2. 用户管理
-- ============================================================

CREATE USER 'myuser'@'%' IDENTIFIED BY 'secret123';
CREATE USER 'myuser'@'10.0.0.%' IDENTIFIED BY 'secret123';  -- IP 范围

CREATE USER 'myuser' IDENTIFIED BY 'secret123'
    DEFAULT ROLE 'analyst';

-- 修改用户
ALTER USER 'myuser' IDENTIFIED BY 'newsecret';
SET PASSWORD FOR 'myuser' = PASSWORD('newsecret');

-- 删除用户
DROP USER 'myuser';

-- ============================================================
-- 3. 角色管理
-- ============================================================

CREATE ROLE analyst;
CREATE ROLE developer;

-- 系统角色: admin, operator

GRANT analyst TO 'myuser'@'%';
SET DEFAULT ROLE analyst TO 'myuser'@'%';

REVOKE analyst FROM 'myuser'@'%';
DROP ROLE analyst;

-- ============================================================
-- 4. 权限管理
-- ============================================================

-- 全局权限
GRANT ADMIN_PRIV ON *.*.* TO 'myuser'@'%';

-- 数据库权限
GRANT SELECT_PRIV ON myapp.*.* TO 'myuser'@'%';
GRANT LOAD_PRIV ON myapp.*.* TO 'myuser'@'%';

-- 表权限
GRANT SELECT_PRIV ON myapp.users TO 'myuser'@'%';
GRANT ALTER_PRIV, LOAD_PRIV ON myapp.users TO 'myuser'@'%';

-- 角色权限
GRANT SELECT_PRIV ON myapp.*.* TO ROLE 'analyst';

-- 查看权限
SHOW GRANTS FOR 'myuser'@'%';
SHOW ALL GRANTS;

-- 收回权限
REVOKE SELECT_PRIV ON myapp.*.* FROM 'myuser'@'%';

-- ============================================================
-- 5. 工作负载组（Workload Group）
-- ============================================================

-- Doris 2.0+
CREATE WORKLOAD GROUP 'rg_report'
PROPERTIES (
    'cpu_share' = '1024',
    'memory_limit' = '30%',
    'max_concurrency' = '10'
);

ALTER WORKLOAD GROUP 'rg_report'
PROPERTIES ('max_concurrency' = '20');

DROP WORKLOAD GROUP 'rg_report';

-- ============================================================
-- 6. 查询元数据
-- ============================================================

SELECT DATABASE(), USER(), CURRENT_USER();

SHOW DATABASES;
SHOW TABLES FROM myapp;
SHOW GRANTS;
SHOW ROLES;

-- 系统表
SELECT * FROM information_schema.schemata;
