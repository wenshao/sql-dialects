-- Snowflake: 分区策略（自动微分区 + 聚簇键）
--
-- 参考资料:
--   [1] Snowflake Documentation - Micro-Partitions & Clustering
--       https://docs.snowflake.com/en/user-guide/tables-clustering-micropartitions
--   [2] Snowflake Documentation - Clustering Keys
--       https://docs.snowflake.com/en/user-guide/tables-clustering-keys

-- ============================================================
-- 1. 核心概念: 微分区 (Micro-Partitions)
-- ============================================================

-- Snowflake 不使用传统的手动分区（RANGE/LIST/HASH）。
-- 所有表的数据自动分成 50-500 MB 的不可变微分区。
-- 每个微分区是一个列存文件，存储在云对象存储 (S3/Blob/GCS) 上。

CREATE TABLE orders (
    id         NUMBER,
    user_id    NUMBER,
    amount     NUMBER(10,2),
    order_date DATE
);
-- 无需指定任何分区方式 —— 数据自动组织

-- 查询时自动进行分区裁剪:
SELECT * FROM orders WHERE order_date = '2024-06-15';
-- 优化器检查每个微分区的 order_date MIN/MAX 元数据
-- 如果某分区的 [MIN, MAX] 范围不包含 '2024-06-15'，直接跳过

-- ============================================================
-- 2. 语法设计分析（对 SQL 引擎开发者）
-- ============================================================

-- 2.1 为什么不支持手动分区
-- 传统分区（如 MySQL PARTITION BY RANGE, Oracle INTERVAL 分区）
-- 需要用户预先定义分区策略，这有几个问题:
--   (a) 用户需要了解数据分布才能选择好的分区键
--   (b) 分区边界需要提前规划（MAXVALUE / 自动扩展）
--   (c) 分区键选择不当导致数据倾斜
--   (d) 分区维护（增加/合并/拆分）是 DBA 的持续负担
--
-- Snowflake 的自动微分区消除了所有这些问题:
--   (a) 数据按插入顺序自动分成 50-500 MB 的块
--   (b) 每个微分区记录列级 MIN/MAX/NDV/NULL_COUNT
--   (c) 查询时自动利用统计信息做分区裁剪
--   (d) 用户只需关注 CLUSTER BY 提示（可选）
--
-- 对比:
--   MySQL:       PARTITION BY RANGE/LIST/HASH（分区键必须在 PK 中）
--   PostgreSQL:  声明式分区（10+），手动管理分区
--   Oracle:      INTERVAL/RANGE/LIST/HASH 分区（功能最丰富）
--   BigQuery:    PARTITION BY DATE/TIMESTAMP/INT（手动指定但维护自动）
--   Redshift:    无显式分区（SORTKEY 类似 CLUSTER BY）
--   Databricks:  PARTITIONED BY（Hive 风格目录级分区）
--   MaxCompute:  PARTITIONED BY（与 Hive 一致）
--
-- 对引擎开发者的启示:
--   自动分区 vs 手动分区是"易用性 vs 控制力"的权衡。
--   Snowflake 和 BigQuery 证明了自动管理在数仓场景下是可行的。
--   但对于已知固定查询模式（如按日期的时序查询），手动分区
--   可能比自动微分区的裁剪效果更好（分区边界精确对齐查询条件）。

-- 2.2 微分区的不可变性: 架构基石
-- 每个微分区一旦写入就不可变（immutable）:
--   INSERT: 创建新的微分区
--   UPDATE: 读取旧分区 → 生成含修改数据的新分区 → 原子替换元数据
--   DELETE: 生成不含被删行的新分区 → 原子替换
--
-- 不可变性带来的好处:
--   (a) Time Travel: 旧分区保留，可回溯任意时间点
--   (b) CLONE: 共享分区指针即可，零拷贝
--   (c) 并发安全: 读操作永远读到一致的分区集合
--   (d) 增量刷新: 只需追踪新增/替换的分区
--
-- 这与 Delta Lake / Apache Iceberg 的设计理念一致。

-- ============================================================
-- 3. 聚簇键 (Clustering Keys)
-- ============================================================

-- 聚簇键控制微分区内数据的物理排列顺序
-- 当数据按聚簇键排列时，分区裁剪效果最好

