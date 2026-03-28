# DB2: 数据库、模式与用户管理

> 参考资料:
> - [IBM Db2 Documentation - CREATE DATABASE](https://www.ibm.com/docs/en/db2/11.5?topic=statements-create-database)
> - [IBM Db2 Documentation - GRANT / REVOKE](https://www.ibm.com/docs/en/db2/11.5?topic=statements-grant)


DB2 命名层级: instance > database > schema > object
默认 schema = 用户名（大写）
DB2 使用操作系统用户进行认证


## 数据库管理（命令行方式）


DB2 的 CREATE DATABASE 是命令行工具，不是 SQL 语句
$ db2 CREATE DATABASE myapp
$ db2 CREATE DATABASE myapp AUTOMATIC STORAGE YES
ON '/data/db2' DBPATH ON '/data/db2'
USING CODESET UTF-8 TERRITORY US COLLATE USING SYSTEM
PAGESIZE 32768
删除数据库
$ db2 DROP DATABASE myapp
连接数据库（SQL 方式）

```sql
CONNECT TO myapp USER myuser USING 'secret123';
CONNECT RESET;                                  -- 断开连接
```

## 模式管理


```sql
CREATE SCHEMA myschema AUTHORIZATION myuser;
CREATE SCHEMA myschema;
```

## 设置默认模式

```sql
SET CURRENT SCHEMA = myschema;
SET SCHEMA myschema;                            -- 简写
```

## 删除模式

```sql
DROP SCHEMA myschema RESTRICT;                  -- 必须为空
```

## 查看当前模式

```sql
VALUES CURRENT SCHEMA;
```

## 用户管理


DB2 使用操作系统用户进行认证
不通过 SQL 创建用户
由操作系统管理员创建 OS 用户
DB2 on Cloud（云版本）可以通过 IAM 管理用户

## 权限管理


DB2 权限级别：
SYSADM > SYSCTRL > SYSMAINT > SYSMON（实例级）
DBADM > SECADM > DATAACCESS > ACCESSCTRL > SQLADM（数据库级）
数据库权限

```sql
GRANT CONNECT ON DATABASE TO USER myuser;
GRANT DBADM ON DATABASE TO USER admin;
GRANT CREATETAB ON DATABASE TO USER myuser;
```

## 模式权限

```sql
GRANT CREATEIN ON SCHEMA myschema TO USER myuser;
GRANT ALTERIN ON SCHEMA myschema TO USER myuser;
GRANT DROPIN ON SCHEMA myschema TO USER myuser;
```

## 表权限

```sql
GRANT SELECT ON TABLE myschema.users TO USER myuser;
GRANT INSERT, UPDATE, DELETE ON TABLE myschema.users TO USER myuser;
GRANT ALL ON TABLE myschema.users TO USER myuser;
GRANT SELECT ON TABLE myschema.users TO PUBLIC;
```

## 列权限

```sql
GRANT UPDATE (email, bio) ON TABLE myschema.users TO USER myuser;
```

## 角色

```sql
CREATE ROLE analyst;
GRANT SELECT ON TABLE myschema.users TO ROLE analyst;
GRANT ROLE analyst TO USER myuser;
DROP ROLE analyst;
```

## 收回权限

```sql
REVOKE SELECT ON TABLE myschema.users FROM USER myuser;
```

## 行和列级安全


## 行权限（RCAC - Row and Column Access Control）

```sql
CREATE PERMISSION region_access ON myschema.sales
    FOR ROWS WHERE (
        VERIFY_ROLE_FOR_USER(SESSION_USER, 'ADMIN') = 1
        OR region = SESSION_USER
    )
    ENFORCED FOR ALL ACCESS
    ENABLE;
```

## 列掩码

```sql
CREATE MASK salary_mask ON myschema.employees
    FOR COLUMN salary RETURN
        CASE WHEN VERIFY_ROLE_FOR_USER(SESSION_USER, 'HR') = 1
             THEN salary
             ELSE 0
        END
    ENABLE;
```

## 激活 RCAC

```sql
ALTER TABLE myschema.sales ACTIVATE ROW ACCESS CONTROL;
ALTER TABLE myschema.employees ACTIVATE COLUMN ACCESS CONTROL;
```

## 查询元数据


```sql
VALUES CURRENT SCHEMA;
VALUES CURRENT USER;
VALUES CURRENT SERVER;
```

## 查看模式

```sql
SELECT SCHEMANAME FROM SYSCAT.SCHEMATA;
```

## 查看权限

```sql
SELECT * FROM SYSCAT.DBAUTH WHERE GRANTEE = 'MYUSER';
SELECT * FROM SYSCAT.TABAUTH WHERE GRANTEE = 'MYUSER';
SELECT * FROM SYSCAT.SCHEMAAUTH WHERE GRANTEE = 'MYUSER';
```

## 查看角色

```sql
SELECT * FROM SYSCAT.ROLES;
SELECT * FROM SYSCAT.ROLEAUTH WHERE GRANTEE = 'MYUSER';
```
