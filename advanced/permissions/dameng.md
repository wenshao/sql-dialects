# DamengDB (达梦): 权限管理

Oracle compatible syntax.

> 参考资料:
> - [DamengDB SQL Reference](https://eco.dameng.com/document/dm/zh-cn/sql-dev/index.html)
> - [DamengDB System Admin Manual](https://eco.dameng.com/document/dm/zh-cn/pm/index.html)


## 创建用户

```sql
CREATE USER alice IDENTIFIED BY password123;
CREATE USER alice IDENTIFIED BY password123
    DEFAULT TABLESPACE users
    TEMPORARY TABLESPACE temp;
```

## 系统权限

```sql
GRANT CREATE SESSION TO alice;
GRANT CREATE TABLE TO alice;
GRANT CREATE VIEW TO alice;
GRANT CREATE PROCEDURE TO alice;
GRANT CREATE SEQUENCE TO alice;
```

## 对象权限

```sql
GRANT SELECT ON users TO alice;
GRANT SELECT, INSERT, UPDATE ON users TO alice;
GRANT ALL ON users TO alice;
```

## 列级权限

```sql
GRANT UPDATE (email, phone) ON users TO alice;
```

## WITH GRANT OPTION

```sql
GRANT SELECT ON users TO alice WITH GRANT OPTION;
```

## 角色

```sql
CREATE ROLE app_read;
CREATE ROLE app_write;
GRANT SELECT ON users TO app_read;
GRANT INSERT, UPDATE, DELETE ON users TO app_write;
GRANT app_read, app_write TO alice;
```

## 预定义角色

```sql
GRANT PUBLIC TO alice;
GRANT DBA TO alice;
GRANT RESOURCE TO alice;
```

## 设置默认角色

```sql
ALTER USER alice DEFAULT ROLE app_read;
```

## 撤销权限

```sql
REVOKE INSERT ON users FROM alice;
REVOKE app_write FROM alice;
```

## 查看权限

```sql
SELECT * FROM USER_SYS_PRIVS;
SELECT * FROM USER_TAB_PRIVS;
SELECT * FROM USER_ROLE_PRIVS;
SELECT * FROM DBA_SYS_PRIVS WHERE GRANTEE = 'ALICE';
```

## 修改密码

```sql
ALTER USER alice IDENTIFIED BY new_password;
```

## 密码策略

```sql
ALTER USER alice LIMIT PASSWORD_LIFE_TIME 90;
ALTER USER alice LIMIT FAILED_LOGIN_ATTEMPTS 5;
```

## 安全审计

达梦支持细粒度审计

```sql
AUDIT SELECT ON users BY alice;
AUDIT INSERT, UPDATE, DELETE ON users;
```

## 删除用户

```sql
DROP USER alice;
DROP USER alice CASCADE;
```

注意事项：
权限语法与 Oracle 高度兼容
支持系统权限和对象权限
支持角色管理
支持审计功能
支持密码策略
达梦还支持强制访问控制（MAC）等安全增强功能
