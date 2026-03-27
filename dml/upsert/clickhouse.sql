-- ClickHouse: UPSERT
--
-- 参考资料:
--   [1] ClickHouse - ReplacingMergeTree
--       https://clickhouse.com/docs/en/engines/table-engines/mergetree-family/replacingmergetree
--   [2] ClickHouse - CollapsingMergeTree
--       https://clickhouse.com/docs/en/engines/table-engines/mergetree-family/collapsingmergetree
--   [3] ClickHouse - VersionedCollapsingMergeTree
--       https://clickhouse.com/docs/en/engines/table-engines/mergetree-family/versionedcollapsingmergetree
--   [4] ClickHouse - INSERT Deduplication
--       https://clickhouse.com/docs/en/operations/settings/settings#insert_deduplicate

-- ============================================================
-- 为什么 ClickHouse 没有传统 UPSERT
-- ============================================================
-- 这不是功能缺失，是架构设计的根本选择。
--
-- 传统 UPSERT (INSERT ON CONFLICT UPDATE) 需要:
--   1. 唯一索引来检测冲突
--   2. 对冲突行加锁
--   3. 原地更新数据
-- 这三件事在列式存储 + 追加式写入的架构中代价极高:
--   - 列式存储不适合修改单行 (需要重写整个列块)
--   - 追加式写入意味着数据不可变 (immutable data parts)
--   - 全局唯一索引在分布式场景下是性能杀手
--
-- ClickHouse 的哲学: 写入极快 (100 万行/秒)，通过后台合并处理去重和更新
-- 代价: 数据一致性是"最终的"，不是"即时的"
--
-- 如果你需要强一致 UPSERT，ClickHouse 可能不是正确的工具
-- 考虑: PostgreSQL 做 OLTP，通过 CDC 同步到 ClickHouse 做分析

-- ============================================================
-- 方式一: ReplacingMergeTree（最常用）
-- ============================================================
-- 原理: 直接 INSERT 新数据，后台合并时按 ORDER BY 键去重，保留版本最新的行

CREATE TABLE user_profiles (
    user_id    UInt64,
    username   String,
    email      String,
    age        UInt8,
    version    UInt64              -- 版本号，合并时保留最大值
)
ENGINE = ReplacingMergeTree(version)
ORDER BY user_id;

-- "UPSERT" = 直接 INSERT，不管是新行还是更新
INSERT INTO user_profiles VALUES (1, 'alice', 'alice@example.com', 25, 1);
-- 更新 alice 的 email:
INSERT INTO user_profiles VALUES (1, 'alice', 'new@example.com', 26, 2);
-- 现在表里有两行! 后台合并后只保留 version=2 的行

-- 查询时的去重策略 (三选一):

-- 策略 A: FINAL 关键字 (简单，但有性能代价)
SELECT * FROM user_profiles FINAL WHERE user_id = 1;
-- FINAL 的代价:
--   - 单线程合并去重 (23.2 之前)
--   - 23.2+: do_not_merge_across_partitions_select_final=1 允许分区级并行
--   - 适合: 小结果集、点查、已知行数少的场景
--   - 不适合: 全表扫描、大范围聚合

-- 策略 B: argMax 手动去重 (推荐大数据量场景)
SELECT
    user_id,
    argMax(username, version) AS username,
    argMax(email, version) AS email,
    argMax(age, version) AS age
FROM user_profiles
WHERE user_id = 1
GROUP BY user_id;
-- 优势: 可以利用多线程，可以选择性去重部分列
-- 劣势: SQL 更冗长，列多的时候写起来痛苦

-- 策略 C: 子查询 + ROW_NUMBER (灵活但重)
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY version DESC) AS rn
    FROM user_profiles
) WHERE rn = 1;

