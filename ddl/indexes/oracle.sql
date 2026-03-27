-- Oracle: 索引
--
-- 参考资料:
--   [1] Oracle SQL Language Reference - CREATE INDEX
--       https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/CREATE-INDEX.html
--   [2] Oracle SQL Language Reference - ALTER INDEX
--       https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/ALTER-INDEX.html

-- 普通索引（B-tree）
CREATE INDEX idx_age ON users (age);

-- 唯一索引
CREATE UNIQUE INDEX uk_email ON users (email);

-- 复合索引
CREATE INDEX idx_city_age ON users (city, age);

-- 降序索引
CREATE INDEX idx_age_desc ON users (age DESC);

-- 函数索引
CREATE INDEX idx_upper_name ON users (UPPER(username));

-- 位图索引（低基数列，适合 OLAP，不适合高并发 OLTP）
CREATE BITMAP INDEX idx_status ON users (status);

-- 反向键索引（避免插入热点，如自增列）
CREATE INDEX idx_id_rev ON users (id) REVERSE;

-- 压缩索引
CREATE INDEX idx_city_age ON users (city, age) COMPRESS 1;

-- 11g+: 不可见索引
CREATE INDEX idx_age ON users (age) INVISIBLE;
ALTER INDEX idx_age VISIBLE;

-- 在线创建（不阻塞 DML）
CREATE INDEX idx_age ON users (age) ONLINE;

-- 12c+: 部分索引（通过索引条件实现，不如 PG 直观）
-- 需要在表上定义虚拟列或使用 CASE 表达式

-- 分区索引
-- 本地分区索引（与表分区对齐）
CREATE INDEX idx_date ON orders (order_date) LOCAL;
-- 全局分区索引
CREATE INDEX idx_amount ON orders (amount) GLOBAL
    PARTITION BY RANGE (amount) (
        PARTITION p1 VALUES LESS THAN (1000),
        PARTITION p2 VALUES LESS THAN (MAXVALUE)
    );

-- 删除索引
DROP INDEX idx_age;

-- 重建索引
ALTER INDEX idx_age REBUILD;
ALTER INDEX idx_age REBUILD ONLINE;

-- 查看索引
SELECT * FROM user_indexes WHERE table_name = 'USERS';
SELECT * FROM user_ind_columns WHERE table_name = 'USERS';
