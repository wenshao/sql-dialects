-- Firebird: UPDATE
--
-- 参考资料:
--   [1] Firebird SQL Reference
--       https://firebirdsql.org/en/reference-manuals/
--   [2] Firebird Release Notes
--       https://firebirdsql.org/file/documentation/release_notes/html/en/4_0/rlsnotes40.html

-- Basic update
UPDATE users SET age = 26 WHERE username = 'alice';

-- Multiple columns
UPDATE users SET email = 'new@example.com', age = 26 WHERE username = 'alice';

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

-- RETURNING (2.1+, return updated rows)
UPDATE users SET age = 26 WHERE username = 'alice' RETURNING id, username, age;

-- Update with subquery in WHERE
UPDATE users SET status = 2
WHERE id IN (SELECT user_id FROM orders GROUP BY user_id HAVING SUM(amount) > 10000);

-- Update with join (using subquery, no FROM clause)
UPDATE users SET status = 1
WHERE EXISTS (SELECT 1 FROM orders WHERE orders.user_id = users.id AND orders.amount > 1000);

-- UPDATE OR INSERT (upsert, see upsert module)
UPDATE OR INSERT INTO users (id, username, email)
VALUES (1, 'alice', 'alice@example.com')
MATCHING (id);

-- Update with EXECUTE BLOCK (batch updates)
SET TERM !! ;
EXECUTE BLOCK
AS
    DECLARE v_id INTEGER;
BEGIN
    FOR SELECT id FROM users WHERE status = 0 INTO :v_id DO
    BEGIN
        UPDATE users SET status = 1, updated_at = CURRENT_TIMESTAMP
        WHERE id = :v_id;
    END
END!!
SET TERM ; !!

-- Cursor-based update (in PSQL)
-- FOR SELECT id, age FROM users WHERE status = 0 AS CURSOR cur DO
--     UPDATE users SET status = 1 WHERE CURRENT OF cur;

-- Note: Firebird uses MVCC; updates create new record versions
-- Note: old record versions are garbage collected automatically