CREATE TABLE events (
    event_id   NUMBER,
    event_time TIMESTAMP_NTZ,
    user_id    NUMBER,
    event_type VARCHAR(50)
) CLUSTER BY (event_time::DATE);
-- 表达式聚簇: event_time 截断为日期

-- 多列聚簇:
CREATE TABLE sales (
    id      NUMBER,
    dt      DATE,
    region  VARCHAR(20),
    amount  NUMBER(10,2)
) CLUSTER BY (dt, region);
-- 列顺序影响优先级: dt 先排列，region 次之

-- 动态管理:
ALTER TABLE orders CLUSTER BY (order_date);
ALTER TABLE orders DROP CLUSTERING KEY;

-- ============================================================
-- 4. 聚簇监控与维护
-- ============================================================

-- 查看聚簇质量:
SELECT SYSTEM$CLUSTERING_INFORMATION('events');
-- 返回 JSON: average_depth, average_overlap, total_partitions
-- clustering_depth 越小越好（理想值 1 = 分区值域不重叠）

SELECT SYSTEM$CLUSTERING_DEPTH('events');
-- 返回单个数值: 聚簇深度

-- 控制自动聚簇:
ALTER TABLE events SUSPEND RECLUSTER;      -- 暂停（节省计算成本）
ALTER TABLE events RESUME RECLUSTER;       -- 恢复

-- 自动聚簇的工作方式:
--   Snowflake 在后台持续监控表的聚簇质量
--   当质量下降到阈值以下时，自动触发重聚簇
--   重聚簇是读取旧分区 → 按聚簇键排序 → 写入新分区
--   按 credit 计费（Automatic Clustering Service）

-- 查看分区裁剪效果:
SELECT query_id, partitions_scanned, partitions_total,
       bytes_scanned
FROM snowflake.account_usage.query_history
WHERE query_text LIKE '%orders%'
ORDER BY start_time DESC
LIMIT 10;

-- ============================================================
-- 5. 聚簇键选择的最佳实践
-- ============================================================
-- (a) 选择 WHERE 子句最常用的过滤列
-- (b) 选择基数适中的列（太低无区分度，太高聚簇无效）
-- (c) 日期/时间列几乎总是好的候选
-- (d) 不超过 3-4 列（过多列增加维护成本）
-- (e) 小表（< 1GB）通常不需要聚簇键

-- ============================================================
-- 6. Search Optimization Service (Enterprise+)
-- ============================================================

-- 为等值和子字符串查询创建后台加速结构
ALTER TABLE orders ADD SEARCH OPTIMIZATION ON EQUALITY(user_id);
ALTER TABLE orders ADD SEARCH OPTIMIZATION ON SUBSTRING(username);
ALTER TABLE orders ADD SEARCH OPTIMIZATION ON GEO(location);

ALTER TABLE orders DROP SEARCH OPTIMIZATION ON EQUALITY(user_id);

-- 对比传统索引:
--   索引: 用户创建、用户命名、用户维护
--   SOS:  用户指定查询类型，系统自动管理结构
--   SOS 适合高基数列的点查询（UUID、email 等）

-- ============================================================
-- 横向对比: 分区与数据组织策略
-- ============================================================
-- 引擎       | 分区方式          | 维护        | 裁剪机制
-- Snowflake  | 自动微分区        | 全自动      | MIN/MAX 元数据裁剪
-- BigQuery   | 手动 PARTITION BY | 自动维护    | 分区裁剪 + 聚簇
-- Redshift   | SORTKEY (无分区)  | 需VACUUM    | Zone maps
-- Databricks | PARTITIONED BY    | 需OPTIMIZE  | 数据跳过+ZORDER
-- MySQL      | RANGE/LIST/HASH   | 手动管理    | 分区裁剪
-- PostgreSQL | 声明式分区        | 手动管理    | 分区裁剪+约束排除
-- Oracle     | INTERVAL/RANGE等  | 自动扩展    | 分区裁剪+Exadata Smart Scan
--
-- 对引擎开发者的启示:
--   微分区 + 统计元数据的"稀疏索引"策略已被 Delta Lake / Iceberg 验证。
--   关键实现: 写入时必须同步更新统计信息，延迟更新导致裁剪失效。
--   自动聚簇是差异化竞争力: BigQuery 和 Snowflake 自动维护，
--   Redshift 需要 VACUUM SORT，Databricks 需要手动 OPTIMIZE。
