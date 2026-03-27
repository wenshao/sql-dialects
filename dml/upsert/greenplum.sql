-- Greenplum: UPSERT
--
-- 参考资料:
--   [1] Greenplum SQL Reference
--       https://docs.vmware.com/en/VMware-Greenplum/7/greenplum-database/ref_guide-sql_commands-sql_ref.html
--   [2] Greenplum Admin Guide
--       https://docs.vmware.com/en/VMware-Greenplum/7/greenplum-database/admin_guide-intro-about_greenplum.html

-- ON CONFLICT（PostgreSQL 9.5+ 兼容）
INSERT INTO users (id, username, email)
VALUES (1, 'alice', 'alice@example.com')
ON CONFLICT (id) DO NOTHING;

-- ON CONFLICT + DO UPDATE
INSERT INTO users (id, username, email, age)
VALUES (1, 'alice', 'new@example.com', 26)
ON CONFLICT (id) DO UPDATE SET
    email = EXCLUDED.email,
    age = EXCLUDED.age,
    updated_at = CURRENT_TIMESTAMP;

-- 批量 UPSERT
INSERT INTO users (id, username, email, age) VALUES
    (1, 'alice', 'alice_new@example.com', 26),
    (2, 'bob', 'bob_new@example.com', 31),
    (3, 'charlie', 'charlie@example.com', 35)
ON CONFLICT (id) DO UPDATE SET
    email = EXCLUDED.email,
    age = EXCLUDED.age;

-- ON CONFLICT 指定约束名
INSERT INTO users (id, username, email)
VALUES (1, 'alice', 'new@example.com')
ON CONFLICT ON CONSTRAINT users_pkey DO UPDATE SET
    email = EXCLUDED.email;

-- 条件 UPSERT（WHERE 子句）
INSERT INTO users (id, username, email, age)
VALUES (1, 'alice', 'new@example.com', 26)
ON CONFLICT (id) DO UPDATE SET
    email = EXCLUDED.email
WHERE users.updated_at < CURRENT_TIMESTAMP;

-- CTE + UPSERT
WITH new_data AS (
    SELECT id, username, email, age FROM staging_users
)
INSERT INTO users (id, username, email, age)
SELECT * FROM new_data
ON CONFLICT (id) DO UPDATE SET
    email = EXCLUDED.email,
    age = EXCLUDED.age;

-- MERGE（SQL 标准，Greenplum 7+）
-- MERGE INTO users t
-- USING staging_users s ON t.id = s.id
-- WHEN MATCHED THEN UPDATE SET
--     username = s.username, email = s.email
-- WHEN NOT MATCHED THEN INSERT (id, username, email)
--     VALUES (s.id, s.username, s.email);

-- 替代方案：DELETE + INSERT（老版本兼容）
BEGIN;
DELETE FROM users WHERE id IN (SELECT id FROM staging_users);
INSERT INTO users SELECT * FROM staging_users;
COMMIT;

-- 注意：ON CONFLICT 要求目标列有 UNIQUE 或 PRIMARY KEY 约束
-- 注意：UNIQUE 约束必须包含分布键
-- 注意：EXCLUDED 引用被拒绝的行
-- 注意：Greenplum 兼容 PostgreSQL UPSERT 语法
