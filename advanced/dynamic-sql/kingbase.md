# KingbaseES (人大金仓): Dynamic SQL

> 参考资料:
> - [KingbaseES PL/SQL 参考手册](https://help.kingbase.com.cn/)
> - ============================================================
> - EXECUTE IMMEDIATE (兼容 Oracle PL/SQL)
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
END;
/
```

## PL/pgSQL EXECUTE (兼容 PostgreSQL)

```sql
CREATE OR REPLACE FUNCTION count_rows(p_table TEXT)
RETURNS BIGINT AS $$
DECLARE
    result BIGINT;
BEGIN
    EXECUTE 'SELECT COUNT(*) FROM ' || quote_ident(p_table) INTO result;
    RETURN result;
END;
$$ LANGUAGE plpgsql;
```

## PREPARE / EXECUTE / DEALLOCATE

```sql
PREPARE stmt(INT) AS SELECT * FROM users WHERE age > $1;
EXECUTE stmt(25);
DEALLOCATE stmt;
```

注意：KingbaseES 同时兼容 Oracle PL/SQL 和 PostgreSQL PL/pgSQL
注意：支持 EXECUTE IMMEDIATE（Oracle 模式）和 EXECUTE（PostgreSQL 模式）
注意：使用绑定变量防止 SQL 注入
限制：兼容性取决于具体版本和兼容模式设置
