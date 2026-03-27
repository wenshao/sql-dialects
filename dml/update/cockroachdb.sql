-- CockroachDB: UPDATE (v23.1+)
--
-- 参考资料:
--   [1] CockroachDB - SQL Statements
--       https://www.cockroachlabs.com/docs/stable/sql-statements
--   [2] CockroachDB - Functions and Operators
--       https://www.cockroachlabs.com/docs/stable/functions-and-operators
--   [3] CockroachDB - Data Types
--       https://www.cockroachlabs.com/docs/stable/data-types

-- CockroachDB uses PostgreSQL-compatible UPDATE syntax

-- Basic update
UPDATE users SET age = 26 WHERE username = 'alice';

-- Multiple columns
UPDATE users SET email = 'new@example.com', age = 26 WHERE username = 'alice';

-- Update all rows
UPDATE users SET status = 0;

-- Subquery update
UPDATE users SET age = (SELECT AVG(age)::INT FROM users) WHERE age IS NULL;

-- FROM clause (multi-table update, same as PostgreSQL)
UPDATE users u
SET status = 1
FROM orders o
WHERE u.id = o.user_id AND o.amount > 1000;

-- CTE + UPDATE
WITH vip AS (
    SELECT user_id FROM orders GROUP BY user_id HAVING SUM(amount) > 10000
)
UPDATE users u
SET status = 2
FROM vip v
WHERE u.id = v.user_id;

-- CASE expression
UPDATE users SET status = CASE
    WHEN age < 18 THEN 0
    WHEN age >= 65 THEN 2
    ELSE 1
END;

-- UPDATE ... RETURNING (same as PostgreSQL)
UPDATE users SET age = 26 WHERE username = 'alice'
RETURNING id, username, age;

-- Update JSONB field
UPDATE users SET metadata = jsonb_set(metadata, '{city}', '"New York"')
WHERE id = 1;

-- Update JSONB: add key
UPDATE users SET metadata = metadata || '{"premium": true}'::JSONB
WHERE id = 1;

-- Update JSONB: remove key
UPDATE users SET metadata = metadata - 'temporary_flag'
WHERE id = 1;

-- Update ARRAY field
UPDATE profiles SET tags = array_append(tags, 'premium')
WHERE user_id = 1;

-- Update with subquery in SET
UPDATE orders o
SET status = 'shipped'
WHERE o.id IN (SELECT order_id FROM shipments WHERE shipped_at IS NOT NULL);

-- Update in multi-region table
UPDATE regional_users SET email = 'new@example.com'
WHERE id = 1 AND region = 'us-east1';

-- Note: UPDATE is transactional and supports automatic retries
-- Note: No DML rate limits (unlike BigQuery)
-- Note: RETURNING clause supported on all DML
-- Note: FROM clause for multi-table updates (same as PostgreSQL)
-- Note: Updates in serializable isolation by default