-- ReplacingMergeTree 的关键陷阱:
--   1. 只在同一分区内去重! 如果数据跨分区，相同 ORDER BY 键的行不会合并
--      所以: 避免用高基数列分区 (PARTITION BY user_id 是灾难)
--   2. 合并时机不可控: 可能几秒后合并，也可能几小时后
--      不要依赖"插入后立刻只能看到一行"
--   3. FINAL 看到的是合并后的视图，但不会触发实际合并
--   4. 没有版本列时，保留"最后插入的行"（不推荐，行为不确定）

-- 手动触发合并 (测试用，生产慎用):
-- OPTIMIZE TABLE user_profiles FINAL;  -- 强制合并所有 part

-- ============================================================
-- 方式二: CollapsingMergeTree（正/负行抵消）
-- ============================================================
-- 原理: 用 sign 列标记行的"存在"(+1) 和"取消"(-1)
-- 合并时 +1 和 -1 的行互相抵消

CREATE TABLE user_balances (
    user_id  UInt64,
    name     String,
    balance  Decimal(10,2),
    sign     Int8              -- +1: 有效行, -1: 取消行
)
ENGINE = CollapsingMergeTree(sign)
ORDER BY user_id;

-- 初始插入
INSERT INTO user_balances VALUES (1, 'alice', 100.00, 1);

-- "更新" alice 的余额: 必须插入两行!
-- 第一行: 取消旧值 (需要知道旧值的所有列!)
-- 第二行: 插入新值
INSERT INTO user_balances VALUES
    (1, 'alice', 100.00, -1),   -- 取消: 必须和旧行完全一致 (除了 sign)
    (1, 'alice', 200.00,  1);   -- 新值

-- 合并前查询 (可能看到 3 行): 用 sum + sign 处理
SELECT user_id, sum(balance * sign) AS balance
FROM user_balances
GROUP BY user_id
HAVING sum(sign) > 0;           -- 排除已被完全取消的行

-- CollapsingMergeTree 的核心问题:
--   1. 取消行必须和原始行完全一致 (除了 sign)
--      你需要在应用层记住旧值，或者先查旧值再插入取消行
--   2. 取消行和有效行必须在同一个 INSERT 批次中 (或至少同一个 part)
--      否则合并时可能找不到配对
--   3. 行插入顺序很重要: 合并时按 ORDER BY 键排序后，相邻的 +1/-1 配对抵消
--      如果 -1 行到达得比 +1 行晚，可能暂时看到错误的聚合结果
--
-- 适用场景: 需要维护可增量更新的聚合计数器
-- 不适用: 需要简单行替换的场景 (用 ReplacingMergeTree)

-- ============================================================
-- 方式三: VersionedCollapsingMergeTree（解决乱序问题）
-- ============================================================
-- CollapsingMergeTree 要求行按顺序到达。现实中数据可能乱序。
-- VersionedCollapsingMergeTree 增加版本列，按版本号配对，不依赖插入顺序。

CREATE TABLE user_events_versioned (
    user_id  UInt64,
    event    String,
    count    UInt32,
    sign     Int8,
    version  UInt64              -- 同一版本的 +1 和 -1 配对
)
ENGINE = VersionedCollapsingMergeTree(sign, version)
ORDER BY (user_id, event);

-- 版本 1: alice 有 10 次点击
INSERT INTO user_events_versioned VALUES (1, 'click', 10, 1, 1);

-- 版本 2: 更新为 15 次点击 (取消版本 1 + 插入版本 2)
INSERT INTO user_events_versioned VALUES
    (1, 'click', 10, -1, 1),    -- 取消版本 1
    (1, 'click', 15,  1, 2);    -- 版本 2

-- 即使插入顺序乱了，合并时也能正确配对:
-- version=1 的 +1 和 -1 配对抵消
-- version=2 的 +1 保留

-- 查询 (合并前安全的写法):
SELECT user_id, event, sum(count * sign) AS count
FROM user_events_versioned
GROUP BY user_id, event
HAVING sum(sign) > 0;

