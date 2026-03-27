-- Google Cloud Spanner: CTE (Common Table Expressions, GoogleSQL)
--
-- 参考资料:
--   [1] Spanner SQL Reference (GoogleSQL)
--       https://cloud.google.com/spanner/docs/reference/standard-sql/query-syntax
--   [2] Spanner - Functions
--       https://cloud.google.com/spanner/docs/reference/standard-sql/functions-and-operators
--   [3] Spanner - Data Types
--       https://cloud.google.com/spanner/docs/reference/standard-sql/data-types

-- Basic CTE
WITH ActiveUsers AS (
    SELECT * FROM Users WHERE Status = 1
)
SELECT * FROM ActiveUsers WHERE Age > 25;

-- Multiple CTEs
WITH
ActiveUsers AS (
    SELECT * FROM Users WHERE Status = 1
),
UserOrders AS (
    SELECT UserId, COUNT(*) AS Cnt, SUM(Amount) AS Total
    FROM Orders GROUP BY UserId
)
SELECT u.Username, o.Cnt, o.Total
FROM ActiveUsers u
JOIN UserOrders o ON u.UserId = o.UserId;

-- CTE referencing previous CTE
WITH
Base AS (SELECT * FROM Users WHERE Status = 1),
Enriched AS (
    SELECT b.*, COUNT(o.OrderId) AS OrderCount
    FROM Base b LEFT JOIN Orders o ON b.UserId = o.UserId
    GROUP BY b.UserId, b.Username, b.Status, b.Age, b.City
)
SELECT * FROM Enriched WHERE OrderCount > 5;

-- Recursive CTE
WITH RECURSIVE Nums AS (
    SELECT 1 AS n
    UNION ALL
    SELECT n + 1 FROM Nums WHERE n < 10
)
SELECT n FROM Nums;

-- Recursive: hierarchy traversal
WITH RECURSIVE OrgTree AS (
    SELECT UserId, Username, ManagerId, 0 AS Level
    FROM Users WHERE ManagerId IS NULL
    UNION ALL
    SELECT u.UserId, u.Username, u.ManagerId, t.Level + 1
    FROM Users u JOIN OrgTree t ON u.ManagerId = t.UserId
)
SELECT * FROM OrgTree;

-- Recursive with depth limit
WITH RECURSIVE OrgTree AS (
    SELECT UserId, Username, ManagerId, 0 AS Level
    FROM Users WHERE ManagerId IS NULL
    UNION ALL
    SELECT u.UserId, u.Username, u.ManagerId, t.Level + 1
    FROM Users u JOIN OrgTree t ON u.ManagerId = t.UserId
    WHERE t.Level < 10
)
SELECT * FROM OrgTree;

-- CTE + INSERT
INSERT INTO UsersArchive (UserId, Username, Email)
WITH Inactive AS (
    SELECT UserId, Username, Email FROM Users WHERE LastLogin < '2023-01-01'
)
SELECT * FROM Inactive;

-- CTE + UPDATE
WITH VipUsers AS (
    SELECT UserId FROM Orders GROUP BY UserId HAVING SUM(Amount) > 10000
)
UPDATE Users u
SET u.Status = 2
FROM VipUsers v
WHERE u.UserId = v.UserId;

-- CTE + DELETE
WITH Inactive AS (
    SELECT UserId FROM Users WHERE LastLogin < '2023-01-01'
)
DELETE FROM Users WHERE UserId IN (SELECT UserId FROM Inactive);

-- CTE with UNNEST
WITH TagList AS (
    SELECT Username, tag
    FROM Users
    CROSS JOIN UNNEST(Tags) AS tag
)
SELECT tag, COUNT(*) AS Cnt
FROM TagList
GROUP BY tag ORDER BY Cnt DESC;

-- Note: Recursive CTEs are supported
-- Note: MATERIALIZED / NOT MATERIALIZED hints are not supported
-- Note: CTEs can be used with INSERT, UPDATE, DELETE
-- Note: Recursive CTEs have a maximum iteration limit
-- Note: CTE inlining is handled by the query optimizer
