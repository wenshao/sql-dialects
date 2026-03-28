# Oracle: 动态 SQL

> 参考资料:
> - [Oracle PL/SQL Reference - EXECUTE IMMEDIATE](https://docs.oracle.com/en/database/oracle/oracle-database/23/lnpls/EXECUTE-IMMEDIATE-statement.html)
> - [Oracle PL/SQL Reference - DBMS_SQL Package](https://docs.oracle.com/en/database/oracle/oracle-database/23/arpls/DBMS_SQL.html)

## EXECUTE IMMEDIATE（原生动态 SQL, NDS）

基本 DDL
```sql
BEGIN
    EXECUTE IMMEDIATE 'CREATE TABLE test_tbl (id NUMBER, name VARCHAR2(100))';
END;
/
```

带 INTO（单行查询）
```sql
DECLARE
    v_count NUMBER;
BEGIN
    EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM users' INTO v_count;
    DBMS_OUTPUT.PUT_LINE('Count: ' || v_count);
END;
/
```

## 绑定变量: USING 子句（防止 SQL 注入 + 提高性能）

```sql
DECLARE
    v_name VARCHAR2(100);
    v_age  NUMBER;
BEGIN
    EXECUTE IMMEDIATE
        'SELECT name, age FROM users WHERE id = :id'
        INTO v_name, v_age
        USING 42;
    DBMS_OUTPUT.PUT_LINE(v_name || ', ' || v_age);
END;
/
```

DML 带绑定变量
```sql
DECLARE
    v_rows NUMBER;
BEGIN
    EXECUTE IMMEDIATE
        'UPDATE users SET status = :s WHERE age > :a'
        USING 'active', 18;
    v_rows := SQL%ROWCOUNT;
END;
/
```

设计分析: 绑定变量的重要性
  Oracle 使用 :name 命名绑定变量（按位置绑定，不是按名称!）。
  绑定变量的核心价值:
  1. 防止 SQL 注入（参数与 SQL 文本分离）
  2. 共享游标（相同 SQL 文本复用执行计划，减少硬解析）
  Oracle 的共享池（Shared Pool）依赖绑定变量实现高并发。
  不使用绑定变量 → 每次硬解析 → 共享池争用 → 性能崩溃

横向对比:
  Oracle:     :name（位置绑定）/ USING 子句
  PostgreSQL: $1, $2（位置绑定）/ EXECUTE ... USING
  MySQL:      ?（位置绑定）/ EXECUTE ... USING
  SQL Server: @name（命名绑定）/ sp_executesql

## BULK COLLECT（批量返回结果集）

```sql
DECLARE
    TYPE user_tab IS TABLE OF users%ROWTYPE;
    v_users user_tab;
BEGIN
    EXECUTE IMMEDIATE
        'SELECT * FROM users WHERE status = :s'
        BULK COLLECT INTO v_users
        USING 'active';
    FOR i IN 1..v_users.COUNT LOOP
        DBMS_OUTPUT.PUT_LINE(v_users(i).username);
    END LOOP;
END;
/
```

## 动态游标（REF CURSOR）

```sql
DECLARE
    TYPE ref_cur IS REF CURSOR;
    v_cur   ref_cur;
    v_id    NUMBER;
    v_name  VARCHAR2(100);
BEGIN
    OPEN v_cur FOR
        'SELECT id, name FROM users WHERE age > :min_age'
        USING 25;
    LOOP
        FETCH v_cur INTO v_id, v_name;
        EXIT WHEN v_cur%NOTFOUND;
        DBMS_OUTPUT.PUT_LINE(v_id || ': ' || v_name);
    END LOOP;
    CLOSE v_cur;
END;
/
```

## DBMS_SQL 包（完全动态 SQL，列数/类型运行时确定）

```sql
DECLARE
    v_cursor INTEGER;
    v_rows   INTEGER;
    v_id     NUMBER;
    v_name   VARCHAR2(100);
BEGIN
    v_cursor := DBMS_SQL.OPEN_CURSOR;
    DBMS_SQL.PARSE(v_cursor, 'SELECT id, name FROM users WHERE age > :age',
                   DBMS_SQL.NATIVE);
    DBMS_SQL.BIND_VARIABLE(v_cursor, ':age', 25);
    DBMS_SQL.DEFINE_COLUMN(v_cursor, 1, v_id);
    DBMS_SQL.DEFINE_COLUMN(v_cursor, 2, v_name, 100);
    v_rows := DBMS_SQL.EXECUTE(v_cursor);
    WHILE DBMS_SQL.FETCH_ROWS(v_cursor) > 0 LOOP
        DBMS_SQL.COLUMN_VALUE(v_cursor, 1, v_id);
        DBMS_SQL.COLUMN_VALUE(v_cursor, 2, v_name);
        DBMS_OUTPUT.PUT_LINE(v_id || ': ' || v_name);
    END LOOP;
    DBMS_SQL.CLOSE_CURSOR(v_cursor);
END;
/
```

NDS vs DBMS_SQL:
  NDS (EXECUTE IMMEDIATE): 简洁，列数/类型编译时已知
  DBMS_SQL: 灵活，列数/类型运行时确定（如动态 PIVOT）
  推荐: 优先使用 NDS，只在需要完全动态时使用 DBMS_SQL

## SQL 注入防护: DBMS_ASSERT

```sql
CREATE OR REPLACE PROCEDURE dynamic_search(
    p_table  IN VARCHAR2,
    p_column IN VARCHAR2,
    p_value  IN VARCHAR2,
    p_result OUT SYS_REFCURSOR
) AS
    v_sql VARCHAR2(4000);
BEGIN
    -- DBMS_ASSERT 验证标识符（防止表名/列名注入）
    v_sql := 'SELECT * FROM '
             || DBMS_ASSERT.SQL_OBJECT_NAME(p_table)
             || ' WHERE '
             || DBMS_ASSERT.SIMPLE_SQL_NAME(p_column)
             || ' = :val';
    OPEN p_result FOR v_sql USING p_value;
END;
/
```

DBMS_ASSERT 函数:
  SQL_OBJECT_NAME: 验证是否为合法的已存在对象名
  SIMPLE_SQL_NAME: 验证是否为合法的简单标识符
  SCHEMA_NAME: 验证是否为合法的 schema 名
  ENQUOTE_NAME: 给标识符加双引号
  NOOP: 不做任何验证（用于测试）

## 动态 DDL

```sql
CREATE OR REPLACE PROCEDURE create_partition(p_year IN NUMBER) AS
BEGIN
    EXECUTE IMMEDIATE
        'CREATE TABLE orders_' || p_year ||
        ' AS SELECT * FROM orders WHERE EXTRACT(YEAR FROM order_date) = :yr'
        USING p_year;
END;
/
```

> **注意**: DDL 不支持绑定变量!
表名/列名不能作为绑定变量（必须拼接字符串）
但值可以作为绑定变量

## 对引擎开发者的总结

1. 绑定变量是 Oracle 性能的基石（共享游标 + 防注入），新引擎必须支持。
2. NDS (EXECUTE IMMEDIATE) 和 DBMS_SQL 对应两种动态程度，优先实现 NDS。
3. DBMS_ASSERT 提供标识符验证，是防止 SQL 注入的最后一道防线。
4. DDL 不支持绑定变量是所有数据库的共同限制（标识符不能参数化）。
5. BULK COLLECT + 动态 SQL 结合，实现了灵活且高效的批量数据处理。
