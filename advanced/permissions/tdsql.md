# TDSQL: 权限管理

TDSQL distributed MySQL-compatible syntax.

> 参考资料:
> - [TDSQL-C MySQL Documentation](https://cloud.tencent.com/document/product/1003)
> - [TDSQL MySQL Documentation](https://cloud.tencent.com/document/product/557)
> - 创建用户

```sql
CREATE USER 'alice'@'localhost' IDENTIFIED BY 'password123';
CREATE USER 'alice'@'%' IDENTIFIED BY 'password123';
CREATE USER 'alice'@'192.168.1.%' IDENTIFIED BY 'password123';
```

## 角色

```sql
CREATE ROLE 'app_read', 'app_write';
```

## 授权

```sql
GRANT SELECT ON mydb.* TO 'alice'@'localhost';
GRANT SELECT, INSERT, UPDATE ON mydb.users TO 'alice'@'localhost';
GRANT ALL PRIVILEGES ON mydb.* TO 'alice'@'localhost';
GRANT ALL PRIVILEGES ON *.* TO 'admin'@'localhost' WITH GRANT OPTION;
```

## 列级权限

```sql
GRANT SELECT (username, email) ON mydb.users TO 'alice'@'localhost';
```

## 角色权限

```sql
GRANT SELECT ON mydb.* TO 'app_read';
GRANT INSERT, UPDATE, DELETE ON mydb.* TO 'app_write';
GRANT 'app_read', 'app_write' TO 'alice'@'localhost';
SET DEFAULT ROLE ALL TO 'alice'@'localhost';
```

## 撤销权限

```sql
REVOKE INSERT ON mydb.users FROM 'alice'@'localhost';
REVOKE ALL PRIVILEGES ON mydb.* FROM 'alice'@'localhost';
```

## 查看权限

```sql
SHOW GRANTS FOR 'alice'@'localhost';
SHOW GRANTS FOR CURRENT_USER;
```

## 修改密码

```sql
ALTER USER 'alice'@'localhost' IDENTIFIED BY 'new_password';
ALTER USER 'alice'@'localhost' PASSWORD EXPIRE INTERVAL 90 DAY;
```

## 删除用户

```sql
DROP USER 'alice'@'localhost';
DROP USER IF EXISTS 'alice'@'localhost';
```

## 刷新权限

```sql
FLUSH PRIVILEGES;
```

注意事项：
权限管理与 MySQL 完全兼容
权限在所有分片上统一管理
支持角色
用户和权限信息存储在代理层
