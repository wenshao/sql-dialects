-- Oracle: Top-N 查询与排名
--
-- 参考资料:
--   [1] Oracle SQL Language Reference - Analytic Functions
--       https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/Analytic-Functions.html
--   [2] Oracle SQL Language Reference - Row Limiting Clause
--       https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/SELECT.html

-- ============================================================
-- 1. 全局 Top-N
-- ============================================================

-- FETCH FIRST（12c+，推荐）
SELECT order_id, customer_id, amount FROM orders
ORDER BY amount DESC FETCH FIRST 10 ROWS ONLY;

-- WITH TIES（包含同值行）
SELECT order_id, customer_id, amount FROM orders
ORDER BY amount DESC FETCH FIRST 10 ROWS WITH TIES;

-- OFFSET + FETCH（分页）
SELECT order_id, customer_id, amount FROM orders
ORDER BY amount DESC
OFFSET 20 ROWS FETCH NEXT 10 ROWS ONLY;

-- FETCH PERCENT
SELECT order_id, customer_id, amount FROM orders
ORDER BY amount DESC FETCH FIRST 10 PERCENT ROWS ONLY;

-- ROWNUM（Pre-12c，经典三层嵌套）
SELECT * FROM (
    SELECT a.*, ROWNUM rnum FROM (
        SELECT order_id, customer_id, amount FROM orders ORDER BY amount DESC
    ) a WHERE ROWNUM <= 30
) WHERE rnum > 20;

-- 注意 ROWNUM 陷阱: ROWNUM > 5 永远返回 0 行（见 pagination 文件）

-- ============================================================
-- 2. 分组 Top-N
-- ============================================================

-- ROW_NUMBER: 每组取严格 Top-N（无并列）
SELECT * FROM (
    SELECT order_id, customer_id, amount,
           ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY amount DESC) AS rn
    FROM orders
) WHERE rn <= 3;

-- RANK: 允许并列（可能超过 N 行）
SELECT * FROM (
    SELECT order_id, customer_id, amount,
           RANK() OVER (PARTITION BY customer_id ORDER BY amount DESC) AS rnk
    FROM orders
) WHERE rnk <= 3;

-- DENSE_RANK: 允许并列且排名无间隙
SELECT * FROM (
    SELECT order_id, customer_id, amount,
           DENSE_RANK() OVER (PARTITION BY customer_id ORDER BY amount DESC) AS drnk
    FROM orders
) WHERE drnk <= 3;

-- ============================================================
-- 3. LATERAL / CROSS APPLY（12c+，分组 Top-N 的优雅方案）
-- ============================================================

SELECT c.customer_id, t.order_id, t.amount
FROM customers c
CROSS APPLY (
    SELECT order_id, amount FROM orders o
    WHERE o.customer_id = c.customer_id
    ORDER BY amount DESC FETCH FIRST 3 ROWS ONLY
) t;

-- OUTER APPLY（包含无订单的客户）
SELECT c.customer_id, c.username, t.order_id, t.amount
FROM customers c
OUTER APPLY (
    SELECT order_id, amount FROM orders o
    WHERE o.customer_id = c.customer_id
    ORDER BY amount DESC FETCH FIRST 3 ROWS ONLY
) t;

-- ============================================================
-- 4. KEEP (DENSE_RANK): Oracle 独有的组内取值聚合
-- ============================================================

-- 每个客户金额最大的订单 ID（不需要窗口函数!）
SELECT customer_id,
       MAX(order_id) KEEP (DENSE_RANK FIRST ORDER BY amount DESC) AS top_order_id,
       MAX(amount) AS max_amount
FROM orders GROUP BY customer_id;

-- KEEP 的设计:
--   在 GROUP BY 中，按指定排序取第一行/最后一行的聚合值。
--   等价于 ROW_NUMBER() + WHERE rn = 1，但更简洁高效（纯聚合操作）。
--   只能取第一名（不能取 Top-N），但效率极高。
--
-- 横向对比: 其他数据库没有等价函数，需要子查询或窗口函数。

-- ============================================================
-- 5. 关联子查询方式（兼容所有版本）
-- ============================================================

SELECT o.* FROM orders o
WHERE (SELECT COUNT(*) FROM orders o2
       WHERE o2.customer_id = o.customer_id AND o2.amount > o.amount
) < 3
ORDER BY o.customer_id, o.amount DESC;

-- ============================================================
-- 6. 性能考量
-- ============================================================

CREATE INDEX idx_orders_customer_amount ON orders (customer_id, amount DESC);

-- 性能排序:
-- 1. CROSS APPLY + FETCH FIRST: 最优（每组只计算 N 行）
-- 2. ROW_NUMBER + WHERE rn <= N: 优化器可优化为 Top-N 排序
-- 3. KEEP (DENSE_RANK): 纯聚合，只能取 Top-1 但最快
-- 4. ROWNUM: Pre-12c 的最优选择
-- 5. 关联子查询: 最慢但兼容性最好

-- ============================================================
-- 7. 对引擎开发者的总结
-- ============================================================
-- 1. ROW_NUMBER + WHERE rn <= N 是最通用的分组 Top-N 方案。
-- 2. 优化器应识别 ROW_NUMBER() + 外层 WHERE 模式并优化为 Top-N 排序。
-- 3. CROSS APPLY/LATERAL 是分组 Top-N 的最优方案（每组只扫描 N 行）。
-- 4. KEEP (DENSE_RANK) 是 Oracle 独有的取组内排名值的高效聚合。
-- 5. ROWNUM 的语义陷阱（在 WHERE 前分配）是新引擎应避免的设计。
