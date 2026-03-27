-- Databricks SQL: ALTER TABLE
--
-- 参考资料:
--   [1] Databricks SQL Language Reference
--       https://docs.databricks.com/en/sql/language-manual/index.html
--   [2] Databricks SQL - Built-in Functions
--       https://docs.databricks.com/en/sql/language-manual/sql-ref-functions-builtin.html
--   [3] Delta Lake Documentation
--       https://docs.delta.io/latest/index.html

-- 添加列
ALTER TABLE users ADD COLUMN phone STRING;
ALTER TABLE users ADD COLUMN IF NOT EXISTS phone STRING;

-- 添加多列
ALTER TABLE users ADD COLUMNS (
    phone STRING COMMENT 'Phone number',
    city STRING DEFAULT 'unknown'
);

-- 删除列（Delta Lake，需要开启列映射）
-- 需要先设置: ALTER TABLE users SET TBLPROPERTIES ('delta.columnMapping.mode' = 'name')
ALTER TABLE users DROP COLUMN phone;
ALTER TABLE users DROP COLUMNS (phone, city);

-- 修改列类型（仅允许安全扩展）
-- 支持: INT -> BIGINT, FLOAT -> DOUBLE, DECIMAL 精度扩展
ALTER TABLE users ALTER COLUMN age TYPE BIGINT;

-- 修改列注释
ALTER TABLE users ALTER COLUMN email COMMENT 'User email address';

-- 修改列默认值
ALTER TABLE users ALTER COLUMN status SET DEFAULT 1;
ALTER TABLE users ALTER COLUMN status DROP DEFAULT;

-- 设置/取消 NOT NULL
ALTER TABLE users ALTER COLUMN email SET NOT NULL;
ALTER TABLE users ALTER COLUMN email DROP NOT NULL;

-- 重命名列（需要列映射模式）
ALTER TABLE users RENAME COLUMN email TO email_address;

-- 重命名表
ALTER TABLE users RENAME TO members;

-- 修改 Liquid Clustering 键
ALTER TABLE events CLUSTER BY (event_date, user_id);
ALTER TABLE events CLUSTER BY NONE;

-- 修改表属性
ALTER TABLE users SET TBLPROPERTIES (
    'delta.autoOptimize.optimizeWrite' = 'true',
    'delta.autoOptimize.autoCompact' = 'true'
);

-- 启用列映射（允许删除和重命名列）
ALTER TABLE users SET TBLPROPERTIES (
    'delta.columnMapping.mode' = 'name',
    'delta.minReaderVersion' = '2',
    'delta.minWriterVersion' = '5'
);

-- 启用变更数据捕获（CDC / Change Data Feed）
ALTER TABLE users SET TBLPROPERTIES (
    'delta.enableChangeDataFeed' = 'true'
);

-- 删除表属性
ALTER TABLE users UNSET TBLPROPERTIES ('delta.autoOptimize.optimizeWrite');

-- 修改表注释
ALTER TABLE users SET COMMENT = 'User information table';
COMMENT ON TABLE users IS 'User information table';

-- 添加约束
ALTER TABLE users ADD CONSTRAINT pk_users PRIMARY KEY (id);
ALTER TABLE users ADD CONSTRAINT uk_email UNIQUE (email);
ALTER TABLE orders ADD CONSTRAINT fk_orders_user
    FOREIGN KEY (user_id) REFERENCES users (id);
-- 注意: PK/FK/UNIQUE 约束是信息性的，不强制执行（用于查询优化）

-- 添加 CHECK 约束（强制执行！）
ALTER TABLE users ADD CONSTRAINT chk_age CHECK (age > 0 AND age < 200);
ALTER TABLE orders ADD CONSTRAINT chk_amount CHECK (amount >= 0);

-- 删除约束
ALTER TABLE users DROP CONSTRAINT pk_users;
ALTER TABLE users DROP CONSTRAINT chk_age;

-- 修改表所有者（Unity Catalog）
ALTER TABLE users SET OWNER TO `data_team`;

-- 添加/修改标签（Unity Catalog）
ALTER TABLE users SET TAGS ('env' = 'prod', 'team' = 'backend');
ALTER TABLE users ALTER COLUMN email SET TAGS ('pii' = 'true');

-- Schema Evolution（通过写入自动添加列）
-- 在写入时设置 mergeSchema 选项即可自动演进 schema

-- 注意：Delta Lake 支持较完整的 ALTER TABLE
-- 注意：列映射模式启用后支持删除和重命名列
-- 注意：CHECK 约束会被强制执行，PK/FK/UNIQUE 只是信息性的
-- 注意：Unity Catalog 提供标签和所有者管理
-- 注意：Schema Evolution 允许写入时自动添加新列
