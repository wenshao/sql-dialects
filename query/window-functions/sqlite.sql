-- SQLite: 窗口函数（3.25.0+, 2018年9月）
--
-- 参考资料:
--   [1] SQLite Documentation - Window Functions
--       https://www.sqlite.org/windowfunctions.html

-- ============================================================
-- 1. 基本窗口函数
-- ============================================================

-- 排名函数
SELECT username, age,
    ROW_NUMBER() OVER (ORDER BY age DESC) AS row_num,
    RANK() OVER (ORDER BY age DESC) AS rank,
    DENSE_RANK() OVER (ORDER BY age DESC) AS dense_rank,
    NTILE(4) OVER (ORDER BY age DESC) AS quartile
FROM users;

-- 分组排名（PARTITION BY）
SELECT username, department, salary,
    ROW_NUMBER() OVER (PARTITION BY department ORDER BY salary DESC) AS dept_rank
FROM employees;

-- 聚合窗口函数
SELECT username, amount,
    SUM(amount) OVER (ORDER BY order_date) AS running_total,
    AVG(amount) OVER (ORDER BY order_date ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS moving_avg,
    COUNT(*) OVER () AS total_count
FROM orders;

-- 偏移函数
SELECT username, amount,
    LAG(amount, 1) OVER (ORDER BY order_date) AS prev_amount,
    LEAD(amount, 1) OVER (ORDER BY order_date) AS next_amount,
    FIRST_VALUE(amount) OVER (ORDER BY order_date) AS first_amount,
    LAST_VALUE(amount) OVER (ORDER BY order_date
        ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS last_amount
FROM orders;

-- ============================================================
-- 2. 窗口帧（Frame Specification）
-- ============================================================

-- ROWS: 按物理行偏移
SELECT amount,
    SUM(amount) OVER (ORDER BY id ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS sum_3
FROM orders;

-- RANGE: 按值范围偏移
SELECT order_date, amount,
    SUM(amount) OVER (ORDER BY julianday(order_date)
        RANGE BETWEEN 7 PRECEDING AND CURRENT ROW) AS week_sum
FROM orders;

-- GROUPS: 按 peer group 偏移（3.28.0+）
SELECT order_date, amount,
    SUM(amount) OVER (ORDER BY order_date GROUPS BETWEEN 1 PRECEDING AND 1 FOLLOWING)
FROM orders;

-- ============================================================
-- 3. 命名窗口（WINDOW 子句）
-- ============================================================

SELECT username, amount,
    SUM(amount) OVER w AS running_sum,
    AVG(amount) OVER w AS running_avg,
    COUNT(*) OVER w AS running_count
FROM orders
WINDOW w AS (ORDER BY order_date);

-- ============================================================
-- 4. 为什么 SQLite 到 3.25.0 才支持窗口函数
-- ============================================================

-- SQLite 诞生于 2000 年，窗口函数 2018 年才添加（等了 18 年）。
-- 原因:
-- (a) 窗口函数在 SQL:2003 标准中定义，但早期嵌入式场景不需要
-- (b) 实现复杂: 窗口函数需要物化中间结果（违反 SQLite 的流式处理模型）
-- (c) 2018 年移动应用和 Electron 应用对本地数据分析需求增长
--
-- 对比时间线:
--   Oracle: 8i (1998) → 第一个支持窗口函数的数据库
--   PostgreSQL: 8.4 (2009)
--   MySQL: 8.0 (2018，与 SQLite 同年!）
--   SQLite: 3.25.0 (2018)
--   ClickHouse: 从第一版就支持

-- ============================================================
-- 5. 对比与引擎开发者启示
-- ============================================================
-- SQLite 窗口函数的特点:
--   (1) 完整的窗口帧支持（ROWS/RANGE/GROUPS）
--   (2) 命名窗口（WINDOW 子句）
--   (3) 3.28.0+: GROUPS 帧类型
--   (4) 不支持 QUALIFY → 需要子查询过滤
--
-- 对引擎开发者的启示:
--   窗口函数是现代 SQL 引擎的必备功能。
--   MySQL 和 SQLite 都在 2018 年补齐了窗口函数，
--   说明即使是成熟引擎也不能忽视这个标准特性。
