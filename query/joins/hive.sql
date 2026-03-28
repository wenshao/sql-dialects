-- Hive: JOIN (MapReduce/Tez 分布式 JOIN)
--
-- 参考资料:
--   [1] Apache Hive Language Manual - Joins
--       https://cwiki.apache.org/confluence/display/Hive/LanguageManual+Joins
--   [2] Apache Hive - Join Optimization
--       https://cwiki.apache.org/confluence/display/Hive/LanguageManual+JoinOptimization

-- ============================================================
-- 1. 标准 JOIN 类型
-- ============================================================
-- INNER JOIN
SELECT u.username, o.amount
FROM users u INNER JOIN orders o ON u.id = o.user_id;

-- LEFT/RIGHT/FULL OUTER JOIN
SELECT u.username, o.amount
FROM users u LEFT JOIN orders o ON u.id = o.user_id;

SELECT u.username, o.amount
FROM users u FULL OUTER JOIN orders o ON u.id = o.user_id;

-- CROSS JOIN (0.10+)
SELECT u.username, r.role_name FROM users u CROSS JOIN roles r;

-- LEFT SEMI JOIN: Hive 独有的高效 EXISTS 替代
SELECT u.* FROM users u
LEFT SEMI JOIN orders o ON u.id = o.user_id;
-- 等价于: SELECT * FROM users WHERE id IN (SELECT user_id FROM orders)
-- 但 SEMI JOIN 更高效: 只需要匹配到第一行就停止

-- ============================================================
-- 2. JOIN 执行策略: Hive 的核心优化
-- ============================================================
-- Hive 的 JOIN 与 RDBMS 有本质区别:
-- RDBMS: Nested Loop / Hash Join / Merge Join (内存中执行)
-- Hive:  Map-side JOIN / Reduce-side JOIN / Bucket Map JOIN (分布式执行)

-- 2.1 Map Join (Broadcast Join): 小表广播
SELECT /*+ MAPJOIN(r) */ u.username, r.role_name
FROM users u JOIN roles r ON u.role_id = r.id;

-- MAPJOIN 的工作原理:
-- 1. 小表(roles)加载到每个 Mapper 的内存中（HashMap）
-- 2. 大表(users)的每行在 Mapper 端直接查找 HashMap 完成 JOIN
-- 3. 不需要 Shuffle 和 Reduce 阶段 → 性能大幅提升
--
-- 自动 Map Join（推荐）:
SET hive.auto.convert.join = true;                  -- 默认开启
SET hive.auto.convert.join.noconditionaltask.size = 10000000;  -- 小表阈值(10MB)

-- 2.2 Reduce-side JOIN: 默认的 Shuffle JOIN
-- 当两个表都很大时，Hive 使用 Shuffle JOIN:
-- 1. Map 阶段: 两个表按 JOIN 键分区输出
-- 2. Shuffle 阶段: 相同 JOIN 键的数据发送到同一个 Reducer
-- 3. Reduce 阶段: 在 Reducer 中完成 JOIN
-- 这是最通用但也是最慢的 JOIN 方式（全量 Shuffle）

-- STREAMTABLE hint: 指定大表作为流式处理表
SELECT /*+ STREAMTABLE(o) */ u.username, o.amount
FROM users u JOIN orders o ON u.id = o.user_id;
-- 大表 stream 读取，小表缓存在内存中

-- 2.3 Bucket Map JOIN: 分桶表优化
SET hive.optimize.bucketmapjoin = true;
SET hive.optimize.bucketmapjoin.sortedmerge = true;

-- 前提: 两表都按 JOIN 列分桶且桶数相同（或成倍数关系）
-- SELECT /*+ MAPJOIN(o) */ u.username, o.amount
-- FROM users_bucketed u JOIN orders_bucketed o ON u.id = o.user_id;
-- 每个桶只和对应的桶 JOIN → 并行度高，内存效率好

-- ============================================================
-- 3. LATERAL VIEW: Hive 的"JOIN"嵌套数据
-- ============================================================
-- LATERAL VIEW 不是传统 JOIN，而是将一行展开为多行
SELECT u.username, tag
FROM users u
LATERAL VIEW EXPLODE(u.tags) t AS tag;

-- LATERAL VIEW OUTER: 保留空数组的行 (0.12+)
SELECT u.username, tag
FROM users u
LATERAL VIEW OUTER EXPLODE(u.tags) t AS tag;

-- POSEXPLODE: 带位置信息 (0.13+)
SELECT u.username, pos, tag
FROM users u
LATERAL VIEW POSEXPLODE(u.tags) t AS pos, tag;

-- MAP 展开
SELECT u.username, k, v
FROM users u
LATERAL VIEW EXPLODE(u.properties) t AS k, v;

-- 多个 LATERAL VIEW (笛卡尔积！)
SELECT u.username, tag, skill
FROM users u
LATERAL VIEW EXPLODE(u.tags) t1 AS tag
LATERAL VIEW EXPLODE(u.skills) t2 AS skill;

-- ============================================================
-- 4. 数据倾斜处理 (Skew Join)
-- ============================================================
SET hive.optimize.skewjoin = true;
SET hive.skewjoin.key = 100000;  -- 阈值

-- 数据倾斜: 某个 JOIN 键的值特别多（如 user_id=null 或热门用户）
-- 导致一个 Reducer 处理大量数据，其他 Reducer 空闲
-- Skew Join 的解决方案:
-- 1. 检测倾斜键
-- 2. 倾斜键的数据用 Map Join 处理（广播小表端对应数据）
-- 3. 非倾斜键的数据用普通 Reduce Join

-- ============================================================
-- 5. 已知限制
-- ============================================================
-- 1. 不支持 USING 子句: JOIN ... USING (col) 不可用
-- 2. 不支持 NATURAL JOIN
-- 3. 早期版本只支持等值 JOIN: ON a.id = b.id（0.13+ 支持不等值）
-- 4. LATERAL VIEW 是 CROSS JOIN 语义: 多个 LATERAL VIEW 是笛卡尔积
-- 5. Map Join 受内存限制: 小表必须能完全加载到内存中

-- ============================================================
-- 6. 跨引擎对比: JOIN 策略
-- ============================================================
-- 引擎          JOIN 策略             小表优化         数据倾斜
-- MySQL(InnoDB) NLJ/Hash/BKA         join_buffer      无自动处理
-- PostgreSQL    NLJ/Hash/Merge       work_mem         无自动处理
-- Hive          Map/Reduce/Bucket    MAPJOIN hint     Skew Join
-- Spark SQL     Broadcast/Sort-Merge broadcast()      AQE(3.0+)
-- BigQuery      Broadcast/Shuffle    自动             自动
-- Trino         Broadcast/Hash       自动             无
-- Flink SQL     Broadcast/Hash       lookup join      无

-- ============================================================
-- 7. 对引擎开发者的启示
-- ============================================================
-- 1. Map Join (Broadcast) 是小表 JOIN 的最佳策略:
--    避免 Shuffle 是分布式 JOIN 优化的第一原则
-- 2. 数据倾斜是分布式 JOIN 的核心挑战:
--    Hive 的 Skew Join 和 Spark 的 AQE 都是解决此问题的方案
-- 3. LATERAL VIEW 是嵌套数据处理的关键:
--    SQL 标准的 UNNEST 更简洁，但 Hive 的 LATERAL VIEW 语义更显式
-- 4. LEFT SEMI JOIN 是 EXISTS 的高效替代:
--    只需找到第一个匹配行即可终止，比 INNER JOIN + DISTINCT 更高效
