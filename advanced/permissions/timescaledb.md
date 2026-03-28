# TimescaleDB: 权限管理

TimescaleDB 继承 PostgreSQL 全部权限管理功能
创建用户

```sql
CREATE USER alice WITH PASSWORD 'password123';
CREATE ROLE app_readonly;
CREATE ROLE app_readwrite;
```

## 授权

```sql
GRANT SELECT ON sensor_data TO alice;
GRANT SELECT, INSERT ON sensor_data TO app_readwrite;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO app_readwrite;
```

## 角色继承

```sql
GRANT app_readonly TO alice;
GRANT app_readwrite TO alice;
```

## Schema 权限

```sql
GRANT USAGE ON SCHEMA public TO app_readonly;
GRANT CREATE ON SCHEMA public TO app_readwrite;
```

## 列级权限

```sql
GRANT SELECT (time, sensor_id, temperature) ON sensor_data TO app_readonly;
```

## 撤销权限

```sql
REVOKE INSERT ON sensor_data FROM alice;
REVOKE ALL ON sensor_data FROM alice;
```

## 默认权限（新建表自动授权）

```sql
ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT SELECT ON TABLES TO app_readonly;
```

## 修改密码

```sql
ALTER USER alice WITH PASSWORD 'new_password';
```

## 删除用户

```sql
DROP USER alice;
DROP ROLE app_readonly;
```

## 查看权限

```sql
SELECT * FROM information_schema.table_privileges WHERE grantee = 'alice';
\du                                               -- psql 中查看用户
```

## TimescaleDB 特有权限


## 超级表操作需要相应权限

```sql
GRANT SELECT ON sensor_data TO alice;              -- 包含所有 chunk
GRANT INSERT ON sensor_data TO alice;              -- 插入自动路由到 chunk
```

## 连续聚合权限

```sql
GRANT SELECT ON hourly_temps TO app_readonly;
```

管理操作权限（需要 superuser 或 USAGE ON EXTENSION）
add_compression_policy, add_retention_policy 等
行级安全（RLS）

```sql
ALTER TABLE sensor_data ENABLE ROW LEVEL SECURITY;
CREATE POLICY sensor_access ON sensor_data
    FOR SELECT TO app_readonly
    USING (sensor_id IN (SELECT id FROM user_sensors WHERE username = current_user));
```

注意：完全兼容 PostgreSQL 权限管理
注意：超级表的权限自动应用到所有 chunk
注意：支持行级安全（RLS）
注意：管理操作需要适当权限级别
