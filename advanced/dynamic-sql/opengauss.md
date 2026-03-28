# openGauss: Dynamic SQL

> 参考资料:
> - [openGauss Documentation - PL/pgSQL](https://docs.opengauss.org/en/docs/latest/docs/DeveloperGuide/pl-pgsql.html)
> - [openGauss Documentation - EXECUTE IMMEDIATE](https://docs.opengauss.org/en/docs/latest/docs/DeveloperGuide/dynamic-statements.html)
> - ============================================================
> - PREPARE / EXECUTE / DEALLOCATE (PostgreSQL 兼容)
> - ============================================================

```sql
PREPARE user_query(INT) AS SELECT * FROM users WHERE age > $1;
EXECUTE user_query(25);
DEALLOCATE user_query;
```

## EXECUTE IMMEDIATE (openGauss 扩展)

```sql
DECLARE
    v_count INTEGER;
BEGIN
    EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM users' INTO v_count;
    RAISE NOTICE 'Count: %', v_count;
END;
/
```

## PL/pgSQL EXECUTE (PostgreSQL 兼容)

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

## EXECUTE ... USING

```sql
CREATE OR REPLACE FUNCTION find_users(p_status TEXT, p_age INT)
RETURNS SETOF users AS $$
BEGIN
    RETURN QUERY EXECUTE
        'SELECT * FROM users WHERE status = $1 AND age >= $2'
        USING p_status, p_age;
END;
$$ LANGUAGE plpgsql;
```

注意：openGauss 基于 PostgreSQL，兼容大部分动态 SQL 语法
注意：额外支持 EXECUTE IMMEDIATE（Oracle 风格）
注意：使用 quote_ident() / format() 防止 SQL 注入
限制：部分 PostgreSQL 新特性可能不完全兼容
