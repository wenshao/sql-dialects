-- Firebird: Stored Procedures (PSQL)
--
-- 参考资料:
--   [1] Firebird SQL Reference
--       https://firebirdsql.org/en/reference-manuals/
--   [2] Firebird Release Notes
--       https://firebirdsql.org/file/documentation/release_notes/html/en/4_0/rlsnotes40.html

-- Executable procedure (performs action, no result set)
SET TERM !! ;
CREATE OR ALTER PROCEDURE transfer(
    p_from BIGINT,
    p_to BIGINT,
    p_amount DECIMAL(12,2)
)
AS
    DECLARE v_balance DECIMAL(12,2);
BEGIN
    SELECT balance FROM accounts WHERE id = :p_from INTO :v_balance;

    IF (v_balance < p_amount) THEN
        EXCEPTION insufficient_balance 'Balance too low: ' || v_balance;

    UPDATE accounts SET balance = balance - :p_amount WHERE id = :p_from;
    UPDATE accounts SET balance = balance + :p_amount WHERE id = :p_to;
END!!
SET TERM ; !!

-- Call executable procedure
EXECUTE PROCEDURE transfer(1, 2, 100.00);

-- Procedure with output parameters
SET TERM !! ;
CREATE OR ALTER PROCEDURE get_user_count
RETURNS (v_count INTEGER)
AS
BEGIN
    SELECT COUNT(*) FROM users INTO :v_count;
END!!
SET TERM ; !!

EXECUTE PROCEDURE get_user_count;

-- Selectable procedure (returns result set, Firebird-unique)
SET TERM !! ;
CREATE OR ALTER PROCEDURE get_active_users
RETURNS (
    id BIGINT,
    username VARCHAR(64),
    email VARCHAR(255),
    age INTEGER
)
AS
BEGIN
    FOR SELECT id, username, email, age FROM users WHERE status = 1
        INTO :id, :username, :email, :age DO
        SUSPEND;  -- yields one row to caller
END!!
SET TERM ; !!

-- Use selectable procedure like a table
SELECT * FROM get_active_users;
SELECT * FROM get_active_users WHERE age > 25;

-- Procedure with cursor and logic
SET TERM !! ;
CREATE OR ALTER PROCEDURE process_inactive_users
RETURNS (processed_count INTEGER)
AS
    DECLARE v_id BIGINT;
BEGIN
    processed_count = 0;
    FOR SELECT id FROM users WHERE status = 0 INTO :v_id DO
    BEGIN
        UPDATE users SET status = 1, updated_at = CURRENT_TIMESTAMP WHERE id = :v_id;
        processed_count = processed_count + 1;
    END
END!!
SET TERM ; !!

-- Procedure with exception handling
SET TERM !! ;
CREATE OR ALTER PROCEDURE safe_insert(
    p_username VARCHAR(64),
    p_email VARCHAR(255)
)
AS
BEGIN
    BEGIN
        INSERT INTO users (username, email) VALUES (:p_username, :p_email);
    WHEN ANY DO
        INSERT INTO error_log (message, created_at)
        VALUES ('Insert failed for ' || :p_username, CURRENT_TIMESTAMP);
    END
END!!
SET TERM ; !!

-- EXECUTE BLOCK (anonymous procedure, like anonymous PL/SQL block)
SET TERM !! ;
EXECUTE BLOCK
RETURNS (username VARCHAR(64), order_count INTEGER)
AS
BEGIN
    FOR SELECT u.username, COUNT(o.order_id)
        FROM users u LEFT JOIN orders o ON u.id = o.user_id
        GROUP BY u.username
        HAVING COUNT(o.order_id) > 5
        INTO :username, :order_count DO
        SUSPEND;
END!!
SET TERM ; !!

-- Custom exceptions
CREATE EXCEPTION insufficient_balance 'Insufficient balance';
CREATE EXCEPTION user_not_found 'User not found';

-- Drop procedure
DROP PROCEDURE get_user_count;

-- Note: SET TERM changes the statement terminator (needed for PSQL blocks)
-- Note: SUSPEND yields rows in selectable procedures (unique to Firebird)
-- Note: selectable procedures can be used in SELECT FROM (like table functions)
-- Note: EXECUTE BLOCK allows anonymous PSQL execution
-- Note: WHEN ANY DO catches all exceptions (like WHEN OTHERS in Oracle)
