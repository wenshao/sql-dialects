-- Flink SQL: ALTER TABLE
--
-- 参考资料:
--   [1] Flink SQL - ALTER TABLE
--       https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/sql/alter/

-- ============================================================
-- 1. 基本语法
-- ============================================================
-- 重命名表
ALTER TABLE user_events RENAME TO user_events_v2;

-- 修改表属性（WITH 子句中的配置项）
ALTER TABLE user_events SET (
    'scan.startup.mode' = 'earliest-offset',
    'properties.group.id' = 'new-consumer-group'
);

-- 重置（移除）表属性（Flink 1.14+）
ALTER TABLE user_events RESET ('scan.startup.mode');

-- 添加列（Flink 1.17+）
ALTER TABLE users ADD (phone STRING, address STRING);
ALTER TABLE users ADD phone STRING AFTER email;
ALTER TABLE users ADD phone STRING FIRST;

-- 添加计算列
ALTER TABLE users ADD total_price AS price * quantity;

-- 添加 Watermark
ALTER TABLE users ADD WATERMARK FOR event_time AS event_time - INTERVAL '5' SECOND;

-- 修改列类型
ALTER TABLE users MODIFY (phone STRING, age BIGINT);
ALTER TABLE users MODIFY phone STRING AFTER email;

-- 修改 Watermark
ALTER TABLE users MODIFY WATERMARK FOR event_time AS event_time - INTERVAL '10' SECOND;

-- 删除列
ALTER TABLE users DROP (phone, address);

-- 删除 Watermark
ALTER TABLE users DROP WATERMARK;

-- 重命名列
ALTER TABLE users RENAME phone TO mobile;

-- 主键管理
ALTER TABLE users ADD PRIMARY KEY (id) NOT ENFORCED;
ALTER TABLE users DROP PRIMARY KEY;

-- ============================================================
-- 2. 语法设计分析（对 SQL 引擎开发者）
-- ============================================================

-- 2.1 ALTER TABLE 在流处理中的特殊含义
-- 传统 RDBMS 中 ALTER TABLE 修改的是存储结构（磁盘文件需要重写或迁移）。
-- Flink 中 ALTER TABLE 修改的是"外部系统的映射定义"，不涉及物理存储变更。
--
-- 核心差异:
--   - ALTER TABLE SET: 修改 Connector 配置（如 Kafka offset、消费者组）
--   - ALTER TABLE ADD COLUMN: 修改 Schema 映射（外部系统可能已有该列）
--   - ALTER TABLE MODIFY WATERMARK: 影响流处理语义（乱序容忍度变化）
--
-- 设计 trade-off:
--   优点: 可以运行时调整流处理参数（如增加 Watermark 延迟容忍度）
--   缺点: 修改不影响已运行的作业（需要重启作业才生效）；
--         不同 Catalog 支持的 ALTER 操作不同
--
-- 对比:
--   MySQL:      ALTER TABLE 可能触发全表重建（COPY 算法）或原地修改（INSTANT）
--   PostgreSQL: ALTER TABLE ADD COLUMN + DEFAULT 在 11+ 即时
--   DuckDB:     ALTER TABLE 大多即时（列存优势）
--   Trino:      ALTER TABLE 取决于 Connector（Iceberg 支持较多，Hive 有限）
--   Databricks: ALTER TABLE 只修改 Delta Log 元数据（不重写 Parquet 文件）

-- 2.2 修改 Connector 配置（Flink 独有能力）
-- 在流处理中，运行时调整源/目的地参数是关键需求。
ALTER TABLE kafka_events SET (
    'scan.startup.mode' = 'timestamp',
    'scan.startup.timestamp-millis' = '1700000000000'
);
-- 这会让新启动的作业从指定时间戳开始消费 Kafka。
-- 已运行的作业不受影响（Flink 作业的 Schema 在提交时固定）。
--
-- 对比:
--   Trino:      修改 Connector 配置需要重新配置 Catalog 文件并重启 Coordinator
--   Spark:      .option("startingTimestamp", ...) 在读取时指定（API 层面）
--   Databricks: ALTER TABLE SET TBLPROPERTIES（修改 Delta 表属性）

