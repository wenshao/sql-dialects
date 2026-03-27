-- Google Cloud Spanner: Subqueries (GoogleSQL)
--
-- 参考资料:
--   [1] Spanner SQL Reference (GoogleSQL)
--       https://cloud.google.com/spanner/docs/reference/standard-sql/query-syntax
--   [2] Spanner - Functions
--       https://cloud.google.com/spanner/docs/reference/standard-sql/functions-and-operators
--   [3] Spanner - Data Types
--       https://cloud.google.com/spanner/docs/reference/standard-sql/data-types

-- Scalar subquery
SELECT Username, (SELECT COUNT(*) FROM Orders WHERE UserId = Users.UserId) AS OrderCount
FROM Users;

-- WHERE subquery
SELECT * FROM Users WHERE UserId IN (SELECT UserId FROM Orders WHERE Amount > 100);
SELECT * FROM Users WHERE UserId NOT IN (SELECT UserId FROM Blacklist);

-- EXISTS
SELECT * FROM Users u
WHERE EXISTS (SELECT 1 FROM Orders o WHERE o.UserId = u.UserId);
SELECT * FROM Users u
WHERE NOT EXISTS (SELECT 1 FROM Orders o WHERE o.UserId = u.UserId);

-- Comparison operators + subquery
SELECT * FROM Users WHERE Age > (SELECT AVG(Age) FROM Users);

-- FROM subquery (derived table)
SELECT t.City, t.Cnt FROM (
    SELECT City, COUNT(*) AS Cnt FROM Users GROUP BY City
) t WHERE t.Cnt > 10;

-- Correlated subquery
SELECT u.Username,
    (SELECT MAX(Amount) FROM Orders o WHERE o.UserId = u.UserId) AS MaxOrder
FROM Users u;

-- CTE (preferred over deeply nested subqueries)
WITH HighValueOrders AS (
    SELECT UserId, SUM(Amount) AS Total
    FROM Orders GROUP BY UserId HAVING SUM(Amount) > 1000
)
SELECT u.Username, h.Total
FROM Users u JOIN HighValueOrders h ON u.UserId = h.UserId;

-- ARRAY subquery (Spanner-specific)
SELECT Username,
    ARRAY(SELECT Amount FROM Orders WHERE UserId = Users.UserId ORDER BY Amount DESC) AS OrderAmounts
FROM Users;

-- ARRAY with STRUCT
SELECT Username,
    ARRAY(SELECT AS STRUCT OrderId, Amount FROM Orders WHERE UserId = Users.UserId) AS OrderDetails
FROM Users;

-- IN with UNNEST (search in array)
SELECT * FROM Users
WHERE 'admin' IN UNNEST(Tags);

-- Subquery in UPDATE
UPDATE Users SET Status = 2
WHERE UserId IN (SELECT UserId FROM Orders GROUP BY UserId HAVING SUM(Amount) > 10000);

-- Subquery in DELETE
DELETE FROM Users
WHERE UserId NOT IN (SELECT DISTINCT UserId FROM Orders);

-- Subquery with STRUCT
SELECT Username,
    (SELECT AS STRUCT COUNT(*) AS Cnt, SUM(Amount) AS Total
     FROM Orders WHERE UserId = Users.UserId) AS OrderInfo
FROM Users;

-- Note: No LATERAL subquery
-- Note: No ANY / ALL / SOME operators
-- Note: ARRAY subqueries return arrays directly
-- Note: SELECT AS STRUCT returns a STRUCT from a subquery
-- Note: IN UNNEST is used to search within ARRAY columns
-- Note: Correlated subqueries are supported but may be slow on large tables
