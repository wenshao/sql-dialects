-- PostgreSQL: 窗口函数（8.4+）
--
-- 参考资料:
--   [1] PostgreSQL Documentation - Window Functions
--       https://www.postgresql.org/docs/current/functions-window.html
--   [2] PostgreSQL Documentation - Window Function Tutorial
--       https://www.postgresql.org/docs/current/tutorial-window.html
--   [3] PostgreSQL Documentation - SELECT (WINDOW clause)
--       https://www.postgresql.org/docs/current/sql-select.html#SQL-WINDOW

-- ============================================================
-- 基本排名函数
-- ============================================================
-- ROW_NUMBER / RANK / DENSE_RANK 的区别（这三个是最常用的）
SELECT username, age,
    ROW_NUMBER() OVER (ORDER BY age) AS rn,          -- 1,2,3,4,5 （永远不重复）
    RANK()       OVER (ORDER BY age) AS rnk,         -- 1,2,2,4,5 （并列跳号）
    DENSE_RANK() OVER (ORDER BY age) AS dense_rnk    -- 1,2,2,3,4 （并列不跳号）
FROM users;
-- 选择指南:
--   分页/去重 → ROW_NUMBER（需要唯一序号）
--   排名/TOP N → RANK 或 DENSE_RANK（取决于是否要跳号）
--   注意: ROW_NUMBER 在 ORDER BY 值相同时结果不确定，加第二排序列可以稳定结果

-- 分区排名（每组内独立排名）
SELECT username, city, age,
    ROW_NUMBER() OVER (PARTITION BY city ORDER BY age DESC) AS city_rank
FROM users;
-- 典型用法: 取每组 TOP N（WHERE city_rank <= 3 需要子查询或 CTE 包装）

-- ============================================================
-- 聚合窗口函数
-- ============================================================
SELECT username, age,
    SUM(age)   OVER () AS total_age,                              -- 全局聚合
    AVG(age)   OVER () AS avg_age,
    COUNT(*)   OVER () AS total_count,
    MIN(age)   OVER (PARTITION BY city) AS city_min_age,          -- 分组聚合
    MAX(age)   OVER (PARTITION BY city) AS city_max_age
FROM users;
-- 关键理解: 窗口函数不会合并行（不像 GROUP BY），每行都保留，只是附加了聚合结果

