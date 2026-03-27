# INTERSECT ALL / EXCEPT ALL / MULTISET 语义

SQL 标准定义的集合操作 ALL 变体——保留重复行的交集与差集，多数引擎长期缺失的特性。

## 支持矩阵

| 引擎 | UNION ALL | INTERSECT ALL | EXCEPT ALL | 版本 |
|------|-----------|---------------|------------|------|
| PostgreSQL | 支持 | 支持 | 支持 | 8.0+ (早期) |
| Oracle | 支持 | 支持 | 支持 | 21c+ (2021) |
| MySQL | 支持 | 支持 | 支持 | 8.0.31+ (2022) |
| MariaDB | 支持 | 支持 | 支持 | 10.3+ |
| DB2 | 支持 | 支持 | 支持 | 早期 |
| SQLite | 支持 | 不支持 | 不支持 | - |
| DuckDB | 支持 | 支持 | 支持 | 0.3.0+ |
| SQL Server | 支持 | 不支持 | 不支持 | - |
| ClickHouse | 支持 | 支持 (默认) | 支持 (默认) | 21.8+ |
| BigQuery | 支持 | 不支持 | 不支持 | - |
| Snowflake | 支持 | 不支持 | 不支持 | - |
| Trino | 支持 | 支持 | 支持 | 早期 |
| Spark SQL | 支持 | 支持 | 支持 | 2.0+ |
| Hive | 支持 | 不支持 | 不支持 | - |

## SQL 标准定义

SQL:1992 定义了四种集合操作及其 ALL/DISTINCT 变体：

| 操作 | 默认行为 | ALL 变体 |
|------|---------|---------|
| `UNION` | 去重 | `UNION ALL` 保留所有行 |
| `INTERSECT` | 去重 | `INTERSECT ALL` 保留重复 |
| `EXCEPT` | 去重 | `EXCEPT ALL` 保留重复 |

标准还使用了"multiset"（多重集合）的概念来描述 ALL 语义：结果中每个值的出现次数由两侧出现次数决定。

## 设计动机

### 问题: 无 ALL 变体时丢失重要信息

考虑两个表，记录不同仓库的库存：

```sql
-- 仓库 A 的商品
warehouse_a: [苹果, 苹果, 苹果, 香蕉, 香蕉]

-- 仓库 B 的商品
warehouse_b: [苹果, 苹果, 香蕉, 香蕉, 香蕉]
```

**INTERSECT（去重）**: `{苹果, 香蕉}` —— 只知道两个仓库都有苹果和香蕉，丢失了数量信息。

**INTERSECT ALL**: `{苹果, 苹果, 香蕉, 香蕉}` —— 保留了重叠的数量（两个仓库都至少有 2 个苹果和 2 个香蕉）。

### ALL 变体的精确语义

对于值 v，设 `count_A(v)` 为 v 在 A 中的出现次数，`count_B(v)` 为 v 在 B 中的出现次数：

| 操作 | 结果中 v 的出现次数 |
|------|-------------------|
| `A UNION ALL B` | `count_A(v) + count_B(v)` |
| `A INTERSECT ALL B` | `MIN(count_A(v), count_B(v))` |
| `A EXCEPT ALL B` | `MAX(count_A(v) - count_B(v), 0)` |

```sql
-- 具体例子
-- A = {1, 1, 1, 2, 2, 3}
-- B = {1, 1, 2, 2, 2, 4}

-- A INTERSECT ALL B = {1, 1, 2, 2}    -- MIN(3,2)=2个1, MIN(2,3)=2个2
-- A EXCEPT ALL B    = {1, 3}           -- MAX(3-2,0)=1个1, MAX(1-0,0)=1个3
-- B EXCEPT ALL A    = {2, 4}           -- MAX(3-2,0)=1个2, MAX(1-0,0)=1个4
```

## 语法对比

### PostgreSQL（最早的完整支持者之一）

```sql
-- INTERSECT ALL: 保留重复的交集
SELECT item FROM warehouse_a
INTERSECT ALL
SELECT item FROM warehouse_b;

-- EXCEPT ALL: 保留重复的差集
SELECT item FROM warehouse_a
EXCEPT ALL
SELECT item FROM warehouse_b;

-- 与 DISTINCT 变体对比
SELECT item FROM warehouse_a
INTERSECT          -- 等同于 INTERSECT DISTINCT
SELECT item FROM warehouse_b;

-- 多个集合操作的组合（优先级: INTERSECT > UNION/EXCEPT）
SELECT id FROM a
UNION ALL
SELECT id FROM b
INTERSECT ALL
SELECT id FROM c;
-- 等同于: a UNION ALL (b INTERSECT ALL c)
```

