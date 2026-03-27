-- Flink SQL: 迁移速查表 (Migration Cheatsheet)
--
-- 参考资料:
--   [1] Flink SQL Reference
--       https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/sql/overview/

-- 一、数据类型: 遵循SQL标准 + 流处理特性
--   INT→INT, BIGINT→BIGINT, FLOAT→FLOAT, DOUBLE→DOUBLE,
--   VARCHAR→STRING/VARCHAR(n), DECIMAL→DECIMAL(p,s), BOOLEAN→BOOLEAN,
--   DATE→DATE, TIMESTAMP→TIMESTAMP(p), BINARY→BYTES/VARBINARY,
--   JSON→STRING(用JSON函数), ARRAY→ARRAY<T>, MAP→MAP<K,V>, ROW→ROW<...>
-- 二、函数: SQL标准函数 + Flink特有函数(PROCTIME(), TUMBLE, HOP等)
-- 三、陷阱: 流处理引擎(批流一体), 需要定义connector和format,
--   无持久化存储(数据在外部系统), WATERMARK对时间语义很重要,
--   状态管理影响性能, 支持的DML有限(取决于connector)
-- 四、自增: 无（流数据由外部源提供ID）
-- 五、日期: CURRENT_TIMESTAMP; CURRENT_DATE; TIMESTAMPADD(DAY,1,ts);
--   TIMESTAMPDIFF(DAY,a,b); DATE_FORMAT(ts,'yyyy-MM-dd HH:mm:ss')
--   TO_TIMESTAMP(s, 'yyyy-MM-dd HH:mm:ss'); FROM_UNIXTIME(epoch)
-- 六、字符串: CHAR_LENGTH, UPPER, LOWER, TRIM, SUBSTRING, REPLACE, POSITION, ||

-- ============================================================
-- 七、数据类型映射（从 MySQL/PostgreSQL 到 Flink SQL）
-- ============================================================
-- MySQL → Flink SQL:
--   INT → INT, BIGINT → BIGINT, FLOAT → FLOAT,
--   DOUBLE → DOUBLE, DECIMAL(p,s) → DECIMAL(p,s),
--   VARCHAR(n) → STRING/VARCHAR(n), TEXT → STRING,
--   DATETIME → TIMESTAMP(3), DATE → DATE,
--   BOOLEAN → BOOLEAN, BLOB → BYTES/VARBINARY,
--   JSON → STRING (用JSON函数), AUTO_INCREMENT → 不适用
-- PostgreSQL → Flink SQL:
--   INTEGER → INT, TEXT → STRING, SERIAL → 不适用,
--   BOOLEAN → BOOLEAN, JSONB → STRING,
--   ARRAY → ARRAY<T>, BYTEA → BYTES
-- 特有类型:
--   TIMESTAMP_LTZ(p), ROW<...>, MULTISET, RAW

-- 八、函数等价映射
-- SQL → Flink SQL:
--   IFNULL → IFNULL/COALESCE, NOW() → CURRENT_TIMESTAMP,
--   CONCAT → CONCAT/||, COUNT/SUM/AVG → 支持,
--   ROW_NUMBER/RANK → 支持 (窗口函数)

-- 九、常见陷阱补充
--   流处理引擎（批流一体），非传统数据库
--   需要定义 connector 和 format (Kafka, JDBC, FileSystem 等)
--   WATERMARK 对事件时间语义非常重要
--   状态管理影响性能和可靠性
--   Checkpoint 确保 exactly-once 语义
--   支持的 DML 取决于 connector (部分只支持 INSERT)
--   PROCTIME() 处理时间 vs 事件时间
--   无持久化存储（数据在外部系统）

-- 十、NULL 处理
-- IFNULL(a, b); COALESCE(a, b, c);
-- NULLIF(a, b);
-- IS NULL / IS NOT NULL

-- 十一、不支持的传统 SQL 特性
-- 无 UPDATE/DELETE (取决于 connector), 无 CREATE INDEX,
-- 无存储过程/触发器, 无 GRANT/REVOKE

-- 十二、窗口操作 (Flink 特有)
-- TUMBLE(ts, INTERVAL '1' HOUR)                      -- 滚动窗口
-- HOP(ts, INTERVAL '5' MINUTE, INTERVAL '1' HOUR)    -- 滑动窗口
-- SESSION(ts, INTERVAL '30' MINUTE)                   -- 会话窗口

-- 十三、日期格式码 (Java SimpleDateFormat)
-- yyyy=年, MM=月, dd=日, HH=24时, mm=分, ss=秒
