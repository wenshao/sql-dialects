-- Spark SQL: Sequences & Auto-Increment (序列与自增)
--
-- 参考资料:
--   [1] Spark SQL - Built-in Functions
--       https://spark.apache.org/docs/latest/sql-ref-functions-builtin.html
--   [2] Spark SQL - monotonically_increasing_id
--       https://spark.apache.org/docs/latest/api/sql/index.html#monotonically_increasing_id

-- ============================================================
-- 1. 核心设计: Spark SQL 没有自增机制
-- ============================================================

-- Spark SQL 不支持 SEQUENCE、AUTO_INCREMENT、IDENTITY、SERIAL。
-- 这不是设计缺陷，而是分布式批处理引擎的必然选择:
--
-- 为什么分布式系统不适合全局自增?
--   1. 全局自增需要中央协调器（单点瓶颈），与分布式并行写入矛盾
--   2. 批处理场景中数据通常已有业务键（order_id, user_id 等）
--   3. 自增 ID 的"连续性"在批量加载时没有实际意义
--   4. Spark 的写入是并行的——多个 Executor 同时写入不同分区文件
--
-- 对比各引擎的自增策略:
--   MySQL:      AUTO_INCREMENT（单机全局锁，简单但不适合分布式）
--   PostgreSQL: SEQUENCE（独立对象）/ IDENTITY（SQL 标准）
--   BigQuery:   无自增（设计哲学: 分布式系统不应依赖全局自增序列）
--   Snowflake:  AUTOINCREMENT（值不保证连续，因为分布式执行）
--   ClickHouse: 无自增（分析型引擎，ID 应在应用层生成）
--   Hive:       无自增（与 Spark 同理）
--   Flink SQL:  无自增（流处理，数据无序到达）
--   TiDB:       AUTO_INCREMENT（兼容 MySQL）+ AUTO_RANDOM（分布式推荐）
--   MaxCompute: 无自增
--
-- 对引擎开发者的启示:
--   如果你的引擎面向批处理/分析场景，不需要实现自增——推荐 UUID 或业务键。
--   如果需要 MySQL 兼容，可以参考 TiDB 的段分配方案（每个节点预分配一段 ID）。
--   如果需要全局排序键，考虑 Snowflake 的做法——允许不连续但保证唯一。

-- ============================================================
-- 2. 替代方案一: monotonically_increasing_id()
-- ============================================================

SELECT
    monotonically_increasing_id() AS id,
    username,
    email
FROM users;

-- 实现原理:
--   返回值 = partition_id * 2^33 + partition 内自增序号
--   保证: 全局唯一、单调递增（在同一分区内连续，跨分区不连续）
--   不保证: 连续性——partition 0 的 ID 可能是 0,1,2，partition 1 是 8589934592,...
--
-- 适用场景: 需要唯一 ID 但不要求连续
-- 不适用: 需要连续整数序列（如行号）

-- CTAS 使用 monotonically_increasing_id
CREATE TABLE users_with_id USING DELTA AS
SELECT
    monotonically_increasing_id() AS id,
    username, email, created_at
FROM staging_users;

-- ============================================================
-- 3. 替代方案二: ROW_NUMBER() 窗口函数
-- ============================================================

SELECT
    ROW_NUMBER() OVER (ORDER BY created_at) AS row_id,
    username,
    email
FROM users;

-- 优点: 生成严格连续的整数序列
-- 缺点: ORDER BY 要求全局排序——数据量大时非常昂贵（单个分区完成排序）
--        这在本质上等于 spark.sql.shuffle.partitions = 1

-- ============================================================
-- 4. 替代方案三: UUID
-- ============================================================

SELECT
    uuid() AS id,
    username,
    email
FROM users;

-- UUID 的优势:
--   1. 完全分布式安全——每个 Executor 独立生成，无需协调
--   2. 无性能开销——不需要 Shuffle 或全局排序
--   3. 全局唯一性极高（128-bit 随机，碰撞概率可忽略）
--
-- UUID 的劣势:
--   1. 字符串类型（36 字节），比 BIGINT（8 字节）占用更多存储和索引空间
--   2. 不可排序（随机性导致无法按 ID 范围查询）
--   3. 可读性差（调试时不如整数 ID 直观）
--
-- 对比: BigQuery 和 Spanner 都推荐 UUID 作为主键（GENERATE_UUID()）

-- ============================================================
-- 5. 替代方案四: zipWithIndex（DataFrame API）
-- ============================================================

-- 仅在 Spark API 中可用（非 SQL）:
-- df.rdd.zipWithIndex().map(lambda row_idx: ...)
--
-- 优点: 严格连续的 0-based 索引
-- 缺点: 需要额外一次数据传递（RDD 操作），不能在纯 SQL 中使用

-- ============================================================
-- 6. 实战建议
-- ============================================================

-- 场景 1: ETL 批量加载，需要唯一 ID
-- 推荐: monotonically_increasing_id()（最快，无 Shuffle）

-- 场景 2: 需要连续行号用于报表
-- 推荐: ROW_NUMBER() OVER (ORDER BY some_column)

-- 场景 3: 分布式写入，需要全局唯一标识
-- 推荐: uuid()（无协调开销）

-- 场景 4: 数据已有业务键（order_id, user_id）
-- 推荐: 直接使用业务键，不需要额外生成 ID

-- 场景 5: 需要严格连续且从 1 开始
-- 推荐: zipWithIndex（DataFrame API）或 ROW_NUMBER()

-- ============================================================
-- 7. 版本演进
-- ============================================================
-- Spark 1.0: monotonically_increasing_id()（最早的替代方案）
-- Spark 2.0: uuid()（随机 UUID 生成）
-- Spark 2.4: 高阶函数增强
-- Spark 3.4: DEFAULT 列值（支持 CURRENT_TIMESTAMP 等简单默认值）
--
-- 限制:
--   不支持 CREATE SEQUENCE / ALTER SEQUENCE / DROP SEQUENCE
--   不支持 AUTO_INCREMENT / IDENTITY / SERIAL / GENERATED AS IDENTITY
--   monotonically_increasing_id() 的值在重新计算时可能变化（非确定性函数）
--   ROW_NUMBER() 生成连续 ID 需要全局排序（大数据集上性能差）
