# CockroachDB: 动态 SQL

> 参考资料:
> - [CockroachDB Documentation - PREPARE](https://www.cockroachlabs.com/docs/stable/prepare.html)
> - [CockroachDB Documentation - EXECUTE](https://www.cockroachlabs.com/docs/stable/execute.html)
> - [CockroachDB Documentation - PL/pgSQL](https://www.cockroachlabs.com/docs/stable/plpgsql.html)

**引擎定位**: 分布式 SQL 数据库，兼容 PostgreSQL 协议。基于 Pebble (RocksDB) 存储，Raft 共识，支持 Geo-Partitioning。

## PREPARE / EXECUTE / DEALLOCATE (兼容 PostgreSQL)

```sql
PREPARE user_query(INT) AS SELECT * FROM users WHERE age > $1;
EXECUTE user_query(25);
DEALLOCATE user_query;

```

## PL/pgSQL 中的 EXECUTE (动态 SQL)                   -- 23.1+

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

## 参数化（防止 SQL 注入）

```sql
CREATE OR REPLACE FUNCTION safe_search(p_table TEXT, p_value TEXT)
RETURNS VOID AS $$
BEGIN
    EXECUTE format('SELECT * FROM %I WHERE name = %L', p_table, p_value);
END;
$$ LANGUAGE plpgsql;

```

版本说明：
  CockroachDB 20.x+ : PREPARE / EXECUTE
  CockroachDB 23.1+ : PL/pgSQL 支持（包括 EXECUTE 动态 SQL）
**注意:** 语法与 PostgreSQL 高度兼容
**注意:** 使用 quote_ident() / format(%I, %L) 防止 SQL 注入
**限制:** PL/pgSQL 功能可能不如 PostgreSQL 完整
