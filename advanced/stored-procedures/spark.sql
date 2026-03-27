-- Spark SQL: Stored Procedures and Functions
--
-- 参考资料:
--   [1] Spark SQL Reference
--       https://spark.apache.org/docs/latest/sql-ref.html
--   [2] Spark SQL - Built-in Functions
--       https://spark.apache.org/docs/latest/sql-ref-functions.html
--   [3] Spark SQL - Data Types
--       https://spark.apache.org/docs/latest/sql-ref-datatypes.html

-- Spark SQL does NOT support traditional stored procedures
-- Instead, it provides these alternatives:

-- 1. Temporary functions (SQL UDFs, Spark 3.0+)
CREATE TEMPORARY FUNCTION classify_age AS
    'com.example.ClassifyAge'                           -- Java/Scala class
    USING JAR '/path/to/udf.jar';

-- 2. SQL-based temporary functions (Spark 3.4+)
CREATE TEMPORARY FUNCTION add_numbers(a INT, b INT)
    RETURNS INT
    RETURN a + b;

SELECT add_numbers(3, 5);                              -- 8

-- SQL function with CASE
CREATE TEMPORARY FUNCTION classify_age(age INT)
    RETURNS STRING
    RETURN CASE
        WHEN age < 18 THEN 'minor'
        WHEN age < 65 THEN 'adult'
        ELSE 'senior'
    END;

SELECT classify_age(25);                               -- 'adult'

-- SQL table-valued function (Spark 3.4+)
CREATE TEMPORARY FUNCTION active_users(min_age INT)
    RETURNS TABLE (id BIGINT, username STRING, age INT)
    RETURN SELECT id, username, age FROM users WHERE status = 1 AND age >= min_age;

SELECT * FROM active_users(25);

-- 3. Permanent functions (stored in Hive metastore)
CREATE FUNCTION mydb.classify_age AS
    'com.example.ClassifyAge'
    USING JAR '/path/to/udf.jar';

-- 4. Python UDFs (registered via PySpark API)
-- In Python:
-- from pyspark.sql.functions import udf
-- @udf(returnType=StringType())
-- def classify(age):
--     if age < 18: return 'minor'
--     elif age < 65: return 'adult'
--     else: return 'senior'
-- spark.udf.register('classify_age', classify)
-- Then in SQL: SELECT classify_age(age) FROM users;

-- 5. Pandas UDFs (vectorized, much faster than row-by-row)
-- In Python:
-- from pyspark.sql.functions import pandas_udf
-- @pandas_udf(DoubleType())
-- def multiply(a: pd.Series, b: pd.Series) -> pd.Series:
--     return a * b
-- spark.udf.register('multiply', multiply)

-- 6. Drop function
DROP TEMPORARY FUNCTION IF EXISTS classify_age;
DROP FUNCTION IF EXISTS mydb.classify_age;

-- 7. Show functions
SHOW FUNCTIONS;
SHOW USER FUNCTIONS;
SHOW SYSTEM FUNCTIONS;
DESCRIBE FUNCTION classify_age;
DESCRIBE FUNCTION EXTENDED classify_age;

-- 8. TRANSFORM (run external script, Hive-compatible)
SELECT TRANSFORM(username, age)
    USING 'python3 /path/to/script.py'
    AS (processed_name STRING, processed_age INT)
FROM users;

-- 9. Views as "stored queries" (workaround for stored procedures)
CREATE OR REPLACE VIEW vip_users AS
SELECT u.*, SUM(o.amount) AS total_spent
FROM users u
JOIN orders o ON u.id = o.user_id
GROUP BY u.id, u.username, u.email, u.age
HAVING SUM(o.amount) > 10000;

-- 10. Delta Lake stored procedures (Databricks-specific)
-- CALL delta.vacuum('users');
-- CALL delta.optimize('users');

-- Note: No CREATE PROCEDURE or CALL statement in standard Spark SQL
-- Note: UDFs can be written in Java, Scala, or Python
-- Note: SQL UDFs (RETURN syntax) added in Spark 3.4+
-- Note: Pandas UDFs are significantly faster than regular Python UDFs
-- Note: TRANSFORM allows using any scripting language for row processing
-- Note: Complex multi-step logic is typically done in PySpark/Scala code
-- Note: Views serve as reusable query definitions (similar to simple procedures)
