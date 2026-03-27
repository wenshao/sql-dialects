-- MySQL: INSERT
--
-- 参考资料:
--   [1] MySQL 8.0 Reference Manual - INSERT
--       https://dev.mysql.com/doc/refman/8.0/en/insert.html
--   [2] MySQL 8.0 Reference Manual - LOAD DATA
--       https://dev.mysql.com/doc/refman/8.0/en/load-data.html
--   [3] MySQL Internals - InnoDB Change Buffer
--       https://dev.mysql.com/doc/refman/8.0/en/innodb-change-buffer.html
--   [4] MySQL 8.0 Reference Manual - Bulk Data Loading for InnoDB
--       https://dev.mysql.com/doc/refman/8.0/en/optimizing-innodb-bulk-data-loading.html

-- ============================================================
-- 1. 基本语法
-- ============================================================

-- 单行插入
INSERT INTO users (username, email, age) VALUES ('alice', 'alice@example.com', 25);

-- 多行插入（批量 VALUES）
INSERT INTO users (username, email, age) VALUES
    ('alice', 'alice@example.com', 25),
    ('bob', 'bob@example.com', 30),
    ('charlie', 'charlie@example.com', 35);

-- 插入并忽略重复（匹配唯一索引/主键冲突时静默跳过）
INSERT IGNORE INTO users (username, email, age) VALUES ('alice', 'alice@example.com', 25);

-- 从查询结果插入
INSERT INTO users_archive (username, email, age)
SELECT username, email, age FROM users WHERE age > 60;

-- 8.0.19+: VALUES 行别名（替代废弃的 VALUES() 函数）
INSERT INTO users (username, email, age) VALUES ('alice', 'alice@example.com', 25) AS new
ON DUPLICATE KEY UPDATE email = new.email;

-- 8.0.19+: TABLE 语句（插入整个表的所有行）
INSERT INTO users_backup TABLE users;

-- 获取自增 ID
INSERT INTO users (username, email) VALUES ('alice', 'alice@example.com');
SELECT LAST_INSERT_ID();

-- SET 语法（MySQL 特有，等价于 VALUES 但可读性不同）
INSERT INTO users SET username = 'alice', email = 'alice@example.com', age = 25;

-- 指定列默认值
INSERT INTO users (username, email, age) VALUES ('alice', 'alice@example.com', DEFAULT);

-- ============================================================
-- 2. INSERT 的内部执行机制（对 SQL 引擎开发者）
-- ============================================================

-- 2.1 InnoDB INSERT 的写入路径
-- 一条 INSERT 在 InnoDB 内部的执行步骤:
--   (1) 分配事务 ID（trx_id），写入 undo log（用于 MVCC 和回滚）
--   (2) 在聚集索引（主键 B+树）中定位插入位置
--   (3) 将行数据写入 Buffer Pool 中的页（如果页不在内存则先从磁盘读入）
--   (4) 对二级索引的更新写入 Change Buffer（见 2.2），不立即修改索引页
--   (5) 将修改记录写入 redo log（WAL 协议，保证持久性）
--   (6) 提交时 redo log 刷盘（由 innodb_flush_log_at_trx_commit 控制）
--
-- 关键设计:
--   聚集索引插入必须立即完成（因为数据就存在聚集索引的叶节点中），
--   但二级索引的更新可以延迟（Change Buffer），这是 InnoDB 写入性能的核心优化。

-- 2.2 Change Buffer（原 Insert Buffer）
-- InnoDB 对二级索引的写入优化:
--   当二级索引页不在 Buffer Pool 中时，不立即从磁盘读入，
--   而是将修改缓存在 Change Buffer 中，等后续读取该页时再 merge。
--
-- 适用条件:
--   - 仅针对非唯一二级索引（唯一索引必须读页才能判断唯一性）
--   - 支持 INSERT、DELETE、UPDATE 操作（5.5+ 扩展为 Change Buffer）
--   - 由 innodb_change_buffer_max_size 控制大小（默认 25%，即 Buffer Pool 的 25%）
--
-- 设计权衡:
--   优点: 随机 I/O 转为顺序写入，大幅减少磁盘读取（对 HDD 提升巨大）
--   缺点: crash recovery 时需要额外的 merge 步骤；SSD 上优势减小
--         如果表有大量唯一索引，Change Buffer 的价值很低
--
-- 对引擎开发者的启示:
--   LSM-Tree 引擎（RocksDB/LevelDB）天然具有类似的写入缓冲能力。
--   B+Tree 引擎如果要优化写入，Change Buffer 是一个经过验证的方案。
--   设计时需要考虑: 缓冲合并的时机、crash recovery 的正确性、内存配额管理。

