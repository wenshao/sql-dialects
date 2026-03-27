-- Snowflake: 分页 (Pagination)
--
-- 参考资料:
--   [1] Snowflake SQL Reference - SELECT (LIMIT/OFFSET)
--       https://docs.snowflake.com/en/sql-reference/sql/select
--   [2] Snowflake SQL Reference - TOP
--       https://docs.snowflake.com/en/sql-reference/constructs/top
--   [3] Snowflake SQL Reference - QUALIFY
--       https://docs.snowflake.com/en/sql-reference/constructs/qualify
--   [4] Snowflake Window Functions
--       https://docs.snowflake.com/en/sql-reference/functions/window

-- ============================================================
-- 1. LIMIT / OFFSET（传统分页）
-- ============================================================

-- 基本分页: 跳过前 20 行，取 10 行
SELECT * FROM users ORDER BY id LIMIT 10 OFFSET 20;

-- 仅取前 N 行
SELECT * FROM users ORDER BY id LIMIT 10;

-- 带总行数的分页（一次查询获取数据和总数）
SELECT *, COUNT(*) OVER() AS total_count
FROM users ORDER BY id LIMIT 10 OFFSET 20;

-- ============================================================
-- 2. FETCH FIRST（SQL 标准语法）
-- ============================================================

-- SQL 标准 OFFSET / FETCH 语法
SELECT * FROM users ORDER BY id OFFSET 20 ROWS FETCH FIRST 10 ROWS ONLY;

-- FETCH NEXT（等价于 FETCH FIRST）
SELECT * FROM users ORDER BY id OFFSET 20 ROWS FETCH NEXT 10 ROWS ONLY;

-- 仅取前 N 行（标准语法）
SELECT * FROM users ORDER BY id FETCH FIRST 10 ROWS ONLY;

-- ============================================================
-- 3. TOP 语法
-- ============================================================

-- TOP N（等价于 LIMIT N）
SELECT TOP 10 * FROM users ORDER BY id;

-- 注意: TOP 不支持 OFFSET，如需跳过行请使用 LIMIT OFFSET 或 FETCH FIRST

-- ============================================================
-- 4. OFFSET 的性能问题（云端分布式架构）
-- ============================================================

-- Snowflake 的多层缓存架构:
--   RESULT_CACHE:  相同查询 24 小时内可命中结果缓存
--   WAREHOUSE_CACHE: 本地 SSD 缓存（微分区数据）
--   REMOTE_STORAGE:  S3/Azure Blob/GCS（云端对象存储）
--
-- OFFSET 在 Snowflake 中的执行:
--   1. 扫描微分区（Micro Partition）获取数据
--   2. 排序后跳过 OFFSET 行
--   3. 返回 LIMIT 行
--   时间复杂度: O(offset + limit)
--   但得益于云端弹性计算，可以快速扩展 Warehouse 来加速
--
-- RESULT_CACHE 对分页的特殊影响:
--   重复的分页查询（相同参数）可直接命中缓存，响应时间 < 100ms
--   但不同页码的查询是不同的 SQL 文本，无法共享缓存

-- ============================================================
-- 5. 键集分页（Keyset Pagination）: 高性能替代方案
-- ============================================================

-- 第一页
SELECT * FROM users ORDER BY id LIMIT 10;

-- 后续页（已知上一页最后一条 id = 100）
SELECT * FROM users WHERE id > 100 ORDER BY id LIMIT 10;
-- 优势: 可利用微分区裁剪（Micro Partition Pruning）
--   Snowflake 的微分区包含 MIN/MAX 统计信息
--   WHERE id > 100 可跳过 id 最大值 <= 100 的微分区

-- 多列排序的键集分页
SELECT * FROM users
WHERE (created_at, id) > ('2025-01-01', 100)
ORDER BY created_at, id
LIMIT 10;

-- ============================================================
-- 6. QUALIFY 分页（Snowflake 特有，推荐）
-- ============================================================

-- QUALIFY + ROW_NUMBER 分页（最简洁的写法）
SELECT * FROM users
QUALIFY ROW_NUMBER() OVER (ORDER BY id) BETWEEN 21 AND 30;
-- QUALIFY 在 HAVING 之后、ORDER BY 之前执行
-- 无需子查询包装，语法更简洁

-- QUALIFY + 分组 Top-N
SELECT * FROM users
QUALIFY ROW_NUMBER() OVER (PARTITION BY city ORDER BY age DESC) <= 3;

-- 注意: QUALIFY 是 Snowflake 的独有语法（StarRocks 3.2+ 也已引入）

-- ============================================================
-- 7. 窗口函数辅助分页
-- ============================================================

-- ROW_NUMBER 分页（传统子查询方式）
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (ORDER BY id) AS rn
    FROM users
) t
WHERE rn BETWEEN 21 AND 30;

-- 分组后 Top-N
SELECT * FROM (
    SELECT username, city, age,
        ROW_NUMBER() OVER (PARTITION BY city ORDER BY age DESC) AS rn
    FROM users
) t WHERE rn <= 3;

-- ============================================================
-- 8. Snowflake 特有说明
-- ============================================================

-- Snowflake 的分页特性:
--   LIMIT / OFFSET:     支持
--   FETCH FIRST:        支持（SQL 标准）
--   TOP N:              支持
--   QUALIFY:            支持（独有特性，推荐使用）
--   RESULT_CACHE:       重复查询自动缓存
--
-- 云端架构的分页优化:
--   弹性 Warehouse: 可根据分页负载自动扩展/缩减
--   挂起 (Suspend): 无查询时自动挂起，节省成本
--   多集群 Warehouse: 高并发分页查询自动扩展集群
--
-- Snowflake 不支持的功能:
--   DECLARE CURSOR:     不支持（Snowflake 是无状态查询引擎）
--   LIMIT m, n:         不支持 MySQL 风格的简写
--   WITH TIES:          不支持（FETCH FIRST ... WITH TIES）
--
-- 微分区裁剪 (Micro Partition Pruning):
--   Snowflake 自动将数据组织为微分区（约 50-500 MB）
--   每个微分区维护列级 MIN/MAX 统计信息
--   键集分页的 WHERE 条件可触发分区裁剪，大幅减少 I/O

-- ============================================================
-- 9. 版本演进
-- ============================================================
-- Snowflake 早期:  LIMIT / OFFSET + FETCH FIRST + TOP + QUALIFY
-- Snowflake 持续:  微分区裁剪优化、RESULT_CACHE 增强
-- Snowflake 最新:  搜索优化服务 (Search Optimization Service)
--                  对点查和范围查询加速，间接提升键集分页性能

-- ============================================================
-- 10. 横向对比: 分页语法差异
-- ============================================================

-- 语法对比:
--   Snowflake:   LIMIT n OFFSET m + FETCH FIRST + TOP + QUALIFY（语法最丰富）
--   BigQuery:    LIMIT n OFFSET m + FETCH FIRST（不支持 TOP 和 QUALIFY）
--   Redshift:    LIMIT n OFFSET m（不支持 FETCH FIRST）
--   Databricks:  LIMIT n OFFSET m + FETCH FIRST（Spark SQL 兼容）
--
-- 云数仓分页对比:
--   Snowflake:   RESULT_CACHE + 微分区裁剪 + 弹性 Warehouse
--   BigQuery:    无缓存（全量扫描计费），分页成本高
--   Redshift:    列存 + 区域排序 (Z-Order)，分页性能取决于排序键
--   Databricks:  Liquid Clustering + Data Skipping，类似微分区裁剪
