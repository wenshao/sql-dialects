-- Snowflake: CREATE TABLE
--
-- 参考资料:
--   [1] Snowflake SQL Reference - CREATE TABLE
--       https://docs.snowflake.com/en/sql-reference/sql/create-table
--   [2] Snowflake SQL Reference - Data Types
--       https://docs.snowflake.com/en/sql-reference/data-types
--   [3] Snowflake Engineering Blog - Micro-partitions
--       https://docs.snowflake.com/en/user-guide/tables-clustering-micropartitions
--   [4] Snowflake Architecture Overview
--       https://docs.snowflake.com/en/user-guide/intro-key-concepts

-- ============================================================
-- 1. 基本语法
-- ============================================================
CREATE TABLE users (
    id         NUMBER(19,0) NOT NULL AUTOINCREMENT,
    username   VARCHAR(64)  NOT NULL,
    email      VARCHAR(255) NOT NULL,
    age        NUMBER(10,0),
    balance    NUMBER(10,2) DEFAULT 0.00,
    bio        VARCHAR,                     -- 无长度限制时默认 16,777,216 (16MB)
    tags       VARIANT,                     -- 半结构化列: JSON/XML/Avro/Parquet
    created_at TIMESTAMP_NTZ NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    updated_at TIMESTAMP_NTZ NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    PRIMARY KEY (id),                       -- 信息性约束，不强制执行
    UNIQUE (username),                      -- 同上: 不强制执行
    UNIQUE (email)
);

-- ============================================================
-- 2. 语法设计分析（对 SQL 引擎开发者）
-- ============================================================

-- 2.1 三层架构如何影响 CREATE TABLE 语义
-- Snowflake 的 CREATE TABLE 与传统数据库最大的区别: 不涉及任何物理存储细节。
-- 没有 ENGINE 子句、没有 TABLESPACE、没有 STORAGE 参数、没有文件组。
-- 这源于三层分离架构:
--   Storage 层:  数据以列存格式写入云对象存储 (S3/Azure Blob/GCS)
--   Compute 层:  Virtual Warehouse 提供算力，与存储完全独立
--   Services 层: 元数据管理、查询优化、安全控制
--
-- 设计 trade-off:
--   优点: DDL 极简，用户零运维，弹性伸缩（开关 Warehouse 不影响数据）
--   缺点: 无法控制数据物理布局，无法针对特定负载做存储级调优
--         （只能通过 CLUSTER BY 给出"提示"，引擎异步执行）
--
-- 对比:
--   MySQL:       ENGINE=InnoDB/MyISAM，可插拔存储引擎
--   PostgreSQL:  TABLESPACE 指定文件系统位置
--   Oracle:      TABLESPACE + STORAGE 子句精细控制
--   BigQuery:    同样无物理存储参数（与 Snowflake 最相似）
--   Redshift:    DISTSTYLE / DISTKEY / SORTKEY，用户必须手动选择分布策略
--   Databricks:  USING DELTA / LOCATION，Lakehouse 模式需指定存储路径
--
-- 对引擎开发者的启示:
--   Snowflake 证明了"零配置 DDL"的可行性: 引擎内部全自动管理物理布局，
--   用户只需声明逻辑模型。这要求引擎具备足够强的自动调优能力（统计信息、
--   自动聚簇、元数据索引）。Redshift 需要用户选 DISTKEY 的设计在易用性上
--   明显逊色，但给了专家更多控制权。

