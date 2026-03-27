-- Spark SQL: JSON Type (Spark 2.0+)
--
-- 参考资料:
--   [1] Spark SQL Reference
--       https://spark.apache.org/docs/latest/sql-ref.html
--   [2] Spark SQL - Built-in Functions
--       https://spark.apache.org/docs/latest/sql-ref-functions.html
--   [3] Spark SQL - Data Types
--       https://spark.apache.org/docs/latest/sql-ref-datatypes.html

-- Spark has no native JSON column type
-- JSON is stored as STRING and processed with built-in functions

CREATE TABLE events (
    id   BIGINT,
    data STRING                        -- JSON stored as STRING
) USING PARQUET;

-- Insert JSON
INSERT INTO events VALUES (1, '{"name": "alice", "age": 25, "tags": ["vip", "new"]}');

-- Extract JSON fields
SELECT GET_JSON_OBJECT(data, '$.name') FROM events;        -- alice (STRING)
SELECT GET_JSON_OBJECT(data, '$.age') FROM events;         -- 25 (STRING)
SELECT GET_JSON_OBJECT(data, '$.tags[0]') FROM events;     -- vip (STRING)
SELECT GET_JSON_OBJECT(data, '$.tags') FROM events;        -- ["vip","new"] (STRING)

-- JSON_TUPLE (extract multiple fields at once, efficient)
SELECT id, j.name, j.age
FROM events
LATERAL VIEW JSON_TUPLE(data, 'name', 'age') j AS name, age;

-- FROM_JSON (parse JSON string into STRUCT, Spark 2.1+)
SELECT FROM_JSON(data, 'STRUCT<name: STRING, age: INT, tags: ARRAY<STRING>>') AS parsed
FROM events;

-- FROM_JSON with schema inference
SELECT FROM_JSON(data, schema_of_json('{"name":"","age":0,"tags":[""]}')) AS parsed
FROM events;

-- Access parsed struct fields
SELECT parsed.name, parsed.age, parsed.tags
FROM (
    SELECT FROM_JSON(data, 'STRUCT<name: STRING, age: INT, tags: ARRAY<STRING>>') AS parsed
    FROM events
);

-- TO_JSON (struct/map/array to JSON string)
SELECT TO_JSON(STRUCT('alice' AS name, 25 AS age));
SELECT TO_JSON(MAP('key1', 'value1', 'key2', 'value2'));
SELECT TO_JSON(ARRAY('a', 'b', 'c'));

-- JSON_OBJECT (Spark 3.5+)
SELECT JSON_OBJECT('name', 'alice', 'age', 25);

-- JSON_ARRAY (Spark 3.5+)
SELECT JSON_ARRAY('a', 'b', 'c');

-- SCHEMA_OF_JSON (infer schema from JSON string, Spark 2.4+)
SELECT SCHEMA_OF_JSON('{"name": "alice", "age": 25}');
-- Returns: STRUCT<age: BIGINT, name: STRING>

-- JSON in WHERE clause
SELECT * FROM events WHERE GET_JSON_OBJECT(data, '$.name') = 'alice';
SELECT * FROM events WHERE CAST(GET_JSON_OBJECT(data, '$.age') AS INT) > 20;

-- Explode JSON arrays
SELECT id, tag
FROM events
LATERAL VIEW EXPLODE(
    FROM_JSON(GET_JSON_OBJECT(data, '$.tags'), 'ARRAY<STRING>')
) t AS tag;

-- JSON aggregation
SELECT TO_JSON(COLLECT_LIST(username)) FROM users;
SELECT TO_JSON(MAP_FROM_ENTRIES(COLLECT_LIST(STRUCT(username, age)))) FROM users;

-- Read JSON files
-- CREATE TABLE json_data USING JSON OPTIONS (path '/data/events.json');
-- SELECT * FROM json_data;

-- Read JSON with explicit schema
-- CREATE TABLE json_data (name STRING, age INT, tags ARRAY<STRING>)
-- USING JSON OPTIONS (path '/data/events.json', multiLine 'true');

-- Complex nested JSON handling
SELECT
    GET_JSON_OBJECT(data, '$.address.city') AS city,
    GET_JSON_OBJECT(data, '$.address.zip') AS zip
FROM events;

-- Parse nested JSON with FROM_JSON
SELECT parsed.*
FROM (
    SELECT FROM_JSON(data,
        'STRUCT<name: STRING, age: INT, address: STRUCT<city: STRING, zip: STRING>>'
    ) AS parsed
    FROM events
);

-- Note: Spark stores JSON as STRING; there is no dedicated JSON column type
-- Note: GET_JSON_OBJECT always returns STRING; cast for other types
-- Note: FROM_JSON is more powerful but requires schema specification
-- Note: JSON_TUPLE with LATERAL VIEW is efficient for extracting multiple fields
-- Note: Spark can read JSON files directly with automatic schema inference
-- Note: No JSON path operators (-> / ->>); use GET_JSON_OBJECT function
-- Note: For nested/complex JSON, FROM_JSON with STRUCT types is recommended
