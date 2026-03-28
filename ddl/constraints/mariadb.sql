-- MariaDB: 约束 (Constraints)
-- CHECK 约束从 10.2.1 开始真正执行 (比 MySQL 8.0.16 更早)
--
-- 参考资料:
--   [1] MariaDB Knowledge Base - Constraint
--       https://mariadb.com/kb/en/constraint/

-- ============================================================
-- 1. 基本约束 (与 MySQL 语法相同)
-- ============================================================
CREATE TABLE employees (
    id         BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
    name       VARCHAR(100) NOT NULL,
    email      VARCHAR(255) NOT NULL,
    dept_id    INT NOT NULL,
    salary     DECIMAL(12,2),
    hire_date  DATE NOT NULL,
    UNIQUE KEY uk_email (email),
    CONSTRAINT fk_dept FOREIGN KEY (dept_id) REFERENCES departments(id)
        ON DELETE RESTRICT ON UPDATE CASCADE
);

-- ============================================================
-- 2. CHECK 约束 (10.2.1+ 真正执行)
-- ============================================================
CREATE TABLE products (
    id       BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
    name     VARCHAR(255) NOT NULL,
    price    DECIMAL(10,2) CONSTRAINT chk_price CHECK (price >= 0),
    quantity INT CHECK (quantity >= 0),
    discount DECIMAL(5,2) CHECK (discount BETWEEN 0 AND 100),
    CONSTRAINT chk_price_qty CHECK (price * quantity < 1000000)
);
-- MariaDB 10.2.1: CHECK 约束开始真正执行违规则报错
-- 对比 MySQL: 5.7 及之前解析但静默忽略! 8.0.16 才真正执行
-- MariaDB 在这一点上领先 MySQL 约 2 年

-- ============================================================
-- 3. WITHOUT OVERLAPS (10.5.3+) -- MariaDB 独有
-- ============================================================
CREATE TABLE room_reservations (
    room_id    INT NOT NULL,
    start_time DATETIME NOT NULL,
    end_time   DATETIME NOT NULL,
    guest      VARCHAR(100),
    PERIOD FOR reservation_period (start_time, end_time),
    UNIQUE (room_id, reservation_period WITHOUT OVERLAPS)
);
-- 数据库级别防止时间段重叠, 无需应用逻辑
-- 这是 SQL:2011 标准特性, MariaDB 是少数实现者之一
-- 对比: PostgreSQL 需要 EXCLUDE USING gist 约束 + btree_gist 扩展
-- 对比: MySQL/Oracle/SQL Server 均不原生支持

-- ============================================================
-- 4. 外键在不同引擎中的行为
-- ============================================================
-- InnoDB: 完整外键支持
-- Aria/MyISAM: 接受外键语法但不执行! (同 MySQL MyISAM)
-- 陷阱: ENGINE=Aria 时外键约束被静默忽略

-- ============================================================
-- 5. 命名约束与管理
-- ============================================================
ALTER TABLE products DROP CONSTRAINT chk_price;
ALTER TABLE products ADD CONSTRAINT chk_new_price CHECK (price > 0 AND price < 99999);

-- IF EXISTS (MariaDB 扩展, MySQL 不完全支持)
ALTER TABLE products DROP CONSTRAINT IF EXISTS chk_old;

-- ============================================================
-- 6. 对引擎开发者的启示
-- ============================================================
-- WITHOUT OVERLAPS 的实现需要:
--   1. PERIOD 定义: 两个列定义一个时间段
--   2. 重叠检测算法: 新行的 [start, end) 与现有行的 [start, end) 比较
--   3. 索引支持: 需要范围查询索引加速重叠检测 (类似 R-Tree 或 GiST)
--   4. 并发控制: 间隙锁或谓词锁防止并发插入产生重叠
-- PostgreSQL 的 EXCLUDE 约束用 GiST 索引实现, MariaDB 用 B-Tree 范围扫描
