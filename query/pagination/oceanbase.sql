-- OceanBase: Pagination
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

-- LIMIT / OFFSET
SELECT * FROM users ORDER BY id LIMIT 10 OFFSET 20;

-- Shorthand form
SELECT * FROM users ORDER BY id LIMIT 20, 10;

-- Window function pagination
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (ORDER BY id) AS rn
    FROM users
) t
WHERE rn BETWEEN 21 AND 30;

-- Cursor-based pagination (recommended)
SELECT * FROM users WHERE id > 100 ORDER BY id LIMIT 10;

-- ============================================================
-- Oracle Mode
-- ============================================================

-- ROWNUM (classic Oracle pagination)
-- Page 3 (rows 21-30):
SELECT * FROM (
    SELECT u.*, ROWNUM AS rn
    FROM (SELECT * FROM users ORDER BY id) u
    WHERE ROWNUM <= 30
)
WHERE rn > 20;

-- FETCH FIRST (Oracle 12c+ syntax, supported in OceanBase 4.0+)
SELECT * FROM users ORDER BY id
FETCH FIRST 10 ROWS ONLY;

-- OFFSET ... FETCH (Oracle 12c+ syntax)
SELECT * FROM users ORDER BY id
OFFSET 20 ROWS FETCH NEXT 10 ROWS ONLY;

-- FETCH with PERCENT
SELECT * FROM users ORDER BY age DESC
FETCH FIRST 10 PERCENT ROWS ONLY;

-- FETCH with TIES (include ties at boundary)
SELECT * FROM users ORDER BY age DESC
FETCH FIRST 10 ROWS WITH TIES;

-- ROW_NUMBER pagination (Oracle mode)
SELECT * FROM (
    SELECT u.*, ROW_NUMBER() OVER (ORDER BY id) AS rn
    FROM users u
)
WHERE rn BETWEEN 21 AND 30;

-- Cursor-based pagination (Oracle mode)
SELECT * FROM users WHERE id > 100 ORDER BY id
FETCH FIRST 10 ROWS ONLY;

-- Parallel pagination hint
SELECT /*+ PARALLEL(4) */ * FROM users ORDER BY id
OFFSET 20 ROWS FETCH NEXT 10 ROWS ONLY;

-- Limitations:
-- MySQL mode: same as MySQL (LIMIT/OFFSET)
-- Oracle mode: ROWNUM, FETCH FIRST, OFFSET FETCH supported
-- Large OFFSET performance degrades in both modes
-- Cursor-based pagination recommended for large datasets
