-- Apache Impala: ALTER TABLE
--
-- 参考资料:
--   [1] Impala SQL Reference
--       https://impala.apache.org/docs/build/html/topics/impala_langref.html
--   [2] Impala Built-in Functions
--       https://impala.apache.org/docs/build/html/topics/impala_functions.html

-- 添加列
ALTER TABLE users ADD COLUMNS (phone STRING, city STRING);

-- 删除列（仅 Kudu 表支持）
ALTER TABLE users_kudu DROP COLUMN phone;

-- 修改列（改名/类型/注释）
ALTER TABLE users CHANGE COLUMN phone phone_number STRING COMMENT 'Phone number';

-- 替换所有列（非分区列）
ALTER TABLE users REPLACE COLUMNS (
    id       BIGINT,
    username STRING,
    email    STRING,
    age      INT,
    phone    STRING
);

-- 重命名表
ALTER TABLE users RENAME TO members;

-- 分区操作
ALTER TABLE orders ADD PARTITION (year=2024, month=4);
ALTER TABLE orders ADD IF NOT EXISTS PARTITION (year=2024, month=5);
ALTER TABLE orders DROP PARTITION (year=2024, month=1);
ALTER TABLE orders DROP IF EXISTS PARTITION (year=2024, month=1);

-- 设置分区的 HDFS 路径
ALTER TABLE orders PARTITION (year=2024, month=1)
    SET LOCATION '/data/orders/2024/01';

-- 修改存储格式
ALTER TABLE users SET FILEFORMAT PARQUET;
ALTER TABLE orders PARTITION (year=2024, month=1) SET FILEFORMAT ORC;

-- 修改表属性
ALTER TABLE users SET TBLPROPERTIES ('parquet.compression' = 'SNAPPY');
ALTER TABLE users SET TBLPROPERTIES ('comment' = 'User information table');

-- 修改行格式（文本表）
ALTER TABLE users_csv SET SERDEPROPERTIES ('field.delim' = '\t');

-- 修改表位置
ALTER TABLE users SET LOCATION '/new/path/to/users';

-- 缓存/取消缓存
ALTER TABLE users SET CACHED IN 'pool1';
ALTER TABLE users PARTITION (year=2024, month=1) SET CACHED IN 'pool1';
ALTER TABLE users SET UNCACHED;

-- Kudu 表特有操作
ALTER TABLE users_kudu SET COLUMN STATS username ('numDVs'='100');
ALTER TABLE users_kudu ALTER COLUMN email SET COMMENT 'Email address';
ALTER TABLE users_kudu ALTER COLUMN age SET DEFAULT 0;

-- Kudu Range 分区操作
ALTER TABLE orders_kudu ADD RANGE PARTITION '2025-01-01' <= VALUES < '2025-04-01';
ALTER TABLE orders_kudu DROP RANGE PARTITION '2024-01-01' <= VALUES < '2024-04-01';

-- 恢复分区（从文件系统目录自动添加分区）
ALTER TABLE orders RECOVER PARTITIONS;

-- 注意：Impala 的 ALTER TABLE 比 RDBMS 受限
-- 注意：非 Kudu 表不支持 DROP COLUMN
-- 注意：修改后需要运行 INVALIDATE METADATA 或 REFRESH 刷新元数据
-- INVALIDATE METADATA users;
-- REFRESH users;
