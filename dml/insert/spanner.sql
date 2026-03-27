-- Google Cloud Spanner: INSERT (GoogleSQL)
--
-- 参考资料:
--   [1] Spanner SQL Reference (GoogleSQL)
--       https://cloud.google.com/spanner/docs/reference/standard-sql/query-syntax
--   [2] Spanner - Functions
--       https://cloud.google.com/spanner/docs/reference/standard-sql/functions-and-operators
--   [3] Spanner - Data Types
--       https://cloud.google.com/spanner/docs/reference/standard-sql/data-types

-- Single row insert
INSERT INTO Users (UserId, Username, Email, Age)
VALUES (1, 'alice', 'alice@example.com', 25);

-- Multiple rows
INSERT INTO Users (UserId, Username, Email, Age) VALUES
    (1, 'alice', 'alice@example.com', 25),
    (2, 'bob', 'bob@example.com', 30),
    (3, 'charlie', 'charlie@example.com', 35);

-- INSERT from query
INSERT INTO UsersArchive (UserId, Username, Email, Age)
SELECT UserId, Username, Email, Age FROM Users WHERE Age > 60;

-- CTE + INSERT
WITH NewUsers AS (
    SELECT 1 AS UserId, 'alice' AS Username, 'alice@example.com' AS Email, 25 AS Age
    UNION ALL
    SELECT 2, 'bob', 'bob@example.com', 30
)
INSERT INTO Users (UserId, Username, Email, Age)
SELECT * FROM NewUsers;

-- INSERT with THEN RETURN (Spanner-specific, similar to RETURNING)
INSERT INTO Users (UserId, Username, Email, Age)
VALUES (1, 'alice', 'alice@example.com', 25)
THEN RETURN UserId, Username;

-- INSERT with GENERATE_UUID()
INSERT INTO Products (ProductId, Name, Price)
VALUES (GENERATE_UUID(), 'Widget', 9.99);

-- INSERT with sequence value
INSERT INTO Orders (OrderId, UserId, Amount)
VALUES (GET_NEXT_SEQUENCE_VALUE(SEQUENCE OrderSeq), 1, 99.99);

-- INSERT with commit timestamp
INSERT INTO AuditLog (LogId, Action, CommitTs)
VALUES (1, 'user_created', PENDING_COMMIT_TIMESTAMP());
-- PENDING_COMMIT_TIMESTAMP() is set at commit time

-- Insert JSON data
INSERT INTO Events (EventId, Data)
VALUES (1, JSON '{"source": "web", "browser": "chrome"}');

-- Insert ARRAY data
INSERT INTO Profiles (UserId, Tags)
VALUES (1, ['vip', 'active', 'premium']);

-- Insert STRUCT via subquery
INSERT INTO Events (EventId, Data)
VALUES (2, JSON_OBJECT('name', 'alice', 'age', 25));

-- Insert into interleaved child table
-- Parent row must exist first
INSERT INTO Orders (OrderId, UserId, Amount, OrderDate)
VALUES (100, 1, 99.99, '2024-01-15');
INSERT INTO OrderItems (OrderId, ItemId, ProductId, Quantity, Price)
VALUES (100, 1, 'prod-001', 2, 49.99);

-- Insert with DEFAULT
INSERT INTO Users (UserId, Username, Email, Status)
VALUES (1, 'alice', 'alice@example.com', DEFAULT);

-- INSERT OR UPDATE (Spanner-specific upsert, see upsert module)
INSERT OR UPDATE INTO Users (UserId, Username, Email, Age)
VALUES (1, 'alice', 'alice_new@example.com', 26);

-- INSERT OR IGNORE (skip if primary key exists)
INSERT OR IGNORE INTO Users (UserId, Username, Email, Age)
VALUES (1, 'alice', 'alice@example.com', 25);

-- Note: No auto-increment; generate keys in application
-- Note: PENDING_COMMIT_TIMESTAMP() records exact commit time
-- Note: THEN RETURN is Spanner's version of PostgreSQL's RETURNING
-- Note: INSERT OR UPDATE / INSERT OR IGNORE are Spanner-specific
-- Note: Mutations API (non-SQL) is faster for bulk inserts
-- Note: Single transaction can modify at most 80,000 mutations