### Oracle 21c+

```sql
-- Oracle 在 21c 版本终于加入 ALL 变体
SELECT item FROM warehouse_a
INTERSECT ALL
SELECT item FROM warehouse_b;

SELECT item FROM warehouse_a
EXCEPT ALL       -- Oracle 21c 也支持 EXCEPT（之前只有 MINUS）
SELECT item FROM warehouse_b;

-- Oracle 传统语法 MINUS 的 ALL 变体
SELECT item FROM warehouse_a
MINUS ALL
SELECT item FROM warehouse_b;
```

### MySQL 8.0.31+

```sql
-- MySQL 8.0.31 (2022年10月) 新增 INTERSECT 和 EXCEPT
-- 同时支持 ALL 和 DISTINCT 变体
SELECT item FROM warehouse_a
INTERSECT ALL
SELECT item FROM warehouse_b;

SELECT item FROM warehouse_a
EXCEPT ALL
SELECT item FROM warehouse_b;
```

### ClickHouse（默认 ALL 语义）

```sql
-- ClickHouse 的 INTERSECT/EXCEPT 默认就是 ALL 语义!
-- 这与 SQL 标准的默认行为相反
SELECT item FROM warehouse_a
INTERSECT
SELECT item FROM warehouse_b;
-- 等同于其他引擎的 INTERSECT ALL

-- 要去重需要显式 DISTINCT
SELECT item FROM warehouse_a
INTERSECT DISTINCT
SELECT item FROM warehouse_b;
```

这是 ClickHouse 的一个独特设计选择，与其 UNION 的默认行为一致（ClickHouse 中 UNION 也默认 DISTINCT，但提供 UNION ALL）。需要特别注意迁移兼容性。

### SQL Server（不支持 ALL 变体）

```sql
-- SQL Server 只支持无 ALL 的版本
SELECT item FROM warehouse_a
INTERSECT
SELECT item FROM warehouse_b;

SELECT item FROM warehouse_a
EXCEPT
SELECT item FROM warehouse_b;

-- 无法写: INTERSECT ALL 或 EXCEPT ALL
```

## 替代方案: 不支持 ALL 时的模拟

### 方案 1: ROW_NUMBER + JOIN

```sql
-- 模拟 INTERSECT ALL
WITH a_numbered AS (
    SELECT item, ROW_NUMBER() OVER (PARTITION BY item ORDER BY item) AS rn
    FROM warehouse_a
),
b_numbered AS (
    SELECT item, ROW_NUMBER() OVER (PARTITION BY item ORDER BY item) AS rn
    FROM warehouse_b
)
SELECT a.item
FROM a_numbered a
JOIN b_numbered b ON a.item = b.item AND a.rn = b.rn;

-- 模拟 EXCEPT ALL
WITH a_numbered AS (
    SELECT item, ROW_NUMBER() OVER (PARTITION BY item ORDER BY item) AS rn
    FROM warehouse_a
),
b_numbered AS (
    SELECT item, ROW_NUMBER() OVER (PARTITION BY item ORDER BY item) AS rn
    FROM warehouse_b
)
SELECT a.item
FROM a_numbered a
LEFT JOIN b_numbered b ON a.item = b.item AND a.rn = b.rn
WHERE b.item IS NULL;
```

### 方案 2: 聚合计数

```sql
-- 模拟 INTERSECT ALL（更直观但需要 lateral 或交叉连接展开）
WITH counts AS (
    SELECT item, LEAST(a_cnt, b_cnt) AS result_cnt
    FROM (
        SELECT item, COUNT(*) AS a_cnt FROM warehouse_a GROUP BY item
    ) a
    JOIN (
        SELECT item, COUNT(*) AS b_cnt FROM warehouse_b GROUP BY item
    ) b USING (item)
)
-- 需要再展开 result_cnt 次...（实际操作很繁琐）
```

ROW_NUMBER 方案更实用，但性能不如原生 INTERSECT ALL（需要额外的排序和 JOIN）。

## 实际应用场景

