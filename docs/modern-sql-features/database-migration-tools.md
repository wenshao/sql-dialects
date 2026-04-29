# 数据库迁移工具 (Database Migration Tools)

凌晨两点的紧急回滚，团队登录数据库准备执行 `db_v3_to_v2.sql`，却发现这个脚本根本不存在——上一次发版时只准备了"前进路径"，没有人写"回退路径"。Schema 版本管理（Schema Versioning）和数据库迁移工具（Database Migration Tools）的诞生，正是为了把"手写 SQL 脚本 + 邮件传递"的混沌状态，转化为像应用代码一样**可审查、可重放、可回滚、可校验**的工程实践。

本文聚焦**迁移工具的横向对比**——20+ 个主流工具的设计范式、能力边界、生态定位。它与 `schema-evolution.md`（Schema 演进模式）、`ddl-transactionality-online.md`（DDL 事务性与在线变更）形成一组三联文章：演进模式回答"应该怎么改"，事务性回答"引擎能否原子地改"，本文回答"用什么工具协调改"。

## 没有 SQL 标准

SQL:2003 标准定义了 `ALTER TABLE` 等 DDL 语法（ISO/IEC 9075-2, Section 11），但**完全没有定义 schema 版本管理的概念**：没有标准的版本表、没有标准的迁移文件格式、没有标准的回滚机制。每个工具都自行设计了：

1. **状态存储**：存放"当前 schema 版本"的元数据表（`schema_migrations`、`flyway_schema_history`、`databasechangelog` 等命名各异）
2. **迁移文件格式**：SQL、Python、Ruby、XML、YAML、JSON、HCL 各家都有
3. **版本号方案**：时间戳、整数、语义化版本（SemVer）、Plan 依赖图
4. **校验和算法**：MD5、SHA-256、CRC32 用于检测已应用迁移的篡改
5. **回滚策略**：双向迁移文件（up/down）、声明式 diff、不支持回滚

这种碎片化导致：跨团队、跨项目、跨语言栈的迁移脚本几乎无法互通。一个 Django 项目转向 Go 后端，过去几年的 Django migrations 几乎只能保留为历史包袱，新代码用 golang-migrate 从头开始。

## 工具支持矩阵（25+ 工具综合）

> 注：本表中"支持的数据库"列出工具明确文档化或主流社区报告可用的引擎，并非穷举。"声明式"指工具计算当前 schema 与目标 schema 的差异；"命令式"指开发者编写明确的变更步骤。

| 工具 | 范式 | 主语言 | 主要 DB 支持 | 校验和 | 事务迁移 | Baseline | 回滚 |
|------|------|-------|---------------|-------|---------|----------|------|
| Liquibase | 命令式 (changeset) | Java | 60+ (PG, MySQL, Oracle, MSSQL, DB2, ...) | MD5/SHA1 | 是 (rollback tag) | `changelogSync` | 是 (内置) |
| Flyway | 命令式 (versioned + repeatable) | Java | 30+ (PG, MySQL, Oracle, MSSQL, ...) | CRC32 | 是 (大部分) | `baseline` | 商业版 |
| sqitch | 命令式 (plan + 依赖图) | Perl | PG, MySQL, Oracle, SQLite, Snowflake, ... | SHA-1 (Git) | 是 | `init` | 是 (revert) |
| Alembic | 命令式 (Python) | Python | SQLAlchemy 支持的所有 | -- | 是 (PG/MSSQL) | `stamp` | 是 (downgrade) |
| Django migrations | 命令式 (Python) | Python | PG, MySQL, SQLite, Oracle | -- | 部分 (依引擎) | `--fake-initial` | 是 (migrate <app> <ver>) |
| Active Record | 命令式 (Ruby) | Ruby | PG, MySQL, SQLite, Oracle, MSSQL | -- | 是 (PG) | `assume_schema` | 是 (down) |
| Knex.js | 命令式 (JS) | JavaScript | PG, MySQL, SQLite, MSSQL, Oracle, CockroachDB | -- | 是 | -- | 是 (rollback) |
| Atlas | 声明式 + 命令式 | Go | PG, MySQL, MariaDB, SQLite, MSSQL, ClickHouse, ... | SHA-256 | 是 | `migrate apply --baseline` | 是 (down) |
| Bytebase | 声明式 + GitOps | Go | PG, MySQL, Oracle, Snowflake, TiDB, ... | -- | 是 | 是 | 部分 |
| Schemachange | 命令式 (Snowflake) | Python | Snowflake | SHA-256 | -- (Snowflake DDL 自动提交) | 是 | 否 |
| db-migrate | 命令式 | JavaScript | PG, MySQL, SQLite, MongoDB | -- | 部分 | -- | 是 |
| dbmate | 命令式 (SQL) | Go | PG, MySQL, SQLite, ClickHouse | -- | 是 | -- | 是 (down) |
| golang-migrate | 命令式 (SQL) | Go | PG, MySQL, SQLite, MSSQL, Cassandra, ClickHouse, MongoDB, Spanner, CockroachDB, Snowflake, Redshift, ... | -- | 是 | `force` | 是 (down) |
| Tern | 命令式 (SQL) | Go | PG | -- | 是 | -- | 是 |
| Phinx | 命令式 (PHP) | PHP | PG, MySQL, SQLite, MSSQL | -- | 是 (PG) | -- | 是 |
| Skeema | 声明式 (MySQL DDL) | Go | MySQL, MariaDB, TiDB | -- | 否 (online DDL) | `pull` | 否 (重新生成) |
| gh-ost | 在线 DDL (非迁移工具) | Go | MySQL | -- | 否 (binlog 复制) | -- | 否 |
| pt-online-schema-change | 在线 DDL (非迁移工具) | Perl | MySQL, MariaDB | -- | 否 (触发器复制) | -- | 否 |
| Pigsty | 部署 + DDL 模板 | Ansible | PG | -- | 是 (PG) | -- | 否 |
| dbt | 数据转换 (SQL/Jinja) | Python | Snowflake, BigQuery, Redshift, PG, Spark, Databricks, ... | -- | 部分 (incremental) | -- | 否 (重建模型) |
| pg_repack | 在线表重组 (非迁移工具) | C | PG | -- | 否 (触发器复制) | -- | 否 |
| pgsodium / pgrun | PG 扩展工具 | C/SQL | PG | -- | 是 | -- | -- |
| Migra | 声明式 (PG diff) | Python | PG | -- | -- | -- | -- |
| Apgdiff | 声明式 (PG diff) | Java | PG | -- | -- | -- | -- |
| Sqlpackage / DACPAC | 声明式 | .NET | MSSQL | -- | 是 | 是 | 部分 |
| Schema Hero | 声明式 (K8s CRD) | Go | PG, MySQL, RQLite, Cassandra | -- | 是 | -- | -- |
| Goose | 命令式 (SQL/Go) | Go | PG, MySQL, SQLite, MSSQL, Redshift, ClickHouse | -- | 是 | -- | 是 (down) |

> 统计：约 18 个工具采用纯命令式范式（写明确的变更脚本），约 6 个工具采用声明式范式（计算 diff），约 3 个工具支持双模式（Atlas、Bytebase、部分 Liquibase 用法）。命令式仍然是主流。

### 数据库专精度分类

| 类别 | 代表工具 | 设计取向 |
|------|---------|---------|
| 全引擎通用 | Liquibase, Flyway, sqitch, Atlas, Bytebase | 抽象差异，跨引擎复用 |
| 单生态深度集成 | Active Record (Ruby), Django (Python), Alembic (SQLAlchemy), Knex.js (Node), Phinx (PHP) | 与 ORM 深度绑定 |
| 单引擎专精 | Schemachange (Snowflake), Skeema (MySQL), pg_repack (PG) | 利用引擎特定能力 |
| 在线 DDL 辅助 | gh-ost, pt-online-schema-change, pg_repack | 不是迁移工具，是 DDL 执行器 |
| 数据转换工具 | dbt, Dataform | 不是 schema 工具，是数据建模工具 |

## 范式对比：声明式 vs 命令式

迁移工具的根本设计选择是**范式（paradigm）**：开发者描述"做什么"，还是描述"怎么做"。

### 命令式（Imperative）

