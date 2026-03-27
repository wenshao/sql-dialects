-- Firebird: Triggers
--
-- 参考资料:
--   [1] Firebird SQL Reference
--       https://firebirdsql.org/en/reference-manuals/
--   [2] Firebird Release Notes
--       https://firebirdsql.org/file/documentation/release_notes/html/en/4_0/rlsnotes40.html

-- BEFORE INSERT trigger
SET TERM !! ;
CREATE OR ALTER TRIGGER trg_users_before_insert FOR users
ACTIVE BEFORE INSERT POSITION 0
AS
BEGIN
    IF (NEW.id IS NULL) THEN
        NEW.id = GEN_ID(gen_users_id, 1);
    NEW.created_at = CURRENT_TIMESTAMP;
    NEW.updated_at = CURRENT_TIMESTAMP;
END!!
SET TERM ; !!

-- AFTER INSERT trigger
SET TERM !! ;
CREATE OR ALTER TRIGGER trg_users_audit_insert FOR users
ACTIVE AFTER INSERT POSITION 0
AS
BEGIN
    INSERT INTO audit_log (table_name, action, record_id, created_at)
    VALUES ('USERS', 'INSERT', NEW.id, CURRENT_TIMESTAMP);
END!!
SET TERM ; !!

-- BEFORE UPDATE trigger
SET TERM !! ;
CREATE OR ALTER TRIGGER trg_users_before_update FOR users
ACTIVE BEFORE UPDATE POSITION 0
AS
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
END!!
SET TERM ; !!

-- AFTER UPDATE trigger
SET TERM !! ;
CREATE OR ALTER TRIGGER trg_users_email_changed FOR users
ACTIVE AFTER UPDATE POSITION 0
AS
BEGIN
    IF (OLD.email <> NEW.email) THEN
        INSERT INTO email_change_log (user_id, old_email, new_email, changed_at)
        VALUES (NEW.id, OLD.email, NEW.email, CURRENT_TIMESTAMP);
END!!
SET TERM ; !!

-- BEFORE DELETE trigger (archive before delete)
SET TERM !! ;
CREATE OR ALTER TRIGGER trg_users_before_delete FOR users
ACTIVE BEFORE DELETE POSITION 0
AS
BEGIN
    INSERT INTO users_archive (id, username, email, deleted_at)
    VALUES (OLD.id, OLD.username, OLD.email, CURRENT_TIMESTAMP);
END!!
SET TERM ; !!

-- Multi-event trigger (3.0+)
SET TERM !! ;
CREATE OR ALTER TRIGGER trg_users_audit FOR users
ACTIVE AFTER INSERT OR UPDATE OR DELETE POSITION 0
AS
BEGIN
    IF (INSERTING) THEN
        INSERT INTO audit_log (table_name, action, record_id)
        VALUES ('USERS', 'INSERT', NEW.id);
    ELSE IF (UPDATING) THEN
        INSERT INTO audit_log (table_name, action, record_id)
        VALUES ('USERS', 'UPDATE', NEW.id);
    ELSE IF (DELETING) THEN
        INSERT INTO audit_log (table_name, action, record_id)
        VALUES ('USERS', 'DELETE', OLD.id);
END!!
SET TERM ; !!

-- Trigger context variables (available in all triggers)
-- INSERTING: TRUE if trigger fired by INSERT
-- UPDATING: TRUE if trigger fired by UPDATE
-- DELETING: TRUE if trigger fired by DELETE
-- OLD.*: previous row values (UPDATE, DELETE)
-- NEW.*: new row values (INSERT, UPDATE)

-- Trigger with POSITION (execution order)
SET TERM !! ;
CREATE OR ALTER TRIGGER trg_first FOR users
ACTIVE BEFORE INSERT POSITION 0
AS
BEGIN
    NEW.status = 1;
END!!

CREATE OR ALTER TRIGGER trg_second FOR users
ACTIVE BEFORE INSERT POSITION 1
AS
BEGIN
    NEW.created_at = CURRENT_TIMESTAMP;
END!!
SET TERM ; !!

-- Database triggers (3.0+, fire on connect/disconnect/transaction events)
SET TERM !! ;
CREATE OR ALTER TRIGGER trg_on_connect
ACTIVE ON CONNECT POSITION 0
AS
BEGIN
    INSERT INTO connection_log (user_name, login_time)
    VALUES (CURRENT_USER, CURRENT_TIMESTAMP);
END!!

CREATE OR ALTER TRIGGER trg_on_disconnect
ACTIVE ON DISCONNECT POSITION 0
AS
BEGIN
    INSERT INTO connection_log (user_name, logout_time)
    VALUES (CURRENT_USER, CURRENT_TIMESTAMP);
END!!

CREATE OR ALTER TRIGGER trg_on_tx_start
ACTIVE ON TRANSACTION START POSITION 0
AS
BEGIN
    -- transaction start logic
    RDB$SET_CONTEXT('USER_SESSION', 'TX_START', CURRENT_TIMESTAMP);
END!!
SET TERM ; !!

-- Drop trigger
DROP TRIGGER trg_users_before_insert;

-- Deactivate/reactivate trigger
ALTER TRIGGER trg_users_audit INACTIVE;
ALTER TRIGGER trg_users_audit ACTIVE;

-- Events (Firebird-specific: notify client applications)
SET TERM !! ;
CREATE OR ALTER TRIGGER trg_notify_new_order FOR orders
ACTIVE AFTER INSERT POSITION 0
AS
BEGIN
    POST_EVENT 'new_order';
END!!
SET TERM ; !!

-- Note: SET TERM changes statement terminator for PSQL blocks
-- Note: POSITION controls trigger execution order (0 = first)
-- Note: INSERTING/UPDATING/DELETING context variables for multi-event triggers
-- Note: database triggers fire on connection/transaction events (unique)
-- Note: POST_EVENT is Firebird's event notification system (unique)
