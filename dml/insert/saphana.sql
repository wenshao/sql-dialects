-- SAP HANA: INSERT
--
-- 参考资料:
--   [1] SAP HANA SQL Reference
--       https://help.sap.com/docs/SAP_HANA_PLATFORM/4fe29514fd584807ac9f2a04f6754767/
--   [2] SAP HANA SQLScript Reference
--       https://help.sap.com/docs/SAP_HANA_PLATFORM/de2486ee947e43e684d39702027f8a94/

-- Single row insert
INSERT INTO users (username, email, age) VALUES ('alice', 'alice@example.com', 25);

-- Multiple rows
INSERT INTO users (username, email, age) VALUES
    ('alice', 'alice@example.com', 25),
    ('bob', 'bob@example.com', 30),
    ('charlie', 'charlie@example.com', 35);

-- Insert from query
INSERT INTO users_archive (username, email, age)
SELECT username, email, age FROM users WHERE age > 60;

-- Default values
INSERT INTO users (username, email, age) VALUES ('alice', 'alice@example.com', DEFAULT);

-- UPSERT (SAP HANA native keyword, same as REPLACE)
-- Inserts if not exists, replaces entire row if primary key matches
UPSERT users (id, username, email, age)
VALUES (1, 'alice', 'alice@example.com', 26)
WHERE id = 1;

-- REPLACE (synonym for UPSERT)
REPLACE users (id, username, email, age)
VALUES (1, 'alice', 'alice@example.com', 26)
WHERE id = 1;

-- INSERT with subquery
INSERT INTO vip_users (user_id, total_spent)
SELECT user_id, SUM(amount)
FROM orders
GROUP BY user_id
HAVING SUM(amount) > 10000;

-- CTAS (for creating new table with data)
CREATE COLUMN TABLE users_copy AS (
    SELECT * FROM users WHERE status = 1
) WITH DATA;

-- INSERT with hints
INSERT INTO users (username, email, age)
VALUES ('alice', 'alice@example.com', 25)
WITH HINT (NO_CS_JOIN);

-- Bulk insert via IMPORT FROM
-- IMPORT FROM CSV FILE '/tmp/users.csv' INTO users;
-- IMPORT FROM PARQUET FILE '/tmp/users.parquet' INTO users;

-- INSERT with generated identity
-- Identity value is auto-generated when omitted
INSERT INTO users (username, email, age)
VALUES ('alice', 'alice@example.com', 25);
-- Retrieve: SELECT CURRENT_IDENTITY_VALUE() FROM DUMMY;
