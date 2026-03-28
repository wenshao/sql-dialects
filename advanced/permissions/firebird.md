# Firebird: Permissions

## Create user (3.0+ uses SQL, earlier versions use gsec utility)

```sql
CREATE USER alice PASSWORD 'password123';
CREATE USER bob PASSWORD 'password456' FIRSTNAME 'Bob' LASTNAME 'Smith';
```

## 3.0+: Create user with specific plugin

```sql
CREATE USER alice PASSWORD 'password123' USING PLUGIN Srp;
```

## Create role

```sql
CREATE ROLE app_read;
CREATE ROLE app_write;
```

## Grant table privileges

```sql
GRANT SELECT ON users TO alice;
GRANT SELECT, INSERT, UPDATE ON users TO alice;
GRANT ALL ON users TO alice;
```

## Grant to role

```sql
GRANT SELECT ON users TO app_read;
GRANT INSERT, UPDATE, DELETE ON users TO app_write;
```

## Assign role to user

```sql
GRANT app_read TO alice;
GRANT app_write TO alice;
```

## Default role (3.0+, automatically activated on login)

```sql
ALTER ROLE app_read SET DEFAULT TO alice;
```

## Grant with admin option

```sql
GRANT app_read TO alice WITH ADMIN OPTION;
```

## Grant with grant option (user can grant to others)

```sql
GRANT SELECT ON users TO alice WITH GRANT OPTION;
```

## Procedure privileges

```sql
GRANT EXECUTE ON PROCEDURE my_procedure TO alice;
```

## Generator (sequence) privileges

```sql
GRANT USAGE ON SEQUENCE seq_orders TO alice;
```

## Grant to PUBLIC (all users)

```sql
GRANT SELECT ON users TO PUBLIC;
```

## Column-level privileges (not directly supported)

Workaround: create a view with specific columns, grant on view

```sql
CREATE VIEW users_public AS SELECT id, username, email FROM users;
GRANT SELECT ON users_public TO alice;
```

## Revoke privileges

```sql
REVOKE SELECT ON users FROM alice;
REVOKE ALL ON users FROM alice;
REVOKE app_read FROM alice;
```

## Modify user

```sql
ALTER USER alice PASSWORD 'new_password';
ALTER USER alice FIRSTNAME 'Alice' LASTNAME 'Jones';
ALTER USER alice ACTIVE;     -- enable user
ALTER USER alice INACTIVE;   -- disable user
```

## 4.0+: Set user as admin

```sql
ALTER USER alice GRANT ADMIN ROLE;
ALTER USER alice REVOKE ADMIN ROLE;
```

## Drop user

```sql
DROP USER alice;
```

## Drop role

```sql
DROP ROLE app_read;
```

## View privileges

System tables

```sql
SELECT * FROM RDB$USER_PRIVILEGES WHERE RDB$USER = 'ALICE';
SELECT * FROM RDB$ROLES;
SELECT * FROM RDB$USER_PRIVILEGES WHERE RDB$RELATION_NAME = 'USERS';
```

## RDB$ADMIN role (3.0+, like DBA)

```sql
GRANT RDB$ADMIN TO alice;
```

Database-level privileges
SYSDBA is the default superuser
RDB$ADMIN role grants DBA-level access within a database
Mapping (3.0+, map OS users to Firebird users)

```sql
CREATE MAPPING os_to_fb USING PLUGIN Win_Sspi
    FROM USER "DOMAIN\alice" TO USER alice;
```

Note: Firebird uses gsec utility for user management in 2.x
Note: 3.0+ added SQL-based user management
Note: no column-level GRANT; use views as workaround
Note: SYSDBA is the built-in superuser account
Note: RDB$ADMIN role provides database admin privileges (3.0+)
Note: roles must be explicitly activated or set as default
