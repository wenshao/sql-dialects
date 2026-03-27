-- TDSQL: 分页 (Pagination)
-- TDSQL 分布式 MySQL 兼容语法。
--
-- 参考资料:
--   [1] TDSQL-C MySQL 版文档
--       https://cloud.tencent.com/document/product/1003
--   [2] TDSQL MySQL 版文档
--       https://cloud.tencent.com/document/product/557
--   [3] TDSQL SQL 兼容性说明
--       https://cloud.tencent.com/document/product/557/51107

-- ============================================================
-- 1. LIMIT / OFFSET（MySQL 兼容语法）
-- ============================================================

-- LIMIT count OFFSET offset（推荐写法，语义清晰）
SELECT * FROM users ORDER BY id LIMIT 10 OFFSET 20;

-- 简写: LIMIT offset, count（注意: offset 在前、count 在后）
SELECT * FROM users ORDER BY id LIMIT 20, 10;

-- 仅限制行数
SELECT * FROM users ORDER BY id LIMIT 10;

-- 带总行数的分页查询
SELECT *, COUNT(*) OVER() AS total_count
FROM users
ORDER BY id
LIMIT 10 OFFSET 20;

-- ============================================================
-- 2. OFFSET 的性能问题（分布式环境尤为严重）
-- ============================================================

-- 单机 TDSQL-C: 与 MySQL 行为一致
--   OFFSET 100000 需要扫描 100010 行然后丢弃前 100000 行
--   时间复杂度: O(offset + limit)
--
-- 分布式 TDSQL: 问题更严重
--   假设 N 个分片（Set），LIMIT 10 OFFSET 100000:
--     每个分片返回 100010 行到网关层（Gateway）
--     网关全局排序后取第 100001~100010 行
--     网络传输量: N * 100010 行（而非 10 行）
--
-- TDSQL 的 ShardKey 机制对分页的影响:
--   如果查询条件包含 shardkey，查询只路由到目标分片
--   此时 OFFSET 的代价等同于单机 MySQL

-- ============================================================
-- 3. 延迟关联优化（Deferred JOIN）
-- ============================================================

-- 原理: 先在索引上快速定位 ID，再用 ID 回表取完整数据
SELECT u.* FROM users u
JOIN (
    SELECT id FROM users ORDER BY created_at DESC LIMIT 10 OFFSET 100000
) AS t ON u.id = t.id;

-- 前提条件:
--   CREATE INDEX idx_created_id ON users (created_at DESC, id);

-- ============================================================
-- 4. 键集分页（Keyset Pagination）: 高性能替代方案
-- ============================================================

-- 第一页
SELECT * FROM users ORDER BY id LIMIT 10;

-- 后续页（已知上一页最后一条 id = 100）
SELECT * FROM users WHERE id > 100 ORDER BY id LIMIT 10;
-- 时间复杂度: O(log n + limit)，与页码无关

-- 多列排序的键集分页（created_at DESC, id DESC）
SELECT * FROM users
WHERE (created_at, id) < ('2025-01-15', 42)
ORDER BY created_at DESC, id DESC
LIMIT 10;

-- 推荐: 使用 shardkey 作为排序键
-- 如果 id 是 shardkey，键集分页查询只路由到特定分片
SELECT * FROM users WHERE id > 100 ORDER BY id LIMIT 10;

-- ============================================================
-- 5. 窗口函数辅助分页
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

-- ============================================================
-- 6. TDSQL 特有说明
-- ============================================================

-- TDSQL 的分页相关特性:
--   完全兼容 MySQL 分页语法（LIMIT / OFFSET）
--   窗口函数支持与 MySQL 8.0 一致
--   不支持 FETCH FIRST ... ROWS ONLY 标准语法
--   不支持 TOP N 语法
--
-- ShardKey 与分页的最佳实践:
--   推荐: 将分页查询的排序键设为 shardkey
--   带 shardkey 条件的分页查询只路由到对应分片
--   示例: 如果 user_id 是 shardkey:
--     SELECT * FROM orders WHERE user_id = 42 ORDER BY id LIMIT 10 OFFSET 20;
--     -- 只路由到 user_id = 42 所在的分片
--
-- TDSQL-C (CynosDB) 与 TDSQL 的区别:
--   TDSQL-C:  云原生架构（共享存储），单机兼容 MySQL，分页行为同 MySQL
--   TDSQL:    分布式架构（分片），分页需考虑跨分片问题

-- ============================================================
-- 7. 版本演进
-- ============================================================
-- TDSQL MySQL 5.6 兼容:  LIMIT / OFFSET 基本分页
-- TDSQL MySQL 8.0 兼容:  窗口函数、降序索引、行构造器比较
-- TDSQL-C:               云原生 MySQL 兼容，单机分页行为同 MySQL

-- ============================================================
-- 8. 横向对比: 分页语法差异
-- ============================================================

-- 语法对比:
--   TDSQL:       LIMIT n OFFSET m / LIMIT m, n（MySQL 兼容）
--   MySQL:       LIMIT n OFFSET m / LIMIT m, n（TDSQL 的上游）
--   PolarDB-X:   LIMIT n OFFSET m（MySQL 兼容，分布式）
--   GaussDB:     LIMIT n OFFSET m + FETCH FIRST（PG 兼容）
--
-- 分布式分页对比:
--   TDSQL:      shardkey 路由优化，可减少跨分片查询
--   PolarDB-X:  协调节点全局排序，支持 LIMIT 下推优化
--   TiDB:       类似架构，全局排序后取 LIMIT
