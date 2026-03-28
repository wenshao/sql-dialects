-- StarRocks: 迁移速查
--
-- 参考资料:
--   [1] StarRocks Documentation - https://docs.starrocks.io/

-- ============================================================
-- 1. 与 Doris 的差异 (两者同源)
-- ============================================================
-- PRIMARY KEY 语法: StarRocks 独有(更清晰)
-- Expression Partition: StarRocks 3.1+(更灵活)
-- 自动分桶: StarRocks 3.0+(可省略 BUCKETS)
-- QUALIFY: StarRocks 3.2+(窗口函数过滤)
-- ASOF JOIN: StarRocks 4.0+(时序匹配)
-- Pipe: StarRocks 3.2+(持续加载)
-- 存算分离: StarRocks 3.0+(Shared-Data)

-- ============================================================
-- 2. MySQL -> StarRocks 核心差异
-- ============================================================
-- 与 MySQL -> Doris 完全相同:
-- 必须选择数据模型 + DISTRIBUTED BY HASH
-- 无外键/CHECK/UNIQUE 约束
-- MySQL 协议兼容

-- ============================================================
-- 3. 类型映射 (与 Doris 相同)
-- ============================================================
-- MySQL INT/BIGINT -> StarRocks INT/BIGINT
-- MySQL TEXT -> STRING
-- MySQL JSON -> JSON(2.2+)

-- ============================================================
-- 4. 写入方式
-- ============================================================
-- INSERT INTO / Stream Load / Broker Load / Routine Load
-- Pipe(3.2+): 对象存储持续加载(StarRocks 独有)

-- ============================================================
-- 5. 权限语法差异
-- ============================================================
-- StarRocks: GRANT SELECT ON db.* TO user
-- Doris:     GRANT SELECT_PRIV ON db.*.* TO user
