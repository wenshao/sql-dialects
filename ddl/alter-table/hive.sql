-- Hive: ALTER TABLE
--
-- 参考资料:
--   [1] Apache Hive Language Manual - DDL (ALTER TABLE)
--       https://cwiki.apache.org/confluence/display/Hive/LanguageManual+DDL#LanguageManualDDL-AlterTable
--   [2] Apache Hive Language Manual - DDL
--       https://cwiki.apache.org/confluence/display/Hive/LanguageManual+DDL

-- 添加列
ALTER TABLE users ADD COLUMNS (phone STRING COMMENT 'Phone number');

-- 添加多列
ALTER TABLE users ADD COLUMNS (
    city    STRING COMMENT 'City',
    country STRING COMMENT 'Country'
);

-- 修改列名和类型（必须同时指定新类型）
ALTER TABLE users CHANGE COLUMN phone mobile STRING COMMENT 'Mobile number';
-- 可以改类型（但只能兼容变更，如 INT -> BIGINT）
ALTER TABLE users CHANGE COLUMN age age BIGINT;

-- 替换所有列定义（危险操作，重新定义列）
ALTER TABLE users REPLACE COLUMNS (
    id       BIGINT,
    username STRING,
    email    STRING
);

-- 添加分区
ALTER TABLE orders ADD PARTITION (dt = '20240115', region = 'us');
ALTER TABLE orders ADD IF NOT EXISTS PARTITION (dt = '20240115');

-- 删除分区
ALTER TABLE orders DROP PARTITION (dt = '20240115');
ALTER TABLE orders DROP IF EXISTS PARTITION (dt = '20240115');

-- 重命名分区
ALTER TABLE orders PARTITION (dt = '20240115')
    RENAME TO PARTITION (dt = '20240116');

-- 重命名表
ALTER TABLE users RENAME TO members;

-- 修改表属性
ALTER TABLE users SET TBLPROPERTIES ('comment' = 'User table');

-- 修改存储格式
ALTER TABLE users SET FILEFORMAT ORC;

-- 修改 SerDe
ALTER TABLE users SET SERDE 'org.apache.hive.hcatalog.data.JsonSerDe';

-- 修改表位置
ALTER TABLE users SET LOCATION '/new/path/users';
ALTER TABLE orders PARTITION (dt = '20240115') SET LOCATION '/data/20240115';

-- 启用/关闭 ACID
ALTER TABLE users SET TBLPROPERTIES ('transactional' = 'true');

-- 修改为外部表 / 内部表（Hive 3.0+）
ALTER TABLE users SET TBLPROPERTIES ('EXTERNAL' = 'TRUE');
ALTER TABLE users SET TBLPROPERTIES ('EXTERNAL' = 'FALSE');

-- TOUCH（更新表的元数据时间戳）
ALTER TABLE orders TOUCH;
ALTER TABLE orders TOUCH PARTITION (dt = '20240115');

-- CONCATENATE（合并小文件，仅 RCFile/ORC）
ALTER TABLE orders PARTITION (dt = '20240115') CONCATENATE;

-- 注意：不支持 DROP COLUMN（使用 REPLACE COLUMNS 重新定义列列表）
-- 注意：不支持直接修改 NOT NULL 约束
-- 注意：CHANGE COLUMN 不能改变列顺序（除非用 FIRST / AFTER）
ALTER TABLE users CHANGE COLUMN phone phone STRING AFTER email;
ALTER TABLE users CHANGE COLUMN phone phone STRING FIRST;
