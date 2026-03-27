-- PostgreSQL: 集合操作 (Set Operations)
--
-- 参考资料:
--   [1] PostgreSQL Documentation - UNION, INTERSECT, EXCEPT
--       https://www.postgresql.org/docs/current/queries-union.html
--   [2] PostgreSQL Source - union planning
--       https://github.com/postgres/postgres/blob/master/src/backend/optimizer/prep/prepunion.c

-- ============================================================
-- 1. UNION / UNION ALL
-- ============================================================

-- UNION: 去重合并（内部排序或哈希去重）
SELECT id, name FROM employees UNION SELECT id, name FROM contractors;

-- UNION ALL: 保留重复（直接追加，更快）
SELECT id, name FROM employees UNION ALL SELECT id, name FROM contractors;

-- ============================================================
-- 2. INTERSECT / EXCEPT (及 ALL 变体)
-- ============================================================

SELECT id FROM employees INTERSECT SELECT id FROM project_members;
SELECT id FROM employees INTERSECT ALL SELECT id FROM project_members;
-- INTERSECT ALL: 保留重复次数（取两边重复次数的较小值）

SELECT id FROM employees EXCEPT SELECT id FROM terminated;
SELECT id FROM employees EXCEPT ALL SELECT id FROM terminated;

-- PostgreSQL 从第一个版本就支持所有集合操作（含 ALL 变体）
-- 对比: MySQL 直到 8.0.31 才支持 INTERSECT / EXCEPT

-- ============================================================
-- 3. 优先级与括号
-- ============================================================

-- 优先级: INTERSECT > UNION = EXCEPT
-- 即: INTERSECT 先计算
SELECT id FROM A UNION SELECT id FROM B INTERSECT SELECT id FROM C;
-- 等价于: A UNION (B INTERSECT C)

-- 使用括号明确意图
(SELECT id FROM A UNION SELECT id FROM B)
INTERSECT
SELECT id FROM C;

-- ============================================================
-- 4. ORDER BY / LIMIT 与集合操作
-- ============================================================

-- ORDER BY 作用于整个结果，只能出现在最后
SELECT name, salary FROM employees
UNION ALL
SELECT name, salary FROM contractors
ORDER BY salary DESC LIMIT 10;

-- 子查询中限制单个分支
(SELECT name FROM employees ORDER BY name LIMIT 5)
UNION ALL
(SELECT name FROM contractors ORDER BY name LIMIT 5);

-- FETCH FIRST 语法
SELECT name FROM employees UNION ALL SELECT name FROM contractors
ORDER BY name FETCH FIRST 10 ROWS ONLY;

-- ============================================================
-- 5. 集合操作的内部实现
-- ============================================================

-- UNION (去重):
--   策略 1: Hash Aggregate（构建哈希表去重）—— 通常更快
--   策略 2: Sort + Unique（排序后去重）—— 内存可控
--   选择取决于数据量和 work_mem
--
-- UNION ALL: 直接 Append 节点拼接结果（最快）
--
-- INTERSECT / EXCEPT:
--   通常使用 Hash SetOp 或 Sort SetOp
--   Hash SetOp: 构建哈希表，计数标记来源
--   Sort SetOp: 排序后合并扫描

EXPLAIN SELECT id FROM employees UNION SELECT id FROM contractors;
-- 观察 HashAggregate / Sort + Unique 节点

-- ============================================================
-- 6. 类型转换规则
-- ============================================================

-- 集合操作要求对应列类型兼容
-- PostgreSQL 会尝试隐式转换:
SELECT 1, 'text' UNION SELECT 2, 'text';          -- INT + TEXT，OK
SELECT 1::INT UNION SELECT 1.5::NUMERIC;           -- INT → NUMERIC 提升

-- 不兼容时需显式 CAST
SELECT id, name::TEXT FROM employees
UNION
SELECT id, CAST(contractor_name AS TEXT) FROM contractors;

-- 对比 MySQL: 类型转换更宽松（可能静默截断）

-- ============================================================
-- 7. CTE 与集合操作结合
-- ============================================================

WITH active AS (SELECT id, name FROM employees WHERE active = TRUE)
SELECT id, name FROM active
UNION
SELECT id, name FROM contractors WHERE active = TRUE;

-- ============================================================
-- 8. 横向对比: 集合操作差异
-- ============================================================

-- 1. INTERSECT / EXCEPT:
--   PostgreSQL: 全版本支持（含 ALL 变体）
--   MySQL:      8.0.31+ 才支持 INTERSECT / EXCEPT
--   Oracle:     MINUS（不是 EXCEPT）, INTERSECT（全版本支持）
--   SQL Server: INTERSECT / EXCEPT (2005+)
--
-- 2. EXCEPT vs MINUS:
--   PostgreSQL: EXCEPT（SQL 标准）
--   Oracle:     MINUS（非标准，语义相同）
--   MySQL 8.0.31+: 同时支持 EXCEPT 和 MINUS
--
-- 3. 集合操作中的 FOR UPDATE:
--   PostgreSQL: 不支持（集合操作结果无法锁定）
--   SQL Server: 不支持
--   Oracle:     不支持
--
-- 4. 并行执行:
--   PostgreSQL 14+: 支持并行 UNION ALL（Parallel Append）

-- ============================================================
-- 9. 对引擎开发者的启示
-- ============================================================

-- (1) UNION ALL 应该是零开销的 Append:
--     不需要排序或哈希，只需流式拼接子查询结果。
--     实现: 多个子计划通过 Append 节点顺序执行。
--
-- (2) UNION 去重的策略选择:
--     Hash 去重 O(n)（内存消耗大），Sort 去重 O(n log n)（可溢出磁盘）。
--     优化器应根据估算行数和 work_mem 选择。
--
-- (3) INTERSECT ALL / EXCEPT ALL 的语义不直觉:
--     INTERSECT ALL: 每个值的出现次数取两边的较小值
--     EXCEPT ALL: 每个值的出现次数取差值（左边次数 - 右边次数）
--     实现: 通常用 hash/sort + 计数器。

-- ============================================================
-- 10. 版本演进
-- ============================================================
-- PostgreSQL 全版本: UNION, UNION ALL, INTERSECT, EXCEPT（含 ALL）
-- PostgreSQL 10:    并行 UNION ALL 子查询
-- PostgreSQL 14:    Parallel Append（并行执行 UNION ALL 分支）
