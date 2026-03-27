-- OceanBase: Triggers
-- OceanBase has dual mode: MySQL mode and Oracle mode. Both shown where relevant.
--
-- 参考资料:
--   [1] OceanBase SQL Reference (MySQL Mode)
--       https://www.oceanbase.com/docs/common-oceanbase-database-cn
--   [2] OceanBase SQL Reference (Oracle Mode)
--       https://www.oceanbase.com/docs/common-oceanbase-database-cn

-- ============================================================
-- MySQL Mode (same as MySQL)
-- ============================================================

-- BEFORE INSERT
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

-- AFTER INSERT
DELIMITER //
CREATE TRIGGER trg_users_after_insert
AFTER INSERT ON users
FOR EACH ROW
BEGIN
    INSERT INTO audit_log (table_name, action, record_id, created_at)
    VALUES ('users', 'INSERT', NEW.id, NOW());
END //
DELIMITER ;

-- BEFORE UPDATE
DELIMITER //
CREATE TRIGGER trg_users_before_update
BEFORE UPDATE ON users
FOR EACH ROW
BEGIN
    SET NEW.updated_at = NOW();
END //
DELIMITER ;

-- AFTER DELETE
DELIMITER //
CREATE TRIGGER trg_users_after_delete
AFTER DELETE ON users
FOR EACH ROW
BEGIN
    INSERT INTO audit_log (table_name, action, record_id, created_at)
    VALUES ('users', 'DELETE', OLD.id, NOW());
END //
DELIMITER ;

-- Drop trigger
DROP TRIGGER IF EXISTS trg_users_before_insert;

-- Show triggers
SHOW TRIGGERS;

-- ============================================================
-- Oracle Mode (PL/SQL triggers)
-- ============================================================

-- BEFORE INSERT (row-level)
CREATE OR REPLACE TRIGGER trg_users_before_insert
BEFORE INSERT ON users
FOR EACH ROW
BEGIN
    IF :NEW.id IS NULL THEN
        :NEW.id := seq_users.NEXTVAL;
    END IF;
    :NEW.created_at := SYSTIMESTAMP;
END;
/

-- AFTER INSERT
CREATE OR REPLACE TRIGGER trg_users_after_insert
AFTER INSERT ON users
FOR EACH ROW
BEGIN
    INSERT INTO audit_log (table_name, action, record_id, created_at)
    VALUES ('users', 'INSERT', :NEW.id, SYSTIMESTAMP);
END;
/

-- BEFORE UPDATE
CREATE OR REPLACE TRIGGER trg_users_before_update
BEFORE UPDATE ON users
FOR EACH ROW
BEGIN
    :NEW.updated_at := SYSTIMESTAMP;
END;
/

-- AFTER DELETE
CREATE OR REPLACE TRIGGER trg_users_after_delete
AFTER DELETE ON users
FOR EACH ROW
BEGIN
    INSERT INTO audit_log (table_name, action, record_id, created_at)
    VALUES ('users', 'DELETE', :OLD.id, SYSTIMESTAMP);
END;
/

-- Statement-level trigger (Oracle mode, fires once per statement)
CREATE OR REPLACE TRIGGER trg_users_after_stmt
AFTER INSERT OR UPDATE OR DELETE ON users
BEGIN
    -- fires once for the entire statement, not per row
    INSERT INTO audit_log (table_name, action, created_at)
    VALUES ('users', 'BULK_CHANGE', SYSTIMESTAMP);
END;
/

-- Compound trigger (Oracle mode, 4.0+)
-- Combines statement-level and row-level trigger logic
CREATE OR REPLACE TRIGGER trg_users_compound
FOR INSERT ON users
COMPOUND TRIGGER
    v_count NUMBER := 0;

    BEFORE STATEMENT IS
    BEGIN
        v_count := 0;
    END BEFORE STATEMENT;

    BEFORE EACH ROW IS
    BEGIN
        :NEW.created_at := SYSTIMESTAMP;
        v_count := v_count + 1;
    END BEFORE EACH ROW;

    AFTER STATEMENT IS
    BEGIN
        DBMS_OUTPUT.PUT_LINE('Inserted ' || v_count || ' rows');
    END AFTER STATEMENT;
END;
/

-- INSTEAD OF trigger (Oracle mode, on views)
CREATE OR REPLACE TRIGGER trg_user_view_insert
INSTEAD OF INSERT ON user_view
FOR EACH ROW
BEGIN
    INSERT INTO users (username, email) VALUES (:NEW.username, :NEW.email);
END;
/

-- Conditional trigger with WHEN clause (Oracle mode)
CREATE OR REPLACE TRIGGER trg_check_salary
BEFORE UPDATE OF salary ON employees
FOR EACH ROW
WHEN (NEW.salary > OLD.salary * 1.5)
BEGIN
    RAISE_APPLICATION_ERROR(-20001, 'Salary increase exceeds 50%');
END;
/

-- Drop trigger (Oracle syntax)
DROP TRIGGER trg_users_before_insert;

-- Enable / Disable triggers (Oracle mode)
ALTER TRIGGER trg_users_before_insert DISABLE;
ALTER TRIGGER trg_users_before_insert ENABLE;
ALTER TABLE users DISABLE ALL TRIGGERS;
ALTER TABLE users ENABLE ALL TRIGGERS;

-- Limitations:
-- MySQL mode: same as MySQL (row-level only, no INSTEAD OF)
-- Oracle mode: statement-level, row-level, compound, INSTEAD OF triggers
-- Oracle mode: ENABLE/DISABLE trigger support
-- Oracle mode: WHEN clause for conditional firing
-- Distributed triggers may have performance implications
