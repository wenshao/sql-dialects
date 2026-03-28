# Oracle: 条件函数

> 参考资料:
> - [Oracle SQL Language Reference - CASE Expressions](https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/CASE-Expressions.html)
> - [Oracle SQL Language Reference - DECODE](https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/DECODE.html)

## CASE WHEN（SQL 标准）

搜索 CASE
```sql
SELECT username,
    CASE
        WHEN age < 18 THEN 'minor'
        WHEN age < 65 THEN 'adult'
        ELSE 'senior'
    END AS category
FROM users;
```

简单 CASE
```sql
SELECT username,
    CASE status
        WHEN 0 THEN 'inactive'
        WHEN 1 THEN 'active'
        ELSE 'unknown'
    END AS status_name
FROM users;
```

## DECODE（Oracle 独有，pre-CASE 遗留函数）

```sql
SELECT username,
    DECODE(status, 0, 'inactive', 1, 'active', 2, 'deleted', 'unknown') AS status_name
FROM users;
```

设计分析: DECODE vs CASE
  DECODE 是 Oracle 在 SQL 标准引入 CASE (SQL:1992) 之前的解决方案。
  DECODE(expr, val1, result1, val2, result2, ..., default)

DECODE 的独特行为:
  1. DECODE 将 NULL = NULL 视为 TRUE!（与 SQL 标准的 NULL 比较不同）
     DECODE(NULL, NULL, 'match', 'no match') → 'match'
     CASE WHEN NULL = NULL THEN 'match' ... → 'no match' (UNKNOWN)
  2. 由于 '' = NULL，DECODE('', NULL, 'match') → 'match'

横向对比:
  Oracle:     DECODE（独有，NULL 比较为 TRUE）
  MySQL:      IF(cond, true_val, false_val)（非标准，但直观）
  SQL Server: IIF(cond, true_val, false_val)（2012+）
  所有数据库: CASE WHEN（SQL 标准）

> **建议**: 新代码使用 CASE WHEN，DECODE 仅在维护旧代码时使用。

## NVL / NVL2（Oracle 独有 NULL 处理函数）

NVL(expr, replacement): 如果 expr 为 NULL 返回 replacement
```sql
SELECT NVL(phone, 'N/A') FROM users;
```

NVL2(expr, not_null_val, null_val): 三参数版本
```sql
SELECT NVL2(phone, 'has phone', 'no phone') FROM users;
```

横向对比:
  Oracle:     NVL(a, b) / NVL2(a, b, c)
  MySQL:      IFNULL(a, b)
  PostgreSQL: COALESCE(a, b)（标准）
  SQL Server: ISNULL(a, b)

> **注意**: 所有数据库都支持 COALESCE（SQL 标准），但:
NVL 和 COALESCE 有微妙的区别:
  NVL(a, b) 总是计算 b，即使 a 不为 NULL
  COALESCE(a, b) 短路求值: 如果 a 不为 NULL，不计算 b
  当 b 是昂贵的子查询时，COALESCE 更高效

## COALESCE / NULLIF（SQL 标准）

```sql
SELECT COALESCE(phone, email, 'unknown') FROM users;
SELECT NULLIF(age, 0) FROM users;  -- 如果 age = 0 返回 NULL
```

## GREATEST / LEAST

```sql
SELECT GREATEST(1, 3, 2) FROM DUAL;             -- 3
SELECT LEAST(1, 3, 2) FROM DUAL;                 -- 1

-- Oracle 的 GREATEST/LEAST 在参数包含 NULL 时返回 NULL!
SELECT GREATEST(1, NULL, 3) FROM DUAL;           -- NULL (不是 3)

-- 横向对比:
--   Oracle:     GREATEST/LEAST 有 NULL → 结果为 NULL
--   PostgreSQL: 同 Oracle
--   MySQL:      GREATEST/LEAST 忽略 NULL（返回非 NULL 值中的最大/最小）
-- 由于 '' = NULL，GREATEST('a', '', 'b') 在 Oracle 中返回 NULL
```

## LNNVL: Oracle 独有的 NULL 友好条件函数

LNNVL 返回条件为 FALSE 或 UNKNOWN(NULL) 的行
```sql
SELECT * FROM users WHERE LNNVL(age > 18);
```

等价于: WHERE age <= 18 OR age IS NULL

场景: 简化包含 NULL 的否定条件
传统写法: WHERE NOT (age > 18) OR age IS NULL
LNNVL:    WHERE LNNVL(age > 18)

## '' = NULL 对条件函数的全面影响

NVL 与空字符串:
```sql
SELECT NVL('', 'default') FROM DUAL;           -- 'default'（因为 '' = NULL）
-- 其他数据库: NVL/IFNULL/ISNULL('', 'default') → ''（空字符串不是 NULL）

-- DECODE 与空字符串:
SELECT DECODE('', NULL, 'is null', 'not null') FROM DUAL;  -- 'is null'

-- COALESCE 与空字符串:
SELECT COALESCE('', 'fallback') FROM DUAL;     -- 'fallback'

-- 这是 Oracle 迁移中最大的痛点:
-- 应用依赖 '' != NULL 的逻辑在 Oracle 中全部失效
```

## ORA_HASH / DUMP（诊断函数）

ORA_HASH: 计算哈希值（用于分桶、采样）
```sql
SELECT ORA_HASH(username) FROM users;
SELECT ORA_HASH(username, 9) FROM users;        -- 映射到 0-9（10 个桶）
```

DUMP: 显示值的内部表示（调试利器）
```sql
SELECT DUMP('hello') FROM DUAL;
-- Typ=96 Len=5: 104,101,108,108,111

SELECT DUMP(SYSDATE) FROM DUAL;
```

显示日期的内部 7 字节表示

## 对引擎开发者的总结

1. DECODE 将 NULL = NULL 视为 TRUE，这与 SQL 标准 CASE 行为不同，是迁移障碍。
2. NVL 不短路求值（总是计算两个参数），COALESCE 短路求值，性能差异显著。
3. LNNVL 是 Oracle 独有的 NULL 友好条件函数，简化了含 NULL 的否定逻辑。
### '' = NULL 影响所有条件函数: NVL、COALESCE、DECODE、GREATEST/LEAST。

5. ORA_HASH 对分桶和采样有用，引擎应内置类似的哈希函数。
