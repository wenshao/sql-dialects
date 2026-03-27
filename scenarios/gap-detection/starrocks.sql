-- StarRocks: 间隙检测与岛屿问题 (Gap Detection & Islands)
--
-- 参考资料:
--   [1] StarRocks Documentation - Window Functions
--       https://docs.starrocks.io/docs/sql-reference/sql-functions/Window_function/
--   [2] StarRocks Documentation - generate_series
--       https://docs.starrocks.io/docs/sql-reference/sql-functions/table-functions/generate_series/

-- ============================================================
-- 准备数据
-- ============================================================

CREATE TABLE orders (id INT, info VARCHAR(100))
DISTRIBUTED BY HASH(id) BUCKETS 1
PROPERTIES ("replication_num" = "1");
INSERT INTO orders VALUES (1,'a'),(2,'b'),(3,'c'),(5,'e'),(6,'f'),
    (10,'j'),(11,'k'),(12,'l'),(15,'o');

CREATE TABLE daily_sales (sale_date DATE, amount DECIMAL(10,2))
DISTRIBUTED BY HASH(sale_date) BUCKETS 1
PROPERTIES ("replication_num" = "1");
INSERT INTO daily_sales VALUES
    ('2024-01-01',100),('2024-01-02',150),('2024-01-04',200),
    ('2024-01-05',120),('2024-01-08',300),('2024-01-09',250),
    ('2024-01-10',180);

-- ============================================================
-- 1. 使用 LAG/LEAD 查找数值间隙
-- ============================================================

SELECT id AS gap_start_after, next_id AS gap_end_before, next_id - id - 1 AS gap_size
FROM (SELECT id, LEAD(id, 1, NULL) OVER (ORDER BY id) AS next_id FROM orders) t
WHERE next_id - id > 1;

-- ============================================================
-- 2. 查找日期间隙
-- ============================================================

SELECT sale_date, next_date, DATEDIFF(next_date, sale_date) - 1 AS missing_days
FROM (
    SELECT sale_date, LEAD(sale_date, 1, NULL) OVER (ORDER BY sale_date) AS next_date
    FROM daily_sales
) t WHERE DATEDIFF(next_date, sale_date) > 1;

-- ============================================================
-- 3. 岛屿问题
-- ============================================================

SELECT MIN(id) AS island_start, MAX(id) AS island_end, COUNT(*) AS island_size
FROM (SELECT id, id - ROW_NUMBER() OVER (ORDER BY id) AS grp FROM orders) t
GROUP BY grp ORDER BY island_start;

-- ============================================================
-- 4. 自连接方法
-- ============================================================

SELECT a.id + 1 AS gap_start, MIN(b.id) - 1 AS gap_end
FROM orders a JOIN orders b ON b.id > a.id
GROUP BY a.id HAVING MIN(b.id) > a.id + 1 ORDER BY gap_start;

-- ============================================================
-- 5. 使用 generate_series（StarRocks 3.1+）
-- ============================================================

SELECT generate_series AS missing_id
FROM TABLE(generate_series(1, 15))
WHERE generate_series NOT IN (SELECT id FROM orders)
ORDER BY missing_id;

-- ============================================================
-- 6. 综合示例
-- ============================================================

WITH islands AS (
    SELECT id, id - ROW_NUMBER() OVER (ORDER BY id) AS grp FROM orders
),
gaps AS (
    SELECT id, LEAD(id, 1, NULL) OVER (ORDER BY id) AS next_id FROM orders
)
SELECT 'Island' AS type, MIN(id) AS range_start, MAX(id) AS range_end, COUNT(*) AS size
FROM islands GROUP BY grp
UNION ALL
SELECT 'Gap', id + 1, next_id - 1, next_id - id - 1
FROM gaps WHERE next_id IS NOT NULL AND next_id - id > 1
ORDER BY range_start;

-- 注意：StarRocks 3.1+ 支持 generate_series 表函数
-- 注意：StarRocks 不支持递归 CTE
-- 注意：StarRocks 的 LEAD/LAG 默认值参数为 NULL
-- 注意：StarRocks 与 Apache Doris 语法高度兼容
