# SQL 标准: 动态SQL

> 参考资料:
> - [ISO/IEC 9075-5: SQL/Bindings (SQL Embedded Dynamic)](https://www.iso.org/standard/76584.html)
> - [SQL:2016 Foundation - PREPARE, EXECUTE, EXECUTE IMMEDIATE](https://www.iso.org/standard/63556.html)

## EXECUTE IMMEDIATE (SQL 标准核心)

直接执行动态 SQL 字符串
```sql
EXECUTE IMMEDIATE 'CREATE TABLE test_table (id INT, name VARCHAR(100))';
```

使用变量
```sql
EXECUTE IMMEDIATE 'INSERT INTO test_table VALUES (1, ''hello'')';
```

## PREPARE / EXECUTE / DEALLOCATE (参数化动态 SQL)

准备语句
```sql
PREPARE stmt FROM 'SELECT * FROM users WHERE id = ?';
```

执行（使用参数绑定）
```sql
EXECUTE stmt USING 42;
```

释放
```sql
DEALLOCATE PREPARE stmt;
```

## 参数化动态 SQL（防止 SQL 注入）

SQL 标准推荐使用占位符 (?) 绑定参数
```sql
PREPARE safe_query FROM 'SELECT * FROM users WHERE username = ? AND age > ?';
EXECUTE safe_query USING 'admin', 18;
DEALLOCATE PREPARE safe_query;
```

## 动态 SQL 在存储过程中的使用（SQL/PSM 标准）

SQL/PSM (Persistent Stored Modules) 标准定义了存储过程中的动态 SQL
CREATE PROCEDURE dynamic_search(IN p_table VARCHAR(128), IN p_col VARCHAR(128))
BEGIN
    DECLARE sql_text VARCHAR(1000);
    SET sql_text = 'SELECT * FROM ' || p_table || ' WHERE ' || p_col || ' IS NOT NULL';
    PREPARE stmt FROM sql_text;
    EXECUTE stmt;
    DEALLOCATE PREPARE stmt;
END;

- **注意：SQL 标准定义了 4 种动态 SQL 级别：**
  Level 1: EXECUTE IMMEDIATE
  Level 2: PREPARE + EXECUTE
  Level 3: 使用描述符 (DESCRIBE, ALLOCATE/DEALLOCATE DESCRIPTOR)
  Level 4: 动态游标 (DECLARE CURSOR FOR statement)
- **注意：各数据库对标准的实现程度不同**
- **注意：始终使用参数化查询，避免拼接字符串（防止 SQL 注入）**
