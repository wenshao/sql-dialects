# MySQL → Oracle 迁移指南

MySQL 到 Oracle 的迁移通常发生在企业级升级或合规要求场景。两者差异巨大，本文档列出所有关键修改点。

## 核心差异总览

| 维度 | MySQL | Oracle | 迁移影响 |
|------|-------|--------|---------|
| 空字符串语义 | `'' ≠ NULL` | `'' = NULL` ！ | **极高**: 所有空字符串逻辑需要重写 |
| DUAL 表 | 不需要（可选） | SELECT 常量必须 FROM DUAL | **高**: 所有常量查询需加 DUAL |
| 自增 | AUTO_INCREMENT | SEQUENCE + TRIGGER / IDENTITY(12c+) | **高**: DDL 全面重写 |
| 分页 | LIMIT / OFFSET | FETCH FIRST(12c+) / ROWNUM(旧) | **高**: 分页逻辑重写 |
| 字符串拼接 | CONCAT() | `\|\|` 运算符 | **中**: CONCAT 只接受 2 个参数 |
| 大小写 | 表名默认小写 | 表名默认大写 | **中**: 标识符引用需注意 |

## 最高风险: '' = NULL

```sql
-- MySQL: '' 和 NULL 是不同的
SELECT * FROM users WHERE name = '';          -- 匹配空字符串行
SELECT * FROM users WHERE name IS NULL;       -- 匹配 NULL 行
SELECT LENGTH('');                            -- 0
SELECT COALESCE('', 'default');               -- '' (空字符串)

-- Oracle: '' 就是 NULL！
SELECT * FROM users WHERE name = '';          -- 不匹配任何行！
SELECT * FROM users WHERE name IS NULL;       -- 匹配空字符串和 NULL 行
SELECT LENGTH('');                            -- NULL (不是 0!)
SELECT COALESCE('', 'default');               -- 'default'
SELECT '' || 'hello';                         -- 'hello' (NULL || x = x in concat)
```

**迁移策略**:
- 所有 `WHERE col = ''` 改为 `WHERE col IS NULL`
- 所有 `WHERE col != ''` 改为 `WHERE col IS NOT NULL`
- `COALESCE(col, '')` 在 Oracle 中可能返回意外结果
- 应用层的空字符串/NULL 判断逻辑全部需要审查

## DDL 迁移

### 数据类型映射

| MySQL | Oracle | 说明 |
|-------|--------|------|
| `TINYINT` | `NUMBER(3)` | Oracle 用 NUMBER 统一 |
| `SMALLINT` | `NUMBER(5)` | |
| `INT` | `NUMBER(10)` | |
| `BIGINT` | `NUMBER(19)` | |
| `FLOAT` | `BINARY_FLOAT` | 或 NUMBER |
| `DOUBLE` | `BINARY_DOUBLE` | 或 NUMBER |
| `DECIMAL(M,D)` | `NUMBER(M,D)` | 直接映射 |
| `VARCHAR(N)` | `VARCHAR2(N CHAR)` | 注意: 默认是字节！加 CHAR |
| `TEXT` | `CLOB` | Oracle 无 TEXT |
| `MEDIUMTEXT/LONGTEXT` | `CLOB` | |
| `BLOB` | `BLOB` | 直接映射 |
| `DATETIME` | `TIMESTAMP` | Oracle DATE 包含时间 |
| `TIMESTAMP` | `TIMESTAMP WITH TIME ZONE` | |
| `DATE` | `DATE` | Oracle DATE 包含时间！ |
| `TIME` | `INTERVAL DAY TO SECOND` | Oracle 无 TIME 类型 |
| `BOOLEAN` / `TINYINT(1)` | `BOOLEAN`(23ai+) / `NUMBER(1)` + CHECK | Oracle 23ai 引入原生 BOOLEAN；之前无 SQL 层 BOOLEAN |
| `ENUM(...)` | `VARCHAR2 + CHECK` | Oracle 无 ENUM |
| `JSON` | `JSON`(21c+) / `CLOB + IS JSON` | |
| `BIT(N)` | `RAW(N)` | |

### 自增主键

