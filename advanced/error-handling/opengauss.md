# openGauss: Error Handling

> 参考资料:
> - [openGauss Documentation - PL/pgSQL](https://docs.opengauss.org/en/docs/latest/docs/DeveloperGuide/pl-pgsql.html)


## EXCEPTION WHEN (PostgreSQL 兼容)

```sql
CREATE OR REPLACE FUNCTION safe_insert(p_name VARCHAR, p_email VARCHAR)
RETURNS TEXT AS $$
BEGIN
    INSERT INTO users(username, email) VALUES(p_name, p_email);
    RETURN 'Success';
EXCEPTION
    WHEN unique_violation THEN
        RETURN 'Duplicate entry';
    WHEN not_null_violation THEN
        RETURN 'NULL value not allowed';
    WHEN OTHERS THEN
        RETURN 'Error: ' || SQLERRM;
END;
$$ LANGUAGE plpgsql;
```

## RAISE

```sql
CREATE OR REPLACE FUNCTION validate(p_val INT)
RETURNS VOID AS $$
BEGIN
    IF p_val < 0 THEN
        RAISE EXCEPTION 'Value cannot be negative: %', p_val;
    END IF;
END;
$$ LANGUAGE plpgsql;
```

注意：openGauss 基于 PostgreSQL，异常处理语法一致
注意：支持 EXCEPTION WHEN, RAISE, GET STACKED DIAGNOSTICS
限制：部分 PostgreSQL 新版特性可能不完全兼容
