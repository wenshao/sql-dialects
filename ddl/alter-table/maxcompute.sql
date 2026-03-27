-- MaxCompute (ODPS): ALTER TABLE
-- Alibaba Cloud's enterprise-level data warehouse (formerly ODPS).
--
-- 参考资料:
--   [1] MaxCompute SQL - ALTER TABLE
--       https://help.aliyun.com/zh/maxcompute/user-guide/alter-table
--   [2] MaxCompute SQL Overview
--       https://help.aliyun.com/zh/maxcompute/user-guide/sql-overview
--   [3] MaxCompute Transactional Tables
--       https://help.aliyun.com/zh/maxcompute/user-guide/transactional-tables
--   [4] MaxCompute Table Operations
--       https://help.aliyun.com/zh/maxcompute/user-guide/table-operations

-- ============================================================
-- 1. 列操作
-- ============================================================

-- 添加列（使用 ADD COLUMNS 语法）
ALTER TABLE users ADD COLUMNS (phone STRING COMMENT '手机号');

-- 一次添加多列
ALTER TABLE users ADD COLUMNS (
    city    STRING COMMENT '城市',
    country STRING COMMENT '国家'
);

-- 添加复杂类型列
ALTER TABLE users ADD COLUMNS (
    tags     ARRAY<STRING> COMMENT '标签列表',
    address  MAP<STRING, STRING> COMMENT '地址信息'
);

-- 修改列名（CHANGE COLUMN）
ALTER TABLE users CHANGE COLUMN phone mobile STRING COMMENT '手机号';

-- 修改列注释
ALTER TABLE users CHANGE COLUMN email email STRING COMMENT '新的邮箱注释';

-- 注意: 不支持 DROP COLUMN（需要通过 CTAS 重建表）
-- 注意: 不支持直接修改列类型（需要通过 CTAS 重建表）
-- 注意: 不支持修改列顺序
-- 注意: 分区列不能被 ADD / DROP / CHANGE

-- ============================================================
-- 2. 分区操作
-- ============================================================

-- 添加分区
ALTER TABLE orders ADD PARTITION (dt = '20240115', region = 'cn');
ALTER TABLE orders ADD IF NOT EXISTS PARTITION (dt = '20240115');

-- 删除分区
ALTER TABLE orders DROP PARTITION (dt = '20240115');
ALTER TABLE orders DROP IF EXISTS PARTITION (dt = '20240115');

-- 合并小文件（减少分区中的小文件数量）
ALTER TABLE orders PARTITION (dt = '20240115') MERGE SMALLFILES;

-- 分区操作限制:
--   分区列不能被 ADD COLUMNS / DROP / CHANGE
--   分区值必须是 STRING 类型（即使看起来像日期或数字）
--   多级分区用逗号分隔

-- ============================================================
-- 3. 表属性操作
-- ============================================================

-- 修改表注释
ALTER TABLE users SET COMMENT '用户信息表 v2';

-- 修改生命周期（TTL 天数）
ALTER TABLE users SET LIFECYCLE 180;    -- 180 天后自动清理
ALTER TABLE users SET LIFECYCLE 0;      -- 0 表示永不过期

-- 修改表属性
ALTER TABLE users SET TBLPROPERTIES ('comment' = 'User table');
ALTER TABLE users SET TBLPROPERTIES ('odps.sql.reducer.instances' = '100');

-- 重命名表
ALTER TABLE users RENAME TO members;

-- 清空表数据
TRUNCATE TABLE users;

-- ============================================================
-- 4. 事务表 ALTER 操作（Transactional Table）
-- ============================================================
-- MaxCompute 从 V2.0 开始支持事务表（Transactional Table），
-- 提供 ACID 能力，与传统数据仓库的 "append-only" 表不同。
-- 事务表支持: INSERT / UPDATE / DELETE

-- 创建事务表
CREATE TABLE trans_users (
    id       BIGINT,
    name     STRING,
    status   STRING,
    upd_time DATETIME
)
TBLPROPERTIES ('transactional' = 'true');

-- 将普通表转换为事务表（不可逆）
ALTER TABLE trans_users SET TBLPROPERTIES ('transactional' = 'true');
-- 注意: 转换后原有数据仍然可读，但后续支持 UPDATE/DELETE

-- 事务表的 ALTER 操作:
--   添加列: 支持（与普通表相同）
ALTER TABLE trans_users ADD COLUMNS (phone STRING);

