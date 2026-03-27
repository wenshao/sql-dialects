-- Apache Impala: 日期序列生成与间隙填充 (Date Series Fill)
--
-- 参考资料:
--   [1] Apache Impala Documentation - Date Functions
--       https://impala.apache.org/docs/build/html/topics/impala_datetime_functions.html
--   [2] Apache Impala Documentation - Window Functions
--       https://impala.apache.org/docs/build/html/topics/impala_window_functions.html
--   [3] Apache Impala Documentation - SQL Statements
--       https://impala.apache.org/docs/build/html/topics/impala_langref_sql.html

-- ============================================================
-- 1. 示例数据
-- ============================================================

CREATE TABLE daily_sales (
    sale_date DATE,
    amount    DECIMAL(10,2)
);

INSERT INTO daily_sales VALUES
    ('2024-01-01', 100.00),
    ('2024-01-02', 150.00),
    ('2024-01-04', 200.00),
    ('2024-01-05', 120.00),
    ('2024-01-08', 300.00),
    ('2024-01-09', 250.00),
    ('2024-01-10', 180.00);

-- 缺失日期: 2024-01-03, 2024-01-06, 2024-01-07

-- ============================================================
-- 2. Impala 日期序列生成的挑战
-- ============================================================

-- Impala 不支持:
--   generate_series（PostgreSQL 特有）
--   递归 CTE（WITH RECURSIVE）
--   CONNECT BY（Oracle 特有）
-- 需要使用辅助表或其他方式生成序列

-- ============================================================
-- 3. 使用辅助数字表生成日期序列
-- ============================================================

-- 创建辅助数字表
CREATE TABLE numbers (n INT);
INSERT INTO numbers VALUES (0),(1),(2),(3),(4),(5),(6),(7),(8),(9),
                           (10),(11),(12),(13),(14),(15),(16),(17),(18),(19),
                           (20),(21),(22),(23),(24),(25),(26),(27),(28),(29);

-- 使用数字表生成日期序列
SELECT DATE_ADD('2024-01-01', INTERVAL n DAY) AS d
FROM   numbers
WHERE  n < 10;

-- 输出: 2024-01-01, 2024-01-02, ..., 2024-01-10

-- ============================================================
-- 4. LEFT JOIN 填充缺失日期（核心模式）
-- ============================================================

SELECT seq.d                    AS sale_date,
       COALESCE(ds.amount, 0)  AS amount
FROM   (SELECT DATE_ADD('2024-01-01', INTERVAL n DAY) AS d
        FROM   numbers
        WHERE  n < 10) seq
LEFT   JOIN daily_sales ds ON ds.sale_date = seq.d
ORDER  BY seq.d;

-- 设计分析:
--   辅助表生成连续日期序列
--   LEFT JOIN 确保所有日期都出现在结果中
--   COALESCE 将 NULL 替换为 0

-- ============================================================
-- 5. 累计和（Running Total）
-- ============================================================

SELECT seq.d                    AS sale_date,
       COALESCE(ds.amount, 0)  AS amount,
       SUM(COALESCE(ds.amount, 0)) OVER (ORDER BY seq.d) AS running_total
FROM   (SELECT DATE_ADD('2024-01-01', INTERVAL n DAY) AS d
        FROM   numbers
        WHERE  n < 10) seq
LEFT   JOIN daily_sales ds ON ds.sale_date = seq.d
ORDER  BY seq.d;

-- SUM() OVER (ORDER BY ...) 计算累计和
-- Impala 支持完整的窗口函数语法

-- ============================================================
-- 6. 用最近已知值填充（LOCF 模式）
-- ============================================================

-- Impala 不支持 IGNORE NULLS，使用 COUNT 分组法模拟
WITH filled AS (
    SELECT seq.d AS sale_date,
           ds.amount,
           COUNT(ds.amount) OVER (ORDER BY seq.d) AS grp
    FROM   (SELECT DATE_ADD('2024-01-01', INTERVAL n DAY) AS d
            FROM   numbers
            WHERE  n < 10) seq
    LEFT   JOIN daily_sales ds ON ds.sale_date = seq.d
)
SELECT sale_date,
       FIRST_VALUE(amount) OVER (PARTITION BY grp ORDER BY sale_date) AS filled_amount
