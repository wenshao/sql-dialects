-- MySQL: JOIN
--
-- 参考资料:
--   [1] MySQL 8.0 Reference Manual - JOIN Clause
--       https://dev.mysql.com/doc/refman/8.0/en/join.html
--   [2] MySQL 8.0 Reference Manual - Nested-Loop Join Algorithms
--       https://dev.mysql.com/doc/refman/8.0/en/nested-loop-joins.html
--   [3] MySQL 8.0 Reference Manual - Hash Join Optimization
--       https://dev.mysql.com/doc/refman/8.0/en/hash-joins.html
--   [4] MySQL 8.0 Reference Manual - EXPLAIN Output Format
--       https://dev.mysql.com/doc/refman/8.0/en/explain-output.html

-- ============================================================
-- 1. 基本语法
-- ============================================================

-- INNER JOIN
SELECT u.username, o.amount
FROM users u
INNER JOIN orders o ON u.id = o.user_id;

-- LEFT JOIN（LEFT OUTER JOIN）
SELECT u.username, o.amount
FROM users u
LEFT JOIN orders o ON u.id = o.user_id;

-- RIGHT JOIN
SELECT u.username, o.amount
FROM users u
RIGHT JOIN orders o ON u.id = o.user_id;

-- CROSS JOIN（笛卡尔积）
SELECT u.username, r.role_name
FROM users u
CROSS JOIN roles r;

-- 自连接
SELECT e.username AS employee, m.username AS manager
FROM users e
LEFT JOIN users m ON e.manager_id = m.id;

-- 多表 JOIN
SELECT u.username, o.amount, p.product_name
FROM users u
JOIN orders o ON u.id = o.user_id
JOIN order_items oi ON o.id = oi.order_id
JOIN products p ON oi.product_id = p.id;

-- USING（连接列同名时简写）
SELECT * FROM users JOIN orders USING (user_id);

-- NATURAL JOIN（自动匹配同名列，不推荐: 列名变化会默默改变语义）
SELECT * FROM users NATURAL JOIN orders;

-- ============================================================
-- 2. JOIN 优化器的工作方式（对引擎开发者关键）
-- ============================================================

-- 2.1 MySQL JOIN 算法的演进
--
-- Simple Nested Loop Join（最朴素，MySQL 几乎不用）:
--   for each row in outer_table:
--     for each row in inner_table:
--       if join_condition: output
--   复杂度: O(M * N)，无缓冲，每次循环都访问内表全量数据
--
-- Index Nested Loop Join（有索引时的首选）:
--   for each row in outer_table:
--     index_lookup(inner_table, join_key)  -- 通过索引定位
--   复杂度: O(M * log(N))，利用内表的索引大幅减少扫描
--   这是 MySQL 5.7 及之前最主要的 JOIN 算法
--   EXPLAIN 中表现为: type=ref/eq_ref
--
-- Block Nested Loop Join (BNL, 5.6+, 8.0.18 前):
--   将外表的多行缓存到 join buffer（join_buffer_size，默认 256KB）
--   然后扫描内表时一次性与 buffer 中的多行匹配
--   减少内表的扫描次数: 从 M 次降为 M / buffer_rows 次
--   EXPLAIN 中表现为: Extra: Using join buffer (Block Nested Loop)
--   适用: 内表无可用索引时的 fallback 方案
--
-- Hash Join (8.0.18+, 推荐):
--   (1) build 阶段: 读取较小的表（build table），构建哈希表
--   (2) probe 阶段: 逐行读取较大的表（probe table），在哈希表中查找匹配
--   复杂度: O(M + N)，内存中完成（超出 join_buffer_size 则溢出到磁盘）
--   EXPLAIN 中表现为: Extra: Using join buffer (hash join)
--   适用条件: 等值 JOIN 且无可用索引（8.0.20+ 也支持非等值条件的 hash join）
--   8.0.20: BNL 被 Hash Join 完全替代（BNL 移除）

-- 2.2 优化器如何选择 JOIN 顺序
-- MySQL 优化器使用穷举法（n! 排列）或贪心算法选择最优 JOIN 顺序:
--   optimizer_search_depth: 控制穷举深度（默认 62，表数超过此值用贪心）
--   optimizer_prune_level: 启用启发式剪枝（默认开启）
--
-- 可以通过 STRAIGHT_JOIN 强制指定 JOIN 顺序:
SELECT u.username, o.amount
FROM users u
STRAIGHT_JOIN orders o ON u.id = o.user_id;
-- 按 FROM 子句中的顺序执行（不让优化器重排）
-- 诊断用途: 怀疑优化器选错 JOIN 顺序时，手动测试

