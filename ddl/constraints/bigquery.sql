-- BigQuery: 约束
--
-- 参考资料:
--   [1] BigQuery SQL Reference - Table Constraints
--       https://cloud.google.com/bigquery/docs/reference/standard-sql/data-definition-language#table_constraints
--   [2] BigQuery SQL Reference - CREATE TABLE
--       https://cloud.google.com/bigquery/docs/reference/standard-sql/data-definition-language#create_table

-- BigQuery 的约束大多是"信息性"的，不强制执行
-- 主要用于查询优化器生成更好的执行计划

-- ============================================================
-- PRIMARY KEY（信息性，不强制执行）
-- ============================================================

CREATE TABLE users (
    id       INT64 NOT NULL,
    username STRING NOT NULL,
    email    STRING NOT NULL,
    PRIMARY KEY (id) NOT ENFORCED
);

-- 添加信息性主键
ALTER TABLE users ADD PRIMARY KEY (id) NOT ENFORCED;

-- 复合主键
CREATE TABLE order_items (
    order_id INT64 NOT NULL,
    item_id  INT64 NOT NULL,
    PRIMARY KEY (order_id, item_id) NOT ENFORCED
);

-- ============================================================
-- FOREIGN KEY（信息性，不强制执行）
-- ============================================================

ALTER TABLE orders ADD CONSTRAINT fk_orders_user
    FOREIGN KEY (user_id) REFERENCES users (id) NOT ENFORCED;

-- 删除外键
ALTER TABLE orders DROP CONSTRAINT fk_orders_user;

-- ============================================================
-- NOT NULL（唯一强制执行的约束）
-- ============================================================

CREATE TABLE users (
    id       INT64 NOT NULL,
    username STRING NOT NULL,
    email    STRING            -- 默认允许 NULL
);

-- 放宽为可空
ALTER TABLE users ALTER COLUMN email DROP NOT NULL;
-- 注意：不能从可空改为 NOT NULL

-- ============================================================
-- DEFAULT
-- ============================================================

CREATE TABLE users (
    id         INT64 NOT NULL,
    status     INT64 NOT NULL DEFAULT 1,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP()
);

ALTER TABLE users ALTER COLUMN status SET DEFAULT 0;
ALTER TABLE users ALTER COLUMN status DROP DEFAULT;

-- ============================================================
-- 不支持的约束
-- ============================================================

-- UNIQUE: 不支持（信息性也不支持）
-- CHECK: 不支持
-- EXCLUDE: 不支持

-- ============================================================
-- 列级约束替代方案
-- ============================================================

-- 使用 ASSERT 或数据质量检查
-- 在应用层或 ETL 管道中验证数据质量

-- 使用 MERGE 语句防止重复
MERGE INTO users AS target
USING (SELECT @id AS id, @name AS username) AS source
ON target.id = source.id
WHEN NOT MATCHED THEN INSERT (id, username) VALUES (source.id, source.username);

-- 查看约束
SELECT * FROM myproject.mydataset.INFORMATION_SCHEMA.TABLE_CONSTRAINTS;
SELECT * FROM myproject.mydataset.INFORMATION_SCHEMA.KEY_COLUMN_USAGE;

-- 注意：PRIMARY KEY 和 FOREIGN KEY 是信息性的，不强制执行！
-- 注意：NOT NULL 是唯一被强制执行的约束
-- 注意：信息性约束帮助优化器进行 JOIN 优化和查询重写
-- 注意：数据完整性需要在应用层或 ETL 管道中保证
