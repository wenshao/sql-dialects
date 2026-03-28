# PolarDB: 迁移速查表 (Migration Cheatsheet)

> 参考资料:
> - [PolarDB Documentation](https://help.aliyun.com/product/172538.html)


一、多引擎: PolarDB MySQL版, PolarDB PostgreSQL版, PolarDB-X(分布式)
PolarDB MySQL版: 高度兼容MySQL 5.6/5.7/8.0
PolarDB PostgreSQL版: 高度兼容PostgreSQL 11/14
PolarDB-X: 分布式MySQL兼容
二、数据类型: 取决于引擎版本
三、陷阱: 共享存储架构(一写多读), 读写分离自动处理,
并行查询是PolarDB特色, 存储计算分离,
PolarDB-X有分布式事务限制, Global Binlog支持CDC
四、自增: AUTO_INCREMENT(MySQL版) 或 SERIAL(PG版)
五、日期/字符串: 与对应引擎(MySQL/PostgreSQL)相同
MySQL版: NOW(); DATE_FORMAT(d,'%Y-%m-%d'); STR_TO_DATE()
PG版: NOW(); TO_CHAR(ts,'YYYY-MM-DD'); TO_DATE()
六、字符串: 与对应引擎相同

## 七、数据类型映射

MySQL → PolarDB MySQL版: 基本完全兼容
所有 MySQL 数据类型直接支持
PostgreSQL → PolarDB PostgreSQL版: 基本完全兼容
所有 PostgreSQL 数据类型直接支持
Oracle → PolarDB:
需使用 PolarDB PostgreSQL版 + Oracle 兼容插件
- NUMBER → NUMERIC, VARCHAR2 → VARCHAR, CLOB → TEXT

### 八、函数等价映射

与对应引擎版本相同
- **MySQL版**: IFNULL, NOW(), DATE_FORMAT, CONCAT, GROUP_CONCAT, LIMIT
- **PG版**: COALESCE, NOW(), TO_CHAR, ||, STRING_AGG, LIMIT

### 九、常见陷阱补充

- **共享存储架构**: 一写多读，读写分离自动处理
并行查询是 PolarDB 特色（加速大表扫描）
存储计算分离，存储自动扩容
- **PolarDB-X (分布式版)**: 有分布式事务限制
PolarDB-X 需要指定分片键和拆分规则
Global Binlog 支持 CDC 数据同步
连接池和代理层自动管理

### 十、NULL 处理: 与对应引擎相同

- **MySQL版**: IFNULL(a,b); COALESCE(a,b,c); NULLIF(a,b); <=> (NULL安全等于)
- **PG版**: COALESCE(a,b,c); NULLIF(a,b); IS DISTINCT FROM

### 十一、分页语法

- **MySQL版**: SELECT * FROM t LIMIT 10 OFFSET 20;
- **PG版**: SELECT * FROM t ORDER BY id LIMIT 10 OFFSET 20;

### 十二、迁移工具

DTS (数据传输服务) 支持 MySQL/PostgreSQL 到 PolarDB 的迁移
ADAM (数据库和应用迁移) 支持 Oracle 到 PolarDB 的迁移
