-- ClickHouse: 数据库、模式与用户管理
--
-- 参考资料:
--   [1] ClickHouse Documentation - CREATE DATABASE
--       https://clickhouse.com/docs/en/sql-reference/statements/create/database
--   [2] ClickHouse Documentation - Access Control
--       https://clickhouse.com/docs/en/operations/access-rights
--   [3] ClickHouse - Database Engines
--       https://clickhouse.com/docs/en/engines/database-engines

-- ============================================================
-- 1. 数据库管理
-- ============================================================

CREATE DATABASE myapp;
CREATE DATABASE IF NOT EXISTS myapp;

-- 指定数据库引擎（ClickHouse 独有设计: 数据库也有引擎!）
CREATE DATABASE myapp ENGINE = Atomic;           -- 默认引擎（原子 DDL）
CREATE DATABASE logs ENGINE = Lazy(3600);        -- 延迟加载，表不活跃时卸载

-- 数据库引擎的设计分析:
--   Atomic（默认）: DDL 原子性保证（RENAME TABLE 等操作是原子的）
--   Lazy:          适合有大量小表的场景（如多租户，每租户一个表）
--                  不活跃的表在 N 秒后从内存卸载，减少内存占用
--   MaterializedMySQL: 从 MySQL binlog 实时复制整个数据库
--   MaterializedPostgreSQL: 从 PostgreSQL WAL 实时复制
--   Replicated:    ZooKeeper 管理的复制数据库（集群环境）
--
-- MaterializedMySQL 示例（实时 MySQL 复制）:
-- CREATE DATABASE mysql_replica ENGINE = MaterializedMySQL(
--     'mysql-host:3306', 'source_db', 'repl_user', 'repl_pass'
-- );
-- → ClickHouse 自动消费 MySQL binlog，实时同步全部表
-- → 典型用例: OLTP（MySQL）→ OLAP（ClickHouse）的实时分析管道

DROP DATABASE myapp;
DROP DATABASE IF EXISTS myapp;

USE myapp;
SHOW DATABASES;
SHOW CREATE DATABASE myapp;

-- ============================================================
-- 2. 用户管理（20.5+，SQL 方式）
-- ============================================================

-- 2.1 早期版本: 配置文件管理用户
-- ClickHouse 早期（20.5 之前）用户定义在 users.xml 中:
--   <users><myuser><password>...</password><networks>...</networks></myuser></users>
-- 修改需要重启服务。这是 OLAP 引擎的历史: 早期不重视用户管理。

-- 2.2 SQL 方式创建用户（20.5+，需要启用 access_management）
CREATE USER myuser IDENTIFIED BY 'secret123';
CREATE USER IF NOT EXISTS myuser IDENTIFIED BY 'secret123';

-- 完整选项
CREATE USER myuser
    IDENTIFIED WITH sha256_password BY 'secret123'
    HOST ANY                                    -- 允许任意主机
    DEFAULT DATABASE myapp
    DEFAULT ROLE analyst
    SETTINGS max_memory_usage = 10000000000;    -- 用户级资源限制

-- 主机限制（安全边界）
CREATE USER local_user IDENTIFIED BY 'pass' HOST LOCAL;
CREATE USER subnet_user IDENTIFIED BY 'pass' HOST IP '10.0.0.0/8';

-- 修改/删除
ALTER USER myuser IDENTIFIED BY 'newsecret';
ALTER USER myuser SETTINGS max_memory_usage = 20000000000;
DROP USER myuser;

-- ============================================================
-- 3. 角色管理
-- ============================================================

CREATE ROLE analyst;
CREATE ROLE developer;

-- 分配角色
GRANT analyst TO myuser;
SET DEFAULT ROLE analyst TO myuser;

-- 角色继承
GRANT analyst TO developer;     -- developer 继承 analyst 的所有权限

-- 当前会话切换角色
SET ROLE analyst;
SET ROLE DEFAULT;

DROP ROLE analyst;

-- ============================================================
-- 4. 权限管理
-- ============================================================

-- 数据库级
GRANT SHOW DATABASES ON *.* TO myuser;
GRANT CREATE ON myapp.* TO developer;

