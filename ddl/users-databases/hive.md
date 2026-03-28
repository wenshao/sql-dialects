# Hive: 数据库/Schema/用户管理与 Metastore

> 参考资料:
> - [1] Apache Hive Language Manual - DDL: Database
>   https://cwiki.apache.org/confluence/display/Hive/LanguageManual+DDL#LanguageManualDDL-CreateDatabase
> - [2] Apache Hive - Hive Metastore Administration
>   https://cwiki.apache.org/confluence/display/Hive/AdminManual+Metastore
> - [3] Apache Ranger - Hive Authorization
>   https://ranger.apache.org/


## 1. 数据库管理 (Database = HDFS 目录 + Metastore 记录)

```sql
CREATE DATABASE IF NOT EXISTS analytics
    COMMENT '分析数据仓库'
    LOCATION '/warehouse/analytics'
    WITH DBPROPERTIES ('owner' = 'data_team', 'env' = 'production');

```

SCHEMA 是同义词

```sql
CREATE SCHEMA IF NOT EXISTS analytics;

```

切换数据库

```sql
USE analytics;

```

查看数据库

```sql
SHOW DATABASES;
SHOW DATABASES LIKE 'anal*';
DESCRIBE DATABASE analytics;
DESCRIBE DATABASE EXTENDED analytics;

```

修改数据库

```sql
ALTER DATABASE analytics SET DBPROPERTIES ('env' = 'staging');
ALTER DATABASE analytics SET OWNER USER admin_user;
ALTER DATABASE analytics SET OWNER ROLE admin_role;
ALTER DATABASE analytics SET LOCATION '/new/path/analytics.db';  -- Hive 2.2.1+

```

删除数据库

```sql
DROP DATABASE IF EXISTS analytics;
DROP DATABASE IF EXISTS analytics CASCADE;  -- 连同所有表一起删除
DROP DATABASE analytics RESTRICT;           -- 非空则报错（默认）

```

 设计分析: Database = 目录
 Hive 的 Database 映射到 HDFS 上的一个目录:
   CREATE DATABASE analytics LOCATION '/warehouse/analytics'
   → 在 HDFS 上创建 /warehouse/analytics/ 目录
   → 该数据库下的表存储在 /warehouse/analytics/table_name/ 子目录中

 这一设计意味着:
1. 数据库级别的权限可以通过 HDFS 权限控制

2. 数据库隔离 = 目录隔离（物理隔离，非逻辑隔离）

3. 跨数据库查询 = 跨目录读取（对 HDFS 透明）


 Hive 的 Database ≠ Schema:
 在 Hive 中 DATABASE 和 SCHEMA 是同义词（CREATE SCHEMA = CREATE DATABASE）
 这与 PostgreSQL/SQL Server 的三级命名空间 (catalog.schema.table) 不同
 Hive 只有两级: database.table

## 2. Hive Metastore (HMS): 核心元数据服务

 Hive Metastore 是 Hive 最持久的遗产——即使 Hive 查询引擎不再使用，
 HMS 仍然是 Hadoop 生态系统的元数据标准。

 HMS 存储的信息:
1. 数据库定义（名称、位置、属性）

2. 表定义（列、类型、SerDe、存储格式、位置）

3. 分区信息（分区值、位置、统计信息）

4. 表/列级别统计信息（用于 CBO）

5. 约束定义（PK/FK/UNIQUE/NOT NULL）

6. UDF 注册信息


 HMS 的架构:
 HMS 本身基于关系数据库（MySQL/PostgreSQL/Derby）存储元数据。
 部署模式:
   Embedded: Derby 嵌入（仅测试用，不支持并发）
   Local:    HiveServer2 进程内的 Metastore
   Remote:   独立 Thrift 服务（生产推荐），多个引擎共享

 HMS 成为生态标准的原因:
   Spark SQL / Presto/Trino / Impala / Flink SQL / Delta Lake / Iceberg
   都可以连接 HMS 读写表元数据。

 HMS 的性能瓶颈:
1. 分区数量: 单表数万分区时，SHOW PARTITIONS / MSCK REPAIR TABLE 极慢

