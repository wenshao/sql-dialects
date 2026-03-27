-- Redshift: UPDATE
--
-- 参考资料:
--   [1] Redshift SQL Reference
--       https://docs.aws.amazon.com/redshift/latest/dg/cm_chap_SQLCommandRef.html
--   [2] Redshift SQL Functions
--       https://docs.aws.amazon.com/redshift/latest/dg/c_SQL_functions.html
--   [3] Redshift Data Types
--       https://docs.aws.amazon.com/redshift/latest/dg/c_Supported_data_types.html

-- 基本更新
UPDATE users SET age = 26 WHERE username = 'alice';

-- 多列更新
UPDATE users SET email = 'new@example.com', age = 26 WHERE username = 'alice';

-- 子查询更新
UPDATE users SET age = (SELECT AVG(age) FROM users) WHERE age IS NULL;

-- FROM 子句（多表更新，PostgreSQL 风格）
UPDATE users
SET status = 1
FROM orders
WHERE users.id = orders.user_id AND orders.amount > 1000;

-- 多表 JOIN 更新
UPDATE users
SET status = 1
FROM orders o, payments p
WHERE users.id = o.user_id AND o.id = p.order_id AND p.amount > 1000;

-- CTE + UPDATE
WITH vip AS (
    SELECT user_id FROM orders GROUP BY user_id HAVING SUM(amount) > 10000
)
UPDATE users
SET status = 2
FROM vip
WHERE users.id = vip.user_id;

-- CASE 表达式
UPDATE users SET status = CASE
    WHEN age < 18 THEN 0
    WHEN age >= 65 THEN 2
    ELSE 1
END;

-- 自引用更新
UPDATE users SET age = age + 1;

-- 更新 SUPER 列（半结构化数据）
UPDATE events SET data = JSON_PARSE('{"source": "web"}') WHERE id = 1;

-- 基于子查询的批量更新
UPDATE users
SET email = t.new_email
FROM (
    SELECT 'alice' AS username, 'alice_new@example.com' AS new_email
    UNION ALL
    SELECT 'bob', 'bob_new@example.com'
) t
WHERE users.username = t.username;

-- 注意：Redshift 中 UPDATE 实际是 DELETE + INSERT（行级，列式存储）
-- 注意：频繁 UPDATE 会导致"ghost rows"，需要 VACUUM DELETE 清理
-- 注意：大批量更新建议用 CTAS 重建表
-- 注意：UPDATE 不支持 RETURNING 子句
-- 注意：UPDATE 不支持 LIMIT
-- 注意：不支持别名（UPDATE users u SET ... 不行，需用全表名）
