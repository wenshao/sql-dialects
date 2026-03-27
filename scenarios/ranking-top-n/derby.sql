-- Apache Derby: Top-N 查询（排名与分组取前 N 条）
--
-- 参考资料:
--   [1] Apache Derby Documentation - ROW_NUMBER
--       https://db.apache.org/derby/docs/10.15/ref/
--   [2] Apache Derby Documentation - FETCH FIRST
--       https://db.apache.org/derby/docs/10.15/ref/rrefsqljoffsetfetch.html

-- ============================================================
-- 示例数据上下文
-- ============================================================
-- 假设表结构:
--   orders(order_id INT, customer_id INT, amount DECIMAL(10,2), order_date DATE)

-- ============================================================
-- 1. Top-N 整体
-- ============================================================

-- FETCH FIRST（Derby 标准方式）
SELECT order_id, customer_id, amount
FROM orders
ORDER BY amount DESC
FETCH FIRST 10 ROWS ONLY;

-- OFFSET + FETCH（Derby 10.5+）
SELECT order_id, customer_id, amount
FROM orders
ORDER BY amount DESC
OFFSET 20 ROWS FETCH NEXT 10 ROWS ONLY;

-- ============================================================
-- 2. Top-N 分组（Derby 10.4+ 窗口函数）
-- ============================================================

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

-- 注意：Derby 仅支持 ROW_NUMBER()，不支持 RANK/DENSE_RANK

-- ============================================================
-- 3. 关联子查询方式
-- ============================================================

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
-- 4. 性能考量
-- ============================================================

CREATE INDEX idx_orders_customer_amount ON orders (customer_id, amount DESC);

-- Derby 仅支持 ROW_NUMBER()，不支持 RANK / DENSE_RANK
-- FETCH FIRST 是 Derby 标准分页语法
-- Derby 是嵌入式数据库，适合小数据集
-- 注意：不支持 LATERAL / CROSS APPLY / QUALIFY / CTE / LIMIT
