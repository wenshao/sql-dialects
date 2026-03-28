# MaxCompute (ODPS): 数值类型

> 参考资料:
> - [1] MaxCompute SQL - Data Types
>   https://help.aliyun.com/zh/maxcompute/user-guide/data-types-1
> - [2] MaxCompute - Mathematical Functions
>   https://help.aliyun.com/zh/maxcompute/user-guide/mathematical-functions


## 1. 整数类型


TINYINT:  1 字节，-128 ~ 127（2.0+）
SMALLINT: 2 字节，-32768 ~ 32767（2.0+）
INT:      4 字节，-2^31 ~ 2^31-1（2.0+）
BIGINT:   8 字节，-2^63 ~ 2^63-1（1.0 起就有，唯一的整数类型）


```sql
SET odps.sql.type.system.odps2 = true;      -- 启用 2.0 类型系统

CREATE TABLE examples (
    tiny_val   TINYINT,                     -- 2.0+
    small_val  SMALLINT,                    -- 2.0+
    int_val    INT,                         -- 2.0+
    big_val    BIGINT                       -- 1.0+ 唯一整数类型
);

```

## 2. 设计决策: 1.0 只有 BIGINT 的极简设计


### 1.0 类型系统: 所有整数都是 BIGINT（8 字节）

   优点: 简化实现（类型推导、运算规则、存储编码统一）
   缺点:
     存储浪费: TINYINT 的值（0~127）也占 8 字节 → 8 倍浪费
     迁移困难: MySQL INT → MaxCompute BIGINT（类型不匹配）
     列式存储的自适应编码部分缓解了浪费:
       AliORC 的字典编码和 RLE 编码可以压缩小值整数
       实际存储中 BIGINT 列如果值域小，压缩后可能只占 1-2 字节/值

### 2.0 修正: 引入完整的整数类型（TINYINT/SMALLINT/INT）

   但默认关闭（SET odps.sql.type.system.odps2 = true）以保持兼容

 对比:
   Hive:        同样只有 TINYINT/SMALLINT/INT/BIGINT（但从一开始就有 INT）
   BigQuery:    INT64（唯一整数类型，与 BIGINT 相同的极简思路）
   Snowflake:   NUMBER(38,0)（唯一整数类型，按精度存储）
   ClickHouse:  Int8/Int16/Int32/Int64/Int128/Int256（最丰富）
   PostgreSQL:  SMALLINT/INTEGER/BIGINT（标准配置）
   MySQL:       TINYINT/SMALLINT/MEDIUMINT/INT/BIGINT（含 UNSIGNED）

 对引擎开发者: 两种策略各有道理
   策略 A（BigQuery）: 一种整数类型，极简，列式压缩弥补存储开销
   策略 B（ClickHouse）: 多种整数类型，精确控制存储和运算
   MaxCompute 从 A 转向 B，付出了两套类型系统的维护代价

## 3. 浮点数


FLOAT:  4 字节，单精度 IEEE 754（2.0+）
DOUBLE: 8 字节，双精度 IEEE 754（1.0+）

浮点数精度问题:

```sql
SELECT CAST(0.1 AS DOUBLE) + CAST(0.2 AS DOUBLE);
```

 结果: 0.30000000000000004（不是精确的 0.3）
 这是所有使用 IEEE 754 的引擎的共同问题

## 4. DECIMAL —— 精确数值


1.0: DECIMAL 固定精度 54 位，小数位 18
2.0: DECIMAL(p, s) 精度 p 最大 36，小数位 s 最大 18


```sql
CREATE TABLE prices (
    price DECIMAL(10, 2),                   -- 精确到分（推荐用于金融场景）
    rate  DOUBLE                            -- 浮点数（适用于科学计算）
);

```

 DECIMAL 运算精度规则:
   加减: DECIMAL(p1,s1) + DECIMAL(p2,s2) → DECIMAL(max(s1,s2)+max(p1-s1,p2-s2)+1, max(s1,s2))
   乘法: DECIMAL(p1,s1) * DECIMAL(p2,s2) → DECIMAL(p1+p2+1, s1+s2)
   除法: DECIMAL(p1,s1) / DECIMAL(p2,s2) → DECIMAL(p1+s2+div_precision, s1+div_precision)
   溢出: 如果结果精度超过 36，可能截断或报错

 对比:
   BigQuery:   NUMERIC (38,9) / BIGNUMERIC (76,38)
   Snowflake:  NUMBER(p,s) p 最大 38
   PostgreSQL: NUMERIC 任意精度（无上限，但性能随精度下降）
   MySQL:      DECIMAL(p,s) p 最大 65

