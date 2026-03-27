# 范围类型和时间段

用一个值表达一个区间——PostgreSQL 的范围类型和 SQL:2011 的 PERIOD 定义，解决"无重叠约束"等传统 SQL 难以表达的问题。

## 支持矩阵

| 引擎 | 特性 | 版本 | 备注 |
|------|------|------|------|
| PostgreSQL | 范围类型 (Range Types) | 9.2+ | **最完整的实现** |
| PostgreSQL | EXCLUDE 约束 | 9.2+ | 基于 GiST 索引 |
| PostgreSQL | 多范围类型 (Multirange) | 14+ | 不连续区间的集合 |
| Teradata | PERIOD 类型 | V13+ | SQL:2011 PERIOD 的先驱 |
| MariaDB | PERIOD + WITHOUT OVERLAPS | 10.5+ | 部分支持 SQL:2011 |
| Oracle | 不支持 | - | 需用两列 + CHECK 约束模拟 |
| SQL Server | 不支持 | - | Temporal Tables 有 PERIOD 但语义不同 |
| MySQL | 不支持 | - | 需用两列模拟 |

## 问题场景: 为什么需要范围类型

### 传统的两列表示法

```sql
-- 酒店房间预订表: 传统方式用两列表示时间段
CREATE TABLE reservations (
    room_id INT,
    guest_name VARCHAR(100),
    check_in DATE,
    check_out DATE,
    CHECK (check_in < check_out)
);

-- 问题: 如何确保同一房间的预订不重叠？
-- 传统方式需要一个复杂的触发器或应用层检查:
-- "不存在另一条记录使得 check_in < other.check_out AND check_out > other.check_in"
```

这种检查有竞态条件：两个并发事务可能同时检查通过，然后都插入成功，导致重叠。

### 范围类型的解决方案

```sql
-- PostgreSQL: 用范围类型 + EXCLUDE 约束，数据库层面保证无重叠
CREATE TABLE reservations (
    room_id INT,
    guest_name VARCHAR(100),
    stay daterange,                         -- 一个列表示整个区间
    EXCLUDE USING gist (
        room_id WITH =,                     -- room_id 相同
        stay WITH &&                         -- 且 stay 有重叠
    )                                        -- → 拒绝插入
);

INSERT INTO reservations VALUES (101, 'Alice', '[2024-03-01, 2024-03-05)');
INSERT INTO reservations VALUES (101, 'Bob',   '[2024-03-04, 2024-03-08)');
-- ERROR: conflicting key value violates exclusion constraint
-- 数据库层面保证无重叠，无竞态条件
```

## PostgreSQL 范围类型

### 内置范围类型

```sql
-- PostgreSQL 提供的内置范围类型:
int4range    -- integer 范围
int8range    -- bigint 范围
numrange     -- numeric 范围
daterange    -- date 范围
tsrange      -- timestamp without time zone 范围
tstzrange    -- timestamp with time zone 范围

-- 范围字面量语法:
'[1, 10]'    -- 闭区间: 1 <= x <= 10
'[1, 10)'    -- 左闭右开: 1 <= x < 10  （最常用）
'(1, 10]'    -- 左开右闭: 1 < x <= 10
'(1, 10)'    -- 开区间: 1 < x < 10

-- 构造函数:
SELECT int4range(1, 10);              -- [1,10)  默认左闭右开
SELECT int4range(1, 10, '[]');        -- [1,11)  闭区间（整数范围会被规范化）
SELECT daterange('2024-01-01', '2024-12-31', '[]');  -- [2024-01-01,2025-01-01)
```

### 范围运算符

```sql
-- && 重叠: 两个范围是否有交集
SELECT '[1,5)'::int4range && '[3,8)'::int4range;   -- true
SELECT '[1,3)'::int4range && '[5,8)'::int4range;   -- false

-- @> 包含: 范围是否包含值或另一个范围
SELECT '[1,10)'::int4range @> 5;                    -- true (包含值)
SELECT '[1,10)'::int4range @> '[3,7)'::int4range;   -- true (包含范围)

-- <@ 被包含: 值或范围是否在另一个范围内
SELECT 5 <@ '[1,10)'::int4range;                    -- true

-- -|- 相邻: 两个范围是否首尾相接
SELECT '[1,5)'::int4range -|- '[5,10)'::int4range;  -- true

-- + 并集, * 交集, - 差集
SELECT '[1,5)'::int4range + '[3,8)'::int4range;     -- [1,8)
SELECT '[1,5)'::int4range * '[3,8)'::int4range;     -- [3,5)
SELECT '[1,10)'::int4range - '[3,5)'::int4range;    -- 错误! 结果不连续

-- 函数
SELECT lower('[2024-01-01, 2024-12-31)'::daterange);   -- 2024-01-01
SELECT upper('[2024-01-01, 2024-12-31)'::daterange);   -- 2024-12-31
SELECT isempty('(5,5)'::int4range);                     -- true
```

