-- Oracle: 数据库、模式与用户管理
--
-- 参考资料:
--   [1] Oracle SQL Language Reference - CREATE USER
--       https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/CREATE-USER.html
--   [2] Oracle Database Concepts - CDB and PDBs
--       https://docs.oracle.com/en/database/oracle/oracle-database/23/cncpt/CDBs-and-PDBs.html

-- ============================================================
-- 1. Oracle 命名层级与设计哲学
-- ============================================================

-- Oracle 的命名层级: instance > CDB > PDB > schema(=user) > object
--
-- Oracle 最独特的设计: schema 和 user 是一一对应的
-- 创建一个用户 = 创建一个同名 schema
-- 这与其他数据库截然不同:
--   PostgreSQL: database > schema > object（schema 独立于 user）
--   MySQL:      server > database(=schema) > object（database 和 schema 同义）
--   SQL Server: server > database > schema > object（schema 独立于 user）
--
-- 对引擎开发者的启示:
--   Oracle 的 user=schema 简化了权限模型但降低了灵活性。
--   现代数据库倾向于分离 user 和 schema（允许一个 schema 多人共享）。
--   推荐采用 PostgreSQL/SQL Server 的三层模型: database > schema > object。

-- ============================================================
-- 2. 可插拔数据库 PDB（12c+，Oracle 独创）
-- ============================================================

-- PDB 是 Oracle 多租户架构的核心创新
-- CDB (Container Database): 根容器，管理基础设施
-- PDB (Pluggable Database): 逻辑数据库，可独立插拔

CREATE PLUGGABLE DATABASE mypdb
    ADMIN USER pdb_admin IDENTIFIED BY secret123
    FILE_NAME_CONVERT = ('/pdbseed/', '/mypdb/');

ALTER PLUGGABLE DATABASE mypdb OPEN;
ALTER PLUGGABLE DATABASE mypdb CLOSE;

DROP PLUGGABLE DATABASE mypdb INCLUDING DATAFILES;

-- 克隆 PDB（快速创建开发/测试环境）
CREATE PLUGGABLE DATABASE mypdb_clone FROM mypdb;

-- 切换到 PDB
ALTER SESSION SET CONTAINER = mypdb;

-- 设计分析:
--   PDB 的核心价值: 资源隔离 + 统一管理 + 快速部署
--   一个 CDB 可以包含数百个 PDB，共享内存和后台进程。
--   类似 Docker 容器的理念: 共享内核（CDB），隔离应用（PDB）。
--
-- 横向对比:
--   Oracle:     CDB/PDB（物理共享+逻辑隔离，最成熟的多租户实现）
--   PostgreSQL: 无原生多租户，通过 database 或 schema 隔离
--   MySQL:      无原生多租户
--   SQL Server: Contained Database（弱版多租户）
--   云原生:     Serverless 引擎（如 Aurora Serverless）用计算/存储分离实现
--
-- 对引擎开发者的启示:
--   多租户是企业级数据库的关键特性。实现方式:
--   方案 A: Oracle PDB（进程内隔离，最高效但最复杂）
--   方案 B: 独立进程（PostgreSQL 方式，简单但资源消耗大）
--   方案 C: 存储层隔离（Snowflake 方式，存算分离）

-- ============================================================
-- 3. 用户/模式管理
-- ============================================================

-- 创建用户（同时创建同名模式）
CREATE USER myuser IDENTIFIED BY secret123
    DEFAULT TABLESPACE users
    TEMPORARY TABLESPACE temp
    QUOTA 500M ON users                       -- 表空间配额
    PROFILE default;

-- 12c+ 公共用户（CDB 级别，跨所有 PDB）
CREATE USER c##common_user IDENTIFIED BY secret123 CONTAINER = ALL;

-- 修改用户
ALTER USER myuser IDENTIFIED BY newsecret;
ALTER USER myuser ACCOUNT LOCK;
ALTER USER myuser ACCOUNT UNLOCK;
ALTER USER myuser PASSWORD EXPIRE;
ALTER USER myuser QUOTA UNLIMITED ON users;

