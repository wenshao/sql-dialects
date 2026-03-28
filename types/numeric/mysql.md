# MySQL: 数值类型

> 参考资料:
> - [MySQL 8.0 Reference Manual - Numeric Data Types](https://dev.mysql.com/doc/refman/8.0/en/numeric-types.html)
> - [MySQL 8.0 Reference Manual - Precision Math](https://dev.mysql.com/doc/refman/8.0/en/precision-math.html)
> - IEEE 754-2008 Standard for Floating-Point Arithmetic
> - [MySQL 8.0 Reference Manual - Type Conversion in Expression Evaluation](https://dev.mysql.com/doc/refman/8.0/en/type-conversion.html)

## 整数类型一览

```sql
CREATE TABLE integer_examples (
    tiny_val   TINYINT,         -- 1B: -128 ~ 127         (UNSIGNED: 0 ~ 255)
    small_val  SMALLINT,        -- 2B: -32768 ~ 32767
    medium_val MEDIUMINT,       -- 3B: -8388608 ~ 8388607 (MySQL 独有)
    int_val    INT,             -- 4B: -2^31 ~ 2^31-1     (约 +-21.47 亿)
    big_val    BIGINT,          -- 8B: -2^63 ~ 2^63-1     (约 +-922 京)
    flag       TINYINT(1),      -- BOOL/BOOLEAN 的别名（不是真正的布尔类型）
    id         BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY
) ENGINE=InnoDB;
```

## BIGINT vs INT: 21 亿上限问题（对引擎开发者）

### INT 的上限: 2,147,483,647 (约 21.47 亿)

看似很大，但在以下场景很快耗尽:
  - 高频写入: 每秒 1000 条 INSERT → 约 24.8 天耗尽 UNSIGNED INT
  - 分布式 ID: 多节点预分配 ID 段时，有效范围进一步缩小
  - 日志/事件表: IoT 设备每秒多条记录，INT 不够用

### BIGINT 的范围: 9,223,372,036,854,775,807 (约 922 京)

每秒 100 万条 INSERT → 约 29.2 万年耗尽
代价: 多占 4 字节/行，主键 + 所有二级索引都存 8 字节指针

实践建议: 新表主键一律用 BIGINT
迁移代价: ALTER TABLE t MODIFY id BIGINT 需要重建整表 + 所有二级索引
这个 ALTER 在大表上可能需要数小时，且 5.7 以下会锁表

横向对比:
  PostgreSQL: INTEGER(4B) / BIGINT(8B)，无 TINYINT/MEDIUMINT
  Oracle:     NUMBER(p)，无固定字节整数，NUMBER(10) 约等于 INT 范围
  SQL Server: TINYINT(1B) / SMALLINT(2B) / INT(4B) / BIGINT(8B)
  ClickHouse: Int8/16/32/64/128/256 + UInt8/16/32/64/128/256
              128 位和 256 位整数是 ClickHouse 独有的（分析场景需要超大聚合）

## DECIMAL 精确计算 vs FLOAT/DOUBLE IEEE 754 精度损失

```sql
CREATE TABLE precision_demo (
    -- DECIMAL(M,D): M 总位数(1-65)，D 小数位(0-30)，D <= M
    price       DECIMAL(10,2),    -- 精确到分: 99999999.99
    rate        DECIMAL(20,10),   -- 高精度比率
    -- FLOAT:  4B, IEEE 754 单精度，约 7 位有效数字
    approx_f    FLOAT,
    -- DOUBLE: 8B, IEEE 754 双精度，约 15 位有效数字
    approx_d    DOUBLE
);
```

### DECIMAL 的内部实现

MySQL 将 DECIMAL 以 BCD (Binary-Coded Decimal) 压缩存储:
每 9 个十进制位占 4 字节，不足 9 位按比例分配:
  1-2位→1B, 3-4位→2B, 5-6位→3B, 7-9位→4B
例: DECIMAL(10,2) = 整数8位 + 小数2位 = 4B(9位) + 1B(2位) = 5B 存储
运算: 加减乘除全部用十进制算术，不经过浮点转换，结果精确

### IEEE 754 的精度损失

FLOAT/DOUBLE 无法精确表示大多数十进制小数:
  0.1 + 0.2 = 0.30000000000000004 (不等于 0.3)
  这不是 MySQL 的 bug，是 IEEE 754 的固有特性

经典事故:
  SELECT FLOAT_COL = 0.1 → 可能永远不匹配！
  SUM(FLOAT_COL) 在百万行后累积误差可达数元
  财务场景使用 FLOAT 导致对账差异: 绝对禁止

规则: 涉及金额、精确计数用 DECIMAL；科学计算、近似统计用 DOUBLE

### 横向对比: 精确数值类型

  MySQL:      DECIMAL(65,30)，存储最大 65 位
  PostgreSQL: NUMERIC(1000,...)，精度上限远高于 MySQL
  Oracle:     NUMBER(38,127)，38 位有效数字，指数范围 -84~127
              NUMBER 是 Oracle 唯一的数值类型（INT 只是 NUMBER(38) 的别名）
  SQL Server: DECIMAL(38,s)，与 Oracle 类似
  ClickHouse: Decimal32(S)/64(S)/128(S)/256(S)
              Decimal256 支持 76 位有效数字（分析场景的超高精度聚合）
  BigQuery:   NUMERIC(38,9) 定点 / BIGNUMERIC(76,38) 高精度
  Snowflake:  NUMBER(38,s)

## UNSIGNED 的废弃趋势和设计反思

### UNSIGNED 整数: MySQL 独有特性

INT UNSIGNED: 0 ~ 4,294,967,295（正数范围翻倍）
看似有用，但带来了严重的语义问题:

### UNSIGNED 的陷阱: 减法溢出

SET sql_mode = 'NO_UNSIGNED_SUBTRACTION' 关闭时（默认关闭）:
  SELECT CAST(0 AS UNSIGNED) - 1;  → 18446744073709551615 (BIGINT UNSIGNED 最大值!)
  SELECT a - b FROM t;  -- 如果 a=1, b=2，结果不是 -1，而是溢出为超大数
这个行为在 C 语言中是合理的（无符号算术），但在 SQL 中极其反直觉

### 废弃时间线

8.0.17+: FLOAT UNSIGNED / DOUBLE UNSIGNED / DECIMAL UNSIGNED 废弃（仍可用但产生警告）
整数 UNSIGNED（INT UNSIGNED, BIGINT UNSIGNED）暂未废弃但不推荐
MySQL 官方理由: "UNSIGNED 对浮点和定点类型没有意义，且行为容易混淆"

### 为什么废弃？对引擎开发者的启示

SQL 标准不包含 UNSIGNED，这是 MySQL 的非标准扩展
导致的问题:
  1. 跨数据库迁移困难（PG/Oracle/SQL Server 均无 UNSIGNED）
  2. 算术语义违反直觉（减法溢出）
  3. 与 CHECK 约束功能重叠: CHECK (val >= 0) 更清晰
  4. ORM 和驱动层需要额外处理 UNSIGNED 到语言类型的映射

横向对比:
  PostgreSQL: 无 UNSIGNED（故意排除），用 CHECK 约束替代
  Oracle:     无 UNSIGNED
  SQL Server: 无 UNSIGNED
  ClickHouse: 有 UInt8/16/32/64/128/256（C++ 分析引擎，无符号有性能意义）
> **结论**: OLTP 数据库不需要 UNSIGNED；分析引擎（如 ClickHouse）因存储和向量化
        计算的对齐优化，UNSIGNED 有合理存在意义

## 显示宽度与 ZEROFILL（已废弃）

INT(11) 中的 11: 不影响存储或范围！仅影响 ZEROFILL 显示
例: INT(5) ZEROFILL + 值 42 → 显示为 00042
8.0.17+: 显示宽度和 ZEROFILL 均已废弃
教训: 将"显示格式"混入"数据类型定义"是错误的设计
       格式化应在应用层或 FORMAT() 函数中处理

## BIT 类型和布尔值

```sql
CREATE TABLE bit_demo (
    flags  BIT(8),           -- 位字段，1-64 位
    active BOOLEAN            -- TINYINT(1) 的别名，不是真正的布尔
);
```

MySQL 没有原生 BOOLEAN:
  TRUE = 1, FALSE = 0，可以存任何 TINYINT 值（如 42）
  WHERE active = TRUE 等价于 WHERE active = 1，不等价于 WHERE active != 0
  INSERT INTO t (active) VALUES (42); -- 合法！不是真正的布尔约束

横向对比:
  PostgreSQL: 原生 BOOLEAN 类型，只接受 TRUE/FALSE/NULL
  SQL Server: BIT 类型，只接受 0/1/NULL（比 MySQL 更严格）
  Oracle:     无 BOOLEAN（PL/SQL 有但 SQL 没有，直到 23c）
  ClickHouse: Bool（UInt8 的别名，0/1）

对引擎开发者的启示: 实现原生 BOOLEAN 类型，不要用整数别名

## 类型转换的隐式规则（影响查询优化）

MySQL 的隐式转换规则可能导致索引失效:
  WHERE varchar_col = 123     → varchar_col 转为数值比较，索引失效！
  WHERE int_col = '123'       → '123' 转为 INT，索引可用
  WHERE int_col = '123abc'    → '123abc' 转为 123（截断！），只产生 warning

这种不对称的转换规则是 MySQL 最大的性能陷阱之一。
横向对比:
  PostgreSQL: 严格类型，不做隐式转换，直接报错 → 安全但学习曲线高
  Oracle:     中等严格，TO_NUMBER/TO_CHAR 显式转换为主
  SQLite:     极度宽松（动态类型），任何列可存任何类型

对引擎开发者的启示:
  隐式类型转换需要谨慎设计。PostgreSQL 的严格路线虽然"不友好"，
  但避免了大量生产事故。如果要支持隐式转换，至少应该:
  1. 确保转换不导致索引失效（双向兼容）
  2. 截断时产生 ERROR 而非 WARNING

## 版本演进总结

MySQL 5.6:    FLOAT(M,D)/DOUBLE(M,D) 仍为标准用法
MySQL 8.0.17: UNSIGNED 浮点/定点废弃，显示宽度废弃，FLOAT(M,D) 废弃
MySQL 8.0:    AUTO_INCREMENT 持久化到 redo log（不再重启回退）

实践建议:
  1. 主键用 BIGINT，不要用 INT
  2. 金额用 DECIMAL，不要用 FLOAT/DOUBLE
  3. 不要用 UNSIGNED，用 CHECK (val >= 0) 替代
  4. 不要依赖 INT(11) 的显示宽度
  5. BOOLEAN 列用 TINYINT(1) + CHECK (val IN (0, 1)) 约束
