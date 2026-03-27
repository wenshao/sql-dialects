-- Trino (formerly PrestoSQL): 分页 (Pagination)
--
-- 参考资料:
--   [1] Trino SQL Reference - SELECT
--       https://trino.io/docs/current/sql/select.html
--   [2] Trino SQL Functions - Window Functions
--       https://trino.io/docs/current/functions/window.html
--   [3] Trino Connector Support Matrix
--       https://trino.io/docs/current/connector.html

-- ============================================================
-- 1. LIMIT（取前 N 行）
-- ============================================================

-- 仅取前 N 行
SELECT * FROM users ORDER BY id LIMIT 10;

-- 注意: Trino 的 LIMIT 在 ORDER BY 之后执行
-- 优化器可利用 Top-N 算子（Partial Top-N）减少排序开销
-- 每个 Worker 维护本地 Top-N 堆，Coordinator 合并取全局 Top-N

-- ============================================================
-- 2. LIMIT / OFFSET
-- ============================================================

-- 基本分页: 跳过前 20 行，取 10 行
SELECT * FROM users ORDER BY id LIMIT 10 OFFSET 20;

-- 注意: OFFSET 在分布式环境中的代价
--   每个 Worker 需要返回 offset + limit 行到 Coordinator
--   Coordinator 全局排序后跳过 offset 行，取 limit 行
--   网络传输量 = Worker 数 * (offset + limit) 行

-- ============================================================
-- 3. FETCH FIRST（SQL 标准语法）
-- ============================================================

-- SQL 标准 OFFSET / FETCH 语法
SELECT * FROM users ORDER BY id OFFSET 20 ROWS FETCH FIRST 10 ROWS ONLY;

-- FETCH NEXT（等价于 FETCH FIRST）
SELECT * FROM users ORDER BY id OFFSET 20 ROWS FETCH NEXT 10 ROWS ONLY;

-- 仅取前 N 行（标准语法）
SELECT * FROM users ORDER BY id FETCH FIRST 10 ROWS ONLY;

-- 注意: Trino 同时支持 LIMIT 和 FETCH FIRST，两者功能等价
--   LIMIT:     非标准但广泛使用的语法
--   FETCH FIRST: SQL 标准，推荐在跨引擎场景中使用

-- ============================================================
-- 4. OFFSET 的性能问题（MPP 架构特殊考量）
-- ============================================================

-- Trino 是 MPP (Massively Parallel Processing) 引擎:
--   OFFSET 在分布式环境中的代价比单机更高
--   假设 10 个 Worker，LIMIT 10 OFFSET 100000:
--     每个 Worker 返回 100010 行到 Coordinator
--     Coordinator 全局排序后取第 100001~100010 行
--     网络传输量: 10 * 100010 行
--
-- 实际性能还取决于底层连接器 (Connector):
--   Hive Connector:     需要从 HDFS 读取数据，OFFSET 开销大
--   MySQL Connector:    可下推 LIMIT OFFSET 到 MySQL
--   Iceberg Connector:  利用 Parquet 的 row group 跳过，稍好
--   Delta Lake Connector: 类似 Iceberg

-- ============================================================
-- 5. 键集分页（Keyset Pagination）: 高性能替代方案
-- ============================================================

-- 第一页
SELECT * FROM users ORDER BY id LIMIT 10;

-- 后续页（已知上一页最后一条 id = 100）
SELECT * FROM users WHERE id > 100 ORDER BY id LIMIT 10;
-- 时间复杂度: O(log n + limit)，与页码无关
-- 优势: 每个 Worker 只需返回 WHERE 条件匹配的行，大幅减少传输量

-- 多列排序的键集分页
SELECT * FROM users
WHERE (created_at, id) > (DATE '2025-01-01', 100)
ORDER BY created_at, id
LIMIT 10;
-- Trino 支持 ROW 值比较

-- ============================================================
-- 6. 窗口函数辅助分页
-- ============================================================

-- ROW_NUMBER 分页
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (ORDER BY id) AS rn
    FROM users
) t
WHERE rn BETWEEN 21 AND 30;

-- 分组后 Top-N
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY city ORDER BY age DESC) AS rn
    FROM users
) t WHERE rn <= 3;

-- 注意: 窗口函数方式需要计算所有行的 ROW_NUMBER
-- 在 Trino 的分布式执行中，窗口函数需要按分区键重分布数据

-- ============================================================
-- 7. TABLESAMPLE（近似采样，非精确分页）
-- ============================================================

-- 按百分比采样（不保证精确行数）
SELECT * FROM users TABLESAMPLE SYSTEM (10);
-- 返回约 10% 的行，适合探索性查询

-- 按 BERNOULLI 采样（每行独立采样，更均匀）
SELECT * FROM users TABLESAMPLE BERNOULLI (1);
-- 注意: 采样不是分页，但可用于大数据集的预览

-- ============================================================
-- 8. Trino 特有说明
-- ============================================================

-- Trino 的高度标准兼容性:
--   LIMIT / OFFSET:     支持
--   FETCH FIRST:        支持（SQL 标准）
--   FETCH NEXT:         支持（等价于 FETCH FIRST）
--   ROW 值比较:         支持（键集分页可用）
--   TABLESAMPLE:        支持（SYSTEM / BERNOULLI）
--
-- 连接器 (Connector) 对分页的影响:
--   分页查询的实际性能取决于底层连接器的实现
--   部分连接器支持 LIMIT 下推（Pushdown），减少数据传输
--   OFFSET 通常不会被下推（语义上需要全局排序后跳过）
--   键集分页的 WHERE 条件可以被连接器下推到存储层
--
-- Trino 不支持的功能:
--   DECLARE CURSOR:     不支持（Trino 是无状态的查询引擎）
--   TOP N:              不支持
--   LIMIT m, n:         不支持 MySQL 风格的简写
--   SQL_CALC_FOUND_ROWS: 不支持（MySQL 特有）

-- ============================================================
-- 9. 版本演进
-- ============================================================
-- Presto (原始):  LIMIT + FETCH FIRST，窗口函数
-- Trino 350+:    增强连接器的 LIMIT 下推能力
-- Trino 400+:    Iceberg 连接器的 row group 跳过优化
-- Trino 最新:    持续优化 Top-N 算子的分布式执行

-- ============================================================
-- 10. 横向对比: 分页语法差异
-- ============================================================

-- 语法对比:
--   Trino:       LIMIT n OFFSET m + FETCH FIRST（双重支持）
--   Presto:      LIMIT n OFFSET m + FETCH FIRST（同 Trino）
--   Spark SQL:   LIMIT n OFFSET m（不支持 FETCH FIRST，3.4+ 支持 OFFSET）
--   Hive:        LIMIT n OFFSET m（不支持 FETCH FIRST）
--
-- MPP 引擎分页对比:
--   Trino:       高度 SQL 标准兼容，连接器决定实际性能
--   Presto:      同 Trino（两者分页特性一致）
--   ClickHouse:  特有 LIMIT BY 语法，单机性能好
--   StarRocks:   MySQL 协议兼容，Top-N 优化更激进
