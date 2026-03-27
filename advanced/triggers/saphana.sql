-- SAP HANA: Triggers
--
-- 参考资料:
--   [1] SAP HANA SQL Reference
--       https://help.sap.com/docs/SAP_HANA_PLATFORM/4fe29514fd584807ac9f2a04f6754767/
--   [2] SAP HANA SQLScript Reference
--       https://help.sap.com/docs/SAP_HANA_PLATFORM/de2486ee947e43e684d39702027f8a94/

-- BEFORE INSERT trigger
CREATE OR REPLACE TRIGGER trg_users_before_insert
BEFORE INSERT ON users
REFERENCING NEW ROW AS new_row
FOR EACH ROW
BEGIN
    new_row.created_at = CURRENT_TIMESTAMP;
    new_row.updated_at = CURRENT_TIMESTAMP;
END;

-- AFTER INSERT trigger
CREATE OR REPLACE TRIGGER trg_users_audit_insert
AFTER INSERT ON users
REFERENCING NEW ROW AS new_row
FOR EACH ROW
BEGIN
    INSERT INTO audit_log (table_name, action, record_id, created_at)
    VALUES ('users', 'INSERT', :new_row.id, CURRENT_TIMESTAMP);
END;

-- BEFORE UPDATE trigger
CREATE OR REPLACE TRIGGER trg_users_before_update
BEFORE UPDATE ON users
REFERENCING NEW ROW AS new_row OLD ROW AS old_row
FOR EACH ROW
BEGIN
    new_row.updated_at = CURRENT_TIMESTAMP;
END;

-- AFTER UPDATE trigger with condition
CREATE OR REPLACE TRIGGER trg_users_email_changed
AFTER UPDATE OF email ON users
REFERENCING NEW ROW AS new_row OLD ROW AS old_row
FOR EACH ROW
BEGIN
    IF :old_row.email <> :new_row.email THEN
        INSERT INTO email_change_log (user_id, old_email, new_email, changed_at)
        VALUES (:new_row.id, :old_row.email, :new_row.email, CURRENT_TIMESTAMP);
    END IF;
END;

-- BEFORE DELETE trigger (archive before delete)
CREATE OR REPLACE TRIGGER trg_users_before_delete
BEFORE DELETE ON users
REFERENCING OLD ROW AS old_row
FOR EACH ROW
BEGIN
    INSERT INTO users_archive (id, username, email, deleted_at)
    VALUES (:old_row.id, :old_row.username, :old_row.email, CURRENT_TIMESTAMP);
END;

-- INSTEAD OF trigger (on views)
CREATE OR REPLACE TRIGGER trg_view_insert
INSTEAD OF INSERT ON user_view
REFERENCING NEW ROW AS new_row
FOR EACH ROW
BEGIN
    INSERT INTO users (username, email)
    VALUES (:new_row.username, :new_row.email);
END;

-- Statement-level trigger (FOR EACH STATEMENT)
CREATE OR REPLACE TRIGGER trg_users_stat_insert
AFTER INSERT ON users
FOR EACH STATEMENT
BEGIN
    UPDATE table_stats SET last_modified = CURRENT_TIMESTAMP
    WHERE table_name = 'users';
END;

-- Trigger with error handling
CREATE OR REPLACE TRIGGER trg_validate_age
BEFORE INSERT ON users
REFERENCING NEW ROW AS new_row
FOR EACH ROW
BEGIN
    IF :new_row.age < 0 OR :new_row.age > 200 THEN
        SIGNAL SQL_ERROR_CODE 10001
            SET MESSAGE_TEXT = 'Invalid age: ' || TO_NVARCHAR(:new_row.age);
    END IF;
END;

-- Drop trigger
DROP TRIGGER trg_users_before_insert;

-- Enable/disable trigger
ALTER TRIGGER trg_users_audit_insert DISABLE;
ALTER TRIGGER trg_users_audit_insert ENABLE;

-- Note: SAP HANA triggers use SQLScript language
-- Note: variable references use : prefix (:new_row.id)
-- Note: SIGNAL SQL_ERROR_CODE raises custom errors
-- Note: supports BEFORE, AFTER, INSTEAD OF triggers
-- Note: FOR EACH ROW and FOR EACH STATEMENT levels
