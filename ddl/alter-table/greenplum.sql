-- Greenplum: ALTER TABLE
--
-- 参考资料:
--   [1] Greenplum SQL Reference
--       https://docs.vmware.com/en/VMware-Greenplum/7/greenplum-database/ref_guide-sql_commands-sql_ref.html
--   [2] Greenplum Admin Guide
--       https://docs.vmware.com/en/VMware-Greenplum/7/greenplum-database/admin_guide-intro-about_greenplum.html

-- 添加列
ALTER TABLE users ADD COLUMN phone VARCHAR(20);
ALTER TABLE users ADD COLUMN phone VARCHAR(20) DEFAULT 'N/A';

-- 删除列
ALTER TABLE users DROP COLUMN phone;
ALTER TABLE users DROP COLUMN IF EXISTS phone;

-- 修改列类型
ALTER TABLE users ALTER COLUMN phone TYPE VARCHAR(32);
ALTER TABLE users ALTER COLUMN age TYPE BIGINT;

-- 重命名列
ALTER TABLE users RENAME COLUMN phone TO mobile;

-- 设置/删除默认值
ALTER TABLE users ALTER COLUMN status SET DEFAULT 1;
ALTER TABLE users ALTER COLUMN status DROP DEFAULT;

-- 设置/删除 NOT NULL
ALTER TABLE users ALTER COLUMN email SET NOT NULL;
ALTER TABLE users ALTER COLUMN email DROP NOT NULL;

-- 重命名表
ALTER TABLE users RENAME TO members;

-- 添加/删除约束
ALTER TABLE users ADD CONSTRAINT uq_email UNIQUE (email, id);  -- 必须包含分布键
ALTER TABLE users DROP CONSTRAINT uq_email;
ALTER TABLE users ADD CONSTRAINT chk_age CHECK (age >= 0);
ALTER TABLE orders ADD CONSTRAINT fk_user FOREIGN KEY (user_id) REFERENCES users(id);

-- 分区操作
ALTER TABLE orders ADD PARTITION p2024_04
    START ('2024-04-01') END ('2024-05-01');
ALTER TABLE orders DROP PARTITION p2024_01;

-- 拆分分区
ALTER TABLE orders SPLIT PARTITION p2024_01 AT ('2024-01-15')
    INTO (PARTITION p2024_01a, PARTITION p2024_01b);

-- 交换分区
ALTER TABLE orders EXCHANGE PARTITION p2024_01 WITH TABLE orders_jan;

-- 截断分区
ALTER TABLE orders TRUNCATE PARTITION p2024_01;

-- 设置默认分区
ALTER TABLE orders SET SUBPARTITION TEMPLATE ();

-- 修改分布策略（需要数据重分布）
ALTER TABLE users SET DISTRIBUTED BY (username);
ALTER TABLE users SET DISTRIBUTED RANDOMLY;

-- 修改存储参数（仅适用于 AO 表的压缩参数等）
ALTER TABLE events_ao SET (compresstype=zstd, compresslevel=5);

-- Owner
ALTER TABLE users OWNER TO admin;

-- Schema
ALTER TABLE users SET SCHEMA archive;

-- 继承
ALTER TABLE users_archive INHERIT users;
ALTER TABLE users_archive NO INHERIT users;

-- 注意：Greenplum 基于 PostgreSQL，支持大部分 PG ALTER TABLE 语法
-- 注意：UNIQUE/PRIMARY KEY 约束必须包含分布键
-- 注意：ALTER COLUMN TYPE 可能需要重写数据
-- 注意：修改分布键会触发数据重分布
