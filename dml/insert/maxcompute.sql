-- MaxCompute (ODPS): INSERT
--
-- 参考资料:
--   [1] MaxCompute SQL - INSERT INTO/OVERWRITE
--       https://help.aliyun.com/zh/maxcompute/user-guide/insert-overwrite-into
--   [2] MaxCompute Tunnel SDK
--       https://help.aliyun.com/zh/maxcompute/user-guide/tunnel

-- ============================================================
-- 1. INSERT OVERWRITE —— MaxCompute 最核心的写入操作
-- ============================================================

-- 覆盖写入整个分区（原子操作: 成功全替换，失败保原数据）
INSERT OVERWRITE TABLE orders PARTITION (dt = '20240115')
SELECT user_id, amount, order_time FROM staging_orders
WHERE dt = '20240115';

-- 设计决策: 为什么 INSERT OVERWRITE 是核心而非 UPDATE?
--   Hive 族引擎的哲学: 不做行级更新，而是重写整个分区
--   底层实现: 写入新的 AliORC 文件到临时目录 → 原子替换旧目录
--   优势:
--     1. 实现简单（文件级操作，无需事务日志）
--     2. 幂等（重跑不会产生重复数据 — ETL 管道的核心需求）
--     3. 原子性（要么全部替换成功，要么保留原数据）
--     4. 无碎片（每次写入都是完整的 AliORC 文件）
--   代价: 即使只改一行，也要重写整个分区的所有数据
--
--   对比:
--     Hive:       INSERT OVERWRITE 完全相同语义
--     Spark:      df.write.mode("overwrite").partitionBy("dt").save()
--     BigQuery:   WRITE_TRUNCATE disposition（类似语义）
--     Snowflake:  无 INSERT OVERWRITE（有 UPDATE/DELETE，不需要）

-- ============================================================
-- 2. INSERT INTO —— 追加写入
-- ============================================================

-- 单行插入（注意: 每次 INSERT 都是一个分布式作业）
INSERT INTO TABLE users VALUES (1, 'alice', 'alice@example.com', 25);

-- 多行插入
INSERT INTO TABLE users VALUES
    (1, 'alice', 'alice@example.com', 25),
    (2, 'bob', 'bob@example.com', 30),
    (3, 'charlie', 'charlie@example.com', 35);

-- INSERT INTO SELECT（追加数据，最常用的形式）
INSERT INTO TABLE users_archive
SELECT username, email, age FROM users WHERE age > 60;

-- 写入分区表
INSERT INTO TABLE events PARTITION (dt = '20240115')
SELECT user_id, event_name, event_time FROM staging_events;

-- 设计注意: INSERT INTO 的性能问题
--   每次 INSERT INTO 都产生新的小文件
--   高频 INSERT INTO 导致大量小文件 → 查询性能下降
--   最佳实践: 尽量用 INSERT OVERWRITE 代替多次 INSERT INTO
--   如果必须追加: 定期执行 ALTER TABLE ... MERGE SMALLFILES

-- ============================================================
-- 3. 动态分区 —— 根据数据自动确定分区值
-- ============================================================

-- 动态分区: 分区列在 SELECT 结果中，不在 PARTITION 子句中指定
INSERT OVERWRITE TABLE events PARTITION (dt)
SELECT user_id, event_name, event_time, dt FROM staging_events;

-- 混合分区: 一级静态 + 二级动态
INSERT OVERWRITE TABLE events PARTITION (dt = '20240115', hour)
SELECT user_id, event_name, event_time, hour FROM staging_events
WHERE dt = '20240115';

-- 设计分析: 动态分区的实现机制
--   优化器在 SELECT 结果中识别分区列的值
--   伏羲调度器为每个不同的分区值创建独立的写入 task
--   每个 task 写入对应分区目录的 AliORC 文件
--   风险: 分区值太多（如按 user_id 分区）会创建海量 task → OOM
--
--   对比:
--     Hive:   SET hive.exec.dynamic.partition.mode=nonstrict;（需手动开启）
--     Spark:  df.write.partitionBy("dt").insertInto("events")
--     BigQuery: 按 _PARTITIONTIME 自动分区（用户无感知）

-- ============================================================
-- 4. 多路输出 —— 一次读取，多次写入
-- ============================================================

