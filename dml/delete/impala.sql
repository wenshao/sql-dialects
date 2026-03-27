-- Apache Impala: DELETE
--
-- 参考资料:
--   [1] Impala SQL Reference
--       https://impala.apache.org/docs/build/html/topics/impala_langref.html
--   [2] Impala Built-in Functions
--       https://impala.apache.org/docs/build/html/topics/impala_functions.html

-- 注意: Impala DELETE 仅支持 Kudu 表
-- HDFS 表（Parquet/ORC/Avro/TextFile）不支持 DELETE

-- === Kudu 表 DELETE ===

-- 基本删除
DELETE FROM users_kudu WHERE username = 'alice';

-- 条件删除
DELETE FROM users_kudu WHERE status = 0 AND last_login < '2023-01-01';

-- 子查询删除
DELETE FROM users_kudu WHERE id IN (SELECT user_id FROM blacklist_kudu);

-- FROM 子句删除
DELETE users_kudu
FROM users_kudu JOIN blacklist_kudu ON users_kudu.email = blacklist_kudu.email;

-- 范围删除
DELETE FROM users_kudu WHERE age < 18;
DELETE FROM users_kudu WHERE created_at < '2023-01-01';

-- 删除所有行
DELETE FROM users_kudu;

-- === HDFS 表的替代方案 ===

-- 方式一：INSERT OVERWRITE（保留不需要删除的数据）
INSERT OVERWRITE users
SELECT * FROM users WHERE status != 0;

-- 方式二：分区级别（删除整个分区的数据）
ALTER TABLE orders DROP PARTITION (year=2023, month=1);

-- 方式三：INSERT OVERWRITE 分区
INSERT OVERWRITE orders PARTITION (year=2024, month=1)
SELECT id, user_id, amount
FROM orders
WHERE year = 2024 AND month = 1 AND amount > 0;

-- 方式四：CTAS（创建新表替换）
CREATE TABLE users_clean
STORED AS PARQUET AS
SELECT * FROM users WHERE status != 0;

-- 然后替换原表
-- DROP TABLE users;
-- ALTER TABLE users_clean RENAME TO users;

-- TRUNCATE（清空表/分区）
TRUNCATE TABLE users_kudu;
TRUNCATE TABLE IF EXISTS users_kudu;

-- 注意：只有 Kudu 表支持 DELETE
-- 注意：HDFS 表需要 INSERT OVERWRITE 或 DROP PARTITION 替代
-- 注意：不支持 USING / CTE + DELETE
-- 注意：不支持 RETURNING
-- 注意：不支持 ORDER BY / LIMIT