--   修改列名: 支持
ALTER TABLE trans_users CHANGE COLUMN phone mobile STRING;

--   修改注释: 支持
ALTER TABLE trans_users SET COMMENT '事务用户表';

-- 事务表限制:
--   不支持 DROP COLUMN
--   不支持修改列类型
--   不支持 CLUSTERED BY（事务表不支持聚簇属性）
--   不支持将事务表转回非事务表（不可逆）
--   事务表不支持部分 DDL 操作（如 ALTER TABLE SET LIFECYCLE 可能受限）

-- ============================================================
-- 5. 不支持的 ALTER 操作及替代方案
-- ============================================================

-- 5.1 不支持 DROP COLUMN → 替代: CTAS 重建
CREATE TABLE users_new AS
SELECT id, username, email, age, created_at  -- 不包含要删除的列
FROM users;

DROP TABLE users;
ALTER TABLE users_new RENAME TO users;

-- 5.2 不支持修改列类型 → 替代: CTAS + CAST
CREATE TABLE users_new AS
SELECT id, username, email, CAST(age AS BIGINT) AS age, created_at
FROM users;

-- 5.3 不支持修改列顺序 → 替代: CTAS 指定列顺序
CREATE TABLE users_new AS
SELECT id, email, username, age, phone, created_at  -- 重新排列
FROM users;

-- 5.4 使用 INSERT OVERWRITE 进行数据修复
-- 对于不需要改 schema 的数据更新:
INSERT OVERWRITE TABLE users
SELECT id, username, email, age, created_at FROM users WHERE status = 'active';

-- ============================================================
-- 6. 设计分析（对 SQL 引擎开发者）
-- ============================================================
-- MaxCompute 的 ALTER TABLE 体现了云数据仓库的设计哲学:
--
-- 6.1 为什么 ALTER 能力有限:
--   MaxCompute 使用分布式列式存储（类似 Parquet/ORC）
--   数据按分区存储在分布式文件系统（盘古）上
--   列式存储下: DROP COLUMN 只需元数据标记（实际已支持底层但不暴露 DDL）
--   类型变更需要重写所有数据文件（代价极高，MaxCompute 选择不支持）
--   列顺序在列式存储中无意义（查询时按名称引用）
--
-- 6.2 事务表的设计权衡:
--   传统数据仓库: append-only（只追加），不支持 UPDATE/DELETE
--   MaxCompute 事务表: 通过 Copy-on-Write 实现行级更新
--   代价: 更新产生新的数据文件，需要定期 COMPACT
--   对比 Hive: Hive 也通过 ACID 表支持事务（底层实现类似）
--   对比 BigQuery: 支持 DML (UPDATE/DELETE) 但表级而非行级
--   对比 Snowflake: 完全支持 DML，微分区自动优化
--
-- 6.3 跨方言对比:
--   MaxCompute: ALTER 有限，CTAS 替代，事务表逐步增强
--   Hive:       ALTER 类似 MaxCompute，ACID 表支持事务
--   BigQuery:   ALTER 支持 ADD/DROP 列，不支持修改类型
--   Snowflake:  ALTER 最灵活（ADD/DROP/RENAME/ALTER TYPE）
--   ClickHouse: ALTER 即时（元数据操作），支持 DETACH/ATTACH
--   Redshift:   ALTER 支持 ADD/DROP/RENAME，类型变更需重建
--
-- 6.4 版本演进:
--   MaxCompute V1.0: 基础 ALTER（ADD COLUMNS, RENAME）
--   MaxCompute V2.0: 事务表支持，复杂类型（ARRAY/MAP/STRUCT）
--   MaxCompute V2.x: IF NOT EXISTS / IF EXISTS 支持，MERGE SMALLFILES
--   MaxCompute 最新: Delta Table（增量表），Time Travel 查询

-- ============================================================
-- 7. 最佳实践
-- ============================================================
-- 1. 优先使用 ADD COLUMNS 而非重建表（性能更好）
-- 2. 需要删除列或修改类型时，使用 CTAS + INSERT OVERWRITE 模式
-- 3. 分区表的生命周期管理可自动化过期数据清理
-- 4. 大量小文件用 MERGE SMALLFILES 合并（提升查询性能）
-- 5. 事务表适合需要频繁更新的维度表，不适合海量事实表
-- 6. 非事务表适合海量追加写入的日志/事实数据
