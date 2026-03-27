-- MariaDB: Stored Procedures
-- MariaDB is a MySQL fork; only differences from MySQL are shown here.
--
-- 参考资料:
--   [1] MariaDB Knowledge Base
--       https://mariadb.com/kb/en/documentation/
--   [2] MariaDB vs MySQL Compatibility
--       https://mariadb.com/kb/en/mariadb-vs-mysql-compatibility/

-- Basic stored procedure (same as MySQL)
DELIMITER //
CREATE PROCEDURE get_user(IN p_username VARCHAR(64))
BEGIN
    SELECT * FROM users WHERE username = p_username;
END //
DELIMITER ;

-- Call (same as MySQL)
CALL get_user('alice');

-- OUT / INOUT parameters (same as MySQL)
DELIMITER //
CREATE PROCEDURE get_user_count(OUT p_count INT)
BEGIN
    SELECT COUNT(*) INTO p_count FROM users;
END //
DELIMITER ;

-- CREATE OR REPLACE PROCEDURE (MariaDB-specific, 10.1.3+)
-- Not available in MySQL (MySQL requires DROP then CREATE)
DELIMITER //
CREATE OR REPLACE PROCEDURE get_user(IN p_username VARCHAR(64))
BEGIN
    SELECT * FROM users WHERE username = p_username;
END //
DELIMITER ;

-- Variables and flow control (same as MySQL)
DELIMITER //
CREATE PROCEDURE transfer(
    IN p_from BIGINT, IN p_to BIGINT, IN p_amount DECIMAL(10,2)
)
BEGIN
    DECLARE v_balance DECIMAL(10,2);
    START TRANSACTION;
    SELECT balance INTO v_balance FROM accounts WHERE id = p_from FOR UPDATE;
    IF v_balance < p_amount THEN
        ROLLBACK;
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Insufficient balance';
    END IF;
    UPDATE accounts SET balance = balance - p_amount WHERE id = p_from;
    UPDATE accounts SET balance = balance + p_amount WHERE id = p_to;
    COMMIT;
END //
DELIMITER ;

-- Cursor (same as MySQL)
DELIMITER //
CREATE PROCEDURE process_users()
BEGIN
    DECLARE v_done INT DEFAULT FALSE;
    DECLARE v_username VARCHAR(64);
    DECLARE cur CURSOR FOR SELECT username FROM users;
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_done = TRUE;
    OPEN cur;
    read_loop: LOOP
        FETCH cur INTO v_username;
        IF v_done THEN LEAVE read_loop; END IF;
        -- process each row
    END LOOP;
    CLOSE cur;
END //
DELIMITER ;

-- Function (same as MySQL, but with OR REPLACE)
DELIMITER //
CREATE OR REPLACE FUNCTION full_name(first VARCHAR(50), last VARCHAR(50))
RETURNS VARCHAR(101)
DETERMINISTIC
BEGIN
    RETURN CONCAT(first, ' ', last);
END //
DELIMITER ;

-- AGGREGATE stored function (10.3.3+, MariaDB-specific)
-- Create custom aggregate functions (not available in MySQL)
DELIMITER //
CREATE AGGREGATE FUNCTION group_median(val DOUBLE)
RETURNS DOUBLE
DETERMINISTIC
BEGIN
    DECLARE cnt INT DEFAULT 0;
    DECLARE total DOUBLE DEFAULT 0;
    DECLARE CONTINUE HANDLER FOR NOT FOUND
        RETURN total / cnt;
    LOOP
        FETCH GROUP NEXT ROW;
        SET cnt = cnt + 1;
        SET total = total + val;
    END LOOP;
END //
DELIMITER ;

-- Usage of custom aggregate:
-- SELECT city, group_median(age) FROM users GROUP BY city;

-- Oracle-compatible PL/SQL (10.3+, with sql_mode=ORACLE)
-- MariaDB supports Oracle-compatible PL/SQL syntax
-- SET sql_mode = 'ORACLE';

-- PL/SQL procedure (Oracle mode):
-- CREATE OR REPLACE PROCEDURE get_user(p_username VARCHAR2)
-- IS
--     v_email VARCHAR2(255);
-- BEGIN
--     SELECT email INTO v_email FROM users WHERE username = p_username;
--     DBMS_OUTPUT.PUT_LINE(v_email);
-- EXCEPTION
--     WHEN NO_DATA_FOUND THEN
--         DBMS_OUTPUT.PUT_LINE('User not found');
-- END;
-- /

-- PL/SQL supports in Oracle mode:
-- EXCEPTION handling (WHEN ... THEN)
-- FOR ... LOOP (cursor FOR loop)
-- %ROWTYPE, %TYPE for variable declaration
-- RAISE_APPLICATION_ERROR
-- Anonymous blocks (BEGIN ... END)

-- Drop (same as MySQL, plus IF EXISTS)
DROP PROCEDURE IF EXISTS get_user;
DROP FUNCTION IF EXISTS full_name;

-- Differences from MySQL 8.0:
-- CREATE OR REPLACE PROCEDURE/FUNCTION (10.1.3+, not in MySQL)
-- Custom AGGREGATE FUNCTION (10.3.3+, not in MySQL)
-- Oracle-compatible PL/SQL via sql_mode=ORACLE (10.3+)
-- PL/SQL: packages, exceptions, %TYPE, %ROWTYPE in Oracle mode
-- Same core stored procedure capabilities as MySQL
-- Same SIGNAL/RESIGNAL for error handling
