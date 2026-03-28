# Teradata: Permissions

> 参考资料:
> - [Teradata SQL Reference](https://docs.teradata.com/r/Teradata-VantageTM-SQL-Functions-Expressions-and-Predicates)
> - [Teradata Database Documentation](https://docs.teradata.com/)


Create user
```sql
CREATE USER alice AS
    PASSWORD = 'password123'
    PERM = 1000000         -- permanent space in bytes
    SPOOL = 500000         -- spool space limit
    TEMPORARY = 500000     -- temporary space limit
    DEFAULT DATABASE = mydb;
```


Create role
```sql
CREATE ROLE app_read;
CREATE ROLE app_write;
```


Grant privileges on database
```sql
GRANT SELECT ON mydb TO alice;
GRANT ALL ON mydb TO alice;
```


Grant privileges on table
```sql
GRANT SELECT ON users TO alice;
GRANT SELECT, INSERT, UPDATE ON users TO alice;
GRANT ALL ON users TO alice;
```


Column-level privileges
```sql
GRANT SELECT (username, email) ON users TO alice;
GRANT UPDATE (email) ON users TO alice;
```


Grant privileges to role
```sql
GRANT SELECT ON users TO app_read;
GRANT INSERT, UPDATE, DELETE ON users TO app_write;
```


Assign role to user
```sql
GRANT app_read TO alice;
GRANT app_write TO alice;
```


Grant WITH GRANT OPTION (user can grant to others)
```sql
GRANT SELECT ON users TO alice WITH GRANT OPTION;
```


Procedure/macro privileges
```sql
GRANT EXECUTE PROCEDURE ON my_procedure TO alice;
GRANT EXECUTE MACRO ON my_macro TO alice;
```


Database-level privileges
```sql
GRANT CREATE TABLE ON mydb TO alice;
GRANT DROP TABLE ON mydb TO alice;
GRANT CREATE VIEW ON mydb TO alice;
GRANT CREATE PROCEDURE ON mydb TO alice;
```


System-level privileges
```sql
GRANT SPOOL TO alice;
GRANT MONITOR TO alice;
GRANT ABORT SESSION TO alice;
```


Revoke privileges
```sql
REVOKE SELECT ON users FROM alice;
REVOKE ALL ON users FROM alice;
REVOKE app_read FROM alice;
```


Modify user
```sql
MODIFY USER alice AS
    PASSWORD = 'new_password'
    PERM = 2000000;
```


Drop user
```sql
DROP USER alice;
```


View privileges
```sql
SHOW GRANTS ON users;
SELECT * FROM DBC.AllRightsV WHERE DatabaseName = 'mydb' AND TableName = 'users';
```


View roles assigned to user
```sql
SELECT * FROM DBC.RoleMembers WHERE Grantee = 'alice';
```


Access logging
```sql
BEGIN LOGGING ON EACH SELECT ON TABLE users BY alice;
END LOGGING ON EACH SELECT ON TABLE users BY alice;
```


Note: Teradata uses PERM/SPOOL/TEMPORARY space allocation per user
Note: privileges cascade through database hierarchy
Note: roles simplify privilege management (like other databases)
Note: ACCESS logging tracks who accesses what data
Note: no ROW LEVEL SECURITY built-in (use views or UDFs)