-- 2.2 约束声明但不执行 (NOT ENFORCED)
-- Snowflake 的 PRIMARY KEY / UNIQUE / FOREIGN KEY 均为信息性约束:
--   - 语法被接受，元数据被记录
--   - 不创建任何数据结构（无索引、无哈希表）
--   - 不在 INSERT/UPDATE 时校验，违反约束的数据可以写入
--
-- 设计理由:
--   在分布式列存引擎中，强制唯一性校验意味着:
--   1) 每次 INSERT 需要全局查重 → 分布式协调开销极大
--   2) 需要维护辅助索引结构 → 与列存批量写入模式冲突
--   3) COPY INTO 批量加载 TB 级数据时逐行校验不可接受
--
-- 约束的实际用途:
--   - 优化器提示: 查询优化器利用 PK/FK 信息做 JOIN 消除和谓词推导
--   - BI 工具: Tableau/Looker 等工具读取约束元数据推断表关系
--   - 文档: 表达设计意图给团队成员
--
-- 对比:
--   MySQL/PostgreSQL/Oracle: 约束强制执行（接受语法就必须执行）
--   BigQuery:      同样不强制（与 Snowflake 理念一致）
--   Redshift:      不强制但用于查询优化（ENCODE/DISTKEY 更重要）
--   Databricks:    Delta Lake 支持 CHECK 但不支持 PK/FK
--   MaxCompute:    不强制，仅用于优化器
--
-- 对引擎开发者的启示:
--   MySQL 8.0.16 之前接受 CHECK 语法但不执行，这是公认的设计失误。
--   Snowflake 的做法更透明: 文档明确标注 NOT ENFORCED。
--   如果引擎不打算执行约束，应在语法层面就显式声明（如 NOT ENFORCED 关键字），
--   而非静默忽略。

-- 2.3 AUTOINCREMENT / IDENTITY: 云数仓的自增设计
-- Snowflake 支持两种等价语法:
--   AUTOINCREMENT [START n INCREMENT m]
--   IDENTITY(start, increment)
-- 但值不保证连续、不保证无间隙。
--
-- 实现推测:
--   多 Warehouse 并发写入时，每个 Warehouse 预分配一段 ID（段分配策略），
--   因此不同 Warehouse 的 INSERT 产生的 ID 可能不连续。
--   这与 TiDB 的 AUTO_INCREMENT 段分配策略类似。
--
-- 对比:
--   MySQL:      AUTO_INCREMENT，5.7- 重启可能回退，8.0+ 持久化
--   PostgreSQL: SERIAL -> IDENTITY (10+)，基于 SEQUENCE
--   BigQuery:   无自增（哲学: 分布式系统不应依赖全局序列）
--   Redshift:   IDENTITY(seed, step)，也不保证连续
--   Databricks: 无自增，用 GENERATED ALWAYS AS IDENTITY (Delta 3.0+)

-- 2.4 VARIANT: 半结构化列的设计哲学
-- VARIANT 是 Snowflake 最独特的类型设计，一个列可存储 JSON/XML/Avro/Parquet。
-- 使用 : 路径运算符访问（如 tags:category::STRING），这是 Snowflake 独有语法。
--
-- 内部实现:
--   VARIANT 列的数据仍然以列存格式存储，Snowflake 自动推断子列
--   (sub-column) 的类型并为高频访问的路径创建独立的物理子列，
--   实现接近原生列的查询性能。最大 16 MB/值。
--
-- 对比:
--   PostgreSQL: JSONB（二进制 JSON，GIN 索引加速）
--   MySQL:      JSON 类型（5.7+，-> / ->> 运算符）
--   BigQuery:   STRUCT + ARRAY（强类型嵌套，必须预定义 Schema）
--   Redshift:   SUPER 类型（借鉴 Snowflake VARIANT 设计）
--   Databricks: STRUCT/MAP/ARRAY（强类型），: 路径语法灵感来自 Snowflake

-- ============================================================
-- 3. 表类型
-- ============================================================

-- 3.1 瞬态表 (TRANSIENT): 无 Fail-safe 保护期，降低存储成本
CREATE TRANSIENT TABLE staging_data (
    id   NUMBER AUTOINCREMENT,
    data VARIANT
);
-- Time Travel: 0-1 天（Permanent 表默认 1 天，Enterprise 最多 90 天）
-- Fail-safe: 无（Permanent 表有 7 天 Snowflake 托管恢复期）
-- 适用场景: ETL 中间表、临时暂存

-- 3.2 临时表 (TEMPORARY): 会话级，会话结束自动删除
CREATE TEMPORARY TABLE temp_results (id NUMBER, score NUMBER);
-- 对其他会话不可见，无 Fail-safe，与 Transient 的区别仅在生命周期

