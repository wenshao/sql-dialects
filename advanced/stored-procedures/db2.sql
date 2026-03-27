-- IBM Db2: Stored Procedures (SQL PL)
--
-- 参考资料:
--   [1] Db2 SQL Reference
--       https://www.ibm.com/docs/en/db2/11.5?topic=sql
--   [2] Db2 Built-in Functions
--       https://www.ibm.com/docs/en/db2/11.5?topic=functions-built-in

-- Basic procedure
CREATE OR REPLACE PROCEDURE get_user_count(OUT v_count INTEGER)
LANGUAGE SQL
BEGIN
    SELECT COUNT(*) INTO v_count FROM users;
END;

-- Call procedure
CALL get_user_count(?);

-- Procedure with IN parameter
CREATE OR REPLACE PROCEDURE get_user_by_name(IN p_username VARCHAR(64))
LANGUAGE SQL
DYNAMIC RESULT SETS 1
BEGIN
    DECLARE cur CURSOR WITH RETURN FOR
        SELECT * FROM users WHERE username = p_username;
    OPEN cur;
END;

CALL get_user_by_name('alice');

-- Procedure with IN/OUT parameters
CREATE OR REPLACE PROCEDURE transfer(
    IN p_from BIGINT,
    IN p_to BIGINT,
    IN p_amount DECIMAL(12,2),
    OUT p_status VARCHAR(50)
)
LANGUAGE SQL
BEGIN
    DECLARE v_balance DECIMAL(12,2);

    SELECT balance INTO v_balance FROM accounts WHERE id = p_from;

    IF v_balance < p_amount THEN
        SET p_status = 'Insufficient balance';
    ELSE
        UPDATE accounts SET balance = balance - p_amount WHERE id = p_from;
        UPDATE accounts SET balance = balance + p_amount WHERE id = p_to;
        SET p_status = 'Success';
        COMMIT;
    END IF;
END;

-- Procedure with cursor
CREATE OR REPLACE PROCEDURE process_users()
LANGUAGE SQL
BEGIN
    DECLARE v_id BIGINT;
    DECLARE v_username VARCHAR(64);
    DECLARE v_end INTEGER DEFAULT 0;
    DECLARE NOT_FOUND CONDITION FOR SQLSTATE '02000';
    DECLARE cur CURSOR FOR
        SELECT id, username FROM users WHERE status = 0;
    DECLARE CONTINUE HANDLER FOR NOT_FOUND SET v_end = 1;

    OPEN cur;
    fetch_loop: LOOP
        FETCH cur INTO v_id, v_username;
        IF v_end = 1 THEN LEAVE fetch_loop; END IF;
        UPDATE users SET status = 1 WHERE id = v_id;
    END LOOP fetch_loop;
    CLOSE cur;
END;

-- Procedure with error handling
CREATE OR REPLACE PROCEDURE safe_insert(
    IN p_username VARCHAR(64),
    IN p_email VARCHAR(255)
)
LANGUAGE SQL
BEGIN
    DECLARE SQLCODE INTEGER DEFAULT 0;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        INSERT INTO error_log (message, created_at)
        VALUES ('Insert failed: SQLCODE=' || CHAR(SQLCODE), CURRENT TIMESTAMP);
        ROLLBACK;
    END;

    INSERT INTO users (username, email) VALUES (p_username, p_email);
    COMMIT;
END;

-- Function (returns scalar value)
CREATE OR REPLACE FUNCTION get_user_email(p_username VARCHAR(64))
RETURNS VARCHAR(255)
LANGUAGE SQL
READS SQL DATA
BEGIN
    DECLARE v_email VARCHAR(255);
    SELECT email INTO v_email FROM users WHERE username = p_username;
    RETURN v_email;
END;

SELECT get_user_email('alice') FROM SYSIBM.SYSDUMMY1;

-- Table function
CREATE OR REPLACE FUNCTION active_users()
RETURNS TABLE (id BIGINT, username VARCHAR(64), email VARCHAR(255))
LANGUAGE SQL
READS SQL DATA
BEGIN ATOMIC
    RETURN SELECT id, username, email FROM users WHERE status = 1;
END;

SELECT * FROM TABLE(active_users());

-- Drop
DROP PROCEDURE get_user_count;
DROP FUNCTION get_user_email;

-- Note: SQL PL is Db2's procedural language
-- Note: DYNAMIC RESULT SETS allows returning cursors
-- Note: BEGIN ATOMIC for inline compound statements
-- Note: Db2 also supports external procedures (C, Java, etc.)
