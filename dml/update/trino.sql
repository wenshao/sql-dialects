-- Trino: UPDATE
--
-- 参考资料:
--   [1] Trino - UPDATE
--       https://trino.io/docs/current/sql/update.html
--   [2] Trino - SQL Statement List
--       https://trino.io/docs/current/sql.html

-- 注意: Trino UPDATE 支持取决于底层 connector
-- 支持 UPDATE 的 connector: Iceberg, Delta Lake, Hive (ACID), Kudu, MySQL, PostgreSQL 等
-- 不支持 UPDATE 的 connector: Kafka, Elasticsearch 等

-- 基本更新
UPDATE users SET age = 26 WHERE username = 'alice';

-- 多列更新
UPDATE users SET email = 'new@example.com', age = 26 WHERE username = 'alice';

-- 子查询更新
UPDATE users SET age = (SELECT CAST(AVG(age) AS INTEGER) FROM users) WHERE age IS NULL;

-- CASE 表达式
UPDATE users SET status = CASE
    WHEN age < 18 THEN 0
    WHEN age >= 65 THEN 2
    ELSE 1
END;

-- 自引用更新
UPDATE users SET age = age + 1;

-- 跨 catalog 子查询更新
UPDATE iceberg.db.users SET status = 1
WHERE id IN (SELECT user_id FROM mysql.db.vip_list);

-- Iceberg connector 特性
-- UPDATE 会产生新的 snapshot，支持 Time Travel 查看历史版本
UPDATE iceberg.db.events SET event_name = 'user_login'
WHERE event_name = 'login';

-- Delta Lake connector 特性
-- UPDATE 操作产生新版本，旧版本保留用于回溯
UPDATE delta.db.users SET status = 0
WHERE last_login < DATE '2023-01-01';

-- Hive ACID 表更新
-- 需要表配置 transactional = true
UPDATE hive.db.users SET age = 26 WHERE username = 'alice';

-- 限制:
-- 不支持多表 JOIN 更新
-- 不支持 FROM 子句
-- 不支持 ORDER BY / LIMIT
-- 性能取决于底层存储和 connector 实现
