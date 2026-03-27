-- Oracle: 表分区策略
--
-- 参考资料:
--   [1] Oracle Documentation - Partitioned Tables and Indexes
--       https://docs.oracle.com/en/database/oracle/oracle-database/23/vldbg/
--   [2] Oracle Documentation - CREATE TABLE (Partitioning)
--       https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/CREATE-TABLE.html

-- ============================================================
-- RANGE 分区
-- ============================================================

CREATE TABLE orders (
    id          NUMBER,
    user_id     NUMBER,
    amount      NUMBER(10,2),
    order_date  DATE
) PARTITION BY RANGE (order_date) (
    PARTITION p2023 VALUES LESS THAN (DATE '2024-01-01'),
    PARTITION p2024 VALUES LESS THAN (DATE '2025-01-01'),
    PARTITION p2025 VALUES LESS THAN (DATE '2026-01-01'),
    PARTITION pmax  VALUES LESS THAN (MAXVALUE)
);

-- INTERVAL 分区（11g+，自动创建分区）
CREATE TABLE logs (
    id         NUMBER,
    log_date   DATE,
    message    VARCHAR2(4000)
) PARTITION BY RANGE (log_date)
  INTERVAL (NUMTOYMINTERVAL(1, 'MONTH')) (
    PARTITION p_init VALUES LESS THAN (DATE '2024-01-01')
);
-- 新数据自动创建按月分区

-- ============================================================
-- LIST 分区
-- ============================================================

CREATE TABLE users_region (
    id       NUMBER,
    username VARCHAR2(100),
    region   VARCHAR2(20)
) PARTITION BY LIST (region) (
    PARTITION p_east  VALUES ('Shanghai', 'Hangzhou'),
    PARTITION p_north VALUES ('Beijing', 'Tianjin'),
    PARTITION p_south VALUES ('Guangzhou', 'Shenzhen'),
    PARTITION p_other VALUES (DEFAULT)
);

-- 自动 LIST 分区（12.2+）
CREATE TABLE events (
    id     NUMBER,
    type   VARCHAR2(50),
    data   CLOB
) PARTITION BY LIST (type) AUTOMATIC (
    PARTITION p_init VALUES ('CLICK')
);
-- 新的 type 值自动创建分区

-- ============================================================
-- HASH 分区
-- ============================================================

CREATE TABLE sessions (
    id      NUMBER,
    user_id NUMBER,
    data    CLOB
) PARTITION BY HASH (user_id)
  PARTITIONS 8;

-- 指定分区名和表空间
CREATE TABLE cache (
    id NUMBER, key_val VARCHAR2(100), data CLOB
) PARTITION BY HASH (key_val) (
    PARTITION p1 TABLESPACE ts1,
    PARTITION p2 TABLESPACE ts2,
    PARTITION p3 TABLESPACE ts3,
    PARTITION p4 TABLESPACE ts4
);

-- ============================================================
-- 复合分区
-- ============================================================

-- RANGE-HASH
CREATE TABLE sales (
    id         NUMBER,
    sale_date  DATE,
    region     VARCHAR2(20),
    amount     NUMBER(10,2)
) PARTITION BY RANGE (sale_date)
  SUBPARTITION BY HASH (region) SUBPARTITIONS 4 (
    PARTITION p2024 VALUES LESS THAN (DATE '2025-01-01'),
    PARTITION p2025 VALUES LESS THAN (DATE '2026-01-01')
);

-- RANGE-LIST
CREATE TABLE transactions (
    id        NUMBER,
    tx_date   DATE,
    tx_type   VARCHAR2(20),
    amount    NUMBER(10,2)
) PARTITION BY RANGE (tx_date)
  SUBPARTITION BY LIST (tx_type) (
    PARTITION p2024 VALUES LESS THAN (DATE '2025-01-01') (
        SUBPARTITION p2024_credit VALUES ('CREDIT'),
        SUBPARTITION p2024_debit  VALUES ('DEBIT'),
        SUBPARTITION p2024_other  VALUES (DEFAULT)
    ),
    PARTITION p2025 VALUES LESS THAN (DATE '2026-01-01') (
        SUBPARTITION p2025_credit VALUES ('CREDIT'),
        SUBPARTITION p2025_debit  VALUES ('DEBIT'),
        SUBPARTITION p2025_other  VALUES (DEFAULT)
    )
);

-- ============================================================
-- REFERENCE 分区（11g+）
-- ============================================================

-- 子表根据外键继承父表的分区策略
CREATE TABLE order_items (
    id       NUMBER,
    order_id NUMBER NOT NULL,
    product  VARCHAR2(100),
    qty      NUMBER,
    CONSTRAINT fk_order FOREIGN KEY (order_id) REFERENCES orders(id)
) PARTITION BY REFERENCE (fk_order);

-- ============================================================
-- 分区管理
-- ============================================================

-- 添加分区
ALTER TABLE orders ADD PARTITION p2026
    VALUES LESS THAN (DATE '2027-01-01');

-- 删除分区
ALTER TABLE orders DROP PARTITION p2023;

-- 清空分区
ALTER TABLE orders TRUNCATE PARTITION p2023;

-- 合并分区
ALTER TABLE orders MERGE PARTITIONS p2024, p2025
    INTO PARTITION p2024_2025;

-- 拆分分区
ALTER TABLE orders SPLIT PARTITION pmax AT (DATE '2027-01-01')
    INTO (PARTITION p2026, PARTITION pmax);

-- 交换分区
ALTER TABLE orders EXCHANGE PARTITION p2024
    WITH TABLE orders_2024_staging;

-- 移动分区到不同表空间
ALTER TABLE orders MOVE PARTITION p2024 TABLESPACE archive_ts;

-- 在线重定义（DBMS_REDEFINITION）
-- 用于在线修改分区策略

-- ============================================================
-- 分区索引
-- ============================================================

-- 本地索引（每个分区一个索引段）
CREATE INDEX idx_orders_user ON orders(user_id) LOCAL;

-- 全局索引（跨分区）
CREATE INDEX idx_orders_amount ON orders(amount) GLOBAL;

-- 全局分区索引
CREATE INDEX idx_orders_global ON orders(user_id) GLOBAL
PARTITION BY RANGE (user_id) (
    PARTITION ip1 VALUES LESS THAN (10000),
    PARTITION ip2 VALUES LESS THAN (MAXVALUE)
);

-- ============================================================
-- 查看分区信息
-- ============================================================

SELECT partition_name, high_value, num_rows, blocks
FROM user_tab_partitions
WHERE table_name = 'ORDERS'
ORDER BY partition_position;

SELECT subpartition_name, partition_name, high_value, num_rows
FROM user_tab_subpartitions
WHERE table_name = 'SALES';

-- 注意：Oracle 提供最丰富的分区功能
-- 注意：INTERVAL 分区（11g+）自动创建新分区
-- 注意：AUTOMATIC LIST 分区（12.2+）自动为新值创建分区
-- 注意：REFERENCE 分区让子表继承父表的分区策略
-- 注意：本地索引自动按分区维护，全局索引可能需要手动 REBUILD
-- 注意：EXCHANGE PARTITION 是批量数据加载的高效方式
