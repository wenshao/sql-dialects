# Derby: 权限管理

## Derby 支持 SQL 标准的权限管理

## 认证配置


启用用户认证（在 derby.properties 中）
derby.connection.requireAuthentication=true
derby.authentication.provider=BUILTIN
创建用户（通过系统属性）

```sql
CALL SYSCS_UTIL.SYSCS_SET_DATABASE_PROPERTY(
    'derby.user.alice', 'password123');
CALL SYSCS_UTIL.SYSCS_SET_DATABASE_PROPERTY(
    'derby.user.bob', 'password456');
```

## 设置数据库所有者

derby.database.fullAccessUsers=admin

## 授权


## 表权限

```sql
GRANT SELECT ON users TO alice;
GRANT SELECT, INSERT, UPDATE, DELETE ON users TO bob;
GRANT ALL PRIVILEGES ON users TO bob;
```

## 执行权限

```sql
GRANT EXECUTE ON PROCEDURE GET_USER TO alice;
GRANT EXECUTE ON FUNCTION FULL_NAME TO alice;
```

## 列权限

```sql
GRANT SELECT (username, email) ON users TO alice;
GRANT UPDATE (email) ON users TO alice;
```

## 撤销权限

```sql
REVOKE INSERT ON users FROM bob;
REVOKE ALL PRIVILEGES ON users FROM alice;
```

## 角色（10.2+）


```sql
CREATE ROLE app_readonly;
CREATE ROLE app_readwrite;

GRANT SELECT ON users TO app_readonly;
GRANT SELECT, INSERT, UPDATE ON users TO app_readwrite;

GRANT app_readonly TO alice;
GRANT app_readwrite TO bob;

SET ROLE app_readonly;                                 -- 激活角色

REVOKE app_readonly FROM alice;
DROP ROLE app_readonly;
```

## 查看权限


```sql
SELECT * FROM SYS.SYSTABLEPERMS;
SELECT * FROM SYS.SYSCOLPERMS;
SELECT * FROM SYS.SYSROUTINEPERMS;
```

注意：Derby 需要先配置认证才能使用权限
注意：用户通过系统属性创建（不是 CREATE USER）
注意：支持列级权限
注意：支持角色（10.2+）
注意：SET ROLE 激活角色
注意：嵌入式模式下默认不启用认证
