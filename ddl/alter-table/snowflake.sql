-- Snowflake: ALTER TABLE
--
-- 参考资料:
--   [1] Snowflake SQL Reference - ALTER TABLE
--       https://docs.snowflake.com/en/sql-reference/sql/alter-table
--   [2] Snowflake SQL Reference - ALTER COLUMN
--       https://docs.snowflake.com/en/sql-reference/sql/alter-table-column

-- ============================================================
-- 1. 基本语法
-- ============================================================

-- 添加列
ALTER TABLE users ADD COLUMN phone VARCHAR(20);
ALTER TABLE users ADD COLUMN metadata VARIANT;

-- 删除列
ALTER TABLE users DROP COLUMN phone;

-- 重命名列
ALTER TABLE users RENAME COLUMN bio TO biography;

-- 修改列类型（仅支持扩大精度，不支持缩小或类型变更）
ALTER TABLE users ALTER COLUMN username SET DATA TYPE VARCHAR(128);
-- NUMBER(10,2) -> NUMBER(20,2) 可以，NUMBER(20,2) -> NUMBER(10,2) 不行
-- VARCHAR -> NUMBER 不支持（需要 CTAS 重建）

-- 修改默认值
ALTER TABLE users ALTER COLUMN balance SET DEFAULT 100.00;
ALTER TABLE users ALTER COLUMN balance DROP DEFAULT;

-- 设置/取消 NOT NULL
ALTER TABLE users ALTER COLUMN age SET NOT NULL;
ALTER TABLE users ALTER COLUMN age DROP NOT NULL;

-- 重命名表
ALTER TABLE users RENAME TO users_v2;

-- ============================================================
-- 2. 语法设计分析（对 SQL 引擎开发者）
-- ============================================================

-- 2.1 元数据操作 vs 数据操作: Snowflake 的核心设计优势
-- Snowflake 的大部分 ALTER TABLE 操作是纯元数据操作（metadata-only），
-- 不需要重写数据文件。这是不可变微分区架构的天然优势:
--
-- 纯元数据操作（瞬时完成）:
--   ADD COLUMN          → 新增列的元数据条目，已有微分区中该列为 NULL
--   DROP COLUMN         → 标记列为删除，微分区中的数据延迟清理
--   RENAME COLUMN       → 仅修改元数据映射
--   SET/DROP DEFAULT    → 仅修改元数据
--   SET/DROP NOT NULL   → 仅修改元数据（不校验已有数据！）
--   ADD/DROP CONSTRAINT → 纯元数据（约束本身就不执行）
--
-- 需要数据操作的场景:
--   CLUSTER BY (新增/修改) → 后台异步重新聚簇
--   数据类型缩小            → 不支持（需要 CTAS 重建）
--
-- 对比:
--   MySQL:      ADD COLUMN 需 ALGORITHM=INSTANT(8.0.12+仅末尾)/INPLACE/COPY
--               修改类型 99% 情况需要全表重写
--   PostgreSQL: ADD COLUMN + DEFAULT 在 11+ 是即时的（之前需要重写）
--               修改类型通常需要 REWRITE（除非类型兼容）
--   Oracle:     ADD COLUMN 即时，MODIFY 需根据情况判断
--   BigQuery:   ADD COLUMN 即时（与 Snowflake 一致），不支持 DROP COLUMN（只能隐藏）
--   Redshift:   ADD COLUMN 即时，但修改/删除需要重建表
--   Databricks: ALTER TABLE ADD/DROP COLUMN 即时（Delta Lake 事务日志）
--
-- 对引擎开发者的启示:
--   不可变存储 + 元数据层的架构天然支持无锁 DDL。传统的可变存储引擎（InnoDB）
--   需要复杂的 Online DDL 机制（INSTANT/INPLACE/COPY）来模拟类似效果。
--   如果从头设计引擎，不可变文件 + 事务日志的架构（如 Delta Lake/Iceberg）
--   可以大幅简化 DDL 实现。

-- 2.2 SET NOT NULL 不校验已有数据
-- Snowflake 的 ALTER COLUMN SET NOT NULL 不会扫描已有数据来验证是否有 NULL。
-- 这与约束不执行的哲学一致: 约束是声明意图，不是运行时保证。
-- 如果列中已有 NULL 值，SET NOT NULL 后:
--   - 新 INSERT 也不校验（约束不执行）
--   - 查询不受影响
--   - 优化器可能利用这个信息做优化（即使信息不准确）
--
-- 对比:
--   PostgreSQL: SET NOT NULL 会扫描全表验证，有 NULL 则报错
--   MySQL:      MODIFY COLUMN ... NOT NULL 也会验证
--   Oracle:     MODIFY ... NOT NULL 带 NOVALIDATE 可以跳过验证
--
-- 对引擎开发者的启示:
--   分析型引擎中约束可作为"建议"而非"保证"，但需要在文档中明确标注。
--   PostgreSQL 的 NOT VALID 约束是一个优雅的折中: 新数据必须满足，旧数据跳过。

