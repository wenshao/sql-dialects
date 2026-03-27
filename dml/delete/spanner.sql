-- Google Cloud Spanner: DELETE (GoogleSQL)
--
-- 参考资料:
--   [1] Spanner SQL Reference (GoogleSQL)
--       https://cloud.google.com/spanner/docs/reference/standard-sql/query-syntax
--   [2] Spanner - Functions
--       https://cloud.google.com/spanner/docs/reference/standard-sql/functions-and-operators
--   [3] Spanner - Data Types
--       https://cloud.google.com/spanner/docs/reference/standard-sql/data-types

-- Basic delete
DELETE FROM Users WHERE Username = 'alice';

-- Delete all rows (WHERE true required)
DELETE FROM Users WHERE true;

-- Subquery delete
DELETE FROM Users WHERE UserId IN (SELECT UserId FROM Blacklist);

-- EXISTS subquery
DELETE FROM Users
WHERE EXISTS (SELECT 1 FROM Blacklist b WHERE b.Email = Users.Email);

-- CTE + DELETE
WITH Inactive AS (
    SELECT UserId FROM Users WHERE LastLogin < '2023-01-01'
)
DELETE FROM Users WHERE UserId IN (SELECT UserId FROM Inactive);

-- DELETE with THEN RETURN (Spanner-specific)
DELETE FROM Users WHERE Status = 0
THEN RETURN UserId, Username, Email;

-- Delete from interleaved child table
DELETE FROM OrderItems WHERE OrderId = 100 AND ItemId = 1;

-- Delete parent with CASCADE (if INTERLEAVE IN PARENT ... ON DELETE CASCADE)
DELETE FROM Orders WHERE OrderId = 100;
-- Child rows in OrderItems are automatically deleted

-- Delete by primary key range
DELETE FROM Events WHERE EventId BETWEEN 1000 AND 2000;

-- Conditional delete with subquery
DELETE FROM Orders
WHERE UserId IN (SELECT UserId FROM Users WHERE Status = 0);

-- Row deletion policy (automatic TTL, alternative to manual DELETE)
-- Set at table creation or via ALTER TABLE:
-- ALTER TABLE Events ADD ROW DELETION POLICY (OLDER_THAN(EventTime, INTERVAL 90 DAY));

-- Note: DELETE requires WHERE clause (use WHERE true for all rows)
-- Note: THEN RETURN replaces PostgreSQL's RETURNING
-- Note: Deleting a parent row cascades to interleaved children (if configured)
-- Note: No TRUNCATE statement
-- Note: No DELETE ... USING (multi-table delete)
-- Note: No DELETE ... LIMIT
-- Note: Single transaction limit: 80,000 mutations
-- Note: Row deletion policy provides automatic TTL-based cleanup
