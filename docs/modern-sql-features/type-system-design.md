# 类型系统设计

SQL 引擎的类型系统决定了数据验证的严格程度、隐式转换的范围、优化器的推理能力，是引擎最底层的设计决策之一。

## 四种类型系统流派

| 流派 | 代表引擎 | 核心特征 | 哲学 |
|------|---------|---------|------|
| 严格类型 | PostgreSQL, Trino, DuckDB | 不允许隐式转换，类型不匹配报错 | 宁可报错也不猜测 |
| 宽松类型 | MySQL, MariaDB, SQLite (WAL 模式) | 大量隐式转换，尽量不报错 | 尽量给出结果 |
| 动态类型 | SQLite | 列可以存任何类型，类型亲和性 | 存什么都行 |
| 强类型命名 | BigQuery, Snowflake | 类型名称唯一，无别名 | 消除歧义 |

## 严格类型: PostgreSQL 流派

### 核心原则

PostgreSQL 的类型系统基于一个简单的规则: **只允许安全的、无损的隐式转换**。

```sql
-- PostgreSQL: 报错！不允许字符串与整数直接运算
SELECT '1' + 2;
-- ERROR: operator does not exist: text + integer
-- HINT: No operator matches the given name and argument types.

-- 必须显式转换
SELECT '1'::integer + 2;    -- 正确: 3
SELECT CAST('1' AS integer) + 2;  -- 正确: 3

-- 整数到浮点: 允许隐式转换（安全、无损）
SELECT 1 + 2.5;  -- 正确: 3.5 (integer 隐式提升为 numeric)

-- 函数重载: 类型必须精确匹配
CREATE FUNCTION add(a integer, b integer) RETURNS integer AS $$ SELECT a + b $$ LANGUAGE sql;
CREATE FUNCTION add(a numeric, b numeric) RETURNS numeric AS $$ SELECT a + b $$ LANGUAGE sql;

SELECT add(1, 2);       -- 调用 add(integer, integer)
SELECT add(1.5, 2.5);   -- 调用 add(numeric, numeric)
SELECT add(1, 2.5);     -- integer 隐式提升为 numeric, 调用 add(numeric, numeric)
SELECT add('1', 2);     -- 报错! text 不能隐式转换为 integer
```

### 类型转换规则

PostgreSQL 将类型转换分为三类:

```
Assignment Cast (赋值转换):
  - INSERT/UPDATE 时使用
  - 允许范围略宽: varchar(10) -> varchar(5) 会截断而非报错

Implicit Cast (隐式转换):
  - 表达式中自动使用
  - 只允许无损转换: integer -> bigint, integer -> numeric

Explicit Cast (显式转换):
  - 用户明确请求: CAST() 或 ::
  - 允许所有合理的转换，包括可能丢失精度的
```

### Trino / DuckDB 的进一步严格化

```sql
-- Trino: 更加严格，连 integer + bigint 都需要注意
SELECT CAST(1 AS TINYINT) + CAST(2 AS INTEGER);
-- 结果类型是 INTEGER（小类型提升到大类型）

-- DuckDB: 类似 PostgreSQL 但更现代
-- 支持隐式的安全提升，拒绝不安全的转换
SELECT '2024-01-01'::DATE + 1;  -- 报错: 不能 DATE + INTEGER
SELECT '2024-01-01'::DATE + INTERVAL '1 day';  -- 正确
```

## 宽松类型: MySQL 流派

### 核心原则

MySQL 的类型系统追求"尽量给出结果"，宁可隐式转换产生意外值，也不报错。

```sql
-- MySQL: 字符串自动转为数字
SELECT '1' + 2;          -- 结果: 3
SELECT '1abc' + 0;       -- 结果: 1 (取前缀数字部分)
SELECT 'abc' + 0;        -- 结果: 0 (无数字前缀，转为 0)
SELECT '3.14xyz' + 0;    -- 结果: 3.14

-- 比较时的隐式转换
SELECT 0 = 'abc';        -- 结果: 1 (TRUE)! 'abc' 转为 0
SELECT 1 = '1abc';       -- 结果: 1 (TRUE)! '1abc' 转为 1

-- 这些隐式转换是安全漏洞和 bug 的常见来源
-- 例如: WHERE user_id = '0 OR 1=1'
-- user_id 是整数列时，'0 OR 1=1' 转为 0
```