```sql
-- MySQL
CREATE TABLE users (
    id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY
);

-- Oracle 12c+ (IDENTITY，推荐)
CREATE TABLE users (
    id NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY
);

-- Oracle 传统方式 (SEQUENCE + TRIGGER)
CREATE SEQUENCE users_seq START WITH 1 INCREMENT BY 1;
CREATE TABLE users (id NUMBER PRIMARY KEY);
CREATE TRIGGER users_trg BEFORE INSERT ON users
FOR EACH ROW BEGIN :NEW.id := users_seq.NEXTVAL; END;
/
```

### 注释

```sql
-- MySQL: 内联 COMMENT
CREATE TABLE users (
    id BIGINT COMMENT '用户ID'
) COMMENT='用户表';

-- Oracle: 独立 COMMENT ON 语句
CREATE TABLE users (id NUMBER);
COMMENT ON TABLE users IS '用户表';
COMMENT ON COLUMN users.id IS '用户ID';
```

## DML 迁移

### INSERT

| MySQL | Oracle | 说明 |
|-------|--------|------|
| `INSERT INTO t VALUES (...)` | 相同 | |
| 多行 VALUES | `INSERT ALL INTO t VALUES (...) INTO t VALUES (...) SELECT 1 FROM DUAL` | Oracle 23ai+ 支持标准多行 VALUES；之前需 INSERT ALL |
| `INSERT IGNORE` | PL/SQL 异常处理 | 无直接等价 |
| `REPLACE INTO` | MERGE | |
| `ON DUPLICATE KEY UPDATE` | MERGE | |
| `LAST_INSERT_ID()` | `seq.CURRVAL` | 需要先 NEXTVAL |

### UPDATE / DELETE

```sql
-- MySQL: LIMIT 在 UPDATE/DELETE 中
UPDATE users SET status = 0 WHERE status = 1 LIMIT 100;

-- Oracle 12c+:
UPDATE users SET status = 0 WHERE ROWID IN (
    SELECT ROWID FROM users WHERE status = 1 FETCH FIRST 100 ROWS ONLY
);

-- Oracle 传统:
UPDATE users SET status = 0 WHERE ROWNUM <= 100 AND status = 1;
-- 注意: ROWNUM 在 WHERE 之前分配，上面的写法可能不返回预期结果！
```

### 分页

```sql
-- MySQL
SELECT * FROM users ORDER BY id LIMIT 10 OFFSET 20;

-- Oracle 12c+ (推荐)
SELECT * FROM users ORDER BY id OFFSET 20 ROWS FETCH NEXT 10 ROWS ONLY;

-- Oracle 传统 (12c 之前)
SELECT * FROM (
    SELECT t.*, ROWNUM rn FROM (
        SELECT * FROM users ORDER BY id
    ) t WHERE ROWNUM <= 30
) WHERE rn > 20;
```

## 函数迁移

| MySQL | Oracle | 说明 |
|-------|--------|------|
| `IFNULL(a, b)` | `NVL(a, b)` | Oracle 独有 NVL |
| `IF(cond, a, b)` | `CASE WHEN cond THEN a ELSE b END` | 或 DECODE |
| `CONCAT(a, b, c)` | `a \|\| b \|\| c` | Oracle CONCAT 只接受 2 个参数！ |
| `GROUP_CONCAT(col)` | `LISTAGG(col, ',') WITHIN GROUP (ORDER BY col)` | 语法完全不同 |
| `NOW()` | `SYSDATE` 或 `SYSTIMESTAMP` | 无括号 |
| `CURDATE()` | `TRUNC(SYSDATE)` | 截断时间部分 |
| `DATE_ADD(d, INTERVAL 1 DAY)` | `d + 1` 或 `d + INTERVAL '1' DAY` | |
| `DATEDIFF(a, b)` | `a - b` (DATE 直接相减) | 返回天数 |
| `DATE_FORMAT(d, '%Y-%m-%d')` | `TO_CHAR(d, 'YYYY-MM-DD')` | 格式字符串不同 |
| `STR_TO_DATE(s, fmt)` | `TO_DATE(s, fmt)` | 格式字符串不同 |
| `UNIX_TIMESTAMP()` | `(SYSDATE - DATE '1970-01-01') * 86400` | 无直接函数 |
| `SUBSTRING(s, p, l)` | `SUBSTR(s, p, l)` | 函数名缩写 |
| `LENGTH(s)` | `LENGTH(s)` | 但 Oracle 的 LENGTH('') = NULL！ |
| `TRIM(s)` | `TRIM(s)` | 相同 |
| `LCASE(s)` / `UCASE(s)` | `LOWER(s)` / `UPPER(s)` | |
| `REGEXP 'pattern'` | `REGEXP_LIKE(col, 'pattern')` | 函数而非运算符 |
| `AUTO_INCREMENT 值` | `seq.NEXTVAL` / `seq.CURRVAL` | 完全不同的机制 |

