-- MySQL: 权限管理
--
-- 参考资料:
--   [1] MySQL 8.0 Reference Manual - Access Control and Account Management
--       https://dev.mysql.com/doc/refman/8.0/en/access-control.html
--   [2] MySQL 8.0 Reference Manual - GRANT Statement
--       https://dev.mysql.com/doc/refman/8.0/en/grant.html
--   [3] MySQL 8.0 Reference Manual - Using Roles
--       https://dev.mysql.com/doc/refman/8.0/en/roles.html
--   [4] MySQL 8.0 Reference Manual - Partial Revokes
--       https://dev.mysql.com/doc/refman/8.0/en/partial-revokes.html

-- ============================================================
-- 1. 基本语法
-- ============================================================

-- 创建用户: user@host 是完整身份标识
CREATE USER 'alice'@'localhost' IDENTIFIED BY 'SecurePass123!';
CREATE USER 'alice'@'%' IDENTIFIED BY 'SecurePass123!';
CREATE USER 'alice'@'192.168.1.%' IDENTIFIED BY 'SecurePass123!';

-- 授权
GRANT SELECT ON mydb.* TO 'alice'@'localhost';
GRANT SELECT, INSERT, UPDATE ON mydb.users TO 'alice'@'localhost';
GRANT ALL PRIVILEGES ON mydb.* TO 'alice'@'localhost';

-- 列级权限
GRANT SELECT (username, email) ON mydb.users TO 'alice'@'localhost';

-- 撤销
REVOKE INSERT ON mydb.users FROM 'alice'@'localhost';

-- 查看 / 修改密码 / 删除
SHOW GRANTS FOR 'alice'@'localhost';
ALTER USER 'alice'@'localhost' IDENTIFIED BY 'NewSecurePass!';
DROP USER IF EXISTS 'alice'@'localhost';

-- ============================================================
-- 2. user@host 权限模型: MySQL 的独特设计（对引擎开发者）
-- ============================================================

-- 2.1 为什么 user@host 是独特的?
-- 在 MySQL 中，'alice'@'localhost' 和 'alice'@'%' 是两个完全不同的用户！
-- 各自有独立的密码、权限、资源限制。这在所有主流数据库中独一无二。
--
-- 设计动机: MySQL 最初是 Web 应用数据库，需要区分:
--   'app'@'web-server-ip':  应用服务器连接 → 读写权限
--   'app'@'%':              任意来源连接 → 只读或拒绝
--   'admin'@'localhost':    本机管理 → 全部权限
--
-- 2.2 host 匹配规则（排序优先级）
-- 连接时 MySQL 按以下优先级匹配:
--   1. 精确 IP:     'alice'@'192.168.1.100'
--   2. IP 通配符:   'alice'@'192.168.1.%'
--   3. 精确主机名:  'alice'@'dbserver.internal'
--   4. '%':         'alice'@'%' (任意主机)
-- 最精确的匹配优先。如果存在 'alice'@'localhost' 则 'alice'@'%' 不匹配本地连接。
--
-- 2.3 经典陷阱
-- 场景: 创建 'alice'@'%' (有权限)，从 localhost 连接
-- 结果: 匹配到 mysql.user 中可能存在的 ''@'localhost'（匿名用户）
--        或匹配到 'alice'@'localhost'（不存在则拒绝）
-- 根因: host 匹配不是"回退"，而是按排序规则的精确匹配
-- 修复: 总是同时创建 'alice'@'localhost' 和 'alice'@'%'
--
-- 2.4 权限层级（5 级）
-- 全局:   GRANT ... ON *.* → mysql.user
-- 数据库: GRANT ... ON db.* → mysql.db
-- 表:     GRANT ... ON db.t → mysql.tables_priv
-- 列:     GRANT SELECT(col) ON db.t → mysql.columns_priv
-- 程序:   GRANT EXECUTE ON PROCEDURE → mysql.procs_priv
-- 每级有独立的授权表，权限检查按层级叠加（OR 关系）