```sql
-- Flyway 风格: V001__create_users.sql
CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    email VARCHAR(255) NOT NULL UNIQUE,
    created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

-- V002__add_user_status.sql
ALTER TABLE users ADD COLUMN status VARCHAR(20) NOT NULL DEFAULT 'active';
```

```python
# Alembic 风格: alembic/versions/abc123_add_user_status.py
def upgrade():
    op.add_column('users', sa.Column('status', sa.String(20), nullable=False, server_default='active'))

def downgrade():
    op.drop_column('users', 'status')
```

特点：
- 开发者明确写 `CREATE`、`ALTER`、`DROP` 语句
- 工具按顺序执行未应用的迁移
- 行为可预测、容易审查
- 但**没有"目标 schema"概念**，只有"变更历史"

### 声明式（Declarative）

```hcl
// Atlas 风格: schema.hcl
table "users" {
    schema = schema.public
    column "id" {
        type = serial
    }
    column "email" {
        type = varchar(255)
        null = false
    }
    column "status" {
        type = varchar(20)
        null = false
        default = "active"
    }
    primary_key {
        columns = [column.id]
    }
}
```

```bash
# Atlas 计算当前 schema 与目标的 diff，生成 ALTER 语句
$ atlas migrate diff --to file://schema.hcl
# Output: 20240301120000_add_user_status.sql:
#   ALTER TABLE users ADD COLUMN status VARCHAR(20) NOT NULL DEFAULT 'active';
```

特点：
- 开发者维护**期望状态**，工具计算变更步骤
- 类似 Kubernetes 声明式资源、Terraform IaC
- 上手简单（只描述目标），但**复杂数据迁移难表达**（如重命名列、数据回填）
- 风险：自动生成的 DDL 可能与人类预期不符

### 混合范式

| 工具 | 实现方式 |
|------|---------|
| Atlas | 声明式 schema 文件 + 自动生成命令式迁移文件 + 人工审查 |
| Bytebase | GitOps 声明式 + 工单审批 + 命令式 SQL |
| Liquibase | 主要命令式，但支持 `<diffChangelog>` 命令做声明式比对 |
| Schemachange | 纯命令式，但 Snowflake 本身的 `CREATE OR REPLACE` 提供了部分声明式特性 |

实践中**混合是大势所趋**：声明式描述目标，命令式描述演进路径，工具负责生成变更并保留人工审查环节。

## 工具深度对比

### Liquibase：变更集（Changeset）模型

Liquibase 由 Nathan Voxland 于 2007 年开源，是最早的跨引擎 schema 迁移工具之一。核心抽象是**变更集（changeset）**——每个 changeset 是一个原子的、可独立追踪的变更单元，由 `id + author + filename` 三元组唯一标识。

```xml
<!-- changelog.xml -->
<?xml version="1.0" encoding="UTF-8"?>
<databaseChangeLog
    xmlns="http://www.liquibase.org/xml/ns/dbchangelog"
    xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
    xsi:schemaLocation="http://www.liquibase.org/xml/ns/dbchangelog
        http://www.liquibase.org/xml/ns/dbchangelog/dbchangelog-4.10.xsd">

    <changeSet id="001-create-users" author="alice">
        <createTable tableName="users">
            <column name="id" type="bigint" autoIncrement="true">
                <constraints primaryKey="true" nullable="false"/>
            </column>
            <column name="email" type="varchar(255)">
                <constraints nullable="false" unique="true"/>
            </column>
        </createTable>
        <rollback>
            <dropTable tableName="users"/>
        </rollback>
    </changeSet>

    <changeSet id="002-add-status" author="bob">
        <addColumn tableName="users">
            <column name="status" type="varchar(20)" defaultValue="active">
                <constraints nullable="false"/>
            </column>
        </addColumn>
    </changeSet>
</databaseChangeLog>
```

```yaml
# 同样的内容也可以用 YAML 表达
databaseChangeLog:
  - changeSet:
      id: 001-create-users
      author: alice
      changes:
        - createTable:
            tableName: users
            columns:
              - column: { name: id, type: bigint, autoIncrement: true, constraints: { primaryKey: true } }
              - column: { name: email, type: varchar(255), constraints: { nullable: false, unique: true } }
```

```sql
-- 也可以用纯 SQL 格式: changelog.sql
--liquibase formatted sql

--changeset alice:001-create-users
CREATE TABLE users (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    email VARCHAR(255) NOT NULL UNIQUE
);
--rollback DROP TABLE users;

--changeset bob:002-add-status
ALTER TABLE users ADD COLUMN status VARCHAR(20) NOT NULL DEFAULT 'active';
```

#### 跟踪表：DATABASECHANGELOG

```sql
-- Liquibase 在数据库中维护两张表
CREATE TABLE DATABASECHANGELOG (
    ID            VARCHAR(255) NOT NULL,
    AUTHOR        VARCHAR(255) NOT NULL,
    FILENAME      VARCHAR(255) NOT NULL,
    DATEEXECUTED  TIMESTAMP NOT NULL,
    ORDEREXECUTED INT NOT NULL,
    EXECTYPE      VARCHAR(10) NOT NULL,  -- EXECUTED / RERAN / FAILED / SKIPPED / MARK_RAN
    MD5SUM        VARCHAR(35),
    DESCRIPTION   VARCHAR(255),
    COMMENTS      VARCHAR(255),
    TAG           VARCHAR(255),
    LIQUIBASE     VARCHAR(20),
    CONTEXTS      VARCHAR(255),
    LABELS        VARCHAR(255),
    DEPLOYMENT_ID VARCHAR(10)
);

CREATE TABLE DATABASECHANGELOGLOCK (
    ID          INT NOT NULL PRIMARY KEY,
    LOCKED      BOOLEAN NOT NULL,
    LOCKGRANTED TIMESTAMP,
    LOCKEDBY    VARCHAR(255)
);
```

#### Liquibase 的关键能力

```bash
# 应用迁移
liquibase update

# 应用到指定标签
liquibase update-to-tag --tag=v1.0.0

# 回滚到指定标签
liquibase rollback --tag=v0.9.0

# 回滚最近 3 个 changeset
liquibase rollback-count 3

# 生成回滚 SQL（不执行）
liquibase rollback-sql --tag=v0.9.0

# 比较两个数据库
liquibase diff --reference-url=jdbc:postgresql://prod-db --url=jdbc:postgresql://staging-db

# 生成新的 changelog（声明式入口）
liquibase generate-changelog

# 同步现有数据库（baseline）
liquibase changelog-sync
```

#### 校验和与篡改检测

```
Liquibase 在每个 changeset 上计算 MD5SUM(默认) 或 SHA1，存入 DATABASECHANGELOG.MD5SUM 列。

如果开发者修改了已应用的 changeset:
  $ liquibase update
  ERROR: Validation Failed: change set 001-create-users.xml::001-create-users::alice
                            has changed since it was ran against the database

恢复策略:
  1. 用 <validCheckSum>any</validCheckSum> 强制接受新校验和（危险）
  2. 用 liquibase clear-checksums 重置所有校验和
  3. 创建新的 changeset 修正问题（推荐）
```

#### Liquibase Pro vs OSS

| 功能 | OSS | Pro (商业) |
|------|-----|------------|
| 基础 changelog | 是 | 是 |
| 多种格式（XML/YAML/JSON/SQL） | 是 | 是 |
| Rollback | 是 | 是 |
| Targeted rollback | 部分 | 完整 |
| 操作审计与策略 | -- | 是 |
| Snowflake 优化 | 部分 | 是 |
| Drift detection | -- | 是 |
| Flow files (DAG 编排) | -- | 是 |

### Flyway：版本化与可重复迁移

Flyway 由 Axel Fontaine 于 2010 年开源（后被 Redgate 收购），核心理念是**简单优于全面**：默认只支持纯 SQL 迁移，文件名约定即版本号。

#### 文件命名规范

```
V<VERSION>__<DESCRIPTION>.sql       # Versioned: 仅运行一次，按版本号顺序
R__<DESCRIPTION>.sql                 # Repeatable: 校验和变化时重新运行
U<VERSION>__<DESCRIPTION>.sql       # Undo (商业版): 回滚版本化迁移
B<VERSION>__<DESCRIPTION>.sql       # Baseline: 设定起点

示例:
  V1__create_users.sql
  V1.1__add_user_status.sql
  V2.0.0__add_orders_table.sql
  V20240301120000__add_audit_columns.sql   # 时间戳风格
  R__refresh_views.sql                       # 视图重建
  R__seed_reference_data.sql                # 参考数据
```

