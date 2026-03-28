# Vertica: 存储过程

> 参考资料:
> - [Vertica SQL Reference](https://www.vertica.com/docs/latest/HTML/Content/Authoring/SQLReferenceManual/SQLReferenceManual.htm)
> - [Vertica Functions](https://www.vertica.com/docs/latest/HTML/Content/Authoring/SQLReferenceManual/Functions/Functions.htm)


Vertica 支持存储过程（PL/vSQL 语言）

## 基本存储过程


```sql
CREATE OR REPLACE PROCEDURE hello_world()
LANGUAGE PLvSQL
AS $$
BEGIN
    RAISE NOTICE 'Hello, World!';
END;
$$;

CALL hello_world();
```


## 带参数的存储过程


```sql
CREATE OR REPLACE PROCEDURE transfer(
    p_from INT, p_to INT, p_amount NUMERIC
)
LANGUAGE PLvSQL
AS $$
DECLARE
    v_balance NUMERIC;
BEGIN
    SELECT balance INTO v_balance FROM accounts WHERE id = p_from;

    IF v_balance < p_amount THEN
        RAISE EXCEPTION 'Insufficient balance: % < %', v_balance, p_amount;
    END IF;

    UPDATE accounts SET balance = balance - p_amount WHERE id = p_from;
    UPDATE accounts SET balance = balance + p_amount WHERE id = p_to;

    COMMIT;
END;
$$;

CALL transfer(1, 2, 100.00);
```


## 带返回值的存储过程


```sql
CREATE OR REPLACE PROCEDURE get_user_count(OUT v_count INT)
LANGUAGE PLvSQL
AS $$
BEGIN
    SELECT COUNT(*) INTO v_count FROM users;
END;
$$;
```


## 循环和游标


```sql
CREATE OR REPLACE PROCEDURE process_users()
LANGUAGE PLvSQL
AS $$
DECLARE
    v_id INT;
    v_username VARCHAR(64);
    cur CURSOR FOR SELECT id, username FROM users WHERE status = 0;
BEGIN
    OPEN cur;
    LOOP
        FETCH cur INTO v_id, v_username;
        IF NOT FOUND THEN EXIT; END IF;

        UPDATE users SET status = 1 WHERE id = v_id;
        RAISE NOTICE 'Processed user: %', v_username;
    END LOOP;
    CLOSE cur;
END;
$$;
```


## 异常处理


```sql
CREATE OR REPLACE PROCEDURE safe_operation()
LANGUAGE PLvSQL
AS $$
BEGIN
    INSERT INTO users (id, username) VALUES (1, 'alice');
EXCEPTION
    WHEN unique_violation THEN
        RAISE NOTICE 'User already exists';
    WHEN OTHERS THEN
        RAISE NOTICE 'Error: %', SQLERRM;
END;
$$;
```


## UDF（用户自定义函数）


SQL UDF
```sql
CREATE OR REPLACE FUNCTION full_name(first_name VARCHAR, last_name VARCHAR)
RETURNS VARCHAR
AS $$
    SELECT first_name || ' ' || last_name;
$$ LANGUAGE SQL;
```


UDF in C++ / Java / Python / R
CREATE OR REPLACE FUNCTION my_func(x INT) RETURNS INT
AS LANGUAGE 'C++' NAME 'MyFuncFactory' LIBRARY MyLib;

## UDTF（用户自定义表函数）


UDTF 返回多行多列（需要 C++/Java/Python 实现）
CREATE OR REPLACE TRANSFORM FUNCTION my_explode
AS LANGUAGE 'C++' NAME 'ExplodeFactory' LIBRARY MyLib;

## 删除


```sql
DROP PROCEDURE IF EXISTS hello_world();
DROP FUNCTION IF EXISTS full_name(VARCHAR, VARCHAR);
```


注意：Vertica 使用 PL/vSQL 语言（类似 PL/pgSQL）
注意：存储过程支持事务控制（COMMIT/ROLLBACK）
注意：支持 C++/Java/Python/R 编写 UDF
注意：UDTF（Transform Function）可以返回多行
