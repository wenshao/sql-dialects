-- IBM Db2: Pagination
--
-- 参考资料:
--   [1] Db2 SQL Reference
--       https://www.ibm.com/docs/en/db2/11.5?topic=sql
--   [2] Db2 Built-in Functions
--       https://www.ibm.com/docs/en/db2/11.5?topic=functions-built-in

-- FETCH FIRST N ROWS ONLY (Db2's original syntax, predates SQL standard)
SELECT * FROM users ORDER BY id FETCH FIRST 10 ROWS ONLY;

-- SQL standard: OFFSET + FETCH (Db2 11.1+)
SELECT * FROM users ORDER BY id OFFSET 20 ROWS FETCH FIRST 10 ROWS ONLY;

-- FETCH NEXT (synonym)
SELECT * FROM users ORDER BY id OFFSET 20 ROWS FETCH NEXT 10 ROWS ONLY;

-- FETCH FIRST with PERCENT
SELECT * FROM users ORDER BY age DESC FETCH FIRST 10 PERCENT ROWS ONLY;

-- FETCH with ties (include tied rows)
SELECT * FROM users ORDER BY age FETCH FIRST 10 ROWS WITH TIES;

-- Window function for pagination
SELECT * FROM (
    SELECT u.*, ROW_NUMBER() OVER (ORDER BY id) AS rn
    FROM users u
) t
WHERE rn BETWEEN 21 AND 30;

-- Top-N per group
SELECT * FROM (
    SELECT username, city, age,
        ROW_NUMBER() OVER (PARTITION BY city ORDER BY age DESC) AS rn
    FROM users
) t WHERE rn <= 3;

-- Keyset pagination (cursor-based)
SELECT * FROM users WHERE id > 100 ORDER BY id FETCH FIRST 10 ROWS ONLY;

-- OPTIMIZE FOR N ROWS (hint for cursor-based access)
SELECT * FROM users ORDER BY id
FETCH FIRST 10 ROWS ONLY
OPTIMIZE FOR 10 ROWS;

-- Scrollable cursor (in stored procedure)
-- DECLARE cur SCROLL CURSOR FOR SELECT * FROM users ORDER BY id;
-- FETCH ABSOLUTE 21 FROM cur;

-- Note: FETCH FIRST N ROWS ONLY was Db2's syntax before SQL standard adopted it
-- Note: Db2 does not support LIMIT/OFFSET syntax
-- Note: OPTIMIZE FOR helps optimizer for pagination queries
