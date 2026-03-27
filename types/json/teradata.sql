-- Teradata: JSON Type (15.10+)
--
-- 参考资料:
--   [1] Teradata SQL Reference
--       https://docs.teradata.com/r/Teradata-VantageTM-SQL-Functions-Expressions-and-Predicates
--   [2] Teradata Database Documentation
--       https://docs.teradata.com/

-- JSON column (stored as CLOB internally)
CREATE TABLE events (
    id   INTEGER NOT NULL,
    data JSON(1000)                   -- max storage size in characters
)
PRIMARY INDEX (id);

-- JSON with larger storage
CREATE TABLE documents (
    id   INTEGER NOT NULL,
    data JSON(32000),
    meta JSON(1000)
)
PRIMARY INDEX (id);

-- Insert JSON
INSERT INTO events (id, data) VALUES (1, '{"name": "alice", "age": 25, "tags": ["vip", "new"]}');

-- NEW JSON (construct JSON)
INSERT INTO events (id, data) VALUES (2, NEW JSON('{"name": "bob", "age": 30}'));

-- Read JSON fields using JSONExtract functions
SELECT data.JSONExtractValue('$.name') FROM events;              -- returns string: alice
SELECT data.JSONExtractValue('$.age') FROM events;               -- returns string: 25
SELECT data.JSONExtractLargeValue('$.tags') FROM events;         -- returns JSON array

-- JSONExtract with type cast
SELECT CAST(data.JSONExtractValue('$.age') AS INTEGER) FROM events;

-- Query conditions on JSON
SELECT * FROM events WHERE data.JSONExtractValue('$.name') = 'alice';
SELECT * FROM events WHERE CAST(data.JSONExtractValue('$.age') AS INTEGER) > 20;

-- JSON_TABLE (16.20+: shred JSON into relational columns)
SELECT jt.*
FROM events,
JSON_TABLE(data, '$'
    COLUMNS (
        name VARCHAR(100) PATH '$.name',
        age  INTEGER      PATH '$.age'
    )
) AS jt;

-- JSON_COMPOSE (build JSON from relational data)
SELECT JSON_COMPOSE(username, email, age) FROM users;

-- JSON_COMPOSE with nesting
SELECT JSON_COMPOSE(
    username AS "name",
    JSON_COMPOSE(city AS "city", country AS "country") AS "address"
) FROM users;

-- JSONExtractValue for nested paths
SELECT data.JSONExtractValue('$.address.city') FROM events;
SELECT data.JSONExtractValue('$.tags[0]') FROM events;

-- Check if valid JSON
SELECT data.JSONExtractValue('$') IS NOT NULL FROM events;

-- Note: JSON type is stored as CLOB with JSON validation
-- Note: JSON size must be specified (no default)
-- Note: JSONExtractValue returns VARCHAR(32000) by default
-- Note: JSON_TABLE available in Teradata 16.20+
-- Note: no native JSON modification functions; rebuild entire JSON
