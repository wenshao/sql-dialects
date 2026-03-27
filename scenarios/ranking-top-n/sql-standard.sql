-- SQL Standard: Top-N 查询（排名与分组取前 N 条）
--
-- 参考资料:
--   [1] ISO/IEC 9075 SQL Standard - Window Functions
--       https://www.iso.org/standard/76583.html
--   [2] SQL Standard - FETCH FIRST / OFFSET
--       https://modern-sql.com/feature/fetch-first

-- ============================================================
-- 示例数据上下文
-- ============================================================
-- 假设表结构:
--   orders(order_id INT, customer_id INT, amount DECIMAL(10,2), order_date DATE)
--   products(product_id INT, category VARCHAR, price DECIMAL(10,2), product_name VARCHAR)

-- ============================================================
-- 1. Top-N 整体（最简单场景）
-- ============================================================

-- 使用 FETCH FIRST（SQL:2008 标准语法）
SELECT order_id, customer_id, amount
FROM orders
ORDER BY amount DESC
FETCH FIRST 10 ROWS ONLY;

-- 使用 OFFSET ... FETCH（分页）
SELECT order_id, customer_id, amount
FROM orders
ORDER BY amount DESC
OFFSET 0 ROWS FETCH FIRST 10 ROWS ONLY;

-- WITH TIES：包含并列行
SELECT order_id, customer_id, amount
FROM orders
ORDER BY amount DESC
FETCH FIRST 10 ROWS WITH TIES;

-- ============================================================
-- 2. Top-N 分组（每组取前 N 条，如每个客户的前 3 笔订单）
-- ============================================================

-- ROW_NUMBER() 方式（严格取前 N，无并列）
SELECT *
FROM (
    SELECT order_id, customer_id, amount, order_date,
           ROW_NUMBER() OVER (
               PARTITION BY customer_id
               ORDER BY amount DESC
           ) AS rn
    FROM orders
) ranked
WHERE rn <= 3;

-- RANK() 方式（有并列时可能超过 N 条）
SELECT *
FROM (
    SELECT order_id, customer_id, amount, order_date,
           RANK() OVER (
               PARTITION BY customer_id
               ORDER BY amount DESC
           ) AS rnk
    FROM orders
) ranked
WHERE rnk <= 3;

-- DENSE_RANK() 方式（并列不跳号）
SELECT *
FROM (
    SELECT order_id, customer_id, amount, order_date,
           DENSE_RANK() OVER (
               PARTITION BY customer_id
               ORDER BY amount DESC
           ) AS drnk
    FROM orders
) ranked
WHERE drnk <= 3;

-- ============================================================
-- 3. ROW_NUMBER vs RANK vs DENSE_RANK 对比
-- ============================================================

-- 假设某客户有 3 笔金额：100, 100, 90
--   ROW_NUMBER: 1, 2, 3   （强制不同序号）
--   RANK:       1, 1, 3   （并列后跳号）
--   DENSE_RANK: 1, 1, 2   （并列不跳号）

SELECT order_id, customer_id, amount,
       ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY amount DESC) AS row_num,
       RANK()       OVER (PARTITION BY customer_id ORDER BY amount DESC) AS rank_num,
       DENSE_RANK() OVER (PARTITION BY customer_id ORDER BY amount DESC) AS dense_num
FROM orders;

-- ============================================================
-- 4. 关联子查询方式（无窗口函数的替代方案）
-- ============================================================

-- 取每个客户金额最大的前 3 笔订单
SELECT o.*
FROM orders o
WHERE (
    SELECT COUNT(*)
    FROM orders o2
    WHERE o2.customer_id = o.customer_id
      AND o2.amount > o.amount
) < 3
ORDER BY o.customer_id, o.amount DESC;

-- ============================================================
-- 5. LATERAL / CROSS APPLY（SQL:2003 标准）
-- ============================================================

-- 标准 SQL 的 LATERAL 子查询
SELECT c.customer_id, t.order_id, t.amount
FROM (SELECT DISTINCT customer_id FROM orders) c,
LATERAL (
    SELECT order_id, amount
    FROM orders o
    WHERE o.customer_id = c.customer_id
    ORDER BY amount DESC
    FETCH FIRST 3 ROWS ONLY
) t;

-- ============================================================
-- 6. 性能考量
-- ============================================================

-- 建议在 (customer_id, amount DESC) 上建索引以优化分组 Top-N
-- ROW_NUMBER 方式需要全表扫描后排名再过滤
-- LATERAL 方式可以利用索引做 index scan + limit
-- 关联子查询在大数据集上性能较差
-- FETCH FIRST WITH TIES 需要额外比较，略慢于 ROWS ONLY
