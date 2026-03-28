-- Snowflake: 约束（信息性约束设计）
--
-- 参考资料:
--   [1] Snowflake SQL Reference - Constraints
--       https://docs.snowflake.com/en/sql-reference/constraints-overview
--   [2] Snowflake SQL Reference - CREATE TABLE
--       https://docs.snowflake.com/en/sql-reference/sql/create-table
--   [3] Snowflake SQL Reference - Constraint Properties
--       https://docs.snowflake.com/en/sql-reference/constraints-properties

-- ============================================================
-- 1. 基本语法
-- ============================================================

CREATE TABLE users (
    id       NUMBER NOT NULL,                            -- NOT NULL 是唯一强制执行的约束
    username VARCHAR(64) NOT NULL,
    email    VARCHAR(255),
    dept_id  NUMBER,
    CONSTRAINT pk_users PRIMARY KEY (id),                -- 信息性，不执行
    CONSTRAINT uk_username UNIQUE (username),             -- 信息性，不执行
    CONSTRAINT uk_email UNIQUE (email)                   -- 信息性，不执行
);

CREATE TABLE orders (
    id       NUMBER NOT NULL,
    user_id  NUMBER,
    amount   NUMBER(10,2),
    CONSTRAINT pk_orders PRIMARY KEY (id),
    CONSTRAINT fk_user FOREIGN KEY (user_id) REFERENCES users(id)  -- 信息性，不执行
);

-- ============================================================
-- 2. 核心设计分析: 约束不执行 (NOT ENFORCED)
-- ============================================================

-- 2.1 什么是信息性约束
-- Snowflake 的 PRIMARY KEY / UNIQUE / FOREIGN KEY 均为 NOT ENFORCED:
--   - 语法被接受，元数据被记录到 INFORMATION_SCHEMA
--   - 不创建任何物理结构（无索引、无哈希表）
--   - INSERT/UPDATE 时不做任何校验
--   - 违反约束的数据可以成功写入
--
-- 例如:
-- INSERT INTO users VALUES (1, 'alice', 'a@e.com', NULL);
-- INSERT INTO users VALUES (1, 'alice', 'a@e.com', NULL);  -- 重复 PK! 成功写入!

-- 2.2 为什么选择不执行
-- 在分布式列存架构中强制约束的代价极高:
--
-- (a) 唯一性校验: INSERT 一行需要查找全表是否已存在相同 PK 值
--     → 分布式系统中需要跨节点协调 → 高延迟
--     → COPY INTO 批量加载 TB 级数据时逐行校验不可接受
--     → 微分区是不可变的，无法像 B-tree 一样高效查重
--
-- (b) 外键校验: 每次 INSERT 子表需要查询父表是否存在对应行
--     → 跨表查询 → 分布式环境下更慢
--     → DELETE 父表需要检查所有子表 → 级联操作极复杂
--
-- (c) 锁机制: 强制约束需要行级或范围锁防止并发违反
--     → Snowflake 只有 READ COMMITTED 隔离级别，无行级锁
--     → 多 Warehouse 并发写入时锁协调成本极高
--
-- 设计 trade-off:
--   Snowflake 选择了高吞吐写入 > 数据完整性保证
--   数据质量由 ETL 管道或应用层保证，而非数据库层

-- 2.3 信息性约束的实际价值
-- (a) 查询优化器利用约束信息:
--     - PK/UNIQUE: 优化器知道某列唯一，可做 GROUP BY 消除、子查询优化
--     - FK: 优化器可以做 JOIN 消除（如果 SELECT 只引用主表列）
-- (b) BI 工具读取 INFORMATION_SCHEMA 推断表关系:
--     - Tableau/Looker/Power BI 自动发现外键关系
-- (c) 文档和沟通: 约束表达数据模型的设计意图

-- ============================================================
-- 3. NOT NULL: 唯一强制执行的约束
-- ============================================================

-- NOT NULL 是 Snowflake 中唯一实际执行的约束:
-- INSERT INTO users (id, username) VALUES (NULL, 'alice');  -- ERROR!
--
-- 设计理由: NOT NULL 校验成本极低（逐行检查，无需全局协调）
-- 对比 PK/UNIQUE 需要全局查重，NOT NULL 只需看当前行
--
-- 对引擎开发者的启示:
--   约束执行成本的差异解释了 Snowflake 的选择:
--   NOT NULL  → O(1) 逐行检查 → 执行
--   UNIQUE    → O(N) 全局查重（或需索引）→ 不执行
--   FK        → 跨表查询 + 级联操作 → 不执行

ALTER TABLE users ALTER COLUMN email SET NOT NULL;
ALTER TABLE users ALTER COLUMN email DROP NOT NULL;

-- ============================================================
-- 4. 约束管理操作
-- ============================================================

