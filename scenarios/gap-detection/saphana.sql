-- SAP HANA: 间隙检测与岛屿问题 (Gap Detection & Islands)
--
-- 参考资料:
--   [1] SAP HANA Documentation - Window Functions
--       https://help.sap.com/docs/SAP_HANA_PLATFORM/4fe29514fd584807ac9f2a04f6754767/20a353327519101495dfd0a87060a0d3.html
--   [2] SAP HANA Documentation - SERIES_GENERATE
--       https://help.sap.com/docs/SAP_HANA_PLATFORM/4fe29514fd584807ac9f2a04f6754767/5f14e09987ef4c638a83e1a015e3bd17.html

-- ============================================================
-- 准备数据
-- ============================================================

CREATE TABLE orders (id INTEGER PRIMARY KEY, info NVARCHAR(100));
INSERT INTO orders VALUES (1,'a'),(2,'b'),(3,'c'),(5,'e'),(6,'f'),
    (10,'j'),(11,'k'),(12,'l'),(15,'o');

CREATE TABLE daily_sales (sale_date DATE PRIMARY KEY, amount DECIMAL(10,2));
INSERT INTO daily_sales VALUES
    ('2024-01-01',100),('2024-01-02',150),('2024-01-04',200),
    ('2024-01-05',120),('2024-01-08',300),('2024-01-09',250),
    ('2024-01-10',180);

-- ============================================================
-- 1. 使用 LAG/LEAD 查找数值间隙
-- ============================================================

SELECT id AS gap_start_after, next_id AS gap_end_before, next_id - id - 1 AS gap_size
FROM (SELECT id, LEAD(id) OVER (ORDER BY id) AS next_id FROM orders)
WHERE next_id - id > 1;

-- ============================================================
-- 2. 查找日期间隙
-- ============================================================

SELECT sale_date, next_date,
       DAYS_BETWEEN(sale_date, next_date) - 1 AS missing_days
FROM (
    SELECT sale_date, LEAD(sale_date) OVER (ORDER BY sale_date) AS next_date
    FROM daily_sales
) WHERE DAYS_BETWEEN(sale_date, next_date) > 1;

-- ============================================================
-- 3. 岛屿问题
-- ============================================================

SELECT MIN(id) AS island_start, MAX(id) AS island_end, COUNT(*) AS island_size
FROM (SELECT id, id - ROW_NUMBER() OVER (ORDER BY id) AS grp FROM orders)
GROUP BY grp ORDER BY island_start;

-- ============================================================
-- 4. 自连接方法
-- ============================================================

SELECT a.id + 1 AS gap_start, MIN(b.id) - 1 AS gap_end
FROM orders a JOIN orders b ON b.id > a.id
GROUP BY a.id HAVING MIN(b.id) > a.id + 1 ORDER BY gap_start;

-- ============================================================
-- 5. 使用 SERIES_GENERATE（SAP HANA 特有）
-- ============================================================

-- 生成数值序列
SELECT GENERATED_PERIOD_START AS n
FROM SERIES_GENERATE_INTEGER(1, 1, 16)
WHERE GENERATED_PERIOD_START NOT IN (SELECT id FROM orders)
  AND GENERATED_PERIOD_START >= (SELECT MIN(id) FROM orders);

-- 生成日期序列
SELECT GENERATED_PERIOD_START AS missing_date
FROM SERIES_GENERATE_DATE('INTERVAL 1 DAY',
    (SELECT MIN(sale_date) FROM daily_sales),
    ADD_DAYS((SELECT MAX(sale_date) FROM daily_sales), 1))
WHERE GENERATED_PERIOD_START NOT IN (SELECT sale_date FROM daily_sales);

-- ============================================================
-- 6. 综合示例
-- ============================================================

WITH islands AS (
    SELECT id, id - ROW_NUMBER() OVER (ORDER BY id) AS grp FROM orders
),
gaps AS (
    SELECT id, LEAD(id) OVER (ORDER BY id) AS next_id FROM orders
)
SELECT 'Island' AS type, MIN(id) AS range_start, MAX(id) AS range_end, COUNT(*) AS size
FROM islands GROUP BY grp
UNION ALL
SELECT 'Gap', id + 1, next_id - 1, next_id - id - 1
FROM gaps WHERE next_id - id > 1
ORDER BY range_start;

-- 注意：SAP HANA 支持 SERIES_GENERATE_INTEGER / SERIES_GENERATE_DATE
-- 注意：DAYS_BETWEEN 用于计算日期差值
-- 注意：SAP HANA 内存计算引擎对窗口函数有极好的优化
-- 注意：SAP HANA 支持递归 CTE（WITH RECURSIVE）