-- ============================================================
-- 3. 8.0+ 角色 (Roles) 和部分撤销 (Partial Revokes)
-- ============================================================

-- 3.1 角色: 8.0+ 引入
CREATE ROLE 'app_read', 'app_write', 'app_admin';

GRANT SELECT ON mydb.* TO 'app_read';
GRANT INSERT, UPDATE, DELETE ON mydb.* TO 'app_write';
GRANT ALL PRIVILEGES ON mydb.* TO 'app_admin';

-- 将角色授予用户
GRANT 'app_read', 'app_write' TO 'alice'@'localhost';

-- 角色激活: MySQL 角色默认不激活！（与其他数据库不同）
SET DEFAULT ROLE ALL TO 'alice'@'localhost';  -- 登录时自动激活所有角色
-- 或运行时手动激活:
SET ROLE 'app_read';
SET ROLE ALL;        -- 激活所有已授予角色
SET ROLE NONE;       -- 不激活任何角色

-- 3.2 角色的内部实现
-- MySQL 角色本质上就是一个 "已锁定的用户":
--   CREATE ROLE 'app_read'  等价于  CREATE USER 'app_read'@'%' ACCOUNT LOCK
-- 角色和用户存储在同一张表 (mysql.user)，通过 account_locked 标志区分
-- 这意味着: 角色名和用户名不能冲突！

-- 3.3 部分撤销 (Partial Revokes, 8.0.16+)
-- 解决的问题: 之前无法"授予全局权限但排除某个数据库"
SET GLOBAL partial_revokes = ON;

-- 先授予全局权限，再排除 mysql 系统库
GRANT SELECT ON *.* TO 'analyst'@'%';
REVOKE SELECT ON mysql.* FROM 'analyst'@'%';
-- analyst 可以查询所有数据库，但不能查询 mysql 系统库

-- 部分撤销的实现: 存储在 mysql.user 的 User_attributes JSON 列中
-- 这是 MySQL 首次用 JSON 列存储系统元数据（不同于传统的列模式）

-- ============================================================
-- 4. 密码策略和账户管理（8.0+）
-- ============================================================

-- 4.1 密码过期
ALTER USER 'alice'@'localhost' PASSWORD EXPIRE;               -- 立即过期
ALTER USER 'alice'@'localhost' PASSWORD EXPIRE INTERVAL 90 DAY;
ALTER USER 'alice'@'localhost' PASSWORD EXPIRE NEVER;

-- 4.2 密码历史 (8.0.3+): 防止重复使用旧密码
ALTER USER 'alice'@'localhost' PASSWORD HISTORY 5;            -- 禁止使用最近 5 个密码
ALTER USER 'alice'@'localhost' PASSWORD REUSE INTERVAL 365 DAY;

-- 4.3 登录失败锁定 (8.0.19+)
ALTER USER 'alice'@'localhost' FAILED_LOGIN_ATTEMPTS 3 PASSWORD_LOCK_TIME 1;
-- 3 次失败后锁定 1 天

-- ============================================================
-- 5. 动态权限 (8.0+): 取代超级权限的碎片化
-- ============================================================

-- 5.7 及之前: SUPER 权限是万能权限（可以做任何管理操作）
-- 8.0+: SUPER 被拆分为细粒度的动态权限:
GRANT SYSTEM_VARIABLES_ADMIN ON *.* TO 'dba'@'localhost';  -- 修改系统变量
GRANT CONNECTION_ADMIN ON *.* TO 'dba'@'localhost';        -- 超过 max_connections 仍可连接
GRANT BACKUP_ADMIN ON *.* TO 'dba'@'localhost';            -- 执行备份操作
GRANT REPLICATION_SLAVE_ADMIN ON *.* TO 'dba'@'localhost'; -- 管理复制
GRANT ROLE_ADMIN ON *.* TO 'dba'@'localhost';              -- 管理角色
-- 总共 30+ 个动态权限（8.0 引入，持续增加中）
-- 原则: 最小权限原则，不再需要授予 SUPER

