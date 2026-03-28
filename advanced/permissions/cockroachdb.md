# CockroachDB: 权限管理

> 参考资料:
> - [CockroachDB - SQL Statements](https://www.cockroachlabs.com/docs/stable/sql-statements)
> - [CockroachDB - Functions and Operators](https://www.cockroachlabs.com/docs/stable/functions-and-operators)
> - [CockroachDB - Data Types](https://www.cockroachlabs.com/docs/stable/data-types)

**引擎定位**: 分布式 SQL 数据库，兼容 PostgreSQL 协议。基于 Pebble (RocksDB) 存储，Raft 共识，支持 Geo-Partitioning。

## Create users/roles


```sql
CREATE ROLE alice LOGIN PASSWORD 'password123';
CREATE USER alice WITH PASSWORD 'password123';  -- same as above
CREATE ROLE app_read;                           -- no login (group role)
CREATE ROLE app_write;

```

## Grant privileges


Table privileges
```sql
GRANT SELECT ON users TO alice;
GRANT SELECT, INSERT, UPDATE ON users TO alice;
GRANT ALL PRIVILEGES ON users TO alice;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO alice;

```

Column-level privileges
```sql
GRANT SELECT (username, email) ON users TO alice;
GRANT UPDATE (email) ON users TO alice;

```

Schema privileges
```sql
GRANT USAGE ON SCHEMA myschema TO alice;
GRANT CREATE ON SCHEMA myschema TO alice;

```

Database privileges
```sql
GRANT CONNECT ON DATABASE mydb TO alice;
GRANT CREATE ON DATABASE mydb TO alice;

```

Sequence privileges
```sql
GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO alice;

```

Type privileges
```sql
GRANT USAGE ON TYPE status TO alice;

```

## Role inheritance


```sql
GRANT SELECT ON ALL TABLES IN SCHEMA public TO app_read;
GRANT INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO app_write;
GRANT app_read TO alice;
GRANT app_write TO alice;

```

## Default privileges


```sql
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO app_read;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE ON SEQUENCES TO app_read;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT INSERT, UPDATE, DELETE ON TABLES TO app_write;

```

## Revoke privileges


```sql
REVOKE INSERT ON users FROM alice;
REVOKE ALL PRIVILEGES ON users FROM alice;
REVOKE app_read FROM alice;

```

## System privileges (CockroachDB-specific)


Grant system-level privileges
```sql
GRANT admin TO alice;                          -- superuser
GRANT VIEWACTIVITY TO alice;                   -- view cluster activity
GRANT CANCELQUERY TO alice;                    -- cancel other users' queries
GRANT MODIFYCLUSTERSETTING TO alice;           -- change cluster settings
GRANT EXTERNALCONNECTION TO alice;             -- create external connections
GRANT VIEWDEBUG TO alice;                      -- view debug pages
GRANT VIEWCLUSTERMETADATA TO alice;            -- view cluster metadata

```

## View privileges


```sql
SHOW GRANTS ON users;
SHOW GRANTS FOR alice;
SHOW ROLES;

SELECT * FROM information_schema.role_table_grants WHERE grantee = 'alice';

```

## Manage users


Change password
```sql
ALTER ROLE alice WITH PASSWORD 'new_password';

```

Set password expiration
```sql
ALTER ROLE alice WITH PASSWORD 'password123' VALID UNTIL '2025-12-31';

```

Login options
```sql
ALTER ROLE alice WITH LOGIN;
ALTER ROLE alice WITH NOLOGIN;

```

Connection limit
```sql
ALTER ROLE alice WITH CONNECTION LIMIT 10;

```

## Row-level security (not supported)


CockroachDB does NOT support row-level security (RLS)
Use views or application-level filtering instead

Alternative: view-based row filtering
```sql
CREATE VIEW alice_orders AS
SELECT * FROM orders WHERE user_id = (SELECT id FROM users WHERE username = current_user);
GRANT SELECT ON alice_orders TO alice;

```

## Drop roles


```sql
DROP ROLE alice;
DROP ROLE IF EXISTS alice;

```

Note: PostgreSQL-compatible RBAC
Note: System privileges are CockroachDB-specific
Note: No row-level security (RLS)
Note: admin role is the superuser equivalent
Note: Privileges apply across the distributed cluster
Note: No FLUSH PRIVILEGES needed; changes are immediate