#### 跟踪表：flyway_schema_history

```sql
CREATE TABLE flyway_schema_history (
    installed_rank  INT NOT NULL,
    version         VARCHAR(50),       -- NULL for repeatable
    description     VARCHAR(200) NOT NULL,
    type            VARCHAR(20) NOT NULL,  -- SQL / JDBC / SCRIPT / BASELINE / SCHEMA / DELETE
    script          VARCHAR(1000) NOT NULL,
    checksum        INT,                -- CRC32
    installed_by    VARCHAR(100) NOT NULL,
    installed_on    TIMESTAMP NOT NULL,
    execution_time  INT NOT NULL,       -- ms
    success         BOOLEAN NOT NULL,
    PRIMARY KEY (installed_rank)
);

CREATE INDEX flyway_schema_history_s_idx ON flyway_schema_history (success);
```

#### Versioned vs Repeatable 的区别

```
Versioned 迁移 (V):
  - 每个版本号只运行一次
  - 校验和被记录，后续验证篡改
  - 严格按版本号升序应用
  - 用于: schema 变更（CREATE TABLE / ALTER TABLE）

Repeatable 迁移 (R):
  - 没有版本号
  - 在每次 migrate 时检查校验和
  - 校验和变化时重新运行
  - 在所有 V 之后运行
  - 用于: 视图、存储过程、函数、参考数据
  - 必须使用幂等 SQL（CREATE OR REPLACE / DROP IF EXISTS）

执行顺序示例:
  V1 → V2 → V3 → R__view_a → R__view_b → R__seed_data
```

```sql
-- R__create_active_users_view.sql
-- Repeatable 迁移示例: 必须幂等
CREATE OR REPLACE VIEW active_users AS
SELECT id, email, status
FROM users
WHERE status = 'active'
  AND deleted_at IS NULL;
```

#### Flyway 关键命令

```bash
# 应用所有未应用的迁移
flyway migrate

# 应用到指定版本（不超过该版本）
flyway migrate -target=2.1.5

# 验证已应用迁移的校验和（不执行新迁移）
flyway validate

# 修复跟踪表（清理失败记录、更新校验和）
flyway repair

# 显示迁移状态
flyway info

# 回滚（仅商业版）
flyway undo

# 清空数据库（仅开发环境）
flyway clean

# 设定 baseline（已有数据库）
flyway baseline -baselineVersion=1.0
```

#### Flyway 校验和与篡改检测

```
默认使用 CRC32（32 位整数），校验和值存储在 flyway_schema_history.checksum 列。

校验范围: 仅文件内容（不含文件名、注释除外）。

修改已应用的 V 文件后:
  $ flyway migrate
  ERROR: Validate failed: Migration checksum mismatch for migration version 1
         -> Applied to database : 12345678
         -> Resolved locally    : 87654321

恢复策略:
  1. flyway repair 更新校验和（接受当前文件）
  2. 创建 V<下一个版本>__修复.sql 修正问题（推荐）
```

#### Flyway 的事务性行为

```
默认情况下:
  - 每个迁移在自己的事务中执行
  - 失败的迁移会回滚（事务支持的引擎）
  - 失败状态被记录到 flyway_schema_history（success=false）

例外情况:
  - MySQL: DDL 自动提交，不可回滚
  - Oracle: DDL 隐式提交
  - 包含 CREATE INDEX CONCURRENTLY 的 PostgreSQL 文件: 不能在事务中执行
    解决: 在文件中使用 -- ##NOT IN TRANSACTION## 注释，或拆分文件
```

### sqitch：Plan 与依赖图

David Wheeler 于 2012 年创建 sqitch（Sagitta，箭头），核心创新是**显式依赖图**而非顺序版本号。

#### Plan 文件

```
%syntax-version=1.0.0
%project=widgets
%uri=https://github.com/example/widgets

# Format: <change_name> [requires] <timestamp> <author> # <description>
appschema 2024-01-15T10:00:00Z Alice <alice@ex.com> # Add application schema
users [appschema] 2024-01-16T10:00:00Z Alice <alice@ex.com> # Create users table
sessions [users] 2024-01-17T10:00:00Z Bob <bob@ex.com> # Add sessions table
audit_log [appschema users] 2024-01-18T10:00:00Z Carol <carol@ex.com> # Audit log
@v1.0 2024-01-20T10:00:00Z Alice # Tag v1.0
```

每次变更生成三个文件：
```
deploy/users.sql        -- 部署脚本
revert/users.sql        -- 回滚脚本
verify/users.sql        -- 验证脚本（执行 SQL 测试）
```

```sql
-- deploy/users.sql
BEGIN;

CREATE TABLE users (
    id BIGSERIAL PRIMARY KEY,
    email VARCHAR(255) NOT NULL UNIQUE,
    created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

COMMIT;

-- revert/users.sql
BEGIN;
DROP TABLE users;
COMMIT;

-- verify/users.sql
BEGIN;
SELECT id, email, created_at FROM users WHERE FALSE;
ROLLBACK;
```

#### sqitch 的核心命令

```bash
# 初始化项目
sqitch init mywidgets --uri https://example.com/mywidgets --engine pg

# 添加变更
sqitch add users -n 'Create users table'
sqitch add sessions -r users -n 'Sessions depend on users'

# 部署到目标
sqitch deploy db:pg://localhost/mywidgets

# 回滚（默认回滚最新一个）
sqitch revert db:pg://localhost/mywidgets

# 回滚到指定 tag
sqitch revert --to @v1.0 db:pg://localhost/mywidgets

# 重新部署（用于开发: revert 然后 deploy）
sqitch rebase db:pg://localhost/mywidgets

# 检查状态
sqitch status db:pg://localhost/mywidgets

# 验证已部署的变更
sqitch verify db:pg://localhost/mywidgets
```

#### sqitch 与其他工具的差异

```
sqitch 的独特设计:
  1. 依赖图: 变更通过 [requires] 声明依赖，不是简单的版本号顺序
  2. Verify 脚本: 部署后自动运行验证 SQL 测试
  3. 与 Git 深度集成: 使用 Git 哈希作为变更 ID，支持分支合并
  4. 不修改数据库: sqitch 不会自动添加列或表，所有变更必须显式编写
  5. 多目标部署: 同一份 plan 可以部署到 dev / staging / prod 多个环境
```

### Alembic：Python 与 SQLAlchemy

Mike Bayer（SQLAlchemy 作者）于 2012 年创建 Alembic，是 Python 生态最主流的迁移工具，深度集成 SQLAlchemy ORM。

#### 自动生成迁移

```python
# alembic/env.py 配置
from myapp.models import Base
target_metadata = Base.metadata

# 命令: 自动检测模型与数据库的差异
# $ alembic revision --autogenerate -m "add user status column"
```

```python
# alembic/versions/abc123_add_user_status_column.py
"""add user status column

Revision ID: abc123
Revises: def456
Create Date: 2024-03-01 12:00:00.000000

"""
from alembic import op
import sqlalchemy as sa

revision = 'abc123'
down_revision = 'def456'
branch_labels = None
depends_on = None


def upgrade():
    op.add_column('users',
        sa.Column('status', sa.String(20), nullable=False, server_default='active'))
    op.create_index('idx_users_status', 'users', ['status'])


def downgrade():
    op.drop_index('idx_users_status', table_name='users')
    op.drop_column('users', 'status')
```

#### 修订版本图（DAG）

```
Alembic 使用 revision ID + down_revision 链式结构，支持分支与合并。

线性历史:
  abc123 (head) ← def456 ← ghi789 ← <base>

分支:
  branch1: xyz111 ← abc123
  branch2: xyz222 ← abc123

合并:
  merged: combined123 ← (xyz111, xyz222)

命令:
  alembic upgrade head           # 升级到最新
  alembic upgrade +1             # 升级 1 个版本
  alembic upgrade abc123         # 升级到指定版本
  alembic downgrade -1           # 回退 1 个版本
  alembic downgrade base         # 回退到初始
  alembic merge xyz111 xyz222 -m "merge branches"   # 合并分支
  alembic stamp head             # 标记当前版本（不执行）
```

