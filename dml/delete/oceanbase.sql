-- OceanBase: DELETE
-- OceanBase has dual mode: MySQL mode and Oracle mode. Both shown where relevant.
--
-- 参考资料:
--   [1] OceanBase SQL Reference (MySQL Mode)
--       https://www.oceanbase.com/docs/common-oceanbase-database-cn
--   [2] OceanBase SQL Reference (Oracle Mode)
--       https://www.oceanbase.com/docs/common-oceanbase-database-cn

-- ============================================================
-- MySQL Mode
-- ============================================================

-- Basic delete (same as MySQL)
DELETE FROM users WHERE username = 'alice';

-- DELETE with LIMIT / ORDER BY
DELETE FROM users WHERE status = 0 ORDER BY created_at LIMIT 100;

-- Multi-table delete (same as MySQL)
DELETE u FROM users u
JOIN blacklist b ON u.email = b.email;

-- DELETE from multiple tables simultaneously
DELETE u, o FROM users u
JOIN orders o ON u.id = o.user_id
WHERE u.status = 0;

-- DELETE with CTE
WITH inactive AS (
    SELECT id FROM users WHERE last_login < '2023-01-01'
)
DELETE u FROM users u JOIN inactive i ON u.id = i.id;

-- TRUNCATE (same as MySQL)
TRUNCATE TABLE users;

-- DELETE IGNORE
DELETE IGNORE FROM users WHERE id = 1;

-- Parallel DML hint (OceanBase-specific)
DELETE /*+ ENABLE_PARALLEL_DML PARALLEL(4) */ FROM users
WHERE last_login < '2023-01-01';

-- Subquery delete
DELETE FROM users WHERE id IN (SELECT user_id FROM blacklist);

-- ============================================================
-- Oracle Mode
-- ============================================================

-- Basic delete
DELETE FROM users WHERE username = 'alice';

-- DELETE with RETURNING (Oracle mode)
DELETE FROM users WHERE username = 'alice'
RETURNING id, username, email INTO :v_id, :v_name, :v_email;

-- Subquery delete
DELETE FROM users WHERE id IN (SELECT user_id FROM blacklist);

-- Correlated subquery delete
DELETE FROM users u
WHERE EXISTS (SELECT 1 FROM blacklist b WHERE b.user_id = u.id);

-- TRUNCATE (Oracle syntax)
TRUNCATE TABLE users;

-- Multi-table delete with MERGE (delete matched rows)
MERGE INTO users t
USING blacklist s ON (t.email = s.email)
WHEN MATCHED THEN DELETE;
-- Note: MERGE ... DELETE supported in Oracle mode 4.0+

-- Limitations:
-- MySQL mode: mostly identical to MySQL
-- Oracle mode: DELETE with RETURNING supported
-- Large deletes should be batched for performance
-- Partition-level delete: DROP PARTITION is faster than DELETE for removing all data
--   ALTER TABLE logs DROP PARTITION p2023;
