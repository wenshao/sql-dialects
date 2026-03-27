-- Apache Impala: 分页 (Pagination)
--
-- 参考资料:
--   [1] Impala SQL Language Reference - SELECT
--       https://impala.apache.org/docs/build/html/topics/impala_select.html
--   [2] Impala Built-in Functions
--       https://impala.apache.org/docs/build/html/topics/impala_functions.html
--   [3] Impala Window Functions
--       https://impala.apache.org/docs/build/html/topics/impala_analytic_functions.html

-- ============================================================
-- 1. LIMIT（取前 N 行）
-- ============================================================

-- 仅取前 N 行（所有版本均支持）
SELECT * FROM users ORDER BY id LIMIT 10;

-- 注意: ORDER BY + LIMIT 在 Impala 中的执行:
--   优化器会将 ORDER BY + LIMIT 转换为 Top-N 操作
--   每个 Impalad 节点维护本地 Top-N 堆
--   Coordinator 节点合并各节点结果取全局 Top-N
--   避免全量排序，复杂度从 O(M*logM) 降低到 O(M*logN)

-- ============================================================
-- 2. LIMIT / OFFSET
-- ============================================================

-- 基本分页: 跳过前 20 行，取 10 行
SELECT * FROM users ORDER BY id LIMIT 10 OFFSET 20;

-- 注意: Impala 支持 OFFSET，但在分布式环境中代价较高
--   每个 Impalad 节点返回 offset + limit 行到 Coordinator
--   Coordinator 合并后跳过 offset 行
--   网络传输量 = 节点数 * (offset + limit) 行

-- ============================================================
-- 3. Impala 不支持的语法
-- ============================================================

-- 以下语法在 Impala 中不支持:
--   FETCH FIRST ... ROWS ONLY    -- 不支持 SQL 标准 FETCH 语法
--   TOP N                        -- 不支持 TOP 关键字
--   LIMIT offset, count          -- 不支持 MySQL 风格的简写
--   DECLARE CURSOR               -- 不支持服务端游标
--   QUALIFY                      -- 不支持 QUALIFY 语法

-- ============================================================
-- 4. OFFSET 的性能问题（MPP + 列存架构）
-- ============================================================

-- Impala 是 MPP 列存引擎:
--   数据按列存储在 HDFS/S3 上（Parquet 格式）
--   OFFSET 需要解码向量数据，然后丢弃前 N 行
--   对于宽表（列数多），OFFSET 的解码代价更高
--
-- Parquet 格式的影响:
--   Parquet 按 Row Group 组织数据（默认 1GB）
--   每个 Row Group 有列级的 MIN/MAX 统计信息
--   键集分页的 WHERE 条件可利用统计信息跳过 Row Group
--   OFFSET 无法利用 Row Group 跳过（需要逐行计数）
--
-- 建议:
--   小结果集（< 10 万行）: LIMIT / OFFSET 可用
--   大结果集: 推荐使用键集分页

-- ============================================================
-- 5. 键集分页（Keyset Pagination）: 高性能替代方案
-- ============================================================

-- 第一页
SELECT * FROM users ORDER BY id LIMIT 10;

-- 后续页（已知上一页最后一条 id = 100）
SELECT * FROM users WHERE id > 100 ORDER BY id LIMIT 10;
-- 时间复杂度: O(log n + limit)，与页码无关
-- 可利用 Parquet Row Group 统计信息跳过不相关的数据块

-- 多列排序的键集分页
SELECT * FROM users
WHERE created_at > '2025-01-01'
   OR (created_at = '2025-01-01' AND id > 100)
ORDER BY created_at, id
LIMIT 10;

-- ============================================================
-- 6. 窗口函数辅助分页（Impala 2.0+）
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

-- RANK / DENSE_RANK 分页（包含并列排名）
SELECT * FROM (
    SELECT *, RANK() OVER (ORDER BY score DESC) AS rnk
    FROM users
) t WHERE rnk <= 10;

-- 注意: 窗口函数方式需要计算所有行的 ROW_NUMBER
-- 在 Impala 中，窗口函数需要按分区键重分布数据（数据移动开销）

-- ============================================================
-- 7. Impala 特有说明
-- ============================================================

-- Impala 与 Hive 的对比（分页相关）:
--   执行引擎: Impala 是 MPP（常驻进程），Hive 是 MapReduce/Tez
--   响应时间: Impala 适合交互式分页（秒级），Hive 适合批处理
--   语法兼容: 两者都支持 LIMIT / OFFSET，都不支持 FETCH FIRST
--   排序性能: Impala 内存排序快，Hive 需要落磁盘
--
-- Impala 的查询优化:
--   Runtime Filter: 动态过滤，减少 JOIN 和扫描的数据量
--   Parquet Predicate Pushdown: 谓词下推到存储层
--   Top-N 优化: ORDER BY + LIMIT 自动使用 Top-N 算子
--  LIMIT 下推: 将 LIMIT 下推到 Scan 节点（减少数据传输）

-- ============================================================
-- 8. 版本演进
-- ============================================================
-- Impala 1.x:  LIMIT（仅取前 N 行）
-- Impala 2.0:  窗口函数（ROW_NUMBER, RANK, DENSE_RANK）
-- Impala 2.x:  OFFSET 支持
-- Impala 3.x:  Runtime Filter 增强，Parquet 下推优化
-- Impala 4.x:  多线程执行，TOP-N 并行优化

-- ============================================================
-- 9. 横向对比: 分页语法差异
-- ============================================================

-- 语法对比:
--   Impala:     LIMIT n OFFSET m（不支持 FETCH FIRST）
--   Hive:       LIMIT n OFFSET m（不支持 FETCH FIRST，2.0+）
--   Spark SQL:  LIMIT n OFFSET m（不支持 FETCH FIRST，3.4+）
--   Trino:      LIMIT n OFFSET m + FETCH FIRST（SQL 标准兼容）
--
-- 大数据引擎分页对比:
--   Impala:     MPP + 列存，交互式分页性能好
--   Hive:       批处理引擎，ORDER BY 单 Reducer 瓶颈
--   Spark SQL:  内存计算，排序性能优于 Hive
--   Trino:      MPP 架构，连接器决定实际性能