### 日期处理的宽松性

```sql
-- MySQL 接受各种"可疑"的日期值
SELECT CAST('2024-02-30' AS DATE);  -- MySQL 5.x: '0000-00-00' (非法日期变零值)
                                      -- MySQL 8.0+ (STRICT): 报错

-- 日期与字符串的隐式比较
SELECT '2024-01-15' > '2024-02-01';  -- 字符串比较: FALSE (正确但不安全)
SELECT DATE '2024-01-15' > '2024-02-01';  -- 字符串隐式转日期: FALSE

-- 字符串与数字的日期混用
SELECT 20240115 + 0;     -- 结果: 20240115 (数字)
SELECT DATE '2024-01-15' + 0;  -- 结果: 20240115 (数字!)
```

### sql_mode 对类型行为的影响

```sql
-- STRICT_TRANS_TABLES (MySQL 8.0 默认开启)
SET sql_mode = 'STRICT_TRANS_TABLES';
INSERT INTO t (int_col) VALUES ('abc');  -- 报错! (非严格模式下会插入 0 并给 warning)

-- NO_ZERO_DATE: 禁止 '0000-00-00'
SET sql_mode = 'STRICT_TRANS_TABLES,NO_ZERO_DATE';
INSERT INTO t (date_col) VALUES ('0000-00-00');  -- 报错!

-- 建议: 生产环境始终开启 STRICT_TRANS_TABLES
```

## 动态类型: SQLite 流派

### 核心原则

SQLite 采用与其他数据库完全不同的方法: **类型附着在值上，而非列上**。

```sql
-- SQLite: 一列可以存储不同类型的值
CREATE TABLE test (value);  -- 不需要指定类型
INSERT INTO test VALUES (42);          -- 整数
INSERT INTO test VALUES ('hello');     -- 文本
INSERT INTO test VALUES (3.14);        -- 浮点
INSERT INTO test VALUES (x'DEADBEEF'); -- BLOB
INSERT INTO test VALUES (NULL);        -- NULL

-- 即使指定了类型，也只是"类型亲和性"(type affinity)
CREATE TABLE typed (num INTEGER, txt TEXT);
INSERT INTO typed VALUES ('hello', 42);  -- 合法! 只是"建议"
SELECT typeof(num), typeof(txt) FROM typed;
-- 结果: 'text', 'integer' (实际存储的类型)
```

### 五种类型亲和性

```
声明类型              亲和性         含义
INT, INTEGER, ...    INTEGER       尝试存为整数
CHAR, VARCHAR, ...   TEXT          尝试存为文本
BLOB, ...            BLOB          不做转换
REAL, FLOAT, ...     REAL          尝试存为浮点
(其他/无)             NUMERIC       尝试存为整数或浮点

规则: "亲和性"只是在 INSERT 时尝试转换，如果转换失败则保留原始类型。
不像其他数据库那样报错。
```

### 比较规则

```sql
-- SQLite 的比较按照以下规则:
-- 1. NULL 小于一切
-- 2. INTEGER/REAL 互相可比较
-- 3. TEXT 按排序规则比较
-- 4. BLOB 按 memcmp 比较
-- 5. 不同类型之间: INTEGER/REAL < TEXT < BLOB

SELECT 100 < '99';   -- TRUE! 数字 < 文本 (不同类型按类别排序)
SELECT 100 < 99;     -- FALSE (同类型，正常比较)
```

### 对引擎开发者的启示

SQLite 的动态类型系统极大地简化了存储引擎的实现，但给查询优化带来了挑战: 优化器无法假设列中所有值的类型一致，难以选择最优的比较函数和算法。

## 强类型命名: BigQuery 流派

### 核心原则

BigQuery 不仅要求类型严格，还消除了类型名称的歧义。

