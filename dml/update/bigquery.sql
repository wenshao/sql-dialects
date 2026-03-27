-- BigQuery: UPDATE
--
-- 参考资料:
--   [1] BigQuery SQL Reference - UPDATE
--       https://cloud.google.com/bigquery/docs/reference/standard-sql/dml-syntax#update_statement
--   [2] BigQuery Documentation - DML Quotas
--       https://cloud.google.com/bigquery/quotas#dml

-- ============================================================
-- 1. 基本语法
-- ============================================================

-- 基本更新（WHERE 是必须的!）
UPDATE myproject.mydataset.users SET age = 26 WHERE username = 'alice';

-- 多列更新
UPDATE myproject.mydataset.users
SET email = 'new@example.com', age = 26
WHERE username = 'alice';

-- 更新所有行（必须显式 WHERE true）
UPDATE myproject.mydataset.users SET status = 0 WHERE true;

-- FROM 子句（多表 UPDATE）
UPDATE myproject.mydataset.users u
SET u.status = 1
FROM myproject.mydataset.orders o
WHERE u.id = o.user_id AND o.amount > 1000;

-- CTE + UPDATE
WITH vip AS (
    SELECT user_id FROM myproject.mydataset.orders
    GROUP BY user_id HAVING SUM(amount) > 10000
)
UPDATE myproject.mydataset.users u
SET u.status = 2
FROM vip v WHERE u.id = v.user_id;

-- CASE 表达式
UPDATE myproject.mydataset.users SET status = CASE
    WHEN age < 18 THEN 0
    WHEN age >= 65 THEN 2
    ELSE 1
END WHERE true;

-- ============================================================
-- 2. 嵌套类型 UPDATE（STRUCT 和 ARRAY）
-- ============================================================

-- 更新 STRUCT 字段
UPDATE myproject.mydataset.events
SET properties.source = 'mobile'
WHERE event_name = 'login';

-- 更新整个 STRUCT
UPDATE myproject.mydataset.events
SET properties = STRUCT('mobile' AS source, 'safari' AS browser)
WHERE event_name = 'login';

-- 更新 ARRAY（必须整体替换，不能单独修改元素）
UPDATE myproject.mydataset.users
SET tags = ['vip', 'premium']
WHERE username = 'alice';

-- 追加到 ARRAY（用 ARRAY_CONCAT）
UPDATE myproject.mydataset.users
SET tags = ARRAY_CONCAT(tags, ['new_tag'])
WHERE username = 'alice';

-- 从 ARRAY 中移除元素
UPDATE myproject.mydataset.users
SET tags = (SELECT ARRAY_AGG(t) FROM UNNEST(tags) AS t WHERE t != 'old_tag')
WHERE username = 'alice';

-- 设计分析:
--   STRUCT 字段可以点号访问更新（properties.source），非常直观。
--   ARRAY 不能直接修改单个元素（因为 Capacitor 格式中 ARRAY 是整体存储的）。
--   需要 UNNEST → 过滤 → ARRAY_AGG 重建（语法冗长但功能完整）。

-- ============================================================
-- 3. BigQuery UPDATE 的内部机制（对引擎开发者）
-- ============================================================

-- BigQuery 的 UPDATE 是 Copy-on-Write（COW）:
--   (1) 读取所有满足 WHERE 的行所在的存储文件
--   (2) 在内存中修改
--   (3) 写入新的存储文件
--   (4) 更新元数据指向新文件
--   (5) 标记旧文件为可回收
--
-- 这意味着:
--   UPDATE 1 行和 UPDATE 100 万行的成本差异不大
--   （因为都是读取+重写整个存储文件/分区）
--   → 应该尽量合并多次 UPDATE 为一次操作
--
-- 对比:
--   MySQL InnoDB: 原地修改 B+Tree 页 + redo log（微秒级）
--   PostgreSQL:   标记旧行为 dead + 插入新行（MVCC，微秒级）
--   ClickHouse:   重写 data part（mutation，秒级）
--   BigQuery:     重写存储文件（COW，秒级）

-- DML 配额的影响:
--   每个表每天最多 1500 次 DML
--   → 不能像 OLTP 数据库那样频繁 UPDATE
--   → 应该批量处理: 积累变更 → 一次 MERGE 或 UPDATE 应用

-- ============================================================
-- 4. 分区表 UPDATE 的优化
-- ============================================================

-- 使用分区条件缩小 UPDATE 范围（减少 COW 的数据量）
UPDATE myproject.mydataset.events
SET event_name = 'user_login'
WHERE event_date = '2024-01-15' AND event_name = 'login';
-- 只重写 2024-01-15 分区的存储文件

-- 不带分区条件的 UPDATE 会扫描全表（成本极高）
-- 如果设置了 require_partition_filter = true，不带分区条件的 UPDATE 会报错

-- ============================================================
-- 5. 对比与引擎开发者启示
-- ============================================================
-- BigQuery UPDATE 的设计特征:
--   (1) WHERE 必须显式 → 防止误操作（UPDATE 全表需要 WHERE true）
--   (2) COW 机制 → UPDATE 1 行和 100 万行成本接近
--   (3) DML 配额 → 不适合高频 UPDATE
--   (4) STRUCT 点号更新 → 嵌套类型直接修改
--   (5) ARRAY 整体替换 → 不支持元素级修改
--
-- 对引擎开发者的启示:
--   云数仓的 UPDATE 应该被视为"批量操作"而非"逐行操作"。
--   COW 机制使得 UPDATE 的成本与受影响的分区数成正比。
--   分区设计直接影响 UPDATE 性能（好的分区 = 更少的 COW 范围）。
--   STRUCT 的点号更新是优秀的语法设计，比 JSON 函数更直观。
