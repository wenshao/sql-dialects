-- Redshift: ALTER TABLE
--
-- 参考资料:
--   [1] Redshift SQL Reference
--       https://docs.aws.amazon.com/redshift/latest/dg/cm_chap_SQLCommandRef.html
--   [2] Redshift SQL Functions
--       https://docs.aws.amazon.com/redshift/latest/dg/c_SQL_functions.html
--   [3] Redshift Data Types
--       https://docs.aws.amazon.com/redshift/latest/dg/c_Supported_data_types.html

-- 添加列
ALTER TABLE users ADD COLUMN phone VARCHAR(20);
ALTER TABLE users ADD COLUMN status SMALLINT DEFAULT 1;

-- 删除列
ALTER TABLE users DROP COLUMN phone;
ALTER TABLE users DROP COLUMN phone CASCADE;

-- 修改列类型（非常有限）
-- Redshift 仅支持扩大 VARCHAR 长度
ALTER TABLE users ALTER COLUMN bio TYPE VARCHAR(65535);
-- 其他类型变更需要通过 CTAS 重建表

-- 修改列默认值
ALTER TABLE users ALTER COLUMN status SET DEFAULT 0;
ALTER TABLE users ALTER COLUMN status DROP DEFAULT;

-- 修改列编码（压缩）
ALTER TABLE users ALTER COLUMN bio ENCODE ZSTD;
ALTER TABLE users ALTER COLUMN status ENCODE AZ64;

-- 重命名列
ALTER TABLE users RENAME COLUMN email TO email_address;

-- 重命名表
ALTER TABLE users RENAME TO members;

-- 添加约束（信息性，不强制执行）
ALTER TABLE users ADD CONSTRAINT pk_users PRIMARY KEY (id);
ALTER TABLE users ADD CONSTRAINT uk_email UNIQUE (email);
ALTER TABLE orders ADD CONSTRAINT fk_orders_user
    FOREIGN KEY (user_id) REFERENCES users (id);

-- 删除约束
ALTER TABLE users DROP CONSTRAINT pk_users;
ALTER TABLE users DROP CONSTRAINT uk_email;
ALTER TABLE orders DROP CONSTRAINT fk_orders_user;

-- 修改 DISTKEY
ALTER TABLE orders ALTER DISTKEY user_id;

-- 修改 SORTKEY
ALTER TABLE orders ALTER SORTKEY (order_date, user_id);
ALTER TABLE orders ALTER SORTKEY AUTO;
ALTER TABLE orders ALTER SORTKEY NONE;

-- 修改 DISTSTYLE
ALTER TABLE orders ALTER DISTSTYLE KEY DISTKEY (user_id);
ALTER TABLE orders ALTER DISTSTYLE EVEN;
ALTER TABLE orders ALTER DISTSTYLE ALL;
ALTER TABLE orders ALTER DISTSTYLE AUTO;

-- 修改编码（ENCODE AUTO）
ALTER TABLE orders ALTER ENCODE AUTO;

-- 追加行（从另一个表）
ALTER TABLE users_archive APPEND FROM users_staging;
-- 移动数据（源表被清空），比 INSERT INTO ... SELECT 更快

-- 修改表属性
ALTER TABLE users SET TABLE PROPERTIES ('auto_analyze' = 'true');

-- 修改表所有者
ALTER TABLE users OWNER TO new_owner;

-- 通过 CTAS 重建表（改变不能直接修改的属性）
CREATE TABLE users_new
DISTSTYLE KEY DISTKEY (username) SORTKEY (created_at) AS
SELECT * FROM users;
DROP TABLE users;
ALTER TABLE users_new RENAME TO users;

-- 注意：不支持在一条语句中添加多列
-- 注意：不支持 ADD COLUMN IF NOT EXISTS
-- 注意：不支持修改列为 NOT NULL / 取消 NOT NULL
-- 注意：类型修改仅支持扩大 VARCHAR 长度
-- 注意：约束（PK、UK、FK）都是信息性的，用于查询优化器
-- 注意：ALTER DISTKEY / SORTKEY 会触发后台数据重分布
