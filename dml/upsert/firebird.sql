-- Firebird: UPSERT
--
-- 参考资料:
--   [1] Firebird SQL Reference
--       https://firebirdsql.org/en/reference-manuals/
--   [2] Firebird Release Notes
--       https://firebirdsql.org/file/documentation/release_notes/html/en/4_0/rlsnotes40.html

-- UPDATE OR INSERT (2.1+, Firebird's native upsert)
-- Matches on MATCHING columns (or PK/UNIQUE if omitted)
UPDATE OR INSERT INTO users (id, username, email, age)
VALUES (1, 'alice', 'alice@example.com', 26)
MATCHING (id);

-- UPDATE OR INSERT matching on other columns
UPDATE OR INSERT INTO users (username, email, age)
VALUES ('alice', 'alice@example.com', 26)
MATCHING (username);

-- UPDATE OR INSERT with RETURNING (2.1+)
UPDATE OR INSERT INTO users (id, username, email, age)
VALUES (1, 'alice', 'alice@example.com', 26)
MATCHING (id)
RETURNING id, username;

-- MERGE (3.0+, SQL standard)
MERGE INTO users AS t
USING (SELECT 1 AS id, 'alice' AS username, 'alice@example.com' AS email, 25 AS age
       FROM RDB$DATABASE) AS s
ON t.id = s.id
WHEN MATCHED THEN
    UPDATE SET username = s.username, email = s.email, age = s.age
WHEN NOT MATCHED THEN
    INSERT (id, username, email, age) VALUES (s.id, s.username, s.email, s.age);

-- MERGE with source table
MERGE INTO users AS t
USING staging_users AS s
ON t.id = s.id
WHEN MATCHED THEN
    UPDATE SET t.email = s.email, t.age = s.age, t.updated_at = CURRENT_TIMESTAMP
WHEN NOT MATCHED THEN
    INSERT (username, email, age) VALUES (s.username, s.email, s.age);

-- MERGE with DELETE (4.0+)
MERGE INTO users AS t
USING staging_users AS s
ON t.id = s.id
WHEN MATCHED AND s.status = 0 THEN
    DELETE
WHEN MATCHED THEN
    UPDATE SET t.email = s.email
WHEN NOT MATCHED THEN
    INSERT (username, email, age) VALUES (s.username, s.email, s.age);

-- MERGE with RETURNING (3.0+)
MERGE INTO users AS t
USING staging_users AS s
ON t.id = s.id
WHEN MATCHED THEN
    UPDATE SET t.email = s.email
WHEN NOT MATCHED THEN
    INSERT (username, email) VALUES (s.username, s.email)
RETURNING t.id, t.username;

-- Note: UPDATE OR INSERT is simpler but less flexible than MERGE
-- Note: MATCHING clause specifies which columns determine insert vs update
-- Note: if MATCHING is omitted, primary key is used
