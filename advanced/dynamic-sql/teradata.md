# Teradata: Dynamic SQL

> 参考资料:
> - [Teradata SQL Reference - Dynamic SQL](https://docs.teradata.com/r/Teradata-Database-SQL-Stored-Procedures-and-Embedded-SQL/)
> - [Teradata SQL Reference - EXECUTE / EXECUTE IMMEDIATE](https://docs.teradata.com/r/Teradata-VantageTM-SQL-Stored-Procedures-and-Embedded-SQL/)


## EXECUTE IMMEDIATE (Teradata SPL)

```sql
CREATE PROCEDURE count_table(IN p_table VARCHAR(128))
BEGIN
    DECLARE v_sql VARCHAR(1000);
    DECLARE v_count INTEGER;

    SET v_sql = 'SELECT COUNT(*) FROM ' || p_table;
    EXECUTE IMMEDIATE v_sql INTO v_count;
END;
```


## PREPARE / EXECUTE (嵌入式 SQL)

Teradata 的嵌入式 SQL (ESQL) 支持 PREPARE/EXECUTE
EXEC SQL PREPARE stmt FROM :sql_text;
EXEC SQL EXECUTE stmt USING :param;
EXEC SQL DEALLOCATE PREPARE stmt;

## 存储过程中的动态 SQL

```sql
REPLACE PROCEDURE dynamic_search(
    IN p_table VARCHAR(128),
    IN p_column VARCHAR(128),
    IN p_value VARCHAR(255)
)
BEGIN
    DECLARE v_sql VARCHAR(4000);
    SET v_sql = 'SELECT * FROM ' || p_table || ' WHERE ' || p_column || ' = ''' || p_value || '''';
    EXECUTE IMMEDIATE v_sql;
END;
```


## 动态游标

```sql
REPLACE PROCEDURE process_dynamic(IN p_table VARCHAR(128))
DYNAMIC RESULT SETS 1
BEGIN
    DECLARE v_sql VARCHAR(4000);
    DECLARE v_cursor CURSOR WITH RETURN FOR v_stmt;

    SET v_sql = 'SELECT * FROM ' || p_table;
    PREPARE v_stmt FROM v_sql;
    OPEN v_cursor;
    -- 结果集自动返回给调用者
END;
```


注意：Teradata 使用 SPL (Stored Procedure Language)
注意：支持 EXECUTE IMMEDIATE 和 PREPARE/EXECUTE
注意：动态游标使用 CURSOR WITH RETURN
限制：动态 SQL 中参数绑定支持有限
限制：EXECUTE IMMEDIATE 不能直接返回结果集
