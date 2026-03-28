-- Apache Doris: 去重策略
--
-- 参考资料:
--   [1] Doris Documentation - Unique Key Model
--       https://doris.apache.org/docs/data-table/data-model

-- ============================================================
-- 1. Unique Key 模型: 天然去重 (Doris 独特方案)
-- ============================================================
-- CREATE TABLE users (...) UNIQUE KEY(email) DISTRIBUTED BY HASH(email);
-- INSERT 相同 email 的行自动替换旧行——无需额外去重逻辑。
--
-- 对比: 这是 Doris/StarRocks 最独特的去重方式。
-- MySQL/PG 需要 UNIQUE 约束 + INSERT ON CONFLICT。
-- ClickHouse ReplacingMergeTree 是异步去重(不保证实时)。

-- ============================================================
-- 2. 查找重复
-- ============================================================
SELECT email, COUNT(*) AS cnt FROM users GROUP BY email HAVING COUNT(*) > 1;

-- ============================================================
-- 3. ROW_NUMBER 去重
-- ============================================================
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY email ORDER BY created_at DESC) AS rn
    FROM users
) ranked WHERE rn = 1;

-- ============================================================
-- 4. 删除重复
-- ============================================================
-- CTAS 方式(推荐)
CREATE TABLE users_clean AS
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY email ORDER BY created_at DESC) AS rn
    FROM users
) ranked WHERE rn = 1;

-- ============================================================
-- 5. 近似去重计数
-- ============================================================
SELECT APPROX_COUNT_DISTINCT(email) FROM users;
SELECT BITMAP_UNION_COUNT(TO_BITMAP(user_id)) FROM orders;
