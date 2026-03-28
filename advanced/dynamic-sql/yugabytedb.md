# YugabyteDB: 动态 SQL

> 参考资料:
> - [YugabyteDB Documentation - PREPARE](https://docs.yugabyte.com/preview/api/ysql/the-sql-language/statements/perf_prepare/)
> - [YugabyteDB Documentation - PL/pgSQL](https://docs.yugabyte.com/preview/api/ysql/user-defined-subprograms-and-anon-blocks/)

**引擎定位**: 分布式 SQL 数据库，兼容 PostgreSQL 协议。基于 DocDB (RocksDB) 存储，Raft 共识。

## PREPARE / EXECUTE / DEALLOCATE (PostgreSQL 兼容)

```sql
PREPARE user_query(INT) AS SELECT * FROM users WHERE age > $1;
EXECUTE user_query(25);
DEALLOCATE user_query;

```

## PL/pgSQL EXECUTE (动态 SQL)

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

## EXECUTE ... USING (参数化动态 SQL)

```sql
CREATE OR REPLACE FUNCTION find_users(p_status TEXT, p_min_age INT)
RETURNS SETOF users AS $$
BEGIN
    RETURN QUERY EXECUTE
        'SELECT * FROM users WHERE status = $1 AND age >= $2'
        USING p_status, p_min_age;
END;
$$ LANGUAGE plpgsql;

```

## format() 构建安全的动态 SQL

```sql
CREATE OR REPLACE FUNCTION safe_insert(p_table TEXT, p_name TEXT, p_value INT)
RETURNS VOID AS $$
BEGIN
    EXECUTE format('INSERT INTO %I (name, value) VALUES (%L, %L)', p_table, p_name, p_value);
END;
$$ LANGUAGE plpgsql;

```

DO 块
```sql
DO $$
DECLARE
    tbl RECORD;
BEGIN
    FOR tbl IN SELECT tablename FROM pg_tables WHERE schemaname = 'public'
    LOOP
        EXECUTE 'ANALYZE ' || quote_ident(tbl.tablename);
    END LOOP;
END;
$$;

```

**注意:** YugabyteDB 兼容 PostgreSQL，动态 SQL 语法一致
**注意:** 使用 quote_ident() / format(%I, %L) 防止 SQL 注入
**注意:** 分布式环境下动态 DDL 可能需要更长时间
**限制:** 与 PostgreSQL 基本一致
