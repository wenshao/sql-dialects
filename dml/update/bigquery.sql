-- BigQuery: UPDATE
--
-- 参考资料:
--   [1] BigQuery SQL Reference - UPDATE
--       https://cloud.google.com/bigquery/docs/reference/standard-sql/dml-syntax#update_statement
--   [2] BigQuery SQL Reference - DML Syntax
--       https://cloud.google.com/bigquery/docs/reference/standard-sql/dml-syntax

-- 注意: BigQuery DML 有配额限制（每个表每秒最多 5 个并发 DML 语句）
-- UPDATE 必须带 WHERE 子句（不允许无条件更新整个表）

-- 基本更新
UPDATE dataset.users SET age = 26 WHERE username = 'alice';

-- 多列更新
UPDATE dataset.users SET email = 'new@example.com', age = 26 WHERE username = 'alice';

-- 更新所有行（必须用 WHERE true）
UPDATE dataset.users SET status = 0 WHERE true;

-- 子查询更新
UPDATE dataset.users SET age = (SELECT CAST(AVG(age) AS INT64) FROM dataset.users) WHERE age IS NULL;

-- FROM 子句（多表更新）
UPDATE dataset.users u
SET u.status = 1
FROM dataset.orders o
WHERE u.id = o.user_id AND o.amount > 1000;

-- CTE + UPDATE
WITH vip AS (
    SELECT user_id FROM dataset.orders GROUP BY user_id HAVING SUM(amount) > 10000
)
UPDATE dataset.users u
SET u.status = 2
FROM vip v
WHERE u.id = v.user_id;

-- CASE 表达式
UPDATE dataset.users SET status = CASE
    WHEN age < 18 THEN 0
    WHEN age >= 65 THEN 2
    ELSE 1
END
WHERE true;

-- 更新嵌套字段（STRUCT）
UPDATE dataset.events SET properties.source = 'mobile' WHERE event_name = 'login';

-- 更新 ARRAY 字段（需要整体替换）
UPDATE dataset.users SET tags = ['vip', 'premium'] WHERE username = 'alice';

-- 更新分区表（自动作用于相关分区）
UPDATE dataset.events SET event_name = 'user_login'
WHERE event_date = '2024-01-15' AND event_name = 'login';