#### Alembic 与 SQLAlchemy ORM

```python
# 自动生成对 SQLAlchemy 模型变更的迁移
# myapp/models.py
class User(Base):
    __tablename__ = 'users'
    id = Column(Integer, primary_key=True)
    email = Column(String(255), nullable=False, unique=True)
    status = Column(String(20), nullable=False, server_default='active')  # 新增

# 运行: alembic revision --autogenerate -m "add status"
# Alembic 比较 User 模型与数据库 schema，生成 op.add_column 调用
```

#### Alembic 的局限

```
自动生成的局限:
  1. 不能检测列重命名: 会被识别为 drop_column + add_column
  2. 不能检测约束变更的某些细节
  3. 检查约束（CHECK constraint）的差异检测有限
  4. 不支持触发器、视图、存储过程等数据库对象
  5. 跨表数据迁移必须手动编写

最佳实践:
  alembic revision --autogenerate 后必须人工审查生成的代码
```

### Django Migrations：与 ORM 一体化

Django 1.7（2014）内置 migrations，与 Django ORM 完全集成，是 Python Web 生态最大用户基数的迁移系统。

```python
# myapp/models.py
class User(models.Model):
    email = models.EmailField(unique=True)
    status = models.CharField(max_length=20, default='active')  # 新增字段
    created_at = models.DateTimeField(auto_now_add=True)
```

```bash
# 自动生成迁移
$ python manage.py makemigrations
Migrations for 'myapp':
  myapp/migrations/0002_user_status.py
    - Add field status to user

# 应用迁移
$ python manage.py migrate

# 查看 SQL（不执行）
$ python manage.py sqlmigrate myapp 0002

# 回滚到指定迁移
$ python manage.py migrate myapp 0001
```

```python
# myapp/migrations/0002_user_status.py
from django.db import migrations, models

class Migration(migrations.Migration):
    dependencies = [
        ('myapp', '0001_initial'),
    ]

    operations = [
        migrations.AddField(
            model_name='user',
            name='status',
            field=models.CharField(default='active', max_length=20),
        ),
    ]
```

#### Django Migrations 的关键特性

```
依赖图: dependencies 列表声明前置迁移
  - 默认: 同 app 内的上一个 migration
  - 跨 app: dependencies = [('other_app', '0005_xxx')]

数据迁移 (data migration):
  operations = [
      migrations.RunPython(
          forward_func,
          reverse_code=reverse_func,
      ),
  ]

原始 SQL:
  operations = [
      migrations.RunSQL(
          sql='UPDATE users SET status = \'active\' WHERE status IS NULL',
          reverse_sql='UPDATE users SET status = NULL WHERE status = \'active\'',
      ),
  ]

跟踪表: django_migrations
  CREATE TABLE django_migrations (
      id SERIAL PRIMARY KEY,
      app VARCHAR(255) NOT NULL,
      name VARCHAR(255) NOT NULL,
      applied TIMESTAMP NOT NULL
  );
```

#### Django 的 squashing（迁移合并）

```bash
# 把 0001~0050 多个迁移合并成一个
$ python manage.py squashmigrations myapp 0001 0050
# 生成 0001_squashed_0050_xxx.py，原文件可以删除
```

squashing 是 Django 独特的能力——长期运行的项目可能有几百个迁移文件，应用 migrations 变慢，squash 后可以重置基线。

### Active Record Migrations：Rails 范式

Rails 是 ORM + migrations 一体化的开创者（2005 年），定义了"reversible migrations" 概念。

```ruby
# db/migrate/20240301120000_add_status_to_users.rb
class AddStatusToUsers < ActiveRecord::Migration[7.0]
  def change
    add_column :users, :status, :string, null: false, default: 'active'
    add_index :users, :status
  end
end
```

```bash
# 应用迁移
$ rails db:migrate

# 回滚
$ rails db:rollback                    # 回退最新一个
$ rails db:rollback STEP=3             # 回退 3 个

# 重置（开发环境）
$ rails db:reset
```

#### `change` 方法的 reversibility

```ruby
# Rails 自动反转可逆操作: add_column / create_table 等
class CreateUsers < ActiveRecord::Migration[7.0]
  def change
    create_table :users do |t|
      t.string :email, null: false
      t.string :status, default: 'active'
      t.timestamps
    end
  end
end

# 不可自动反转的操作必须分 up/down
class CustomMigration < ActiveRecord::Migration[7.0]
  def up
    execute "UPDATE users SET status = 'active' WHERE status IS NULL"
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
```

#### schema.rb 与 structure.sql

```ruby
# Rails 维护 db/schema.rb 作为当前 schema 快照（声明式风格）
ActiveRecord::Schema[7.0].define(version: 20240301120000) do
  create_table "users", force: :cascade do |t|
    t.string "email", null: false
    t.string "status", default: "active", null: false
    t.datetime "created_at", precision: nil, null: false
  end
  add_index "users", ["email"], unique: true
end

# 替代方案: db/structure.sql 是引擎原生 SQL dump
# config: config.active_record.schema_format = :sql
```

新部署的实例可以从 `schema.rb` 直接创建表，不必跑完所有 migrations。

### Knex.js：Node 生态

```javascript
// migrations/20240301120000_add_user_status.js
exports.up = function(knex) {
  return knex.schema.alterTable('users', (table) => {
    table.string('status', 20).notNullable().defaultTo('active');
    table.index('status');
  });
};

exports.down = function(knex) {
  return knex.schema.alterTable('users', (table) => {
    table.dropIndex('status');
    table.dropColumn('status');
  });
};
```

```bash
$ knex migrate:make add_user_status
$ knex migrate:latest
$ knex migrate:rollback
$ knex migrate:status
```

Knex 的特点：链式 API、支持 PG/MySQL/SQLite/MSSQL/Oracle/CockroachDB，与 Bookshelf.js / Objection.js ORM 集成。

### Atlas：声明式驱动

Atlas 由 Ariel "Ariga" 团队（也是 Ent ORM 作者）开发，是迁移工具领域**最现代的设计**——明确把声明式作为一等公民，同时保留命令式审查环节。

#### 声明式 schema（HCL / SQL）

```hcl
# atlas.hcl
table "users" {
    schema = schema.public

    column "id" {
        null = false
        type = bigint
        identity {
            generated = ALWAYS
        }
    }

    column "email" {
        null = false
        type = varchar(255)
    }

    column "status" {
        null    = false
        type    = varchar(20)
        default = "active"
    }

    primary_key {
        columns = [column.id]
    }

    index "idx_users_email" {
        unique  = true
        columns = [column.email]
    }
}

schema "public" {}
```

或 SQL 风格：

```sql
-- schema.sql
CREATE TABLE users (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    email VARCHAR(255) NOT NULL UNIQUE,
    status VARCHAR(20) NOT NULL DEFAULT 'active'
);

CREATE INDEX idx_users_status ON users(status);
```

#### 自动 diff 生成迁移

```bash
# 计算当前 schema 与目标的差异
$ atlas migrate diff add_user_status \
    --dir "file://migrations" \
    --to "file://schema.sql" \
    --dev-url "docker://postgres/15/dev"

# 生成 migrations/20240301120000_add_user_status.sql:
# ALTER TABLE users ADD COLUMN status VARCHAR(20) NOT NULL DEFAULT 'active';
# CREATE INDEX idx_users_status ON users(status);
```

`--dev-url` 是 Atlas 的关键创新——使用一个临时 Docker 数据库作为"参考实例"，先把当前 schema 应用到 dev 库，再 diff 到目标，确保生成的 SQL 在引擎实际执行可行。

#### Atlas 的迁移目录

```
migrations/
├── 20240301120000_initial.sql
├── 20240302150000_add_user_status.sql
├── 20240303120000_add_orders_table.sql
└── atlas.sum                    # 校验和文件（哈希链）
```

```
# atlas.sum 内容示例
h1:abcdef0123456789...           # 整个目录的 hash
20240301120000_initial.sql       h1:0123abc...
20240302150000_add_user_status.sql h1:def456...
```

整个目录使用**哈希链**校验，类似 Go modules 的 go.sum——任何文件被篡改都会被检测出来。

