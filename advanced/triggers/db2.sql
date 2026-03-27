-- IBM Db2: Triggers
--
-- 参考资料:
--   [1] Db2 SQL Reference
--       https://www.ibm.com/docs/en/db2/11.5?topic=sql
--   [2] Db2 Built-in Functions
--       https://www.ibm.com/docs/en/db2/11.5?topic=functions-built-in

-- BEFORE INSERT trigger
CREATE OR REPLACE TRIGGER trg_users_before_insert
BEFORE INSERT ON users
REFERENCING NEW AS n
FOR EACH ROW
BEGIN ATOMIC
    SET n.created_at = CURRENT TIMESTAMP;
    SET n.updated_at = CURRENT TIMESTAMP;
END;

-- AFTER INSERT trigger
CREATE OR REPLACE TRIGGER trg_users_audit_insert
AFTER INSERT ON users
REFERENCING NEW AS n
FOR EACH ROW
BEGIN ATOMIC
    INSERT INTO audit_log (table_name, action, record_id, created_at)
    VALUES ('users', 'INSERT', n.id, CURRENT TIMESTAMP);
END;

-- BEFORE UPDATE trigger
CREATE OR REPLACE TRIGGER trg_users_before_update
BEFORE UPDATE ON users
REFERENCING NEW AS n OLD AS o
FOR EACH ROW
BEGIN ATOMIC
    SET n.updated_at = CURRENT TIMESTAMP;
END;

-- AFTER UPDATE trigger with column condition
CREATE OR REPLACE TRIGGER trg_users_email_changed
AFTER UPDATE OF email ON users
REFERENCING NEW AS n OLD AS o
FOR EACH ROW
WHEN (o.email <> n.email)
BEGIN ATOMIC
    INSERT INTO email_change_log (user_id, old_email, new_email, changed_at)
    VALUES (n.id, o.email, n.email, CURRENT TIMESTAMP);
END;

-- BEFORE DELETE trigger
CREATE OR REPLACE TRIGGER trg_users_before_delete
BEFORE DELETE ON users
REFERENCING OLD AS o
FOR EACH ROW
BEGIN ATOMIC
    INSERT INTO users_archive (id, username, email, deleted_at)
    VALUES (o.id, o.username, o.email, CURRENT TIMESTAMP);
END;

-- INSTEAD OF trigger (on views)
CREATE OR REPLACE TRIGGER trg_view_insert
INSTEAD OF INSERT ON user_view
REFERENCING NEW AS n
FOR EACH ROW
BEGIN ATOMIC
    INSERT INTO users (username, email) VALUES (n.username, n.email);
END;

-- Statement-level trigger (FOR EACH STATEMENT)
CREATE OR REPLACE TRIGGER trg_users_stat_insert
AFTER INSERT ON users
FOR EACH STATEMENT
BEGIN ATOMIC
    UPDATE table_stats SET last_modified = CURRENT TIMESTAMP
    WHERE table_name = 'users';
END;

-- AFTER trigger with transition table (access all affected rows)
CREATE OR REPLACE TRIGGER trg_bulk_audit
AFTER INSERT ON users
REFERENCING NEW TABLE AS new_rows
FOR EACH STATEMENT
BEGIN ATOMIC
    INSERT INTO audit_log (table_name, action, record_id, created_at)
    SELECT 'users', 'INSERT', id, CURRENT TIMESTAMP
    FROM new_rows;
END;

-- Drop trigger
DROP TRIGGER trg_users_before_insert;

-- Enable/disable trigger (not directly supported; must drop/recreate)
-- Alternative: use ALTER TABLE ... DEACTIVATE ALL TRIGGERS (Db2 11.5+)

-- Note: BEGIN ATOMIC required for inline triggers
-- Note: REFERENCING names OLD/NEW for row, OLD TABLE/NEW TABLE for statement
-- Note: Db2 supports BEFORE, AFTER, and INSTEAD OF triggers
-- Note: no ENABLE/DISABLE trigger in standard Db2 (must drop/recreate)