-- 2.3 AUTO_INCREMENT 与批量 INSERT 的锁交互
-- innodb_autoinc_lock_mode 决定自增值的分配方式:
--   0 (traditional): 语句级 AUTO-INC 锁（整条 INSERT 持有表锁）
--   1 (consecutive): 简单 INSERT 用轻量 mutex；批量 INSERT（INSERT...SELECT）用表锁
--   2 (interleaved):  8.0 默认，所有 INSERT 都用轻量 mutex（最快但 ID 可能不连续）
--
-- 在 mode=2 下，并发批量 INSERT 的自增值可能交错:
--   线程 A: INSERT 100 行，得到 ID 1,3,5,7...（不连续）
--   线程 B: INSERT 100 行，得到 ID 2,4,6,8...（交错分配）
-- 这对 binlog 复制有影响: mode=2 要求 binlog_format=ROW（不能用 STATEMENT）

-- ============================================================
-- 3. 批量写入方案对比（性能分析）
-- ============================================================

-- 3.1 单行 INSERT vs 多行 VALUES vs LOAD DATA

-- 方案 A: 逐行 INSERT（最慢）
-- INSERT INTO t VALUES (1, 'a'); INSERT INTO t VALUES (2, 'b'); ...
-- 每条语句: 解析 → 优化 → 执行 → redo/undo → 可能的隐式 commit
-- 网络往返: N 次
-- 10 万行典型耗时: 30-60 秒

-- 方案 B: 多行 VALUES（推荐的应用层方案）
-- INSERT INTO t VALUES (1,'a'), (2,'b'), (3,'c'), ...;
-- 一次解析执行，一次网络往返，一次 redo log fsync
-- 最佳批次大小: 1000-5000 行（过大会导致 binlog event 过大）
-- 10 万行典型耗时: 1-3 秒

-- 方案 C: LOAD DATA INFILE（最快的单机方案）
LOAD DATA INFILE '/tmp/users.csv'
INTO TABLE users
FIELDS TERMINATED BY ',' ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(username, email, age);
-- 绕过 SQL 层解析，直接构建行数据，批量写入
-- 可以临时关闭索引和约束检查进一步加速:
--   SET unique_checks = 0;
--   SET foreign_key_checks = 0;
--   ALTER TABLE t DISABLE KEYS;   -- MyISAM 专用
-- 10 万行典型耗时: 0.3-1 秒
-- 注意: secure_file_priv 限制文件路径；LOAD DATA LOCAL INFILE 从客户端读文件

-- 方案 D: SELECT INTO OUTFILE + LOAD DATA（表间数据迁移最优解）
SELECT * FROM users INTO OUTFILE '/tmp/users_export.csv'
FIELDS TERMINATED BY ',' ENCLOSED BY '"' LINES TERMINATED BY '\n';
-- 再用 LOAD DATA 导入目标表，避免 INSERT...SELECT 的锁和事务开销

-- 3.2 批量加载优化技巧
-- (1) 按主键顺序插入: 避免页分裂（InnoDB 聚集索引按主键排序）
-- (2) 事务批量提交: START TRANSACTION; 插入 N 行; COMMIT; 减少 fsync 次数
-- (3) 调大 bulk_insert_buffer_size: MyISAM 的批量插入缓冲（默认 8MB）
-- (4) innodb_buffer_pool_size: 确保 Buffer Pool 能容纳活跃数据和索引
-- (5) 先删索引再加载再建索引: 适用于空表的初始加载

-- ============================================================
-- 4. 横向对比: 各引擎的批量写入最佳方案
-- ============================================================

-- MySQL:       LOAD DATA INFILE（最快）> 多行 VALUES > INSERT...SELECT
--              特点: 面向行的 OLTP 写入设计，单条事务粒度

-- PostgreSQL:  COPY FROM（等价于 LOAD DATA，但更标准化）
--              COPY users FROM '/tmp/users.csv' WITH (FORMAT csv, HEADER true);
--              pg_bulkload: 第三方工具，绕过 WAL 日志（危险但更快）
--              特点: COPY 是官方推荐的大批量加载方式

-- Oracle:      SQL*Loader（命令行工具，最快的加载方式）
--              INSERT /*+ APPEND */ INTO ... SELECT ...（直接路径插入，绕过 Buffer Cache）
--              特点: Direct Path Load 直接写数据文件，不经过 SGA

-- SQL Server:  BULK INSERT（类似 LOAD DATA）/ BCP 工具
--              最小日志: BULK INSERT WITH (TABLOCK)，在简单恢复模式下不写完整日志
--              特点: 最小日志模式是 SQL Server 的独特优化

-- ClickHouse:  INSERT INTO ... FORMAT CSVWithNames / JSONEachRow / Native
--              最佳实践: 每次写入 >= 1000 行，避免小批量（MergeTree 每次写入生成一个 part）
--              特点: 列式存储按 part 组织，小批量写入会导致大量 part 合并开销

