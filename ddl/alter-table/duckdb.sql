-- DuckDB: ALTER TABLE
-- DuckDB is an in-process analytical database (OLAP).
--
-- 参考资料:
--   [1] DuckDB Documentation - ALTER TABLE
--       https://duckdb.org/docs/sql/statements/alter_table
--   [2] DuckDB Documentation - Data Types
--       https://duckdb.org/docs/sql/data_types/overview
--   [3] DuckDB Documentation - Nested Types
--       https://duckdb.org/docs/sql/data_types/overview#nested--composite-types
--   [4] DuckDB Documentation - Structs
--       https://duckdb.org/docs/sql/data_types/struct
--   [5] DuckDB v1.0 Release Notes
--       https://duckdb.org/2024/06/03/announcing-duckdb-100

-- ============================================================
-- 1. 基本列操作
-- ============================================================

-- 添加列
ALTER TABLE users ADD COLUMN phone VARCHAR;
ALTER TABLE users ADD COLUMN IF NOT EXISTS phone VARCHAR;

-- 添加列带默认值和约束
ALTER TABLE users ADD COLUMN status INTEGER NOT NULL DEFAULT 1;

-- 删除列（v0.8+）
ALTER TABLE users DROP COLUMN phone;
ALTER TABLE users DROP COLUMN IF EXISTS phone;

-- 重命名列
ALTER TABLE users RENAME COLUMN phone TO mobile;

-- 重命名表
ALTER TABLE users RENAME TO members;

-- ============================================================
-- 2. 列类型修改
-- ============================================================

-- 修改列类型（v0.8+）
ALTER TABLE users ALTER COLUMN age SET DATA TYPE BIGINT;
ALTER TABLE users ALTER COLUMN age TYPE BIGINT;  -- 短语法

-- 设置 / 删除默认值
ALTER TABLE users ALTER COLUMN status SET DEFAULT 0;
ALTER TABLE users ALTER COLUMN status DROP DEFAULT;

-- 设置 / 删除 NOT NULL（v0.8+）
ALTER TABLE users ALTER COLUMN email SET NOT NULL;
ALTER TABLE users ALTER COLUMN email DROP NOT NULL;

-- 类型转换限制:
--   安全转换: INT → BIGINT, VARCHAR → TEXT（宽化）
--   不安全转换: VARCHAR → INT（需确保数据全部可转换）
--   DuckDB 不支持 ALTER TABLE ... USING (表达式) 进行自定义转换
--   替代方案: ADD COLUMN + UPDATE + DROP COLUMN

-- ============================================================
-- 3. 嵌套类型操作（DuckDB 特色）
-- ============================================================
-- DuckDB 支持 STRUCT / MAP / LIST 三种嵌套类型，
-- 这些类型的 ALTER 操作是 DuckDB 的独有能力。

-- 3.1 STRUCT 类型的列操作
-- 添加 STRUCT 列
ALTER TABLE users ADD COLUMN address STRUCT(
    street VARCHAR,
    city   VARCHAR,
    zip    VARCHAR
);

-- 查询 STRUCT 字段
SELECT address.city FROM users;

-- 修改 STRUCT 内部字段类型（需要重建列）
-- DuckDB 不支持直接 ALTER STRUCT 内部字段
-- 替代方案: 提取 → 修改 → 重建
-- Step 1: 添加新 STRUCT 列
ALTER TABLE users ADD COLUMN address_v2 STRUCT(
    street VARCHAR,
    city   VARCHAR,
    zip    VARCHAR,
    country VARCHAR DEFAULT 'CN'
);
-- Step 2: 迁移数据
UPDATE users SET address_v2 = struct_pack(
    street  := address.street,
    city    := address.city,
    zip     := address.zip,
    country := 'CN'
);
-- Step 3: 替换旧列
ALTER TABLE users DROP COLUMN address;
ALTER TABLE users RENAME COLUMN address_v2 TO address;

-- 3.2 MAP 类型的列操作
-- 添加 MAP 列
ALTER TABLE users ADD COLUMN meta MAP(VARCHAR, VARCHAR);

-- MAP 操作示例
UPDATE users SET meta = map_from_entries([('key1', 'value1'), ('key2', 'value2')]);
SELECT meta['key1'] FROM users;

-- 修改 MAP 的键/值类型需要重建列（同 STRUCT）

-- 3.3 LIST (ARRAY) 类型的列操作
-- 添加 LIST 列
ALTER TABLE users ADD COLUMN tags VARCHAR[];
ALTER TABLE users ADD COLUMN scores INTEGER[];

-- LIST 操作示例
UPDATE users SET tags = ['duck', 'goose', 'swan'];
SELECT tags[1] FROM users;  -- DuckDB LIST 是 1-indexed!
SELECT list_aggregate(scores, 'sum') FROM users;
SELECT unnest(tags) FROM users;  -- 展开为多行