-- 2.3 JOIN 的成本模型
-- MySQL 8.0 使用成本模型（cost model）选择执行计划:
--   io_cost: 从磁盘/内存读取数据页的代价
--   cpu_cost: 比较、过滤、排序的 CPU 代价
--   memory_cost: 内存分配和 hash 表构建的代价
-- 成本参数存储在 mysql.server_cost 和 mysql.engine_cost 表中
-- 可调整（但不推荐盲目修改）

-- ============================================================
-- 3. 不支持 FULL OUTER JOIN 的原因和模拟方案
-- ============================================================

-- MySQL 不支持 FULL OUTER JOIN（唯一不支持的主流 RDBMS）
-- 原因:
--   (1) MySQL 的 JOIN 实现基于 Nested Loop，FULL OUTER JOIN 难以用 NLJ 高效实现
--   (2) Hash Join（8.0.18+）理论上可以支持，但到目前仍未添加语法
--   (3) 使用频率相对较低，优先级不高

-- 模拟方案（UNION ALL 方式）:
SELECT u.id, u.username, o.amount
FROM users u LEFT JOIN orders o ON u.id = o.user_id
UNION ALL
SELECT u.id, u.username, o.amount
FROM users u RIGHT JOIN orders o ON u.id = o.user_id
WHERE u.id IS NULL;
-- 说明: LEFT JOIN 保留左表所有行，RIGHT JOIN 只取右表独有行（WHERE u.id IS NULL）
-- 用 UNION ALL 而非 UNION: 避免去重开销（两部分结果天然不重复）

-- 其他数据库:
--   PostgreSQL: 支持 FULL OUTER JOIN（通过 Hash Join 实现）
--   Oracle:     支持 FULL OUTER JOIN
--   SQL Server: 支持 FULL OUTER JOIN（通过 Merge Join 或 Hash Join）
--   SQLite:     不支持（与 MySQL 相同，用 UNION ALL 模拟）

-- ============================================================
-- 4. LATERAL 的实现和性能影响（8.0.14+）
-- ============================================================

-- LATERAL 允许派生表引用前面 FROM 子句中的列（打破了派生表的独立性）
-- 等价于 SQL Server 的 CROSS APPLY / OUTER APPLY

-- 场景: 获取每个用户的最新 3 笔订单
SELECT u.username, latest.amount, latest.created_at
FROM users u
JOIN LATERAL (
    SELECT amount, created_at
    FROM orders
    WHERE user_id = u.id
    ORDER BY created_at DESC LIMIT 3
) latest ON TRUE;

-- LEFT JOIN LATERAL（保留没有订单的用户，等价于 OUTER APPLY）
SELECT u.username, latest.amount
FROM users u
LEFT JOIN LATERAL (
    SELECT amount FROM orders WHERE user_id = u.id ORDER BY created_at DESC LIMIT 1
) latest ON TRUE;

-- 4.1 LATERAL 的执行模型
-- LATERAL 在内部转化为关联子查询:
--   for each row in users:
--     execute lateral_subquery(u.id) → 返回结果集
--     join results
-- 这意味着 LATERAL 的执行代价与外表行数成正比。
-- 如果外表有 100 万行，LATERAL 子查询执行 100 万次。
--
-- 优化关键: LATERAL 子查询内部的索引
--   确保 orders.user_id 有索引，且 ORDER BY + LIMIT 能用索引避免排序
--   EXPLAIN: LATERAL 子查询应显示 type=ref，而不是全表扫描

-- 4.2 LATERAL 解决的问题（替代方案对比）
-- 问题: "每组取 Top-N"
--
-- 方案 A: LATERAL（最直观）
-- 见上方示例
--
-- 方案 B: 窗口函数 + 子查询
SELECT * FROM (
    SELECT u.username, o.amount, o.created_at,
           ROW_NUMBER() OVER (PARTITION BY o.user_id ORDER BY o.created_at DESC) AS rn
    FROM users u JOIN orders o ON u.id = o.user_id
) ranked WHERE rn <= 3;
-- 问题: 需要先对所有订单计算 ROW_NUMBER，再过滤（可能扫描更多数据）
--
-- 方案 C: 关联子查询
-- SELECT ... WHERE o.id IN (SELECT id FROM orders WHERE user_id = u.id ORDER BY ... LIMIT 3)
-- MySQL 8.0 前: 性能差（子查询可能不被优化为半连接）

-- ============================================================
-- 5. 横向对比: JOIN 算法在各引擎中的选择
-- ============================================================

-- 5.1 Nested Loop Join (NLJ)
--   MySQL:      5.7 及之前的唯一算法（Index NLJ 为主）
--   PostgreSQL: 支持，小表 + 有索引时优化器会选择
--   Oracle:     支持，有索引的 OLTP 查询常用
--   适用场景:   小表驱动大表、索引覆盖、返回少量行