-- 表级
GRANT SELECT ON myapp.users TO analyst;
GRANT SELECT ON myapp.* TO analyst;
GRANT INSERT, ALTER ON myapp.events TO developer;

-- 列级安全（ClickHouse 独有的细粒度控制）
GRANT SELECT(id, username) ON myapp.users TO myuser;
-- myuser 只能 SELECT id 和 username，访问其他列会报错

-- 管理权限
GRANT CREATE USER ON *.* TO admin;

-- 查看/收回
SHOW GRANTS FOR myuser;
REVOKE SELECT ON myapp.users FROM analyst;

-- ============================================================
-- 5. 资源控制: Quota 和 Settings Profile
-- ============================================================

-- 5.1 Quota: 限制用户的查询资源消耗
CREATE QUOTA monthly_quota
    FOR INTERVAL 1 MONTH
    MAX QUERIES 10000
    MAX RESULT_ROWS 1000000000
    MAX READ_ROWS 10000000000
    TO analyst;

-- 设计分析:
--   Quota 是 ClickHouse 独有的资源控制机制。
--   传统数据库（MySQL/PostgreSQL）没有类似功能（需要外部工具）。
--   BigQuery 通过计费配额（billing quota）控制，不在 SQL 层面。
--   ClickHouse 选择在 SQL 层面提供，因为 OLAP 查询资源消耗大且不可预测。

-- 5.2 Settings Profile: 预定义查询设置模板
CREATE SETTINGS PROFILE limited_profile
    SETTINGS
        max_memory_usage = 10000000000 MIN 1000000 MAX 20000000000,
        max_execution_time = 300
    TO analyst;

-- 5.3 行级安全策略（Row Policy）
CREATE ROW POLICY region_filter ON myapp.sales
    FOR SELECT
    USING region = 'APAC'
    TO analyst;
-- analyst 查询 sales 表时只能看到 region='APAC' 的行

-- ============================================================
-- 6. 集群环境下的数据库管理
-- ============================================================

-- ON CLUSTER: 在集群所有节点执行 DDL
CREATE DATABASE myapp ON CLUSTER my_cluster;
DROP DATABASE myapp ON CLUSTER my_cluster;
CREATE USER myuser ON CLUSTER my_cluster IDENTIFIED BY 'pass';

-- 设计分析:
--   ON CLUSTER 通过 ZooKeeper 协调 DDL 在所有节点的执行。
--   这是 ClickHouse 独有的分布式 DDL 机制。
--   对比: MySQL 集群需要手动在每个节点执行 DDL
--   对比: BigQuery 无此概念（无服务器，自动分布）

-- ============================================================
-- 7. 元数据查询
-- ============================================================

SHOW DATABASES;
SHOW TABLES FROM myapp;
SHOW CREATE DATABASE myapp;

SELECT name, engine FROM system.databases;
SELECT name FROM system.users;
SELECT name FROM system.roles;
SELECT * FROM system.grants WHERE user_name = 'myuser';
SELECT * FROM system.quotas;
SELECT * FROM system.row_policies;
SELECT currentUser(), currentDatabase();

-- ============================================================
-- 8. 对比与引擎开发者启示
-- ============================================================
-- ClickHouse 的用户/数据库管理特点:
--   (1) 数据库引擎: 可插拔（Atomic/Lazy/MaterializedMySQL），独特设计
--   (2) 从配置文件到 SQL: 20.5 才支持 SQL 用户管理，反映 OLAP 的演进
--   (3) Quota 内置: 资源控制在 SQL 层面，适合多租户 OLAP
--   (4) ON CLUSTER: 分布式 DDL 通过 ZooKeeper 协调
--   (5) 列级权限: GRANT SELECT(col1, col2)，比大多数数据库更细粒度
--
-- 对引擎开发者的启示:
--   OLAP 引擎的用户管理不需要从第一天就完善（ClickHouse 等了 5 年才加 SQL 用户管理）。
--   但 Quota（资源配额）应该尽早设计: 分析查询的资源消耗不可预测，
--   一个失控的 SELECT 可以耗尽整个集群的内存。
