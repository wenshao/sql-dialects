# MariaDB: 动态 SQL

语法与 MySQL 完全一致

参考资料:
[1] MariaDB Knowledge Base - PREPARE Statement
https://mariadb.com/kb/en/prepare-statement/

## 1. PREPARE / EXECUTE / DEALLOCATE

```sql
SET @sql = 'SELECT * FROM users WHERE age > ? AND username LIKE ?';
PREPARE stmt FROM @sql;
SET @min_age = 18;
SET @pattern = 'a%';
EXECUTE stmt USING @min_age, @pattern;
DEALLOCATE PREPARE stmt;
```


## 2. 动态 DDL

```sql
SET @tbl = 'temp_report';
SET @sql = CONCAT('CREATE TABLE IF NOT EXISTS ', @tbl, ' (id INT, val TEXT)');
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;
```


## 3. 在存储过程中使用

```sql
DELIMITER //
CREATE PROCEDURE dynamic_query(IN p_table VARCHAR(64), IN p_where TEXT)
BEGIN
    SET @sql = CONCAT('SELECT * FROM ', p_table, ' WHERE ', p_where);
    PREPARE stmt FROM @sql;
    EXECUTE stmt;
    DEALLOCATE PREPARE stmt;
END //
DELIMITER ;
```


## 4. Oracle 兼容模式的 EXECUTE IMMEDIATE (10.3+)

SET sql_mode=ORACLE;
EXECUTE IMMEDIATE 'SELECT * FROM users WHERE id = :1' USING p_id;
这是 Oracle PL/SQL 的动态 SQL 语法, MariaDB 独有支持

## 5. 对引擎开发者的启示

MySQL/MariaDB 的 PREPARE 是会话级的:
预编译的语句只在当前连接有效, 连接断开自动释放
预编译的执行计划不跨会话共享 (vs Oracle 的共享游标)
SQL 注入防护: PREPARE + ? 参数是最有效的防注入方案
参数绑定在执行层处理, 不经过 SQL 解析 (参数不会被解释为 SQL)
