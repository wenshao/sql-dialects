# Materialize: 权限管理

## Materialize 支持基于角色的访问控制（RBAC）

## 角色管理


## 创建角色

```sql
CREATE ROLE alice LOGIN PASSWORD 'password123';
CREATE ROLE app_readonly;
CREATE ROLE app_readwrite;
```

## 删除角色

```sql
DROP ROLE alice;
```

## 授权


## 对象级权限

```sql
GRANT SELECT ON users TO alice;
GRANT SELECT, INSERT, UPDATE, DELETE ON users TO app_readwrite;
GRANT ALL PRIVILEGES ON TABLE users TO app_readwrite;
```

## Schema 权限

```sql
GRANT USAGE ON SCHEMA public TO app_readonly;
GRANT CREATE ON SCHEMA public TO app_readwrite;
```

## 数据库权限

```sql
GRANT USAGE ON DATABASE materialize TO alice;
```

## 连接权限

```sql
GRANT USAGE ON CONNECTION kafka_conn TO app_readwrite;
```

## Cluster 权限

```sql
GRANT USAGE ON CLUSTER default TO alice;
```

## SECRET 权限

```sql
GRANT USAGE ON SECRET pg_password TO app_readwrite;
```

## 角色继承

```sql
GRANT app_readonly TO alice;
```

## 撤销权限


```sql
REVOKE INSERT ON users FROM alice;
REVOKE ALL ON users FROM alice;
```

## 默认权限


```sql
ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT SELECT ON TABLES TO app_readonly;
```

## 查看权限


```sql
SHOW ROLES;
```

注意：Materialize 支持 RBAC
注意：权限模型兼容 PostgreSQL
注意：支持对 SOURCE、CONNECTION、CLUSTER 等特有对象的权限
注意：不支持行级安全（RLS）