-- 删除用户
DROP USER myuser CASCADE;                     -- 级联删除所有对象

-- 设置当前模式（访问其他用户的对象）
ALTER SESSION SET CURRENT_SCHEMA = other_user;

-- ============================================================
-- 4. 表空间管理（Oracle 独有概念）
-- ============================================================

-- 表空间是 Oracle 特有的存储管理层:
-- 逻辑结构: 表空间 > 段(segment) > 区(extent) > 数据块(block)
-- 物理结构: 表空间 → 一个或多个数据文件

CREATE TABLESPACE app_data
    DATAFILE '/u01/oradata/app_data01.dbf' SIZE 1G
    AUTOEXTEND ON NEXT 100M MAXSIZE 10G
    EXTENT MANAGEMENT LOCAL
    SEGMENT SPACE MANAGEMENT AUTO;

CREATE TEMPORARY TABLESPACE app_temp
    TEMPFILE '/u01/oradata/app_temp01.dbf' SIZE 500M;

DROP TABLESPACE app_data INCLUDING CONTENTS AND DATAFILES;

-- 横向对比:
--   Oracle:     表空间 → 数据文件（DBA 精细控制存储）
--   PostgreSQL: 表空间（指向文件系统目录，相对简单）
--   MySQL:      InnoDB 表空间（file-per-table 或共享表空间）
--   SQL Server: 文件组（Filegroup）→ 数据文件

-- ============================================================
-- 5. 角色与权限
-- ============================================================

-- 系统权限
GRANT CREATE SESSION TO myuser;               -- 必须! 允许登录
GRANT CREATE TABLE, CREATE VIEW, CREATE SEQUENCE TO myuser;
GRANT UNLIMITED TABLESPACE TO myuser;

-- 对象权限
GRANT SELECT ON hr.employees TO myuser;
GRANT SELECT ON hr.employees TO myuser WITH GRANT OPTION;

-- 角色
CREATE ROLE analyst;
GRANT SELECT ANY TABLE TO analyst;
GRANT analyst TO myuser;

-- 预定义角色
GRANT CONNECT TO myuser;                      -- 基本连接
GRANT RESOURCE TO myuser;                     -- 创建对象
GRANT DBA TO myuser;                          -- 完全管理

-- 收回权限
REVOKE CREATE TABLE FROM myuser;

-- Profile（资源限制，Oracle 独有）
CREATE PROFILE app_profile LIMIT
    SESSIONS_PER_USER 10
    FAILED_LOGIN_ATTEMPTS 5
    PASSWORD_LIFE_TIME 90
    PASSWORD_REUSE_TIME 365;
ALTER USER myuser PROFILE app_profile;

-- ============================================================
-- 6. 数据字典查询（Oracle 三层架构）
-- ============================================================

-- USER_* / ALL_* / DBA_* 三层视图是 Oracle 的标志性设计

-- 当前用户信息
SELECT SYS_CONTEXT('USERENV', 'CURRENT_USER') AS current_user,
       SYS_CONTEXT('USERENV', 'CURRENT_SCHEMA') AS current_schema,
       SYS_CONTEXT('USERENV', 'DB_NAME') AS db_name,
       SYS_CONTEXT('USERENV', 'CON_NAME') AS container_name
FROM DUAL;

-- SYS_CONTEXT 是 Oracle 独有的上下文查询函数
-- 对比: PostgreSQL 用 current_user / current_database()
--       MySQL 用 USER() / DATABASE()
--       SQL Server 用 SUSER_SNAME() / DB_NAME()

-- 列出用户
SELECT username, account_status, default_tablespace, created
FROM dba_users WHERE oracle_maintained = 'N';

-- 列出 PDB
SELECT pdb_name, status FROM cdb_pdbs;

-- 对引擎开发者的启示:
--   Oracle 的 SYS_CONTEXT 通过命名空间组织会话信息，扩展性极强。
--   应用可以创建自定义上下文: CREATE CONTEXT ... USING package_name
--   这为 VPD（虚拟私有数据库）等安全特性提供了基础。
--   新引擎可以考虑类似的会话上下文机制来支持行级安全。