#### Atlas 的关键命令

```bash
# 应用迁移
atlas migrate apply --url "postgres://..." --dir "file://migrations"

# 干跑模式（仅打印 SQL）
atlas migrate apply --dry-run --url "..." --dir "file://migrations"

# Lint: 检测危险变更
atlas migrate lint --dir "file://migrations" --dev-url "..."

# 状态查询
atlas migrate status --url "..." --dir "file://migrations"

# 设定 baseline
atlas migrate apply --baseline 20240101000000 --url "..."

# 重新生成校验和
atlas migrate hash --dir "file://migrations"

# 直接应用 schema（无迁移文件，类似 terraform apply）
atlas schema apply --url "postgres://..." --to "file://schema.sql"
```

#### Atlas 的 Lint 检查

```
Atlas migrate lint 内置规则:
  - DS101: 删除 schema 风险
  - DS102: 删除表风险
  - DS103: 删除非空列
  - MF101: 添加 NOT NULL 列无默认值
  - MF103: 修改非空约束
  - BC101: 重命名表（破坏向后兼容）
  - PG: PostgreSQL 特定规则（如 ADD COLUMN with DEFAULT 在 PG < 11 锁表）
  - MY: MySQL 特定规则
  - LT: 在线变更检测（基于 gh-ost / pt-osc）

示例:
  $ atlas migrate lint --dir "file://migrations" --dev-url "docker://mysql/8/dev"
  Analyzing changes from version 20240301 to 20240302 (1 migration in total):

    -- analyzing version 20240302150000:
      L2: Adding a non-nullable column "status" without a default value to table
          "users" will fail (MF101)
```

#### Atlas Pro vs OSS

| 功能 | OSS | Pro / Cloud |
|------|-----|-------------|
| 声明式 schema | 是 | 是 |
| 自动 diff | 是 | 是 |
| Lint 基础规则 | 是 | 是 |
| Lint 高级规则（破坏性、性能） | 部分 | 完整 |
| Drift detection | -- | 是 |
| Schema 监控 | -- | 是 |
| Atlas Cloud（中央化迁移管理） | -- | 是 |
| 与 GitHub Actions 集成 | 是 | 增强 |

### Bytebase：GitOps 与工单

Bytebase 是面向**多团队协作**的迁移平台，把 schema 变更视为工单流程，包含审批、SQL 审查、变更窗口、回滚。

```yaml
# bytebase 项目结构
bytebase/
├── projects/
│   └── myapp/
│       ├── schema/
│       │   ├── public.sql           # 声明式 schema
│       │   └── migrations/
│       │       └── 20240301_v1.0.sql
│       └── config.yaml
└── pipelines/
    └── deploy.yaml                  # CI/CD 集成
```

Bytebase 的特色：
- **GitOps 工作流**：开发者在 Git 提交 schema 变更 → Bytebase 自动创建工单 → DBA 审批 → 应用
- **SQL 审查规则**：90+ 内置规则，如"DROP TABLE 必须人工审批"、"ALTER TABLE 大表必须用 gh-ost"
- **多数据库类型**：PG, MySQL, Oracle, MSSQL, MongoDB, Snowflake, TiDB, ClickHouse
- **Drift detection**：定期比对生产 schema 与 Git 主干，检测意外变更
- **基于角色的访问控制**：开发者只能提交、DBA 才能审批和应用

### Schemachange：Snowflake 专精

Snowflake 官方维护的迁移工具，是 Flyway 风格的简化版。

```
migrations/
├── V1.0.0__create_database.sql
├── V1.0.1__create_users_table.sql
├── V1.0.2__add_status_column.sql
└── R__refresh_views.sql
```

```sql
-- V1.0.1__create_users_table.sql
CREATE TABLE {{ database_name }}.public.users (
    id NUMBER AUTOINCREMENT,
    email VARCHAR(255) NOT NULL,
    status VARCHAR(20) DEFAULT 'active',
    created_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);
```

特点：
- **Jinja 模板**：`{{ database_name }}` 等变量在执行时替换
- **针对 Snowflake**：利用 Snowflake 的 `CREATE OR REPLACE`、零拷贝克隆
- **不支持回滚**：Snowflake DDL 自动提交，回滚必须手写新迁移
- **Time Travel 集成**：可以利用 Snowflake 的 Time Travel 做"事后回滚"

### golang-migrate：Go 生态首选

golang-migrate 是 Go 社区最广泛使用的迁移库，支持 30+ 引擎。

```
migrations/
├── 000001_init_users.up.sql
├── 000001_init_users.down.sql
├── 000002_add_status.up.sql
└── 000002_add_status.down.sql
```

```sql
-- 000001_init_users.up.sql
CREATE TABLE users (
    id BIGSERIAL PRIMARY KEY,
    email VARCHAR(255) NOT NULL UNIQUE
);

-- 000001_init_users.down.sql
DROP TABLE users;
```

```bash
# CLI 用法
$ migrate -path ./migrations -database "postgres://..." up
$ migrate -path ./migrations -database "postgres://..." down 1
$ migrate -path ./migrations -database "postgres://..." goto 5
$ migrate -path ./migrations -database "postgres://..." force 3
$ migrate -path ./migrations -database "postgres://..." version
```

```go
// Go 代码集成
import (
    "github.com/golang-migrate/migrate/v4"
    _ "github.com/golang-migrate/migrate/v4/database/postgres"
    _ "github.com/golang-migrate/migrate/v4/source/file"
)

m, _ := migrate.New("file://migrations", "postgres://...")
m.Up()       // 应用所有
m.Steps(2)   // 前进 2 步
m.Down()     // 回退所有
```

### dbmate / Goose / Tern：轻量替代

| 工具 | 特点 |
|------|------|
| dbmate | 单二进制、跨语言、SQL-only、CLI 友好 |
| Goose | 支持 Go 函数迁移、嵌入到应用、SQL 与 Go 双模式 |
| Tern | PG-only，简单可靠，CLI + Go 库 |

### Skeema：MySQL 声明式

Skeema 是 MySQL/MariaDB/TiDB 专精的**声明式工具**，把整个数据库 schema 视为目录结构，使用 `git push` 风格的命令应用。

```
schema/
├── production/
│   ├── mydb/
│   │   ├── users.sql        # CREATE TABLE users (...)
│   │   ├── orders.sql       # CREATE TABLE orders (...)
│   │   └── procedures/
│   │       └── update_stats.sql
│   └── .skeema              # 配置（host、user、port）
```

```bash
# 拉取生产 schema 到目录（baseline）
$ skeema pull production

# 比较目录与生产
$ skeema diff production

# 应用变更（声明式）
$ skeema push production --allow-unsafe

# Lint 检查
$ skeema lint
```

特色：
- **声明式 + MySQL 原生**：直接写 CREATE TABLE，工具计算 ALTER
- **集成 gh-ost / pt-osc**：大表自动用 online DDL 工具
- **不维护迁移历史**：每次 push 是声明式 apply，但有审计日志
- **TiDB 兼容**：支持 TiDB 的 INSTANT DDL 优化

### gh-ost / pt-online-schema-change：在线 DDL 引擎

> 重要区分：gh-ost 与 pt-online-schema-change（pt-osc）**不是迁移工具**——它们不维护版本历史、不应用迁移文件、不追踪 schema 状态。它们是**单条 ALTER TABLE 语句的在线执行引擎**，目的是绕过 MySQL 早期版本的锁表问题。

```bash
# pt-online-schema-change（基于触发器复制）
$ pt-online-schema-change \
    --alter "ADD COLUMN status VARCHAR(20) NOT NULL DEFAULT 'active'" \
    --execute \
    D=mydb,t=users

# gh-ost（基于 binlog 复制，无触发器）
$ gh-ost \
    --database=mydb \
    --table=users \
    --alter="ADD COLUMN status VARCHAR(20) NOT NULL DEFAULT 'active'" \
    --execute
```

工作原理：
1. 创建影子表 `_users_new`（new schema）
2. 把原表数据复制到影子表（pt-osc 用触发器，gh-ost 用 binlog）
3. 期间增量变更同步到影子表
4. 完成后用 RENAME 原子切换：`_users_new → users`、`users → _users_old`