```sql
-- BigQuery: 每种类型只有一个名字
-- INT64 而非 INT/INTEGER/BIGINT/TINYINT/SMALLINT
-- FLOAT64 而非 FLOAT/DOUBLE/REAL
-- BOOL 而非 BOOLEAN
-- STRING 而非 VARCHAR/CHAR/TEXT/CLOB
-- BYTES 而非 BINARY/VARBINARY/BLOB

CREATE TABLE example (
    id INT64,
    name STRING,
    score FLOAT64,
    active BOOL,
    created TIMESTAMP
);

-- 对比 MySQL: 同一概念多种写法
CREATE TABLE example (
    id BIGINT,        -- 也可以是 INT, INTEGER, TINYINT, SMALLINT, MEDIUMINT
    name VARCHAR(255), -- 也可以是 CHAR, TEXT, TINYTEXT, MEDIUMTEXT, LONGTEXT
    score DOUBLE,      -- 也可以是 FLOAT, REAL, DECIMAL, NUMERIC
    active BOOLEAN,    -- 也可以是 TINYINT(1), BIT
    created DATETIME   -- 也可以是 TIMESTAMP, DATE
);
```

### 类型名称一致性对比

| 概念 | BigQuery | PostgreSQL | MySQL | SQL Server | Oracle |
|------|---------|-----------|-------|-----------|--------|
| 64位整数 | `INT64` | `BIGINT` / `INT8` | `BIGINT` | `BIGINT` | `NUMBER(19)` |
| 32位整数 | `INT64` (无32位) | `INTEGER` / `INT` / `INT4` | `INT` / `INTEGER` | `INT` | `NUMBER(10)` |
| 布尔 | `BOOL` | `BOOLEAN` / `BOOL` | `BOOLEAN` / `TINYINT(1)` | `BIT` | 不支持 |
| 文本 | `STRING` | `TEXT` / `VARCHAR` | `VARCHAR` / `TEXT` / `CHAR` | `VARCHAR` / `NVARCHAR` | `VARCHAR2` / `CLOB` |
| 二进制 | `BYTES` | `BYTEA` | `VARBINARY` / `BLOB` | `VARBINARY` | `RAW` / `BLOB` |

### Snowflake 的中间路线

```sql
-- Snowflake: 接受别名但有规范名称
-- 以下都合法，但内部统一为 NUMBER
CREATE TABLE t (
    a INT,          -- -> NUMBER(38,0)
    b INTEGER,      -- -> NUMBER(38,0)
    c BIGINT,       -- -> NUMBER(38,0)
    d SMALLINT,     -- -> NUMBER(38,0)
    e TINYINT       -- -> NUMBER(38,0)
);
-- 所有整数类型在内部都是 NUMBER(38,0)，别名只是语法糖
```

## 隐式转换矩阵的实现

### 转换矩阵的设计

引擎开发者需要定义一个类型转换矩阵，指定每对类型之间是否可以隐式转换:

```
              目标类型
             BOOL  INT  BIGINT  FLOAT  DECIMAL  STRING  DATE  TIMESTAMP
源   BOOL     -     N     N       N      N        E       N      N
类   INT      N     -     I       I      I        E       N      N
型   BIGINT   N     A     -       I      I        E       N      N
     FLOAT    N     E     E       -      E        E       N      N
     DECIMAL  N     E     E       I      -        E       N      N
     STRING   E     E     E       E      E        -       E      E
     DATE     N     N     N       N      N        E       -      I
     TIMESTAMP N    N     N       N      N        E       A      -

I = Implicit (隐式，自动执行)
A = Assignment (赋值时允许，表达式中不允许)
E = Explicit only (必须显式 CAST)
N = Not allowed (不允许，即使显式也不行)
- = 同类型，无需转换
```

### 类型提升优先级

当二元运算符的两侧类型不同时，需要一个"公共类型"(common type)规则:

```
规则: 两侧都提升到"更大"的类型

优先级 (从低到高):
  BOOL < TINYINT < SMALLINT < INT < BIGINT < DECIMAL < FLOAT < DOUBLE

示例:
  INT + BIGINT    -> BIGINT + BIGINT   (INT 提升)
  INT + DECIMAL   -> DECIMAL + DECIMAL (INT 提升)
  INT + DOUBLE    -> DOUBLE + DOUBLE   (INT 提升)
  DECIMAL + FLOAT -> DOUBLE + DOUBLE   (两侧都提升)

字符串与数字:
  严格类型: 报错，不存在公共类型
  宽松类型: 字符串转为数字
```

### 实现代码结构