-- 5.2 Hash Join
--   MySQL:      8.0.18+ 支持（替代 BNL）
--   PostgreSQL: 从最早版本就支持（实现最成熟）
--   Oracle:     从 7.3 开始支持（实现最早之一）
--   SQL Server: 从 7.0 开始支持
--   ClickHouse: 默认 JOIN 算法（列式引擎适合批量 hash 匹配）
--   适用场景:   大表等值 JOIN、无索引、数据仓库查询

-- 5.3 Sort-Merge Join
--   MySQL:      不支持（历史原因: 早期只有 NLJ）
--   PostgreSQL: 支持（数据已排序时效率高）
--   Oracle:     支持（SORT MERGE JOIN hint: /*+ USE_MERGE(t1 t2) */）
--   SQL Server: 支持（数据已按 JOIN key 排序时自动选择）
--   适用场景:   JOIN key 上有聚集索引/排序、两表大小相近、非等值 JOIN
--
--   MySQL 不支持 Sort-Merge Join 的影响:
--     对已排序数据的 JOIN 可能不如 PG/Oracle 高效
--     8.0.18+ 的 Hash Join 部分弥补了这个差距

-- 5.4 各引擎的 JOIN 算法总结
-- | 引擎       | NLJ | Hash Join | Sort-Merge | Broadcast | Shuffle |
-- |-----------|-----|-----------|------------|-----------|---------|
-- | MySQL     | Yes | 8.0.18+   | No         | N/A       | N/A     |
-- | PostgreSQL| Yes | Yes       | Yes        | N/A       | N/A     |
-- | Oracle    | Yes | Yes       | Yes        | RAC       | RAC     |
-- | SQL Server| Yes | Yes       | Yes        | N/A       | N/A     |
-- | ClickHouse| No  | Yes       | Yes        | Yes       | Yes     |
-- | Spark SQL | No  | Yes       | Yes        | Yes       | Yes     |
-- | TiDB      | Yes | Yes(TiFlash)| No       | Yes       | Yes     |

-- 分布式引擎的额外 JOIN 策略:
--   Broadcast Join: 将小表广播到所有节点（适合小表 JOIN 大表）
--   Shuffle Join:   按 JOIN key 重新分区两张表到相同节点（大表 JOIN 大表）
--   Colocated Join: 如果两表的分区键 = JOIN key，直接本地 JOIN（最优）
--   这些策略是分布式引擎性能的关键，单机引擎无此概念

-- ============================================================
-- 6. 对引擎开发者: JOIN 实现的设计决策
-- ============================================================

-- 决策 1: 最少应支持哪些 JOIN 算法?
--   OLTP 引擎: Index NLJ 是必须的（利用索引是 OLTP 的核心）
--   OLAP 引擎: Hash Join 是必须的（大表等值 JOIN 的最优解）
--   完整引擎: NLJ + Hash Join + Sort-Merge Join（三种都支持，优化器自动选择）
--   MySQL 长期只有 NLJ 导致无索引 JOIN 性能差，直到 8.0.18 才补上 Hash Join

-- 决策 2: JOIN 顺序优化
--   穷举搜索: n! 种排列，精确但指数级复杂度（MySQL 的做法，表数 < 阈值时）
--   动态规划: 避免重复子问题（PostgreSQL 的 GEQO，表数 > 12 时启用遗传算法）
--   贪心算法: 每步选择当前最优，不保证全局最优（大量表时的 fallback）
--   左深树 vs 灌木树: MySQL/PG 只考虑左深树（简化搜索空间），Spark 考虑灌木树

-- 决策 3: 内存与磁盘溢出
--   Hash Join 的 build table 超出内存时:
--   MySQL: Grace Hash Join（分区后溢出到磁盘临时文件）
--   PG:    同样使用分区溢出（hybrid hash join）
--   关键参数: join_buffer_size (MySQL) / work_mem (PG) / hash_join_threshold (ClickHouse)

-- ============================================================
-- 7. 版本演进
-- ============================================================
-- MySQL 5.1:  优化器改进: 子查询转 semi-join（有限场景）
-- MySQL 5.6:  BKA (Batched Key Access) 优化 NLJ
-- MySQL 8.0.14: LATERAL 派生表支持
-- MySQL 8.0.18: Hash Join 引入（无索引等值 JOIN 的性能革命）
-- MySQL 8.0.20: BNL 完全被 Hash Join 替代; 非等值条件 Hash Join 支持
-- MySQL 8.0.23: Hash Join 支持 anti-join 和 semi-join
