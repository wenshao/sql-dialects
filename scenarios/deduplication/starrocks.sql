-- StarRocks: 去重策略
--
-- 参考资料:
--   [1] StarRocks Documentation - Primary Key Model
--       https://docs.starrocks.io/docs/table_design/table_types/

-- ============================================================
-- 1. Primary Key 模型: 天然去重
-- ============================================================
-- CREATE TABLE users (...) PRIMARY KEY(email) DISTRIBUTED BY HASH(email);
-- INSERT 自动覆盖——与 Doris Unique Key 相同。

-- ============================================================
-- 2. ROW_NUMBER 去重 (标准方案)
-- ============================================================
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY email ORDER BY created_at DESC) AS rn
    FROM users
) ranked WHERE rn = 1;

-- QUALIFY 简化(3.2+):
-- SELECT *, ROW_NUMBER() OVER (PARTITION BY email ORDER BY created_at DESC) AS rn
-- FROM users QUALIFY rn = 1;

-- ============================================================
-- 3. 近似去重
-- ============================================================
SELECT APPROX_COUNT_DISTINCT(email) FROM users;
SELECT BITMAP_UNION_COUNT(TO_BITMAP(user_id)) FROM orders;
