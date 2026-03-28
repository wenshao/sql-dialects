-- Spark SQL: ALTER TABLE
--
-- 参考资料:
--   [1] Spark SQL Reference - ALTER TABLE
--       https://spark.apache.org/docs/latest/sql-ref-syntax-ddl-alter-table.html
--   [2] Delta Lake - Schema Evolution
--       https://docs.delta.io/latest/delta-batch.html#schema-evolution

-- ============================================================
-- 1. 基本语法
-- ============================================================
ALTER TABLE users ADD COLUMNS (phone STRING, address STRING);
ALTER TABLE users ADD COLUMNS (phone STRING COMMENT '手机号码');

-- 重命名列（Spark 3.1+）
ALTER TABLE users RENAME COLUMN phone TO mobile;

-- 修改列类型（仅兼容的类型扩展，如 INT -> BIGINT）
ALTER TABLE users ALTER COLUMN age TYPE BIGINT;

-- 修改列注释
ALTER TABLE users ALTER COLUMN email COMMENT '用户邮箱地址';

-- 修改列位置（Spark 3.1+）
ALTER TABLE users ALTER COLUMN phone AFTER email;
ALTER TABLE users ALTER COLUMN phone FIRST;

-- 修改列可空性（Spark 3.1+, 需要数据源支持）
ALTER TABLE users ALTER COLUMN email SET NOT NULL;
ALTER TABLE users ALTER COLUMN email DROP NOT NULL;

-- 删除列（Spark 3.1+, 需要 Delta/Iceberg 等数据源支持）
ALTER TABLE users DROP COLUMN phone;
ALTER TABLE users DROP COLUMNS (phone, address);

-- 重命名表
ALTER TABLE users RENAME TO members;

-- ============================================================
-- 2. ALTER TABLE 的设计约束（对引擎开发者）
-- ============================================================

-- 2.1 列操作的数据源依赖性
-- Spark ALTER TABLE 的能力完全取决于底层数据源的支持程度:
--   Parquet/ORC (Hive 表):  ADD COLUMNS（追加到末尾），RENAME/DROP 不支持
--   Delta Lake:              全部列操作（ADD/DROP/RENAME/TYPE/POSITION）
--   Iceberg:                 全部列操作 + 列 ID 跟踪（Schema Evolution 最强）
--   CSV/JSON:                几乎无 ALTER 支持
--
-- 这是"计算存储分离"架构的必然结果——ALTER TABLE 需要底层存储格式配合。
-- 传统数据库（MySQL/PostgreSQL）完全控制存储层，ALTER TABLE 能力统一。
--
-- 对比:
--   MySQL:      ALTER TABLE 统一，但大表 ALTER 可能锁表数小时（5.6 前）
--               8.0 INSTANT DDL 可以秒级完成 ADD COLUMN（末尾）
--   PostgreSQL: ADD COLUMN + DEFAULT 在 11+ 是即时的（之前需重写全表）
--   Hive:       ADD COLUMNS 仅追加；REPLACE COLUMNS 可以替换整个 Schema
--   Flink SQL:  ALTER TABLE 主要修改表属性（connector 配置），Schema 变更有限
--   Trino:      ALTER TABLE 能力取决于 Connector 实现

-- 2.2 Schema Evolution（Delta Lake / Iceberg）
-- Delta Lake 和 Iceberg 的 Schema Evolution 是现代数据湖的关键能力:
--   - 列追加: 新数据包含新列，旧数据读取时填 NULL
--   - 列删除: 元数据标记删除，物理文件不变
--   - 列重命名: 通过列 ID 映射（Iceberg）或列名映射（Delta）
--   - 类型扩展: INT -> BIGINT, FLOAT -> DOUBLE（仅向上兼容）
--
-- Iceberg 的 Schema Evolution 基于列 ID（每列有唯一整数 ID），与列名无关。
-- 这意味着重命名列不会破坏已有的 Parquet 文件——文件通过 ID 而非名称关联。
-- Delta Lake 默认基于列名映射，但可以开启 column mapping mode 使用 ID。
--
-- 对引擎开发者的启示:
--   如果设计新的表格式，列 ID 映射比列名映射更健壮（Iceberg 的做法优于早期 Delta）。
--   MySQL 的 INSTANT DDL 也需要在 InnoDB 行格式中处理列版本问题——本质相同。

