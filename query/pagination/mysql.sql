-- MySQL: 分页
--
-- 参考资料:
--   [1] MySQL 8.0 Reference Manual - SELECT ... LIMIT
--       https://dev.mysql.com/doc/refman/8.0/en/select.html
--   [2] MySQL 8.0 Reference Manual - LIMIT Query Optimization
--       https://dev.mysql.com/doc/refman/8.0/en/limit-optimization.html
--   [3] Use The Index, Luke - Pagination
--       https://use-the-index-luke.com/no-offset

-- ============================================================
-- 1. 基本语法
-- ============================================================

-- LIMIT count OFFSET offset（推荐写法，语义清晰）
SELECT * FROM users ORDER BY id LIMIT 10 OFFSET 20;

-- 简写: LIMIT offset, count（注意: offset 在前、count 在后，容易混淆）
SELECT * FROM users ORDER BY id LIMIT 20, 10;

-- 仅限制行数
SELECT * FROM users ORDER BY id LIMIT 10;

-- 8.0+: 窗口函数辅助分页（获取行号）
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (ORDER BY id) AS rn
    FROM users
) t
WHERE rn BETWEEN 21 AND 30;

-- 带总行数的分页查询（8.0+，使用窗口函数避免额外 COUNT 查询）
SELECT *, COUNT(*) OVER() AS total_count
FROM users
ORDER BY id
LIMIT 10 OFFSET 20;

-- SQL_CALC_FOUND_ROWS（已废弃）
-- MySQL 8.0.17+ 已废弃，建议使用 COUNT(*) OVER() 替代
-- SELECT SQL_CALC_FOUND_ROWS * FROM users ORDER BY id LIMIT 10 OFFSET 20;
-- SELECT FOUND_ROWS();

-- ============================================================
-- 2. LIMIT OFFSET 的深分页性能问题（对 SQL 引擎开发者）
-- ============================================================

-- 2.1 问题本质
-- SELECT * FROM users ORDER BY id LIMIT 10 OFFSET 100000;
-- MySQL 的执行过程:
--   Step 1: 通过索引（或全表扫描）读取前 100010 行
--   Step 2: 丢弃前 100000 行
--   Step 3: 返回后 10 行
-- 即使有索引，MySQL 仍需要遍历索引的 100010 个叶子节点
-- OFFSET 越大，扫描的行越多，性能线性退化: O(offset + limit)

-- 2.2 为什么 MySQL 不能 "跳过" offset 行？
-- B+树索引支持范围扫描，但不支持 "跳到第 N 个位置":
--   - B+树的内部节点不存储子树的行数（不是 Order-Statistic Tree）
--   - 要知道 "第 100000 行在哪"，必须从头遍历
-- 对比: 数组可以 O(1) 随机访问，但 B+树不行
--
-- 对引擎开发者的启示:
--   如果分页是核心场景，可以考虑在 B+树内部节点维护子树大小信息
--   代价: 每次 INSERT/DELETE/分裂/合并都需要更新子树大小（写放大）
--   实际上几乎没有引擎这样做（代价太高，收益场景有限）

-- ============================================================
-- 3. 优化方案一: Deferred JOIN（延迟关联）
-- ============================================================

-- 原理: 先在索引上快速定位 ID，再用 ID 回表取完整数据
-- 将 O(offset * row_size) 减少为 O(offset * index_entry_size + limit * row_size)

-- 原始查询（慢: 回表 100010 次，读取完整行数据）:
-- SELECT * FROM users ORDER BY created_at DESC LIMIT 10 OFFSET 100000;

-- 延迟关联（快: 索引扫描 100010 条索引项，只回表 10 次）:
SELECT u.* FROM users u
JOIN (
    SELECT id FROM users ORDER BY created_at DESC LIMIT 10 OFFSET 100000
) AS t ON u.id = t.id;

-- 为什么更快？
--   子查询 SELECT id 使用覆盖索引（如果有 INDEX(created_at, id) 或主键是 id）
--   覆盖索引不需要回表: 索引项比完整行小得多（如 16 字节 vs 1KB）
--   扫描 100010 个索引项比扫描 100010 个完整行快 10-100 倍
--   最终只对 10 个 id 做回表查找

-- 前提条件:
--   需要一个覆盖排序列和主键的索引:
--   CREATE INDEX idx_created_id ON users (created_at DESC, id);

-- ============================================================
-- 4. 优化方案二: Keyset Pagination（键集分页/游标分页）
-- ============================================================

-- 原理: 记住上一页最后一条记录的排序键，用 WHERE 过滤而不是 OFFSET 跳过
-- 时间复杂度: O(log n + limit)，与页码无关（不退化）

-- 第一页
SELECT * FROM users ORDER BY id LIMIT 10;

-- 后续页（上一页最后一条 id = 100）
SELECT * FROM users WHERE id > 100 ORDER BY id LIMIT 10;

-- 多列排序的键集分页（created_at DESC, id DESC）
-- 上一页最后一条: created_at = '2025-01-15', id = 42
SELECT * FROM users
WHERE (created_at, id) < ('2025-01-15', 42)
ORDER BY created_at DESC, id DESC
LIMIT 10;
-- MySQL 8.0+ 支持行构造器比较: (a, b) < (v1, v2) 等价于 a < v1 OR (a = v1 AND b < v2)
-- 5.7 需要展开为 OR 条件（且优化器可能无法高效使用索引）

