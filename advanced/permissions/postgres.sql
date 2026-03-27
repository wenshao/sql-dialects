-- PostgreSQL: 权限管理
--
-- 参考资料:
--   [1] PostgreSQL Documentation - GRANT
--       https://www.postgresql.org/docs/current/sql-grant.html
--   [2] PostgreSQL Documentation - CREATE ROLE
--       https://www.postgresql.org/docs/current/sql-createrole.html
--   [3] PostgreSQL Documentation - Privileges
--       https://www.postgresql.org/docs/current/ddl-priv.html

-- 创建用户/角色（用户就是能登录的角色）
CREATE ROLE alice LOGIN PASSWORD 'password123';
CREATE USER alice WITH PASSWORD 'password123';   -- 等同于上面
CREATE ROLE app_read;                            -- 不能登录的角色（组角色）

-- 授权
GRANT SELECT ON users TO alice;
GRANT SELECT, INSERT, UPDATE ON users TO alice;
GRANT ALL PRIVILEGES ON users TO alice;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO alice;

-- 列级权限
GRANT SELECT (username, email) ON users TO alice;
GRANT UPDATE (email) ON users TO alice;

-- Schema 权限
GRANT USAGE ON SCHEMA myschema TO alice;
GRANT CREATE ON SCHEMA myschema TO alice;

-- 数据库权限
GRANT CONNECT ON DATABASE mydb TO alice;
GRANT CREATE ON DATABASE mydb TO alice;

-- 序列权限
GRANT USAGE ON SEQUENCE users_id_seq TO alice;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO alice;

-- 函数权限
GRANT EXECUTE ON FUNCTION my_function(INT) TO alice;

-- 角色继承
CREATE ROLE app_read;
CREATE ROLE app_write;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO app_read;
GRANT INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO app_write;
GRANT app_read TO alice;
GRANT app_write TO alice;

-- 默认权限（对将来创建的对象自动授权）
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO app_read;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE ON SEQUENCES TO app_read;

-- 撤销权限
REVOKE INSERT ON users FROM alice;
REVOKE ALL PRIVILEGES ON users FROM alice;
REVOKE app_read FROM alice;

-- 查看权限
\dp users                                          -- psql 命令
SELECT * FROM information_schema.role_table_grants WHERE grantee = 'alice';

-- 修改密码
ALTER ROLE alice WITH PASSWORD 'new_password';
-- 密码有效期
ALTER ROLE alice VALID UNTIL '2025-01-01';

-- 行级安全（RLS，9.5+）
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
CREATE POLICY user_policy ON users
    USING (username = current_user);               -- 只能看到自己的行
CREATE POLICY user_insert_policy ON users
    FOR INSERT
    WITH CHECK (username = current_user);

-- 删除用户
DROP ROLE alice;
DROP ROLE IF EXISTS alice;

-- 注意：PostgreSQL 没有 FLUSH PRIVILEGES，权限立即生效
-- 注意：SUPERUSER 可以绕过所有权限检查
