-- Apache Doris: 分页 (Pagination)
--
-- 参考资料:
--   [1] Apache Doris SQL Manual - SELECT
--       https://doris.apache.org/docs/sql-manual/sql-statements/Data-Manipulation-Statements/SELECT/
--   [2] Apache Doris Query Optimization
--       https://doris.apache.org/docs/query/optimization/
--   [3] Apache Doris Window Functions
--       https://doris.apache.org/docs/sql-manual/sql-functions/window-functions/

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
--   Doris 使用列存引擎，OFFSET 需要解码向量
--   对于宽表（列数多），OFFSET 的代价更高
--   建议: 大数据量使用键集分页替代 OFFSET

-- ============================================================
-- 3. Top-N 查询优化
-- ============================================================

-- ORDER BY + LIMIT 自动触发 Top-N 优化
SELECT * FROM users ORDER BY created_at DESC LIMIT 10;
-- 优化器会使用堆排序（Heap Sort）代替全量排序
-- 只维护一个大小为 N 的堆，复杂度从 O(M*logM) 降低到 O(M*logN)

-- 分组后 Top-N（使用窗口函数）
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY city ORDER BY age DESC) AS rn
    FROM users
) t WHERE rn <= 3;
-- 每个 Partition 独立排序取 Top-3，可并行执行

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

-- 分组后 Top-N
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY city ORDER BY age DESC) AS rn
    FROM users
) t WHERE rn <= 3;

-- 注意: 窗口函数方式需要计算所有行的 ROW_NUMBER，性能不如键集分页

-- ============================================================
-- 6. Doris 特有说明
-- ============================================================

-- Doris 兼容 MySQL 协议，分页特性:
--   LIMIT / OFFSET:     支持（MySQL 兼容）
--   LIMIT m, n:         支持（MySQL 简写）
--   FETCH FIRST:        不支持（非 MySQL 标准）
--   TOP N:              不支持
--
-- Doris 优化器特性:
--   Top-N 优化: ORDER BY + LIMIT 自动转换为 Top-N 算子
--   Runtime Filter: JOIN 场景下的动态过滤，可减少分页数据量
--   Colocate JOIN: 如果分页涉及 JOIN，Colocate 可避免数据移动
--   Bucket Shuffle Join: 基于分桶的本地 JOIN
--
-- 存储模型对分页的影响:
--   Duplicate Key Model:  无主键，分页需额外排序
--   Aggregate Key Model:  预聚合，分页在聚合后执行
--   Unique Key Model:     有主键，主键排序分页性能最好

-- ============================================================
-- 7. 版本演进
-- ============================================================
-- Doris 0.x:   LIMIT / OFFSET（MySQL 兼容）
-- Doris 1.0:   窗口函数增强，Top-N 优化
-- Doris 2.0:   Pipeline 执行引擎，LIMIT 下推优化
-- Doris 2.1+:  Runtime Filter 增强，Colocate Group 优化

-- ============================================================
-- 8. 横向对比: 分页语法差异
-- ============================================================

-- 语法对比:
--   Doris:       LIMIT n OFFSET m / LIMIT m, n（MySQL 兼容）
--   StarRocks:   LIMIT n OFFSET m / LIMIT m, n（MySQL 兼容）
--   MySQL:       LIMIT n OFFSET m / LIMIT m, n（Doris 的协议基础）
--   ClickHouse:  LIMIT n OFFSET m（不支持 LIMIT m, n 简写）
--
-- MPP 列存引擎分页对比:
--   Doris:      Top-N 优化 + Runtime Filter + Colocate JOIN
--   StarRocks:  Pipeline 引擎 + Top-N 优化 + 物化视图加速
--   ClickHouse: 特有 LIMIT BY 语法（分组取前 N），OFFSET 极慢
--   Trino:      MPP 架构，但无 Top-N 优化