-- 一次扫描 staging_events，分别写入两个目标表
FROM staging_events
INSERT OVERWRITE TABLE events_web PARTITION (dt = '20240115')
    SELECT user_id, event_name WHERE source = 'web'
INSERT OVERWRITE TABLE events_app PARTITION (dt = '20240115')
    SELECT user_id, event_name WHERE source = 'app';

-- 设计分析: 多路输出避免了重复扫描源表
--   传统做法: 两个 INSERT 语句 = 两次全表扫描
--   多路输出: 一次扫描，按条件分发到不同目标 = 50% I/O 节省
--   这是 Hive 引入的语法，MaxCompute 完整继承
--   伏羲调度: 在 Map 阶段按 source 分发数据到不同的 Reduce 阶段
--
--   对比:
--     Hive:   FROM ... INSERT ... INSERT ...（相同语法）
--     Spark:  需要 cache() + 两次 write（无等价语法糖）
--     BigQuery: 需要两个独立 INSERT 语句

-- ============================================================
-- 5. CTE + INSERT
-- ============================================================

WITH new_users AS (
    SELECT 'alice' AS username, 'alice@example.com' AS email
)
INSERT INTO TABLE users
SELECT username, email FROM new_users;

-- ============================================================
-- 6. VALUES 子句的注意事项
-- ============================================================

-- MaxCompute 的 VALUES 行为与标准 SQL 有差异:
--   标准 SQL: SELECT 1; 合法
--   MaxCompute: SELECT 1; 不合法（需要 FROM 子句或 VALUES 语法）
--   合法写法:
SELECT 1 FROM (SELECT 1) t;                -- 用子查询
-- SELECT * FROM VALUES (1, 'alice') t(id, name);  -- VALUES 表构造器

-- ============================================================
-- 7. Tunnel SDK —— 大批量数据导入（非 SQL）
-- ============================================================

-- Tunnel 是 MaxCompute 的高吞吐数据通道，非 SQL 接口
-- CLI:
--   tunnel upload data.txt users -fd ',' -h true;
--   tunnel download users data.txt -fd ',';
--
-- 设计分析: 为什么需要 Tunnel（而非 INSERT VALUES）?
--   INSERT VALUES 每次都是一个 MapReduce 作业 → 启动延迟 5-30 秒
--   Tunnel 是流式 HTTP 上传 → 支持 GB 级数据秒级写入
--   对比:
--     BigQuery:   Storage Write API（类似 Tunnel 的高吞吐通道）
--     Snowflake:  COPY INTO（从 Stage 批量加载）
--     ClickHouse: clickhouse-client --query="INSERT" < data.csv

-- ============================================================
-- 8. 横向对比: INSERT 语义
-- ============================================================

-- INSERT OVERWRITE（分区覆盖）:
--   MaxCompute: 核心操作，原子替换分区    | Hive: 完全相同
--   Spark:      支持（overwrite mode）    | BigQuery: WRITE_TRUNCATE
--   Snowflake:  无此概念（有 UPDATE/DELETE，不需要）
--   ClickHouse: 无此概念（用 ALTER TABLE ... DROP PARTITION + INSERT）

-- 多路输出:
--   MaxCompute: FROM ... INSERT ... INSERT ... | Hive: 完全相同
--   其他引擎: 大多不支持此语法

-- 动态分区:
--   MaxCompute: PARTITION (dt) 不指定值      | Hive: 相同
--   BigQuery:   按列值自动分区（_PARTITIONTIME）
--   Snowflake:  CLUSTER BY 自动管理

-- ============================================================
-- 9. 对引擎开发者的启示
-- ============================================================

-- 1. INSERT OVERWRITE 的幂等性是 ETL 管道最重要的特性
-- 2. 批处理引擎的 INSERT 是"提交作业"而非"插入行"—— 延迟模型完全不同
-- 3. 多路输出（一读多写）在 ETL 场景中价值极高，值得在 SQL 层面支持
-- 4. 动态分区简化了 ETL 开发，但需要限制最大分区数（防止 OOM）
-- 5. 高吞吐数据导入应有独立通道（如 Tunnel/Storage Write API），不走 SQL
-- 6. VALUES 每次触发 MapReduce 作业 → 批处理引擎不适合逐行插入