-- 3.3 外部表 (EXTERNAL TABLE): 查询 Stage 上的文件，不加载数据
CREATE EXTERNAL TABLE ext_logs (
    log_time VARCHAR AS (VALUE:c1::VARCHAR),
    message  VARCHAR AS (VALUE:c2::VARCHAR)
)
LOCATION = @my_stage/logs/
FILE_FORMAT = (TYPE = 'CSV');
-- 查询性能远低于原生表（每次都读文件），适合探索性分析
-- 对比 BigQuery 外部表: 同样性能较差，推荐 COPY INTO 加载后查询

-- ============================================================
-- 4. 零拷贝 CLONE: Snowflake 的杀手级特性
-- ============================================================
CREATE TABLE users_clone CLONE users;
-- 基于 Copy-on-Write (COW):
--   克隆表共享源表的微分区指针（仅复制元数据，不复制数据）
--   修改克隆表时才产生新的微分区
--   克隆 TB 级表只需秒级时间，无额外存储成本（直到写入新数据）
--
-- 可以克隆特定时间点的数据（结合 Time Travel）:
CREATE TABLE users_yesterday CLONE users AT (TIMESTAMP => DATEADD(DAY, -1, CURRENT_TIMESTAMP()));
--
-- 对比:
--   MySQL/PostgreSQL/Oracle: 无等价功能（需要 CREATE TABLE AS SELECT 全量复制）
--   BigQuery:    TABLE CLONE (2022+)，语义类似但实现不同
--   Databricks:  SHALLOW CLONE / DEEP CLONE (Delta Lake)
--   Redshift:    无原生 CLONE
--
-- 对引擎开发者的启示:
--   零拷贝 CLONE 依赖不可变分区（immutable micro-partition）设计。
--   如果引擎采用 in-place update（如 InnoDB），则无法实现真正的零拷贝。
--   Lakehouse 格式（Delta/Iceberg/Hudi）的不可变文件特性也天然支持此功能。

-- ============================================================
-- 5. CLUSTER BY: 手动聚簇提示
-- ============================================================
CREATE TABLE orders (
    id         NUMBER AUTOINCREMENT,
    user_id    NUMBER,
    amount     NUMBER(10,2),
    status     VARCHAR(20),
    order_date DATE
)
CLUSTER BY (order_date, user_id);
-- CLUSTER BY 不是索引，不是分区，而是告诉引擎按指定列排列微分区内数据
-- 自动聚簇 (Automatic Reclustering) 在后台异步维护
-- 查看聚簇质量: SELECT SYSTEM$CLUSTERING_INFORMATION('orders');
--
-- 对比:
--   Redshift:    SORTKEY（创建时指定，不自动维护，需要 VACUUM SORT）
--   BigQuery:    CLUSTER BY（语义最接近，也自动维护）
--   Databricks:  OPTIMIZE ZORDER BY（手动触发，不自动）
--   MaxCompute:  CLUSTERED BY + SORTED BY（类似 Hive）

-- ============================================================
-- 6. Time Travel 与 UNDROP
-- ============================================================
CREATE TABLE important_data (
    id   NUMBER,
    data VARCHAR
) DATA_RETENTION_TIME_IN_DAYS = 90;        -- 默认 1 天, Enterprise 版最多 90 天

-- 查询历史数据:
-- SELECT * FROM important_data AT(TIMESTAMP => '2024-01-15 10:00:00'::TIMESTAMP_NTZ);
-- SELECT * FROM important_data BEFORE(STATEMENT => '<query_id>');

-- 误删恢复:
-- DROP TABLE important_data;
-- UNDROP TABLE important_data;

-- ============================================================
-- 7. CREATE OR REPLACE / IF NOT EXISTS / LIKE / CTAS
-- ============================================================
CREATE OR REPLACE TABLE users_v2 (id NUMBER, name VARCHAR);
-- 原子操作: 先 DROP 再 CREATE，但旧表进入 Time Travel 可恢复
-- 对比 MySQL: DROP IF EXISTS + CREATE 不是原子的