```
// 伪代码: 类型推导
function resolveCommonType(left: Type, right: Type): Type {
    if (left == right) return left;

    // 检查隐式转换矩阵
    if (canImplicitCast(left, right)) return right;
    if (canImplicitCast(right, left)) return left;

    // 检查是否存在公共上级类型
    let common = findCommonSuperType(left, right);
    if (common != null) return common;

    // 严格模式: 报错
    throw TypeError("No common type for " + left + " and " + right);

    // 宽松模式: 尝试 fallback 规则
    // return STRING;  // 万物皆可转字符串
}
```

## 类型系统对优化器的影响

### 1. 谓词下推的类型约束

```sql
-- 表: orders(order_date DATE, amount DECIMAL(10,2))
-- 查询:
SELECT * FROM orders WHERE order_date = '2024-01-15';

-- 严格类型引擎:
--   '2024-01-15' 是 STRING，order_date 是 DATE
--   如果不允许隐式转换，必须报错或要求用户写 DATE '2024-01-15'
--   优化器可以确定过滤精确命中 DATE 索引

-- 宽松类型引擎:
--   隐式将 '2024-01-15' 转为 DATE
--   但如果列上有函数索引 idx(CAST(order_date AS VARCHAR))，
--   优化器需要判断是先转换再比较还是直接用 DATE 索引
```

### 2. JOIN 条件的类型不一致

```sql
-- 表 A: users(id INT), 表 B: orders(user_id BIGINT)
SELECT * FROM users u JOIN orders o ON u.id = o.user_id;

-- 严格类型: INT 可以安全提升到 BIGINT，JOIN 可以使用索引
-- 宽松类型: 同上，但还允许 id VARCHAR JOIN user_id INT
--   此时需要对一侧做 CAST，可能导致索引失效

-- 经典 MySQL 问题:
-- WHERE varchar_col = 12345
-- MySQL 将 varchar_col 逐行转为数字来比较，而非将 12345 转为字符串
-- 导致全表扫描 (索引失效)!
```

### 3. 聚合函数的返回类型推导

```sql
-- SUM(INT) 应该返回什么类型？
-- PostgreSQL: BIGINT (防止溢出)
-- MySQL: BIGINT (SIGNED) 或 DECIMAL
-- BigQuery: INT64 (可能溢出报错)

-- AVG(INT) 应该返回什么类型？
-- PostgreSQL: NUMERIC (精确)
-- MySQL: DECIMAL (精确)
-- BigQuery: FLOAT64 (近似)
-- 这个选择影响计算结果的精度
```

### 4. 表达式折叠的安全性

```sql
-- 常量折叠: 编译期计算常量表达式
SELECT * FROM t WHERE col > 100 + 200;
-- 优化为: SELECT * FROM t WHERE col > 300;

-- 但类型转换可能改变语义:
SELECT * FROM t WHERE float_col > 1/3;
-- 如果 1/3 在编译期用 INT 除法 = 0，则语义错误
-- 应该提升为 FLOAT: 1.0/3.0 = 0.333...

-- 严格类型系统让折叠规则更明确
-- 宽松类型系统需要更多 edge case 处理
```

## Trade-off 分析: 引擎开发者该选哪种？

### 各方案对比

| 维度 | 严格类型 | 宽松类型 | 动态类型 | 强类型命名 |
|------|---------|---------|---------|-----------|
| 用户学习成本 | 高 | 低 | 低 | 中 |
| Bug 预防 | 强 | 弱 | 弱 | 强 |
| 迁移兼容性 | 低 | 高 (MySQL) | 低 | 低 |
| 优化器实现 | 简单 | 复杂 | 很复杂 | 简单 |
| 存储引擎实现 | 中等 | 中等 | 简单 | 中等 |
| 生态工具支持 | 好 | 好 | 好 | 中等 |

### 推荐策略

```
1. 新引擎: 选择严格类型 + 少量安全隐式转换
   - 效仿 PostgreSQL 或 Trino 的模型
   - 只允许无损的数值提升 (INT -> BIGINT -> DECIMAL)
   - 字符串与其他类型之间不允许隐式转换
   - 好处: 优化器实现简单，bug 少，用户代码质量高

2. MySQL 兼容引擎: 被迫选择宽松类型
   - TiDB, OceanBase, StarRocks 的 MySQL 协议兼容
   - 必须复刻 MySQL 的隐式转换规则
   - 建议: 内部用严格类型实现，外层加兼容适配层

3. 多方言引擎: 类型系统可配置
   - 提供 strict_mode / compatible_mode 开关
   - 内部统一为严格类型，按配置决定是否注入隐式转换规则
```

