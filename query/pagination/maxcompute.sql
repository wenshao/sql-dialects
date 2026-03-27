-- MaxCompute (ODPS): 分页 (Pagination)
--
-- 参考资料:
--   [1] MaxCompute SQL - SELECT 语法
--       https://help.aliyun.com/zh/maxcompute/user-guide/select
--   [2] MaxCompute SQL 概述
--       https://help.aliyun.com/zh/maxcompute/user-guide/sql-overview
--   [3] MaxCompute MCQA 交互式分析
--       https://help.aliyun.com/zh/maxcompute/user-guide/mcqa

-- ============================================================
-- 1. LIMIT（取前 N 行）
-- ============================================================

-- 仅取前 N 行（所有版本均支持）
SELECT * FROM users ORDER BY id LIMIT 10;

-- LIMIT 无 OFFSET 时，配合 ORDER BY 利用 Top-K 优化
-- MaxCompute 优化器会将 ORDER BY + LIMIT 转换为 Top-K 算子
-- 避免全量排序，只维护一个大小为 K 的堆

-- ============================================================
-- 2. LIMIT / OFFSET（MaxCompute 2.0+）
-- ============================================================

-- 基本分页: 跳过前 20 行，取 10 行
SELECT * FROM users ORDER BY id LIMIT 10 OFFSET 20;

-- 注意: MaxCompute 早期版本不支持 OFFSET
-- 早期版本的替代方案: 使用窗口函数 ROW_NUMBER

-- 带总行数的分页（一次查询获取数据和总数）
SELECT *, COUNT(*) OVER() AS total_count
FROM users ORDER BY id LIMIT 10 OFFSET 20;
-- 注意: COUNT(*) OVER() 需要扫描全部数据，大数据集下可能很慢

-- ============================================================
-- 3. MaxCompute 不支持的语法
-- ============================================================

-- 以下语法在 MaxCompute 中不支持:
--   FETCH FIRST ... ROWS ONLY    -- 不支持 SQL 标准 FETCH 语法
--   TOP N                        -- 不支持 TOP 关键字
--   LIMIT offset, count          -- 不支持 MySQL 风格的简写
--   DECLARE CURSOR               -- 不支持服务端游标

-- ============================================================
-- 4. 窗口函数辅助分页（早期版本的替代方案）
-- ============================================================

-- ROW_NUMBER 分页（适用于所有版本）
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
-- 在大数据集上（TB 级）性能较差，需要全量排序

-- ============================================================
-- 5. 键集分页（Keyset Pagination）
-- ============================================================

-- 第一页
SELECT * FROM users ORDER BY id LIMIT 10;

-- 后续页（已知上一页最后一条 id = 100）
SELECT * FROM users WHERE id > 100 ORDER BY id LIMIT 10;

-- 多列排序的键集分页
SELECT * FROM users
WHERE created_at > '2025-01-01'
   OR (created_at = '2025-01-01' AND id > 100)
ORDER BY created_at, id
LIMIT 10;

-- ============================================================
-- 6. MaxCompute 特有说明: 大数据场景下的分页
-- ============================================================

-- MaxCompute 是离线大数据引擎（非 OLTP），分页有特殊考量:
--
-- 全表 ORDER BY 在大数据量下非常耗资源:
--   ORDER BY 需要将所有数据发送到一个 Reducer 进行全局排序
--   对于 TB 级数据，单个 Reducer 是严重瓶颈
--   建议: 始终配合 LIMIT 使用 ORDER BY（触发 Top-K 优化）
--
-- MCQA (MaxCompute Query Acceleration) 交互式场景:
--   MCQA 是 MaxCompute 的交互式查询加速服务
--   分页查询适用于 MCQA 场景（秒级响应）
--   离线任务（ETL）不建议使用分页
--
-- DISTRIBUTE BY + SORT BY（替代 ORDER BY 的方案）:
--   DISTRIBUTE BY hash_column: 按 hash_column 分发到不同 Reducer
--   SORT BY sort_col: 在每个 Reducer 内部排序（非全局排序）
--   适用于: 只需局部有序 + LIMIT 的场景
--   SELECT * FROM users DISTRIBUTE BY hash(id) SORT BY id LIMIT 10;

-- 数据量建议:
--   < 100 万行: LIMIT / OFFSET 可用（MCQA 场景）
--   100 万 ~ 1 亿行: 推荐键集分页 + LIMIT
--   > 1 亿行: 避免分页，改用数据导出或分区过滤

-- ============================================================
-- 7. 版本演进
-- ============================================================
-- MaxCompute V1.0:  LIMIT（仅取前 N 行，无 OFFSET）
-- MaxCompute V2.0:  LIMIT + OFFSET 支持，窗口函数增强
-- MaxCompute MCQA:  交互式查询加速，分页响应更快

-- ============================================================
-- 8. 横向对比: 分页语法差异
-- ============================================================

-- 语法对比:
--   MaxCompute:  LIMIT n OFFSET m（不支持 FETCH FIRST、TOP）
--   Hive:        LIMIT n OFFSET m（2.0+，不支持 FETCH FIRST）
--   Spark SQL:   LIMIT n OFFSET m（类似 Hive）
--   Presto/Trino: LIMIT n OFFSET m + FETCH FIRST（支持 SQL 标准）
--
-- 大数据引擎分页对比:
--   MaxCompute:  离线批处理，MCQA 可加速交互式分页
--   Hive:        离线批处理，ORDER BY 单 Reducer 瓶颈
--   Spark SQL:   内存计算，ORDER BY 性能优于 Hive
--   Trino:       MPP 引擎，交互式分页性能好
