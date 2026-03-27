-- SQL Server: ALTER TABLE
--
-- 参考资料:
--   [1] SQL Server T-SQL - ALTER TABLE
--       https://learn.microsoft.com/en-us/sql/t-sql/statements/alter-table-transact-sql
--   [2] SQL Server T-SQL - Data Types
--       https://learn.microsoft.com/en-us/sql/t-sql/data-types/data-types-transact-sql

-- 添加列
ALTER TABLE users ADD phone NVARCHAR(20);
ALTER TABLE users ADD status INT NOT NULL DEFAULT 1;

-- 添加多列
ALTER TABLE users ADD
    city NVARCHAR(64),
    country NVARCHAR(64);

-- 修改列类型
ALTER TABLE users ALTER COLUMN phone NVARCHAR(32) NOT NULL;

-- 重命名列（使用系统存储过程）
EXEC sp_rename 'users.phone', 'mobile', 'COLUMN';

-- 删除列
ALTER TABLE users DROP COLUMN phone;
-- 如果有默认值约束，需要先删除约束
ALTER TABLE users DROP CONSTRAINT DF_users_status;
ALTER TABLE users DROP COLUMN status;

-- 2016+: IF EXISTS
ALTER TABLE users DROP COLUMN IF EXISTS phone, city;

-- 修改默认值（需要添加/删除约束）
ALTER TABLE users ADD CONSTRAINT DF_users_status DEFAULT 0 FOR status;
ALTER TABLE users DROP CONSTRAINT DF_users_status;

-- 重命名表
EXEC sp_rename 'users', 'members';

-- 注意：ALTER COLUMN 不支持同时修改多个属性
-- 需要多条语句分别修改类型、NULL 性、默认值
