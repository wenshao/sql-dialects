# MySQL: 动态 SQL

> 参考资料:
> - [MySQL 8.0 Reference Manual - PREPARE Statement](https://dev.mysql.com/doc/refman/8.0/en/prepare.html)
> - [MySQL 8.0 Reference Manual - EXECUTE Statement](https://dev.mysql.com/doc/refman/8.0/en/execute.html)
> - [MySQL 8.0 Reference Manual - DEALLOCATE PREPARE](https://dev.mysql.com/doc/refman/8.0/en/deallocate-prepare.html)

## PREPARE / EXECUTE / DEALLOCATE PREPARE

基本用法
```sql
PREPARE stmt FROM 'SELECT * FROM users WHERE id = ?';
SET @user_id = 42;
EXECUTE stmt USING @user_id;
DEALLOCATE PREPARE stmt;
```

多参数
```sql
PREPARE stmt FROM 'SELECT * FROM users WHERE age > ? AND status = ?';
SET @min_age = 18;
SET @status = 'active';
EXECUTE stmt USING @min_age, @status;
DEALLOCATE PREPARE stmt;
```

## 动态 SQL 在存储过程中

```sql
DELIMITER //
CREATE PROCEDURE dynamic_search(
    IN p_table VARCHAR(64),
    IN p_column VARCHAR(64),
    IN p_value VARCHAR(255)
)
BEGIN
    SET @sql = CONCAT('SELECT * FROM ', p_table,
                      ' WHERE ', p_column, ' = ?');
    SET @val = p_value;
    PREPARE stmt FROM @sql;
    EXECUTE stmt USING @val;
    DEALLOCATE PREPARE stmt;
END //
DELIMITER ;
```

## 动态 DDL

```sql
DELIMITER //
CREATE PROCEDURE create_archive_table(IN p_year INT)
BEGIN
    SET @sql = CONCAT('CREATE TABLE IF NOT EXISTS orders_',
                      p_year,
                      ' LIKE orders');
    PREPARE stmt FROM @sql;
    EXECUTE stmt;
    DEALLOCATE PREPARE stmt;
END //
DELIMITER ;
```

## 参数化动态 SQL（防止 SQL 注入）

```sql
DELIMITER //
CREATE PROCEDURE safe_user_search(IN p_username VARCHAR(64))
BEGIN
    -- 正确：使用参数占位符
    SET @sql = 'SELECT * FROM users WHERE username = ?';
    SET @uname = p_username;
    PREPARE stmt FROM @sql;
    EXECUTE stmt USING @uname;
    DEALLOCATE PREPARE stmt;
```

错误（危险）：直接拼接用户输入
```sql
SET @sql = CONCAT('SELECT * FROM users WHERE username = ''',
```

                  p_username, '''');
```sql
END //
DELIMITER ;
```

## 动态游标（MySQL 不直接支持，使用临时表模拟）

```sql
DELIMITER //
CREATE PROCEDURE process_dynamic_result(IN p_table VARCHAR(64))
BEGIN
    SET @sql = CONCAT('CREATE TEMPORARY TABLE tmp_result AS SELECT * FROM ', p_table);
    PREPARE stmt FROM @sql;
    EXECUTE stmt;
    DEALLOCATE PREPARE stmt;
```

在临时表上使用游标
```sql
    BEGIN
        DECLARE done INT DEFAULT FALSE;
        DECLARE v_id BIGINT;
        DECLARE cur CURSOR FOR SELECT id FROM tmp_result;
        DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = TRUE;
        OPEN cur;
        read_loop: LOOP
            FETCH cur INTO v_id;
            IF done THEN LEAVE read_loop; END IF;
            -- 处理每行
        END LOOP;
        CLOSE cur;
    END;
    DROP TEMPORARY TABLE IF EXISTS tmp_result;
END //
DELIMITER ;
```

## 动态 LIMIT / OFFSET (常用场景)                      -- 5.0+

```sql
DELIMITER //
CREATE PROCEDURE paginate(IN p_table VARCHAR(64), IN p_offset INT, IN p_limit INT)
BEGIN
    SET @sql = CONCAT('SELECT * FROM ', p_table, ' LIMIT ?, ?');
    SET @off = p_offset;
    SET @lim = p_limit;
    PREPARE stmt FROM @sql;
    EXECUTE stmt USING @off, @lim;
    DEALLOCATE PREPARE stmt;
END //
DELIMITER ;
```

版本说明：
  MySQL 5.0+  : PREPARE / EXECUTE / DEALLOCATE PREPARE
  MySQL 8.0+  : 存储过程中完整支持
注意：PREPARE 只能使用用户变量 (@var)，不能使用局部变量
注意：每个会话最多同时有 max_prepared_stmt_count 个预编译语句
注意：PREPARE 只支持特定语句类型（SELECT, INSERT, UPDATE, DELETE, CREATE TABLE 等）
限制：不支持 EXECUTE IMMEDIATE
限制：动态 SQL 中不能使用 INTO 局部变量（需要用用户变量）
