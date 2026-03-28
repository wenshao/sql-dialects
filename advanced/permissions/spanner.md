# Spanner: 权限管理

> 参考资料:
> - [Spanner SQL Reference (GoogleSQL)](https://cloud.google.com/spanner/docs/reference/standard-sql/query-syntax)
> - [Spanner - Functions](https://cloud.google.com/spanner/docs/reference/standard-sql/functions-and-operators)
> - [Spanner - Data Types](https://cloud.google.com/spanner/docs/reference/standard-sql/data-types)

**引擎定位**: Google 全球分布式数据库，TrueTime 外部一致性。基于 Colossus 存储，支持跨洲强一致事务。

## IAM roles (managed via Google Cloud Console, gcloud CLI, or API)


Predefined IAM roles:
roles/spanner.admin          -- Full admin access
roles/spanner.databaseAdmin  -- Database admin (DDL, but not instance)
roles/spanner.databaseReader -- Read-only access to databases
roles/spanner.databaseUser   -- Read/write access to databases
roles/spanner.viewer         -- View metadata only

Grant IAM role via gcloud CLI:
gcloud spanner databases add-iam-policy-binding mydb \
    --instance=myinstance \
    --member='user:alice@example.com' \
    --role='roles/spanner.databaseReader'

## Fine-grained access control (FGAC, 2022+)


Create database role
```sql
CREATE ROLE reader;
CREATE ROLE writer;
CREATE ROLE admin;

```

Grant table-level privileges
```sql
GRANT SELECT ON TABLE Users TO ROLE reader;
GRANT SELECT, INSERT, UPDATE ON TABLE Users TO ROLE writer;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE Users TO ROLE admin;

```

Grant on all tables
```sql
GRANT SELECT ON TABLE Users, Orders, Products TO ROLE reader;

```

Column-level privileges
```sql
GRANT SELECT (Username, Email) ON TABLE Users TO ROLE reader;
GRANT UPDATE (Email) ON TABLE Users TO ROLE writer;

```

## Row-level security via views (workaround)


Create view for filtered access
```sql
CREATE VIEW UserView SQL SECURITY INVOKER AS
SELECT * FROM Users WHERE Region = 'us-east1';

GRANT SELECT ON VIEW UserView TO ROLE us_reader;

```

## Change stream access


```sql
GRANT SELECT ON CHANGE STREAM UserChanges TO ROLE stream_reader;

```

## Role hierarchy


Grant role to another role
```sql
GRANT reader TO ROLE writer;                   -- writer inherits reader
GRANT writer TO ROLE admin;                    -- admin inherits writer

```

Map IAM principal to database role:
gcloud spanner databases add-iam-policy-binding mydb \
    --instance=myinstance \
    --member='user:alice@example.com' \
    --role='roles/spanner.fineGrainedAccessUser' \
    --condition='expression=resource.name.endsWith("/databaseRoles/reader")'

## Revoke privileges


```sql
REVOKE SELECT ON TABLE Users FROM ROLE reader;
REVOKE INSERT, UPDATE ON TABLE Users FROM ROLE writer;
REVOKE reader FROM ROLE writer;

```

## Drop roles


```sql
DROP ROLE reader;
DROP ROLE IF EXISTS reader;

```

## View privileges


```sql
SELECT * FROM INFORMATION_SCHEMA.TABLE_PRIVILEGES;
SELECT * FROM INFORMATION_SCHEMA.COLUMN_PRIVILEGES;

```

View roles
```sql
SELECT * FROM INFORMATION_SCHEMA.ROLES;
SELECT * FROM INFORMATION_SCHEMA.ROLE_TABLE_GRANTS;

```

Note: Primary access control is via Google Cloud IAM
Note: Fine-grained access control (FGAC) for table/column-level SQL grants
Note: No CREATE USER or ALTER USER in SQL (managed via IAM)
Note: No row-level security (RLS) policy syntax
Note: SQL SECURITY INVOKER views for filtered access
Note: Roles are database-scoped, not instance-scoped
Note: FGAC roles are mapped to IAM principals via conditions
