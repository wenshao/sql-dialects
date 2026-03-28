# SQLite: 条件函数

> 参考资料:
> - [SQLite Documentation - CASE Expression](https://www.sqlite.org/lang_expr.html#case)
> - [SQLite Documentation - Core Functions](https://www.sqlite.org/lang_corefunc.html)

## CASE 表达式（标准 SQL）

简单 CASE
```sql
SELECT username, CASE status
    WHEN 0 THEN 'inactive'
    WHEN 1 THEN 'active'
    WHEN 2 THEN 'suspended'
    ELSE 'unknown'
END AS status_text
FROM users;
```

搜索 CASE
```sql
SELECT username, CASE
    WHEN age < 18 THEN 'minor'
    WHEN age < 65 THEN 'adult'
    ELSE 'senior'
END AS age_group
FROM users;
```

## NULL 处理函数

COALESCE（返回第一个非 NULL 值）
```sql
SELECT COALESCE(nickname, username, 'anonymous') FROM users;
```

IFNULL（COALESCE 的两参数简化版，SQLite/MySQL 特有）
```sql
SELECT IFNULL(email, 'no email') FROM users;
```

NULLIF（两值相等时返回 NULL）
```sql
SELECT NULLIF(denominator, 0) FROM data;  -- 避免除零: x / NULLIF(d, 0)

-- IIF（三元条件，3.32.0+）
SELECT IIF(age >= 18, 'adult', 'minor') FROM users;
```

等价于: CASE WHEN age >= 18 THEN 'adult' ELSE 'minor' END

## typeof（SQLite 独有的类型检查函数）

由于 SQLite 是动态类型，typeof 用于运行时类型检查:
```sql
SELECT typeof(42);          -- 'integer'
SELECT typeof(3.14);        -- 'real'
SELECT typeof('hello');     -- 'text'
SELECT typeof(NULL);        -- 'null'
SELECT typeof(x'AB');       -- 'blob'

-- 结合 CASE 按实际类型处理:
SELECT CASE typeof(value)
    WHEN 'integer' THEN 'Number: ' || CAST(value AS TEXT)
    WHEN 'text' THEN 'String: ' || value
    WHEN 'null' THEN 'NULL'
    ELSE 'Other: ' || typeof(value)
END FROM data;
```

## 对比与引擎开发者启示

SQLite 条件函数的特点:
- (1) CASE / COALESCE / NULLIF / IFNULL → 标准 SQL
- (2) IIF → 3.32.0+ 三元条件（简洁）
- (3) typeof → 动态类型系统的必需品

缺少:
- GREATEST / LEAST → 需要嵌套 CASE 或 MAX()/MIN()
- DECODE → Oracle 特有，用 CASE 替代

对比:
- **MySQL**: IF(cond, a, b) 函数
- **PostgreSQL**: 无 IIF，用 CASE
- **ClickHouse**: if(cond, a, b) + multiIf()
- **BigQuery**: IF(cond, a, b) + IFF

对引擎开发者的启示:
  - IIF/IF 三元函数是 CASE 的有用简化，实现成本低但用户体验好。
  - typeof 对动态类型引擎是必需的（让用户知道实际存储的是什么类型）。
