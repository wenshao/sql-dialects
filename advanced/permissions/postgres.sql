-- PostgreSQL: 权限管理 (Permissions & RBAC)
--
-- 参考资料:
--   [1] PostgreSQL Documentation - Privileges
--       https://www.postgresql.org/docs/current/ddl-priv.html
--   [2] PostgreSQL Documentation - Row Security Policies
--       https://www.postgresql.org/docs/current/ddl-rowsecurity.html

-- ============================================================
-- 1. 角色与用户
-- ============================================================

-- PostgreSQL 的统一模型: USER = ROLE WITH LOGIN
CREATE ROLE alice LOGIN PASSWORD 'password123';
CREATE USER alice WITH PASSWORD 'password123';   -- 等同上面
CREATE ROLE app_read NOLOGIN;                    -- 不能登录的"组角色"

-- ============================================================
-- 2. 权限层级: Database → Schema → Table → Column → Row
-- ============================================================

-- 数据库权限
GRANT CONNECT ON DATABASE mydb TO alice;
GRANT CREATE ON DATABASE mydb TO alice;

-- Schema 权限（必须先 GRANT USAGE 才能访问内部对象）
GRANT USAGE ON SCHEMA myschema TO alice;
GRANT CREATE ON SCHEMA myschema TO alice;

-- 表权限
GRANT SELECT ON users TO alice;
GRANT SELECT, INSERT, UPDATE, DELETE ON users TO alice;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO alice;

-- 列级权限
GRANT SELECT (username, email) ON users TO alice;
GRANT UPDATE (email) ON users TO alice;

-- 序列/函数权限
GRANT USAGE ON SEQUENCE users_id_seq TO alice;
GRANT EXECUTE ON FUNCTION my_function(INT) TO alice;

-- ============================================================
-- 3. 角色继承 (RBAC)
-- ============================================================

CREATE ROLE app_read NOLOGIN;
CREATE ROLE app_write NOLOGIN;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO app_read;
GRANT INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO app_write;

-- 角色层级: app_write 继承 app_read
GRANT app_read TO app_write;
GRANT app_write TO alice;     -- alice 自动获得 app_read + app_write 权限

-- 14+: INHERIT FALSE（需要 SET ROLE 激活）
GRANT admin TO alice WITH INHERIT FALSE;
-- alice 需要 SET ROLE admin 才能使用 admin 权限（更安全的最小权限原则）

-- 预定义角色 (14+)
GRANT pg_read_all_data TO analyst;     -- 读取所有表
GRANT pg_write_all_data TO app_user;   -- 写入所有表
GRANT pg_monitor TO monitor_user;      -- 监控视图访问

-- ============================================================
-- 4. DEFAULT PRIVILEGES: 自动授权
-- ============================================================

ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO app_read;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE ON SEQUENCES TO app_write;

-- 注意: DEFAULT PRIVILEGES 绑定到执行 ALTER 的角色!
-- 如果 admin 设了 DEFAULT PRIVILEGES，只有 admin 创建的对象才生效。
-- 其他用户创建的对象不受影响。

-- ============================================================
-- 5. 行级安全 (RLS, 9.5+)
-- ============================================================

ALTER TABLE users ENABLE ROW LEVEL SECURITY;

-- 读策略: USING
CREATE POLICY user_isolation ON users USING (username = current_user);
-- 写策略: WITH CHECK
CREATE POLICY user_insert ON users FOR INSERT WITH CHECK (username = current_user);
-- 组合: 不同操作不同策略
CREATE POLICY user_select ON users FOR SELECT USING (department = current_setting('app.dept'));
CREATE POLICY user_update ON users FOR UPDATE
    USING (department = current_setting('app.dept'))
    WITH CHECK (department = current_setting('app.dept'));

-- RLS 的内部实现:
--   策略条件作为隐式 WHERE 子句注入查询优化器。
--   即使发生 SQL 注入，RLS 也能防止数据泄露。
--   表 OWNER 和 SUPERUSER 默认绕过 RLS:
ALTER TABLE users FORCE ROW LEVEL SECURITY; -- 强制 OWNER 也受 RLS 约束

-- ============================================================
-- 6. 权限查看
-- ============================================================

-- psql 命令: \dp users
SELECT * FROM information_schema.role_table_grants WHERE grantee = 'alice';
SELECT rolname, rolsuper, rolcreatedb, rolcanlogin FROM pg_roles;

-- ============================================================
-- 7. 横向对比: 权限模型
-- ============================================================

-- 1. 权限粒度:
--   PostgreSQL: Database > Schema > Table > Column > Row (RLS)
--   MySQL:      Database > Table > Column（无 Schema 级，无原生 RLS）
--   Oracle:     Schema > Table > Column > Row (VPD)
--   SQL Server: Database > Schema > Table > Column > Row (RLS, 2016+)
--
-- 2. 权限即时生效:
--   PostgreSQL: 权限立即生效（无需 FLUSH PRIVILEGES）
--   MySQL:      GRANT 立即生效，但修改 mysql.user 表后需要 FLUSH
--
-- 3. 行级安全:
--   PostgreSQL: RLS (9.5+)，策略在优化器中注入
--   Oracle:     VPD (Virtual Private Database)，类似但配置更复杂
--   MySQL:      不支持（需视图或应用层实现）
--
-- 4. 默认权限:
--   PostgreSQL: ALTER DEFAULT PRIVILEGES（自动授权新对象）
--   MySQL:      无等价功能
--   Oracle:     无等价功能（通常用角色+定期脚本）

-- ============================================================
-- 8. 对引擎开发者的启示
-- ============================================================

-- (1) RBAC（角色继承）是权限管理的最佳实践:
--     直接给用户授权 → 管理混乱（N用户×M对象）。
--     角色作为权限集合 → 只需管理少量角色。
--
-- (2) RLS 是安全的最后一道防线:
--     在查询优化器中注入 WHERE 条件，比应用层过滤更安全。
--     即使 SQL 注入成功，RLS 仍然保护数据隔离。
--
-- (3) "权限即时生效"需要内存中维护 ACL 缓存:
--     PostgreSQL 在 shared memory 中缓存 ACL（syscache）。
--     GRANT/REVOKE 通过 invalidation message 通知其他后端刷新缓存。

-- ============================================================
-- 9. 版本演进
-- ============================================================
-- PostgreSQL 8.1:  ROLE 系统（统一 USER/GROUP）
-- PostgreSQL 9.0:  ALTER DEFAULT PRIVILEGES
-- PostgreSQL 9.5:  行级安全 (RLS)
-- PostgreSQL 14:   预定义角色, INHERIT FALSE 选项
-- PostgreSQL 15:   GRANT 支持 PUBLIC schema 权限限制
