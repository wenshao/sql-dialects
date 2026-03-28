-- MaxCompute (ODPS): UPSERT / MERGE
--
-- 参考资料:
--   [1] MaxCompute SQL - MERGE INTO
--       https://help.aliyun.com/zh/maxcompute/user-guide/merge-into
--   [2] MaxCompute Transactional Tables
--       https://help.aliyun.com/zh/maxcompute/user-guide/transactional-tables

-- ============================================================
-- 1. 事务表 MERGE INTO（标准 SQL MERGE）
-- ============================================================

-- 基本 MERGE（匹配则更新，不匹配则插入）
MERGE INTO users AS t
USING staging_users AS s
ON t.id = s.id
WHEN MATCHED THEN
    UPDATE SET username = s.username, email = s.email, age = s.age
WHEN NOT MATCHED THEN
    INSERT (id, username, email, age) VALUES (s.id, s.username, s.email, s.age);

-- 带条件的 MERGE（只更新比目标表更新的记录）
MERGE INTO users AS t
USING staging_users AS s
ON t.id = s.id
WHEN MATCHED AND s.updated_at > t.updated_at THEN
    UPDATE SET username = s.username, email = s.email
WHEN MATCHED AND s.updated_at <= t.updated_at THEN
    UPDATE SET t.id = t.id                  -- 不更新（MaxCompute 需要有 UPDATE 子句）
WHEN NOT MATCHED THEN
    INSERT VALUES (s.id, s.username, s.email, s.age);

-- MERGE + DELETE（匹配且标记删除的记录删除）
MERGE INTO users AS t
USING staging_users AS s
ON t.id = s.id
WHEN MATCHED AND s.is_deleted = TRUE THEN
    DELETE
WHEN MATCHED THEN
    UPDATE SET username = s.username, email = s.email
WHEN NOT MATCHED AND s.is_deleted = FALSE THEN
    INSERT VALUES (s.id, s.username, s.email, s.age);

-- 设计分析: MERGE INTO 的底层实现
--   1. 读取 target 表和 source 表
--   2. 按 ON 条件做 JOIN（决定哪些行 MATCHED/NOT MATCHED）
--   3. 对 MATCHED 行: 写入 update delta 文件
--   4. 对 NOT MATCHED 行: 写入 insert 文件
--   5. 提交事务: 原子性地将所有 delta 文件注册到元数据
--
--   MERGE 是原子操作: 所有 UPDATE/INSERT/DELETE 在一个事务中完成
--   对比 先 DELETE 后 INSERT 的非原子方案: MERGE 更安全

-- ============================================================
-- 2. 非事务表: INSERT OVERWRITE 模拟 UPSERT
-- ============================================================

-- 这是 MaxCompute 中最常用的"更新"模式（适用于所有表）

-- 方案 A: FULL OUTER JOIN
INSERT OVERWRITE TABLE users
SELECT
    COALESCE(s.id, t.id) AS id,
    COALESCE(s.username, t.username) AS username,
    COALESCE(s.email, t.email) AS email,
    COALESCE(s.age, t.age) AS age
FROM users t
FULL OUTER JOIN staging_users s ON t.id = s.id;

-- 方案 B: UNION ALL + LEFT ANTI JOIN（性能通常更好）
INSERT OVERWRITE TABLE users
-- 新数据（覆盖已有记录 + 新增记录）
SELECT s.id, s.username, s.email, s.age FROM staging_users s
UNION ALL
-- 未被覆盖的旧数据
SELECT t.id, t.username, t.email, t.age FROM users t
LEFT ANTI JOIN staging_users s ON t.id = s.id;

-- 方案 C: ROW_NUMBER 去重（最通用）
INSERT OVERWRITE TABLE users
SELECT id, username, email, age FROM (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY id ORDER BY updated_at DESC) AS rn
    FROM (
        SELECT *, updated_at FROM staging_users
        UNION ALL
        SELECT *, updated_at FROM users
    ) combined
) ranked WHERE rn = 1;

