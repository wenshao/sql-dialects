# TDSQL: 迁移速查表 (Migration Cheatsheet)

> 参考资料:
> - [TDSQL Documentation](https://cloud.tencent.com/document/product/557)


一、与 MySQL 兼容性: 高度兼容MySQL 5.7/8.0
TDSQL-C(云原生): 共享存储, 兼容MySQL
TDSQL-H(分析型): HTAP混合负载
TDSQL(分布式): 分布式MySQL, 需要指定分片键(shardkey)
二、数据类型: 与MySQL相同
三、陷阱: 分布式版本需要shardkey(分片键), 分布式事务性能影响,
跨分片JOIN有限制, 全局唯一索引需要包含shardkey,
DDL操作在分布式模式下可能阻塞, sequence全局唯一
四、自增: AUTO_INCREMENT（分布式模式下全局唯一但不连续）
分布式版: 使用 sequence 全局唯一
五、日期/字符串: 与 MySQL 相同
NOW(); CURDATE(); DATE_ADD(NOW(), INTERVAL 1 DAY);
DATE_FORMAT(NOW(), '%Y-%m-%d %H:%i:%s'); STR_TO_DATE()
六、字符串: LENGTH, UPPER, LOWER, TRIM, SUBSTRING, REPLACE, LOCATE, CONCAT, GROUP_CONCAT

## 七、数据类型映射（从 MySQL/Oracle 到 TDSQL）

MySQL → TDSQL: 高度兼容
所有 MySQL 数据类型直接支持
- JSON → JSON, GEOMETRY → GEOMETRY (部分)
Oracle → TDSQL:
- NUMBER(p,s) → DECIMAL(p,s), VARCHAR2(n) → VARCHAR(n),
- CLOB → LONGTEXT, DATE → DATETIME,
- SYSDATE → NOW(), SEQUENCE → AUTO_INCREMENT

### 八、函数等价映射

Oracle → TDSQL:
- NVL → IFNULL/COALESCE, SYSDATE → NOW(),
- TO_CHAR(d,'YYYY-MM-DD') → DATE_FORMAT(d,'%Y-%m-%d'),
- TO_DATE → STR_TO_DATE, ROWNUM → LIMIT,
- DECODE → CASE WHEN, || → CONCAT,
- LISTAGG → GROUP_CONCAT

### 九、常见陷阱补充

分布式版需要 shardkey（分片键），选择不当导致数据倾斜
跨分片 JOIN 有限制（建议使用广播表）
全局唯一索引必须包含 shardkey
DDL 操作在分布式模式下可能阻塞
TDSQL-C (云原生版) 共享存储，无需分片键
TDSQL-H (分析型) HTAP 混合负载，支持分析查询

### 十、NULL 处理

IFNULL(a, b); COALESCE(a, b, c);
NULLIF(a, b); <=> (NULL 安全等于)
ISNULL(a) 返回 0 或 1

### 十一、分页语法

SELECT * FROM t LIMIT 10 OFFSET 20;               -- 与 MySQL 相同

### 十二、分布式事务

分布式版支持分布式事务（XA 协议）
跨分片事务性能有影响
建议将相关数据放在同一分片
