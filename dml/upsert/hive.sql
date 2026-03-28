-- Hive: UPSERT / MERGE (ACID 表 2.2+)
--
-- 参考资料:
--   [1] Apache Hive Language Manual - MERGE
--       https://cwiki.apache.org/confluence/display/Hive/LanguageManual+DML#LanguageManualDML-Merge
--   [2] Apache Hive - Hive Transactions
--       https://cwiki.apache.org/confluence/display/Hive/Hive+Transactions

-- ============================================================
-- 1. MERGE: Hive 的 UPSERT 实现 (2.2+, 仅 ACID 表)
-- ============================================================
-- Hive 没有 MySQL 的 ON DUPLICATE KEY UPDATE 或 PostgreSQL 的 ON CONFLICT。
-- MERGE 是 SQL:2003 标准的 UPSERT 操作，Hive 2.2 引入。

-- 基本 MERGE（UPSERT）
MERGE INTO users AS t
USING staging_users AS s
ON t.id = s.id
WHEN MATCHED THEN
    UPDATE SET username = s.username, email = s.email
WHEN NOT MATCHED THEN
    INSERT VALUES (s.id, s.username, s.email);

-- 带条件的 MERGE（UPDATE + DELETE + INSERT）
MERGE INTO users AS t
USING staging_users AS s
ON t.id = s.id
WHEN MATCHED AND s.action = 'update' THEN
    UPDATE SET username = s.username, email = s.email
WHEN MATCHED AND s.action = 'delete' THEN
    DELETE
WHEN NOT MATCHED THEN
    INSERT VALUES (s.id, s.username, s.email);

-- 仅插入不存在的行（INSERT IF NOT EXISTS）
MERGE INTO users AS t
USING staging_users AS s
ON t.id = s.id
WHEN NOT MATCHED THEN
    INSERT VALUES (s.id, s.username, s.email);

-- 从子查询 MERGE
MERGE INTO users AS t
USING (SELECT 1 AS id, 'alice' AS username, 'alice@example.com' AS email) AS s
ON t.id = s.id
WHEN MATCHED THEN UPDATE SET email = s.email
WHEN NOT MATCHED THEN INSERT VALUES (s.id, s.username, s.email);

-- MERGE 的内部实现:
-- MERGE 被编译为一个 FULL OUTER JOIN + 条件路由:
-- 1. 匹配的行 → WHEN MATCHED 分支 → UPDATE (delete delta + insert delta) 或 DELETE
-- 2. 不匹配的行 → WHEN NOT MATCHED → INSERT (insert delta)
-- 整个 MERGE 是一个原子操作（一个隐式事务）

-- ============================================================
-- 2. 非 ACID 表的 UPSERT 替代方案
-- ============================================================

-- 方案 A: FULL OUTER JOIN + INSERT OVERWRITE
INSERT OVERWRITE TABLE users
SELECT
    COALESCE(s.id, t.id) AS id,
    COALESCE(s.username, t.username) AS username,
    COALESCE(s.email, t.email) AS email
FROM users t
FULL OUTER JOIN staging_users s ON t.id = s.id;

-- 方案 B: UNION ALL + ROW_NUMBER 去重（增量数据优先）
INSERT OVERWRITE TABLE users
SELECT id, username, email FROM (
    SELECT id, username, email,
           ROW_NUMBER() OVER (PARTITION BY id ORDER BY source_priority DESC) AS rn
    FROM (
        SELECT id, username, email, 1 AS source_priority FROM staging_users  -- 新数据优先
        UNION ALL
        SELECT id, username, email, 0 AS source_priority FROM users          -- 旧数据
    ) combined
) ranked
WHERE rn = 1;

-- 方案 C: 分区级 UPSERT（只重写受影响的分区）
INSERT OVERWRITE TABLE events PARTITION (dt='2024-01-15')
SELECT
    COALESCE(s.user_id, t.user_id),
    COALESCE(s.event_name, t.event_name),
    COALESCE(s.event_time, t.event_time)
FROM events t
FULL OUTER JOIN staging_events s
    ON t.user_id = s.user_id AND t.event_time = s.event_time
WHERE t.dt = '2024-01-15' OR s.dt = '2024-01-15';

-- 设计分析: INSERT OVERWRITE UPSERT 的代价
-- 需要读取整个表 + staging 数据 → JOIN → 写回整个表
-- 对于 TB 级表，即使 staging 只有几百行，也需要全量重写
-- 这就是为什么 ACID MERGE 在大表场景下更高效

-- ============================================================
-- 3. SCD (缓慢变化维) 中的 MERGE 应用
-- ============================================================
-- Type 1 SCD: 直接覆盖（用 MERGE UPDATE）
MERGE INTO dim_customer AS t
USING staging_customer AS s
ON t.customer_id = s.customer_id
WHEN MATCHED THEN
    UPDATE SET name = s.name, address = s.address
WHEN NOT MATCHED THEN
    INSERT VALUES (s.customer_id, s.name, s.address);

-- Type 2 SCD: 保留历史（INSERT OVERWRITE 方案，见 scenarios/slowly-changing-dim）

-- ============================================================
-- 4. 跨引擎对比: UPSERT 语法
-- ============================================================
-- 引擎          UPSERT 语法                       版本
-- MySQL         INSERT ... ON DUPLICATE KEY UPDATE  3.22+
-- PostgreSQL    INSERT ... ON CONFLICT DO UPDATE    9.5+
-- Oracle        MERGE INTO ... USING ... ON ...     9i+
-- SQL Server    MERGE (有已知 Bug)                  2008+
-- Hive          MERGE (ACID 表)                     2.2+
-- Spark SQL     MERGE (Delta Lake)                  Delta 0.3+
-- BigQuery      MERGE                               标准
-- Trino         MERGE (部分 Connector)              432+
-- Flink SQL     不支持 MERGE                        Changelog 替代
-- MaxCompute    MERGE (类 Hive)                     支持
--
-- MySQL 的 ON DUPLICATE KEY UPDATE 是最简洁的 UPSERT:
-- INSERT INTO t (id, name) VALUES (1, 'alice') ON DUPLICATE KEY UPDATE name='alice';
-- 但它绑定了唯一索引，而 Hive 没有唯一索引，因此无法实现这种语法。

-- ============================================================
-- 5. 对引擎开发者的启示
-- ============================================================
-- 1. MERGE 是最通用的 UPSERT 语法: SQL 标准兼容，支持 UPDATE+DELETE+INSERT
-- 2. MERGE 的实现本质是 JOIN + 条件路由: 优化器需要高效处理大表 JOIN
-- 3. 非 ACID UPSERT 的 INSERT OVERWRITE 模式仍然有效:
--    对于批处理 ETL，全量重写的幂等性比行级 MERGE 更可靠
-- 4. UPSERT 需要"匹配键": MERGE 的 ON 条件 / ON CONFLICT 的约束列
--    Hive 没有主键强制执行，用户需要自行保证匹配键的唯一性
