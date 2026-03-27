-- ClickHouse: 权限管理
--
-- 参考资料:
--   [1] ClickHouse SQL Reference - GRANT
--       https://clickhouse.com/docs/en/sql-reference/statements/grant
--   [2] ClickHouse - CREATE USER
--       https://clickhouse.com/docs/en/sql-reference/statements/create/user
--   [3] ClickHouse - Access Control
--       https://clickhouse.com/docs/en/operations/access-rights

-- ClickHouse 20.1+ 支持 RBAC（基于角色的访问控制）

-- ============================================================
-- 创建用户
-- ============================================================

CREATE USER alice IDENTIFIED WITH sha256_password BY 'StrongP@ss123';
CREATE USER bob IDENTIFIED WITH sha256_hash BY 'hash_value';
CREATE USER app_user IDENTIFIED WITH double_sha1_password BY 'password';

-- 无密码用户（仅限 localhost）
CREATE USER local_user NOT IDENTIFIED HOST LOCAL;

-- 限制访问来源
CREATE USER alice
    IDENTIFIED WITH sha256_password BY 'password'
    HOST IP '192.168.1.0/24';

CREATE USER alice HOST IP '10.0.0.0/8', IP '172.16.0.0/12';

-- 修改密码
ALTER USER alice IDENTIFIED WITH sha256_password BY 'NewP@ss456';

-- 删除用户
DROP USER IF EXISTS alice;

-- ============================================================
-- 创建角色
-- ============================================================

CREATE ROLE analyst;
CREATE ROLE data_engineer;
CREATE ROLE app_reader;

-- 授予角色给用户
GRANT analyst TO alice;
GRANT data_engineer TO bob;

-- 角色继承
GRANT analyst TO data_engineer;  -- data_engineer 继承 analyst

-- 设置默认角色
SET DEFAULT ROLE analyst TO alice;
SET DEFAULT ROLE ALL TO bob;

-- ============================================================
-- 数据库权限
-- ============================================================

GRANT SHOW DATABASES ON *.* TO analyst;
GRANT CREATE DATABASE ON *.* TO data_engineer;
GRANT ALL ON mydb.* TO data_engineer;

-- ============================================================
-- 表权限
-- ============================================================

GRANT SELECT ON mydb.users TO analyst;
GRANT SELECT, INSERT ON mydb.users TO data_engineer;
GRANT ALL ON mydb.users TO data_engineer;

-- 所有表
GRANT SELECT ON mydb.* TO analyst;

-- 所有数据库的所有表
GRANT SELECT ON *.* TO analyst;

-- ============================================================
-- 列级权限
-- ============================================================

GRANT SELECT(username, email) ON mydb.users TO analyst;
GRANT SELECT(id, username) ON mydb.users TO app_reader;

-- ============================================================
-- 行级安全（Row Policy，20.3+）
-- ============================================================

CREATE ROW POLICY policy_region ON mydb.orders
    FOR SELECT
    USING region = 'US'
    TO analyst;

-- 多个策略（取并集）
CREATE ROW POLICY policy_admin ON mydb.orders
    FOR SELECT
    USING 1 = 1
    TO data_engineer;

-- 限制性策略（取交集）
CREATE ROW POLICY policy_active ON mydb.orders
    AS RESTRICTIVE
    FOR SELECT
    USING status = 'active'
    TO ALL;

-- 删除
DROP ROW POLICY policy_region ON mydb.orders;

-- ============================================================
-- 特定权限
-- ============================================================

-- 字典权限
GRANT dictGet ON mydb.my_dict TO analyst;

-- 系统权限
GRANT SYSTEM RELOAD DICTIONARIES TO data_engineer;
GRANT SYSTEM MERGES ON mydb.users TO data_engineer;
GRANT SYSTEM MOVES ON mydb.users TO data_engineer;

-- 设置配额（限制资源使用）
CREATE QUOTA analyst_quota
    FOR INTERVAL 1 HOUR MAX QUERIES = 1000, MAX RESULT_ROWS = 1000000
    TO analyst;

-- 设置资源配置
CREATE SETTINGS PROFILE analyst_profile
    SETTINGS max_memory_usage = 10000000000,  -- 10 GB
             max_execution_time = 300          -- 5 分钟
    TO analyst;

-- ============================================================
-- 撤销权限
-- ============================================================

REVOKE SELECT ON mydb.users FROM analyst;
REVOKE ALL ON mydb.* FROM analyst;
REVOKE analyst FROM alice;

-- ============================================================
-- 查看权限
-- ============================================================

SHOW GRANTS FOR alice;
SHOW GRANTS FOR ROLE analyst;
SHOW CREATE USER alice;
SHOW USERS;
SHOW ROLES;
SHOW ROW POLICIES ON mydb.orders;

-- 系统表查询
SELECT * FROM system.users;
SELECT * FROM system.roles;
SELECT * FROM system.grants;
SELECT * FROM system.row_policies;
SELECT * FROM system.quotas;

-- 注意：RBAC 从 20.1 版本引入
-- 注意：之前版本使用 users.xml 配置文件管理权限
-- 注意：Row Policy 提供行级安全
-- 注意：Quota 限制用户资源使用
-- 注意：Settings Profile 控制用户的查询参数限制