## 5. BOOLEAN


 BOOLEAN: TRUE / FALSE / NULL（2.0+）
### 1.0 没有 BOOLEAN，通常用 BIGINT 的 0/1 代替


```sql
CREATE TABLE flags (active BOOLEAN DEFAULT TRUE);

SELECT * FROM flags WHERE active = TRUE;
SELECT * FROM flags WHERE active;           -- 隐式 TRUE 判断

```

## 6. 类型转换与隐式规则


```sql
SELECT CAST('123' AS BIGINT);               -- 字符串→整数
SELECT CAST(123 AS DOUBLE);                 -- 整数→浮点
SELECT CAST(3.14 AS BIGINT);               -- 浮点→整数（截断，非四舍五入）
SELECT CAST(3.14 AS DECIMAL(10,1));         -- 3.1

```

 隐式转换规则:
   TINYINT → SMALLINT → INT → BIGINT → FLOAT → DOUBLE
   所有整数 + DOUBLE = DOUBLE
   STRING + 数值运算 → 尝试转为数值

 溢出行为:
   默认: 溢出时行为取决于 odps.sql.type.system.odps2 设置
   1.0: 可能静默溢出（环绕）
   2.0: 可能报错
   对引擎开发者: 溢出行为必须有明确的规范（静默溢出是危险的）

## 7. 数值字面量


 整数字面量:
### 1.0 类型系统: 42 → BIGINT

### 2.0 类型系统: 42 → INT（如果在 INT 范围内）

这个差异可能导致类型不一致:
1.0: SELECT 42 的结果列类型是 BIGINT
2.0: SELECT 42 的结果列类型是 INT

后缀标注:

```sql
SELECT 42Y;                                 -- TINYINT（Y 后缀）
SELECT 42S;                                 -- SMALLINT（S 后缀）
SELECT 42;                                  -- INT（2.0）或 BIGINT（1.0）
SELECT 42L;                                 -- BIGINT（L 后缀）
SELECT 3.14BD;                              -- DECIMAL（BD 后缀）

```

## 8. 横向对比: 数值类型


 整数类型数量:
MaxCompute 1.0: 1 种（BIGINT）        | BigQuery: 1 种（INT64）
MaxCompute 2.0: 4 种（TINY~BIGINT）   | ClickHouse: 6 种（Int8~Int256）
PostgreSQL:     3 种（SMALL/INT/BIG）  | MySQL: 5 种（含 MEDIUMINT）

 UNSIGNED:
MaxCompute: 不支持                     | MySQL: 支持 UNSIGNED
PostgreSQL: 不支持                     | ClickHouse: 支持 UInt8~UInt256

 精确数值:
MaxCompute: DECIMAL(36,18) 最大精度   | BigQuery: BIGNUMERIC(76,38)
PostgreSQL: NUMERIC 无限精度           | Snowflake: NUMBER(38,s)

 特殊数值:
MaxCompute: 无 UNSIGNED/BIT/MONEY     | SQL Server: MONEY/SMALLMONEY
PostgreSQL: SERIAL（自增语法糖）      | MaxCompute: 无自增

## 9. 对引擎开发者的启示


1. 类型系统一旦发布极难更改 — MaxCompute 两套类型系统是深刻教训

2. 列式存储的自适应编码可以部分弥补类型选择不当的存储浪费

3. 整数字面量的默认类型（INT vs BIGINT）影响类型推导链 — 需慎重设计

4. DECIMAL 运算的精度传播规则必须在 SQL 编译期完整实现

5. 溢出行为（静默环绕 vs 报错）是安全关键决策 — 应默认报错

6. BigQuery 的"一种整数类型"策略配合列式压缩是优雅的简化方案

