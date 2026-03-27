-- MySQL: 权限管理
--
-- 参考资料:
--   [1] MySQL 8.0 Reference Manual - GRANT
--       https://dev.mysql.com/doc/refman/8.0/en/grant.html
--   [2] MySQL 8.0 Reference Manual - CREATE USER
--       https://dev.mysql.com/doc/refman/8.0/en/create-user.html
--   [3] MySQL 8.0 Reference Manual - Access Control
--       https://dev.mysql.com/doc/refman/8.0/en/access-control.html

-- 创建用户
CREATE USER 'alice'@'localhost' IDENTIFIED BY 'password123';
CREATE USER 'alice'@'%' IDENTIFIED BY 'password123';              -- 允许任意主机
CREATE USER 'alice'@'192.168.1.%' IDENTIFIED BY 'password123';    -- IP 段

-- 8.0+: 角色
CREATE ROLE 'app_read', 'app_write';

-- 授权
GRANT SELECT ON mydb.* TO 'alice'@'localhost';
GRANT SELECT, INSERT, UPDATE ON mydb.users TO 'alice'@'localhost';
GRANT ALL PRIVILEGES ON mydb.* TO 'alice'@'localhost';
GRANT ALL PRIVILEGES ON *.* TO 'admin'@'localhost' WITH GRANT OPTION;

-- 列级权限
GRANT SELECT (username, email) ON mydb.users TO 'alice'@'localhost';

-- 角色权限
GRANT SELECT ON mydb.* TO 'app_read';
GRANT INSERT, UPDATE, DELETE ON mydb.* TO 'app_write';
GRANT 'app_read', 'app_write' TO 'alice'@'localhost';
SET DEFAULT ROLE ALL TO 'alice'@'localhost';

-- 撤销权限
REVOKE INSERT ON mydb.users FROM 'alice'@'localhost';
REVOKE ALL PRIVILEGES ON mydb.* FROM 'alice'@'localhost';

-- 查看权限
SHOW GRANTS FOR 'alice'@'localhost';
SHOW GRANTS FOR CURRENT_USER;

-- 修改密码
ALTER USER 'alice'@'localhost' IDENTIFIED BY 'new_password';
-- 8.0+: 密码过期策略
ALTER USER 'alice'@'localhost' PASSWORD EXPIRE INTERVAL 90 DAY;

-- 删除用户
DROP USER 'alice'@'localhost';
DROP USER IF EXISTS 'alice'@'localhost';

-- 刷新权限
FLUSH PRIVILEGES;

-- 8.0.16+: 部分撤销（Partial Revokes，需要 SET GLOBAL partial_revokes = ON）
-- 先授予全局权限，再撤销特定数据库
GRANT SELECT ON *.* TO 'alice'@'localhost';
REVOKE SELECT ON mysql.* FROM 'alice'@'localhost';
