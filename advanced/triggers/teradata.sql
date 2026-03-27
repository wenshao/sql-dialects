-- Teradata: Triggers
--
-- 参考资料:
--   [1] Teradata SQL Reference
--       https://docs.teradata.com/r/Teradata-VantageTM-SQL-Functions-Expressions-and-Predicates
--   [2] Teradata Database Documentation
--       https://docs.teradata.com/

-- BEFORE INSERT trigger
CREATE TRIGGER trg_users_before_insert
BEFORE INSERT ON users
REFERENCING NEW AS new_row
FOR EACH ROW
BEGIN
    SET new_row.created_at = CURRENT_TIMESTAMP;
    SET new_row.updated_at = CURRENT_TIMESTAMP;
END;

-- AFTER INSERT trigger
CREATE TRIGGER trg_users_audit_insert
AFTER INSERT ON users
REFERENCING NEW AS new_row
FOR EACH ROW
BEGIN
    INSERT INTO audit_log (table_name, action, record_id, created_at)
    VALUES ('users', 'INSERT', new_row.id, CURRENT_TIMESTAMP);
END;

-- BEFORE UPDATE trigger
CREATE TRIGGER trg_users_before_update
BEFORE UPDATE ON users
REFERENCING NEW AS new_row OLD AS old_row
FOR EACH ROW
BEGIN
    SET new_row.updated_at = CURRENT_TIMESTAMP;
END;

-- AFTER UPDATE trigger with condition
CREATE TRIGGER trg_users_email_changed
AFTER UPDATE OF email ON users
REFERENCING NEW AS new_row OLD AS old_row
FOR EACH ROW
WHEN (old_row.email <> new_row.email)
BEGIN
    INSERT INTO email_change_log (user_id, old_email, new_email, changed_at)
    VALUES (new_row.id, old_row.email, new_row.email, CURRENT_TIMESTAMP);
END;

-- BEFORE DELETE trigger
CREATE TRIGGER trg_users_before_delete
BEFORE DELETE ON users
REFERENCING OLD AS old_row
FOR EACH ROW
BEGIN
    INSERT INTO users_archive (id, username, email, deleted_at)
    VALUES (old_row.id, old_row.username, old_row.email, CURRENT_TIMESTAMP);
END;

-- AFTER DELETE trigger
CREATE TRIGGER trg_users_after_delete
AFTER DELETE ON users
REFERENCING OLD AS old_row
FOR EACH ROW
BEGIN
    INSERT INTO audit_log (table_name, action, record_id, created_at)
    VALUES ('users', 'DELETE', old_row.id, CURRENT_TIMESTAMP);
END;

-- Statement-level trigger (FOR EACH STATEMENT)
CREATE TRIGGER trg_users_statement
AFTER INSERT ON users
FOR EACH STATEMENT
BEGIN
    COLLECT STATISTICS ON users;
END;

-- Trigger order (multiple triggers on same event)
CREATE TRIGGER trg_first
ORDER 1
BEFORE INSERT ON users
REFERENCING NEW AS new_row
FOR EACH ROW
BEGIN
    SET new_row.status = 1;
END;

CREATE TRIGGER trg_second
ORDER 2
BEFORE INSERT ON users
REFERENCING NEW AS new_row
FOR EACH ROW
BEGIN
    SET new_row.created_at = CURRENT_TIMESTAMP;
END;

-- Replace trigger
REPLACE TRIGGER trg_users_before_insert
BEFORE INSERT ON users
REFERENCING NEW AS new_row
FOR EACH ROW
BEGIN
    SET new_row.created_at = CURRENT_TIMESTAMP;
END;

-- Drop trigger
DROP TRIGGER trg_users_before_insert;

-- Note: Teradata triggers support BEFORE/AFTER, ROW/STATEMENT level
-- Note: REFERENCING clause names OLD and NEW row aliases
-- Note: ORDER clause controls execution order of multiple triggers
-- Note: REPLACE TRIGGER replaces existing trigger
-- Note: triggers can reference other tables
