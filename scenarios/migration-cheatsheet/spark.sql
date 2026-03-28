-- Spark SQL: 迁移速查表 (Migration Cheatsheet)
--
-- 参考资料:
--   [1] Spark SQL Migration Guide
--       https://spark.apache.org/docs/latest/sql-migration-guide.html

-- ============================================================
-- 1. 数据类型映射
-- ============================================================
-- MySQL/PostgreSQL -> Spark SQL:
--   INT/INTEGER      -> INT
--   BIGINT           -> BIGINT (别名 LONG)
--   FLOAT/REAL       -> FLOAT
--   DOUBLE PRECISION -> DOUBLE
--   VARCHAR(n)       -> STRING (推荐) 或 VARCHAR(n) (3.1+)
--   CHAR(n)          -> STRING (推荐) 或 CHAR(n) (3.1+)
--   TEXT/CLOB        -> STRING
--   DECIMAL(p,s)     -> DECIMAL(p,s)
--   BOOLEAN          -> BOOLEAN
--   DATE             -> DATE
--   TIMESTAMP        -> TIMESTAMP
--   TIMESTAMP WITH TZ -> TIMESTAMP (Spark TIMESTAMP 带 session timezone)
--   BLOB/BYTEA       -> BINARY
--   JSON/JSONB       -> STRING (用 from_json 解析) 或 VARIANT (4.0+)
--   ARRAY            -> ARRAY<T>
--   MAP/HSTORE       -> MAP<K,V>
--   ENUM             -> STRING (无 ENUM 类型)
--   SERIAL/IDENTITY  -> 无 (用 monotonically_increasing_id() 或 uuid())

-- ============================================================
-- 2. 常用函数映射
-- ============================================================
-- 自增 ID:
--   MySQL AUTO_INCREMENT / PG SERIAL -> monotonically_increasing_id() 或 uuid()

-- 日期/时间:
SELECT current_timestamp();                              -- NOW()
SELECT current_date();                                   -- CURDATE()
SELECT date_add(current_date(), 1);                      -- DATE_ADD
SELECT datediff(DATE '2024-12-31', DATE '2024-01-01');   -- DATEDIFF
SELECT date_format(current_timestamp(), 'yyyy-MM-dd HH:mm:ss'); -- DATE_FORMAT

-- 字符串:
--   MySQL GROUP_CONCAT -> CONCAT_WS(',', COLLECT_LIST(col))
--   PG STRING_AGG      -> CONCAT_WS(',', COLLECT_LIST(col))
--   MySQL IFNULL       -> NVL / COALESCE
--   PG COALESCE        -> COALESCE (完全一致)
--   MySQL CONCAT       -> CONCAT (注意: Spark 的 CONCAT 跳过 NULL)

-- 正则:
--   MySQL REGEXP        -> RLIKE 或 REGEXP
--   PG ~ operator       -> RLIKE (Java 正则语法，需双反斜杠)

-- 类型转换:
--   MySQL/PG CAST       -> CAST 或 TRY_CAST (安全转换)
--   PG :: operator      -> CAST 或 :: (3.4+)

-- ============================================================
-- 3. DDL 迁移注意事项
-- ============================================================
-- PRIMARY KEY:     Spark 无强制 PK (Delta Lake 3.0+ 信息性 PK)
-- UNIQUE:          不支持 (应用层检查)
-- FOREIGN KEY:     不支持 (Delta Lake 3.0+ 信息性 FK)
-- CHECK:           仅 Delta Lake 支持
-- AUTO_INCREMENT:  不支持 (见上方替代方案)
-- INDEX:           不支持 (用分区/Z-ORDER/Bloom Filter 替代)
-- STORED PROCEDURE: 不支持 (用 PySpark/Scala 应用代码替代)
-- TRIGGER:         不支持 (用 CDF/Streaming 替代)

-- ============================================================
-- 4. DML 迁移注意事项
-- ============================================================
-- UPDATE/DELETE:   需要 Delta Lake 或 Iceberg
-- INSERT OVERWRITE: Spark 独有 (替代 TRUNCATE + INSERT)
-- MERGE INTO:      需要 Delta Lake 或 Iceberg
-- UPSERT:          用 MERGE INTO 替代 ON DUPLICATE KEY UPDATE

-- ============================================================
-- 5. 查询语法差异
-- ============================================================
-- LIMIT + OFFSET:  Spark 3.4+ 支持 (之前用 ROW_NUMBER 替代)
-- ILIKE:           不支持 (用 LOWER(col) LIKE pattern)
-- :: 类型转换:     Spark 3.4+ 支持
-- LATERAL JOIN:    Spark 3.4+ 支持
-- QUALIFY:         不支持 (用子查询包装)
-- RETURNING:       不支持
-- FOR UPDATE:      不支持 (Spark 无行级锁)

-- ============================================================
-- 6. 关键行为差异
-- ============================================================
-- CONCAT NULL 处理:
--   MySQL:      CONCAT('a', NULL) = NULL
--   Spark:      CONCAT('a', NULL) = 'a' (跳过 NULL!)

-- DAYOFWEEK:
--   MySQL:      1=Sunday (与 Spark 一致)
--   PostgreSQL: EXTRACT(DOW) 返回 0=Sunday

-- 整数除法:
--   MySQL:      5/2 = 2.5 (返回 DECIMAL)
--   Spark:      5/2 = 2.5 (返回 DOUBLE), 5 DIV 2 = 2 (整数除法)

-- ANSI 模式:
--   Spark 3.x:  默认关闭 (宽容: 1/0=NULL, CAST('abc' AS INT)=NULL)
--   Spark 4.0:  默认开启 (严格: 报错)

-- 大小写敏感:
--   Spark SQL:  表名/列名默认大小写不敏感
--   PostgreSQL: 默认小写 (除非双引号)
--   MySQL:      取决于操作系统和 lower_case_table_names

-- ============================================================
-- 7. 性能迁移建议
-- ============================================================
-- 数据格式: 优先使用 Parquet/Delta (列式存储，压缩率高)
-- 分区: 日期列分区 (替代数据库的分区表)
-- UDF: 尽量用内置函数 (Python UDF 性能差 10-100 倍)
-- 分区裁剪: WHERE 条件必须包含分区列 (否则全表扫描)
-- 小表广播: 小表 JOIN 用 /*+ BROADCAST(small_table) */
-- AQE: 开启 spark.sql.adaptive.enabled = true

-- ============================================================
-- 8. 推荐迁移路径
-- ============================================================
-- OLTP 数据库 (MySQL/PG) -> Spark SQL:
--   1. 数据通过 JDBC Source 或 CDC 同步到数据湖
--   2. 使用 Delta Lake 格式存储 (ACID + Time Travel)
--   3. 存储过程逻辑迁移到 PySpark/Scala 应用
--   4. 定时任务迁移到 Spark 作业调度 (Airflow/Databricks Workflows)
--
-- Hive -> Spark SQL:
--   1. 语法高度兼容，大部分 HiveQL 可直接运行
--   2. 将 Hive STORED AS ORC/PARQUET 表升级为 Delta Lake
--   3. Hive UDF (Java) 可直接在 Spark 中使用
--   4. Hive Metastore 可直接被 Spark 使用