-- ============================================================
-- 3. 约束管理
-- ============================================================
ALTER TABLE orders ADD CONSTRAINT pk_orders PRIMARY KEY (id);
ALTER TABLE orders ADD CONSTRAINT fk_user
    FOREIGN KEY (user_id) REFERENCES users(id);
ALTER TABLE orders DROP CONSTRAINT pk_orders;

-- 所有约束均为信息性（NOT ENFORCED），见 constraints/snowflake.sql

-- ============================================================
-- 4. 聚簇键管理
-- ============================================================
ALTER TABLE orders CLUSTER BY (order_date, user_id);
ALTER TABLE orders DROP CLUSTERING KEY;

-- 控制自动聚簇
ALTER TABLE orders SUSPEND RECLUSTER;
ALTER TABLE orders RESUME RECLUSTER;

-- 聚簇键修改后，Snowflake 后台自动重新组织数据（异步，按 credit 计费）
-- 对比 Redshift: ALTER TABLE ... ALTER SORTKEY 后需手动 VACUUM SORT

-- ============================================================
-- 5. Time Travel 与存储属性
-- ============================================================
ALTER TABLE users SET DATA_RETENTION_TIME_IN_DAYS = 90;
ALTER TABLE users SET DATA_RETENTION_TIME_IN_DAYS = 0;  -- 关闭 Time Travel

-- 启用变更追踪（Stream 所需）
ALTER TABLE users SET CHANGE_TRACKING = TRUE;

-- ============================================================
-- 6. 搜索优化
-- ============================================================
ALTER TABLE users ADD SEARCH OPTIMIZATION ON EQUALITY(email);
ALTER TABLE users ADD SEARCH OPTIMIZATION ON SUBSTRING(username);
ALTER TABLE users ADD SEARCH OPTIMIZATION ON GEO(location);
ALTER TABLE users DROP SEARCH OPTIMIZATION ON EQUALITY(email);
-- Search Optimization Service (Enterprise+) 为特定列创建后台搜索结构
-- 这是 Snowflake 对"无索引"设计的补充，但由系统管理而非用户创建

-- ============================================================
-- 7. 标签与注释
-- ============================================================
ALTER TABLE users SET COMMENT = 'Core user information table';
ALTER TABLE users SET TAG cost_center = 'engineering';
ALTER TABLE users ALTER COLUMN email SET COMMENT = 'User primary email';
ALTER TABLE users ALTER COLUMN email SET MASKING POLICY email_mask;
-- 列级 masking policy 是 Snowflake 数据治理的核心能力
-- 对比: 传统数据库通过视图实现类似效果，Snowflake 在存储层强制执行

-- ============================================================
-- 8. 交换分区 (SWAP WITH)
-- ============================================================
ALTER TABLE users SWAP WITH users_staging;
-- 原子交换两个表的内容（元数据交换，瞬时完成）
-- 常用于 ETL: 先写入 staging 表，验证后与生产表交换
-- 对比:
--   Oracle:     ALTER TABLE ... EXCHANGE PARTITION
--   MySQL:      无原生支持（需要 RENAME TABLE 三步交换）
--   PostgreSQL: 无原生支持
--   BigQuery:   无原生支持

-- ============================================================
-- 9. 行访问策略
-- ============================================================
ALTER TABLE users ADD ROW ACCESS POLICY region_policy ON (region);
ALTER TABLE users DROP ROW ACCESS POLICY region_policy;

-- ============================================================
-- 10. DDL 事务性
-- ============================================================
-- Snowflake DDL 是原子的（单个 DDL 语句要么全成功要么全失败）
-- 但 DDL 自动提交（不能在事务中回滚 DDL）
--
-- 对比:
--   PostgreSQL: DDL 是事务性的，可以 BEGIN; ALTER TABLE ...; ROLLBACK;
--   MySQL:      DDL 隐式提交（同 Snowflake）
--   Oracle:     DDL 隐式提交（同 Snowflake）
--   SQL Server: DDL 是事务性的（同 PostgreSQL）

-- ============================================================
-- 横向对比: ALTER TABLE 能力矩阵
-- ============================================================
-- 操作               | Snowflake   | BigQuery    | Redshift    | Databricks
-- ADD COLUMN         | 即时(元数据) | 即时(元数据) | 即时        | 即时(Delta)
-- DROP COLUMN        | 即时(元数据) | 不支持(隐藏) | 需重建      | 即时(Delta)
-- RENAME COLUMN      | 即时(元数据) | 不支持       | 不支持      | 即时(Delta)
-- 修改类型(扩大)     | 即时(元数据) | 不支持       | 不支持      | 不支持
-- 修改类型(缩小/变更)| 不支持       | 不支持       | 不支持      | 不支持
-- ADD CONSTRAINT     | 元数据(不执行)| 元数据      | 元数据      | CHECK only
-- CLUSTER BY         | 异步重聚簇   | 即时(元数据) | 需VACUUM    | 需OPTIMIZE
--
-- 结论: Snowflake 和 BigQuery 的 ALTER TABLE 体验最好（几乎所有操作即时完成），
-- 这得益于不可变存储 + 元数据分离的架构设计。
