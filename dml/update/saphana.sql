-- SAP HANA: UPDATE
--
-- 参考资料:
--   [1] SAP HANA SQL Reference
--       https://help.sap.com/docs/SAP_HANA_PLATFORM/4fe29514fd584807ac9f2a04f6754767/
--   [2] SAP HANA SQLScript Reference
--       https://help.sap.com/docs/SAP_HANA_PLATFORM/de2486ee947e43e684d39702027f8a94/

-- Basic update
UPDATE users SET age = 26 WHERE username = 'alice';

-- Multiple columns
UPDATE users SET email = 'new@example.com', age = 26 WHERE username = 'alice';

-- Update with FROM (join update)
UPDATE users SET status = 1
FROM orders
WHERE users.id = orders.user_id AND orders.amount > 1000;

-- Subquery update
UPDATE users SET age = (SELECT AVG(age) FROM users) WHERE age IS NULL;

-- Correlated subquery update
UPDATE users SET total_orders = (
    SELECT COUNT(*) FROM orders WHERE orders.user_id = users.id
);

-- CASE expression
UPDATE users SET status = CASE
    WHEN age < 18 THEN 0
    WHEN age >= 65 THEN 2
    ELSE 1
END;

-- Update with subquery in WHERE
UPDATE users SET status = 2
WHERE id IN (SELECT user_id FROM orders GROUP BY user_id HAVING SUM(amount) > 10000);

-- Update with hints
UPDATE users SET age = 26 WHERE username = 'alice'
WITH HINT (USE_OLAP_PLAN);

-- REPLACE / UPSERT (updates if PK exists, inserts otherwise)
-- See upsert module for details
UPSERT users (id, username, email, age)
VALUES (1, 'alice', 'alice@example.com', 26)
WHERE id = 1;

-- Update using MERGE
MERGE INTO users AS t
USING (SELECT 'alice' AS username, 26 AS new_age FROM DUMMY) AS s
ON t.username = s.username
WHEN MATCHED THEN UPDATE SET t.age = s.new_age;

-- Update with CURRENT_TIMESTAMP
UPDATE users SET updated_at = CURRENT_TIMESTAMP WHERE id = 1;

-- Note: column store updates go to delta storage first, then merged
-- MERGE DELTA OF users;  -- manually trigger delta merge if needed