-- 2.3 MODIFY WATERMARK: 流处理语义的 DDL 化
-- Watermark 决定了事件时间窗口何时关闭（直接影响结果正确性）。
-- 把 Watermark 放在 DDL 层面管理是 Flink 的创新设计:
--   - DBA/数据工程师可以用 SQL 调整流处理行为（无需修改代码）
--   - Watermark 参数与表绑定（而非散落在 API 配置中）
--
-- 对比:
--   Spark Structured Streaming: withWatermark() 在 API 代码中（修改需要重新部署）
--   Kafka Streams: grace period 在代码中（同上）

-- 2.4 Schema Evolution 的 Catalog 依赖
-- Flink 的 ALTER TABLE 能力取决于使用的 Catalog:
--   GenericInMemoryCatalog: 支持所有 ALTER 操作（默认，内存存储）
--   HiveCatalog: 支持 ADD COLUMN、RENAME TABLE
--   JDBC Catalog: 有限支持
--   Iceberg Catalog: 支持 ADD/DROP/RENAME COLUMN
--
-- 对比 Schema Evolution 能力:
--   Delta Lake: 支持 ADD/RENAME/DROP COLUMN、类型放宽（INT → BIGINT）
--   Iceberg:    支持 ADD/DROP/RENAME/REORDER、类型放宽（列有唯一 ID）
--   Hive:       仅支持 ADD COLUMN（末尾），RENAME 可能导致数据错位

-- ============================================================
-- 3. 不支持的 ALTER 操作
-- ============================================================
-- Flink 不支持:
--   ALTER TABLE ADD CONSTRAINT（除 PRIMARY KEY NOT ENFORCED）
--   ALTER TABLE ADD INDEX（无索引概念）
--   ALTER TABLE ADD FOREIGN KEY / UNIQUE
--   ALTER TABLE ADD PARTITION（分区由 Connector 管理）
--
-- 设计理由:
--   Flink 不管理物理存储，这些操作应该在底层存储系统中完成。
--   例如: 给 MySQL 表加索引应该在 MySQL 中操作，不是在 Flink 中。

-- ============================================================
-- 4. 横向对比: ALTER TABLE 能力矩阵
-- ============================================================
-- 操作                Flink     DuckDB   Trino(Iceberg)  Databricks
-- ADD COLUMN          部分      即时     即时(元数据)      即时(元数据)
-- DROP COLUMN         部分      即时     即时(元数据)      即时(需CM)
-- RENAME COLUMN       部分      即时     即时(元数据)      即时(需CM)
-- ALTER TYPE          部分      扫描列   只放宽            只放宽
-- ADD CONSTRAINT      PK only   有限     不支持            信息性
-- SET PROPERTIES      支持      N/A      支持              支持
-- MODIFY WATERMARK    支持(独有) N/A     N/A               N/A
-- MODIFY CLUSTERING   N/A       N/A      N/A               支持(独有)
-- (CM = Column Mapping 模式)

-- ============================================================
-- 5. 对引擎开发者的启示
-- ============================================================
-- ALTER TABLE 的设计需要考虑引擎的定位:
--   存储引擎（MySQL/DuckDB）: ALTER TABLE 直接操作物理数据
--   查询引擎（Trino）:        ALTER TABLE 委托给底层 Connector
--   流处理引擎（Flink）:      ALTER TABLE 修改映射定义和处理参数
--
-- Flink 的 MODIFY WATERMARK 是一个值得学习的设计:
-- 将流处理语义参数（乱序容忍度）提升到 DDL 层面，
-- 让非程序员也能用 SQL 调整流处理行为。
-- 对比 Spark 把一切放在 API 中的做法，Flink 更"SQL-native"。
