-- MariaDB: JSON Type
-- MariaDB is a MySQL fork; only differences from MySQL are shown here.
--
-- 参考资料:
--   [1] MariaDB Knowledge Base
--       https://mariadb.com/kb/en/documentation/
--   [2] MariaDB vs MySQL Compatibility
--       https://mariadb.com/kb/en/mariadb-vs-mysql-compatibility/

-- JSON "type": MariaDB stores JSON as LONGTEXT (not a binary format!)
-- MySQL stores JSON in an internal binary format for faster access
-- MariaDB validates JSON on insert but stores as text
CREATE TABLE events (
    id   BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
    data JSON  -- alias for LONGTEXT with JSON validation (10.2.7+)
);

-- JSON validation on insert (same behavior as MySQL)
INSERT INTO events (data) VALUES ('{"name": "alice", "age": 25, "tags": ["vip", "new"]}');
INSERT INTO events (data) VALUES (JSON_OBJECT('name', 'bob', 'age', 30));
INSERT INTO events (data) VALUES (JSON_ARRAY(1, 2, 3));

-- Read JSON fields
-- -> and ->> operators supported (10.2.3+)
SELECT data->'$.name' FROM events;            -- returns JSON: "alice"
SELECT data->>'$.name' FROM events;           -- returns text: alice (10.2.3+)
-- Note: -> in MariaDB is alias for JSON_EXTRACT (same as MySQL)
-- ->> in MariaDB is alias for JSON_UNQUOTE(JSON_EXTRACT()) (same as MySQL)

SELECT JSON_EXTRACT(data, '$.name') FROM events;
SELECT JSON_UNQUOTE(JSON_EXTRACT(data, '$.name')) FROM events;

-- Nested access
SELECT data->'$.tags[0]' FROM events;
SELECT data->>'$.address.city' FROM events;

-- Query conditions (same as MySQL)
SELECT * FROM events WHERE data->>'$.name' = 'alice';
SELECT * FROM events WHERE JSON_CONTAINS(data, '"vip"', '$.tags');
SELECT * FROM events WHERE JSON_CONTAINS_PATH(data, 'one', '$.name', '$.email');

-- Modify JSON (same as MySQL)
SELECT JSON_SET(data, '$.age', 26) FROM events;
SELECT JSON_INSERT(data, '$.email', 'a@e.com') FROM events;
SELECT JSON_REPLACE(data, '$.age', 26) FROM events;
SELECT JSON_REMOVE(data, '$.tags') FROM events;

-- JSON functions (same as MySQL)
SELECT JSON_TYPE(data->'$.name') FROM events;
SELECT JSON_VALID('{"a":1}');
SELECT JSON_KEYS(data) FROM events;
SELECT JSON_LENGTH(data->'$.tags') FROM events;

-- JSON aggregation (10.5+)
SELECT JSON_ARRAYAGG(username) FROM users;
SELECT JSON_OBJECTAGG(username, age) FROM users;
-- Note: JSON_ARRAYAGG/JSON_OBJECTAGG available later than MySQL (MySQL 5.7.22+)

-- JSON_TABLE: supported in 10.6+
-- Available later than MySQL 8.0
SELECT * FROM events,
JSON_TABLE(data, '$' COLUMNS (
    name VARCHAR(64) PATH '$.name',
    age INT PATH '$.age'
)) AS jt;

-- JSON_OVERLAPS (10.9+): check if two JSON documents share any values
SELECT * FROM events WHERE JSON_OVERLAPS(data->'$.tags', '["vip", "premium"]');

-- JSON utility functions
SELECT JSON_DETAILED(data) FROM events;       -- MariaDB-specific: pretty-print JSON
SELECT JSON_LOOSE(data) FROM events;          -- MariaDB-specific: format with spaces
SELECT JSON_COMPACT(data) FROM events;        -- MariaDB-specific: minified JSON

-- JSON_EQUALS (10.7+, MariaDB-specific): compare JSON values semantically
SELECT * FROM events WHERE JSON_EQUALS(data, '{"age": 25, "name": "alice"}');
-- Order-insensitive comparison for objects

-- Indexing JSON: use virtual/persistent generated columns
ALTER TABLE events ADD COLUMN name_val VARCHAR(64) AS (data->>'$.name') PERSISTENT;
CREATE INDEX idx_name ON events (name_val);
-- No multi-valued index support (MySQL 8.0.17+ ARRAY index not available)

-- Differences from MySQL 8.0:
-- JSON stored as LONGTEXT (text format), not binary format
--   Consequence: slower random access to nested fields on large documents
-- JSON_TABLE available from 10.6+ (MySQL from 8.0)
-- JSON_ARRAYAGG/OBJECTAGG from 10.5+ (MySQL from 5.7.22+)
-- MariaDB-specific: JSON_DETAILED, JSON_LOOSE, JSON_COMPACT, JSON_EQUALS
-- No multi-valued index (CAST ... AS ... ARRAY) support
-- No MEMBER OF operator
-- Virtual column + index is the recommended approach for JSON indexing
