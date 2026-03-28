# Amazon Redshift: Dynamic SQL

> 参考资料:
> - [Redshift Documentation - PREPARE](https://docs.aws.amazon.com/redshift/latest/dg/r_PREPARE.html)
> - [Redshift Documentation - EXECUTE](https://docs.aws.amazon.com/redshift/latest/dg/r_EXECUTE.html)
> - [Redshift Documentation - Stored Procedures](https://docs.aws.amazon.com/redshift/latest/dg/stored-procedure-overview.html)


## PREPARE / EXECUTE / DEALLOCATE

```sql
PREPARE user_query(INT) AS SELECT * FROM users WHERE age > $1;
EXECUTE user_query(25);
DEALLOCATE user_query;
```


## 存储过程中的 EXECUTE (PL/pgSQL)

```sql
CREATE OR REPLACE PROCEDURE count_table(p_table VARCHAR(128))
AS $$
DECLARE
    row_count BIGINT;
BEGIN
    EXECUTE 'SELECT COUNT(*) FROM ' || p_table INTO row_count;
    RAISE INFO 'Table % has % rows', p_table, row_count;
END;
$$ LANGUAGE plpgsql;

CALL count_table('users');
```


## EXECUTE ... USING (参数化动态 SQL)

```sql
CREATE OR REPLACE PROCEDURE find_users(p_status VARCHAR, p_age INT)
AS $$
BEGIN
    EXECUTE 'SELECT * FROM users WHERE status = $1 AND age >= $2'
        USING p_status, p_age;
END;
$$ LANGUAGE plpgsql;
```


## 动态 DDL

```sql
CREATE OR REPLACE PROCEDURE create_archive(p_year INT)
AS $$
BEGIN
    EXECUTE 'CREATE TABLE orders_' || p_year::VARCHAR
         || ' AS SELECT * FROM orders WHERE EXTRACT(YEAR FROM order_date) = '
         || p_year::VARCHAR;
END;
$$ LANGUAGE plpgsql;
```


版本说明：
Redshift    : PREPARE / EXECUTE / DEALLOCATE
Redshift    : PL/pgSQL 存储过程 (2018+)
注意：Redshift 基于 PostgreSQL 8.0.2，PL/pgSQL 功能有限
注意：使用参数化查询防止 SQL 注入
限制：不支持 format() 函数
限制：不支持 quote_ident() / quote_literal()
限制：存储过程不支持返回结果集（需要使用临时表或 REFCURSOR）