-- 添加约束
ALTER TABLE orders ADD CONSTRAINT fk_user
    FOREIGN KEY (user_id) REFERENCES users(id);

-- 删除约束
ALTER TABLE orders DROP CONSTRAINT fk_user;
ALTER TABLE users DROP PRIMARY KEY;
ALTER TABLE users DROP UNIQUE (email);

-- 重命名约束
ALTER TABLE users RENAME CONSTRAINT pk_users TO pk_users_v2;

-- 查看约束
SHOW PRIMARY KEYS IN TABLE users;
SHOW UNIQUE KEYS IN TABLE users;
SHOW IMPORTED KEYS IN TABLE orders;  -- 外键
SHOW EXPORTED KEYS IN TABLE users;   -- 被引用的外键

-- 从 INFORMATION_SCHEMA 查看:
SELECT constraint_name, constraint_type, table_name, enforced
FROM information_schema.table_constraints
WHERE table_schema = 'PUBLIC' AND table_name = 'USERS';
-- enforced 列始终为 'NO'（除了 NOT NULL）

-- ============================================================
-- 5. CHECK 约束
-- ============================================================

-- Snowflake 接受 CHECK 语法但不执行（与 PK/FK/UNIQUE 一致）:
CREATE TABLE products (
    id    NUMBER NOT NULL,
    price NUMBER(10,2),
    qty   NUMBER,
    CONSTRAINT chk_price CHECK (price > 0),      -- 不执行
    CONSTRAINT chk_qty CHECK (qty >= 0)           -- 不执行
);
-- INSERT INTO products VALUES (1, -10, -5);  -- 成功! CHECK 不执行!

-- 对比:
--   MySQL 8.0.16+: CHECK 强制执行（之前静默忽略，是公认的设计失误）
--   PostgreSQL:    CHECK 从第一个版本就强制执行
--   Oracle:        CHECK 强制执行
--   BigQuery:      不支持 CHECK 语法
--   Redshift:      不支持 CHECK
--   Databricks:    Delta Lake CHECK 约束强制执行（少数执行约束的分析引擎）

-- ============================================================
-- 6. 数据质量保证的替代方案
-- ============================================================

-- 6.1 SQL 查询验证（手动或自动化）
-- SELECT COUNT(*) FROM users GROUP BY id HAVING COUNT(*) > 1;      -- 检查 PK 唯一性
-- SELECT COUNT(*) FROM orders WHERE user_id NOT IN (SELECT id FROM users); -- 检查 FK

-- 6.2 dbt 测试框架（业界最佳实践）
-- schema.yml:
--   columns:
--     - name: id
--       tests: [unique, not_null]

-- 6.3 COPY INTO 验证
-- SELECT * FROM TABLE(VALIDATE(users, JOB_ID => '_last'));

-- 6.4 数据掩码策略（替代列级安全约束）
CREATE MASKING POLICY email_mask AS (val STRING) RETURNS STRING ->
    CASE WHEN CURRENT_ROLE() IN ('ADMIN') THEN val
    ELSE REGEXP_REPLACE(val, '.+@', '***@')
    END;
ALTER TABLE users ALTER COLUMN email SET MASKING POLICY email_mask;

-- ============================================================
-- 7. 横向对比: 约束执行矩阵
-- ============================================================
-- 约束        | Snowflake | BigQuery | Redshift | Databricks | MySQL | PostgreSQL
-- NOT NULL    | 执行      | 执行     | 执行     | 执行       | 执行  | 执行
-- PRIMARY KEY | 不执行    | 不执行   | 不执行   | 不支持     | 执行  | 执行
-- UNIQUE      | 不执行    | 不执行   | 不执行   | 不支持     | 执行  | 执行
-- FOREIGN KEY | 不执行    | 不执行   | 不执行   | 不支持     | 执行  | 执行
-- CHECK       | 不执行    | 不支持   | 不支持   | 执行       | 执行  | 执行
-- DEFAULT     | 执行      | 执行     | 执行     | 执行       | 执行  | 执行
--
-- 规律: 云数仓 (Snowflake/BigQuery/Redshift) 普遍不执行约束
--       传统 OLTP (MySQL/PostgreSQL/Oracle) 强制执行约束
--
-- 对引擎开发者的启示:
--   约束执行是 OLTP vs OLAP 的核心设计分歧之一。
--   OLAP 引擎不执行约束可以大幅提升写入吞吐。
--   OLTP 或 HTAP 引擎必须执行约束。
--   Snowflake Hybrid Tables (2024) 开始支持约束执行，向 HTAP 演进。
--   最差的设计: MySQL 8.0.16 之前接受 CHECK 但静默忽略。
--   正确的做法: 要么执行，要么明确标注 NOT ENFORCED，要么不接受语法。