迁移工具与在线 DDL 引擎的关系：
- **Skeema** 内置集成 gh-ost 和 pt-osc，自动选择
- **Atlas** 在 lint 阶段建议使用 gh-ost
- **Bytebase** 提供 gh-ost 工单类型
- **Liquibase / Flyway** 不直接集成，但可以在迁移脚本中调用 shell

### pg_repack：PostgreSQL 在线表重组

pg_repack 同样**不是迁移工具**，而是 PostgreSQL 的**在线 VACUUM FULL 替代品**——在不锁表的情况下回收空间、重建索引、消除膨胀。

```bash
# 重组单表
$ pg_repack -d mydb -t users

# 重组数据库所有表
$ pg_repack -d mydb -a

# 仅重建索引
$ pg_repack -d mydb -t users --only-indexes
```

工作原理：基于触发器复制（与 pt-osc 类似），创建新表 → 复制数据 → 切换。常用于：
- 大批量删除后回收空间
- 索引膨胀重建
- 改变表的 fillfactor

### dbt：数据转换而非 schema 工具

dbt（data build tool）是数据工程领域的**模型构建工具**，不是 schema 迁移工具。

```sql
-- models/marts/active_users.sql
{{ config(materialized='incremental', unique_key='user_id') }}

SELECT
    user_id,
    last_login,
    status
FROM {{ ref('users') }}
WHERE status = 'active'

{% if is_incremental() %}
    AND last_login > (SELECT MAX(last_login) FROM {{ this }})
{% endif %}
```

dbt 的范畴：
- **模型构建**：从源表派生分析模型（dimensions, facts, marts）
- **数据测试**：声明式数据质量测试
- **文档生成**：自动生成数据血缘
- **不管理 schema**：不做 ALTER TABLE，依赖 CREATE OR REPLACE

dbt 与迁移工具的关系：互补而非竞争。Schema 变更用迁移工具，数据建模用 dbt。

### 工具组合实例

```
典型 PostgreSQL 项目栈:
  - Schema 变更: Atlas（声明式）或 sqitch（命令式）
  - 应用 ORM: SQLAlchemy + Alembic（自动 diff）
  - 在线表重组: pg_repack
  - 数据建模: dbt

典型 MySQL 项目栈:
  - Schema 变更: Skeema（声明式）或 Liquibase（命令式）
  - 在线 DDL: gh-ost（大表）
  - 应用框架: Rails (ActiveRecord) / Django

典型 Snowflake 项目栈:
  - Schema 变更: Schemachange + Liquibase Pro
  - 数据建模: dbt
  - 编排: Airflow / Dagster
```

## 跨工具能力对比

### 校验和算法对比

| 工具 | 算法 | 校验范围 |
|------|------|---------|
| Liquibase | MD5 (默认) / SHA1 | 整个 changeset 的标准化内容 |
| Flyway | CRC32 | 文件内容（去除注释和空白） |
| sqitch | SHA-1 (Git) | 部署、回滚、验证三个文件 |
| Atlas | SHA-256 (整目录哈希链) | 整个迁移目录 |
| Schemachange | SHA-256 | 单个文件 |
| Alembic / Django / Rails | -- | 不强制校验，依赖 revision ID |
| golang-migrate / dbmate | -- | 不校验 |

校验和的目的是**检测已应用迁移的篡改**——如果一个迁移在 dev 环境改过，部署到 prod 时被发现校验和不一致，必须人工干预。这是防止"开发者改了已发版迁移"的关键安全网。

### 事务性支持对比

| 工具 | 单迁移事务 | 多迁移事务 | 失败行为 |
|------|-----------|-----------|---------|
| Liquibase | 是 | 否 | 失败迁移回滚，跟踪表标记 EXECUTED=FAILED |
| Flyway | 是 | 否 (默认) | 失败迁移回滚，跟踪表标记 success=false |
| sqitch | 是 (开发者编写 BEGIN/COMMIT) | 否 | 失败回滚整个变更 |
| Alembic | 是 (PG/MSSQL) / 否 (MySQL) | 否 | 失败抛出异常，未提交事务回滚 |
| Django | 部分 (依引擎) | 否 | 失败时迁移标记未应用，事务支持的 DB 自动回滚 |
| Active Record | 是 (PG) / 否 (MySQL) | 否 | 失败回滚 |
| Atlas | 是 | 是 (transactional 模式) | 失败回滚整个 batch |
| Schemachange | 否 (Snowflake 自动提交) | -- | -- |

注意：**MySQL DDL 自动提交**是工具无法绕过的引擎限制。一个 MySQL 迁移如果包含两条 ALTER TABLE，第一条成功后第二条失败，第一条**不会回滚**。这就是为什么单迁移文件应该只包含一个原子变更。

### Baseline（基线）支持对比

```
"Baseline" = 在已有数据库上启用迁移工具时的初始状态。
```

| 工具 | Baseline 命令 | 行为 |
|------|--------------|------|
| Liquibase | `changelog-sync` | 把所有 changeset 标记为已应用，不执行 SQL |
| Flyway | `baseline -baselineVersion=X` | 在跟踪表插入版本 X 标记，跳过低于 X 的迁移 |
| sqitch | `init` + 手动写 deploy 脚本 | 不主动设置 baseline，依赖开发者标记 |
| Alembic | `stamp <revision>` | 设置当前版本为 <revision>，不执行 |
| Django | `migrate --fake` 或 `--fake-initial` | 标记迁移已应用，不执行 SQL |
| Atlas | `migrate apply --baseline <version>` | 跳过低于 version 的迁移 |
| golang-migrate | `force <version>` | 强制设置版本 |

Baseline 是迁移工具落地老项目的关键能力——你不需要把现有 schema 的所有创建语句都迁移到工具中，而是直接"声明当前是版本 N"。

## Liquibase 变更集模型深度剖析

### 变更集的可组合性

```xml
<!-- 单个 changeset 包含多个 change 元素 -->
<changeSet id="003-multi-change" author="alice">
    <addColumn tableName="users">
        <column name="phone" type="varchar(20)"/>
    </addColumn>
    <createIndex indexName="idx_users_phone" tableName="users">
        <column name="phone"/>
    </createIndex>
    <addUniqueConstraint tableName="users" columnNames="phone"
                         constraintName="uk_users_phone"/>
</changeSet>
```

```
原则:
  1. 一个 changeset 应当是一个语义上的原子变更
  2. 多个 change 在同一事务中执行（事务支持的引擎）
  3. 失败时整个 changeset 回滚（事务支持的引擎）
  4. 不要在一个 changeset 里做太多事（影响 rollback 粒度）
```

### Contexts、Labels 与运行时控制

```xml
<changeSet id="seed-data-dev" author="alice" context="dev">
    <insert tableName="users">
        <column name="email" value="dev@example.com"/>
    </insert>
</changeSet>

<changeSet id="seed-data-prod" author="alice" context="prod">
    <insert tableName="users">
        <column name="email" value="admin@company.com"/>
    </insert>
</changeSet>
```

```bash
# 仅执行 dev context
$ liquibase update --contexts=dev

# 多 context
$ liquibase update --contexts=dev,test

# Labels 类似但用于灰度
$ liquibase update --labels=v2.0,!experimental
```

### 自定义变更类型与 SQL 转换

```xml
<!-- 直接 SQL -->
<changeSet id="custom-sql" author="alice">
    <sql splitStatements="true" stripComments="true" endDelimiter=";">
        CREATE EXTENSION IF NOT EXISTS pg_trgm;
        CREATE INDEX idx_users_email_trgm ON users USING GIN (email gin_trgm_ops);
    </sql>
    <rollback>
        <sql>
            DROP INDEX idx_users_email_trgm;
            DROP EXTENSION pg_trgm;
        </sql>
    </rollback>
</changeSet>

<!-- 引擎特定 SQL -->
<changeSet id="postgres-only" author="alice" dbms="postgresql">
    <sql>CREATE INDEX CONCURRENTLY idx_users_status ON users(status);</sql>
</changeSet>
```

### Preconditions

```xml
<changeSet id="conditional" author="alice">
    <preConditions onFail="MARK_RAN">
        <not>
            <columnExists tableName="users" columnName="status"/>
        </not>
    </preConditions>
    <addColumn tableName="users">
        <column name="status" type="varchar(20)"/>
    </addColumn>
</changeSet>
```

