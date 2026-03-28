# MariaDB: 权限

角色系统比 MySQL 更早引入 (10.0.5+)

参考资料:
[1] MariaDB Knowledge Base - Grant
https://mariadb.com/kb/en/grant/

## 1. 角色 (10.0.5+, MySQL 8.0 才支持)

```sql
CREATE ROLE app_reader;
CREATE ROLE app_writer;
CREATE ROLE app_admin;

GRANT SELECT ON myapp.* TO app_reader;
GRANT INSERT, UPDATE, DELETE ON myapp.* TO app_writer;
GRANT ALL PRIVILEGES ON myapp.* TO app_admin;
```


角色层次
```sql
GRANT app_reader TO app_writer;    -- writer 继承 reader 权限
GRANT app_writer TO app_admin;     -- admin 继承 writer 权限
```


分配角色给用户
```sql
GRANT app_writer TO 'appuser'@'%';
SET DEFAULT ROLE app_writer FOR 'appuser'@'%';
```


## 2. 细粒度权限

```sql
GRANT SELECT (username, email) ON myapp.users TO 'report_user'@'%';   -- 列级权限
GRANT EXECUTE ON PROCEDURE myapp.get_user_orders TO 'appuser'@'%';    -- 过程权限
```


## 3. 查看权限

```sql
SHOW GRANTS FOR 'appuser'@'%';
SELECT * FROM information_schema.APPLICABLE_ROLES;
SELECT * FROM mysql.roles_mapping;
```


## 4. 对引擎开发者的启示

MariaDB 的角色比 MySQL 更早实现 (10.0.5 vs 8.0)
实现差异:
MariaDB: 角色存储在 mysql.roles_mapping 表中
MySQL: 角色存储在 mysql.role_edges 和 mysql.default_roles 中
角色激活模型:
MariaDB: SET ROLE 激活角色, SET DEFAULT ROLE 设置登录默认角色
MySQL: 类似, 但 activate_all_roles_on_login 可以自动激活所有角色
