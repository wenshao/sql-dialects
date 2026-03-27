-- DuckDB: Stored Procedures and Functions
--
-- 参考资料:
--   [1] DuckDB - SQL Reference
--       https://duckdb.org/docs/sql/introduction
--   [2] DuckDB - Functions
--       https://duckdb.org/docs/sql/functions/overview
--   [3] DuckDB - Data Types
--       https://duckdb.org/docs/sql/data_types/overview

-- DuckDB does NOT support stored procedures or user-defined PL/pgSQL functions
-- Instead, it provides these alternatives:

-- 1. Macros (scalar, v0.8+)
-- Macros are like inline functions defined with CREATE MACRO
CREATE MACRO add(a, b) AS a + b;
SELECT add(3, 5);                                      -- 8

-- Macro with default parameters
CREATE MACRO greet(name, greeting := 'Hello') AS greeting || ' ' || name;
SELECT greet('Alice');                                  -- 'Hello Alice'
SELECT greet('Alice', 'Hi');                            -- 'Hi Alice'

-- Macro with CASE expression
CREATE MACRO classify_age(age) AS
    CASE
        WHEN age < 18 THEN 'minor'
        WHEN age < 65 THEN 'adult'
        ELSE 'senior'
    END;
SELECT classify_age(25);                               -- 'adult'

-- 2. Table macros (return tables, v0.9+)
CREATE MACRO active_users(min_age) AS TABLE
    SELECT * FROM users WHERE status = 1 AND age >= min_age;
SELECT * FROM active_users(25);

-- Table macro with multiple parameters
CREATE MACRO user_orders(uid, min_amount := 0) AS TABLE
    SELECT u.username, o.amount
    FROM users u
    JOIN orders o ON u.id = o.user_id
    WHERE u.id = uid AND o.amount >= min_amount;
SELECT * FROM user_orders(1, 100);

-- 3. CREATE OR REPLACE MACRO
CREATE OR REPLACE MACRO add(a, b) AS a + b;

-- 4. Drop macro
DROP MACRO add;
DROP MACRO IF EXISTS add;
DROP MACRO active_users;

-- 5. Parameterized queries with PREPARE / EXECUTE
PREPARE get_user AS SELECT * FROM users WHERE id = $1;
EXECUTE get_user(42);

PREPARE insert_user AS
    INSERT INTO users (username, email) VALUES ($1, $2);
EXECUTE insert_user('alice', 'alice@example.com');

-- Deallocate prepared statement
DEALLOCATE get_user;

-- 6. Script-like patterns using CTEs
-- Instead of procedures with logic, chain CTEs:
WITH
step1 AS (
    SELECT user_id, SUM(amount) AS total FROM orders GROUP BY user_id
),
step2 AS (
    SELECT u.*, s.total
    FROM users u JOIN step1 s ON u.id = s.user_id
    WHERE s.total > 1000
)
SELECT * FROM step2;

-- 7. Python UDFs (via DuckDB Python API, not SQL)
-- In Python:
-- import duckdb
-- def my_function(x): return x * 2
-- duckdb.create_function('double_it', my_function, [int], int)
-- duckdb.sql("SELECT double_it(21)")  -- 42

-- 8. Extensions for additional functionality
-- DuckDB extensions can add new functions:
-- INSTALL httpfs; LOAD httpfs;   -- HTTP/S3 file access
-- INSTALL spatial; LOAD spatial; -- Spatial functions

-- Note: CREATE FUNCTION is an alias for CREATE MACRO (v0.9+); no CREATE PROCEDURE
-- Note: Macros are expanded inline (no function call overhead)
-- Note: Table macros return result sets (like table-valued functions)
-- Note: For complex logic, use the host language (Python, Java, etc.)
-- Note: PREPARE/EXECUTE provides parameterized queries (not stored procedures)
-- Note: No PL/pgSQL, no procedural language support
-- Note: No CALL statement (no procedures to call)
