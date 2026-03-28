# Teradata: Stored Procedures (SPL - Stored Procedure Language)

> 参考资料:
> - [Teradata SQL Reference](https://docs.teradata.com/r/Teradata-VantageTM-SQL-Functions-Expressions-and-Predicates)
> - [Teradata Database Documentation](https://docs.teradata.com/)


Basic procedure
```sql
REPLACE PROCEDURE get_user_count(OUT v_count INTEGER)
BEGIN
    SELECT COUNT(*) INTO v_count FROM users;
END;
```


Call procedure
```sql
CALL get_user_count(result_count);
```


Procedure with IN parameter
```sql
REPLACE PROCEDURE get_user_by_name(IN p_username VARCHAR(64))
BEGIN
    SELECT * FROM users WHERE username = p_username;
END;

CALL get_user_by_name('alice');
```


Procedure with IN/OUT parameters
```sql
REPLACE PROCEDURE transfer(
    IN p_from INTEGER,
    IN p_to INTEGER,
    IN p_amount DECIMAL(12,2),
    OUT p_status VARCHAR(50)
)
BEGIN
    DECLARE v_balance DECIMAL(12,2);

    SELECT balance INTO v_balance FROM accounts WHERE id = p_from;

    IF v_balance < p_amount THEN
        SET p_status = 'Insufficient balance';
    ELSE
        UPDATE accounts SET balance = balance - p_amount WHERE id = p_from;
        UPDATE accounts SET balance = balance + p_amount WHERE id = p_to;
        SET p_status = 'Success';
    END IF;
END;
```


Procedure with cursor
```sql
REPLACE PROCEDURE process_users()
BEGIN
    DECLARE v_id INTEGER;
    DECLARE v_username VARCHAR(64);
    DECLARE v_done INTEGER DEFAULT 0;
    DECLARE cur CURSOR FOR
        SELECT id, username FROM users WHERE status = 0;
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_done = 1;

    OPEN cur;
    read_loop: LOOP
        FETCH cur INTO v_id, v_username;
        IF v_done = 1 THEN LEAVE read_loop; END IF;
        UPDATE users SET status = 1 WHERE id = v_id;
    END LOOP read_loop;
    CLOSE cur;
END;
```


Procedure with dynamic SQL
```sql
REPLACE PROCEDURE run_query(IN p_sql VARCHAR(10000))
BEGIN
    CALL DBC.SysExecSQL(p_sql);
END;
```


Procedure with error handling
```sql
REPLACE PROCEDURE safe_insert(
    IN p_username VARCHAR(64),
    IN p_email VARCHAR(255)
)
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        -- Log error or take action
        INSERT INTO error_log (message, created_at)
        VALUES ('Insert failed for ' || p_username, CURRENT_TIMESTAMP);
    END;

    INSERT INTO users (username, email) VALUES (p_username, p_email);
END;
```


Procedure with WHILE loop
```sql
REPLACE PROCEDURE populate_data(IN p_count INTEGER)
BEGIN
    DECLARE v_i INTEGER DEFAULT 1;
    WHILE v_i <= p_count DO
        INSERT INTO test_data (id, value) VALUES (v_i, v_i * 10);
        SET v_i = v_i + 1;
    END WHILE;
END;
```


Procedure returning result set
```sql
REPLACE PROCEDURE get_active_users()
DYNAMIC RESULT SETS 1
BEGIN
    DECLARE cur CURSOR WITH RETURN ONLY FOR
        SELECT * FROM users WHERE status = 1;
    OPEN cur;
END;
```


Drop procedure
```sql
DROP PROCEDURE get_user_count;
```


Note: REPLACE PROCEDURE creates or replaces
Note: SPL supports cursors, loops, conditionals, exception handling
Note: DYNAMIC RESULT SETS allows returning query results
Note: no CREATE OR REPLACE; use REPLACE PROCEDURE
