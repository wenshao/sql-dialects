-- IBM Db2: INSERT
--
-- 参考资料:
--   [1] Db2 SQL Reference
--       https://www.ibm.com/docs/en/db2/11.5?topic=sql
--   [2] Db2 Built-in Functions
--       https://www.ibm.com/docs/en/db2/11.5?topic=functions-built-in

-- Single row insert
INSERT INTO users (username, email, age) VALUES ('alice', 'alice@example.com', 25);

-- Multiple rows
INSERT INTO users (username, email, age) VALUES
    ('alice', 'alice@example.com', 25),
    ('bob', 'bob@example.com', 30),
    ('charlie', 'charlie@example.com', 35);

-- Insert from query
INSERT INTO users_archive (username, email, age)
SELECT username, email, age FROM users WHERE age > 60;

-- RETURNING (Db2 11.1+: SELECT FROM final table)
SELECT * FROM FINAL TABLE (
    INSERT INTO users (username, email, age)
    VALUES ('alice', 'alice@example.com', 25)
);

-- Get generated identity value
SELECT id FROM FINAL TABLE (
    INSERT INTO users (username, email, age)
    VALUES ('alice', 'alice@example.com', 25)
);

-- Also: IDENTITY_VAL_LOCAL() after insert
INSERT INTO users (username, email, age) VALUES ('alice', 'alice@example.com', 25);
VALUES IDENTITY_VAL_LOCAL();

-- Default values
INSERT INTO users (username, email, age) VALUES ('alice', 'alice@example.com', DEFAULT);

-- Override identity column
INSERT INTO users (id, username, email)
OVERRIDING SYSTEM VALUE
VALUES (100, 'alice', 'alice@example.com');

-- CTE + INSERT
WITH new_users AS (
    SELECT 'alice' AS username, 'alice@example.com' AS email
    FROM SYSIBM.SYSDUMMY1
)
INSERT INTO users (username, email)
SELECT username, email FROM new_users;

-- INSERT with isolation
INSERT INTO users (username, email, age)
VALUES ('alice', 'alice@example.com', 25)
WITH UR;  -- uncommitted read

-- Bulk operations
-- IMPORT FROM file.csv OF DEL INSERT INTO users;
-- LOAD FROM file.csv OF DEL INSERT INTO users;
-- Note: LOAD is faster but requires more privileges

-- MERGE used for conditional insert (see upsert)
