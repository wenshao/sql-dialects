-- StarRocks: 分页 (Pagination)
--
-- 参考资料:
--   [1] StarRocks SQL Reference - SELECT
--       https://docs.starrocks.io/docs/sql-reference/sql-statements/query/SELECT/
--   [2] StarRocks Query Optimization
--       https://docs.starrocks.io/docs/using_starrocks/optimization/
--   [3] StarRocks Window Functions
--       https://docs.starrocks.io/docs/sql-reference/sql-functions/window-functions/

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
-- 2. OFFSET 的性能问题（列存 + MPP 架构）
-- ============================================================

-- 单机场景: 与 MySQL 行为一致
--   OFFSET 100000 需要扫描 100010 行然后丢弃前 100000 行
--   时间复杂度: O(offset + limit)
--
-- MPP 分布式场景: 问题更严重
--   假设 3 个 BE（Backend），LIMIT 10 OFFSET 100000:
--     每个 BE 返回 100010 行到协调节点 (FE)
--     FE 全局排序后取第 100001~100010 行
--     网络传输量: 3 * 100010 行
--
-- 列存引擎的特殊考量:
--   StarRocks 使用列存引擎，OFFSET 需要解码向量
--   对于宽表（列数多），OFFSET 的代价更高

-- ============================================================
-- 3. 延迟关联优化（Deferred JOIN）
-- ============================================================

-- 原理: 先在索引上快速定位 ID，再用 ID 回表取完整数据
SELECT u.* FROM users u
JOIN (
    SELECT id FROM users ORDER BY created_at DESC LIMIT 10 OFFSET 100000
) AS t ON u.id = t.id;

-- StarRocks 中物化视图可以作为覆盖索引:
--   CREATE MATERIALIZED VIEW mv_created_id AS
--     SELECT created_at, id FROM users ORDER BY created_at DESC;
--   子查询可以直接命中物化视图，避免扫描基础表

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

-- ============================================================
-- 5. 窗口函数辅助分页
-- ============================================================

-- ROW_NUMBER 分页
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (ORDER BY id) AS rn
    FROM users
) t
WHERE rn BETWEEN 21 AND 30;

-- QUALIFY + ROW_NUMBER 分页（StarRocks 3.2+，更简洁）
SELECT * FROM users
QUALIFY ROW_NUMBER() OVER (ORDER BY id) BETWEEN 21 AND 30;
-- QUALIFY 语法源自 Snowflake，StarRocks 3.2 引入

-- 分组后 Top-N
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY city ORDER BY age DESC) AS rn
    FROM users
) t WHERE rn <= 3;

-- ============================================================
-- 6. StarRocks 特有说明
-- ============================================================

-- StarRocks 兼容 MySQL 协议，分页特性:
--   LIMIT / OFFSET:     支持（MySQL 兼容）
--   LIMIT m, n:         支持（MySQL 简写）
--   FETCH FIRST:        不支持（非 MySQL 标准）
--   TOP N:              不支持
--   QUALIFY:            3.2+ 支持
--
-- 优化器特性:
--   Top-N 优化: ORDER BY + LIMIT 自动转换为 Top-N 算子
--   LIMIT 下推: 将 LIMIT 下推到 Scan 节点（减少数据传输）
--   Pipeline 执行引擎: 流式处理，LIMIT 到达即停止
--   Colocate JOIN: 如果分页涉及 JOIN，Colocate 可避免数据移动
--
-- 物化视图加速分页:
--   创建排序键和主键的物化视图，可作为覆盖索引用于延迟关联
--   物化视图自动透明重写（Query Rewrite），无需修改 SQL

-- ============================================================
-- 7. 版本演进
-- ============================================================
-- StarRocks 1.x:  LIMIT / OFFSET（MySQL 兼容），窗口函数分页
-- StarRocks 2.x:  Pipeline 执行引擎，LIMIT 下推优化
-- StarRocks 3.0:  物化视图透明重写增强
-- StarRocks 3.2:  QUALIFY 语法支持

-- ============================================================
-- 8. 横向对比: 分页语法差异
-- ============================================================

-- 语法对比:
--   StarRocks:   LIMIT n OFFSET m / LIMIT m, n（MySQL 兼容）
--   MySQL:       LIMIT n OFFSET m / LIMIT m, n（StarRocks 的协议基础）
--   Doris:       LIMIT n OFFSET m / LIMIT m, n（MySQL 兼容）
--   ClickHouse:  LIMIT n OFFSET m（不支持 LIMIT m, n 简写）
--
-- MPP 列存引擎分页对比:
--   StarRocks:  Pipeline 引擎 + Top-N 优化 + 物化视图加速
--   Doris:      类似架构，Top-N 优化
--   ClickHouse: 特有 LIMIT BY 语法（分组取前 N）
--   Trino:      MPP 架构，但不支持 LIMIT m, n