```sql
-- 场景 1: 订单对账——找出系统 A 多出的记录（含重复）
SELECT order_id, amount, order_date
FROM system_a_orders
EXCEPT ALL
SELECT order_id, amount, order_date
FROM system_b_orders;

-- 场景 2: 数据迁移验证——确认两个系统数据完全一致
-- 如果以下两个查询都返回空，则数据一致
SELECT * FROM old_system EXCEPT ALL SELECT * FROM new_system;
SELECT * FROM new_system EXCEPT ALL SELECT * FROM old_system;

-- 场景 3: 库存重叠分析
SELECT product_id FROM store_a_inventory
INTERSECT ALL
SELECT product_id FROM store_b_inventory;
-- 结果反映实际可匹配的库存数量
```

## 对引擎开发者的实现建议

### 1. 语法解析

集合操作的语法需要支持可选的 ALL/DISTINCT 修饰符：

```
set_operation:
    query_term (UNION | INTERSECT | EXCEPT) [ALL | DISTINCT] query_term
```

默认行为（无修饰符时）按 SQL 标准应为 DISTINCT。

### 2. 实现策略

#### 策略 A: 排序合并（Sort-Merge）

```
1. 对两个输入按所有列排序
2. 双指针合并扫描:
   - INTERSECT ALL: 两边都有时输出，输出次数 = MIN(左次数, 右次数)
   - EXCEPT ALL: 左边有但右边没有时输出，输出次数 = MAX(左次数 - 右次数, 0)
```

优点: 内存占用小，适合大数据量。缺点: 需要排序。

#### 策略 B: 哈希计数（Hash Aggregate）

```
1. 扫描右侧输入，构建 HashMap<行, 计数>
2. 扫描左侧输入:
   - INTERSECT ALL: 如果在 map 中且计数 > 0，输出并将计数减 1
   - EXCEPT ALL: 如果不在 map 中或计数 = 0，直接输出；否则将计数减 1 不输出
```

优点: 无需排序，流式输出。缺点: 右侧输入需要完全加载到内存。

#### 策略对比

| 策略 | 时间复杂度 | 空间复杂度 | 适用场景 |
|------|-----------|-----------|---------|
| 排序合并 | O(n log n) | O(1) 额外 | 两侧数据量都大 |
| 哈希计数 | O(n) | O(右侧大小) | 右侧数据量较小 |

### 3. NULL 处理

集合操作中 NULL 的比较遵循特殊规则——两个 NULL 被视为相等（与 WHERE 中的行为不同）：

```sql
-- 在集合操作中 NULL = NULL
SELECT NULL INTERSECT ALL SELECT NULL;
-- 返回 1 行 NULL

-- 但在 WHERE 中
WHERE NULL = NULL  -- 返回 UNKNOWN (false)
```

实现时，集合操作的比较函数需要使用 "NULL-safe equals"（即 IS NOT DISTINCT FROM 语义）。

### 4. 优先级

SQL 标准定义 INTERSECT 的优先级高于 UNION 和 EXCEPT：

```sql
A UNION ALL B INTERSECT ALL C
-- 解析为: A UNION ALL (B INTERSECT ALL C)
-- 不是: (A UNION ALL B) INTERSECT ALL C
```

Parser 需要正确处理优先级，或要求用户用括号显式指定。

### 5. 与现有 DISTINCT 优化的复用

INTERSECT/EXCEPT（不带 ALL）本质上是先做 ALL 操作再去重。引擎可以复用已有的 DISTINCT 算子：

```
INTERSECT = INTERSECT ALL + DISTINCT
EXCEPT    = EXCEPT ALL    + DISTINCT
```

或者反过来，如果已经实现了 DISTINCT 版本，ALL 版本需要额外的计数逻辑。

## 参考资料

- SQL:1992 标准: ISO/IEC 9075:1992 Section 7.10 `<query expression>`
- PostgreSQL: [UNION, INTERSECT, EXCEPT](https://www.postgresql.org/docs/current/sql-select.html#SQL-UNION)
- Oracle 21c: [Set Operators](https://docs.oracle.com/en/database/oracle/oracle-database/21/sqlrf/Set-Operators.html)
- MySQL 8.0.31: [INTERSECT/EXCEPT](https://dev.mysql.com/doc/refman/8.0/en/intersect.html)
- ClickHouse: [Set Operations](https://clickhouse.com/docs/en/sql-reference/statements/select/intersect)