### EXCLUDE 约束: 无重叠保证

```sql
-- EXCLUDE 约束是 UNIQUE 约束的泛化
-- UNIQUE: 任意两行的值不能 "相等"
-- EXCLUDE: 任意两行的值不能满足 "指定的运算符组合"

-- 需要安装 btree_gist 扩展（让标量类型也能用 GiST 索引）
CREATE EXTENSION IF NOT EXISTS btree_gist;

-- 会议室预约: 同一房间同一时间不能有两个会议
CREATE TABLE meetings (
    room_id INT,
    meeting_time tstzrange,
    organizer TEXT,
    EXCLUDE USING gist (
        room_id WITH =,              -- room_id 相等
        meeting_time WITH &&          -- 且时间重叠
    )                                 -- → 拒绝
);

-- 价格有效期: 同一产品同一时间只能有一个价格
CREATE TABLE product_prices (
    product_id INT,
    price NUMERIC,
    valid_period daterange,
    EXCLUDE USING gist (
        product_id WITH =,
        valid_period WITH &&
    )
);

INSERT INTO product_prices VALUES (1, 9.99, '[2024-01-01, 2024-06-01)');
INSERT INTO product_prices VALUES (1, 8.99, '[2024-04-01, 2024-09-01)');
-- ERROR: 价格有效期重叠
```

### 多范围类型 (PostgreSQL 14+)

```sql
-- 多范围: 多个不连续区间的集合
SELECT '{[1,3), [7,10)}'::int4multirange;

-- 用于表示不连续的时间段
-- 例: 员工的工作时间（可能有间断）
SELECT '{[2020-01-01, 2022-06-30), [2023-01-01, 2024-12-31)}'::datemultirange;

-- 范围差集的结果可以用多范围表示
SELECT '[1,10)'::int4range - '[3,5)'::int4range;  -- 在 PG14+ 返回 {[1,3),[5,10)}
```

### GiST 索引

```sql
-- 范围类型的查询需要 GiST 索引来加速
CREATE INDEX idx_reservations_stay ON reservations USING gist (stay);

-- 查询某个日期哪些房间被占用
SELECT room_id, guest_name
FROM reservations
WHERE stay @> '2024-03-03'::date;      -- GiST 索引加速

-- 查询与某个时间段重叠的预订
SELECT room_id, guest_name
FROM reservations
WHERE stay && '[2024-03-01, 2024-03-10)'::daterange;  -- GiST 索引加速

-- SP-GiST 索引也支持范围类型（PG 14+）
CREATE INDEX idx_reservations_stay_spgist ON reservations USING spgist (stay);
```

## Teradata PERIOD 类型

```sql
-- Teradata 是 PERIOD 类型的先驱
CREATE TABLE employee_history (
    emp_id INTEGER,
    dept_id INTEGER,
    employment PERIOD(DATE)           -- PERIOD 类型
);

-- 插入
INSERT INTO employee_history VALUES (1, 10, PERIOD(DATE '2020-01-01', DATE '2024-12-31'));

-- 查询: BEGIN/END 提取端点
SELECT emp_id, BEGIN(employment), END(employment) FROM employee_history;

-- 重叠检测
SELECT * FROM employee_history
WHERE employment OVERLAPS PERIOD(DATE '2023-01-01', DATE '2023-12-31');

-- P_INTERSECT / P_NORMALIZE 等内置函数
```

## SQL:2011 PERIOD 定义

SQL:2011 标准定义了 PERIOD 的规范：

```sql
-- SQL:2011 标准语法（非所有引擎支持）
CREATE TABLE contracts (
    contract_id INT PRIMARY KEY,
    customer_id INT,
    start_date DATE,
    end_date DATE,
    PERIOD FOR validity (start_date, end_date),      -- 定义 PERIOD
    CONSTRAINT no_overlap
        UNIQUE (customer_id, validity WITHOUT OVERLAPS) -- 无重叠约束
);

-- WITHOUT OVERLAPS 等价于 PostgreSQL 的 EXCLUDE ... WITH &&
-- 但语法更标准化
```

### MariaDB 实现 (10.5+)

```sql
-- MariaDB 部分支持 SQL:2011 PERIOD
CREATE TABLE prices (
    product_id INT,
    price DECIMAL(10,2),
    start_date DATE,
    end_date DATE,
    PERIOD FOR valid_period (start_date, end_date),
    UNIQUE (product_id, valid_period WITHOUT OVERLAPS)
);

-- MariaDB 的 PERIOD 不是真正的范围类型
-- 它仍然使用两个标量列，PERIOD 只是元数据声明
-- WITHOUT OVERLAPS 是基于这个声明做约束检查

-- DELETE / UPDATE 可以按 PERIOD 操作
DELETE FROM prices
FOR PORTION OF valid_period
FROM '2024-03-01' TO '2024-06-01';
-- 自动拆分: 如果删除区间在已有记录中间，会自动拆分为两条记录
```

