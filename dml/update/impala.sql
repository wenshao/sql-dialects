-- Apache Impala: UPDATE
--
-- 参考资料:
--   [1] Impala SQL Reference
--       https://impala.apache.org/docs/build/html/topics/impala_langref.html
--   [2] Impala Built-in Functions
--       https://impala.apache.org/docs/build/html/topics/impala_functions.html

-- 注意: Impala UPDATE 仅支持 Kudu 表
-- HDFS 表（Parquet/ORC/Avro/TextFile）不支持 UPDATE

-- === Kudu 表 UPDATE ===

-- 基本更新
UPDATE users_kudu SET age = 26 WHERE username = 'alice';

-- 多列更新
UPDATE users_kudu SET email = 'new@example.com', age = 26 WHERE id = 1;

-- 表达式更新
UPDATE users_kudu SET age = age + 1 WHERE id = 1;

-- CASE 表达式
UPDATE users_kudu SET status = CASE
    WHEN age < 18 THEN 0
    WHEN age >= 65 THEN 2
    ELSE 1
END;

-- 子查询条件
UPDATE users_kudu SET status = 0
WHERE id IN (SELECT user_id FROM blacklist_kudu);

-- FROM 子句更新
UPDATE users_kudu SET status = 1
FROM users_kudu JOIN orders_kudu ON users_kudu.id = orders_kudu.user_id
WHERE orders_kudu.amount > 1000;

-- 条件更新
UPDATE users_kudu SET
    status = 0
WHERE last_login < '2023-01-01' AND status = 1;

-- 批量更新（通过子查询）
UPDATE users_kudu SET
    email = t.new_email
FROM users_kudu JOIN (
    SELECT 1 AS id, 'alice_new@example.com' AS new_email
    UNION ALL
    SELECT 2, 'bob_new@example.com'
) t ON users_kudu.id = t.id;

-- === HDFS 表的替代方案 ===

-- 方式一：INSERT OVERWRITE（全量替换）
INSERT OVERWRITE users
SELECT
    id, username,
    CASE WHEN username = 'alice' THEN 'new@example.com' ELSE email END AS email,
    CASE WHEN username = 'alice' THEN 26 ELSE age END AS age,
    balance, bio, created_at, updated_at
FROM users;

-- 方式二：CTAS（创建新表）
CREATE TABLE users_new STORED AS PARQUET AS
SELECT id, username, email,
    CASE WHEN age IS NULL THEN 0 ELSE age END AS age
FROM users;

-- 方式三：分区级别覆盖
INSERT OVERWRITE orders PARTITION (year=2024, month=1)
SELECT id, user_id,
    CASE WHEN amount < 0 THEN 0 ELSE amount END AS amount
FROM orders WHERE year = 2024 AND month = 1;

-- 注意：只有 Kudu 表支持 UPDATE
-- 注意：不支持更新主键列
-- 注意：HDFS 表需要用 INSERT OVERWRITE 替代 UPDATE
-- 注意：不支持 RETURNING
-- 注意：不支持 CTE + UPDATE
