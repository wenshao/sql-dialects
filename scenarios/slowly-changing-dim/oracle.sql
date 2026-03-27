-- Oracle: 缓慢变化维度 (Slowly Changing Dimension)
--
-- 参考资料:
--   [1] Oracle SQL Language Reference - MERGE
--       https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/MERGE.html
--   [2] Oracle Database Concepts - Flashback Technology
--       https://docs.oracle.com/en/database/oracle/oracle-database/23/cncpt/

-- ============================================================
-- 维度表和源数据表
-- ============================================================

CREATE TABLE dim_customer (
    customer_key   NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    customer_id    VARCHAR2(20) NOT NULL,
    name           VARCHAR2(100),
    city           VARCHAR2(100),
    tier           VARCHAR2(20),
    effective_date DATE DEFAULT SYSDATE NOT NULL,
    expiry_date    DATE DEFAULT DATE '9999-12-31' NOT NULL,
    is_current     CHAR(1) DEFAULT 'Y' NOT NULL CHECK (is_current IN ('Y','N')),
    created_at     TIMESTAMP DEFAULT SYSTIMESTAMP
);

CREATE TABLE stg_customer (
    customer_id VARCHAR2(20),
    name        VARCHAR2(100),
    city        VARCHAR2(100),
    tier        VARCHAR2(20)
);

-- ============================================================
-- 1. SCD Type 1: 直接覆盖（MERGE，Oracle 9i 首创）
-- ============================================================

MERGE INTO dim_customer t
USING stg_customer s
ON (t.customer_id = s.customer_id AND t.is_current = 'Y')
WHEN MATCHED THEN
    UPDATE SET t.name = s.name, t.city = s.city, t.tier = s.tier
    WHERE t.name <> s.name OR t.city <> s.city OR t.tier <> s.tier
WHEN NOT MATCHED THEN
    INSERT (customer_id, name, city, tier)
    VALUES (s.customer_id, s.name, s.city, s.tier);

-- Oracle MERGE 的独特优势:
--   Oracle 9i 是第一个实现 MERGE 的数据库
--   MATCHED + UPDATE WHERE 子句可以只更新变化的行（避免无效更新）
--   MERGE 在一次操作中完成 INSERT + UPDATE（原子性保证）

-- ============================================================
-- 2. SCD Type 2: 保留历史版本（两步 MERGE）
-- ============================================================

-- 步骤 1: 关闭旧版本（将变化的行标记为过期）
MERGE INTO dim_customer t
USING stg_customer s
ON (t.customer_id = s.customer_id AND t.is_current = 'Y')
WHEN MATCHED THEN
    UPDATE SET t.expiry_date = SYSDATE - 1,
               t.is_current  = 'N'
    WHERE t.name <> s.name OR t.city <> s.city OR t.tier <> s.tier;

-- 步骤 2: 插入新版本
INSERT INTO dim_customer (customer_id, name, city, tier)
SELECT s.customer_id, s.name, s.city, s.tier
FROM stg_customer s
WHERE EXISTS (
    SELECT 1 FROM dim_customer d
    WHERE d.customer_id = s.customer_id
      AND d.is_current = 'N' AND d.expiry_date = SYSDATE - 1
)
OR NOT EXISTS (
    SELECT 1 FROM dim_customer d WHERE d.customer_id = s.customer_id
);
COMMIT;

-- ============================================================
-- 3. '' = NULL 对 SCD 的影响
-- ============================================================

-- WHERE t.name <> s.name 的陷阱:
-- 如果 s.name 或 t.name 是空字符串（= NULL），
-- 比较结果是 UNKNOWN，不会触发 UPDATE。
-- 需要用 NVL 或 DECODE 处理:
-- WHERE NVL(t.name, '~') <> NVL(s.name, '~')

-- ============================================================
-- 4. Oracle Flashback: 替代 SCD 的历史数据查询
-- ============================================================

-- Flashback Query: 查询某个时间点的数据快照
SELECT * FROM dim_customer
AS OF TIMESTAMP SYSTIMESTAMP - INTERVAL '1' HOUR;

-- Flashback Version Query: 查看某行的所有变更历史
SELECT customer_id, name, city, tier,
       VERSIONS_STARTTIME, VERSIONS_ENDTIME, VERSIONS_OPERATION
FROM dim_customer
VERSIONS BETWEEN TIMESTAMP SYSTIMESTAMP - INTERVAL '1' DAY AND SYSTIMESTAMP
WHERE customer_id = 'C001';
-- VERSIONS_OPERATION: I=Insert, U=Update, D=Delete

-- 设计分析:
--   Flashback 提供了 SCD 的"免费"替代方案:
--   不需要维护 effective_date/expiry_date/is_current 列，
--   直接通过 MVCC Undo 段查询历史版本。
--   限制: Undo 保留时间有限（由 UNDO_RETENTION 控制）。
--
-- 横向对比:
--   Oracle:     Flashback（基于 Undo，最优雅但有时间限制）
--   PostgreSQL: 无原生 Flashback（需要 PITR 或手动审计）
--   SQL Server: Temporal Tables (2016+)（系统维护的历史表）
--   MySQL:      无原生 Flashback

-- ============================================================
-- 5. 对引擎开发者的总结
-- ============================================================
-- 1. MERGE 是 SCD 实现的核心 DML，Oracle 9i 首创，SQL:2003 标准化。
-- 2. Flashback Version Query 提供了 SCD 的"零成本"替代方案。
-- 3. '' = NULL 影响变更检测（<> 比较对 NULL 结果为 UNKNOWN）。
-- 4. SCD Type 2 在 Oracle 中需要两步操作（MERGE + INSERT）。
-- 5. Temporal Tables（SQL Server 方式）是更现代的 SCD 替代方案。
