-- SQL Server: 表分区（三步模型）
--
-- 参考资料:
--   [1] SQL Server - Partitioned Tables and Indexes
--       https://learn.microsoft.com/en-us/sql/relational-databases/partitions/partitioned-tables-and-indexes

-- ============================================================
-- 1. 分区三步模型: SQL Server 独有的复杂设计
-- ============================================================

-- 步骤 1: 分区函数（定义分区边界）
CREATE PARTITION FUNCTION pf_order_date (DATE)
AS RANGE RIGHT FOR VALUES ('2023-01-01', '2024-01-01', '2025-01-01', '2026-01-01');
-- RANGE RIGHT: 边界值属于右分区（>=）
-- RANGE LEFT:  边界值属于左分区（<=）

-- 步骤 2: 分区方案（映射分区到文件组）
CREATE PARTITION SCHEME ps_order_date
AS PARTITION pf_order_date
TO (fg_archive, fg_2023, fg_2024, fg_2025, fg_current);
-- 或全部映射到一个文件组: ALL TO ([PRIMARY]);

-- 步骤 3: 创建表（指定分区方案）
CREATE TABLE orders (
    id         BIGINT IDENTITY(1,1),
    user_id    BIGINT,
    amount     DECIMAL(10,2),
    order_date DATE NOT NULL
) ON ps_order_date(order_date);

-- 聚集索引对齐分区
CREATE CLUSTERED INDEX IX_orders ON orders(order_date, id)
ON ps_order_date(order_date);

-- 设计分析（对引擎开发者）:
--   SQL Server 的三步模型是所有主流数据库中最复杂的分区设计:
--   分区函数(边界) → 分区方案(物理映射) → 表(使用方案)
--   这种分离设计的优点: 函数和方案可以复用（多个表共享同一分区策略）
--   缺点: 创建一个分区表需要写 3 条 DDL——其他数据库只需要 1 条
--
-- 横向对比:
--   PostgreSQL: CREATE TABLE t (...) PARTITION BY RANGE (col)（一步）
--   MySQL:      CREATE TABLE t (...) PARTITION BY RANGE (YEAR(col))（一步）
--   Oracle:     CREATE TABLE t (...) PARTITION BY RANGE (col)（一步）
--
-- 对引擎开发者的启示:
--   分区函数/方案的复用是理论上的优势，实际中很少使用。
--   一步式分区语法更符合用户心智模型——建议引擎采用一步式设计。

-- ============================================================
-- 2. 分区管理操作
-- ============================================================

-- SPLIT: 添加新分区
ALTER PARTITION SCHEME ps_order_date NEXT USED fg_2027;  -- 先指定文件组
ALTER PARTITION FUNCTION pf_order_date() SPLIT RANGE ('2027-01-01');

-- MERGE: 合并分区
ALTER PARTITION FUNCTION pf_order_date() MERGE RANGE ('2023-01-01');

-- SWITCH: 分区切换（瞬间完成的元数据操作！）
ALTER TABLE orders SWITCH PARTITION 3 TO orders_archive PARTITION 1;

-- SWITCH 是 SQL Server 分区的核心优势——它是 O(1) 操作:
--   不移动数据，只修改元数据中的分区指向。
--   条件: 目标表结构、索引、约束必须与源分区完全一致。
--   用途: 大量数据的快速归档和加载。

-- 2016+: 分区级 TRUNCATE
TRUNCATE TABLE orders WITH (PARTITIONS (3, 5));

-- ============================================================
-- 3. 分区裁剪（Partition Pruning）
-- ============================================================

-- 分区裁剪是分区的核心价值——查询只扫描相关分区
SET STATISTICS IO ON;
SELECT * FROM orders WHERE order_date = '2024-06-15';
-- 只读取 2024 分区（其他分区完全跳过）

-- 使用 $PARTITION 函数检查分区编号
SELECT $PARTITION.pf_order_date('2024-06-15') AS partition_number;

-- ============================================================
-- 4. 滑动窗口模式（经典的数据生命周期管理）
-- ============================================================

-- 1. 创建与分区对齐的 Staging 表
-- 2. 加载数据到 Staging
-- 3. 添加 CHECK 约束（匹配分区边界）
ALTER TABLE orders_staging ADD CHECK (
    order_date >= '2027-01-01' AND order_date < '2028-01-01'
);
-- 4. SPLIT 新分区
-- 5. SWITCH IN 新数据
ALTER TABLE orders_staging SWITCH TO orders PARTITION 6;
-- 6. SWITCH OUT 旧数据
ALTER TABLE orders SWITCH PARTITION 1 TO orders_archive;
-- 7. MERGE 旧分区

-- ============================================================
-- 5. 分区信息查询
-- ============================================================

-- 分区函数边界
SELECT * FROM sys.partition_range_values
WHERE function_id = (SELECT function_id FROM sys.partition_functions
                     WHERE name = 'pf_order_date');

-- 各分区行数
SELECT p.partition_number, p.rows
FROM sys.partitions p
JOIN sys.tables t ON p.object_id = t.object_id
WHERE t.name = 'orders' AND p.index_id <= 1
ORDER BY p.partition_number;

-- ============================================================
-- 6. 分区限制与注意事项
-- ============================================================

-- (1) 分区列必须包含在聚集索引中（与 MySQL 限制类似）
-- (2) Enterprise Edition 才支持分区（Standard 版不支持——这是最大的限制）
-- (3) 单表最多 15000 个分区（2012+ 扩展到 15000，之前是 1000）
-- (4) SWITCH 要求源和目标结构完全匹配（包括索引、约束）
--
-- 横向对比:
--   PostgreSQL: 所有版本都支持分区（无 Enterprise 限制）
--   MySQL:      所有版本都支持分区
--   Oracle:     Enterprise Edition 才支持（同 SQL Server）
--
-- 对引擎开发者的启示:
--   分区是 OLTP/OLAP 混合负载的核心功能。
--   将分区锁定在付费版本是合理的商业策略但不利于用户。
--   SWITCH（零拷贝分区交换）是 SQL Server 分区的杀手级功能——
--   其他数据库的 ATTACH/DETACH PARTITION 类似但语义不完全等价。
