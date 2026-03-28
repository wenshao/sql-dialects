-- Spark SQL: INSERT (插入)
--
-- 参考资料:
--   [1] Spark SQL Reference - INSERT
--       https://spark.apache.org/docs/latest/sql-ref-syntax-dml-insert-into.html
--   [2] Spark SQL Reference - INSERT OVERWRITE
--       https://spark.apache.org/docs/latest/sql-ref-syntax-dml-insert-overwrite-table.html

-- ============================================================
-- 1. 基本 INSERT
-- ============================================================

INSERT INTO users VALUES (1, 'alice', 'alice@example.com', 25);

-- 指定列名
INSERT INTO users (id, username, email, age)
VALUES (1, 'alice', 'alice@example.com', 25);

-- 多行插入（Spark 2.4+）
INSERT INTO users VALUES
    (1, 'alice', 'alice@example.com', 25),
    (2, 'bob', 'bob@example.com', 30),
    (3, 'charlie', 'charlie@example.com', 35);

-- 从查询插入
INSERT INTO users_archive
SELECT * FROM users WHERE age > 60;

-- ============================================================
-- 2. INSERT OVERWRITE: Spark SQL 最重要的 DML 特性
-- ============================================================

-- INSERT OVERWRITE 替换整张表的数据（而非追加）
INSERT OVERWRITE TABLE users
SELECT * FROM staging_users;

-- 静态分区覆盖（只覆盖指定分区）
INSERT OVERWRITE TABLE orders PARTITION (order_date = '2024-01-15')
SELECT id, user_id, amount FROM staging_orders
WHERE order_date = '2024-01-15';

-- 动态分区覆盖（只覆盖数据中出现的分区）
SET spark.sql.sources.partitionOverwriteMode = dynamic;
INSERT OVERWRITE TABLE orders PARTITION (order_date)
SELECT id, user_id, amount, order_date FROM staging_orders;

-- 设计分析: INSERT OVERWRITE 的核心价值
--   在没有 UPDATE/DELETE 的原生 Spark 表上，INSERT OVERWRITE 是唯一的数据修正方式。
--   它实现了"幂等性"——多次执行相同的 INSERT OVERWRITE 结果相同。
--   这使得 ETL 管道可以安全地重跑（失败后重新执行不会产生重复数据）。
--
-- 对比:
--   MySQL:      INSERT ... ON DUPLICATE KEY UPDATE（非标准但实用的 UPSERT）
--   PostgreSQL: INSERT ... ON CONFLICT DO UPDATE/NOTHING（SQL 标准的 MERGE 简化版）
--   Hive:       INSERT OVERWRITE（与 Spark 完全一致，Spark 继承自 Hive）
--   BigQuery:   WRITE_DISPOSITION = WRITE_TRUNCATE（API 层面等价）
--   ClickHouse: 无 INSERT OVERWRITE（通过 ALTER TABLE DELETE + INSERT 实现）
--   Flink SQL:  INSERT INTO 为追加，INSERT OVERWRITE 用于批模式
--
-- 对引擎开发者的启示:
--   INSERT OVERWRITE 的"动态分区覆盖"模式是关键:
--   - static 模式: 覆盖整张表——简单但危险（可能丢失其他分区数据）
--   - dynamic 模式: 只覆盖有数据的分区——安全且高效
--   Spark 3.0 引入 partitionOverwriteMode=dynamic 是对早期设计的重要修正。

-- ============================================================
-- 3. 分区插入
-- ============================================================

-- 静态分区
INSERT INTO orders PARTITION (order_date = '2024-01-15')
VALUES (1, 100, 99.99);

-- 动态分区
INSERT INTO orders PARTITION (order_date)
SELECT id, user_id, amount, order_date FROM raw_orders;

-- ============================================================
-- 4. CTAS: CREATE TABLE AS SELECT
-- ============================================================

CREATE TABLE active_users AS
SELECT * FROM users WHERE status = 1;

CREATE TABLE top_users USING DELTA PARTITIONED BY (city) AS
SELECT * FROM users WHERE age > 25;

-- CTAS 是 Spark SQL 中最常用的"初始加载"模式:
-- 一次性创建表结构并填充数据，不需要先 CREATE TABLE 再 INSERT

-- ============================================================
-- 5. CTE 结合 INSERT（Spark 3.0+）
-- ============================================================

WITH new_users AS (
    SELECT 'alice' AS username, 'alice@example.com' AS email
)
INSERT INTO users (username, email)
SELECT username, email FROM new_users;

-- ============================================================
-- 6. LOAD DATA（Hive 兼容）
-- ============================================================

LOAD DATA INPATH '/data/users.csv' INTO TABLE users;
LOAD DATA INPATH '/data/users.csv' OVERWRITE INTO TABLE users;
LOAD DATA LOCAL INPATH '/local/users.csv' INTO TABLE users;

-- LOAD DATA vs INSERT:
--   LOAD DATA 直接移动文件到表目录（不做数据转换）
--   INSERT INTO 从查询结果写入（经过 Spark 执行引擎处理）
--   生产环境推荐使用 INSERT INTO/OVERWRITE（经过 Spark 优化和验证）

-- ============================================================
-- 7. VALUES 作为内联表
-- ============================================================

INSERT INTO users
SELECT * FROM VALUES
    (1, 'alice', 'alice@example.com', 25),
    (2, 'bob', 'bob@example.com', 30)
AS t(id, username, email, age);

-- ============================================================
-- 8. Delta Lake Schema Evolution（插入时自动扩展 Schema）
-- ============================================================

-- 开启自动 Schema 合并:
-- SET spark.databricks.delta.schema.autoMerge.enabled = true;
-- INSERT INTO delta_table SELECT * FROM source_with_new_columns;
-- 新列会自动添加到 Delta 表的 Schema 中

-- ============================================================
-- 9. DataFrame write API（与 SQL INSERT 的对应关系）
-- ============================================================

-- df.write.mode("append").saveAsTable("users")       -- = INSERT INTO
-- df.write.mode("overwrite").saveAsTable("users")    -- = INSERT OVERWRITE
-- df.write.mode("ignore").saveAsTable("users")       -- = CREATE TABLE IF NOT EXISTS
-- df.write.mode("error").saveAsTable("users")        -- = 表存在则报错

-- ============================================================
-- 10. 版本演进
-- ============================================================
-- Spark 2.0: INSERT INTO, INSERT OVERWRITE, CTAS
-- Spark 2.4: 多行 VALUES 插入
-- Spark 3.0: CTE + INSERT, partitionOverwriteMode = dynamic
-- Spark 3.4: DEFAULT 列值在 INSERT 时生效
-- Delta:     Schema Evolution on INSERT
--
-- 限制:
--   无 RETURNING 子句（不能返回插入的行）
--   无 INSERT OR IGNORE / INSERT OR REPLACE（使用 MERGE 替代）
--   无 COPY 命令（使用 LOAD DATA 或 DataFrame API 读取文件）
--   INSERT OVERWRITE 的 static 模式可能意外删除其他分区数据
--   大规模 INSERT 的性能瓶颈通常在 Shuffle 和文件写入
