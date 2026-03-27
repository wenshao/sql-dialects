-- MaxCompute (ODPS): ALTER TABLE
--
-- 参考资料:
--   [1] MaxCompute SQL - ALTER TABLE
--       https://help.aliyun.com/zh/maxcompute/user-guide/alter-table
--   [2] MaxCompute SQL Overview
--       https://help.aliyun.com/zh/maxcompute/user-guide/sql-overview

-- 添加列
ALTER TABLE users ADD COLUMNS (phone STRING COMMENT '手机号');

-- 添加多列
ALTER TABLE users ADD COLUMNS (
    city    STRING COMMENT '城市',
    country STRING COMMENT '国家'
);

-- 添加分区列（添加分区值）
ALTER TABLE orders ADD PARTITION (dt = '20240115', region = 'cn');
ALTER TABLE orders ADD IF NOT EXISTS PARTITION (dt = '20240115');

-- 删除分区
ALTER TABLE orders DROP PARTITION (dt = '20240115');
ALTER TABLE orders DROP IF EXISTS PARTITION (dt = '20240115');

-- 修改列名
ALTER TABLE users CHANGE COLUMN phone mobile STRING COMMENT '手机号';

-- 修改列注释
ALTER TABLE users CHANGE COLUMN email email STRING COMMENT '新的注释';

-- 修改表注释
ALTER TABLE users SET COMMENT '用户信息表';

-- 修改生命周期
ALTER TABLE users SET LIFECYCLE 180;

-- 重命名表
ALTER TABLE users RENAME TO members;

-- 修改表属性
ALTER TABLE users SET TBLPROPERTIES ('comment' = 'User table');

-- 清空表数据
TRUNCATE TABLE users;

-- 事务表操作（需要声明 transactional）
-- ALTER TABLE users SET TBLPROPERTIES ('transactional' = 'true');

-- 合并小文件
ALTER TABLE orders PARTITION (dt = '20240115') MERGE SMALLFILES;

-- 注意：不支持 DROP COLUMN（需要重建表）
-- 注意：不支持直接修改列类型（需要重建表）
-- 注意：不支持修改列顺序
-- 注意：分区列不能被 ADD/DROP/CHANGE
-- 注意：ALTER TABLE 能力比传统数据库有限
-- 替代方案：通过 CREATE TABLE ... AS SELECT 重建表来实现不支持的变更
