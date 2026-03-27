-- Google Cloud Spanner: JSON Type (GoogleSQL)
--
-- 参考资料:
--   [1] Spanner SQL Reference (GoogleSQL)
--       https://cloud.google.com/spanner/docs/reference/standard-sql/query-syntax
--   [2] Spanner - Functions
--       https://cloud.google.com/spanner/docs/reference/standard-sql/functions-and-operators
--   [3] Spanner - Data Types
--       https://cloud.google.com/spanner/docs/reference/standard-sql/data-types

-- JSON: native JSON type
-- Spanner also has STRUCT and ARRAY as native complex types

CREATE TABLE Events (
    EventId INT64 NOT NULL,
    Data    JSON
) PRIMARY KEY (EventId);

-- Insert JSON
INSERT INTO Events (EventId, Data)
VALUES (1, JSON '{"name": "alice", "age": 25, "tags": ["vip"]}');
INSERT INTO Events (EventId, Data)
VALUES (2, JSON_OBJECT('name', 'bob', 'age', 30));

-- Access JSON fields
SELECT Data.name FROM Events;                  -- dot notation (returns JSON)
SELECT Data.tags[0] FROM Events;               -- array access
SELECT JSON_VALUE(Data, '$.name') FROM Events;  -- returns STRING scalar
SELECT JSON_QUERY(Data, '$.tags') FROM Events;   -- returns JSON array/object

-- JSON_VALUE vs JSON_QUERY:
-- JSON_VALUE: extracts scalar, returns STRING
-- JSON_QUERY: extracts array/object, returns JSON

-- Type conversion from JSON
SELECT INT64(Data.age) FROM Events;            -- convert to INT64
SELECT FLOAT64(Data.price) FROM Events;        -- convert to FLOAT64
SELECT BOOL(Data.active) FROM Events;          -- convert to BOOL
SELECT STRING(Data.name) FROM Events;          -- convert to STRING
SELECT JSON_VALUE(Data, '$.age' RETURNING INT64) FROM Events;  -- inline conversion

-- Query conditions
SELECT * FROM Events WHERE JSON_VALUE(Data, '$.name') = 'alice';
SELECT * FROM Events WHERE INT64(Data.age) > 20;

-- JSON construction
SELECT JSON_OBJECT('name', 'alice', 'age', 25);
SELECT JSON_ARRAY(1, 2, 3);
SELECT TO_JSON(STRUCT('alice' AS name, 25 AS age));

-- JSON modification
SELECT JSON_SET(Data, '$.city', 'New York') FROM Events;
SELECT JSON_SET(Data, '$.premium', true) FROM Events;
SELECT JSON_REMOVE(Data, '$.temporary') FROM Events;
SELECT JSON_STRIP_NULLS(Data) FROM Events;

-- JSON expansion
SELECT key, value
FROM Events, UNNEST(JSON_KEYS(Data)) AS key;
SELECT tag
FROM Events, UNNEST(JSON_QUERY_ARRAY(Data, '$.tags')) AS tag;

-- JSON array length
SELECT ARRAY_LENGTH(JSON_QUERY_ARRAY(Data, '$.tags')) FROM Events;

-- JSON type checking
SELECT JSON_TYPE(Data) FROM Events;            -- object, array, string, number, etc.
SELECT JSON_TYPE(Data.name) FROM Events;       -- string

-- STRUCT (native structured type, often preferred over JSON)
CREATE TABLE Users (
    UserId  INT64 NOT NULL,
    Name    STRING(100),
    Address STRUCT<Street STRING(200), City STRING(100), Zip STRING(10)>
) PRIMARY KEY (UserId);
SELECT Address.City FROM Users;

-- ARRAY (native array type)
CREATE TABLE Profiles (
    UserId INT64 NOT NULL,
    Tags   ARRAY<STRING(50)>
) PRIMARY KEY (UserId);
SELECT tag FROM Profiles, UNNEST(Tags) AS tag;

-- Note: JSON type supported natively
-- Note: Dot notation for JSON access (Data.field)
-- Note: JSON_VALUE for scalars, JSON_QUERY for arrays/objects
-- Note: Spanner recommends STRUCT/ARRAY over JSON for structured data
-- Note: No JSONB (binary JSON); JSON is the only variant
-- Note: JSON columns cannot be used in primary keys or indexes directly
-- Note: Use JSON_VALUE in index expressions for indexed JSON queries