`onFail` 选项：`HALT`（停止）/ `MARK_RAN`（标记已执行但跳过）/ `WARN`（警告继续）/ `CONTINUE`（继续）。

## Flyway 版本化与可重复迁移的对比深入

### Versioned 迁移的版本号比较规则

```
Flyway 版本号支持多种格式:
  V1.sql                  → 1
  V1.1.sql                → 1.1
  V1.1.1.sql              → 1.1.1
  V20240301120000.sql     → 20240301120000

比较规则:
  - 按点分割成段
  - 每段比较为整数（不是字符串）
  - 1.10 > 1.9 (10 > 9，不是字符串字典序)
  - 1.1 < 1.1.1 (短的小于长的同前缀)
```

### Repeatable 迁移的执行顺序

```
所有 Versioned 完成后:
  - Repeatable 按文件名字母顺序执行
  - 仅当校验和与跟踪表中不同时执行
  - 默认每次 migrate 都检查校验和

应用场景:
  - 视图: 改一行 SELECT 不需要新版本号
  - 存储过程: 函数体修改不影响表 schema
  - 参考数据: 字典表的 INSERT
  - 权限: GRANT / REVOKE 语句

注意事项:
  - 必须幂等（CREATE OR REPLACE / DROP IF EXISTS）
  - 修改后立即重新执行，不需要新文件
  - 适合声明式风格的 schema 对象
```

```sql
-- R__create_user_summary_view.sql
CREATE OR REPLACE VIEW user_summary AS
SELECT
    u.id,
    u.email,
    u.status,
    COUNT(o.id) AS order_count,
    SUM(o.total) AS total_spent
FROM users u
LEFT JOIN orders o ON o.user_id = u.id
GROUP BY u.id, u.email, u.status;
```

### Flyway 占位符（Placeholder）

```sql
-- V1__create_schema.sql
CREATE SCHEMA ${schema_name};
GRANT USAGE ON SCHEMA ${schema_name} TO ${app_user};
```

```bash
$ flyway migrate \
    -placeholders.schema_name=myapp \
    -placeholders.app_user=app
```

允许同一份 SQL 文件用于多环境（dev/staging/prod）。

### Flyway 回调（Callback）

```sql
-- afterMigrate__refresh_stats.sql
ANALYZE;
```

特殊事件文件：`beforeMigrate`、`afterMigrate`、`beforeEachMigrate`、`afterEachMigrate`、`afterMigrateError` 等。

## Atlas 声明式迁移：现代设计

### Schema as Code 的核心理念

```
传统命令式:
  开发者写 V1.sql, V2.sql, V3.sql
  -> 历史增长，难以理解"当前 schema 是什么"
  -> 必须从 base 重放所有迁移才能看到完整 schema

Atlas 声明式:
  开发者维护 schema.hcl（描述目标状态）
  -> 始终知道"当前 schema 是什么"
  -> 工具自动生成 V1, V2, V3 迁移文件
  -> 迁移文件提交到 Git 后**冻结**（不能再修改）
```

### Atlas 的工作流

```
1. 开发者修改 schema.hcl（添加 status 列）

2. atlas migrate diff <name>
   -> 生成 20240301120000_add_user_status.sql

3. 人工审查生成的 SQL

4. atlas migrate lint
   -> 检测危险变更（如删列、加非空列）

5. 提交 schema.hcl + 迁移文件 + atlas.sum 到 Git

6. CI 流水线运行:
   - atlas migrate apply --dry-run
   - atlas migrate lint
   - 失败则阻断合并

7. 部署:
   - 生产环境: atlas migrate apply --url "..."
```

### 与 Terraform 风格的对比

```hcl
# Atlas schema.hcl
table "users" {
    column "id"     { type = bigint, identity { generated = ALWAYS } }
    column "email"  { type = varchar(255), null = false }
    column "status" { type = varchar(20), default = "active" }
    primary_key { columns = [column.id] }
}
```

Atlas 是数据库领域的 Terraform：
- 声明目标状态
- 工具计算 plan
- 应用前人工审查
- Drift detection

但与 Terraform 的关键差异：**数据库变更是有副作用的**。删除一列会丢失数据，重命名表会破坏依赖。声明式工具必须**生成迁移文件而非直接 apply**——给开发者审查机会。

### `atlas schema apply`：直接应用模式（不推荐生产）

```bash
# 危险: 直接把 schema.hcl 应用到目标库（无迁移文件审计）
$ atlas schema apply --url "postgres://..." --to "file://schema.hcl"
```

仅用于开发环境的快速实验，不推荐生产环境。

### Atlas 的 Devel-DB 概念

```
Atlas 的 --dev-url 参数指向一个临时的 dev 数据库（通常是 Docker）。

Diff 生成步骤:
  1. 启动 dev DB（如 Docker postgres:15）
  2. 应用迁移目录中的所有现有迁移到 dev DB
  3. 把目标 schema.hcl 应用到 dev DB（dry-run，捕获 SQL）
  4. 比较步骤 2 和步骤 3 的 SQL，得到差异

为什么需要 dev DB？
  - 解析复杂的 default 表达式（如 NOW()）
  - 验证类型转换
  - 检测 ENUM、自定义类型、CHECK 约束的实际行为
  - 不依赖目标库的现有状态
```

### Atlas 的 transactional 模式

```sql
-- 默认: txmode = "file"（每个文件一个事务）
-- 可选: txmode = "all"（整个 batch 一个事务，引擎支持时）
-- 可选: txmode = "none"（无事务）

-- 在迁移文件头部声明:
-- atlas:txmode none

CREATE INDEX CONCURRENTLY idx_users_status ON users(status);
```

## 关键发现

### 1. 命令式仍然是主流，声明式是趋势

约 18 个工具采用命令式范式，但**新一代工具几乎都引入声明式特性**：Atlas、Bytebase、Skeema 都把声明式作为核心能力。原因：
- 声明式更容易理解"当前 schema 是什么"
- 适合 GitOps 工作流
- 与 IaC（Terraform、Kubernetes）思维一致

但**纯声明式不可行**——数据迁移、列重命名、复杂索引重组都需要命令式控制。混合范式（声明式描述目标 + 命令式描述路径）是终态。

### 2. 校验和是数据库迁移的关键安全网

约 5 个工具实现了完整的校验和机制（Liquibase MD5, Flyway CRC32, sqitch SHA-1, Atlas SHA-256, Schemachange SHA-256），约 7 个工具完全不校验（Alembic、Django、Rails、Knex、golang-migrate、dbmate、Goose）。

不校验的工具的隐患：开发者可以悄悄修改已发版的迁移文件，团队其他成员、CI/CD、生产环境都不会察觉，直到出现"为什么 dev 库和 prod 库 schema 不一致"。

引擎开发建议：迁移工具应当**默认开启校验和**，提供 `--allow-checksum-mismatch` 这种显式选项。

### 3. 跨引擎抽象的代价

Liquibase、Flyway 这类全引擎通用工具，必须在抽象层做大量妥协：
- 不能利用引擎特定的优化（如 PG 的 CONCURRENTLY、MySQL 的 INSTANT、Snowflake 的 zero-copy clone）
- 标准化的 changeset 必然丢失细节
- 调优能力受限

而 Schemachange（Snowflake-only）、Skeema（MySQL-only）、Tern（PG-only）这类专精工具能直接利用引擎特性。

实践建议：
- 多引擎部署：选 Liquibase / Flyway / Atlas
- 单引擎深度优化：选专精工具
- 不要为了"未来可能换引擎"而选通用工具，因为换引擎时迁移历史几乎不可移植

### 4. ORM 集成 vs 独立迁移工具的权衡

| 优势 | ORM 集成（Alembic, Django, Rails） | 独立工具（Flyway, sqitch） |
|------|----------------------------------|--------------------------|
| 自动 diff | 是（从模型生成迁移） | 否 |
| 类型安全 | 是 | 否 |
| 单一语言栈 | 是（必须用同语言） | 否（与应用解耦） |
| 跨服务共享 schema | 难 | 容易 |
| DBA 可独立操作 | 难（需懂应用代码） | 容易 |

实践：**应用层用 ORM 集成的迁移**（开发者友好），**关键 schema 变更用独立工具**（DBA 友好）。两者可以共存于同一项目。

