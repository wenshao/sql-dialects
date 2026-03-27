-- SAP HANA: Stored Procedures (SQLScript)
--
-- 参考资料:
--   [1] SAP HANA SQL Reference
--       https://help.sap.com/docs/SAP_HANA_PLATFORM/4fe29514fd584807ac9f2a04f6754767/
--   [2] SAP HANA SQLScript Reference
--       https://help.sap.com/docs/SAP_HANA_PLATFORM/de2486ee947e43e684d39702027f8a94/

-- Basic procedure (read-only)
CREATE OR REPLACE PROCEDURE get_user_count(OUT v_count INTEGER)
LANGUAGE SQLSCRIPT
SQL SECURITY INVOKER
READS SQL DATA
AS
BEGIN
    SELECT COUNT(*) INTO v_count FROM users;
END;

-- Call procedure
CALL get_user_count(?);

-- Procedure with IN parameter returning table result
CREATE OR REPLACE PROCEDURE get_users_by_city(IN p_city NVARCHAR(64))
LANGUAGE SQLSCRIPT
READS SQL DATA
AS
BEGIN
    SELECT * FROM users WHERE city = :p_city;
END;

CALL get_users_by_city('Beijing');

-- Procedure with IN/OUT parameters
CREATE OR REPLACE PROCEDURE transfer(
    IN p_from BIGINT,
    IN p_to BIGINT,
    IN p_amount DECIMAL(12,2),
    OUT p_status NVARCHAR(50)
)
LANGUAGE SQLSCRIPT
SQL SECURITY INVOKER
AS
    v_balance DECIMAL(12,2);
BEGIN
    SELECT balance INTO v_balance FROM accounts WHERE id = :p_from;

    IF :v_balance < :p_amount THEN
        p_status = 'Insufficient balance';
    ELSE
        UPDATE accounts SET balance = balance - :p_amount WHERE id = :p_from;
        UPDATE accounts SET balance = balance + :p_amount WHERE id = :p_to;
        p_status = 'Success';
        COMMIT;
    END IF;
END;

-- Procedure with table variable output
CREATE OR REPLACE PROCEDURE get_user_stats(
    OUT ot_result TABLE (city NVARCHAR(64), cnt INTEGER, avg_age DECIMAL(10,2))
)
LANGUAGE SQLSCRIPT
READS SQL DATA
AS
BEGIN
    ot_result = SELECT city, COUNT(*) AS cnt, AVG(age) AS avg_age
                FROM users
                GROUP BY city;
END;

CALL get_user_stats(?);

-- Procedure with table variable (intermediate processing)
CREATE OR REPLACE PROCEDURE process_orders()
LANGUAGE SQLSCRIPT
AS
    lt_orders TABLE (user_id BIGINT, total DECIMAL(12,2));
BEGIN
    lt_orders = SELECT user_id, SUM(amount) AS total FROM orders GROUP BY user_id;

    UPSERT user_totals (user_id, total_amount)
    SELECT user_id, total FROM :lt_orders;
END;

-- Procedure with cursor (imperative style)
CREATE OR REPLACE PROCEDURE process_users()
LANGUAGE SQLSCRIPT
AS
    CURSOR cur FOR SELECT id, username FROM users WHERE status = 0;
BEGIN
    FOR row AS cur DO
        UPDATE users SET status = 1 WHERE id = row.id;
    END FOR;
END;

-- Procedure with error handling
CREATE OR REPLACE PROCEDURE safe_insert(
    IN p_username NVARCHAR(64),
    IN p_email NVARCHAR(255)
)
LANGUAGE SQLSCRIPT
AS
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        INSERT INTO error_log (message, created_at)
        VALUES ('Insert failed for ' || :p_username, CURRENT_TIMESTAMP);
    END;

    INSERT INTO users (username, email) VALUES (:p_username, :p_email);
END;

-- Function (scalar)
CREATE OR REPLACE FUNCTION get_user_email(p_username NVARCHAR(64))
RETURNS email NVARCHAR(255)
LANGUAGE SQLSCRIPT
READS SQL DATA
AS
BEGIN
    SELECT email INTO email FROM users WHERE username = :p_username;
END;

SELECT get_user_email('alice') FROM DUMMY;

-- Table function
CREATE OR REPLACE FUNCTION active_users()
RETURNS TABLE (id BIGINT, username NVARCHAR(64), email NVARCHAR(255))
LANGUAGE SQLSCRIPT
READS SQL DATA
AS
BEGIN
    RETURN SELECT id, username, email FROM users WHERE status = 1;
END;

SELECT * FROM active_users();

-- Drop
DROP PROCEDURE get_user_count;
DROP FUNCTION get_user_email;

-- Note: SQLScript is SAP HANA's procedural language
-- Note: variables use : prefix when reading (:v_balance)
-- Note: table variables enable set-based processing (preferred over cursors)
-- Note: SQL SECURITY INVOKER/DEFINER controls execution context