-- ============================================================
-- 6. 横向对比: 权限模型设计（对引擎开发者）
-- ============================================================

-- 6.1 PostgreSQL: RBAC (Role-Based Access Control)
-- PG 从一开始就统一了 user 和 role 的概念:
--   CREATE USER = CREATE ROLE ... LOGIN
--   CREATE ROLE = CREATE ROLE ... NOLOGIN（类似 MySQL 的 ACCOUNT LOCK）
-- 无 user@host 概念: 连接控制通过 pg_hba.conf 文件（与权限解耦）
-- 默认角色: pg_read_all_data, pg_write_all_data (14+)
-- 优势: 权限模型简洁，无 host 匹配的复杂性
-- 行级安全 (RLS): CREATE POLICY ... USING (...) -- MySQL 不支持

-- 6.2 Oracle: 传统 RBAC + Fine-Grained Access Control
-- 预定义角色: CONNECT, RESOURCE, DBA（非常古老但仍广泛使用）
-- VPD (Virtual Private Database): 自动附加 WHERE 条件实现行级过滤
-- Data Redaction: 查询结果中实时脱敏（DBMS_REDACT 包）
-- 无 user@host: 连接控制通过 listener + tnsnames.ora + sqlnet.ora

-- 6.3 SQL Server: Windows 集成认证 + RBAC
-- 双重认证: Windows 认证 (Kerberos/NTLM) + SQL Server 认证
-- 固定服务器角色: sysadmin, dbcreator, securityadmin 等
-- 固定数据库角色: db_owner, db_datareader, db_datawriter 等
-- EXECUTE AS: 临时切换执行上下文（类似 sudo）
-- 动态数据掩码: 对特定用户自动脱敏查询结果（类似 Oracle VPD）

-- 6.4 云数据库: IAM (Identity and Access Management)
-- BigQuery:  完全基于 Google Cloud IAM，无 SQL 级别的 CREATE USER
--            roles/bigquery.dataViewer, roles/bigquery.dataEditor
-- Snowflake: RBAC + 层级角色继承（ACCOUNTADMIN > SYSADMIN > 自定义角色）
--            与云 IAM 集成 (SCIM provisioning)
-- 趋势: 云数据库正在用 IAM 替代传统 SQL 权限语句

-- 对引擎开发者的启示:
--   1. user@host 模型是 MySQL 特有的历史设计，增加了复杂度但灵活性有限
--      现代设计应将认证（谁可以连接）和授权（连接后能做什么）解耦
--   2. 角色是必需品: 没有角色的权限管理在规模化后不可维护
--   3. 行级安全 (RLS) 是现代数据库的重要能力（PG, SQL Server, Oracle 都有）
--   4. 云原生引擎应从设计之初就对接 IAM（而非自建权限系统）
--   5. 动态权限（MySQL 8.0 拆分 SUPER 的做法）是正确方向:
--      避免"超级管理员"权限，实现最小权限原则

-- ============================================================
-- 7. 版本演进与最佳实践
-- ============================================================
-- MySQL 8.0: 角色, 动态权限, caching_sha2_password 默认
-- MySQL 8.0.16: 部分撤销 | 8.0.19: 登录锁定 | 8.0.27: MFA
--
-- 实践建议:
--   1. 永远不要用 'root'@'%'（不限制 root 的来源 IP）
--   2. 使用角色管理权限，不要直接 GRANT 给用户
--   3. 生产环境开启 partial_revokes，排除 mysql/information_schema
--   4. 应用账户只授予需要的最小权限（不要 ALL PRIVILEGES）
--   5. 定期审计: SELECT user, host, account_locked FROM mysql.user;
--   6. 使用 caching_sha2_password（默认），弃用 mysql_native_password
