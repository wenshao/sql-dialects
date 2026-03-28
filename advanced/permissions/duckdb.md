# DuckDB: 权限管理

> 参考资料:
> - [DuckDB - SQL Reference](https://duckdb.org/docs/sql/introduction)
> - [DuckDB - Functions](https://duckdb.org/docs/sql/functions/overview)
> - [DuckDB - Data Types](https://duckdb.org/docs/sql/data_types/overview)

**引擎定位**: 嵌入式 OLAP 分析引擎，类似 SQLite 的定位。列式存储 + 向量化执行，PostgreSQL 兼容语法。

```sql
CREATE SECRET my_s3_secret (
    TYPE S3,
    KEY_ID 'AKIAIOSFODNN7EXAMPLE',
    SECRET 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY',
    REGION 'us-east-1'
);

```

Create a secret for HTTP bearer token
```sql
CREATE SECRET my_http_secret (
    TYPE HTTP,
    BEARER_TOKEN 'my-token-12345'
);

```

Temporary secret (session-scoped)
```sql
CREATE TEMPORARY SECRET session_secret (
    TYPE S3,
    KEY_ID 'AKIAIOSFODNN7EXAMPLE',
    SECRET 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY'
);

```

Persistent secret (stored in DuckDB config directory)
```sql
CREATE PERSISTENT SECRET prod_s3 (
    TYPE S3,
    KEY_ID 'AKIAIOSFODNN7EXAMPLE',
    SECRET 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY',
    SCOPE 's3://my-bucket'
);

```

List secrets
```sql
SELECT * FROM duckdb_secrets();

```

Drop secret
```sql
DROP SECRET my_s3_secret;
DROP SECRET IF EXISTS my_s3_secret;

```

## Extension security

Control which extensions can be loaded
SET allow_unsigned_extensions = false;  -- Default: only signed extensions

## Community extensions security

SET allow_community_extensions = true;  -- Allow community extensions

## Disable external access

SET enable_external_access = false;     -- Prevent file system and network access

## Attach with limited access

```sql
ATTACH 'analytics.duckdb' AS analytics (READ_ONLY);
```

The analytics database can only be read, not modified

## Views for data restriction (application-level access control)

Create views that limit what data users can see
```sql
CREATE VIEW public_users AS
SELECT id, username, city FROM users;  -- Hide email, phone, etc.

CREATE VIEW department_orders AS
SELECT * FROM orders WHERE department_id = 42;  -- Row-level filtering

```

## Application-level security patterns

In Python:
# Create a connection per user role
read_conn = duckdb.connect('db.duckdb', read_only=True)
admin_conn = duckdb.connect('db.duckdb', read_only=False)
# Use read_conn for regular users, admin_conn for admins

Note: No CREATE USER, CREATE ROLE, GRANT, or REVOKE statements
Note: No authentication mechanism (no passwords, no login)
Note: No row-level security (RLS) policies
Note: No column-level permissions
Note: Security is handled at the application and OS level
Note: Secrets manager handles credentials for external services (S3, HTTP)
Note: READ_ONLY attach mode is the primary write protection mechanism
Note: For multi-user scenarios, use application middleware for access control