-- 修改 LIST 的元素类型
ALTER TABLE users ALTER COLUMN scores SET DATA TYPE BIGINT[];  -- VARCHAR[] → BIGINT[] 需兼容

-- 3.4 复杂嵌套组合
-- 多层嵌套: LIST of STRUCT
ALTER TABLE orders ADD COLUMN items STRUCT(
    product_id BIGINT,
    name       VARCHAR,
    tags       VARCHAR[]
)[];

-- 查询嵌套数据
SELECT items FROM orders;
SELECT unnest(items) AS item FROM orders;  -- 展开 LIST
SELECT item.name, unnest(item.tags) AS tag FROM orders, unnest(items) AS item;

-- ============================================================
-- 4. 添加/删除列约束（v1.0+）
-- ============================================================

-- 添加主键（DuckDB 对主键支持有限，主要用于约束）
ALTER TABLE users ADD PRIMARY KEY (id);

-- 添加唯一约束
ALTER TABLE users ADD CONSTRAINT uk_email UNIQUE (email);

-- 删除约束
ALTER TABLE users DROP CONSTRAINT uk_email;

-- ============================================================
-- 5. DuckDB ALTER TABLE 的限制
-- ============================================================
-- 不支持 AFTER / FIRST 子句（列总是添加到末尾）
-- 不支持多操作合并（必须分开多个 ALTER TABLE 语句）
-- 不支持 ALTER TABLE ... SET SCHEMA
-- 不支持 ALTER TABLE ... ADD FOREIGN KEY
-- 不支持 USING 子句进行自定义类型转换
-- STRUCT/MAP 内部字段不能直接 ALTER（需要重建列）
-- 列顺序不可修改（分析型数据库不依赖列顺序）

-- ============================================================
-- 6. 设计分析（对 SQL 引擎开发者）
-- ============================================================
-- DuckDB 的 ALTER TABLE 设计哲学:
--   "分析型数据库的 Schema 变更应该是即时（instant）的"
--
-- 6.1 为什么 DuckDB 的 ALTER 几乎都是即时操作:
--   DuckDB 使用列式存储，每列独立存储文件
--   ADD COLUMN: 只修改元数据（catalog），不重写数据文件
--   DROP COLUMN: 标记删除，不立即回收空间（lazy 方式）
--   RENAME: 只修改元数据
--   CHANGE TYPE: 某些情况需要重写，但 DuckDB 尽量延迟
--   对比 PostgreSQL: ADD COLUMN + 非 NULL DEFAULT 在 11 之前需要重写全表
--   对比 MySQL:      ALGORITHM=INSTANT 在 8.0.12+ 支持部分操作
--
-- 6.2 嵌套类型的 ALTER 挑战:
--   STRUCT 是固定 schema 的嵌套类型（类似轻量级表），修改内部字段需要重写
--   MAP 是动态 schema 的键值对，不需要 ALTER 内部结构
--   LIST 是有序集合，元素类型固定，修改元素类型需要重写
--   列式存储下嵌套类型的编码（Parquet 方式）使部分更新非常困难
--
-- 6.3 跨方言对比:
--   DuckDB:   支持 STRUCT/MAP/LIST，ALTER 即时，无 AFTER/FIRST
--   SQLite:   不支持 ALTER 的灵活性（只支持 RENAME TABLE / ADD COLUMN）
--   ClickHouse: ALTER 也是即时（元数据操作），支持 NESTED 类型
--   BigQuery: 支持 STRUCT/ARRAY，ALTER 支持 ADD/DROP 列
--   Snowflake: 支持 VARIANT (半结构化)，ALTER 支持 ADD/DROP/RENAME 列
--   PostgreSQL: 支持 JSONB/JSON，ALTER 支持丰富但嵌套类型修改受限
--
-- 6.4 版本演进:
--   DuckDB 0.3: 基础 ALTER（ADD/DROP/RENAME 列）
--   DuckDB 0.8: 支持 SET DATA TYPE, SET/DROP NOT NULL, DROP COLUMN 改进
--   DuckDB 0.10: IF NOT EXISTS / IF EXISTS 支持
--   DuckDB 1.0: 稳定版，ADD CONSTRAINT / DROP CONSTRAINT 支持
--   DuckDB 1.1+: 持续改进嵌套类型和类型转换能力

-- ============================================================
-- 7. 最佳实践
-- ============================================================
-- 1. 利用 IF NOT EXISTS / IF EXISTS 避免幂等性问题
-- 2. 修改 STRUCT 内部字段用 "添加新列 → 数据迁移 → 删除旧列" 模式
-- 3. 对于频繁变化的嵌套数据，考虑用 MAP (VARCHAR, VARCHAR) 代替 STRUCT
-- 4. ALTER 操作在 DuckDB 中几乎无性能代价，可以放心使用
-- 5. 数据管道中使用 ALTER + UPDATE 组合替代重建整表
