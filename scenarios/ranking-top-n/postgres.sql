-- PostgreSQL: Top-N 查询与排名 (Ranking & Top-N)
--
-- 参考资料:
--   [1] PostgreSQL Documentation - LIMIT / FETCH
--       https://www.postgresql.org/docs/current/queries-limit.html
--   [2] PostgreSQL Documentation - DISTINCT ON
--       https://www.postgresql.org/docs/current/sql-select.html#SQL-DISTINCT

-- ============================================================
-- 1. 全局 Top-N
-- ============================================================

SELECT * FROM orders ORDER BY amount DESC LIMIT 10;
SELECT * FROM orders ORDER BY amount DESC FETCH FIRST 10 ROWS ONLY;     -- SQL 标准
SELECT * FROM orders ORDER BY amount DESC FETCH FIRST 10 ROWS WITH TIES;-- 含并列(13+)

-- ============================================================
-- 2. 分组 Top-N: 三种方式的对比
-- ============================================================

-- 方式 1: ROW_NUMBER（最通用）
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY amount DESC) AS rn
    FROM orders
) ranked WHERE rn <= 3;

-- 方式 2: DISTINCT ON（每组第 1 名，PostgreSQL 独有）
SELECT DISTINCT ON (customer_id) *
FROM orders ORDER BY customer_id, amount DESC;

-- 方式 3: LATERAL + LIMIT（有索引时最快）
SELECT c.customer_id, t.*
FROM customers c
CROSS JOIN LATERAL (
    SELECT order_id, amount FROM orders o
    WHERE o.customer_id = c.customer_id ORDER BY amount DESC LIMIT 3
) t;
-- LEFT JOIN LATERAL 保留没有订单的客户:
-- LEFT JOIN LATERAL (...) t ON TRUE

-- ============================================================
-- 3. 性能对比分析
-- ============================================================

-- ROW_NUMBER 方式:
--   全表扫描 + 窗口计算 → O(n log n)
--   不需要特定索引，但对大表可能慢

-- DISTINCT ON 方式:
--   Sort + Unique → O(n log n)
--   只能取每组第 1 名，不能取 Top-3
--   有 (customer_id, amount DESC) 索引时可走 Index Scan

-- LATERAL + LIMIT 方式:
--   对每个客户做索引扫描 → O(k * log n)（k=客户数）
--   有 (customer_id, amount DESC) 索引时最快
--   推荐索引:
CREATE INDEX idx_orders_cust_amt ON orders (customer_id, amount DESC);

-- 经验法则:
--   Top-1 → DISTINCT ON（最简洁）
--   Top-N + 有索引 → LATERAL + LIMIT（最快）
--   Top-N + 无索引 → ROW_NUMBER（通用）

-- ============================================================
-- 4. RANK / DENSE_RANK: 处理并列
-- ============================================================

SELECT * FROM (
    SELECT *, RANK() OVER (PARTITION BY customer_id ORDER BY amount DESC) AS rnk
    FROM orders
) ranked WHERE rnk <= 3;
-- RANK: 并列时跳号（1,1,3）
-- DENSE_RANK: 并列不跳号（1,1,2）
-- ROW_NUMBER: 无并列（1,2,3）

-- ============================================================
-- 5. 横向对比与对引擎开发者的启示
-- ============================================================

-- 1. WITH TIES (13+):
--   PostgreSQL: FETCH FIRST N ROWS WITH TIES
--   Oracle:     FETCH FIRST N ROWS WITH TIES (12c+)
--   SQL Server: TOP N WITH TIES
--   MySQL:      不支持
--
-- 2. DISTINCT ON:
--   PostgreSQL: 独有（最简洁的 Top-1）
--   其他:       均需 ROW_NUMBER 子查询
--
-- 3. LATERAL:
--   PostgreSQL: LATERAL JOIN (9.3+)
--   SQL Server: CROSS APPLY (2005+, 等价)
--
-- 对引擎开发者:
--   LATERAL + LIMIT 是"分组 Top-N"的最优执行路径:
--   利用索引的有序性，每组只扫描 N 条，避免全表窗口计算。
--   优化器应能识别这种模式并自动选择。
