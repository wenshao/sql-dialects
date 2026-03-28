# Redshift: 存储过程（PL/pgSQL 子集，2019+）

> 参考资料:
> - [Redshift SQL Reference](https://docs.aws.amazon.com/redshift/latest/dg/cm_chap_SQLCommandRef.html)
> - [Redshift SQL Functions](https://docs.aws.amazon.com/redshift/latest/dg/c_SQL_functions.html)
> - [Redshift Data Types](https://docs.aws.amazon.com/redshift/latest/dg/c_Supported_data_types.html)


创建存储过程
```sql
CREATE OR REPLACE PROCEDURE get_user(p_username VARCHAR)
AS $$
BEGIN
    -- 注意：Redshift 存储过程不能直接返回结果集
    -- 需要将结果写入临时表
    CREATE TEMP TABLE IF NOT EXISTS tmp_result (LIKE users);
    TRUNCATE tmp_result;
    INSERT INTO tmp_result
    SELECT * FROM users WHERE username = p_username;
END;
$$ LANGUAGE plpgsql;
```


调用
```sql
CALL get_user('alice');
SELECT * FROM tmp_result;
```


带 INOUT 参数
```sql
CREATE OR REPLACE PROCEDURE get_user_count(INOUT p_count BIGINT)
AS $$
BEGIN
    SELECT COUNT(*) INTO p_count FROM users;
END;
$$ LANGUAGE plpgsql;

CALL get_user_count(0);                      -- 返回计数值
```


事务控制（Redshift 存储过程可以控制事务！）
```sql
CREATE OR REPLACE PROCEDURE transfer(
    p_from_id BIGINT,
    p_to_id BIGINT,
    p_amount DECIMAL(10,2)
)
AS $$
DECLARE
    v_balance DECIMAL(10,2);
BEGIN
    SELECT balance INTO v_balance FROM accounts WHERE id = p_from_id;

    IF v_balance < p_amount THEN
        RAISE EXCEPTION 'Insufficient balance: %', v_balance;
    END IF;

    UPDATE accounts SET balance = balance - p_amount WHERE id = p_from_id;
    UPDATE accounts SET balance = balance + p_amount WHERE id = p_to_id;
```


在存储过程中可以显式提交
COMMIT;
```sql
END;
$$ LANGUAGE plpgsql;

CALL transfer(1, 2, 100.00);
```


循环
```sql
CREATE OR REPLACE PROCEDURE batch_update()
AS $$
DECLARE
    v_batch_size INT := 1000;
    v_offset INT := 0;
    v_count INT;
BEGIN
    SELECT COUNT(*) INTO v_count FROM users WHERE status = 0;

    WHILE v_offset < v_count LOOP
        UPDATE users SET status = 1
        WHERE id IN (
            SELECT id FROM users WHERE status = 0
            ORDER BY id LIMIT v_batch_size
        );
        v_offset := v_offset + v_batch_size;
        -- COMMIT;  -- 可以在循环中提交
    END LOOP;
END;
$$ LANGUAGE plpgsql;
```


游标
```sql
CREATE OR REPLACE PROCEDURE process_users()
AS $$
DECLARE
    v_username VARCHAR(64);
    cur CURSOR FOR SELECT username FROM users WHERE status = 1;
BEGIN
    OPEN cur;
    LOOP
        FETCH cur INTO v_username;
        EXIT WHEN NOT FOUND;
        -- 处理每行
        RAISE INFO 'Processing: %', v_username;
    END LOOP;
    CLOSE cur;
END;
$$ LANGUAGE plpgsql;
```


异常处理
```sql
CREATE OR REPLACE PROCEDURE safe_insert(
    p_username VARCHAR, p_email VARCHAR
)
AS $$
BEGIN
    INSERT INTO users (username, email) VALUES (p_username, p_email);
EXCEPTION
    WHEN OTHERS THEN
        RAISE WARNING 'Insert failed: %', SQLERRM;
        -- 不会回滚事务
END;
$$ LANGUAGE plpgsql;
```


条件逻辑
```sql
CREATE OR REPLACE PROCEDURE set_user_status(
    p_user_id BIGINT, p_new_status INT
)
AS $$
DECLARE
    v_current_status INT;
BEGIN
    SELECT status INTO v_current_status FROM users WHERE id = p_user_id;

    IF v_current_status IS NULL THEN
        RAISE EXCEPTION 'User % not found', p_user_id;
    ELSIF v_current_status = p_new_status THEN
        RAISE INFO 'Status already %', p_new_status;
    ELSE
        UPDATE users SET status = p_new_status, updated_at = GETDATE()
        WHERE id = p_user_id;
    END IF;
END;
$$ LANGUAGE plpgsql;
```


删除存储过程
```sql
DROP PROCEDURE IF EXISTS get_user(VARCHAR);
DROP PROCEDURE IF EXISTS get_user_count(BIGINT);
```


查看存储过程
```sql
SELECT proname, prosrc FROM pg_proc WHERE proname = 'get_user';
SHOW PROCEDURE get_user(VARCHAR);
```


注意：Redshift 存储过程使用 PL/pgSQL 的子集
注意：不能直接返回结果集（需要通过临时表或 INOUT 参数）
注意：支持事务控制（COMMIT / ROLLBACK）
注意：不支持用户自定义函数（UDF）返回表
注意：不支持触发器
注意：Lambda UDF 支持 Python / SQL（Redshift 2020+）
注意：存储过程在 Leader 节点或计算节点执行，取决于操作
