# Firebird: Dynamic SQL

> 参考资料:
> - [Firebird Documentation - EXECUTE STATEMENT](https://firebirdsql.org/file/documentation/html/en/refdocs/fblangref40/firebird-40-language-reference.html#fblangref40-psql-coding-exec-stmt)
> - [Firebird Documentation - PSQL](https://firebirdsql.org/file/documentation/html/en/refdocs/fblangref40/firebird-40-language-reference.html#fblangref40-psql)


## EXECUTE STATEMENT (PSQL 动态 SQL)

## 基本用法

```sql
EXECUTE BLOCK AS
BEGIN
    EXECUTE STATEMENT 'INSERT INTO test_tbl VALUES (1, ''hello'')';
END;
```

## EXECUTE STATEMENT ... INTO (单行结果)

```sql
EXECUTE BLOCK
RETURNS (cnt INTEGER)
AS
BEGIN
    EXECUTE STATEMENT 'SELECT COUNT(*) FROM users' INTO :cnt;
    SUSPEND;
END;
```

## EXECUTE STATEMENT 带参数                            -- 2.5+

```sql
EXECUTE BLOCK (p_age INTEGER = ?)
RETURNS (user_name VARCHAR(100))
AS
BEGIN
    FOR EXECUTE STATEMENT 'SELECT username FROM users WHERE age > ?'
        (p_age)
        INTO :user_name
    DO
        SUSPEND;
END;
```

## 命名参数

```sql
EXECUTE BLOCK
RETURNS (user_name VARCHAR(100), user_age INTEGER)
AS
BEGIN
    FOR EXECUTE STATEMENT
        'SELECT username, age FROM users WHERE status = :s AND age > :a'
        (s := 'active', a := 18)
        INTO :user_name, :user_age
    DO
        SUSPEND;
END;
```

## 存储过程中的动态 SQL

```sql
CREATE OR REPLACE PROCEDURE dynamic_count(p_table VARCHAR(64))
RETURNS (row_count BIGINT)
AS
DECLARE v_sql VARCHAR(1000);
BEGIN
    v_sql = 'SELECT COUNT(*) FROM ' || p_table;
    EXECUTE STATEMENT v_sql INTO :row_count;
    SUSPEND;
END;
```

## 动态游标 (FOR EXECUTE STATEMENT)

```sql
CREATE OR REPLACE PROCEDURE process_table(p_table VARCHAR(64))
RETURNS (col_id INTEGER, col_name VARCHAR(100))
AS
BEGIN
    FOR EXECUTE STATEMENT 'SELECT id, name FROM ' || p_table
        INTO :col_id, :col_name
    DO
        SUSPEND;
END;
```

版本说明：
Firebird 1.5+ : EXECUTE STATEMENT（基本）
Firebird 2.5+ : EXECUTE STATEMENT 带参数
Firebird 3.0+ : EXECUTE STATEMENT ON EXTERNAL
注意：Firebird 使用 EXECUTE STATEMENT 而非 EXECUTE IMMEDIATE
注意：使用参数绑定（位置或命名）防止 SQL 注入
限制：EXECUTE STATEMENT 不支持 DDL 中的参数绑定
