-- SQL Server: 表分区策略
--
-- 参考资料:
--   [1] Microsoft Docs - Partitioned Tables and Indexes
--       https://learn.microsoft.com/en-us/sql/relational-databases/partitions/partitioned-tables-and-indexes
--   [2] Microsoft Docs - Partition Function
--       https://learn.microsoft.com/en-us/sql/t-sql/statements/create-partition-function-transact-sql

-- ============================================================
-- 创建分区（三步骤）
-- ============================================================

-- 步骤 1: 创建分区函数（定义分区边界）
CREATE PARTITION FUNCTION pf_order_date (DATE)
AS RANGE RIGHT FOR VALUES (
    '2023-01-01', '2024-01-01', '2025-01-01', '2026-01-01'
);

-- RANGE RIGHT: 边界值属于右分区（>=）
-- RANGE LEFT:  边界值属于左分区（<=）

-- 步骤 2: 创建分区方案（映射分区到文件组）
CREATE PARTITION SCHEME ps_order_date
AS PARTITION pf_order_date
TO (fg_archive, fg_2023, fg_2024, fg_2025, fg_current);
-- 或全部映射到一个文件组：
-- ALL TO ([PRIMARY]);

-- 步骤 3: 创建表（指定分区方案）
CREATE TABLE orders (
    id BIGINT IDENTITY(1,1),
    user_id BIGINT,
    amount DECIMAL(10,2),
    order_date DATE NOT NULL
) ON ps_order_date(order_date);  -- 在分区方案上创建

-- 聚集索引也要对齐分区
CREATE CLUSTERED INDEX IX_orders ON orders(order_date, id)
ON ps_order_date(order_date);

-- ============================================================
-- 分区管理
-- ============================================================

-- 添加新分区（SPLIT）
ALTER PARTITION FUNCTION pf_order_date()
SPLIT RANGE ('2027-01-01');

-- 先设置下一个使用的文件组
ALTER PARTITION SCHEME ps_order_date
NEXT USED fg_2027;

-- 合并分区（MERGE）
ALTER PARTITION FUNCTION pf_order_date()
MERGE RANGE ('2023-01-01');

-- 切换分区（SWITCH，高效的数据移动）
-- 将分区数据切换到另一个表（瞬间完成）
ALTER TABLE orders SWITCH PARTITION 3
TO orders_archive PARTITION 1;

-- 清空特定分区
TRUNCATE TABLE orders WITH (PARTITIONS (3));  -- 2016+

-- ============================================================
-- 分区信息查询
-- ============================================================

-- 查看分区函数
SELECT * FROM sys.partition_functions;
SELECT * FROM sys.partition_range_values
WHERE function_id = (SELECT function_id FROM sys.partition_functions
                     WHERE name = 'pf_order_date');

-- 查看各分区的行数
SELECT p.partition_number, p.rows,
       prv.value AS boundary_value
FROM sys.partitions p
JOIN sys.tables t ON p.object_id = t.object_id
LEFT JOIN sys.partition_range_values prv
    ON p.partition_number = prv.boundary_id + 1
    AND prv.function_id = (SELECT function_id FROM sys.partition_functions
                           WHERE name = 'pf_order_date')
WHERE t.name = 'orders'
  AND p.index_id <= 1
ORDER BY p.partition_number;

-- 使用 $PARTITION 函数
SELECT $PARTITION.pf_order_date('2024-06-15') AS partition_number;

-- ============================================================
-- 分区裁剪
-- ============================================================

-- 查看查询是否进行了分区裁剪
SET STATISTICS IO ON;
SELECT * FROM orders WHERE order_date = '2024-06-15';
-- 只扫描一个分区

-- ============================================================
-- 滑动窗口模式
-- ============================================================

-- 1. 创建 Staging 表
CREATE TABLE orders_staging (...) ON fg_new;

-- 2. 加载数据到 Staging
INSERT INTO orders_staging ...;

-- 3. 添加约束（匹配分区边界）
ALTER TABLE orders_staging ADD CHECK (
    order_date >= '2027-01-01' AND order_date < '2028-01-01'
);

-- 4. 拆分分区
ALTER PARTITION SCHEME ps_order_date NEXT USED fg_new;
ALTER PARTITION FUNCTION pf_order_date() SPLIT RANGE ('2028-01-01');

-- 5. 切入新数据
ALTER TABLE orders_staging SWITCH TO orders PARTITION ...;

-- 6. 切出旧数据
ALTER TABLE orders SWITCH PARTITION 1 TO orders_archive;

-- 7. 合并旧分区
ALTER PARTITION FUNCTION pf_order_date() MERGE RANGE ('2023-01-01');

-- 注意：SQL Server 分区需要三步：分区函数 → 分区方案 → 表
-- 注意：SWITCH PARTITION 是元数据操作，瞬间完成
-- 注意：2016+ 支持 TRUNCATE TABLE WITH (PARTITIONS (...))
-- 注意：分区列必须包含在聚集索引中
-- 注意：滑动窗口模式是大量数据生命周期管理的最佳实践
-- 注意：Enterprise Edition 才支持分区功能