## 用例

### 1. 酒店预订无重叠

```sql
-- PostgreSQL 完整方案
CREATE EXTENSION IF NOT EXISTS btree_gist;

CREATE TABLE hotel_bookings (
    booking_id SERIAL PRIMARY KEY,
    room_id INT NOT NULL,
    guest_name TEXT NOT NULL,
    stay daterange NOT NULL,
    CONSTRAINT valid_stay CHECK (NOT isempty(stay)),
    EXCLUDE USING gist (room_id WITH =, stay WITH &&)
);

-- 查询某日可用房间
SELECT room_id FROM rooms
WHERE room_id NOT IN (
    SELECT room_id FROM hotel_bookings
    WHERE stay @> CURRENT_DATE
);
```

### 2. 员工任职区间

```sql
CREATE TABLE employment_periods (
    emp_id INT,
    dept_id INT,
    period daterange,
    EXCLUDE USING gist (emp_id WITH =, period WITH &&)
);

-- 某员工的完整任职历史
SELECT dept_id, lower(period) AS start_date, upper(period) AS end_date
FROM employment_periods
WHERE emp_id = 42
ORDER BY lower(period);
```

### 3. 价格有效期查询

```sql
-- 查询某产品在某日期的价格
SELECT price
FROM product_prices
WHERE product_id = 100
  AND valid_period @> '2024-06-15'::date;

-- 查询某产品的价格变更历史
SELECT price, lower(valid_period) AS effective_from, upper(valid_period) AS effective_until
FROM product_prices
WHERE product_id = 100
ORDER BY lower(valid_period);
```

## 对引擎开发者的实现建议

### 1. 范围类型的存储表示

```
RangeValue {
    lower: Option<T>         // None = 无下界 (-infinity)
    upper: Option<T>         // None = 无上界 (+infinity)
    lower_inclusive: bool     // 下界是否包含
    upper_inclusive: bool     // 上界是否包含
    is_empty: bool           // 空范围标记
}

// 规范化: 离散类型（integer, date）的范围自动转为左闭右开
// [1, 5] → [1, 6)
// (1, 5] → [2, 6)
// 这简化了比较和运算
```

### 2. GiST 索引支持

范围查询的高效执行依赖 GiST（Generalized Search Tree）索引：

- 内部节点存储范围的边界框（bounding range）
- 支持的操作：包含、被包含、重叠、相邻、左侧、右侧
- 插入时通过最小化边界框扩展来选择子树
- 对于 EXCLUDE 约束，在插入前检查是否有冲突

### 3. 不支持原生范围类型时的替代实现

```sql
-- 对于不支持范围类型的引擎，可用两列 + 唯一索引 + 触发器模拟
-- 但无法避免并发竞态条件（除非用序列化隔离级别）

CREATE TABLE reservations (
    room_id INT,
    start_date DATE,
    end_date DATE,
    CHECK (start_date < end_date)
);

-- 伪 EXCLUDE 约束（通过触发器）
-- 在 INSERT/UPDATE 前检查:
-- NOT EXISTS (
--   SELECT 1 FROM reservations
--   WHERE room_id = NEW.room_id
--     AND start_date < NEW.end_date
--     AND end_date > NEW.start_date
-- )
-- 注意: 需要 SERIALIZABLE 隔离级别才能避免竞态
```

## 设计争议

### 范围类型 vs PERIOD

PostgreSQL 的范围类型是真正的一等类型——有独立的存储格式、运算符、索引支持。SQL:2011 的 PERIOD 只是两个标量列上的元数据声明，底层仍然是两列存储。

范围类型更强大（支持完整的集合运算），但学习曲线更陡；PERIOD 更容易理解，但功能有限。

对引擎开发者的建议：如果目标是"无重叠约束"这一核心需求，PERIOD + WITHOUT OVERLAPS 就够了，实现成本远低于完整的范围类型系统。

## 参考资料

- PostgreSQL: [Range Types](https://www.postgresql.org/docs/current/rangetypes.html)
- PostgreSQL: [EXCLUDE Constraint](https://www.postgresql.org/docs/current/sql-createtable.html#SQL-CREATETABLE-EXCLUDE)
- SQL:2011 标准: ISO/IEC 9075-2, Section 4.6.3 (Periods)
- MariaDB: [PERIOD](https://mariadb.com/kb/en/application-time-periods/)
- Teradata: [PERIOD Data Type](https://docs.teradata.com/r/Teradata-Database-SQL-Data-Types-and-Literals)
