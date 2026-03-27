-- Oracle: ALTER TABLE
--
-- 参考资料:
--   [1] Oracle SQL Language Reference - ALTER TABLE
--       https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/ALTER-TABLE.html
--   [2] Oracle SQL Language Reference - Data Types
--       https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/Data-Types.html

-- 添加列
ALTER TABLE users ADD (phone VARCHAR2(20));
ALTER TABLE users ADD (phone VARCHAR2(20) DEFAULT 'N/A' NOT NULL);

-- 添加多列
ALTER TABLE users ADD (
    city    VARCHAR2(64),
    country VARCHAR2(64)
);

-- 修改列类型 / 大小
ALTER TABLE users MODIFY (phone VARCHAR2(32));
ALTER TABLE users MODIFY (phone VARCHAR2(32) NOT NULL);

-- 多列一起修改
ALTER TABLE users MODIFY (
    phone VARCHAR2(32) NOT NULL,
    email VARCHAR2(320)
);

-- 9i R2+: 重命名列
ALTER TABLE users RENAME COLUMN phone TO mobile;

-- 删除列
ALTER TABLE users DROP COLUMN phone;
ALTER TABLE users DROP (phone, city);  -- 一次删除多列

-- 标记列为未使用（大表删列更快，先标记再后台清理）
ALTER TABLE users SET UNUSED COLUMN phone;
ALTER TABLE users DROP UNUSED COLUMNS;

-- 修改默认值
ALTER TABLE users MODIFY (status NUMBER(1) DEFAULT 0);

-- 重命名表
ALTER TABLE users RENAME TO members;

-- 12c+: 添加列带默认值不再重写整个表（即时操作）
-- 11g+: 添加带 DEFAULT + NOT NULL 的列也是即时的

-- 只读表
ALTER TABLE users READ ONLY;
ALTER TABLE users READ WRITE;
