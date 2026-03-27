-- Teradata: UPDATE
--
-- 参考资料:
--   [1] Teradata SQL Reference
--       https://docs.teradata.com/r/Teradata-VantageTM-SQL-Functions-Expressions-and-Predicates
--   [2] Teradata Database Documentation
--       https://docs.teradata.com/

-- Basic update
UPDATE users SET age = 26 WHERE username = 'alice';

-- Multiple columns
UPDATE users SET email = 'new@example.com', age = 26 WHERE username = 'alice';

-- Update with FROM (join update)
UPDATE users
FROM orders
SET users.status = 1
WHERE users.id = orders.user_id AND orders.amount > 1000;

-- Subquery update
UPDATE users SET age = (SELECT CAST(AVG(age) AS INTEGER) FROM users) WHERE age IS NULL;

-- Correlated subquery update
UPDATE users
SET total_orders = (
    SELECT COUNT(*) FROM orders WHERE orders.user_id = users.id
);

-- CASE expression
UPDATE users SET status = CASE
    WHEN age < 18 THEN 0
    WHEN age >= 65 THEN 2
    ELSE 1
END;

-- Update with join using FROM
UPDATE target_table
FROM source_table
SET target_table.col1 = source_table.col1,
    target_table.col2 = source_table.col2
WHERE target_table.id = source_table.id;

-- Update with aggregate subquery
UPDATE users
SET city_rank = (
    SELECT COUNT(*) + 1
    FROM users u2
    WHERE u2.city = users.city AND u2.age > users.age
);

-- Update VOLATILE table
UPDATE vt_staging SET processed = 1 WHERE id IN (SELECT id FROM processed_ids);

-- Note: updates to PRIMARY INDEX column values cause row redistribution
-- Note: large updates should consider batch processing
-- Note: COLLECT STATISTICS after large updates
COLLECT STATISTICS ON users COLUMN (status);