-- 设计分析: INSERT OVERWRITE UPSERT 的权衡
--   优点:
--     1. 所有表都支持（不需要事务表）
--     2. 幂等（重跑结果相同）
--     3. 无碎片（重写生成完整文件）
--   缺点:
--     1. 必须读写全量数据（即使只更新几行）
--     2. SQL 复杂（FULL OUTER JOIN / UNION ALL 逻辑不直观）
--     3. 大表性能差
--     4. 并发不安全（两个 INSERT OVERWRITE 竞争）

-- ============================================================
-- 3. 分区表的 UPSERT（只重写受影响分区）
-- ============================================================

-- 这是生产中最常见的模式: 按分区增量更新
INSERT OVERWRITE TABLE events PARTITION (dt = '20240115')
SELECT COALESCE(s.user_id, t.user_id) AS user_id,
       COALESCE(s.event_name, t.event_name) AS event_name,
       COALESCE(s.event_time, t.event_time) AS event_time
FROM events t
FULL OUTER JOIN staging_events s
    ON t.user_id = s.user_id AND t.event_time = s.event_time
WHERE t.dt = '20240115' OR s.dt = '20240115';

-- 优势: 只重写一个分区的数据（GB 级而非 TB 级）
-- 这就是分区设计的核心价值: 将全表操作转化为分区级操作

-- ============================================================
-- 4. MERGE vs INSERT OVERWRITE 选择指南
-- ============================================================

-- 使用 MERGE INTO:
--   需要事务表声明
--   适合: 维度表（行数 < 千万）、需要精确行级控制
--   优势: 语法简洁、原子性、只写 delta（不重写全量）
--   场景: SCD Type 1 维度表更新、CDC 增量合并

-- 使用 INSERT OVERWRITE:
--   所有表都支持
--   适合: 事实表（行数 > 亿）、ETL 分区级更新
--   优势: 幂等、无碎片、不需要事务表
--   场景: 每日全量刷新、数据修复、分区级合并

-- ============================================================
-- 5. 横向对比: UPSERT/MERGE 语法
-- ============================================================

-- SQL 标准 MERGE:
--   MaxCompute: 事务表支持标准 MERGE    | Oracle: 9i+ 最早支持
--   PostgreSQL: 15+ 支持 MERGE          | SQL Server: 支持但有 Bug
--   BigQuery:   支持 MERGE              | Snowflake: 支持 MERGE
--   Hive:       ACID 表支持 MERGE

-- 非标准 UPSERT:
--   MySQL:      INSERT ... ON DUPLICATE KEY UPDATE（最常用）
--               REPLACE INTO（DELETE + INSERT，有副作用）
--   PostgreSQL: INSERT ... ON CONFLICT（9.5+，原生 UPSERT）
--   SQLite:     INSERT OR REPLACE / ON CONFLICT
--   ClickHouse: ReplacingMergeTree（后台异步合并去重）

-- INSERT OVERWRITE 模拟 UPSERT:
--   MaxCompute: 核心方案               | Hive: 相同方案
--   Spark:      df.write.mode("overwrite") + 自定义逻辑
--   BigQuery/Snowflake: 有原生 MERGE，不需要此方案

-- ============================================================
-- 6. 对引擎开发者的启示
-- ============================================================

-- 1. MERGE 是最强大的数据整合语句 — 新引擎应优先支持
-- 2. INSERT OVERWRITE 模拟 UPSERT 虽然笨拙但通用 — 作为兜底方案
-- 3. 分区级 UPSERT 是大数据场景的最佳实践（避免全表重写）
-- 4. MERGE 的原子性比 DELETE + INSERT 的非原子方案更安全
-- 5. ClickHouse ReplacingMergeTree 的异步去重是有趣的第三种方案
-- 6. LEFT ANTI JOIN 模拟 UPSERT 通常比 FULL OUTER JOIN 性能更好
