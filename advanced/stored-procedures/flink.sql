-- Flink SQL: Stored Procedures and Functions
--
-- 参考资料:
--   [1] Flink SQL Documentation
--       https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/sql/overview/
--   [2] Flink SQL - Built-in Functions
--       https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/functions/systemfunctions/
--   [3] Flink SQL - Data Types
--       https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/types/

-- Flink SQL does NOT support stored procedures
-- Instead, it provides User-Defined Functions (UDFs)

-- 1. Temporary system functions (from Java/Scala/Python UDFs)
-- First implement a UDF class in Java:
-- public class ClassifyAge extends ScalarFunction {
--     public String eval(int age) {
--         if (age < 18) return "minor";
--         else if (age < 65) return "adult";
--         else return "senior";
--     }
-- }

-- Register in SQL client or via Table API:
CREATE TEMPORARY FUNCTION classify_age AS 'com.example.ClassifyAge';
SELECT classify_age(age) FROM users;

-- 2. Temporary system function with LANGUAGE JAVA
CREATE TEMPORARY FUNCTION classify_age AS 'com.example.ClassifyAge'
    LANGUAGE JAVA;

-- 3. Temporary system function with Python (PyFlink)
-- CREATE TEMPORARY FUNCTION classify_age AS 'classify_age'
--     LANGUAGE PYTHON;

-- 4. Catalog functions (persistent, stored in catalog)
CREATE FUNCTION mydb.classify_age AS 'com.example.ClassifyAge';

-- 5. Drop function
DROP TEMPORARY FUNCTION IF EXISTS classify_age;
DROP FUNCTION IF EXISTS mydb.classify_age;

-- 6. Types of UDFs in Flink

-- Scalar Function: one row in, one value out
-- public class MyHash extends ScalarFunction {
--     public int eval(String s) { return s.hashCode(); }
-- }
CREATE TEMPORARY FUNCTION my_hash AS 'com.example.MyHash';
SELECT my_hash(username) FROM users;

-- Table Function: one row in, zero or more rows out
-- public class SplitFunction extends TableFunction<Row> {
--     public void eval(String str) {
--         for (String s : str.split(",")) { collect(Row.of(s)); }
--     }
-- }
CREATE TEMPORARY FUNCTION split_to_rows AS 'com.example.SplitFunction';
SELECT user_id, tag
FROM events, LATERAL TABLE(split_to_rows(tags)) AS t(tag);

-- Aggregate Function: many rows in, one value out
-- public class WeightedAvg extends AggregateFunction<Long, WeightedAvgAccum> {
--     // implementation
-- }
CREATE TEMPORARY FUNCTION weighted_avg AS 'com.example.WeightedAvg';
SELECT city, weighted_avg(age, weight) FROM users GROUP BY city;

-- Table Aggregate Function: many rows in, many rows out
-- public class Top2 extends TableAggregateFunction<Tuple2<Integer, Integer>, Top2Accum> {
--     // implementation
-- }

-- Async Table Function (Flink 1.16+): for async I/O in lookup joins
-- public class AsyncLookup extends AsyncTableFunction<Row> {
--     // async lookup implementation
-- }

-- 7. Built-in functions overview
SHOW FUNCTIONS;
SHOW USER FUNCTIONS;

-- 8. Views as reusable queries
CREATE VIEW active_users AS
SELECT * FROM users WHERE status = 1;

CREATE TEMPORARY VIEW tmp_results AS
SELECT user_id, COUNT(*) AS cnt
FROM events
GROUP BY user_id;

-- 9. STATEMENT SET for complex pipelines (alternative to procedures)
BEGIN STATEMENT SET;
INSERT INTO output_1 SELECT * FROM events WHERE type = 'A';
INSERT INTO output_2 SELECT * FROM events WHERE type = 'B';
INSERT INTO output_3
    SELECT user_id, COUNT(*) FROM events GROUP BY user_id;
END;

-- Note: No CREATE PROCEDURE or CALL statement
-- Note: UDFs must be implemented in Java, Scala, or Python
-- Note: Scalar, Table, Aggregate, and Table Aggregate function types
-- Note: UDF JARs must be available on the Flink cluster classpath
-- Note: Catalog functions persist across sessions; temporary functions do not
-- Note: No SQL-based function bodies (RETURN syntax); logic is in Java/Scala/Python
-- Note: STATEMENT SET groups multiple INSERT statements into one streaming job
-- Note: For complex pipelines, use Flink's DataStream/Table API
