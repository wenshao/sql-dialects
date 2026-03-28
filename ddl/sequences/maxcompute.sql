-- MaxCompute (ODPS): Sequences & Auto-Increment
--
-- 参考资料:
--   [1] MaxCompute Documentation - Data Types
--       https://help.aliyun.com/zh/maxcompute/user-guide/data-type-editions
--   [2] MaxCompute Documentation - Built-in Functions
--       https://help.aliyun.com/zh/maxcompute/user-guide/built-in-functions

-- ============================================================
-- 1. MaxCompute 不支持 SEQUENCE / AUTO_INCREMENT —— 设计决策
-- ============================================================

-- 为什么批处理/分布式引擎不需要自增?
--   自增需要全局序列号分配器，在分布式环境中:
--     全局协调: 每次 INSERT 需要向中央节点申请序列号 → 性能瓶颈
--     批量写入: MaxCompute 一次 INSERT OVERWRITE 可能写入数十亿行
--              为每行分配一个全局唯一的递增 ID 代价极高
--     幂等性: INSERT OVERWRITE 是可重试的，但自增 ID 不幂等
--              重跑一次，ID 就不同了 → 与下游数据不一致
--
--   同样不支持的引擎:
--     BigQuery:    无自增（推荐 GENERATE_UUID()）
--     Hive:        无自增
--     ClickHouse:  无自增（分析引擎，数据批量加载）
--     Spark SQL:   无自增（用 monotonically_increasing_id()，但不保证连续）
--
--   支持自增的分布式引擎（及其实现代价）:
--     Snowflake:   AUTOINCREMENT（值不保证连续，通过段分配实现）
--     TiDB:        AUTO_INCREMENT（段分配）+ AUTO_RANDOM（推荐，随机分配避免热点）
--     CockroachDB: SERIAL（每节点独立分配范围，不连续）

-- ============================================================
-- 2. 替代方案 1: ROW_NUMBER() 窗口函数
-- ============================================================

-- 为结果集生成顺序编号（最常用的替代方案）
SELECT
    ROW_NUMBER() OVER (ORDER BY created_at) AS row_id,
    username,
    email
FROM users;

-- CTAS + ROW_NUMBER: 持久化带编号的数据
CREATE TABLE users_with_id AS
SELECT
    ROW_NUMBER() OVER (ORDER BY created_at) AS id,
    username,
    email,
    created_at
FROM users;

-- ROW_NUMBER 的特点:
--   优点: 结果确定（相同数据 + 相同 ORDER BY = 相同编号）
--   缺点: 需要全局排序（所有数据发送到一个 Reducer）
--         对于 TB 级数据，这是严重的性能瓶颈
--   适用: 百万级以下的数据集、分组内编号

-- 分组内编号（避免全局排序，性能好得多）
SELECT
    ROW_NUMBER() OVER (PARTITION BY city ORDER BY created_at) AS city_row_id,
    city,
    username
FROM users;

-- ============================================================
-- 3. 替代方案 2: UUID
-- ============================================================

SELECT UUID() AS id, username, email FROM staging_users;

-- UUID 的特点:
--   优点: 全局唯一，无需协调，生成速度快
--   缺点: 36 字符字符串，占用存储空间大
--         不可排序（不能用于 ORDER BY 保证插入顺序）
--         可读性差（人类无法通过 UUID 判断记录的新旧）
--
--   对比:
--     BigQuery:    GENERATE_UUID()（官方推荐的唯一 ID 方案）
--     Snowflake:   UUID_STRING()
--     PostgreSQL:  gen_random_uuid()（14+内置）

-- ============================================================
-- 4. 替代方案 3: 数据管道中生成 ID
-- ============================================================

-- 在 PyODPS/DataWorks 中预处理:
-- import uuid
-- for row in data:
--     row['id'] = str(uuid.uuid4())  # 或使用雪花算法
-- o.write_table('users', data)

-- 雪花算法（Snowflake ID，与 Snowflake 数据库无关）:
--   时间戳 + 机器 ID + 序列号 = 64 位整数
--   优点: 递增（可排序）、分布式无协调、整数类型（存储紧凑）
--   缺点: 依赖时钟同步
--   适用: 在数据管道中预生成后写入 MaxCompute

-- ============================================================
-- 5. 替代方案 4: 哈希生成确定性 ID
-- ============================================================

-- 基于业务键生成确定性 ID（幂等，重跑结果一致）
SELECT
    MD5(CONCAT(username, '|', email)) AS deterministic_id,
    username,
    email
FROM staging_users;

-- 优点: 幂等（重跑不变），可用于去重
-- 缺点: 不递增，有极小概率碰撞
-- 适用: ETL 场景中需要稳定 ID 的场景

-- ============================================================
-- 6. 横向对比: 自增/序列方案
-- ============================================================

-- 对比总览:
--   MaxCompute:  无自增（ROW_NUMBER/UUID/管道生成）
--   Hive:        无自增（同 MaxCompute）
--   BigQuery:    无自增（GENERATE_UUID 推荐）
--   Snowflake:   AUTOINCREMENT（不保证连续）
--   MySQL:       AUTO_INCREMENT（表级，最多一列）
--   PostgreSQL:  SERIAL（语法糖）→ IDENTITY（10+，SQL 标准）
--   Oracle:      SEQUENCE 对象（独立于表，最灵活）
--   SQL Server:  IDENTITY(seed, increment)（支持步长）
--   TiDB:        AUTO_INCREMENT + AUTO_RANDOM（分布式推荐后者）
--   ClickHouse:  无自增（分析引擎批量加载，应用层生成 ID）

-- 设计哲学差异:
--   OLTP 引擎: 自增是核心需求（逐行插入，主键索引，外键引用）
--   OLAP/批处理引擎: 自增是反模式（批量写入，无点查，幂等性优先）

-- ============================================================
-- 7. 对引擎开发者的启示
-- ============================================================

-- 1. 批处理引擎不应支持自增: 它破坏幂等性，且全局协调代价太高
-- 2. 如果一定要支持: 采用段分配（每个节点预分配一段 ID），放弃连续性保证
-- 3. UUID 是分布式环境下最简单的唯一 ID 方案，但存储效率低
-- 4. 雪花算法是 ID 设计的甜蜜点: 递增 + 分布式 + 整数类型
-- 5. 确定性 ID（基于业务键哈希）在 ETL 场景中优于自增（幂等性）
-- 6. ROW_NUMBER 只适合小数据集或分组内编号，不适合 TB 级全局编号
