# Amazon Redshift: Error Handling

> 参考资料:
> - [Redshift Documentation - Stored Procedures Error Handling](https://docs.aws.amazon.com/redshift/latest/dg/stored-procedure-trapping-errors.html)


## EXCEPTION WHEN (PL/pgSQL 存储过程)

```sql
CREATE OR REPLACE PROCEDURE safe_insert(p_id INT, p_name VARCHAR)
AS $$
BEGIN
    INSERT INTO users(id, username) VALUES(p_id, p_name);
EXCEPTION
    WHEN unique_violation THEN
        RAISE INFO 'Duplicate entry: %', p_name;
    WHEN OTHERS THEN
        RAISE WARNING 'Error: %', SQLERRM;
END;
$$ LANGUAGE plpgsql;
```


## RAISE

```sql
CREATE OR REPLACE PROCEDURE validate_amount(p_amount DECIMAL)
AS $$
BEGIN
    IF p_amount <= 0 THEN
        RAISE EXCEPTION 'Amount must be positive: %', p_amount;
    END IF;
END;
$$ LANGUAGE plpgsql;
```


## 事务与错误处理

```sql
CREATE OR REPLACE PROCEDURE transfer(p_from INT, p_to INT, p_amt DECIMAL)
AS $$
BEGIN
    UPDATE accounts SET balance = balance - p_amt WHERE id = p_from;
    UPDATE accounts SET balance = balance + p_amt WHERE id = p_to;
EXCEPTION WHEN OTHERS THEN
    RAISE INFO 'Transfer failed: %', SQLERRM;
    -- Redshift 存储过程中的异常自动回滚子事务
END;
$$ LANGUAGE plpgsql;
```


版本说明：
Redshift : PL/pgSQL 存储过程 (2018+)
注意：语法类似 PostgreSQL 但功能有限
注意：EXCEPTION 块中不支持事务控制 (COMMIT/ROLLBACK)
限制：不支持 GET STACKED DIAGNOSTICS
限制：不支持所有 PostgreSQL 异常条件名