CREATE TABLE IF NOT EXISTS audit_log (
    id      NUMBER AUTOINCREMENT,
    action  VARCHAR(50),
    detail  VARIANT,
    ts      TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

CREATE TABLE users_backup LIKE users;      -- 复制结构，不复制数据
CREATE TABLE active_users AS               -- CTAS: 复制结构 + 数据
SELECT id, username, email FROM users WHERE age >= 18;

-- ============================================================
-- 8. 数据类型设计分析
-- ============================================================

-- 8.1 三种 TIMESTAMP 类型: Snowflake 独有的精细设计
-- TIMESTAMP_NTZ: 无时区（Not Time Zone aware），存字面值
-- TIMESTAMP_LTZ: 本地时区（Local Time Zone），内部存 UTC，显示时按 session 时区转换
-- TIMESTAMP_TZ:  带时区偏移（Time Zone），存 UTC + 时区偏移量
--
-- TIMESTAMP 默认映射由 TIMESTAMP_TYPE_MAPPING 参数控制（默认 NTZ）
-- 这三种类型的隐式转换规则复杂，是 Snowflake 最常见的 bug 来源之一
--
-- 对比:
--   PostgreSQL:  TIMESTAMP vs TIMESTAMPTZ（推荐始终用 TIMESTAMPTZ）
--   MySQL:       DATETIME vs TIMESTAMP（2038 年问题）
--   BigQuery:    DATETIME(无时区) vs TIMESTAMP(有时区)
--   Oracle:      TIMESTAMP / TIMESTAMP WITH TIME ZONE / TIMESTAMP WITH LOCAL TIME ZONE
--
-- 对引擎开发者的启示:
--   三种 TIMESTAMP 虽然语义精确，但增加了用户认知负担。
--   PostgreSQL 的"两种就够"策略更受开发者欢迎。
--   如果必须支持三种，需要提供非常清晰的默认值和隐式转换文档。

-- 8.2 VARCHAR 默认 16MB
-- Snowflake 的 VARCHAR 不指定长度时默认最大 16,777,216 字节。
-- 指定长度对存储无影响（内部始终按实际长度存储），仅影响输入校验。
-- 这与 PostgreSQL 的 TEXT 设计理念一致: 长度限制是逻辑约束而非存储优化。
-- 对比 MySQL: VARCHAR(n) 的 n 影响内存临时表分配和索引长度限制。

-- ============================================================
-- 9. 版本演进与建表语法变化
-- ============================================================
-- 2014 GA:   基础 CREATE TABLE + VARIANT
-- 2018:      Time Travel + CLONE 成为核心特性
-- 2020:      External Table GA
-- 2022:      Snowpark + Python UDF
-- 2023:      Iceberg Tables（Apache Iceberg 格式的原生支持）
-- 2024:      Dynamic Tables（声明式 ETL，替代 CTAS + Stream + Task）
--            Hybrid Tables（行存 + 列存，支持索引和约束执行，OLTP 场景）
--
-- Hybrid Tables 标志着 Snowflake 开始反向补充 OLTP 能力:
--   支持 B+树索引、强制约束、行级锁，定位 Unistore（HTAP 混合负载）。
--   这与 BigQuery 纯分析的定位形成分化。

-- ============================================================
-- 横向对比: Snowflake vs 其他云数仓的 CREATE TABLE
-- ============================================================

-- 1. 物理存储控制:
--   Snowflake: 完全自动（零配置）
--   BigQuery:  完全自动（与 Snowflake 最相似）
--   Redshift:  DISTSTYLE EVEN/KEY/ALL + SORTKEY（必须手动选择）
--   Databricks: LOCATION + PARTITIONED BY + TBLPROPERTIES
--   MaxCompute: LIFECYCLE + CLUSTERED BY + RANGE/HASH 分布

-- 2. 半结构化数据:
--   Snowflake: VARIANT 列（最灵活，Schema-on-Read）
--   BigQuery:  STRUCT + ARRAY（强类型，Schema-on-Write）
--   Redshift:  SUPER 类型（借鉴 Snowflake，但查询性能较弱）
--   Databricks: MAP/STRUCT/ARRAY + JSON 路径函数

-- 3. 表克隆:
--   Snowflake: CLONE（零拷贝 COW，秒级）
--   BigQuery:  TABLE CLONE（类似语义）
--   Redshift:  不支持
--   Databricks: SHALLOW CLONE / DEEP CLONE
