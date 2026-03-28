-- MariaDB: CTE (公共表表达式, 10.2.1+)
-- 比 MySQL 8.0 更早支持
--
-- 参考资料:
--   [1] MariaDB Knowledge Base - WITH (CTE)
--       https://mariadb.com/kb/en/with/

-- ============================================================
-- 1. 非递归 CTE
-- ============================================================
WITH active_users AS (
    SELECT id, username, email FROM users WHERE age >= 18
)
SELECT * FROM active_users WHERE email LIKE '%@example.com';

-- 多个 CTE
WITH
    dept_stats AS (
        SELECT dept_id, AVG(salary) AS avg_salary FROM employees GROUP BY dept_id
    ),
    high_earners AS (
        SELECT e.* FROM employees e JOIN dept_stats d ON e.dept_id = d.dept_id
        WHERE e.salary > d.avg_salary * 1.5
    )
SELECT * FROM high_earners;

-- ============================================================
-- 2. 递归 CTE
-- ============================================================
WITH RECURSIVE org_tree AS (
    SELECT id, name, manager_id, 1 AS level
    FROM employees WHERE manager_id IS NULL
    UNION ALL
    SELECT e.id, e.name, e.manager_id, t.level + 1
    FROM employees e JOIN org_tree t ON e.manager_id = t.id
)
SELECT * FROM org_tree ORDER BY level, name;

-- 数字序列生成
WITH RECURSIVE numbers AS (
    SELECT 1 AS n
    UNION ALL
    SELECT n + 1 FROM numbers WHERE n < 100
)
SELECT * FROM numbers;

-- ============================================================
-- 3. CTE 物化行为
-- ============================================================
-- MariaDB 10.2+: CTE 的物化策略与 MySQL 8.0 不同
-- MariaDB 倾向于将 CTE 合并到外部查询 (merge), 而非总是物化
-- MySQL 8.0: 在某些情况下强制物化 CTE (即使 merge 更优)
-- MariaDB 10.4+: 优化器提示可以控制 CTE 物化行为
-- 这是性能差异的重要来源: 物化增加临时表开销, 但可能减少重复计算

-- ============================================================
-- 4. 对引擎开发者的启示
-- ============================================================
-- CTE 物化 vs 合并的选择:
--   物化: CTE 被多次引用时有利 (计算一次, 多次读取)
--   合并: CTE 只引用一次时有利 (避免临时表开销)
-- 递归 CTE 实现要点:
--   1. 工作表 (Working Table) + 中间表 (Intermediate Table) 模型
--   2. 每轮迭代: 执行递归部分 → 结果存入中间表 → 追加到工作表
--   3. 终止条件: 中间表为空
--   4. 防无限递归: max_recursive_iterations (MariaDB) / cte_max_recursion_depth (MySQL)