### 类型别名的处理建议

```
建议: 内部使用规范化类型 (BigQuery 风格)，在 parser 层做别名映射

Parser 别名表:
  INT, INTEGER            -> INT32
  BIGINT, INT8            -> INT64
  FLOAT, REAL             -> FLOAT32
  DOUBLE, DOUBLE PRECISION -> FLOAT64
  VARCHAR(n), CHAR(n)     -> STRING(n)
  TEXT, CLOB              -> STRING(MAX)
  BOOLEAN, BOOL           -> BOOL

好处:
  - 内部类型推导和比较只需处理一组类型
  - 减少 switch/case 分支
  - DDL 序列化/反序列化统一
  - SHOW CREATE TABLE 输出一致
```

## 实际案例: 类型系统设计失误

### MySQL 的 TINYINT(1) 困境

```sql
-- MySQL 用 TINYINT(1) 表示 BOOLEAN
CREATE TABLE t (active BOOLEAN);  -- 实际存储: TINYINT(1)

-- 但 TINYINT(1) 本质是整数
INSERT INTO t VALUES (42);   -- 合法!
SELECT active FROM t;        -- 42, 不是 TRUE/FALSE

-- 应用层 ORM 的混乱:
-- Java JDBC: getBoolean() vs getInt()?
-- Python: True/False vs 0/1?
-- 不同 driver 行为不一致
```

### Oracle 没有 BOOLEAN 的后果

```sql
-- Oracle 直到 23c 才在 SQL 中支持 BOOLEAN (PL/SQL 早就有了)
-- 数十年来开发者被迫用:
active NUMBER(1)        -- 0/1
active CHAR(1)          -- 'Y'/'N'
active VARCHAR2(5)      -- 'TRUE'/'FALSE'

-- 没有统一标准，每个项目、每个 ORM 自己选择
-- 导致大量的转换逻辑和不一致性
```

### PostgreSQL 的 TEXT vs VARCHAR 讨论

```sql
-- PostgreSQL 中 TEXT 和 VARCHAR 性能完全一致
-- VARCHAR(n) 只是增加了长度检查
-- 内部实现: 都是 varlena (变长存储)

-- 推荐: 直接用 TEXT，除非业务上确实需要长度限制
-- 这是 PostgreSQL 社区与传统 DBA 习惯的冲突
```

## 对引擎开发者的总结

### 类型系统设计清单

```
1. 基础类型集:
   [ ] 整数: INT8/16/32/64, UINT8/16/32/64 (是否支持无符号?)
   [ ] 浮点: FLOAT32, FLOAT64
   [ ] 精确小数: DECIMAL(p, s)
   [ ] 布尔: BOOL (独立类型 vs 整数别名?)
   [ ] 字符串: STRING (定长 vs 变长? 最大长度?)
   [ ] 二进制: BYTES
   [ ] 日期时间: DATE, TIME, TIMESTAMP, INTERVAL
   [ ] 复杂类型: ARRAY, MAP, STRUCT, JSON

2. 隐式转换规则:
   [ ] 定义类型转换矩阵
   [ ] 定义公共类型提升规则
   [ ] 定义赋值转换规则 (INSERT/UPDATE)

3. 优化器集成:
   [ ] 类型推导 (expression type inference)
   [ ] 常量折叠的类型安全
   [ ] 索引匹配的类型检查
   [ ] JOIN 条件的类型对齐

4. 兼容性:
   [ ] 类型别名映射表
   [ ] 方言模式切换 (strict / compatible)
   [ ] DDL 语法解析与类型规范化
```

## 参考资料

- PostgreSQL: [Type Conversion](https://www.postgresql.org/docs/current/typeconv.html)
- MySQL: [Type Conversion in Expression Evaluation](https://dev.mysql.com/doc/refman/8.0/en/type-conversion.html)
- SQLite: [Datatypes In SQLite](https://www.sqlite.org/datatype3.html)
- BigQuery: [Data Types](https://cloud.google.com/bigquery/docs/reference/standard-sql/data-types)
- Trino: [Type System](https://trino.io/docs/current/develop/types.html)
- SQL Standard: ISO/IEC 9075-2 Section 9 "Data type conversions"