-- ============================================================
-- 偏移函数: LAG / LEAD / FIRST_VALUE / LAST_VALUE / NTH_VALUE
-- ============================================================
SELECT username, age,
    LAG(age, 1)  OVER (ORDER BY id) AS prev_age,
    LEAD(age, 1) OVER (ORDER BY id) AS next_age,
    LAG(age, 1, 0) OVER (ORDER BY id) AS prev_age_or_zero,       -- 第三参数: 默认值
    FIRST_VALUE(username) OVER (PARTITION BY city ORDER BY age) AS youngest,
    LAST_VALUE(username)  OVER (PARTITION BY city ORDER BY age
        ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS oldest
FROM users;

-- !! LAST_VALUE 的经典陷阱 !!
-- 很多人写: LAST_VALUE(x) OVER (ORDER BY y) 期望得到最后一个值
-- 但默认帧是 RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
-- 所以 LAST_VALUE 返回的是"当前行"的值，不是整个分区的最后值！
-- 必须显式指定: ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING

-- NTH_VALUE（8.4+）
SELECT username, age,
    NTH_VALUE(username, 2) OVER (ORDER BY age
        ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS second_youngest
FROM users;
-- NTH_VALUE 也有同样的帧陷阱: 如果第 N 行还不在当前帧内，返回 NULL

-- ============================================================
-- NTILE / PERCENT_RANK / CUME_DIST
-- ============================================================
SELECT username, age,
    NTILE(4)       OVER (ORDER BY age) AS quartile,     -- 分成 4 组（1,2,3,4）
    PERCENT_RANK() OVER (ORDER BY age) AS pct_rank,     -- (rank - 1) / (total - 1)，范围 [0,1]
    CUME_DIST()    OVER (ORDER BY age) AS cume_dist     -- count(val <= current) / total，范围 (0,1]
FROM users;
-- NTILE 的分组: 如果 10 行分 3 组，分别是 4,3,3 行（尽量均匀，多的放前面）

-- ============================================================
-- 命名窗口（WINDOW 子句）
-- ============================================================
-- 当多个窗口函数使用相同定义时，用命名窗口避免重复
SELECT username, age,
    ROW_NUMBER() OVER w AS rn,
    RANK()       OVER w AS rnk,
    LAG(age)     OVER w AS prev_age
FROM users
WINDOW w AS (ORDER BY age);

-- 命名窗口可以继承和扩展:
SELECT username, city, age,
    ROW_NUMBER() OVER (w ORDER BY age) AS rn,           -- 在 w 基础上加 ORDER BY
    SUM(age)     OVER w AS city_total
FROM users
WINDOW w AS (PARTITION BY city);
-- 限制: 如果父窗口已有 ORDER BY，子窗口不能再加 ORDER BY

-- ============================================================
-- 帧子句详解（ROWS vs RANGE vs GROUPS）
-- ============================================================
-- 这是窗口函数最难理解也最容易出错的部分

-- 默认帧行为（几乎所有人都会忘记这个）:
-- 有 ORDER BY 时: RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
-- 无 ORDER BY 时: RANGE BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
-- 这导致了无数 bug！比如 LAST_VALUE 不返回"最后"值

-- ROWS: 按物理行计算（最直观，最常用）
SELECT username, age,
    -- 滑动窗口: 当前行 + 前2行
    SUM(age) OVER (ORDER BY id ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS rolling_3,
    -- 前1行到后1行
    AVG(age) OVER (ORDER BY id ROWS BETWEEN 1 PRECEDING AND 1 FOLLOWING) AS centered_avg,
    -- 当前行到最后
    SUM(age) OVER (ORDER BY id ROWS BETWEEN CURRENT ROW AND UNBOUNDED FOLLOWING) AS remaining
FROM users;

-- RANGE: 按值范围计算（适用于时间窗口）
SELECT username, created_at, amount,
    -- 过去 7 天的总额（基于 created_at 的值范围，不是行数）
    SUM(amount) OVER (ORDER BY created_at
        RANGE BETWEEN INTERVAL '7 days' PRECEDING AND CURRENT ROW) AS weekly_total,
    -- 这比 ROWS 更有意义: 如果某天没有数据，ROWS 会跨过去取前面几天的数据
    -- 而 RANGE 严格按 7 天的时间范围来
    COUNT(*) OVER (ORDER BY created_at
        RANGE BETWEEN INTERVAL '7 days' PRECEDING AND CURRENT ROW) AS weekly_count
FROM orders;

-- RANGE vs ROWS 的核心区别:
--   数据: (age=20), (age=20), (age=30), (age=40)
--   ROWS CURRENT ROW: 只包含物理上的当前行
--   RANGE CURRENT ROW: 包含所有与当前行 ORDER BY 值相同的行（两个 age=20 都包含）

-- GROUPS: 按"组"计算（11+，最不常用但某些场景很方便）
SELECT username, age,
    SUM(age) OVER (ORDER BY age GROUPS BETWEEN 1 PRECEDING AND 1 FOLLOWING) AS group_sum
FROM users;
-- GROUPS 中一"组"= ORDER BY 值相同的所有行
-- GROUPS 1 PRECEDING = 包含前一个不同值的所有行
-- 例如 age: 20,20,30,40,40,50
--   对于 age=30: GROUPS 1 PRECEDING AND 1 FOLLOWING → 包含 20,20,30,40,40

-- ============================================================
-- FILTER 子句（9.4+）—— PostgreSQL 独有的强大特性
-- ============================================================
-- FILTER 比 CASE WHEN 更清晰、更高效

-- 传统写法（其他数据库）:
SELECT city,
    COUNT(CASE WHEN age < 30 THEN 1 END) AS young_count,
    COUNT(CASE WHEN age >= 30 THEN 1 END) AS senior_count,
    SUM(CASE WHEN status = 1 THEN balance ELSE 0 END) AS active_balance
FROM users GROUP BY city;

-- PostgreSQL FILTER 写法（推荐）:
SELECT city,
    COUNT(*) FILTER (WHERE age < 30) AS young_count,
    COUNT(*) FILTER (WHERE age >= 30) AS senior_count,
    SUM(balance) FILTER (WHERE status = 1) AS active_balance
FROM users GROUP BY city;
-- FILTER 的优势:
--   1. 语义更清晰: 明确表达"对这个聚合函数应用过滤"
--   2. 性能更好: 优化器可以更好地处理（特别是对 COUNT(*)）
--   3. 不容易出错: CASE WHEN 忘记 ELSE 时 SUM 会包含 NULL（不影响结果但意图不清）
--   4. 可以和窗口函数组合:
SELECT city, username,
    COUNT(*) FILTER (WHERE age < 30) OVER (PARTITION BY city) AS young_in_city,
    COUNT(*) FILTER (WHERE age >= 30) OVER () AS total_senior
FROM users;

-- ============================================================
-- EXCLUDE 子句（11+）
-- ============================================================
-- EXCLUDE 从帧中排除特定行，很少用但某些场景很方便
SELECT username, age,
    AVG(age) OVER (ORDER BY age ROWS BETWEEN 2 PRECEDING AND 2 FOLLOWING
        EXCLUDE CURRENT ROW) AS avg_neighbors,           -- 排除当前行
    AVG(age) OVER (ORDER BY age ROWS BETWEEN 2 PRECEDING AND 2 FOLLOWING
        EXCLUDE GROUP) AS avg_excluding_same_age,        -- 排除相同 ORDER BY 值的行
    AVG(age) OVER (ORDER BY age ROWS BETWEEN 2 PRECEDING AND 2 FOLLOWING
        EXCLUDE TIES) AS avg_excluding_ties              -- 排除相同值但保留当前行
FROM users;
-- EXCLUDE NO OTHERS: 默认行为，不排除任何行
-- 实际场景: 计算"同龄人之外的平均值"、"去掉自己的组内平均值"

-- ============================================================
-- 性能优化技巧
-- ============================================================
--
-- 1. 索引与窗口函数:
--    窗口函数本身不能使用索引来加速计算，但 ORDER BY 和 PARTITION BY 可以利用索引
--    避免排序开销:
--    CREATE INDEX idx_users_city_age ON users(city, age);
--    -- 让 PARTITION BY city ORDER BY age 直接利用索引排序
--
-- 2. 多个窗口函数共享窗口定义:
--    PostgreSQL 只需要对相同窗口定义排序一次
--    不同窗口定义需要多次排序 → 尽量让窗口函数使用相同的 PARTITION BY + ORDER BY
--
-- 3. 避免不必要的帧计算:
--    ROW_NUMBER、RANK、DENSE_RANK 不使用帧 → 不需要指定帧子句
--    只有聚合函数（SUM、AVG、COUNT 等）和 FIRST_VALUE/LAST_VALUE/NTH_VALUE 使用帧
--
-- 4. WHERE 里不能直接用窗口函数:
--    错误: SELECT *, ROW_NUMBER() OVER (...) AS rn FROM t WHERE rn <= 10
--    正确: 用子查询或 CTE 包装
--    WITH ranked AS (
--        SELECT *, ROW_NUMBER() OVER (...) AS rn FROM t
--    ) SELECT * FROM ranked WHERE rn <= 10;
--
-- 5. 物化 CTE vs 内联 CTE:
--    PostgreSQL 12+ CTE 可能被内联优化，如果需要强制物化:
--    WITH ranked AS MATERIALIZED (SELECT ... OVER ...) SELECT * FROM ranked;
--
-- 6. EXPLAIN 分析:
--    看到 WindowAgg 节点就是窗口函数计算
--    看到 Sort 节点在 WindowAgg 之前说明需要排序（可以用索引消除）

-- ============================================================
-- 横向对比: PostgreSQL vs 其他方言的窗口函数
-- ============================================================

-- 1. 窗口函数支持版本对比:
--   PostgreSQL: 8.4+（2009 年，较早支持）
--   MySQL:      8.0+（2018 年！5.7 及之前不支持窗口函数，是 MySQL 长期被诟病的短板）
--   Oracle:     8i+（2000 年左右，最早支持，功能最全）
--   SQL Server: 2005+（较早支持，2012 大幅增强帧子句）
--   SQLite:     3.25+（2018 年）
--   MariaDB:    10.2+（2017 年）

-- 2. FILTER 子句对比（PostgreSQL 独有优势）:
--   PostgreSQL: COUNT(*) FILTER (WHERE condition)（9.4+，语义清晰、性能好）
--   MySQL:      不支持 FILTER，只能用 SUM(CASE WHEN ... THEN 1 ELSE 0 END)
--   Oracle:     不支持 FILTER，只能用 CASE WHEN
--   SQL Server: 不支持 FILTER，只能用 CASE WHEN
--   SQLite:     3.30+ 支持 FILTER（跟随 PostgreSQL）
--   这是 PostgreSQL 在窗口函数/聚合领域的独有优势

-- 3. 帧类型对比:
--   PostgreSQL: ROWS / RANGE / GROUPS（11+，三种都支持）
--   MySQL:      ROWS / RANGE（8.0+，不支持 GROUPS）
--   Oracle:     ROWS / RANGE（不支持 GROUPS）
--   SQL Server: ROWS / RANGE（2012+，不支持 GROUPS）
--   GROUPS 是 SQL:2011 标准特性，按"相同 ORDER BY 值的组"计算帧

-- 4. EXCLUDE 子句对比:
--   PostgreSQL: EXCLUDE CURRENT ROW / GROUP / TIES / NO OTHERS（11+）
--   MySQL:      不支持 EXCLUDE
--   Oracle:     不支持 EXCLUDE
--   SQL Server: 不支持 EXCLUDE
--   SQLite:     3.28+ 支持 EXCLUDE（跟随 PostgreSQL）
--   又一个 PostgreSQL 的独有优势

-- 5. 命名窗口 (WINDOW 子句) 对比:
--   PostgreSQL: WINDOW w AS (PARTITION BY ...)，支持窗口继承
--   MySQL:      8.0+ 支持 WINDOW 子句
--   Oracle:     不支持 WINDOW 子句（每个窗口函数需要写完整的 OVER）
--   SQL Server: 不支持 WINDOW 子句
--   SQLite:     3.28+ 支持 WINDOW 子句

-- 6. RANGE BETWEEN INTERVAL 对比:
--   PostgreSQL: RANGE BETWEEN INTERVAL '7 days' PRECEDING AND CURRENT ROW（直接用 INTERVAL）
--   MySQL:      不支持 RANGE + INTERVAL（只支持数值型 RANGE）
--   Oracle:     支持 RANGE BETWEEN INTERVAL '7' DAY PRECEDING（语法略不同）
--   SQL Server: 不支持 RANGE + INTERVAL（需要转换为数值或用其他方法）

-- 7. NTH_VALUE / NTILE 对比:
--   PostgreSQL: NTH_VALUE（8.4+），NTILE（8.4+）
--   MySQL:      NTH_VALUE（8.0+），NTILE（8.0+）
--   Oracle:     NTH_VALUE（11g+），NTILE（8i+）
--   SQL Server: 不支持 NTH_VALUE（需要用 ROW_NUMBER + 子查询模拟），NTILE（2005+）

-- 8. Oracle 独有的分析函数特性:
--   Oracle 作为窗口函数的先驱（8i+），有一些独有或最早实现的特性:
--     - LISTAGG: 分组字符串聚合（11gR2+），其他数据库后来才加入类似功能
--       PostgreSQL: STRING_AGG（9.0+），MySQL: GROUP_CONCAT，SQL Server: STRING_AGG（2017+）
--     - MODEL 子句: 类似电子表格的行间计算（10g+），极其强大但复杂，其他数据库没有
--     - RATIO_TO_REPORT: 计算占比（SUM 的语法糖），PostgreSQL 需要手写 val / SUM(val) OVER()
--     - KEEP (DENSE_RANK FIRST/LAST): 分组最大/最小值对应的其他列，PostgreSQL 用 DISTINCT ON
--   Oracle '' = NULL 在窗口函数中的影响:
--     PARTITION BY col 时，如果 col 包含空字符串 ''，它们会和 NULL 行分到同一个分区
--     迁移到 PostgreSQL: '' 和 NULL 会分到不同分区，可能导致结果不同
--   Oracle NUMBER 类型在窗口函数中:
--     SUM/AVG 等聚合窗口函数的结果始终是 NUMBER 类型
--     PostgreSQL 中 SUM(INTEGER) 返回 BIGINT，SUM(BIGINT) 返回 NUMERIC
--     迁移时注意类型差异可能导致精度或溢出行为不同

-- 9. SQL Server 独有的窗口函数特性:
--   聚集索引（Clustered Index）= 表的物理排列顺序:
--     窗口函数的 ORDER BY 如果与聚集索引一致，可以避免排序操作
--     这是 SQL Server 性能调优的独有考量（PostgreSQL 没有聚集索引概念）
--   Batch Mode 处理（2012+，列存储索引相关）:
--     对列存储索引上的窗口函数使用批处理模式，性能提升 10-100 倍
--     2019+ Batch Mode on Rowstore: 即使是行存储索引也能使用批处理
--     这是 SQL Server 在大数据分析场景的独有优势
--   SQL Server 特有的窗口函数限制:
--     - 不支持 NTH_VALUE（需要用 ROW_NUMBER + 子查询模拟）
--     - 不支持 WINDOW 子句（每个窗口函数必须写完整的 OVER 定义）
--     - 不支持 GROUPS 帧类型
--     - 不支持 EXCLUDE 子句
--     - 不支持 RANGE + INTERVAL
--   WITH (NOLOCK) 与窗口函数的交互:
--     在 WITH (NOLOCK) 查询中使用窗口函数可能产生不一致的结果
--     因为 NOLOCK 允许在扫描过程中读到正在修改的数据
--     窗口函数的排序和分区可能基于不一致的数据，导致排名跳跃或聚合值错误
--     正确做法: 开启 RCSI（READ_COMMITTED_SNAPSHOT），不要使用 NOLOCK

-- 10. SNAPSHOT 隔离与窗口函数一致性:
--   SQL Server SNAPSHOT 隔离:
--     开启 SNAPSHOT 后窗口函数看到的是事务开始时的一致性快照
--     这保证了跨多行的窗口计算结果一致（不会受到并发修改影响）
--     但需要注意 tempdb 压力（行版本存储在 tempdb 中）
--   PostgreSQL REPEATABLE READ / SERIALIZABLE:
--     天然 MVCC，窗口函数始终看到一致性快照，无需额外配置
--   Oracle READ COMMITTED:
--     天然 MVCC，语句级一致性快照，窗口函数结果始终一致

-- 11. 性能实现对比:
--   PostgreSQL: 单遍扫描 + 排序（可利用索引避免排序），12+ CTE 内联优化
--   MySQL:      8.0 初期性能较差（内部临时表），后续版本持续优化
--   Oracle:     最成熟的窗口函数优化器，支持窗口函数消除、窗口排序合并
--   SQL Server: 2012+ 大幅改进帧计算性能，Batch Mode 处理列存储索引