-- 键集分页的优缺点:
--   优点:
--     a. 性能恒定，与 "第几页" 无关（总是 O(log n + limit)）
--     b. 天然支持实时数据: 新插入/删除的数据不影响分页一致性
--     c. 适合无限滚动（infinite scroll）场景
--   缺点:
--     a. 不支持 "跳到第 N 页"（因为不知道第 N 页从哪个 key 开始）
--     b. 需要稳定且唯一的排序键（如果排序键有重复值，必须加 id 做 tiebreaker）
--     c. 实现复杂度比 OFFSET 高（客户端需要管理 cursor 状态）
--     d. 只能向前/向后翻页，不能随机跳页

-- ============================================================
-- 5. 横向对比: 各引擎的分页方案和性能特征
-- ============================================================

-- 5.1 语法对比:
--   MySQL:      LIMIT count OFFSET offset（非 SQL 标准）
--   PostgreSQL: LIMIT count OFFSET offset（同 MySQL）+ SQL 标准 FETCH FIRST N ROWS ONLY
--   Oracle:     12c+ FETCH FIRST N ROWS ONLY / OFFSET N ROWS（SQL 标准）
--               12c 之前: ROWNUM（性能陷阱: WHERE ROWNUM > 10 永远返回空！）
--               因为 ROWNUM 在 WHERE 过滤之前分配，过滤掉第 1 行后第 2 行变成第 1 行
--   SQL Server: TOP N（不支持 OFFSET）-> 2012+ OFFSET N ROWS FETCH NEXT M ROWS ONLY
--   SQLite:     LIMIT count OFFSET offset（同 MySQL）
--   BigQuery:   LIMIT count OFFSET offset（但不推荐: 分布式扫描下 OFFSET 语义代价更高）

-- 5.2 深分页性能对比:
--   所有基于 B+树索引的引擎都有 OFFSET 深分页问题（MySQL/PG/Oracle/SQL Server）
--   原因相同: B+树不维护位置信息，OFFSET N 需要扫描 N 行
--
--   各引擎的优化策略:
--   MySQL:      延迟关联（手动优化）、键集分页（推荐）
--   PostgreSQL: 同 MySQL，额外支持: 带 GIN 索引的高效 OFFSET（特定场景）
--   Oracle:     ROWNUM + 内层排序（经典写法）、12c+ FETCH FIRST（优化器自动优化）
--   SQL Server: TOP + 子查询（2008 之前）、OFFSET-FETCH（2012+，优化器有专门的 Top 算子）
--   Elasticsearch: scroll API / search_after（天然键集分页，不支持大 OFFSET）
--   ClickHouse:  LIMIT OFFSET 可用，但大 OFFSET 在分布式查询中问题更严重
--                 （每个 shard 都要返回 offset+limit 行到协调节点）

-- 5.3 总行数获取方案对比:
--   MySQL 8.0+:  COUNT(*) OVER()（窗口函数，一次查询获取数据+总数）
--   MySQL 旧版:  SQL_CALC_FOUND_ROWS + FOUND_ROWS()（已废弃）
--   PostgreSQL:  COUNT(*) OVER()，或 SELECT count(*) 单独查询
--                大表精确 COUNT 慢: 可用 pg_class.reltuples 获取近似值
--   Oracle:      COUNT(*) OVER()（很早就支持窗口函数）
--   分析引擎:    通常有近似计数函数（如 APPROX_COUNT_DISTINCT）

-- 5.4 分布式引擎的分页挑战:
--   分布式查询中 OFFSET 的代价更高:
--   假设 10 个分片，LIMIT 10 OFFSET 100000:
--     每个分片需要返回 100010 行到协调节点
--     协调节点全局排序后取第 100001~100010 行
--     网络传输量: 10 * 100010 行（而不是 10 行）
--
--   优化方案:
--     a. 键集分页: 每个分片只需返回 WHERE key > cursor LIMIT 10（大幅减少传输量）
--     b. 两阶段查询: 第一阶段取排序键+分片信息，第二阶段精确获取目标行
--     c. 限制最大 OFFSET: 很多 API 设计（如 Elasticsearch）限制 max_result_window = 10000
--     d. 近似分页: 接受不精确的结果（适合 feed 流等场景）

-- ============================================================
-- 6. 最佳实践总结
-- ============================================================

-- 场景 1: 后台管理系统（需要跳页）
--   小数据量（< 10 万行）: LIMIT OFFSET 足够
--   大数据量: 延迟关联 + 限制最大页数（如只允许查看前 100 页）

-- 场景 2: 移动端无限滚动
--   键集分页（keyset pagination）是最优解
--   客户端只需传递 last_id / last_cursor

-- 场景 3: API 设计
--   RESTful: ?page=5&size=20（对用户友好，但后端用键集分页实现）
--   GraphQL: Relay 规范的 cursor-based pagination（first/after/last/before）
--   注意: 无论 API 形式如何，后端实现应优先使用键集分页

-- 索引建议:
--   分页排序列必须有索引（否则需要 filesort，性能灾难）
--   复合排序: CREATE INDEX idx ON table (sort_col1, sort_col2, id)
--   降序分页: MySQL 8.0+ 使用降序索引: CREATE INDEX idx ON table (created_at DESC, id DESC)

-- 对引擎开发者的总结:
--   1) LIMIT OFFSET 语法简单但性能模型糟糕（O(offset)），用户教育成本高
--   2) 提供 cursor/keyset 分页的原生支持可以减少用户犯错（如 SQL 标准的 FETCH ... WITH TIES）
--   3) 分布式引擎应考虑限制最大 OFFSET（或至少给出性能警告）
--   4) 在 EXPLAIN 输出中显示预估扫描行数，帮助用户识别深分页问题