FROM   filled
ORDER  BY sale_date;

-- 设计分析: COUNT 分组法
--   COUNT(amount) 对非 NULL 值递增计数
--   相邻的 NULL 值与之前的非 NULL 值归入同一组
--   FIRST_VALUE 取每组的第一个值（即最近的非 NULL 值）
--   这是通用的 IGNORE NULLS 模拟方案

-- ============================================================
-- 7. 动态日期范围（从数据中获取最小/最大日期）
-- ============================================================

SELECT seq.d                    AS sale_date,
       COALESCE(ds.amount, 0)  AS amount
FROM   (SELECT DATE_ADD(min_date, INTERVAL n DAY) AS d
        FROM   numbers,
               (SELECT MIN(sale_date) AS min_date FROM daily_sales) t
        WHERE  n <= DATEDIFF(
                   (SELECT MAX(sale_date) FROM daily_sales),
                   (SELECT MIN(sale_date) FROM daily_sales)
               )) seq
LEFT   JOIN daily_sales ds ON ds.sale_date = seq.d
ORDER  BY seq.d;

-- 动态计算日期范围，无需硬编码起止日期
-- DATEDIFF 计算两个日期之间的天数差

-- ============================================================
-- 8. 使用 UNION ALL 构建小序列（无需辅助表）
-- ============================================================

-- 生成 0-9 的序列（无需辅助数字表）
SELECT DATE_ADD('2024-01-01', INTERVAL d.n DAY) AS d
FROM   (
         SELECT 0 AS n UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL
         SELECT 3 UNION ALL SELECT 4 UNION ALL SELECT 5 UNION ALL
         SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9
       ) d;

-- 适用于小范围序列（10 天以内）
-- 优点: 不依赖辅助表
-- 缺点: 范围大时 SQL 冗长

-- ============================================================
-- 9. 多维度填充（类别 x 日期交叉）
-- ============================================================

CREATE TABLE category_sales (
    sale_date DATE,
    category  STRING,
    amount    DECIMAL(10,2)
);

INSERT INTO category_sales VALUES
    ('2024-01-01', 'A', 100), ('2024-01-01', 'B', 200),
    ('2024-01-02', 'A', 150),
    ('2024-01-04', 'A', 200), ('2024-01-04', 'B', 300);

SELECT seq.d                    AS sale_date,
       cat.category,
       COALESCE(cs.amount, 0)  AS amount
FROM   (SELECT DATE_ADD('2024-01-01', INTERVAL n DAY) AS d
        FROM   numbers WHERE n < 4) seq
CROSS  JOIN (SELECT DISTINCT category FROM category_sales) cat
LEFT   JOIN category_sales cs ON cs.sale_date = seq.d AND cs.category = cat.category
ORDER  BY cat.category, seq.d;

-- ============================================================
-- 10. 横向对比与对引擎开发者的启示
-- ============================================================

-- 1. Impala 日期序列生成的限制:
--   无 generate_series → 需要辅助数字表或 UNION ALL
--   无递归 CTE → 无法自举生成序列
--   有完整窗口函数 → 间隙填充逻辑与 PostgreSQL 一致
--
-- 2. 与其他数据库对比:
--   PostgreSQL:  generate_series + LEFT JOIN（最优雅）
--   Impala:      辅助数字表 + DATE_ADD + LEFT JOIN
--   Hive:        与 Impala 类似（也缺乏序列生成函数）
--   Presto:      SEQUENCE() 函数（比 Impala 更方便）
--   Spark SQL:   sequence() 函数（与 Presto 类似）
--
-- 对引擎开发者:
--   缺少序列生成函数是 Impala 的主要短板
--   推荐方案: 内置 SEQUENCE(start, end, step) 表函数
--   Presto/Spark 的 sequence() 函数是更好的设计参考
--   辅助数字表 + 窗口函数的组合虽可行但不优雅
--   FIRST_VALUE + COUNT 分组法是通用的 LOCF 模拟方案
