-- YugabyteDB: UPDATE (YSQL, v2.x+)
--
-- 参考资料:
--   [1] YugabyteDB YSQL Reference
--       https://docs.yugabyte.com/stable/api/ysql/
--   [2] YugabyteDB PostgreSQL Compatibility
--       https://docs.yugabyte.com/stable/explore/ysql-language-features/

-- YugabyteDB uses PostgreSQL-compatible UPDATE syntax

-- Basic update
UPDATE users SET age = 26 WHERE username = 'alice';

-- Multiple columns
UPDATE users SET email = 'new@example.com', age = 26 WHERE username = 'alice';

-- Update all rows
UPDATE users SET status = 0;

-- Subquery update
UPDATE users SET age = (SELECT AVG(age)::INT FROM users) WHERE age IS NULL;

-- FROM clause (multi-table update)
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

-- Update JSONB: merge
UPDATE users SET metadata = metadata || '{"premium": true}'::JSONB
WHERE id = 1;

-- Update JSONB: remove key
UPDATE users SET metadata = metadata - 'temporary_flag'
WHERE id = 1;

-- Update ARRAY field
UPDATE profiles SET tags = array_append(tags, 'premium')
WHERE user_id = 1;
UPDATE profiles SET tags = array_remove(tags, 'trial')
WHERE user_id = 1;

-- Update partitioned table (routes to correct partition)
UPDATE geo_orders SET amount = 150.00
WHERE id = 1 AND region = 'us';

-- Update with subquery in SET
UPDATE orders o
SET status = 'shipped'
WHERE o.id IN (SELECT order_id FROM shipments WHERE shipped_at IS NOT NULL);

-- Update with row-level locking
UPDATE accounts SET balance = balance - 100
WHERE id = 1;
-- In YugabyteDB, row locking is implicit with updates

-- Note: UPDATE is transactional across distributed tablets
-- Note: RETURNING clause works the same as PostgreSQL
-- Note: FROM clause for multi-table updates (same as PostgreSQL)
-- Note: Updates touching multiple tablets use distributed transactions
-- Note: Single-row updates on hash-sharded tables are fast (single tablet)
-- Note: No DML rate limits
