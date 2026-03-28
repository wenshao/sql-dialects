# MariaDB: 迁移速查表 (Migration Cheatsheet)

> 参考资料:
> - [MariaDB Knowledge Base](https://mariadb.com/kb/en/)
> - [MariaDB vs MySQL Compatibility](https://mariadb.com/kb/en/mariadb-vs-mysql-compatibility/)


## 一、从 MySQL 迁移到 MariaDB

数据类型: 基本完全兼容
区别: MariaDB JSON 类型是 LONGTEXT 的别名
新增: MariaDB 10.7+ 支持 UUID 列类型
函数: 基本完全兼容
新增: MariaDB 有 SEQUENCE 引擎, RETURNING 子句(10.5+),
System Versioning(10.3+), Window Functions(10.2+)
陷阱: 部分 MySQL 8.0 新特性 MariaDB 不支持(如 MySQL ROLES 语法差异)
MariaDB 的 GTID 格式与 MySQL 不同（域ID-服务器ID-序号）

二、从 PostgreSQL 迁移到 MariaDB: 类似 MySQL，注意:
SERIAL→AUTO_INCREMENT, BOOLEAN→TINYINT(1), TEXT→LONGTEXT,
||→CONCAT, STRING_AGG→GROUP_CONCAT, RETURNING→RETURNING(10.5+)

三、自增: AUTO_INCREMENT 或 SEQUENCE（MariaDB 10.3+）
```sql
CREATE TABLE t (id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY);
CREATE SEQUENCE my_seq START WITH 1 INCREMENT BY 1;
SELECT NEXT VALUE FOR my_seq;
```


四、日期: NOW(), CURDATE(), DATE_ADD(NOW(), INTERVAL 1 DAY),
DATEDIFF, DATE_FORMAT(NOW(), '%Y-%m-%d %H:%i:%s')
五、字符串: CHAR_LENGTH, UPPER, LOWER, TRIM, SUBSTRING,
REPLACE, LOCATE, CONCAT, GROUP_CONCAT