-- Doris/StarRocks: Stream Load（HTTP 接口，推荐）/ Broker Load（从 HDFS/S3 加载）
--              INSERT INTO ... SELECT 仅用于少量数据或 ETL
--              特点: Stream Load 是面向实时分析场景设计的写入协议

-- BigQuery:    LOAD DATA（从 GCS 加载）是主要方式，INSERT DML 每天有配额限制
--              bq load --source_format=CSV gs://bucket/file.csv dataset.table
--              特点: 不鼓励行级 INSERT，设计哲学是批量加载

-- Hive/Spark:  INSERT OVERWRITE（覆盖分区）是标准写入方式，不支持单行 INSERT
--              LOAD DATA INPATH '/hdfs/path' INTO TABLE t;（移动文件而非复制）
--              特点: 写入 = 生成不可变文件（ORC/Parquet），没有行级更新概念

-- ============================================================
-- 5. 对引擎开发者: 批量写入接口设计
-- ============================================================

-- 5.1 写入协议的设计选择
--
-- 行协议（Row-based）:
--   MySQL/PG 的 INSERT 语句，一次一行或多行
--   优点: 简单、SQL 标准、事务语义清晰
--   缺点: 文本解析开销大、网络效率低（尤其是逐行 INSERT）
--   适用: OLTP 场景、低延迟要求
--
-- 列协议（Columnar）:
--   ClickHouse Native 格式、Arrow Flight 协议
--   数据按列组织传输，对列式存储引擎零拷贝
--   优点: 压缩比高、编码效率好（同类型数据放一起）
--   缺点: 需要客户端 SDK 支持，不是 SQL 标准
--   适用: OLAP 场景、批量分析数据加载
--
-- 文件导入协议:
--   CSV/TSV（通用）、ORC/Parquet（列式文件）、JSON
--   MySQL LOAD DATA / PG COPY / ClickHouse INSERT FORMAT
--   优点: 绕过 SQL 解析层，吞吐量最高
--   缺点: 错误处理粗粒度（通常只能跳过或中断）
--   适用: 初始数据加载、ETL 管道

-- 5.2 写入缓冲的设计决策
--
-- (1) WAL 优先还是内存表优先?
--   MySQL InnoDB: 修改 Buffer Pool 页 + WAL（redo log），脏页异步刷盘
--   RocksDB/LSM: 写入 MemTable + WAL，MemTable 满后 flush 为 SST 文件
--   ClickHouse: 写入内存生成 part，part 直接刷盘，无 WAL（通过 ReplicatedMergeTree 保证可靠性）
--
-- (2) 索引维护时机
--   同步更新: 每次 INSERT 立即更新所有索引（PG、Oracle 默认）
--   延迟更新: Change Buffer（InnoDB）、批量构建（LOAD DATA + DISABLE KEYS）
--   后台合并: LSM-Tree 的 Compaction（写入不更新索引，读取时合并）
--
-- (3) 可见性控制
--   提交即可见: 传统 RDBMS（INSERT 提交后立刻对其他事务可见）
--   延迟可见: ClickHouse（part 写入后需要一段时间才能被查询看到）
--   分区可见: Hive（INSERT OVERWRITE 完成后整个分区原子性可见）

-- ============================================================
-- 6. INSERT IGNORE 与 INSERT ... ON DUPLICATE KEY UPDATE 的区别
-- ============================================================
-- INSERT IGNORE: 冲突时静默跳过，不报错不更新
--   注意: 不仅忽略唯一冲突，还会把类型转换错误等降级为警告（有隐患）
-- ON DUPLICATE KEY UPDATE: 冲突时执行 UPDATE（见 upsert/mysql.sql）
-- REPLACE INTO: 冲突时 DELETE + INSERT（见 upsert/mysql.sql）
--
-- INSERT IGNORE 的隐藏行为:
--   - 字符串截断: 超长字符串被截断为 VARCHAR(n) 长度（而非报错）
--   - 数值溢出: 超范围的数值被截断为类型最大/最小值
--   - NOT NULL 违反: 插入类型的默认零值（0、''、'0000-00-00'）
--   这些行为在 strict mode 下也会被 IGNORE 降级为警告，非常危险。

-- ============================================================
-- 7. 版本演进
-- ============================================================
-- MySQL 4.1:   INSERT ... ON DUPLICATE KEY UPDATE
-- MySQL 5.0:   INSERT ... SELECT 加锁改进
-- MySQL 5.6:   多值 INSERT 性能优化（减少 redo log 量）
-- MySQL 8.0.13: 表达式默认值（DEFAULT (expr)）
-- MySQL 8.0.19: VALUES 行别名语法（替代废弃的 VALUES() 函数）
-- MySQL 8.0.19: TABLE 语句（INSERT INTO t TABLE s）
