-- Google Cloud Spanner: Stored Procedures and Functions (GoogleSQL)
--
-- 参考资料:
--   [1] Spanner SQL Reference (GoogleSQL)
--       https://cloud.google.com/spanner/docs/reference/standard-sql/query-syntax
--   [2] Spanner - Functions
--       https://cloud.google.com/spanner/docs/reference/standard-sql/functions-and-operators
--   [3] Spanner - Data Types
--       https://cloud.google.com/spanner/docs/reference/standard-sql/data-types

-- Spanner does not support traditional stored procedures
-- Alternative approaches are provided below

-- ============================================================
-- No stored procedures or user-defined functions in SQL
-- ============================================================

-- Spanner does not support:
-- CREATE FUNCTION
-- CREATE PROCEDURE
-- CALL
-- PL/pgSQL or any procedural language

-- ============================================================
-- Alternative: Views (for reusable queries)
-- ============================================================

CREATE VIEW ActiveUsers AS
SELECT UserId, Username, Email, Age
FROM Users
WHERE Status = 1;

SELECT * FROM ActiveUsers WHERE Age > 25;

CREATE VIEW UserOrderStats AS
SELECT u.UserId, u.Username,
    COUNT(o.OrderId) AS OrderCount,
    COALESCE(SUM(o.Amount), 0) AS TotalAmount
FROM Users u
LEFT JOIN Orders o ON u.UserId = o.UserId
GROUP BY u.UserId, u.Username;

-- ============================================================
-- Alternative: Client-side application logic
-- ============================================================

-- Transfer logic would be implemented in application code:
-- 1. Begin transaction (read-write)
-- 2. Read balance: SELECT Balance FROM Accounts WHERE AccountId = @from
-- 3. Check balance >= amount
-- 4. UPDATE Accounts SET Balance = Balance - @amount WHERE AccountId = @from
-- 5. UPDATE Accounts SET Balance = Balance + @amount WHERE AccountId = @to
-- 6. Commit transaction

-- ============================================================
-- Alternative: Batched DML in transactions
-- ============================================================

-- Multiple DML statements in a single transaction:
-- BEGIN TRANSACTION;
-- UPDATE Accounts SET Balance = Balance - 100 WHERE AccountId = 1;
-- UPDATE Accounts SET Balance = Balance + 100 WHERE AccountId = 2;
-- INSERT INTO TransferLog (FromId, ToId, Amount) VALUES (1, 2, 100);
-- COMMIT;

-- ============================================================
-- Change streams (for event-driven processing, 2022+)
-- ============================================================

-- Watch for data changes (alternative to triggers):
CREATE CHANGE STREAM UserChanges FOR Users;
CREATE CHANGE STREAM AllChanges FOR ALL;
CREATE CHANGE STREAM OrderChanges FOR Orders (Amount, Status);

-- Change streams are consumed via API, not SQL

-- Drop change stream
DROP CHANGE STREAM UserChanges;

-- ============================================================
-- Scheduled operations
-- ============================================================

-- Use Cloud Scheduler + Cloud Functions for periodic tasks
-- No built-in job scheduler in Spanner

-- Note: No stored procedures, functions, or triggers
-- Note: Use views for reusable query logic
-- Note: Use application code for procedural logic
-- Note: Change streams provide trigger-like functionality (via API)
-- Note: Transactions support multiple DML statements
-- Note: Spanner PostgreSQL interface also does not support procedures