### 5. 在线 DDL 工具不是迁移工具

gh-ost、pt-online-schema-change、pg_repack 是**单条 DDL 的执行引擎**，不是迁移工具。混淆这两个概念会导致：
- 没有版本管理，schema 变更不可重放
- 没有跟踪表，多人协作冲突
- 不能回滚

正确架构：迁移工具（Flyway/Atlas）调用在线 DDL 工具（gh-ost）执行单条变更。Skeema、Bytebase 已经原生集成。

### 6. 回滚是真正的难题

| 工具 | 回滚机制 | 实际可行性 |
|------|---------|-----------|
| Flyway OSS | 不支持 | -- |
| Flyway Pro / Liquibase | Undo 文件 | 中等（需开发者编写） |
| Alembic / Django / Rails | downgrade 函数 | 中等 |
| Atlas | 反向 diff | 中等 |
| sqitch | revert 文件 | 中等 |

**回滚的本质难题**：DDL 可以反向（DROP COLUMN 反向是 ADD COLUMN），但**数据丢失不可逆**。删了一列再加回来，列里的数据不会回来。

实务做法：
- 不依赖回滚——而是写"前向修复"迁移
- 用 expand-contract 模式做大变更（详见 `schema-evolution.md`）
- 关键变更前做 backup（PITR / snapshot）

### 7. 迁移工具的选型矩阵

| 场景 | 推荐工具 | 原因 |
|------|---------|------|
| Java + 单引擎 | Flyway | 简单、SQL-only、生态成熟 |
| Java + 多引擎 + 复杂逻辑 | Liquibase | 跨引擎、变更集模型、回滚能力 |
| Python + SQLAlchemy | Alembic | 自动 diff、ORM 集成 |
| Python + Django | Django migrations | 内置、深度集成 |
| Ruby on Rails | Active Record | 内置、reversibility |
| Node.js | Knex.js / db-migrate | 链式 API、与 Bookshelf/Objection 集成 |
| Go 应用 | golang-migrate / Goose | 嵌入二进制、SQL-only |
| 现代声明式（多引擎） | Atlas | Schema as Code、Lint、Cloud |
| MySQL 单引擎声明式 | Skeema | 集成 gh-ost、声明式 push |
| Snowflake | Schemachange / Liquibase Pro | Snowflake 优化 |
| 多团队协作 + 审批 | Bytebase | GitOps、工单流、SQL 审查 |
| Perl 项目 / Git 集成 | sqitch | 依赖图、verify 测试 |
| 大型 PG 项目 | sqitch + pg_repack | 控制力强 + 在线表重组 |

### 8. 引擎开发者的实现建议

```
对引擎开发者:
  1. 提供原生的"INSTANT DDL"语义，让迁移工具能利用
  2. 提供 ALTER TABLE 的事务性保证（参考 PG/MSSQL）
  3. 提供 schema diff 的引擎级 API，让工具不用解析 information_schema
  4. 提供 schema 变更的审计日志（pg_stat_statements 风格）
  5. 提供 Time Travel / PITR，作为回滚的最终保障

对工具作者:
  1. 默认开启校验和，避免悄悄篡改
  2. 提供 dry-run 模式（atlas migrate apply --dry-run）
  3. 集成在线 DDL 工具（Skeema 模式）
  4. 提供 Lint 规则（Atlas 模式）
  5. 与 Git 深度集成（sqitch 模式）
  6. 提供 baseline 命令，支持老项目接入
```

## 总结对比矩阵

### 工具能力总览

| 能力 | Liquibase | Flyway | sqitch | Alembic | Django | Atlas | Bytebase | Skeema | golang-migrate | Schemachange |
|------|-----------|--------|--------|---------|--------|-------|----------|--------|---------------|--------------|
| 命令式 | 是 | 是 | 是 | 是 | 是 | 是 | 是 | -- | 是 | 是 |
| 声明式 | 部分 | -- | -- | 自动 diff | 自动 diff | 是 | 是 | 是 | -- | -- |
| 校验和 | MD5 | CRC32 | SHA-1 | -- | -- | SHA-256 | -- | -- | -- | SHA-256 |
| 跨引擎 | 60+ | 30+ | 5+ | SQLA 全部 | 4 | 10+ | 10+ | MySQL系 | 30+ | Snowflake |
| 事务迁移 | 是 | 是 | 手动 | PG/MSSQL | 部分 | 是 | 是 | -- | 是 | -- |
| 回滚 | 是 | 商业版 | 是 | 是 | 是 | 是 | 部分 | -- | 是 | -- |
| Baseline | changelog-sync | baseline | 手动 | stamp | --fake | --baseline | 是 | pull | force | 是 |
| GitOps | 部分 | 部分 | 是 | -- | -- | 是 | 是 | 是 | -- | -- |
| Lint | 部分 | 部分 | -- | -- | -- | 是 | 是 | 是 | -- | -- |
| 在线 DDL 集成 | 部分 | -- | -- | -- | -- | 建议 | 是 | 是 (gh-ost) | -- | -- |
| ORM 集成 | -- | -- | -- | SQLAlchemy | Django | -- | -- | -- | -- | -- |

### 选型快速决策树

```
1. 用什么语言？
   Java         → Flyway / Liquibase
   Python       → Alembic（用 SQLAlchemy）/ Django migrations
   Ruby         → Active Record
   Node         → Knex.js
   Go           → golang-migrate / Goose / Atlas
   PHP          → Phinx
   Perl         → sqitch

2. 单引擎还是多引擎？
   Snowflake-only       → Schemachange / Liquibase Pro
   MySQL-only           → Skeema
   PostgreSQL-only      → sqitch / Tern
   多引擎               → Liquibase / Flyway / Atlas

3. 团队协作复杂度？
   小团队               → 任何工具
   多团队 + 审批        → Bytebase
   GitOps               → Atlas / Bytebase

4. 范式偏好？
   声明式               → Atlas / Skeema
   命令式               → Flyway / sqitch
   混合                 → Liquibase / Bytebase

5. 是否需要回滚？
   是                   → Liquibase / sqitch / Alembic / Active Record
   否（前向修复）       → Flyway OSS / Schemachange
```

## 参考资料

- Liquibase: [Documentation](https://docs.liquibase.com/)
- Flyway: [Documentation](https://documentation.red-gate.com/fd/)
- sqitch: [Tutorial](https://sqitch.org/docs/manual/sqitchtutorial/)
- Alembic: [Tutorial](https://alembic.sqlalchemy.org/en/latest/tutorial.html)
- Django: [Migrations](https://docs.djangoproject.com/en/stable/topics/migrations/)
- Active Record: [Migrations](https://guides.rubyonrails.org/active_record_migrations.html)
- Knex.js: [Migrations](https://knexjs.org/guide/migrations.html)
- Atlas: [Documentation](https://atlasgo.io/)
- Bytebase: [Documentation](https://www.bytebase.com/docs/)
- Schemachange: [GitHub](https://github.com/Snowflake-Labs/schemachange)
- golang-migrate: [GitHub](https://github.com/golang-migrate/migrate)
- dbmate: [GitHub](https://github.com/amacneil/dbmate)
- Goose: [GitHub](https://github.com/pressly/goose)
- Tern: [GitHub](https://github.com/jackc/tern)
- Phinx: [Documentation](https://book.cakephp.org/phinx/)
- Skeema: [Documentation](https://www.skeema.io/docs/)
- gh-ost: [GitHub](https://github.com/github/gh-ost)
- pt-online-schema-change: [Percona Toolkit](https://docs.percona.com/percona-toolkit/pt-online-schema-change.html)
- pg_repack: [GitHub](https://github.com/reorg/pg_repack)
- dbt: [Documentation](https://docs.getdbt.com/)
- Migra: [GitHub](https://github.com/djrobstep/migra)
- Schema Hero: [Documentation](https://schemahero.io/)
- Sqlpackage / DACPAC: [Microsoft Docs](https://learn.microsoft.com/en-us/sql/tools/sqlpackage/sqlpackage)
- Wheeler, D. "Sane Database Change Management with Sqitch" (2013)
- Fowler, M. "Evolutionary Database Design" (2003)
- Ambler, S. & Sadalage, P. "Refactoring Databases" (2006), Addison-Wesley
