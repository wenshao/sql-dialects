-- TDSQL: 聚合函数 (Aggregate Functions)
--
-- 参考资料:
--   [1] TDSQL-C MySQL Documentation
--       https://cloud.tencent.com/document/product/1003
--   [2] TDSQL MySQL Documentation
--       https://cloud.tencent.com/document/product/557
--   [3] MySQL 8.0 Reference Manual - Aggregate Functions
--       https://dev.mysql.com/doc/refman/8.0/en/aggregate-functions.html
--
-- 说明: TDSQL 是腾讯云分布式数据库，聚合函数与 MySQL 兼容。
--       分布式环境下聚合需要合并各分片结果，有额外性能注意事项。

-- ============================================================
-- 1. 基本聚合函数
-- ============================================================

SELECT COUNT(*) FROM users;                           -- 总行数
SELECT COUNT(id) FROM users;                          -- 非 NULL 行数
SELECT COUNT(DISTINCT city) FROM users;               -- 去重计数
SELECT SUM(amount) FROM orders;                       -- 求和
SELECT AVG(amount) FROM orders;                       -- 平均值
SELECT MIN(created_at) FROM orders;                   -- 最小值
SELECT MAX(created_at) FROM orders;                   -- 最大值

-- 聚合函数忽略 NULL（COUNT(*)除外）
SELECT SUM(NULL);                                     -- NULL
SELECT AVG(NULL);                                     -- NULL
SELECT COUNT(col_with_nulls) FROM users;              -- 仅计算非 NULL 行

-- ============================================================
-- 2. GROUP BY 分组聚合
-- ============================================================

-- 单列分组
SELECT city, COUNT(*) AS cnt, AVG(age) AS avg_age
FROM users GROUP BY city;

-- 多列分组
SELECT city, status, COUNT(*) AS cnt
FROM users GROUP BY city, status;

-- GROUP BY + HAVING（分组后过滤）
SELECT city, COUNT(*) AS cnt
FROM users
GROUP BY city
HAVING COUNT(*) > 10;

-- HAVING 与 WHERE 的区别:
--   WHERE: 在分组前过滤行（不能使用聚合函数）
--   HAVING: 在分组后过滤（可以使用聚合函数）

-- ============================================================
-- 3. WITH ROLLUP: 层级汇总
-- ============================================================

-- ROLLUP: 生成小计行和总计行
SELECT city, COUNT(*) AS cnt
FROM users GROUP BY city WITH ROLLUP;

-- 多列 ROLLUP
SELECT city, status, COUNT(*) AS cnt
FROM users GROUP BY city, status WITH ROLLUP;
-- 生成: (city, status), (city, NULL), (NULL, NULL) 三级汇总

-- GROUPING() 函数: 判断是否是汇总行
SELECT city, GROUPING(city) AS is_subtotal, COUNT(*)
FROM users GROUP BY city WITH ROLLUP;

-- ============================================================
-- 4. GROUP_CONCAT: 字符串聚合
-- ============================================================

-- 基本用法
SELECT GROUP_CONCAT(username ORDER BY username SEPARATOR ', ') FROM users;

-- 分组字符串聚合
SELECT department,
    GROUP_CONCAT(name ORDER BY name SEPARATOR '; ') AS members
FROM employees GROUP BY department;

-- 去重
SELECT GROUP_CONCAT(DISTINCT city SEPARATOR ', ') FROM users;

-- 分布式注意事项:
--   跨分片 GROUP_CONCAT 由代理层合并
--   默认最大长度: group_concat_max_len = 1024
--   SET SESSION group_concat_max_len = 1000000;  -- 调大限制
--   跨分片合并可能不保序，建议显式 ORDER BY

-- ============================================================
-- 5. JSON 聚合 (MySQL 5.7+/TDSQL)
-- ============================================================

-- JSON_ARRAYAGG: 聚合为 JSON 数组
SELECT JSON_ARRAYAGG(username) FROM users;
SELECT department, JSON_ARRAYAGG(name) FROM employees GROUP BY department;

-- JSON_OBJECTAGG: 聚合为 JSON 对象
SELECT JSON_OBJECTAGG(username, age) FROM users;
-- 结果: {"alice": 25, "bob": 30, ...}

-- ============================================================
-- 6. 统计聚合函数
-- ============================================================

-- 标准差与方差
SELECT STD(amount) FROM orders;                       -- 样本标准差（STDDEV 别名）
SELECT STDDEV(amount) FROM orders;                    -- 样本标准差
SELECT STDDEV_POP(amount) FROM orders;                -- 总体标准差
SELECT STDDEV_SAMP(amount) FROM orders;               -- 样本标准差
SELECT VARIANCE(amount) FROM orders;                  -- 样本方差
SELECT VAR_POP(amount) FROM orders;                   -- 总体方差
SELECT VAR_SAMP(amount) FROM orders;                  -- 样本方差

-- ============================================================
-- 7. BIT 聚合函数
-- ============================================================

SELECT BIT_AND(flags) FROM settings;                  -- 按位与
SELECT BIT_OR(flags) FROM settings;                   -- 按位或
SELECT BIT_XOR(flags) FROM settings;                  -- 按位异或

-- ============================================================
-- 8. 条件聚合（CASE WHEN 模拟）
-- ============================================================

-- MySQL 不支持 FILTER 子句，用 CASE WHEN 实现
SELECT
    COUNT(*) AS total,
    SUM(CASE WHEN age > 30 THEN 1 ELSE 0 END) AS over_30,
    SUM(CASE WHEN age <= 30 THEN 1 ELSE 0 END) AS under_30,
    AVG(CASE WHEN status = 'active' THEN score ELSE NULL END) AS active_avg_score
FROM users;

-- 等价于 PostgreSQL 的:
--   COUNT(*) FILTER (WHERE age > 30)

-- ============================================================
-- 9. 分布式聚合性能要点
-- ============================================================

-- 1. COUNT(DISTINCT) 需要全局去重，可能性能较差
--    替代方案: 使用 HyperLogLog 近似计数（如果支持）
--    或在业务层接受近似结果

-- 2. GROUP BY 对齐 shardkey 时性能最好
--    例如: 表按 city 分片，GROUP BY city 可在各分片独立完成

-- 3. 跨分片聚合的执行流程:
--    (a) 各分片执行局部聚合（Phase 1）
--    (b) 代理层收集并合并结果（Phase 2）
--    (c) 如果 GROUP BY 键不是分片键，Phase 2 可能大量数据传输

-- 4. 大数据量聚合建议:
--    - 确保分片键与 GROUP BY 列对齐
--    - 使用覆盖索引减少回表
--    - 考虑预聚合表减少实时计算量

-- ============================================================
-- 10. 版本兼容性
-- ============================================================
-- MySQL 5.7 / TDSQL: 基础聚合 + GROUP_CONCAT + JSON 聚合
-- MySQL 8.0 / TDSQL: GROUPING() 函数, 窗口函数支持
-- 确认 TDSQL 底层 MySQL 版本以确定可用功能范围
-- 注意: 不支持 GROUPING SETS / CUBE（标准 SQL），仅有 WITH ROLLUP
