# KingbaseES (人大金仓): 权限管理

PostgreSQL compatible with security extensions.

> 参考资料:
> - [KingbaseES SQL Reference](https://help.kingbase.com.cn/v8/index.html)
> - [KingbaseES Documentation](https://help.kingbase.com.cn/v8/index.html)
> - 创建用户/角色

```sql
CREATE ROLE alice LOGIN PASSWORD 'password123';
CREATE USER alice WITH PASSWORD 'password123';
CREATE ROLE app_read;
```

## 授权

```sql
GRANT SELECT ON users TO alice;
GRANT SELECT, INSERT, UPDATE ON users TO alice;
GRANT ALL PRIVILEGES ON users TO alice;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO alice;
```

## 列级权限

```sql
GRANT SELECT (username, email) ON users TO alice;
GRANT UPDATE (email) ON users TO alice;
```

## Schema 权限

```sql
GRANT USAGE ON SCHEMA myschema TO alice;
GRANT CREATE ON SCHEMA myschema TO alice;
```

## 数据库权限

```sql
GRANT CONNECT ON DATABASE mydb TO alice;
GRANT CREATE ON DATABASE mydb TO alice;
```

## 序列权限

```sql
GRANT USAGE ON SEQUENCE users_id_seq TO alice;
```

## 函数权限

```sql
GRANT EXECUTE ON FUNCTION my_function(INT) TO alice;
```

## 角色继承

```sql
CREATE ROLE app_read;
CREATE ROLE app_write;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO app_read;
GRANT INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO app_write;
GRANT app_read TO alice;
GRANT app_write TO alice;
```

## 默认权限

```sql
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO app_read;
```

## 撤销权限

```sql
REVOKE INSERT ON users FROM alice;
REVOKE ALL PRIVILEGES ON users FROM alice;
REVOKE app_read FROM alice;
```

## 查看权限

```sql
SELECT * FROM information_schema.role_table_grants WHERE grantee = 'alice';
```

## 修改密码

```sql
ALTER ROLE alice WITH PASSWORD 'new_password';
ALTER ROLE alice VALID UNTIL '2025-01-01';
```

## 行级安全（RLS）

```sql
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
CREATE POLICY user_policy ON users
    USING (username = current_user);
CREATE POLICY user_insert_policy ON users
    FOR INSERT
    WITH CHECK (username = current_user);
```

三权分立（KingbaseES 安全特性）
系统管理员（SYSADMIN）：数据库系统管理
安全管理员（SSO）：安全策略和用户管理
审计管理员（SAO）：审计管理
KingbaseES 支持三权分立，权限严格隔离
强制访问控制（MAC，KingbaseES 安全增强）
基于安全标签的访问控制
GRANT LABEL "SECRET" ON TABLE users TO alice;
删除用户

```sql
DROP ROLE alice;
DROP ROLE IF EXISTS alice;
```

注意事项：
权限语法与 PostgreSQL 兼容
KingbaseES 支持三权分立安全模型
支持行级安全（RLS）
支持强制访问控制（MAC）
支持安全审计
权限立即生效
Oracle 兼容模式下也支持 GRANT CREATE SESSION 等 Oracle 风格权限
