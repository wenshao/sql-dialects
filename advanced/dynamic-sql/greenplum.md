# Greenplum: Dynamic SQL

> 参考资料:
> - [Greenplum Documentation - PL/pgSQL](https://docs.vmware.com/en/VMware-Greenplum/7/greenplum-database/ref_guide-extensions-pl_sql.html)


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
CREATE OR REPLACE FUNCTION find_users(p_status TEXT, p_age INT)
RETURNS SETOF users AS $$
BEGIN
    RETURN QUERY EXECUTE
        'SELECT * FROM users WHERE status = $1 AND age >= $2'
        USING p_status, p_age;
END;
$$ LANGUAGE plpgsql;
```


## 动态分布式 DDL

```sql
CREATE OR REPLACE FUNCTION create_partition(p_year INT)
RETURNS VOID AS $$
BEGIN
    EXECUTE format(
        'CREATE TABLE orders_%s (LIKE orders) DISTRIBUTED BY (id)',
        p_year
    );
END;
$$ LANGUAGE plpgsql;
```


注意：Greenplum 基于 PostgreSQL，动态 SQL 语法一致
注意：使用 quote_ident() / format(%I, %L) 防止 SQL 注入
注意：分布式环境下动态 DDL 需注意分布键
限制：部分 PostgreSQL 新版本特性可能不支持
