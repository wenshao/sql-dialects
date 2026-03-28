# Oracle: 迁移速查表

> 参考资料:
> - [Oracle SQL Language Reference](https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/)

## 从 MySQL 迁移到 Oracle

数据类型映射:
  INT/BIGINT    → NUMBER(10)/NUMBER(19)
  VARCHAR(n)    → VARCHAR2(n)（注意: 默认字节语义!推荐 VARCHAR2(n CHAR)）
  TEXT          → CLOB
  DATETIME      → TIMESTAMP
  BOOLEAN       → NUMBER(1) 或 CHAR(1)（23c+ 支持 BOOLEAN）
  AUTO_INCREMENT → IDENTITY(12c+) 或 SEQUENCE
  JSON          → JSON(21c+) 或 CLOB + IS JSON 约束

函数映射:
  IFNULL(a,b)        → NVL(a,b)
  IF(c,t,f)          → DECODE(c,TRUE,t,f) 或 CASE
  NOW()              → SYSDATE 或 SYSTIMESTAMP
  CONCAT(a,b,c)      → a||b||c （Oracle CONCAT 只接受 2 参数!）
  GROUP_CONCAT        → LISTAGG ... WITHIN GROUP
  DATE_FORMAT         → TO_CHAR(date, format)
  LIMIT n             → FETCH FIRST n ROWS ONLY (12c+) 或 ROWNUM
  LIMIT offset, n     → OFFSET m ROWS FETCH NEXT n ROWS ONLY (12c+)

关键陷阱:
  1. '' = NULL（最大的陷阱!所有空字符串逻辑需要重写）
  2. 无 AUTO_INCREMENT（12c+ 有 IDENTITY）
  3. SELECT 必须有 FROM（使用 DUAL 表）
  4. 标识符默认大写（除非用双引号）
  5. DDL 隐式提交（不能回滚 CREATE/ALTER/DROP）

## 从 SQL Server 迁移到 Oracle

数据类型映射:
  NVARCHAR(n)       → NVARCHAR2(n) 或 VARCHAR2(n CHAR)
  BIT               → NUMBER(1)
  DATETIME2         → TIMESTAMP
  IDENTITY          → IDENTITY(12c+) 或 SEQUENCE
  UNIQUEIDENTIFIER  → RAW(16) 或 VARCHAR2(36)

函数映射:
  ISNULL(a,b)   → NVL(a,b)
  GETDATE()     → SYSDATE
  IIF(c,t,f)    → CASE WHEN c THEN t ELSE f END
  TOP n         → FETCH FIRST n ROWS ONLY (12c+)
  CROSS APPLY   → CROSS APPLY (12c+, 语法相同!)

关键陷阱:
  1. T-SQL → PL/SQL 完全不同的过程语言（需要完全重写）
  2. 临时表: #table → GTT（结构永久）或 PTT(18c+)
  3. Oracle 事务需要显式 COMMIT（SQL Server 默认自动提交）
  4. '' = NULL（同上）

## 从 PostgreSQL 迁移到 Oracle

数据类型映射:
  SERIAL/BIGSERIAL  → IDENTITY(12c+)
  TEXT              → VARCHAR2(4000) 或 CLOB
  BOOLEAN           → NUMBER(1)（23c+ 支持 BOOLEAN）
  JSONB             → JSON(21c+)
  ARRAY             → VARRAY 或 Nested Table（需要 TYPE 定义）

函数映射:
  string_agg       → LISTAGG
  generate_series  → CONNECT BY LEVEL
  ::type           → CAST(x AS type) 或 TO_NUMBER/TO_CHAR
  array_agg        → COLLECT（需要预定义类型）

关键陷阱:
  1. '' = NULL（又是这个）
  2. DDL 不能在事务中回滚（PostgreSQL 可以）
  3. BOOLEAN 列（23c 之前不支持）
  4. ARRAY 类型（Oracle 需要预定义 TYPE，不如 PostgreSQL 方便）

## 通用迁移注意事项

自增/序列:
```sql
CREATE TABLE t (id NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY);
-- 或:
CREATE SEQUENCE my_seq START WITH 1 INCREMENT BY 1;
```

日期/时间:
```sql
SELECT SYSDATE FROM DUAL;                     -- 当前日期时间
SELECT SYSTIMESTAMP FROM DUAL;                -- 高精度时间戳
SELECT TRUNC(SYSDATE) FROM DUAL;              -- 去掉时间部分
SELECT SYSDATE + 1 FROM DUAL;                 -- 加一天
SELECT TO_CHAR(SYSDATE, 'YYYY-MM-DD HH24:MI:SS') FROM DUAL;
```

字符串:
```sql
SELECT LENGTH('hello') FROM DUAL;
SELECT SUBSTR('hello', 2, 3) FROM DUAL;       -- 'ell'
SELECT 'hello' || ' world' FROM DUAL;
SELECT LISTAGG(name, ', ') WITHIN GROUP (ORDER BY name) FROM users;
SELECT REGEXP_SUBSTR('a,b,c', '[^,]+', 1, 2) FROM DUAL; -- 'b'
```

NULL 处理:
```sql
SELECT NVL(col, 'default') FROM t;
SELECT NVL2(col, 'has value', 'is null') FROM t;
SELECT COALESCE(a, b, c) FROM t;
```

分页:
```sql
SELECT * FROM t ORDER BY id OFFSET 20 ROWS FETCH NEXT 10 ROWS ONLY; -- 12c+
```

## 对引擎开发者的总结

1. '' = NULL 是 Oracle 迁移中最大的障碍，几乎影响所有字符串逻辑。
2. PL/SQL 与 T-SQL/PL/pgSQL 是完全不同的过程语言，无法自动转换。
3. DUAL 表、标识符大写、DDL 隐式提交是 Oracle 独有的行为。
4. 12c 是 Oracle 兼容性的分水岭（IDENTITY、FETCH FIRST、LATERAL 等）。
5. 从 Oracle 迁出比迁入更困难（因为 PL/SQL 包、CONNECT BY、VPD 等独有特性）。
