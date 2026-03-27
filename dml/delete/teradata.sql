-- Teradata: DELETE
--
-- 参考资料:
--   [1] Teradata SQL Reference
--       https://docs.teradata.com/r/Teradata-VantageTM-SQL-Functions-Expressions-and-Predicates
--   [2] Teradata Database Documentation
--       https://docs.teradata.com/

-- Basic delete
DELETE FROM users WHERE username = 'alice';

-- Delete with join (using subquery)
DELETE FROM users WHERE id IN (SELECT user_id FROM blacklist);

-- Delete with FROM (join delete)
DELETE FROM users
WHERE EXISTS (SELECT 1 FROM blacklist WHERE blacklist.email = users.email);

-- Correlated subquery delete
DELETE FROM users
WHERE NOT EXISTS (SELECT 1 FROM orders WHERE orders.user_id = users.id);

-- Delete all rows
DELETE FROM users;

-- Delete all rows (faster, DDL operation)
DELETE users ALL;  -- Teradata-specific shortcut

-- TRUNCATE (not available in older versions; use DELETE ALL)
-- Note: no standard TRUNCATE in older Teradata

-- Delete with SAMPLE (delete a sample of rows)
DELETE FROM users WHERE username IN (
    SELECT username FROM users SAMPLE 100
);

-- Archive then delete (two-step)
INSERT INTO users_archive SELECT * FROM users WHERE status = 0;
DELETE FROM users WHERE status = 0;

-- Delete using VOLATILE table for staging
CREATE VOLATILE TABLE vt_delete_ids (id INTEGER) PRIMARY INDEX (id) ON COMMIT PRESERVE ROWS;
INSERT INTO vt_delete_ids SELECT id FROM users WHERE last_login < DATE '2023-01-01';
DELETE FROM users WHERE id IN (SELECT id FROM vt_delete_ids);
DROP TABLE vt_delete_ids;

-- Note: Teradata does not support RETURNING on DELETE
-- Note: COLLECT STATISTICS after large deletes
COLLECT STATISTICS ON users;

-- Note: DELETE is an all-AMP operation when no PI condition is used
-- Note: use PI column in WHERE clause for single-AMP delete
DELETE FROM users WHERE id = 123;  -- single-AMP if id is UPI
