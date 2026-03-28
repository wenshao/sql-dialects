# DB2: Dynamic SQL

> 参考资料:
> - [IBM DB2 Documentation - EXECUTE IMMEDIATE](https://www.ibm.com/docs/en/db2/11.5?topic=statements-execute-immediate)
> - [IBM DB2 Documentation - PREPARE](https://www.ibm.com/docs/en/db2/11.5?topic=statements-prepare)
> - [IBM DB2 Documentation - Dynamic SQL](https://www.ibm.com/docs/en/db2/11.5?topic=programming-dynamic-sql)


## EXECUTE IMMEDIATE

```sql
BEGIN
    EXECUTE IMMEDIATE 'CREATE TABLE test_tbl (id INT, name VARCHAR(100))';
END@
```

## PREPARE / EXECUTE (参数化动态 SQL)

```sql
BEGIN
    DECLARE v_sql VARCHAR(1000);
    DECLARE v_stmt STATEMENT;
    DECLARE v_count INT;

    SET v_sql = 'SELECT COUNT(*) FROM users WHERE age > ?';
    PREPARE v_stmt FROM v_sql;
    EXECUTE v_stmt INTO v_count USING 18;
END@
```

## 动态游标

```sql
BEGIN
    DECLARE v_sql VARCHAR(1000);
    DECLARE v_stmt STATEMENT;
    DECLARE v_cur CURSOR FOR v_stmt;
    DECLARE v_id INT;
    DECLARE v_name VARCHAR(100);
    DECLARE SQLSTATE CHAR(5) DEFAULT '00000';

    SET v_sql = 'SELECT id, name FROM users WHERE age > ?';
    PREPARE v_stmt FROM v_sql;
    OPEN v_cur USING 18;
    FETCH v_cur INTO v_id, v_name;
    WHILE SQLSTATE = '00000' DO
        FETCH v_cur INTO v_id, v_name;
    END WHILE;
    CLOSE v_cur;
END@
```

## 存储过程中的动态 SQL

```sql
CREATE OR REPLACE PROCEDURE dynamic_search(
    IN p_table VARCHAR(128),
    IN p_value VARCHAR(255)
)
LANGUAGE SQL
BEGIN
    DECLARE v_sql VARCHAR(4000);
    DECLARE v_stmt STATEMENT;
    DECLARE v_cur CURSOR WITH RETURN FOR v_stmt;

    SET v_sql = 'SELECT * FROM ' || p_table || ' WHERE name = ?';
    PREPARE v_stmt FROM v_sql;
    OPEN v_cur USING p_value;
END@
```

## 参数化（防止 SQL 注入）

```sql
BEGIN
    DECLARE v_sql VARCHAR(1000);
    DECLARE v_stmt STATEMENT;
    SET v_sql = 'SELECT * FROM users WHERE username = ? AND age > ?';
    PREPARE v_stmt FROM v_sql;
    EXECUTE v_stmt USING 'admin', 18;
END@
```

版本说明：
DB2 全版本 : PREPARE / EXECUTE / EXECUTE IMMEDIATE
注意：DB2 支持完整的 SQL 标准动态 SQL
注意：使用参数标记 (?) 防止 SQL 注入
注意：DECLARE CURSOR FOR statement 支持动态游标
限制：EXECUTE IMMEDIATE 不能返回结果集
