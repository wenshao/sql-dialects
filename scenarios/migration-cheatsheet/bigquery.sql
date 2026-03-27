-- BigQuery: 迁移速查表 (Migration Cheatsheet)
--
-- 参考资料:
--   [1] BigQuery Migration Guide
--       https://cloud.google.com/bigquery/docs/migration
--   [2] BigQuery - SQL Translation
--       https://cloud.google.com/bigquery/docs/interactive-sql-translator

-- ============================================================
-- 从 MySQL/PostgreSQL 迁移到 BigQuery 的常见问题
-- ============================================================

-- 1. 数据类型映射
-- MySQL INT/BIGINT       → INT64（唯一整数类型）
-- MySQL FLOAT/DOUBLE     → FLOAT64
-- MySQL DECIMAL(10,2)    → NUMERIC（精度 38，标度 9）
-- MySQL VARCHAR/TEXT      → STRING
-- MySQL DATETIME          → DATETIME（无时区）
-- MySQL TIMESTAMP         → TIMESTAMP（UTC）
-- MySQL BOOLEAN           → BOOL
-- MySQL ENUM              → STRING
-- MySQL JSON              → JSON 或 STRING
-- PostgreSQL SERIAL       → INT64 + DEFAULT GENERATE_UUID()
-- PostgreSQL UUID          → STRING（无专用 UUID 类型）
-- PostgreSQL ARRAY        → ARRAY<Type>（原生支持）
-- PostgreSQL JSONB        → JSON 类型

-- 2. 命名空间
-- MySQL:      database.table
-- PostgreSQL: database.schema.table
-- BigQuery:   project.dataset.table

-- 3. DML 差异
-- MySQL:      AUTO_INCREMENT     → GENERATE_UUID() 或 ROW_NUMBER()
-- MySQL:      INSERT IGNORE      → MERGE ... WHEN NOT MATCHED
-- MySQL:      REPLACE INTO       → MERGE ... WHEN MATCHED / NOT MATCHED
-- MySQL:      ON DUPLICATE KEY   → MERGE
-- MySQL:      TRUNCATE TABLE     → TRUNCATE TABLE（BigQuery 也支持）

-- 4. 不支持的特性
-- 无传统索引（B-Tree/Hash）→ 使用分区 + 聚集
-- 无存储过程（MySQL 风格）→ 使用 BEGIN...END 脚本 + UDF
-- 无触发器 → 使用计划查询或 Cloud Functions
-- 约束是 NOT ENFORCED → 数据质量在 ETL 层保证
-- DML 配额限制 → 批量加载用 LOAD 作业（免费）

-- 5. 函数差异
-- MySQL NOW()              → CURRENT_TIMESTAMP()
-- MySQL IFNULL(a, b)       → IFNULL(a, b) 或 COALESCE(a, b)
-- MySQL DATE_FORMAT(d, f)  → FORMAT_TIMESTAMP(f, d)
-- MySQL GROUP_CONCAT       → STRING_AGG
-- MySQL LIMIT m, n         → LIMIT n OFFSET m（语序不同!）
-- PostgreSQL string_agg    → STRING_AGG
-- PostgreSQL generate_series → GENERATE_ARRAY + UNNEST

-- ============================================================
-- 批量迁移方案
-- ============================================================

-- 1. BigQuery Data Transfer Service（从其他云数仓）
-- 支持: Amazon S3, Amazon Redshift, Teradata

-- 2. LOAD 作业（从 Cloud Storage）
-- bq load --source_format=CSV mydataset.t gs://bucket/data.csv
-- bq load --source_format=PARQUET mydataset.t gs://bucket/data.parquet

-- 3. SQL 翻译器（BigQuery Migration Service）
-- 自动将 MySQL/PostgreSQL/Oracle SQL 翻译为 BigQuery SQL
-- https://cloud.google.com/bigquery/docs/interactive-sql-translator

-- ============================================================
-- 对比与引擎开发者启示
-- ============================================================
-- BigQuery 迁移的核心挑战:
--   DML 配额 → 不能逐行 INSERT（必须批量加载）
--   NOT ENFORCED 约束 → 数据质量需要外部保证
--   无索引 → 分区+聚集替代（查询模式可能需要调整）
--   按扫描量计费 → 查询设计直接影响成本
--
-- 对引擎开发者的启示:
--   SQL 翻译器是降低迁移门槛的关键工具。
--   BigQuery 提供自动化的 SQL 方言转换，极大地简化了迁移。
--   提供 LOAD 作业（批量导入）+ Streaming API（实时写入）
--   两种数据入口，覆盖了所有迁移场景。