-- ============================================================
-- 3. 表属性管理
-- ============================================================

-- 设置表属性
ALTER TABLE users SET TBLPROPERTIES ('comment' = '用户账户表');
ALTER TABLE users SET TBLPROPERTIES (
    'delta.autoOptimize.optimizeWrite' = 'true',
    'delta.autoOptimize.autoCompact' = 'true'
);

-- 移除表属性
ALTER TABLE users UNSET TBLPROPERTIES ('comment');
ALTER TABLE users UNSET TBLPROPERTIES IF EXISTS ('comment');

-- 修改存储格式（仅 Hive 表）
ALTER TABLE users SET FILEFORMAT PARQUET;
ALTER TABLE users SET SERDEPROPERTIES ('field.delim' = ',');

-- 设置表注释（Spark 3.0+）
COMMENT ON TABLE users IS '用户账户表';

-- 修改表位置
ALTER TABLE users SET LOCATION '/new/data/path/';

-- ============================================================
-- 4. 分区管理
-- ============================================================

-- 添加分区
ALTER TABLE orders ADD PARTITION (order_date='2024-01-15')
    LOCATION '/data/orders/2024-01-15';
ALTER TABLE orders ADD IF NOT EXISTS PARTITION (order_date='2024-01-15');

-- 删除分区
ALTER TABLE orders DROP PARTITION (order_date='2024-01-15');
ALTER TABLE orders DROP IF EXISTS PARTITION (order_date='2024-01-15');

-- 修复分区（同步文件系统上的分区到 Metastore）
ALTER TABLE orders RECOVER PARTITIONS;
MSCK REPAIR TABLE orders;

-- 设计分析:
--   MSCK REPAIR TABLE 是 Hive 遗留语法。Spark 继承了这一设计，用于将文件系统上
--   已存在但 Metastore 中未注册的分区目录同步到元数据中。
--   这反映了 Hive/Spark 的"Schema-on-Read"理念——数据可以先于元数据存在。
--   Delta Lake/Iceberg 不需要 MSCK REPAIR，因为它们的元数据自包含在数据目录中。
--
-- 对比:
--   Hive:   MSCK REPAIR TABLE（完全相同）
--   Trino:  CALL system.sync_partition_metadata('schema', 'table', 'FULL')
--   MySQL:  分区不涉及文件系统目录，ALTER TABLE ... REORGANIZE PARTITION

-- ============================================================
-- 5. Delta Lake 特有的 ALTER 操作
-- ============================================================

-- 约束管理（Delta Lake 3.0+）
-- ALTER TABLE users ADD CONSTRAINT pk_users PRIMARY KEY (id);
-- ALTER TABLE users ADD CONSTRAINT chk_age CHECK (age > 0);
-- ALTER TABLE users DROP CONSTRAINT pk_users;

-- 启用 Change Data Feed
-- ALTER TABLE users SET TBLPROPERTIES (delta.enableChangeDataFeed = true);

-- 设置隔离级别
-- ALTER TABLE users SET TBLPROPERTIES ('delta.isolationLevel' = 'Serializable');

-- ============================================================
-- 6. 版本演进与限制
-- ============================================================
-- Spark 2.0: ADD COLUMNS, SET TBLPROPERTIES, 分区管理
-- Spark 3.0: COMMENT ON TABLE, DataSource V2 扩展
-- Spark 3.1: RENAME COLUMN, DROP COLUMN, ALTER COLUMN TYPE/POSITION/NULLABILITY
-- Spark 3.4: 更完善的 Schema Evolution
--
-- 限制:
--   不支持 MODIFY COLUMN（MySQL 语法），使用 ALTER COLUMN ... TYPE
--   不支持跨数据库 RENAME（不能 RENAME 到不同 database 下）
--   类型变更仅支持兼容的向上转换（INT->BIGINT, FLOAT->DOUBLE）
--   Parquet/ORC Hive 表: 不支持 DROP COLUMN、RENAME COLUMN
--   列位置变更（FIRST/AFTER）需要 Spark 3.1+ 且数据源支持
