-- MaxCompute (ODPS): 执行计划与查询分析
--
-- 参考资料:
--   [1] MaxCompute Documentation - EXPLAIN
--       https://help.aliyun.com/document_detail/464257.html
--   [2] MaxCompute Documentation - 性能优化
--       https://help.aliyun.com/document_detail/102613.html

-- ============================================================
-- EXPLAIN 基本用法
-- ============================================================

EXPLAIN SELECT * FROM users WHERE age > 25;

-- 输出包含：
-- Job 的执行阶段和依赖关系
-- 每个阶段的操作符

-- ============================================================
-- COST SQL（估算资源消耗）
-- ============================================================

-- 估算 SQL 的资源消耗（不执行）
COST SQL SELECT * FROM users WHERE age > 25;

-- 输出：
-- Input: xxx bytes
-- Output: xxx bytes
-- Complexity: xxx

-- ============================================================
-- Logview（作业执行日志）
-- ============================================================

-- 执行查询后获得 Logview URL
-- 通过 Logview 查看：
-- 1. 作业 DAG（各阶段依赖关系）
-- 2. 每个阶段的 Instance 数量
-- 3. 数据读写量
-- 4. 执行时间
-- 5. 资源使用（CPU、内存）

-- ============================================================
-- 执行计划关键概念
-- ============================================================

-- Map 阶段    数据读取和初步处理
-- Reduce 阶段 数据汇总和输出
-- Join 阶段   数据连接
-- M 任务      Map 任务
-- R 任务      Reduce 任务
-- J 任务      Join 任务

-- ============================================================
-- Information Schema
-- ============================================================

-- 查看历史作业
SELECT * FROM INFORMATION_SCHEMA.TASKS_HISTORY
WHERE task_type = 'SQL'
ORDER BY create_time DESC
LIMIT 10;

-- 查看表的大小
SELECT table_name, data_length, table_rows
FROM INFORMATION_SCHEMA.TABLES
WHERE table_schema = 'myproject';

-- ============================================================
-- 性能诊断
-- ============================================================

-- 查看作业队列
SHOW P;  -- 显示正在运行和排队的作业

-- ============================================================
-- 优化要点
-- ============================================================

-- 1. 分区裁剪：WHERE 条件中使用分区列
SELECT * FROM orders WHERE dt = '2024-01-01';

-- 2. 列裁剪：只选择需要的列
SELECT user_id, amount FROM orders;

-- 3. MapJoin：小表广播
SELECT /*+ MAPJOIN(u) */ u.username, o.amount
FROM users u JOIN orders o ON u.id = o.user_id;

-- 注意：MaxCompute 使用分布式 Map-Reduce 模型
-- 注意：COST SQL 估算资源消耗但不执行查询
-- 注意：Logview 是分析作业性能的主要工具
-- 注意：分区裁剪和列裁剪是最重要的优化手段
-- 注意：MAPJOIN Hint 将小表广播到所有节点
