-- SQL Server: Sequences & Auto-Increment
--
-- 参考资料:
--   [1] Microsoft Documentation - CREATE SEQUENCE
--       https://learn.microsoft.com/en-us/sql/t-sql/statements/create-sequence-transact-sql
--   [2] Microsoft Documentation - IDENTITY Property
--       https://learn.microsoft.com/en-us/sql/t-sql/statements/create-table-transact-sql-identity-property
--   [3] Microsoft Documentation - NEWID / NEWSEQUENTIALID
--       https://learn.microsoft.com/en-us/sql/t-sql/functions/newid-transact-sql

-- ============================================
-- SEQUENCE（SQL Server 2012+）
-- ============================================
CREATE SEQUENCE user_id_seq
    AS BIGINT
    START WITH 1
    INCREMENT BY 1
    MINVALUE 1
    MAXVALUE 9223372036854775807
    CACHE 50
    NO CYCLE;

-- 使用序列
INSERT INTO users (id, username) VALUES (NEXT VALUE FOR user_id_seq, 'alice');
SELECT NEXT VALUE FOR user_id_seq;

-- 在 DEFAULT 约束中使用
CREATE TABLE orders (
    id       BIGINT DEFAULT (NEXT VALUE FOR user_id_seq),
    amount   DECIMAL(10,2)
);

-- 序列范围（批量获取）
SELECT * FROM sys.sp_sequence_get_range(@sequence_name = N'user_id_seq', @range_size = 100);

-- 修改序列
ALTER SEQUENCE user_id_seq RESTART WITH 1000;
ALTER SEQUENCE user_id_seq INCREMENT BY 2;

-- 删除序列
DROP SEQUENCE user_id_seq;
DROP SEQUENCE IF EXISTS user_id_seq;          -- 2016+

-- ============================================
-- IDENTITY（传统自增方式）
-- ============================================
CREATE TABLE users (
    id       BIGINT IDENTITY(1, 1) NOT NULL, -- IDENTITY(seed, increment)
    username NVARCHAR(64) NOT NULL,
    email    NVARCHAR(255) NOT NULL,
    CONSTRAINT PK_users PRIMARY KEY (id)
);

-- 获取最后生成的 IDENTITY 值
SELECT SCOPE_IDENTITY();                     -- 当前作用域（推荐）
SELECT @@IDENTITY;                           -- 当前会话（包括触发器）
SELECT IDENT_CURRENT('users');               -- 指定表的最后值

-- SET IDENTITY_INSERT 允许手动指定
SET IDENTITY_INSERT users ON;
INSERT INTO users (id, username, email) VALUES (100, 'bob', 'bob@example.com');
SET IDENTITY_INSERT users OFF;

-- 重新播种 IDENTITY
DBCC CHECKIDENT ('users', RESEED, 1000);

-- ============================================
-- UUID 生成
-- ============================================
SELECT NEWID();                              -- 随机 UUID (v4)
-- 结果示例：'7F1B7E42-3A1C-4B5D-8F2E-9C0D1E2F3A4B'

-- NEWSEQUENTIALID()（只能用在 DEFAULT 约束中）
CREATE TABLE sessions (
    id         UNIQUEIDENTIFIER DEFAULT NEWSEQUENTIALID(),  -- 顺序 UUID
    user_id    BIGINT,
    created_at DATETIME2 DEFAULT SYSDATETIME()
);
-- NEWSEQUENTIALID() 生成顺序 UUID，索引友好

-- ============================================
-- 序列 vs 自增 权衡
-- ============================================
-- 1. IDENTITY：最简单，一张表一个，传统方式
-- 2. SEQUENCE（2012+）：灵活，可跨表共享，可在 DEFAULT 中使用
-- 3. NEWID()：全局唯一但随机（索引碎片）
-- 4. NEWSEQUENTIALID()：顺序 UUID，索引友好
-- 5. SEQUENCE 支持 CACHE 提升性能
-- 6. IDENTITY 不能跨表共享
-- 7. SCOPE_IDENTITY() 比 @@IDENTITY 更安全
