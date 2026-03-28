-- Snowflake: UPSERT (MERGE)
--
-- 参考资料:
--   [1] Snowflake SQL Reference - MERGE
--       https://docs.snowflake.com/en/sql-reference/sql/merge

-- ============================================================
-- 1. 基本语法
-- ============================================================

-- 标准 MERGE (SQL:2003)
MERGE INTO users AS t
USING (SELECT 'alice' AS username, 'alice@example.com' AS email, 25 AS age) AS s
ON t.username = s.username
WHEN MATCHED THEN
    UPDATE SET email = s.email, age = s.age
WHEN NOT MATCHED THEN
    INSERT (username, email, age) VALUES (s.username, s.email, s.age);

-- 从 staging 表批量 MERGE
MERGE INTO users AS t
USING staging_users AS s
ON t.username = s.username
WHEN MATCHED THEN
    UPDATE SET email = s.email, age = s.age
WHEN NOT MATCHED THEN
    INSERT (username, email, age) VALUES (s.username, s.email, s.age);

-- ============================================================
-- 2. 语法设计分析（对 SQL 引擎开发者）
-- ============================================================

-- 2.1 MERGE 是 Snowflake 唯一的 UPSERT 方案
-- Snowflake 不支持:
--   INSERT ... ON CONFLICT (PostgreSQL 9.5+)
--   INSERT ... ON DUPLICATE KEY UPDATE (MySQL)
--   REPLACE INTO (MySQL)
-- 原因: 这些语法依赖唯一约束来检测冲突，
-- 但 Snowflake 的约束不执行（PK/UNIQUE 是信息性的）→ 无法检测冲突。
-- MERGE 使用显式的 ON 条件匹配，不依赖约束。
--
-- 对比:
--   MySQL:      INSERT ... ON DUPLICATE KEY UPDATE（最常用）+ REPLACE INTO
--   PostgreSQL: INSERT ... ON CONFLICT DO UPDATE / DO NOTHING（最优雅）
--   Oracle:     MERGE（最早实现 MERGE 的数据库，9i+）
--   SQL Server: MERGE（但有大量已知 Bug，多位 MVP 建议避免使用）
--   BigQuery:   MERGE（与 Snowflake 一致）
--   Redshift:   MERGE（2023 新增）
--   Databricks: MERGE INTO（Delta Lake，语法与 Snowflake 一致）
--
-- 对引擎开发者的启示:
--   INSERT ON CONFLICT 依赖约束索引 → 只适合执行约束的 OLTP 引擎
--   MERGE 基于显式 ON 条件 → 适合任何引擎（包括不执行约束的数仓）
--   这就是为什么所有云数仓都选择 MERGE 而非 ON CONFLICT。

-- 2.2 MERGE 的微分区实现
-- MERGE 在 Snowflake 中的执行步骤:
--   (a) 扫描源表 (USING) 和目标表
--   (b) 按 ON 条件执行 JOIN（通常是 Hash Join）
--   (c) 分类: MATCHED / NOT MATCHED
--   (d) MATCHED → 读取旧微分区 → 修改 → 写入新微分区
--   (e) NOT MATCHED → 写入新微分区
--   (f) 原子提交所有新分区
--
-- 性能特征:
--   MERGE 的代价 ≈ JOIN + UPDATE + INSERT
--   大表 MERGE: 主要瓶颈是 JOIN 的 Hash Build 阶段
--   优化: 对目标表的匹配列加 CLUSTER BY 可以显著提升 MERGE 性能

-- ============================================================
-- 3. 带条件的 MERGE
-- ============================================================

-- 条件 UPDATE + DELETE + INSERT
MERGE INTO users AS t
USING staging_users AS s
ON t.username = s.username
WHEN MATCHED AND s.age > t.age THEN
    UPDATE SET age = s.age
WHEN MATCHED AND s.age <= t.age THEN
    DELETE
WHEN NOT MATCHED THEN
    INSERT (username, email, age) VALUES (s.username, s.email, s.age);

-- 多 WHEN MATCHED 子句
MERGE INTO users AS t
USING staging_users AS s
ON t.username = s.username
WHEN MATCHED AND s.status = 'delete' THEN
    DELETE
WHEN MATCHED AND s.status = 'update' THEN
    UPDATE SET email = s.email, age = s.age
WHEN NOT MATCHED AND s.status != 'delete' THEN
    INSERT (username, email, age) VALUES (s.username, s.email, s.age);

-- 对引擎开发者的启示:
--   多 WHEN MATCHED 子句使 MERGE 成为"ETL 万能工具":
--   一条语句同时处理 INSERT + UPDATE + DELETE 三种操作。
--   这在 SCD (Slowly Changing Dimension) 场景中非常有价值。

-- ============================================================
-- 4. 仅 INSERT 不存在的行（INSERT IF NOT EXISTS）
-- ============================================================

MERGE INTO users AS t
USING staging_users AS s
ON t.username = s.username
WHEN NOT MATCHED THEN
    INSERT (username, email, age) VALUES (s.username, s.email, s.age);
-- 等价于 PostgreSQL 的 INSERT ... ON CONFLICT DO NOTHING

-- ============================================================
-- 5. VALUES 子句直接 MERGE
-- ============================================================

MERGE INTO users AS t
USING (
    SELECT column1 AS username, column2 AS email, column3 AS age
    FROM VALUES ('alice', 'alice@example.com', 25), ('bob', 'bob@example.com', 30)
) AS s
ON t.username = s.username
WHEN MATCHED THEN
    UPDATE SET email = s.email, age = s.age
WHEN NOT MATCHED THEN
    INSERT (username, email, age) VALUES (s.username, s.email, s.age);

-- 注意 Snowflake 的 VALUES 表引用使用 column1, column2, ... 作为列名
-- 对比 PostgreSQL 的 VALUES ('a','b') AS t(col1, col2) 语法

-- ============================================================
-- 6. MERGE 与 Streams 的结合
-- ============================================================

-- Stream 捕获源表变更 → MERGE 应用到目标表
-- 这是 Snowflake 的 CDC (Change Data Capture) 标准模式:
--
-- MERGE INTO target AS t
-- USING (SELECT * FROM source_stream WHERE METADATA$ACTION = 'INSERT') AS s
-- ON t.id = s.id
-- WHEN MATCHED THEN UPDATE SET ...
-- WHEN NOT MATCHED THEN INSERT ...;

-- 消费 Stream 后，Stream 偏移量自动推进（仅在 MERGE 提交后）

-- ============================================================
-- 横向对比: UPSERT 能力矩阵
-- ============================================================
-- 能力               | Snowflake  | BigQuery  | PostgreSQL     | MySQL
-- MERGE              | 完整       | 完整      | 15+            | 不支持
-- INSERT ON CONFLICT | 不支持     | 不支持    | 9.5+           | ON DUP KEY
-- 多 WHEN MATCHED    | 支持       | 支持      | 支持           | N/A
-- MERGE + DELETE     | 支持       | 支持      | 支持           | N/A
-- 条件 WHEN          | 支持       | 支持      | 支持           | N/A
-- REPLACE INTO       | 不支持     | 不支持    | 不支持         | 支持
--
-- 为什么 MySQL 没有 MERGE:
--   MySQL 选择了 INSERT ... ON DUPLICATE KEY UPDATE 作为 UPSERT 方案。
--   这个方案更简洁但功能更弱（不支持条件分支、不支持 DELETE）。
--   Oracle MERGE 的设计更通用，被 Snowflake/BigQuery/Databricks 采纳为标准。
