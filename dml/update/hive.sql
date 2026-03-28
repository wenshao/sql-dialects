-- Hive: UPDATE (仅 ACID 表, Hive 0.14+)
--
-- 参考资料:
--   [1] Apache Hive Language Manual - DML
--       https://cwiki.apache.org/confluence/display/Hive/LanguageManual+DML
--   [2] Apache Hive - Hive Transactions
--       https://cwiki.apache.org/confluence/display/Hive/Hive+Transactions

-- ============================================================
-- 1. UPDATE 的前提条件
-- ============================================================
-- Hive UPDATE 仅支持 ACID 事务表:
-- 1. ORC 格式: 只有 ORC 支持 ACID（Parquet 不支持）
-- 2. transactional=true: 表属性中启用事务
-- 3. 托管表: 外部表(EXTERNAL)不支持 UPDATE
-- 4. 事务管理器: hive.txn.manager = DbTxnManager
--
-- CREATE TABLE users (id BIGINT, username STRING, email STRING, age INT)
-- STORED AS ORC TBLPROPERTIES ('transactional'='true');

-- ============================================================
-- 2. ACID 表的 UPDATE
-- ============================================================
-- 基本更新
UPDATE users SET age = 26 WHERE username = 'alice';

-- 多列更新
UPDATE users SET email = 'new@example.com', age = 26 WHERE username = 'alice';

-- CASE 表达式
UPDATE users SET status = CASE
    WHEN age < 18 THEN 'minor'
    WHEN age >= 65 THEN 'senior'
    ELSE 'adult'
END;

-- 自引用更新
UPDATE users SET age = age + 1;

-- 子查询更新
UPDATE users SET age = (SELECT AVG(age) FROM users) WHERE age IS NULL;

-- UPDATE 的内部实现:
-- UPDATE users SET age=26 WHERE id=1 被转换为:
-- 1. 读取 WHERE 匹配的行
-- 2. 写入 delete delta（标记旧行为删除）
-- 3. 写入 insert delta（插入包含新值的行）
-- 本质上: UPDATE = DELETE + INSERT
-- 这意味着 UPDATE 的 I/O 代价约为同等行数 DELETE + INSERT 的总和

-- ============================================================
-- 3. 非 ACID 表的替代方案: INSERT OVERWRITE
-- ============================================================
-- 重写整个表
INSERT OVERWRITE TABLE users
SELECT
    username,
    CASE WHEN username = 'alice' THEN 'new@example.com' ELSE email END AS email,
    CASE WHEN username = 'alice' THEN 26 ELSE age END AS age
FROM users;

-- 重写特定分区（更高效）
INSERT OVERWRITE TABLE events PARTITION (dt='2024-01-15')
SELECT
    user_id,
    CASE WHEN event_name = 'login' THEN 'user_login' ELSE event_name END AS event_name,
    event_time
FROM events
WHERE dt = '2024-01-15';

-- INSERT OVERWRITE 模拟 UPDATE 的设计分析:
-- 优点: 不需要 ACID 支持，所有表都可用; 结果是幂等的
-- 缺点: 需要读写整个表/分区（即使只更新一行）;
--        需要手动在 CASE 中处理每一列（SQL 复杂度高）
-- 适用: 批量数据修正（如全量数据清洗）

-- ============================================================
-- 4. 已知限制
-- ============================================================
-- 1. 仅 ACID 表支持 UPDATE（ORC + transactional=true）
-- 2. 不支持多表 JOIN UPDATE: 不能 UPDATE a SET ... FROM a JOIN b ON ...
-- 3. 不支持 ORDER BY / LIMIT
-- 4. 分区列不能更新: 分区值是目录路径的一部分
-- 5. 分桶列不能更新 (Hive 2.x): 会破坏桶分配
-- 6. 不支持 RETURNING 子句: 不能返回被更新的行
-- 7. 每次 UPDATE 增加 delta 文件: 频繁 UPDATE 需要定期 Compaction

-- ============================================================
-- 5. 跨引擎对比: UPDATE 设计
-- ============================================================
-- 引擎           UPDATE 实现                  限制
-- MySQL(InnoDB)  In-place 原地更新 + Undo Log  JOIN UPDATE 支持
-- PostgreSQL     写入新 tuple + 标记旧 tuple   UPDATE ... FROM 支持
-- Hive(ACID)     Delete delta + Insert delta   无 JOIN UPDATE
-- Hive(非ACID)   不支持(INSERT OVERWRITE替代)  全量重写
-- Spark/Delta    Copy-on-Write 或 MoR          行级 UPDATE 支持
-- BigQuery       UPDATE (DML 配额限制)         JOIN UPDATE 支持
-- ClickHouse     ALTER TABLE UPDATE (异步)     Mutation 机制
-- Trino          Connector 依赖               部分 Connector 支持
--
-- PostgreSQL 的 UPDATE 实现最独特:
-- 它创建新的行版本(tuple)而不是原地修改，旧版本由 VACUUM 清理。
-- 这与 Hive ACID 的 delta 文件机制在概念上相似（都是追加式）。

-- ============================================================
-- 6. 对引擎开发者的启示
-- ============================================================
-- 1. UPDATE = DELETE + INSERT 是不可变存储系统的必然选择:
--    Hive/PostgreSQL 都将 UPDATE 分解为删除旧行 + 插入新行
-- 2. 分区列不可更新是目录分区模型的限制:
--    修改分区值 = 将文件从一个目录移到另一个目录，这在原子性上难以保证
-- 3. INSERT OVERWRITE 是比 UPDATE 更适合批处理的写入模式:
--    对于批量数据修正，全量重写比逐行 UPDATE 更简单、更高效
-- 4. 频繁 UPDATE 的场景不适合 Hive:
--    每次 UPDATE 产生 delta 文件，累积后需要 Compaction，
--    这使得 Hive ACID 不适合高并发 OLTP 写入
