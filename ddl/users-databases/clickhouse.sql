-- ClickHouse: 数据库、模式与用户管理
--
-- 参考资料:
--   [1] ClickHouse Documentation - CREATE DATABASE
--       https://clickhouse.com/docs/en/sql-reference/statements/create/database
--   [2] ClickHouse Documentation - Access Control
--       https://clickhouse.com/docs/en/operations/access-rights

-- ============================================================
-- ClickHouse 命名层级: cluster > database > table
-- 没有独立的 schema 层
-- database 相当于其他数据库的 schema
-- ============================================================

-- ============================================================
-- 1. 数据库管理
-- ============================================================

CREATE DATABASE myapp;
CREATE DATABASE IF NOT EXISTS myapp;

-- 指定数据库引擎
CREATE DATABASE myapp ENGINE = Atomic;          -- 默认引擎（推荐）
CREATE DATABASE myapp ENGINE = Lazy(3600);      -- 延迟加载，适合大量小表

-- MaterializedMySQL / MaterializedPostgreSQL（实时复制）
-- CREATE DATABASE mysql_replica ENGINE = MaterializedMySQL('host:3306', 'sourcedb', 'user', 'pass');
-- CREATE DATABASE pg_replica ENGINE = MaterializedPostgreSQL('host:5432', 'sourcedb', 'user', 'pass');

-- 修改数据库
-- ClickHouse 不支持 ALTER DATABASE 修改属性

-- 删除数据库
DROP DATABASE myapp;
DROP DATABASE IF EXISTS myapp;

-- 切换数据库
USE myapp;

-- 查看数据库
SHOW DATABASES;

-- ============================================================
-- 2. 用户管理（ClickHouse 20.5+）
-- ============================================================

CREATE USER myuser IDENTIFIED BY 'secret123';
CREATE USER IF NOT EXISTS myuser IDENTIFIED BY 'secret123';

CREATE USER myuser
    IDENTIFIED WITH sha256_password BY 'secret123'
    HOST ANY                                    -- 允许任意主机
    DEFAULT DATABASE myapp
    DEFAULT ROLE analyst
    SETTINGS max_memory_usage = 10000000000;    -- 用户级设置限制

-- 主机限制
CREATE USER myuser IDENTIFIED BY 'secret123'
    HOST LOCAL;                                 -- 仅本地
CREATE USER myuser IDENTIFIED BY 'secret123'
    HOST IP '10.0.0.0/8';                       -- IP 范围

-- 修改用户
ALTER USER myuser IDENTIFIED BY 'newsecret';
ALTER USER myuser DEFAULT ROLE analyst;
ALTER USER myuser SETTINGS max_memory_usage = 20000000000;

-- 删除用户
DROP USER myuser;
DROP USER IF EXISTS myuser;

-- ============================================================
-- 3. 角色管理
-- ============================================================

CREATE ROLE analyst;
CREATE ROLE developer;
CREATE ROLE IF NOT EXISTS data_engineer;

GRANT analyst TO myuser;
SET DEFAULT ROLE analyst TO myuser;

-- 角色继承
GRANT analyst TO developer;                     -- developer 继承 analyst

-- 激活角色（当前会话）
SET ROLE analyst;
SET ROLE DEFAULT;

DROP ROLE analyst;

-- ============================================================
-- 4. 权限管理
-- ============================================================

-- 数据库权限
GRANT SHOW DATABASES ON *.* TO myuser;
GRANT CREATE ON myapp.* TO developer;

-- 表权限
GRANT SELECT ON myapp.users TO analyst;
GRANT SELECT ON myapp.* TO analyst;
GRANT INSERT, ALTER ON myapp.events TO developer;

-- 列权限
GRANT SELECT(id, username) ON myapp.users TO myuser;

-- 管理权限
GRANT CREATE USER ON *.* TO admin;

-- 查看权限
SHOW GRANTS FOR myuser;

-- 收回权限
REVOKE SELECT ON myapp.users FROM analyst;

-- ============================================================
-- 5. 配额（资源限制）
-- ============================================================

CREATE QUOTA monthly_quota
    FOR INTERVAL 1 MONTH
    MAX QUERIES 10000
    MAX RESULT ROWS 1000000000
    MAX READ ROWS 10000000000
    TO analyst;

DROP QUOTA monthly_quota;

-- ============================================================
-- 6. 行级策略
-- ============================================================

CREATE ROW POLICY region_filter ON myapp.sales
    FOR SELECT
    USING region = 'APAC'
    TO analyst;

DROP ROW POLICY region_filter ON myapp.sales;

-- ============================================================
-- 7. Settings Profile
-- ============================================================

CREATE SETTINGS PROFILE limited_profile
    SETTINGS
        max_memory_usage = 10000000000 MIN 1000000 MAX 20000000000,
        max_execution_time = 300
    TO analyst;

DROP SETTINGS PROFILE limited_profile;

-- ============================================================
-- 8. 查询元数据
-- ============================================================

SHOW DATABASES;
SHOW TABLES FROM myapp;
SHOW CREATE DATABASE myapp;

SELECT name, engine FROM system.databases;
SELECT name FROM system.users;
SELECT name FROM system.roles;
SELECT * FROM system.grants WHERE user_name = 'myuser';
SELECT * FROM system.quotas;
SELECT * FROM system.row_policies;

-- 当前用户和数据库
SELECT currentUser(), currentDatabase();

-- ============================================================
-- 9. 集群数据库（分布式）
-- ============================================================

-- 在集群所有节点创建数据库
CREATE DATABASE myapp ON CLUSTER my_cluster;
DROP DATABASE myapp ON CLUSTER my_cluster;

-- 注意：ClickHouse 早期版本使用配置文件管理用户
-- 20.5+ 支持 SQL 方式的访问控制（需要启用）
-- 配置: <access_management>1</access_management>
