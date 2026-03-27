-- Spark SQL: Pagination (Spark 2.0+)
--
-- 参考资料:
--   [1] Spark SQL Reference
--       https://spark.apache.org/docs/latest/sql-ref.html
--   [2] Spark SQL - Built-in Functions
--       https://spark.apache.org/docs/latest/sql-ref-functions.html
--   [3] Spark SQL - Data Types
--       https://spark.apache.org/docs/latest/sql-ref-datatypes.html

-- LIMIT (basic)
SELECT * FROM users ORDER BY id LIMIT 10;

-- LIMIT with OFFSET (Spark 3.4+)
SELECT * FROM users ORDER BY id LIMIT 10 OFFSET 20;

-- SQL standard syntax (Spark 3.4+)
SELECT * FROM users ORDER BY id OFFSET 20 ROWS FETCH FIRST 10 ROWS ONLY;

-- Window function pagination (works in all Spark versions)
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (ORDER BY id) AS rn
    FROM users
) t
WHERE rn BETWEEN 21 AND 30;

-- Keyset / cursor pagination (efficient for large offsets)
SELECT * FROM users WHERE id > 100 ORDER BY id LIMIT 10;

-- Top-N per partition
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY city ORDER BY age DESC) AS rn
    FROM users
) t
WHERE rn <= 5;

-- Distributed pagination with DISTRIBUTE BY (for parallelism)
-- Each partition gets its own row numbering:
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (ORDER BY id) AS rn
    FROM users
) t
WHERE rn <= 100;

-- TABLESAMPLE (random sampling, not pagination)
SELECT * FROM users TABLESAMPLE (10 PERCENT);
SELECT * FROM users TABLESAMPLE (100 ROWS);
SELECT * FROM users TABLESAMPLE (BUCKET 1 OUT OF 10 ON id);

-- Note: OFFSET was added in Spark 3.4+; before that, use window functions
-- Note: LIMIT without ORDER BY returns arbitrary rows (non-deterministic)
-- Note: Large OFFSET values are inefficient; use keyset pagination for big data
-- Note: Spark collects LIMIT results to the driver; very large limits may cause OOM
-- Note: TABLESAMPLE is for statistical sampling, not deterministic pagination
