-- IBM Db2: UPDATE
--
-- 参考资料:
--   [1] Db2 SQL Reference
--       https://www.ibm.com/docs/en/db2/11.5?topic=sql
--   [2] Db2 Built-in Functions
--       https://www.ibm.com/docs/en/db2/11.5?topic=functions-built-in

-- Basic update
UPDATE users SET age = 26 WHERE username = 'alice';

-- Multiple columns
UPDATE users SET email = 'new@example.com', age = 26 WHERE username = 'alice';

-- Subquery update
UPDATE users SET age = (SELECT AVG(age) FROM users) WHERE age IS NULL;

-- Correlated subquery update
UPDATE users u SET total_orders = (
    SELECT COUNT(*) FROM orders o WHERE o.user_id = u.id
);

-- Update with join (using subquery in SET)
UPDATE users SET status = 1
WHERE id IN (SELECT user_id FROM orders WHERE amount > 1000);

-- MERGE for multi-table update (see upsert module)

-- CASE expression
UPDATE users SET status = CASE
    WHEN age < 18 THEN 0
    WHEN age >= 65 THEN 2
    ELSE 1
END;

-- SELECT FROM ... UPDATE (return updated rows, Db2 specific)
SELECT id, username, age FROM FINAL TABLE (
    UPDATE users SET age = 26 WHERE username = 'alice'
);

-- Update with OLD TABLE (see previous values)
SELECT id, username, age FROM OLD TABLE (
    UPDATE users SET age = 26 WHERE username = 'alice'
);

-- CTE + UPDATE
WITH vip AS (
    SELECT user_id FROM orders GROUP BY user_id HAVING SUM(amount) > 10000
)
UPDATE users SET status = 2
WHERE id IN (SELECT user_id FROM vip);

-- Batch update with cursor (in stored procedure)
-- DECLARE cur CURSOR FOR SELECT id, age FROM users WHERE status = 0 FOR UPDATE;
-- UPDATE users SET status = 1 WHERE CURRENT OF cur;

-- Update with isolation level
UPDATE users SET age = 26 WHERE username = 'alice' WITH RS;

-- After large updates
RUNSTATS ON TABLE schema.users WITH DISTRIBUTION AND DETAILED INDEXES ALL;
REORG TABLE users;
