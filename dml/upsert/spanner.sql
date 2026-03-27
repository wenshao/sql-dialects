-- Google Cloud Spanner: UPSERT (GoogleSQL)
--
-- 参考资料:
--   [1] Spanner SQL Reference (GoogleSQL)
--       https://cloud.google.com/spanner/docs/reference/standard-sql/query-syntax
--   [2] Spanner - Functions
--       https://cloud.google.com/spanner/docs/reference/standard-sql/functions-and-operators
--   [3] Spanner - Data Types
--       https://cloud.google.com/spanner/docs/reference/standard-sql/data-types

-- Spanner has built-in INSERT OR UPDATE and MERGE for upsert

-- ============================================================
-- INSERT OR UPDATE (Spanner-specific, simplest upsert)
-- ============================================================

-- Insert if not exists, update all columns if exists (by primary key)
INSERT OR UPDATE INTO Users (UserId, Username, Email, Age)
VALUES (1, 'alice', 'alice@example.com', 26);

-- INSERT OR UPDATE multiple rows
INSERT OR UPDATE INTO Users (UserId, Username, Email, Age) VALUES
    (1, 'alice', 'alice@example.com', 25),
    (2, 'bob', 'bob@example.com', 30);

-- INSERT OR UPDATE with THEN RETURN
INSERT OR UPDATE INTO Users (UserId, Username, Email, Age)
VALUES (1, 'alice', 'alice@example.com', 26)
THEN RETURN UserId, Username, Email;

-- ============================================================
-- INSERT OR IGNORE (skip if primary key exists)
-- ============================================================

INSERT OR IGNORE INTO Users (UserId, Username, Email, Age)
VALUES (1, 'alice', 'alice@example.com', 25);
-- No error if UserId=1 already exists

-- ============================================================
-- REPLACE (delete existing + insert)
-- ============================================================

-- Deletes existing row with same primary key and inserts new row
REPLACE INTO Users (UserId, Username, Email, Age)
VALUES (1, 'alice', 'alice_new@example.com', 26);

-- ============================================================
-- MERGE (SQL standard, most flexible)
-- ============================================================

-- Basic MERGE
MERGE INTO Users AS t
USING (SELECT 1 AS UserId, 'alice' AS Username, 'alice@example.com' AS Email, 26 AS Age) AS s
ON t.UserId = s.UserId
WHEN MATCHED THEN
    UPDATE SET Email = s.Email, Age = s.Age
WHEN NOT MATCHED THEN
    INSERT (UserId, Username, Email, Age) VALUES (s.UserId, s.Username, s.Email, s.Age);

-- MERGE from another table
MERGE INTO Users AS t
USING StagingUsers AS s
ON t.UserId = s.UserId
WHEN MATCHED THEN
    UPDATE SET Email = s.Email, Age = s.Age
WHEN NOT MATCHED THEN
    INSERT (UserId, Username, Email, Age)
    VALUES (s.UserId, s.Username, s.Email, s.Age);

-- MERGE with conditional update
MERGE INTO Users AS t
USING StagingUsers AS s
ON t.UserId = s.UserId
WHEN MATCHED AND s.Age > t.Age THEN
    UPDATE SET Age = s.Age
WHEN MATCHED AND s.Age <= t.Age THEN
    DELETE
WHEN NOT MATCHED THEN
    INSERT (UserId, Username, Email, Age)
    VALUES (s.UserId, s.Username, s.Email, s.Age);

-- MERGE with THEN RETURN
MERGE INTO Users AS t
USING (SELECT 1 AS UserId, 'alice' AS Username, 'alice@example.com' AS Email) AS s
ON t.UserId = s.UserId
WHEN MATCHED THEN UPDATE SET Email = s.Email
WHEN NOT MATCHED THEN INSERT (UserId, Username, Email) VALUES (s.UserId, s.Username, s.Email)
THEN RETURN t.UserId, t.Username;

-- Note: INSERT OR UPDATE matches on primary key only
-- Note: INSERT OR IGNORE silently skips existing rows
-- Note: REPLACE deletes + re-inserts (triggers ON DELETE CASCADE on interleaved children)
-- Note: MERGE provides most flexibility with conditions
-- Note: No INSERT ... ON CONFLICT syntax (use INSERT OR UPDATE or MERGE)
-- Note: All operations are strongly consistent
