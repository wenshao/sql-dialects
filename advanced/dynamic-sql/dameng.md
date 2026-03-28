# 达梦 (DM): Dynamic SQL

> 参考资料:
> - [达梦数据库 SQL 语言参考手册](https://eco.dameng.com/document/dm/zh-cn/sql-dev/dmpl-sql-dynamic.html)
> - [达梦数据库 PL/SQL 编程](https://eco.dameng.com/document/dm/zh-cn/pm/pl-sql.html)
> - ============================================================
> - EXECUTE IMMEDIATE (达梦 PL/SQL)
> - ============================================================

```sql
DECLARE
    v_count NUMBER;
BEGIN
    EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM users' INTO v_count;
    DBMS_OUTPUT.PUT_LINE('Count: ' || v_count);
END;
/
```

## EXECUTE IMMEDIATE ... USING (参数化)

```sql
DECLARE
    v_name VARCHAR2(100);
BEGIN
    EXECUTE IMMEDIATE
        'SELECT username FROM users WHERE id = :1'
        INTO v_name
        USING 42;
    DBMS_OUTPUT.PUT_LINE('Name: ' || v_name);
END;
/
```

## 存储过程中的动态 SQL

```sql
CREATE OR REPLACE PROCEDURE dynamic_search(
    p_table IN VARCHAR2,
    p_col   IN VARCHAR2,
    p_value IN VARCHAR2
) AS
    v_sql VARCHAR2(4000);
    v_cur SYS_REFCURSOR;
BEGIN
    v_sql := 'SELECT * FROM ' || p_table || ' WHERE ' || p_col || ' = :val';
    OPEN v_cur FOR v_sql USING p_value;
    CLOSE v_cur;
END;
/
```

## PREPARE / EXECUTE

```sql
PREPARE stmt FROM 'SELECT * FROM users WHERE age > ?';
EXECUTE stmt USING 18;
DEALLOCATE PREPARE stmt;
```

注意：达梦兼容 Oracle PL/SQL 语法
注意：支持 EXECUTE IMMEDIATE 和 DBMS_SQL 包
注意：使用绑定变量 (:name) 防止 SQL 注入
限制：部分 Oracle 高级动态 SQL 功能可能有差异
