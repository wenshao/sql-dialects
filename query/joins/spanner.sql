-- Google Cloud Spanner: JOIN (GoogleSQL)
--
-- 参考资料:
--   [1] Spanner SQL Reference (GoogleSQL)
--       https://cloud.google.com/spanner/docs/reference/standard-sql/query-syntax
--   [2] Spanner - Functions
--       https://cloud.google.com/spanner/docs/reference/standard-sql/functions-and-operators
--   [3] Spanner - Data Types
--       https://cloud.google.com/spanner/docs/reference/standard-sql/data-types

-- INNER JOIN
SELECT u.Username, o.Amount
FROM Users u
INNER JOIN Orders o ON u.UserId = o.UserId;

-- LEFT JOIN
SELECT u.Username, o.Amount
FROM Users u
LEFT JOIN Orders o ON u.UserId = o.UserId;

-- RIGHT JOIN
SELECT u.Username, o.Amount
FROM Users u
RIGHT JOIN Orders o ON u.UserId = o.UserId;

-- FULL OUTER JOIN
SELECT u.Username, o.Amount
FROM Users u
FULL OUTER JOIN Orders o ON u.UserId = o.UserId;

-- CROSS JOIN
SELECT u.Username, r.RoleName
FROM Users u
CROSS JOIN Roles r;

-- Self join
SELECT e.Username AS employee, m.Username AS manager
FROM Users e
LEFT JOIN Users m ON e.ManagerId = m.UserId;

-- USING
SELECT * FROM Users JOIN Orders USING (UserId);

-- Multi-table JOIN
SELECT u.Username, o.Amount, p.ProductName
FROM Users u
JOIN Orders o ON u.UserId = o.UserId
JOIN OrderItems oi ON o.OrderId = oi.OrderId
JOIN Products p ON oi.ProductId = p.ProductId;

-- UNNEST (array expansion)
SELECT u.Username, tag
FROM Users u
CROSS JOIN UNNEST(u.Tags) AS tag;

-- UNNEST with OFFSET
SELECT u.Username, tag, pos
FROM Users u
CROSS JOIN UNNEST(u.Tags) AS tag WITH OFFSET AS pos;

-- JOIN hint: FORCE_JOIN_ORDER
SELECT /*@FORCE_JOIN_ORDER=TRUE*/ u.Username, o.Amount
FROM Users u
JOIN Orders o ON u.UserId = o.UserId;

-- JOIN hint: JOIN_METHOD
SELECT /*@JOIN_METHOD=HASH_JOIN*/ u.Username, o.Amount
FROM Users u
JOIN Orders o ON u.UserId = o.UserId;

-- JOIN hint: JOIN_METHOD=APPLY_JOIN (nested loop)
SELECT /*@JOIN_METHOD=APPLY_JOIN*/ u.Username, o.Amount
FROM Users u
JOIN Orders o ON u.UserId = o.UserId;

-- Interleaved table join (very efficient, data is co-located)
SELECT o.OrderId, oi.ItemId, oi.Price
FROM Orders o
JOIN OrderItems oi ON o.OrderId = oi.OrderId;
-- OrderItems INTERLEAVED IN PARENT Orders: data is physically co-located

-- Subquery in JOIN
SELECT u.Username, stats.TotalAmount
FROM Users u
JOIN (
    SELECT UserId, SUM(Amount) AS TotalAmount FROM Orders GROUP BY UserId
) stats ON u.UserId = stats.UserId;

-- TABLESAMPLE
SELECT u.Username, o.Amount
FROM Users u TABLESAMPLE BERNOULLI (10)
JOIN Orders o ON u.UserId = o.UserId;

-- Note: LATERAL JOIN is not supported
-- Note: NATURAL JOIN is not supported
-- Note: Interleaved table joins are extremely efficient (no network hop)
-- Note: JOIN hints use SQL comments syntax /*@ ... */
-- Note: FORCE_JOIN_ORDER forces tables to be joined in query order