### 格式字符串对照

| 含义 | MySQL | Oracle |
|------|-------|--------|
| 四位年 | `%Y` | `YYYY` |
| 两位月 | `%m` | `MM` |
| 两位日 | `%d` | `DD` |
| 24小时 | `%H` | `HH24` |
| 12小时 | `%h` | `HH` 或 `HH12` |
| 分钟 | `%i` | `MI` |
| 秒 | `%s` | `SS` |
| AM/PM | `%p` | `AM` 或 `PM` |

## 高危迁移点

### 1. Oracle DATE 包含时间

```sql
-- MySQL: DATE 只有日期
SELECT CAST('2024-01-15 10:30:00' AS DATE);  -- '2024-01-15' (丢失时间)

-- Oracle: DATE 包含时间！
SELECT CAST(TIMESTAMP '2024-01-15 10:30:00' AS DATE) FROM DUAL;  -- 保留时间
-- 比较: WHERE order_date = DATE '2024-01-15' 不匹配有时间的行！
-- 修复: WHERE TRUNC(order_date) = DATE '2024-01-15'
```

### 2. CONCAT 参数个数

```sql
-- MySQL: CONCAT 接受任意个参数
SELECT CONCAT(first_name, ' ', last_name);

-- Oracle: CONCAT 只接受 2 个参数！
SELECT first_name || ' ' || last_name FROM DUAL;   -- 推荐
SELECT CONCAT(CONCAT(first_name, ' '), last_name) FROM DUAL;  -- 嵌套
```

### 3. FROM DUAL

```sql
-- MySQL: FROM 可选
SELECT 1 + 1;
SELECT NOW();

-- Oracle: 必须 FROM DUAL
SELECT 1 + 1 FROM DUAL;
SELECT SYSDATE FROM DUAL;
-- 23ai+: Oracle 也支持省略 FROM DUAL 了
```

### 4. 标识符大小写

```sql
-- MySQL (Linux): 表名区分大小写（取决于文件系统）
-- MySQL (Windows): 表名不区分大小写

-- Oracle: 默认全部转为大写存储
CREATE TABLE my_table (...);   -- 存储为 MY_TABLE
SELECT * FROM my_table;        -- Oracle 自动转为 MY_TABLE
SELECT * FROM "my_table";      -- 双引号保留原始大小写（不推荐）
```

## Oracle 23ai 新特性（降低迁移难度）

Oracle 23ai（原定名 23c，2024 年正式发布）引入了多项降低 MySQL 迁移难度的改进：

| 特性 | 说明 | 迁移影响 |
|------|------|---------|
| 原生 BOOLEAN 类型 | SQL 层支持 `BOOLEAN`（之前仅 PL/SQL） | TINYINT(1) 可直接映射 BOOLEAN，无需 NUMBER(1)+CHECK |
| 多行 VALUES | 支持 `INSERT INTO t VALUES (...), (...), (...)` | 不再需要 INSERT ALL ... SELECT FROM DUAL |
| FROM DUAL 放宽 | SELECT 常量不再强制 FROM DUAL | 减少纯量查询的改写工作量 |
| DDL IF [NOT] EXISTS | 支持 `CREATE TABLE IF NOT EXISTS`、`DROP TABLE IF EXISTS` 等 | 与 MySQL DDL 语法更一致，迁移脚本改动更少 |
