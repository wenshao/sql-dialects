# KingbaseES (人大金仓): 存储过程和函数

PostgreSQL compatible PL/pgSQL with Oracle compatible PL/SQL.

> 参考资料:
> - [KingbaseES SQL Reference](https://help.kingbase.com.cn/v8/index.html)
> - [KingbaseES Documentation](https://help.kingbase.com.cn/v8/index.html)


## 创建函数（PL/pgSQL）

```sql
CREATE OR REPLACE FUNCTION get_user(p_username VARCHAR)
RETURNS TABLE (id BIGINT, username VARCHAR, email VARCHAR, age INTEGER)
AS $$
    SELECT id, username, email, age FROM users WHERE username = p_username;
$$ LANGUAGE sql;
```

## 调用

```sql
SELECT * FROM get_user('alice');
```

## PL/pgSQL 函数

```sql
CREATE OR REPLACE FUNCTION get_user_count()
RETURNS INTEGER AS $$
DECLARE
    v_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO v_count FROM users;
    RETURN v_count;
END;
$$ LANGUAGE plpgsql;

SELECT get_user_count();
```

## 存储过程（支持事务控制）

```sql
CREATE OR REPLACE PROCEDURE transfer(
    p_from BIGINT, p_to BIGINT, p_amount NUMERIC
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_balance NUMERIC;
BEGIN
    SELECT balance INTO v_balance FROM accounts WHERE id = p_from FOR UPDATE;

    IF v_balance < p_amount THEN
        RAISE EXCEPTION 'Insufficient balance: % < %', v_balance, p_amount;
    END IF;

    UPDATE accounts SET balance = balance - p_amount WHERE id = p_from;
    UPDATE accounts SET balance = balance + p_amount WHERE id = p_to;

    COMMIT;
END;
$$;
```

## 调用过程

```sql
CALL transfer(1, 2, 100.00);
```

## 带 OUT 参数

```sql
CREATE OR REPLACE FUNCTION get_stats(
    OUT min_age INTEGER, OUT max_age INTEGER, OUT avg_age NUMERIC
)
AS $$
    SELECT MIN(age), MAX(age), AVG(age) FROM users;
$$ LANGUAGE sql;
```

## 返回多行

```sql
CREATE OR REPLACE FUNCTION active_users()
RETURNS SETOF users AS $$
    SELECT * FROM users WHERE status = 1;
$$ LANGUAGE sql;
```

## 异常处理

```sql
CREATE OR REPLACE FUNCTION safe_divide(a NUMERIC, b NUMERIC)
RETURNS NUMERIC AS $$
BEGIN
    RETURN a / b;
EXCEPTION
    WHEN division_by_zero THEN
        RETURN NULL;
END;
$$ LANGUAGE plpgsql;
```

Oracle 兼容模式下的 PL/SQL 过程
CREATE OR REPLACE PROCEDURE get_user_oracle(p_username IN VARCHAR)
AS
v_email VARCHAR(255);
BEGIN
SELECT email INTO v_email FROM users WHERE username = p_username;
DBMS_OUTPUT.PUT_LINE('Email: ' || v_email);
END;
/
删除

```sql
DROP FUNCTION IF EXISTS get_user(VARCHAR);
DROP PROCEDURE IF EXISTS transfer(BIGINT, BIGINT, NUMERIC);
```

注意事项：
基本语法与 PostgreSQL 兼容（PL/pgSQL）
Oracle 兼容模式下支持 PL/SQL 语法
支持包（Package）在 Oracle 兼容模式下
支持多种过程语言（PL/pgSQL、SQL）