2. 统计信息: ANALYZE TABLE 计算统计信息需要全表扫描

3. 元数据锁: 多个引擎并发修改元数据时可能冲突

4. 后端数据库: MySQL 作为 HMS 后端的连接数和查询性能限制


## 3. 权限管理

 Hive 有三种授权模型:

### 3.1 Storage-Based Authorization (默认)

 利用 HDFS 文件权限控制访问
 优点: 简单，与 HDFS 权限一致
 缺点: 粒度只到目录级别，无法控制列级/行级权限

### 3.2 SQL Standard Based Authorization (Hive 2.0+)

```sql
GRANT SELECT ON TABLE orders TO USER analyst;
GRANT SELECT, INSERT ON TABLE orders TO ROLE etl_role;
REVOKE INSERT ON TABLE orders FROM USER analyst;
GRANT ALL ON DATABASE analytics TO ROLE admin_role;

```

角色管理

```sql
CREATE ROLE analyst_role;
GRANT ROLE analyst_role TO USER john;
SET ROLE analyst_role;
SHOW ROLES;
SHOW ROLE GRANT USER john;
SHOW CURRENT ROLES;
DROP ROLE analyst_role;

```

列级权限

```sql
GRANT SELECT (username, email) ON TABLE users TO ROLE analyst;

```

### 3.3 Apache Ranger / Apache Sentry (企业级)

生产环境通常使用 Ranger 而非 Hive 内置权限:
Ranger: 集中式策略管理，支持行级/列级过滤，审计日志

当前数据库查询

```sql
SELECT current_database();

```

## 4. 函数管理 (UDF 注册)

临时函数（会话级）

```sql
CREATE TEMPORARY FUNCTION my_upper AS 'com.example.UpperUDF'
    USING JAR '/path/to/udf.jar';

```

永久函数（注册到 Metastore）

```sql
CREATE FUNCTION db.my_lower AS 'com.example.LowerUDF'
    USING JAR 'hdfs:///libs/udf.jar';

SHOW FUNCTIONS;
SHOW FUNCTIONS LIKE 'my_*';
DESCRIBE FUNCTION my_upper;
DROP FUNCTION IF EXISTS db.my_lower;

```

## 5. 跨引擎对比: 元数据与权限

 引擎           元数据管理           权限模型
 Hive           HMS (关系数据库)     GRANT/Ranger/Sentry
 MySQL          information_schema   GRANT/REVOKE (用户级)
 PostgreSQL     pg_catalog           GRANT/REVOKE (角色级)
 BigQuery       无独立 Metastore     IAM 集成
 Spark SQL      HMS 或 Glue          继承 HMS 权限或 YARN
 Trino          HMS 或自有 Catalog   System Access Control
 Snowflake      内部 Catalog         RBAC (角色级)
 MaxCompute     内部 Catalog         阿里云 RAM 集成

## 6. 已知限制

1. 无 Schema 子级别: Hive 只有 database.table 两级，无法像 PG 那样 db.schema.table

2. 无 CREATE USER: 用户管理由 LDAP/Kerberos 等外部系统处理

3. HMS 单点问题: 虽然可以 HA 部署，但后端关系数据库仍是瓶颈

4. 权限不跨引擎: Hive GRANT 的权限在 Spark/Trino 中不一定生效

5. 内置权限模型简陋: 无行级安全、无动态数据脱敏（需要 Ranger）

6. CASCADE DROP 危险: DROP DATABASE CASCADE 会删除所有表及其数据


## 7. 对引擎开发者的启示

1. Metastore 独立于查询引擎: Hive 最大的遗产不是 HiveQL，而是 HMS。

    设计引擎时，将元数据管理作为独立服务是正确的架构决策。
2. 三级命名空间 (catalog.schema.table) 是更好的设计:

    Hive 两级命名空间在多租户场景下不够灵活
3. 权限应该外部化: Hive 的经验表明，嵌入式权限管理不够强大，

    生产环境总是需要 Ranger 这样的外部权限系统
4. 元数据作为 API: HMS Thrift API 的成功说明，元数据服务的 API 设计

决定了生态系统的互操作性

