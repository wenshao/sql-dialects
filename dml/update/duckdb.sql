-- DuckDB: UPDATE (v0.8+)
--
-- 参考资料:
--   [1] DuckDB - SQL Reference
--       https://duckdb.org/docs/sql/introduction
--   [2] DuckDB - Functions
--       https://duckdb.org/docs/sql/functions/overview
--   [3] DuckDB - Data Types
--       https://duckdb.org/docs/sql/data_types/overview

-- Basic update
UPDATE users SET age = 26 WHERE username = 'alice';

-- Multi-column update
UPDATE users SET email = 'new@example.com', age = 26 WHERE username = 'alice';

-- Update from subquery
UPDATE users SET age = (SELECT AVG(age)::INTEGER FROM users) WHERE age IS NULL;

-- FROM clause (multi-table update, PostgreSQL-compatible)
UPDATE users SET status = 1
FROM orders
WHERE users.id = orders.user_id AND orders.amount > 1000;

-- RETURNING (v0.9+)
UPDATE users SET age = 26 WHERE username = 'alice' RETURNING id, username, age;
UPDATE users SET age = age + 1 RETURNING *;

-- CTE + UPDATE
WITH vip AS (
    SELECT user_id FROM orders GROUP BY user_id HAVING SUM(amount) > 10000
)
UPDATE users SET status = 2
FROM vip
WHERE users.id = vip.user_id;

-- CASE expression
UPDATE users SET status = CASE
    WHEN age < 18 THEN 0
    WHEN age >= 65 THEN 2
    ELSE 1
END;

-- Update with complex types
UPDATE complex_data SET tags = ['new_tag1', 'new_tag2'] WHERE id = 1;
UPDATE complex_data SET address = {'street': '456 Oak Ave', 'city': 'LA', 'zip': '90001'}
WHERE id = 1;
UPDATE complex_data SET meta = MAP {'updated': 'true'} WHERE id = 1;

-- Update with list_append / list_concat
UPDATE complex_data SET tags = list_append(tags, 'extra_tag') WHERE id = 1;

-- Update with struct field access
UPDATE events SET data = struct_insert(data, 'processed', true) WHERE id = 1;

-- Batch update from values
UPDATE users u SET
    email = t.new_email
FROM (VALUES ('alice', 'alice_new@example.com'), ('bob', 'bob_new@example.com'))
    AS t(username, new_email)
WHERE u.username = t.username;

-- Note: DuckDB supports UPDATE with full PostgreSQL-compatible syntax
-- Note: UPDATE works on persistent tables and temporary tables
-- Note: DuckDB UPDATE uses MVCC (row-level versioning internally)
-- Note: For bulk transformations, CREATE OR REPLACE TABLE ... AS SELECT is often faster
