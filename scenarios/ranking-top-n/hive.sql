-- Hive: Top-N 查询 (排名与分组取前 N 条)
--
-- 参考资料:
--   [1] Apache Hive - Window Functions
--       https://cwiki.apache.org/confluence/display/Hive/LanguageManual+WindowingAndAnalytics

-- ============================================================
-- 1. 全局 Top-N
-- ============================================================
SELECT order_id, customer_id, amount
FROM orders ORDER BY amount DESC LIMIT 10;

-- ORDER BY + LIMIT 在 Hive 中的优化:
-- 优化器将全局排序转为 Top-K 算子（每个 Reducer 维护大小 K 的堆）
-- 避免全量排序，显著降低开销

-- ============================================================
-- 2. 分组 Top-N: ROW_NUMBER
-- ============================================================
-- 每个客户的前 3 笔最大订单
SELECT * FROM (
    SELECT order_id, customer_id, amount,
        ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY amount DESC) AS rn
    FROM orders
) ranked WHERE rn <= 3;

-- ============================================================
-- 3. 分组 Top-N: RANK (包含并列)
-- ============================================================
SELECT * FROM (
    SELECT order_id, customer_id, amount,
        RANK() OVER (PARTITION BY customer_id ORDER BY amount DESC) AS rnk
    FROM orders
) ranked WHERE rnk <= 3;
-- RANK: 并列排名后跳号 (1,2,2,4)
-- DENSE_RANK: 并列不跳号 (1,2,2,3)

-- ============================================================
-- 4. 分组 Top-1 (每组最大/最新)
-- ============================================================
-- 每个客户的最新订单
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY order_date DESC) AS rn
    FROM orders
) t WHERE rn = 1;

-- ============================================================
-- 5. 聚合 Top-N
-- ============================================================
-- 消费金额最高的前 10 个客户
SELECT customer_id, SUM(amount) AS total, COUNT(*) AS cnt
FROM orders
GROUP BY customer_id
ORDER BY total DESC
LIMIT 10;

-- 每个地区消费最高的客户
SELECT * FROM (
    SELECT customer_id, region, SUM(amount) AS total,
        ROW_NUMBER() OVER (PARTITION BY region ORDER BY SUM(amount) DESC) AS rn
    FROM orders GROUP BY customer_id, region
) t WHERE rn <= 5;

-- ============================================================
-- 6. Hive 特有: SORT BY + LIMIT (多 Reducer 并行)
-- ============================================================
-- 当全局 ORDER BY 太慢时，可以使用 SORT BY + LIMIT
-- 每个 Reducer 各自排序取 Top-K，然后合并
SET mapreduce.job.reduces = 10;
SELECT order_id, amount FROM orders SORT BY amount DESC LIMIT 100;

-- ============================================================
-- 7. 跨引擎对比: Top-N 语法
-- ============================================================
-- 引擎          全局 Top-N                分组 Top-N
-- MySQL         ORDER BY + LIMIT          ROW_NUMBER + 子查询
-- PostgreSQL    ORDER BY + LIMIT          DISTINCT ON / ROW_NUMBER
-- Oracle        FETCH FIRST / ROWNUM      ROW_NUMBER / RANK
-- Hive          ORDER BY + LIMIT          ROW_NUMBER + 子查询
-- BigQuery      ORDER BY + LIMIT          QUALIFY ROW_NUMBER <= N
--
-- BigQuery 的 QUALIFY 最简洁:
-- SELECT * FROM orders QUALIFY ROW_NUMBER() OVER (...) <= 3;
-- Hive 不支持 QUALIFY，必须用子查询包装

-- ============================================================
-- 8. 对引擎开发者的启示
-- ============================================================
-- 1. Top-K 优化器是排序的关键优化: 避免全量排序
-- 2. QUALIFY 应该被支持: 消除了 ROW_NUMBER + 子查询的冗长写法
-- 3. SORT BY + LIMIT 是分布式 Top-K 的好方案: 利用多 Reducer 并行
