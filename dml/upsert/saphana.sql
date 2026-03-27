-- SAP HANA: UPSERT
--
-- 参考资料:
--   [1] SAP HANA SQL Reference
--       https://help.sap.com/docs/SAP_HANA_PLATFORM/4fe29514fd584807ac9f2a04f6754767/
--   [2] SAP HANA SQLScript Reference
--       https://help.sap.com/docs/SAP_HANA_PLATFORM/de2486ee947e43e684d39702027f8a94/

-- UPSERT (SAP HANA native keyword)
-- Inserts new row or replaces entire row if primary key matches
UPSERT users VALUES (1, 'alice', 'alice@example.com', 25, 0.00, NULL,
    CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
WHERE id = 1;

-- UPSERT with column list
UPSERT users (id, username, email, age)
VALUES (1, 'alice', 'alice@example.com', 26)
WHERE id = 1;

-- REPLACE (synonym for UPSERT)
REPLACE users (id, username, email, age)
VALUES (1, 'alice', 'alice@example.com', 26)
WHERE id = 1;

-- UPSERT with subquery
UPSERT users (id, username, email, age)
SELECT id, username, email, age FROM staging_users
WHERE id IN (SELECT id FROM staging_users);

-- MERGE (SQL standard, more flexible)
MERGE INTO users AS t
USING (SELECT 'alice' AS username, 'alice@example.com' AS email, 25 AS age FROM DUMMY) AS s
ON t.username = s.username
WHEN MATCHED THEN
    UPDATE SET email = s.email, age = s.age
WHEN NOT MATCHED THEN
    INSERT (username, email, age) VALUES (s.username, s.email, s.age);

-- MERGE with source table
MERGE INTO users AS t
USING staging_users AS s
ON t.id = s.id
WHEN MATCHED THEN
    UPDATE SET t.email = s.email, t.age = s.age, t.updated_at = CURRENT_TIMESTAMP
WHEN NOT MATCHED THEN
    INSERT (username, email, age, created_at) VALUES (s.username, s.email, s.age, CURRENT_TIMESTAMP);

-- MERGE with conditional logic
MERGE INTO users AS t
USING staging_users AS s
ON t.id = s.id
WHEN MATCHED AND s.status = 0 THEN
    DELETE
WHEN MATCHED THEN
    UPDATE SET t.email = s.email, t.age = s.age
WHEN NOT MATCHED THEN
    INSERT (username, email, age) VALUES (s.username, s.email, s.age);

-- Note: UPSERT/REPLACE replaces the ENTIRE row (all columns)
-- Note: MERGE allows partial updates (only specified columns)
-- Note: UPSERT requires primary key to determine match
-- Note: MERGE allows arbitrary ON condition
