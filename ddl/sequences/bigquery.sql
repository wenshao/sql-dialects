-- BigQuery: Sequences & Auto-Increment
--
-- 参考资料:
--   [1] BigQuery SQL Reference - GENERATE_UUID
--       https://cloud.google.com/bigquery/docs/reference/standard-sql/functions-and-operators#generate_uuid
--   [2] BigQuery Documentation - Data Definition Language
--       https://cloud.google.com/bigquery/docs/reference/standard-sql/data-definition-language
--   [3] BigQuery Architecture - Dremel Paper
--       https://research.google/pubs/pub36632/

-- ============================================================
-- 1. 为什么 BigQuery 不支持 SEQUENCE / AUTO_INCREMENT
-- ============================================================

-- BigQuery 没有 SEQUENCE、AUTO_INCREMENT、IDENTITY 或 SERIAL。
-- 这是无服务器分布式架构的必然结果:
--
-- (a) 无状态计算:
--     BigQuery 的计算节点（slot）是临时分配的。
--     没有持久化的"服务器进程"来维护序列计数器。
--     每次查询/DML 分配不同的 slot，无法在 slot 之间共享序列状态。
--
-- (b) 分布式写入:
--     一次 INSERT 可能被分配到多个 slot 并行执行。
--     全局自增需要 slot 之间的协调（分布式锁/共识），增加延迟。
--     BigQuery 的设计目标是高吞吐批量写入，不是低延迟单行写入。
--
-- (c) DML 配额限制:
--     每个表每天最多 1500 次 DML 操作（INSERT/UPDATE/DELETE/MERGE）。
--     每次 DML 有最少 10 秒的冷却时间。
--     在这种限制下，逐行 INSERT + AUTO_INCREMENT 没有意义。
--     BigQuery 的数据加载应使用批量 LOAD 或 Streaming API。
--
-- (d) 设计哲学:
--     BigQuery 认为唯一标识应该在数据进入之前（ETL 管道中）生成。
--     数据库只负责存储和查询，不负责生成业务 ID。
--
-- 对比:
--   Snowflake: 支持 AUTOINCREMENT / IDENTITY（但值不保证连续）
--   Redshift:  支持 IDENTITY（但在分布式环境中可能不连续）
--   Databricks: 不支持自增（与 BigQuery 相同理由）

-- ============================================================
-- 2. GENERATE_UUID(): 推荐的唯一标识方案
-- ============================================================

-- 使用 DEFAULT 自动生成 UUID
CREATE TABLE users (
    id         STRING NOT NULL DEFAULT GENERATE_UUID(),
    username   STRING NOT NULL,
    email      STRING NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
);

-- 插入时自动生成 UUID
INSERT INTO users (username, email) VALUES ('alice', 'alice@e.com');
-- id = '7f1b7e42-3a1c-4b5d-8f2e-9c0d1e2f3a4b'

-- 在 SELECT 中使用
SELECT GENERATE_UUID() AS new_id;

-- CTAS 中使用
CREATE TABLE users_with_id AS
SELECT GENERATE_UUID() AS id, * FROM staging_users;

-- 注意: GENERATE_UUID() 生成 RFC 4122 v4 UUID（随机）
-- UUID 是 STRING 类型（不是专用 UUID 类型）
-- → BigQuery 没有 UUID 数据类型，使用 STRING 存储
-- → 对比 ClickHouse: 有专用 UUID 类型（128-bit 固定大小，比 STRING 高效）
-- → 对比 PostgreSQL: 有专用 uuid 类型

-- ============================================================
-- 3. 其他唯一标识替代方案
-- ============================================================

-- 方法 1: ROW_NUMBER() 生成查询时序号（非持久化）
SELECT
    ROW_NUMBER() OVER (ORDER BY created_at) AS row_id,
    username, email
FROM users;

-- 方法 2: FARM_FINGERPRINT 生成确定性哈希 ID
-- 相同输入总是产生相同的 64 位整数
INSERT INTO users (id, username, email)
SELECT
    CAST(FARM_FINGERPRINT(CONCAT(username, email)) AS STRING),
    username, email
FROM staging_users;
-- 用途: 幂等写入（重复执行不产生新 ID）
-- 风险: 哈希碰撞（64 位空间，10 亿行约 0.0000001% 碰撞率）

-- 方法 3: CTAS + ROW_NUMBER 为存量数据编号
CREATE OR REPLACE TABLE users_numbered AS
SELECT
    ROW_NUMBER() OVER (ORDER BY created_at) AS id,
    username, email, created_at
FROM users;

-- 方法 4: 时间戳拼接随机数
SELECT
    CONCAT(
        FORMAT_TIMESTAMP('%Y%m%d%H%M%S', CURRENT_TIMESTAMP()),
        CAST(CAST(RAND() * 1000000 AS INT64) AS STRING)
    ) AS custom_id;

-- ============================================================
-- 4. Streaming API 中的去重
-- ============================================================

-- BigQuery Streaming API（实时写入）支持 insertId 去重:
-- 每行可以指定一个 insertId，相同 insertId 的重复行会被去重。
-- 但去重窗口有限（约 1 分钟），不是严格保证。
--
-- 这进一步证明 BigQuery 的设计: 唯一性由客户端保证，而非数据库。

-- ============================================================
-- 5. 为什么 UUID 比自增 ID 更适合 BigQuery
-- ============================================================

-- (a) 无热点: UUID 随机分布，不会导致写入集中到某个分区
--     自增 ID 会导致"最新分区"成为写入热点
-- (b) 无协调: 每个 slot 独立生成 UUID，不需要全局同步
-- (c) 分布式友好: UUID 在 ETL 管道的任何阶段都可以生成
-- (d) 合并安全: 多个数据源的 UUID 自然不冲突
--
-- 唯一的缺点: UUID 是 STRING 类型，比 INT64 大（36 字节 vs 8 字节）
-- 在 BigQuery 的列式压缩下，这个差异被大幅缩小。

-- ============================================================
-- 6. 对比与引擎开发者启示
-- ============================================================
-- BigQuery 不支持自增的核心原因:
--   无服务器 + 分布式 + 批量写入 → 没有维护全局序列的基础设施
--
-- 对引擎开发者的启示:
--   (1) 云原生数仓应该提供 UUID 函数而非 SEQUENCE
--   (2) 唯一标识的生成应该是无协调的（UUID / Snowflake ID）
--   (3) 如果必须提供 IDENTITY 列（如 Snowflake），明确文档说明不保证连续
--   (4) DML 配额限制使得逐行 INSERT 不可行 → 自增 ID 在这种模型下无意义
--   (5) 考虑提供 FARM_FINGERPRINT 类的确定性哈希函数
--       作为 UUID 的补充（支持幂等写入场景）
