-- Hive: Sequences & Auto-Increment
--
-- 参考资料:
--   [1] Hive Language Manual - Data Types
--       https://cwiki.apache.org/confluence/display/Hive/LanguageManual+Types
--   [2] Hive Language Manual - UDF
--       https://cwiki.apache.org/confluence/display/Hive/LanguageManual+UDF
--   [3] Hive Language Manual - DDL
--       https://cwiki.apache.org/confluence/display/Hive/LanguageManual+DDL

-- ============================================
-- Hive 不支持 SEQUENCE、AUTO_INCREMENT、IDENTITY
-- 以下是替代方案
-- ============================================

-- 方法 1：使用 ROW_NUMBER() 窗口函数
SELECT
    ROW_NUMBER() OVER (ORDER BY created_at) AS row_id,
    username,
    email
FROM users;

-- 方法 2：使用 UUID 函数（Hive 4.0+ 或使用 reflect）
SELECT
    reflect('java.util.UUID', 'randomUUID') AS id,
    username,
    email
FROM users;

-- Hive 4.0+ 内置 UUID
-- SELECT uuid() AS id, username, email FROM users;

-- 方法 3：使用 monotonically_increasing_id()（Spark on Hive）
-- 在 Spark 环境中可用，不保证连续

-- 方法 4：CTAS + ROW_NUMBER 生成带 ID 的表
CREATE TABLE users_with_id AS
SELECT
    ROW_NUMBER() OVER (ORDER BY created_at) AS id,
    username,
    email,
    created_at
FROM users;

-- 方法 5：使用 Surrogate Key UDF
-- 某些 Hive 发行版提供 SURROGATE_KEY() 函数
-- SELECT SURROGATE_KEY() AS id, * FROM source_table;

-- 方法 6：使用 INPUT__FILE__NAME + ROW_NUMBER 组合
SELECT
    CONCAT(INPUT__FILE__NAME, '_', ROW_NUMBER() OVER ()) AS unique_id,
    username,
    email
FROM users;

-- ============================================
-- UUID 生成
-- ============================================
-- Hive 4.0+
-- SELECT uuid();

-- 通用方法（所有版本）
SELECT reflect('java.util.UUID', 'randomUUID');

-- ============================================
-- 序列 vs 自增 权衡
-- ============================================
-- Hive 是批处理数仓引擎，设计理念不同于 OLTP：
-- 1. 数据通常批量加载，不需要行级自增
-- 2. ROW_NUMBER() 是最常用的序号生成方式
-- 3. UUID 适合跨批次唯一标识
-- 4. 如需严格递增 ID，在 ETL 管道中生成
-- 5. Hive 3.0+ 的 ACID 表可以使用 ROW__ID（内部行标识）

-- 限制：
-- 不支持 CREATE SEQUENCE
-- 不支持 AUTO_INCREMENT / IDENTITY / SERIAL
-- 不支持 GENERATED AS IDENTITY
-- ROW_NUMBER() 仅在查询时生成，不持久化
