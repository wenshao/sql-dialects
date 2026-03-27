-- SQL Server: 约束
--
-- 参考资料:
--   [1] SQL Server T-SQL - Table Constraints
--       https://learn.microsoft.com/en-us/sql/t-sql/statements/alter-table-table-constraint-transact-sql
--   [2] SQL Server T-SQL - CREATE TABLE
--       https://learn.microsoft.com/en-us/sql/t-sql/statements/create-table-transact-sql

-- PRIMARY KEY
ALTER TABLE users ADD CONSTRAINT pk_users PRIMARY KEY (id);
-- 聚集 vs 非聚集主键
ALTER TABLE users ADD CONSTRAINT pk_users PRIMARY KEY NONCLUSTERED (id);

-- UNIQUE
ALTER TABLE users ADD CONSTRAINT uk_email UNIQUE (email);

-- FOREIGN KEY
ALTER TABLE orders ADD CONSTRAINT fk_orders_user
    FOREIGN KEY (user_id) REFERENCES users (id)
    ON DELETE CASCADE
    ON UPDATE CASCADE;
-- 动作: CASCADE / SET NULL / SET DEFAULT / NO ACTION

-- NOT NULL
ALTER TABLE users ALTER COLUMN email NVARCHAR(255) NOT NULL;

-- DEFAULT（必须作为命名约束）
ALTER TABLE users ADD CONSTRAINT df_status DEFAULT 1 FOR status;
ALTER TABLE users DROP CONSTRAINT df_status;

-- CHECK
ALTER TABLE users ADD CONSTRAINT chk_age CHECK (age >= 0 AND age <= 200);
ALTER TABLE users ADD CONSTRAINT chk_dates CHECK (end_date > start_date);

-- WITH NOCHECK（添加约束时不校验已有数据）
ALTER TABLE users WITH NOCHECK ADD CONSTRAINT chk_age CHECK (age >= 0);
ALTER TABLE users WITH CHECK CHECK CONSTRAINT chk_age;  -- 之后再校验

-- 启用 / 禁用约束
ALTER TABLE users NOCHECK CONSTRAINT chk_age;
ALTER TABLE users CHECK CONSTRAINT chk_age;
ALTER TABLE users NOCHECK CONSTRAINT ALL;  -- 禁用所有

-- 删除约束
ALTER TABLE users DROP CONSTRAINT uk_email;
-- 2016+:
ALTER TABLE users DROP CONSTRAINT IF EXISTS uk_email;

-- 查看约束
SELECT * FROM sys.check_constraints WHERE parent_object_id = OBJECT_ID('users');
SELECT * FROM sys.foreign_keys WHERE parent_object_id = OBJECT_ID('orders');
SELECT * FROM sys.key_constraints WHERE parent_object_id = OBJECT_ID('users');
EXEC sp_helpconstraint 'users';
