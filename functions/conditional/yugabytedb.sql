-- YugabyteDB: Conditional Functions (YSQL, v2.x+)
--
-- 参考资料:
--   [1] YugabyteDB YSQL Reference
--       https://docs.yugabyte.com/stable/api/ysql/
--   [2] YugabyteDB PostgreSQL Compatibility
--       https://docs.yugabyte.com/stable/explore/ysql-language-features/

-- YugabyteDB supports all PostgreSQL conditional functions

-- CASE WHEN
SELECT username,
    CASE
        WHEN age < 18 THEN 'minor'
        WHEN age < 65 THEN 'adult'
        ELSE 'senior'
    END AS category
FROM users;

-- Simple CASE
SELECT username,
    CASE status
        WHEN 0 THEN 'inactive'
        WHEN 1 THEN 'active'
        WHEN 2 THEN 'deleted'
        ELSE 'unknown'
    END AS status_name
FROM users;

-- COALESCE
SELECT COALESCE(phone, email, 'unknown') FROM users;

-- NULLIF
SELECT NULLIF(age, 0) FROM users;              -- returns NULL if age = 0

-- GREATEST / LEAST
SELECT GREATEST(1, 3, 2);                      -- 3
SELECT LEAST(1, 3, 2);                         -- 1

-- Type casting (PostgreSQL syntax)
SELECT CAST('123' AS INTEGER);
SELECT '123'::INTEGER;                          -- :: syntax
SELECT '2024-01-15'::DATE;
SELECT CAST('true' AS BOOLEAN);

-- Safe casting (no built-in TRY_CAST)
SELECT CASE WHEN '123a' ~ '^\d+$' THEN '123a'::INTEGER ELSE NULL END;

-- Boolean expression as value (same as PostgreSQL)
SELECT username, (age >= 18) AS is_adult FROM users;

-- IS DISTINCT FROM (NULL-safe comparison)
SELECT * FROM users WHERE phone IS DISTINCT FROM 'unknown';
SELECT * FROM users WHERE phone IS NOT DISTINCT FROM NULL;

-- num_nulls / num_nonnulls
SELECT num_nulls(phone, email, city) FROM users;
SELECT num_nonnulls(phone, email, city) FROM users;

-- Conditional in WHERE
SELECT * FROM users WHERE COALESCE(status, 0) = 1;

-- Conditional in ORDER BY
SELECT * FROM users ORDER BY
    CASE WHEN status = 1 THEN 0 ELSE 1 END,
    username;

-- Note: Same conditional functions as PostgreSQL
-- Note: :: casting syntax supported
-- Note: IS DISTINCT FROM for NULL-safe comparisons
-- Note: No IF() or IFNULL() (use CASE/COALESCE)
-- Note: No TRY_CAST or SAFE_CAST (use conditional logic)
-- Note: Based on PostgreSQL 11.2 conditional function set