-- ============================================================
-- 方式四: INSERT 幂等性 (insert_deduplicate)
-- ============================================================
-- 这不是 UPSERT，而是防止重复 INSERT
-- 适用场景: 消费 Kafka 消息时，如果 consumer 重启导致重复消费

-- 默认开启 (MergeTree 表):
-- SET insert_deduplicate = 1;      -- 默认值

-- 工作原理:
--   每次 INSERT 计算数据块的 hash
--   如果最近的 INSERT 中有相同 hash 的块，跳过本次 INSERT
--   "最近" = 由 replicated_deduplication_window (默认 100) 控制

-- 示例: 以下两次 INSERT 只有第一次生效
INSERT INTO user_profiles VALUES (1, 'alice', 'alice@example.com', 25, 1);
INSERT INTO user_profiles VALUES (1, 'alice', 'alice@example.com', 25, 1);
-- 第二次 INSERT 被静默跳过 (因为数据块 hash 相同)

-- 注意:
--   1. 去重窗口有限 (默认最近 100 个块)
--   2. 只对完全相同的数据块去重 (按字节比较 hash)
--   3. 不同批次中的相同行不会去重 (只比较整个 INSERT 块)
--   4. 非 Replicated 表用 non_replicated_deduplication_window
--   5. 关闭: SET insert_deduplicate = 0 (某些场景需要允许重复插入)

-- ============================================================
-- 方式五: 轻量级 DELETE + INSERT (23.3+)
-- ============================================================
-- ClickHouse 23.3 起支持标准 DELETE 语法 (之前只有 ALTER TABLE DELETE)
DELETE FROM user_profiles WHERE user_id = 1;
INSERT INTO user_profiles VALUES (1, 'alice', 'updated@example.com', 27, 3);

-- 轻量级 DELETE 原理:
--   不是立即删除数据，而是标记行为"已删除" (mask bit)
--   后续查询自动过滤掉标记行
--   后台合并时真正物理删除
--   比 ALTER TABLE DELETE 快得多 (ALTER TABLE DELETE 需要重写整个 part)
--
-- 仍然不推荐高频使用:
--   每次 DELETE 创建一个 mutation，大量小 DELETE 会积累 mutation 队列
--   如果需要高频更新，还是用 ReplacingMergeTree

-- ============================================================
-- 方式六: ALTER TABLE UPDATE (最后手段)
-- ============================================================
-- 重量级操作: 重写整个 data part
ALTER TABLE user_profiles UPDATE email = 'new@example.com' WHERE user_id = 1;
-- 这是异步操作! ALTER 返回不代表更新完成
-- 检查进度: SELECT * FROM system.mutations WHERE table = 'user_profiles';
--
-- 何时使用: 修复数据错误、批量回填字段
-- 何时不使用: 常规业务更新 (太重了)

-- ============================================================
-- 最佳实践总结
-- ============================================================
-- 1. 大多数场景: ReplacingMergeTree + INSERT 覆盖
--    简单、可靠，查询时用 FINAL 或 argMax 去重
--
-- 2. 需要增量聚合: CollapsingMergeTree 或 VersionedCollapsingMergeTree
--    更复杂但支持高效的增量计数/求和
--
-- 3. 防重复消费: insert_deduplicate (幂等性)
--    不是 UPSERT，但解决了 exactly-once 语义问题
--
-- 4. 偶尔修数据: ALTER TABLE UPDATE 或 DELETE + INSERT
--    不要用于常规业务流程
--
-- 5. 批量 > 逐行: ClickHouse 优化的是大批次写入
--    一次 INSERT 10 万行 >> 10 万次 INSERT 1 行
--    推荐每批次 1000-100000 行，每秒不超过 1 次 INSERT
--
-- 6. 如果你发现自己在 ClickHouse 上做大量单行 UPSERT:
--    停下来。重新考虑架构。
--    可能需要: OLTP 数据库 (PostgreSQL) + CDC → ClickHouse
