-- MariaDB: Triggers
-- MariaDB is a MySQL fork; only differences from MySQL are shown here.
--
-- 参考资料:
--   [1] MariaDB Knowledge Base
--       https://mariadb.com/kb/en/documentation/
--   [2] MariaDB vs MySQL Compatibility
--       https://mariadb.com/kb/en/mariadb-vs-mysql-compatibility/

-- BEFORE INSERT (same as MySQL)
DELIMITER //
CREATE TRIGGER trg_users_before_insert
BEFORE INSERT ON users
FOR EACH ROW
BEGIN
    SET NEW.created_at = NOW();
    SET NEW.updated_at = NOW();
    SET NEW.username = LOWER(NEW.username);
END //
DELIMITER ;

-- AFTER INSERT (same as MySQL)
DELIMITER //
CREATE TRIGGER trg_users_after_insert
AFTER INSERT ON users
FOR EACH ROW
BEGIN
    INSERT INTO audit_log (table_name, action, record_id, created_at)
    VALUES ('users', 'INSERT', NEW.id, NOW());
END //
DELIMITER ;

-- BEFORE UPDATE (same as MySQL)
DELIMITER //
CREATE TRIGGER trg_users_before_update
BEFORE UPDATE ON users
FOR EACH ROW
BEGIN
    SET NEW.updated_at = NOW();
END //
DELIMITER ;

-- AFTER DELETE (same as MySQL)
DELIMITER //
CREATE TRIGGER trg_users_after_delete
AFTER DELETE ON users
FOR EACH ROW
BEGIN
    INSERT INTO audit_log (table_name, action, record_id, old_data, created_at)
    VALUES ('users', 'DELETE', OLD.id, JSON_OBJECT('username', OLD.username), NOW());
END //
DELIMITER ;

-- CREATE OR REPLACE TRIGGER (MariaDB-specific, 10.1.4+)
-- Not available in MySQL (MySQL requires DROP then CREATE)
DELIMITER //
CREATE OR REPLACE TRIGGER trg_users_before_insert
BEFORE INSERT ON users
FOR EACH ROW
BEGIN
    SET NEW.created_at = NOW();
    SET NEW.updated_at = NOW();
END //
DELIMITER ;

-- Multiple triggers on same event (same as MySQL 5.7.2+)
-- FOLLOWS / PRECEDES for ordering
CREATE TRIGGER trg_validate BEFORE INSERT ON users
FOR EACH ROW FOLLOWS trg_users_before_insert
BEGIN
    IF NEW.age < 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Age cannot be negative';
    END IF;
END //

-- IF NOT EXISTS (10.1.4+, MariaDB-specific)
DELIMITER //
CREATE TRIGGER IF NOT EXISTS trg_users_before_insert
BEFORE INSERT ON users
FOR EACH ROW
BEGIN
    SET NEW.created_at = NOW();
END //
DELIMITER ;

-- Trigger with system versioning awareness
-- When modifying system-versioned tables, triggers fire on the current version
-- History rows are maintained by the system, not by triggers
DELIMITER //
CREATE TRIGGER trg_products_before_update
BEFORE UPDATE ON products  -- system-versioned table
FOR EACH ROW
BEGIN
    -- This fires for current row updates
    -- System automatically manages history (row_start, row_end)
    SET NEW.updated_by = CURRENT_USER();
END //
DELIMITER ;

-- Oracle-compatible triggers (sql_mode=ORACLE, 10.3+)
-- MariaDB supports Oracle PL/SQL trigger syntax in ORACLE mode
-- SET sql_mode = 'ORACLE';
-- CREATE OR REPLACE TRIGGER trg_users_before_insert
-- BEFORE INSERT ON users
-- FOR EACH ROW
-- BEGIN
--     :NEW.created_at := SYSDATE;
-- END;
-- /

-- Drop trigger
DROP TRIGGER IF EXISTS trg_users_before_insert;

-- Show triggers (same as MySQL)
SHOW TRIGGERS;
SELECT * FROM information_schema.TRIGGERS WHERE TRIGGER_SCHEMA = DATABASE();

-- Differences from MySQL 8.0:
-- CREATE OR REPLACE TRIGGER (MariaDB-specific, 10.1.4+)
-- IF NOT EXISTS (MariaDB-specific, 10.1.4+)
-- Oracle-compatible trigger syntax via sql_mode=ORACLE (10.3+)
-- Same trigger types: BEFORE/AFTER INSERT/UPDATE/DELETE
-- Same limitation: no INSTEAD OF triggers (except in ORACLE mode)
-- Same limitation: row-level only (FOR EACH ROW), no statement-level
-- System versioning interactions with triggers (10.3.4+)
