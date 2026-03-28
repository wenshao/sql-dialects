-- Hive: 约束 (2.1+, 仅元数据声明)
--
-- 参考资料:
--   [1] Apache Hive Language Manual - Constraints
--       https://cwiki.apache.org/confluence/display/Hive/LanguageManual+DDL#LanguageManualDDL-Constraints
--   [2] HIVE-13290: Support for Constraints
--       https://issues.apache.org/jira/browse/HIVE-13290

-- ============================================================
-- 1. 约束声明语法 (Hive 2.1+)
-- ============================================================
CREATE TABLE orders (
    id         BIGINT    CONSTRAINT pk_orders PRIMARY KEY DISABLE NOVALIDATE,
    user_id    BIGINT    CONSTRAINT fk_user REFERENCES users(id) DISABLE NOVALIDATE,
    amount     DECIMAL(10,2) NOT NULL DISABLE,
    email      STRING    CONSTRAINT uq_email UNIQUE DISABLE NOVALIDATE,
    status     STRING    DEFAULT 'pending',
    order_time TIMESTAMP CONSTRAINT chk_time CHECK (order_time IS NOT NULL) DISABLE NOVALIDATE
)
STORED AS ORC;

-- ============================================================
-- 2. 核心设计: 约束声明但不执行
-- ============================================================
-- Hive 的约束是 "informational constraints"——仅存在于 Metastore 元数据中，
-- 运行时不会验证或强制执行。
--
-- DISABLE NOVALIDATE 是唯一可用的约束模式:
--   DISABLE:    不在 INSERT/UPDATE 时检查约束
--   NOVALIDATE: 不验证已有数据是否满足约束
--   RELY:       可选标记，告诉优化器"信任此约束"用于查询优化
--   NORELY:     默认，优化器不利用约束信息
--
-- 为什么 Hive 不强制执行约束？
-- 1. 性能: 数据量 TB/PB 级，每次 INSERT 检查唯一性需要全表扫描或维护索引
-- 2. 分布式环境: 多个 Mapper/Reducer 并行写入，跨节点唯一性检查代价极高
-- 3. HDFS 限制: 底层存储不支持随机读写，无法高效维护索引结构
-- 4. INSERT OVERWRITE 语义: 整体覆盖分区，约束检查只在写入端有意义

-- ============================================================
-- 3. RELY 约束: 优化器提示
-- ============================================================
CREATE TABLE users_rely (
    id       BIGINT,
    username STRING,
    PRIMARY KEY (id) DISABLE NOVALIDATE RELY
);

-- RELY 标记的作用:
-- 告诉优化器 "可以利用此约束做查询优化"，即使约束不被强制执行。
-- 典型优化:
--   1. JOIN 消除: 如果知道某列是唯一的(PK/UNIQUE)，可以消除不必要的 JOIN
--   2. 空值传播: NOT NULL RELY 让优化器省略 IS NULL 检查
--   3. 外键推导: FK RELY 可以帮助优化器推导 JOIN 选择性
--
-- 风险: 如果数据实际上违反约束，RELY 会导致查询结果错误！
-- 用户必须自行保证数据满足声明的约束。

-- ============================================================
-- 4. DEFAULT 值 (Hive 3.0+)
-- ============================================================
CREATE TABLE products (
    id     BIGINT,
    name   STRING,
    status STRING DEFAULT 'active',
    price  DECIMAL(10,2) DEFAULT 0.00,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
)
STORED AS ORC
TBLPROPERTIES ('transactional' = 'true');

-- DEFAULT 行为:
-- INSERT 时若未指定列值，使用 DEFAULT 值填充
-- 仅支持常量和 CURRENT_TIMESTAMP/CURRENT_DATE
-- 不支持表达式 DEFAULT（如 DEFAULT uuid()）

-- ============================================================
-- 5. NOT NULL 约束
-- ============================================================
-- Hive 中 NOT NULL 是唯一可以选择性强制执行的约束:
CREATE TABLE events (
    id   BIGINT NOT NULL ENABLE,            -- 写入时检查，违反则报错
    name STRING NOT NULL DISABLE,           -- 仅声明，不检查
    ts   TIMESTAMP NOT NULL ENABLE NOVALIDATE  -- 检查新数据，不验证旧数据
)
STORED AS ORC
TBLPROPERTIES ('transactional' = 'true');   -- ENABLE NOT NULL 需要 ACID 表

-- NOT NULL ENABLE 需要 ACID 表的原因:
-- ACID 表的写入路径经过 Hive 的 Writer 组件（可以插入检查逻辑），
-- 非 ACID 表的写入可能绕过 Hive（直接写 HDFS），无法拦截违反约束的数据。

-- ============================================================
-- 6. 查看与管理约束
-- ============================================================
DESCRIBE EXTENDED orders;                    -- 查看约束信息
SHOW CREATE TABLE orders;                    -- DDL 中包含约束定义

ALTER TABLE orders DROP CONSTRAINT pk_orders;
ALTER TABLE orders ADD CONSTRAINT pk_orders_v2 PRIMARY KEY (id) DISABLE NOVALIDATE;

-- ============================================================
-- 7. 跨引擎对比: 约束执行模型
-- ============================================================
-- 引擎           PK/UNIQUE 强制执行   FK 强制执行   CHECK    设计理由
-- MySQL (InnoDB)  强制执行             强制执行      8.0.16+  OLTP 数据完整性
-- PostgreSQL      强制执行             强制执行      完整支持 严格标准合规
-- Hive            不执行(声明式)       不执行        不执行   分布式成本太高
-- BigQuery        不执行(声明式)       不执行        不支持   大规模数据集成本
-- Snowflake       不执行(NOT NULL除外) 不执行        不支持   同上
-- Spark SQL       不支持约束           不支持        不支持   继承 Hive 但更极端
-- Trino           不支持约束           不支持        不支持   查询引擎不写数据
-- MaxCompute      不执行(声明式)       不执行        不支持   类似 Hive
-- Flink SQL       声明式 PK           不支持        不支持   PK 用于 changelog
-- ClickHouse      不执行(声明式)       不支持        不支持   OLAP 聚焦查询性能
--
-- 规律: OLTP 引擎强制执行约束，OLAP/大数据引擎要么不支持要么仅声明。
-- MySQL 早期 CHECK 约束的教训: 解析语法但不执行 → 用户误以为有保护 → 脏数据入库。
-- Hive 的 DISABLE NOVALIDATE 至少明确告知用户"此约束不会被强制执行"。

-- ============================================================
-- 8. 对引擎开发者的启示
-- ============================================================
-- 1. 约束要么执行，要么明确告知不执行:
--    MySQL 5.7 的 CHECK（解析但不执行）是反面教材，Hive 的 DISABLE 至少透明
-- 2. 声明式约束对优化器有价值: 即使不执行，PK/FK 信息可用于 JOIN 优化和查询改写
-- 3. NOT NULL 是最容易强制执行的约束: 只需在写入路径检查，不需要全局数据扫描
-- 4. 分布式系统中唯一性约束的代价:
--    方案 A: 全局协调（代价极高，不适合大数据量）
--    方案 B: 声明但不执行 + 数据质量工具离线检查（Hive/BigQuery 方案）
--    方案 C: 范围分区 + 局部唯一性保证（TiDB 方案）
-- 5. 数据质量应该是独立系统: Great Expectations、dbt tests 等
--    而不是嵌入在查询引擎中（大数据引擎的共识）
