-- Firebird: DELETE
--
-- 参考资料:
--   [1] Firebird SQL Reference
--       https://firebirdsql.org/en/reference-manuals/
--   [2] Firebird Release Notes
--       https://firebirdsql.org/file/documentation/release_notes/html/en/4_0/rlsnotes40.html

-- Basic delete
DELETE FROM users WHERE username = 'alice';

-- Delete with subquery
DELETE FROM users WHERE id IN (SELECT user_id FROM blacklist);

-- Correlated subquery delete
DELETE FROM users
WHERE NOT EXISTS (SELECT 1 FROM orders WHERE orders.user_id = users.id);

-- RETURNING (2.1+, return deleted rows)
DELETE FROM users WHERE status = 0 RETURNING id, username;

-- RETURNING *
DELETE FROM users WHERE status = 0 RETURNING *;

-- Archive then delete using EXECUTE BLOCK with RETURNING
SET TERM !! ;
EXECUTE BLOCK
AS
    DECLARE v_id BIGINT;
    DECLARE v_username VARCHAR(64);
    DECLARE v_email VARCHAR(255);
BEGIN
    FOR DELETE FROM users WHERE status = 0
        RETURNING id, username, email INTO :v_id, :v_username, :v_email DO
    BEGIN
        INSERT INTO users_archive (id, username, email)
        VALUES (:v_id, :v_username, :v_email);
    END
END!!
SET TERM ; !!

-- Delete all rows
DELETE FROM users;

-- Note: no TRUNCATE TABLE in Firebird
-- Use DELETE FROM table for full table clear
-- Optionally follow with database sweep for garbage collection

-- Delete with PLAN (force index usage)
DELETE FROM users
WHERE age > 100
PLAN (users INDEX (idx_age));

-- Delete with ROWS clause (limit number of deleted rows, 2.0+)
DELETE FROM logs
ORDER BY created_at
ROWS 1000;

-- Cursor-based delete (in PSQL)
-- FOR SELECT id FROM users WHERE status = 0 AS CURSOR cur DO
--     DELETE FROM users WHERE CURRENT OF cur;

-- Note: deleted record versions remain until garbage collection
-- Note: use gfix -sweep or allow automatic sweep
-- Note: RETURNING can be used with INSERT ... SELECT for archive pattern
