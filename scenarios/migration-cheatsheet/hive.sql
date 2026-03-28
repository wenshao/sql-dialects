-- Hive: 迁移速查表 (Migration Cheatsheet)
--
-- 参考资料:
--   [1] Apache Hive Language Manual
--       https://cwiki.apache.org/confluence/display/Hive/LanguageManual
--   [2] Apache Hive - Data Types
--       https://cwiki.apache.org/confluence/display/Hive/LanguageManual+Types

-- ============================================================
-- 1. 数据类型映射
-- ============================================================
-- RDBMS → Hive 类型映射:
-- INT/INTEGER       → INT
-- BIGINT             → BIGINT
-- FLOAT              → FLOAT
-- DOUBLE             → DOUBLE
-- DECIMAL(p,s)       → DECIMAL(p,s)
-- VARCHAR(n)/TEXT     → STRING (推荐) 或 VARCHAR(n)
-- CHAR(n)            → CHAR(n) (0.13+) 或 STRING
-- BOOLEAN            → BOOLEAN
-- DATE               → DATE (0.12+)
-- TIMESTAMP          → TIMESTAMP
-- DATETIME           → TIMESTAMP (Hive 无 DATETIME)
-- TIME               → STRING (Hive 无 TIME 类型)
-- BLOB/BYTEA         → BINARY
-- JSON               → STRING (用函数处理) 或 MAP/STRUCT
-- ARRAY              → ARRAY<T>
-- ENUM               → STRING (无 ENUM 类型)

-- ============================================================
-- 2. 核心语法差异
-- ============================================================
-- 建表:
--   MySQL:  CREATE TABLE t (id INT AUTO_INCREMENT PRIMARY KEY) ENGINE=InnoDB;
--   Hive:   CREATE TABLE t (id BIGINT) STORED AS ORC;
--   → 无 AUTO_INCREMENT, 无 PRIMARY KEY 强制执行, 必须指定 STORED AS

-- 写入:
--   MySQL:  INSERT INTO t VALUES (1, 'alice');
--   Hive:   INSERT INTO TABLE t VALUES (1, 'alice');  -- 需要 ACID 表
--   Hive:   INSERT OVERWRITE TABLE t SELECT ...;      -- 核心写入模式

-- 更新:
--   MySQL:  UPDATE t SET name = 'bob' WHERE id = 1;
--   Hive:   UPDATE t SET name = 'bob' WHERE id = 1;   -- 仅 ACID 表
--   Hive:   INSERT OVERWRITE TABLE t SELECT CASE WHEN id=1 THEN 'bob' ELSE name END, ... FROM t;

-- 删除:
--   MySQL:  DELETE FROM t WHERE id = 1;
--   Hive:   DELETE FROM t WHERE id = 1;                -- 仅 ACID 表
--   Hive:   INSERT OVERWRITE TABLE t SELECT * FROM t WHERE id != 1;  -- 非 ACID

-- 分页:
--   MySQL:  SELECT * FROM t LIMIT 10 OFFSET 20;
--   Hive:   SELECT * FROM t ORDER BY id LIMIT 10 OFFSET 20;  -- 2.0+

-- ============================================================
-- 3. 函数映射
-- ============================================================
-- 字符串:
--   MySQL GROUP_CONCAT    → CONCAT_WS(',', COLLECT_LIST(col))
--   MySQL IFNULL           → NVL(col, default) 或 COALESCE
--   PG    string_agg       → CONCAT_WS(',', COLLECT_LIST(col))
--   通用  ||               → CONCAT(a, b)  (Hive 不支持 ||)

-- 日期:
--   MySQL NOW()            → CURRENT_TIMESTAMP
--   MySQL DATE_FORMAT(,%Y) → DATE_FORMAT(, 'yyyy')  (Java 格式)
--   PG    TO_CHAR          → DATE_FORMAT
--   PG    AGE()            → DATEDIFF (只返回天数)

-- 条件:
--   MySQL IFNULL(a,b)      → NVL(a,b) 或 COALESCE(a,b)
--   通用  CASE WHEN        → CASE WHEN (相同)
--   MySQL IF(cond,a,b)     → IF(cond,a,b) (相同)

-- ============================================================
-- 4. 迁移关键陷阱
-- ============================================================
-- 1. 无主键/唯一约束强制: 数据唯一性需要在 ETL 层保证
-- 2. 无自增列: 使用 ROW_NUMBER() 或 UUID()
-- 3. 无索引: 依赖分区裁剪 + ORC/Parquet 内置统计
-- 4. INSERT 代价高: 每条 INSERT 是一个 MR/Tez 作业
-- 5. 分区设计关键: 需要在迁移时设计好分区策略
-- 6. 存储格式选择: ORC(ACID) 或 Parquet(跨引擎兼容)
-- 7. 日期格式不同: Java SimpleDateFormat (yyyy-MM-dd)
-- 8. 不支持 ||: 必须用 CONCAT()
-- 9. 不支持事务控制: 无 BEGIN/COMMIT/ROLLBACK
-- 10. CAST 失败返回 NULL: 不报错（与 PG 不同）

-- ============================================================
-- 5. 从 Hive 迁移到其他引擎
-- ============================================================
-- Hive → Spark SQL: 几乎完全兼容，注意 3.0 默认 ACID 差异
-- Hive → Trino:     语法兼容度高，但 LATERAL VIEW 写法不同（用 UNNEST）
-- Hive → BigQuery:  INSERT OVERWRITE → WRITE_TRUNCATE; LATERAL VIEW → UNNEST
-- Hive → Flink SQL: 可通过 HiveCatalog 直接读写 Hive 表
-- Hive → MaxCompute: 语法高度兼容，注意函数细节差异

-- ============================================================
-- 6. 跨引擎对比: Hive 独有概念
-- ============================================================
-- Hive 概念         RDBMS 等价           说明
-- STORED AS ORC     无直接等价           存储格式声明
-- PARTITIONED BY    PARTITION BY RANGE   目录级分区
-- CLUSTERED BY      无直接等价           Hash 分桶
-- EXTERNAL TABLE    无直接等价           数据不由引擎管理
-- INSERT OVERWRITE  TRUNCATE + INSERT    幂等覆盖写入
-- LATERAL VIEW      CROSS APPLY/UNNEST   展开嵌套类型
-- MAPJOIN hint      无直接等价           广播小表优化
-- MSCK REPAIR       无直接等价           元数据同步
-- SerDe             无直接等价           可插拔序列化

-- ============================================================
-- 7. 对引擎开发者的启示
-- ============================================================
-- 1. Hive 的语法是大数据 SQL 的"基准方言": Spark/MaxCompute/Impala 都高度兼容
-- 2. 迁移的核心困难不是语法而是设计模式:
--    RDBMS 的 INSERT/UPDATE/DELETE 在 Hive 中需要转换为 INSERT OVERWRITE
-- 3. 分区设计是迁移成败的关键: RDBMS 不需要分区策略，Hive 查询性能完全依赖它
