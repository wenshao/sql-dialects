# SQL 标准制定内幕：政治、妥协与技术演进

> 参考资料：
> - [The 1995 SQL Reunion: People, Projects, and Politics](http://archive.computerhistory.org/resources/access/text/2015/07/102740133-05-01-acc.pdf) — SQL 创始人的回忆录
> - [Modern SQL by Markus Winand](https://modern-sql.com/) — SQL 标准演进的最佳参考
> - [PostgreSQL Wiki - SQL Standard](https://wiki.postgresql.org/wiki/SQL_standard) — PostgreSQL 的标准合规追踪
> - [ISO/IEC JTC 1/SC 32](https://www.iso.org/committee/45342.html) — SQL 标准的制定委员会

## 1. SQL 的诞生：IBM 的研究与 Oracle 的截胡

### Codd 的理论与 IBM 的犹豫

1970 年，IBM 研究员 **Edgar F. Codd** 发表了划时代论文《大型共享数据库的关系模型》，提出了关系模型的数学基础。但 IBM 管理层并不买账——他们已经有了 IMS（层次型数据库），而且 IMS 正在为公司赚大钱。

IBM 内部的 **System R** 项目（1974-1979）在 San Jose 研究实验室实现了 Codd 的理论，发明了 **SEQUEL**（Structured English Query Language），后来改名为 SQL。但 System R 始终是研究项目，IBM 迟迟不将其商业化。

**关键内幕**：System R 团队的 **Donald Chamberlin** 和 **Raymond Boyce** 在设计 SQL 时，做了一个后来被广泛批评的决定——**偏离 Codd 的关系代数**，采用了更接近英语的语法风格。Codd 本人对 SQL 的设计颇有微词，他认为 SQL 没有忠实实现关系模型（例如 NULL 的三值逻辑、允许重复行等）。

### Oracle 的战略性截胡

1977 年，**Larry Ellison** 和同事创立了 Software Development Laboratories（后来的 Oracle Corporation）。他们读到了 IBM 公开发表的 System R 论文和 SQL 规范——IBM 发表这些论文是为了展示学术成果，但无意中为竞争对手提供了技术蓝图。

**Oracle V2**（1979）成为第一个商业化的 SQL 关系数据库，比 IBM 自己的 SQL/DS（1981）和 DB2（1983）都早。

**对引擎开发者的启示**：Oracle 的成功证明了"先发优势"的价值——即使技术不是最好的（早期 Oracle 性能很差），先占领市场也能建立生态优势。这个教训今天仍然适用（比如 ClickHouse 抢占了列式分析引擎的生态位）。

## 2. 标准化过程：谁在制定 SQL 标准？

### 委员会结构

SQL 标准由 **ISO/IEC JTC1 SC32 WG3** 制定：
- **ISO**：国际标准化组织
- **IEC**：国际电工委员会
- **JTC1**：联合技术委员会 1（信息技术）
- **SC32**：第 32 子委员会（数据管理与交换）
- **WG3**：第 3 工作组（数据库语言）

### 参与者是谁？

要参与 SQL 标准制定，你需要：
1. 加入你所在国家的标准化机构（如美国的 **INCITS**、中国的 SAC/TC28）
2. 通过国家机构被委派到国际工作组
3. WG3 每年线下会面 2-3 次，讨论和处理提案

**实际参与者主要是数据库厂商的代表**：
- **Oracle** 长期是最活跃的参与者（SQL 标准中很多特性先在 Oracle 中出现，然后被标准化）
- **IBM**（DB2 团队）
- **Microsoft**（SQL Server 团队）
- **PostgreSQL 社区**（个人参与者，如 **Peter Eisentraut**）
- 近年来 **Google**（BigQuery/Spanner）和 **Snowflake** 也开始参与

### 标准制定的政治

**厂商影响标准的典型模式**：

1. **先实现再标准化**：厂商在自己的产品中实现一个特性，然后推动将其纳入标准
   - Oracle 的窗口函数（8i, 1999）→ SQL:2003 标准化
   - Oracle 的 MERGE（9i, 2001）→ SQL:2003 标准化
   - Teradata 的 QUALIFY → 至今未纳入标准（但被多家引擎采用）

2. **标准作为竞争武器**：将自己已有的特性标准化，迫使竞争对手也实现
   - Oracle 推动 MERGE 标准化后，MySQL 至今未实现（可能是因为 Oracle 控制了 MySQL）

3. **故意留白**：当厂商无法达成一致时，标准会留下"实现定义"（implementation-defined）
   - SQL-89 的大量特性被标记为 "implementer-defined"——这不是技术限制，而是政治妥协
   - 索引（CREATE INDEX）至今不在 SQL 标准中——因为各厂商的索引实现差异太大

4. **新玩家的加入**：近年来 BigQuery/Snowflake/Databricks 的崛起带来了新的标准化压力
   - SQL:2023 的 SQL/PGQ（图查询）背后是 Neo4j 和多家图数据库厂商的推动
   - JSON 支持（SQL:2016）的标准化反映了 NoSQL 浪潮对 SQL 生态的影响

## 3. 标准 vs 现实：最大的失败和成功

### 成功案例

| 标准特性 | 版本 | 采纳情况 | 成功原因 |
|---------|------|---------|---------|
| JOIN 语法 | SQL-92 | 几乎所有引擎 | 明显优于逗号分隔的旧语法 |
| CASE WHEN | SQL-92 | 所有引擎 | 无替代方案 |
| 窗口函数 | SQL:2003 | 几乎所有引擎（MySQL 最晚 2018） | Oracle 先行验证了价值 |
| CTE (WITH) | SQL:1999 | 几乎所有引擎 | 大幅提升复杂查询可读性 |
| FETCH FIRST | SQL:2008 | 多数引擎（但 LIMIT 更流行） | 标准语法但来得太晚 |

### 失败/争议案例

| 标准特性 | 版本 | 问题 | 原因分析 |
|---------|------|------|---------|
| BOOLEAN 类型 | SQL:1999 | MySQL 用 TINYINT(1)，Oracle 23ai 前无 SQL BOOLEAN | 厂商不愿改已有类型系统 |
| SIMILAR TO | SQL:1999 | 极少使用 | LIKE 和 REGEXP 已满足需求 |
| MULTISET | SQL:2003 | 几乎无人实现 | 概念过于学术化，无实际需求 |
| SQL/XML | SQL:2003/2006 | XML 在数据库中使用率低 | JSON 取代了 XML 的地位 |
| 时态表 | SQL:2011 | 仅 SQL Server 2016+ 完整实现 | 实现复杂度高，需求不够普遍 |
| MATCH_RECOGNIZE | SQL:2016 | 仅 Oracle/Snowflake/Trino/Flink 实现 | NFA 状态机实现复杂 |

### 最大的标准缺失

| 缺失特性 | 说明 | 为什么不在标准中 |
|---------|------|----------------|
| CREATE INDEX | 索引是性能优化的核心 | 各厂商索引实现差异太大，无法统一 |
| AUTO_INCREMENT / SERIAL | 自增是最常用的功能之一 | SQL:2003 的 IDENTITY 理论上替代了它 |
| LIMIT / OFFSET | 分页最流行的语法 | SQL:2008 的 FETCH FIRST 是标准方案，但来得太晚 |
| UPSERT (ON CONFLICT) | 高频需求 | SQL:2003 的 MERGE 理论上覆盖，但太复杂 |
| IF EXISTS / IF NOT EXISTS | DDL 幂等性 | 各引擎已广泛实现但标准迟迟不纳入 |
| 物化视图 | 查询加速核心能力 | 各引擎实现差异大（刷新策略、查询重写） |

## 4. 标准采纳的时间线：谁最快谁最慢？

### 窗口函数采纳时间线（最具代表性的标准特性）

```
SQL:2003 标准发布
        │
        ├── Oracle 8i (1999)     ← 标准发布前 4 年就实现了！
        ├── DB2 (2003)           ← 同年
        ├── SQL Server 2005      ← +2 年（部分支持）
        ├── PostgreSQL 8.4 (2009) ← +6 年
        ├── SQLite 3.25 (2018)   ← +15 年
        ├── MySQL 8.0 (2018)     ← +15 年（最慢的主流引擎）
        └── MariaDB 10.2 (2017)  ← +14 年
```

**为什么 MySQL 这么慢？**

MySQL 长期专注于 Web 应用的简单查询（SELECT/INSERT/UPDATE/DELETE），窗口函数被认为是"高级分析功能"，优先级低。直到 Oracle 收购 MySQL（2010）后，才开始补齐与 Oracle/PostgreSQL 的功能差距。MySQL 8.0（2018）是 MySQL 历史上最大的功能升级，一次性加入了窗口函数、CTE、原子 DDL 等多个标准特性。

### JSON 支持采纳时间线

```
SQL:2016 标准发布
        │
        ├── Oracle 12c R1 (2013)  ← 标准发布前 3 年
        ├── PostgreSQL 9.4 JSONB (2014) ← 标准发布前 2 年
        ├── MySQL 5.7 (2015)      ← 标准发布前 1 年
        ├── SQL Server 2016       ← 同年（但无原生 JSON 类型）
        └── PostgreSQL 17 JSON_TABLE (2024) ← +8 年才完整实现标准语法
```

**启示**：各引擎先用自己的方式实现 JSON 支持（PG JSONB、MySQL ->>、SQL Server OPENJSON），然后 SQL:2016 试图统一语法——但各引擎已经有了大量存量代码依赖非标准语法，标准化来得太晚。

## 5. 为什么 SQL 标准不重要又很重要

### 不重要的原因

1. **没有合规认证**：没有机构测试和认证"某引擎符合 SQL:2016"。厂商自己宣称兼容。
2. **标准文档付费且难读**：ISO 标准不免费，SQL:2023 的完整文档超过 5000 页，天价购买。
3. **事实标准 > 法定标准**：`LIMIT` 比 `FETCH FIRST` 更流行；`GROUP_CONCAT` 比 `LISTAGG` 用户更多。
4. **每个引擎都有大量非标准扩展**：Oracle 的 CONNECT BY、MySQL 的 `||` = OR、PostgreSQL 的 `::`——这些都不在标准中但被广泛使用。

### 很重要的原因

1. **迁移基础**：跨引擎迁移时，标准 SQL 是最大公约数。标准特性的可移植性最好。
2. **功能路线图**：标准指明了 SQL 的发展方向——引擎开发者可以参考标准决定下一步实现什么。
3. **优化器提示**：标准定义的语义让优化器有明确的优化空间（如窗口函数的帧语义）。
4. **人才流动**：开发者学习标准 SQL 可以跨引擎工作，降低学习成本。

## 6. 对引擎开发者的启示

### 标准合规策略

| 策略 | 代表引擎 | 优劣 |
|------|---------|------|
| **标准优先** | PostgreSQL、Trino | 优：可移植性好、社区认可。劣：某些标准特性实际价值低 |
| **实用优先** | MySQL、ClickHouse | 优：用户体验直接。劣：迁移困难、生态锁定 |
| **兼容优先** | TiDB（MySQL兼容）、CockroachDB（PG兼容） | 优：零迁移成本。劣：继承了兼容目标的所有设计缺陷 |

### 实现建议

1. **先实现事实标准，再补充法定标准**：LIMIT 比 FETCH FIRST 更紧迫
2. **标准中的好设计值得采纳**：窗口函数的帧语义、MERGE 的 WHEN MATCHED/NOT MATCHED 分支
3. **标准中的坏设计可以跳过**：MULTISET、SQL/XML 几乎没有实际价值
4. **关注标准的"方向信号"**：SQL:2023 的 SQL/PGQ 预示了图查询在关系引擎中的未来
5. **参与标准制定**：如果你的引擎有创新特性（如 ClickHouse 的 LIMIT BY、Snowflake 的 QUALIFY），推动标准化可以扩大影响力

## 7. SQL 标准的未来

### 即将到来的 SQL:202x 趋势

| 方向 | 说明 | 推动者 |
|------|------|--------|
| **图查询（SQL/PGQ）** | 在关系表上做图遍历，MATCH 子句 | Neo4j、Oracle、ISO |
| **AI/ML 集成** | SQL 中调用 ML 模型（BigQuery ML 是先驱） | Google、Snowflake |
| **向量搜索** | 向量类型和 ANN 查询的标准化 | PostgreSQL(pgvector)、各向量数据库 |
| **流处理 SQL** | 将流式语义纳入标准（Flink SQL 是先驱） | Apache Flink、Confluent |
| **数据湖表格式** | Iceberg/Delta 的 SQL 操作标准化 | Databricks、Snowflake、Apple |

### 标准是否还有意义？

在 2025 年的今天，SQL 标准的意义不在于"统一所有引擎的语法"——这已经证明不可能。它的意义在于提供**共同的概念框架**：窗口函数的语义、JSON 路径表达式的规范、事务隔离级别的定义。

对引擎开发者来说，SQL 标准是一份**设计参考手册**，而非必须遵守的法律。理解标准的历史和政治，能帮助你做出更好的语法设计决策。

## 8. SQL 设计中的理论争议

### Codd vs SQL：发明者的不满

SQL 的设计**偏离了 Codd 的关系模型**，这是数据库理论界最大的争议之一：

| 关系模型（Codd） | SQL 的偏离 | 后果 |
|-----------------|-----------|------|
| 表是元组的**集合**（无重复） | SQL 表是行的**列表**（允许重复行） | 需要 DISTINCT 去重，COUNT(*) 计入重复行 |
| 不存在 NULL | SQL 引入 NULL 和三值逻辑 | `NULL = NULL` 为 UNKNOWN，NOT IN + NULL 返回空集 |
| 关系运算基于集合代数 | SQL 基于"结构化英语"语法 | 语法冗长，歧义多（NATURAL JOIN 的危险性） |
| 列顺序无意义 | SQL 的 `SELECT *` 依赖列顺序 | 表结构变更可能破坏应用代码 |

**Codd 自己的反思**（1990 年）：Codd 在他最后的著作中承认单一 NULL 是不够的，建议用两种 NULL——A-Mark（适用但缺失）和 I-Mark（不适用）。这将需要**四值逻辑**而非三值逻辑。但这个建议从未被 SQL 标准采纳。

### Chris Date 和 The Third Manifesto

Chris Date（Codd 的学生和合作者）和 Hugh Darwen 是 SQL 最激烈的批评者。他们的**第三宣言**（The Third Manifesto）主张：

1. **彻底消除 NULL**——用默认值或类型级 OPTION<T> 替代
2. **强制集合语义**——禁止重复行
3. **关系赋值**（relational assignment）替代 INSERT/UPDATE/DELETE

虽然学术上有道理，但实际影响极小——已有的 SQL 生态不可能重写。**对引擎开发者的启示**：了解这些理论批评有助于理解为什么 NULL 处理是所有引擎中 bug 最密集的区域。

### 三值逻辑的实际代价

SQL 的 NULL 三值逻辑导致了无数反直觉的行为：

```sql
-- NOT IN 的 NULL 陷阱（所有引擎都有，SQL 标准行为）
SELECT * FROM users WHERE id NOT IN (1, 2, NULL);
-- 返回空集！因为 id <> NULL 对所有 id 为 UNKNOWN

-- NULL 在聚合中的行为
SELECT COUNT(col) FROM t;   -- 不计算 NULL
SELECT COUNT(*) FROM t;     -- 计算所有行（含 NULL）
SELECT AVG(col) FROM t;     -- 忽略 NULL（分母不含 NULL 行）

-- CASE WHEN 中的 NULL
SELECT CASE NULL WHEN NULL THEN 'match' ELSE 'no match' END;
-- 返回 'no match'！因为 NULL = NULL 是 UNKNOWN
```

> **Markus Winand 的观点**：SQL 的三值逻辑是"语言中最大的认知负担"——开发者需要在每一个比较操作中考虑 NULL 的可能性。IS DISTINCT FROM（SQL:1999）是部分解决方案，但大多数引擎实现得很晚（MySQL 至今不支持）。

## 9. 标准文档的访问壁垒

### 付费标准的讽刺

SQL 标准文档**不免费**——这是 ISO 标准体系的通病：

| 部分 | 页数（约） | 单独购买价格（约） |
|------|-----------|------------------|
| Part 1: Framework | ~90 页 | CHF 60 (~$70) |
| Part 2: Foundation | ~1,500 页 | CHF 330 (~$370) |
| Part 4: SQL/PSM | ~200 页 | CHF 100 (~$110) |
| Part 9: SQL/MED | ~250 页 | CHF 130 (~$150) |
| Part 14: SQL/XML | ~500 页 | CHF 200 (~$220) |
| Part 16: SQL/PGQ | ~300 页 | CHF 150 (~$170) |
| **全套** | **~4,000+ 页** | **~$1,000+** |

**讽刺**：一个声称要统一全世界数据库语言的标准，大多数数据库开发者从未读过——因为太贵了。

**替代资源**（对引擎开发者）：
- [modern-sql.com](https://modern-sql.com/) — Markus Winand 的免费在线参考，是了解 SQL 标准特性的最佳资源
- [PostgreSQL 文档](https://www.postgresql.org/docs/current/features.html) — PG 文档明确标注了每个特性对应的 SQL 标准条款
- [SQL:1999 草案](https://web.cecs.pdx.edu/~len/sql1999.pdf) — 旧版标准草案可公开获取
- [jOOQ SQL Feature Comparison](https://www.jooq.org/diff) — 各引擎标准合规度对比

## 10. MySQL 为什么不支持 MERGE？——一个标准政治的案例

MySQL 是唯一不支持 SQL:2003 MERGE 语句的主流 RDBMS。这个缺失背后有深层原因：

**时间线**：
- 2001: Oracle 9i 实现 MERGE（比标准早 2 年）
- 2003: SQL:2003 标准化 MERGE
- 2005: SQL Server 2008 实现 MERGE
- 2015: PostgreSQL 15 实现 MERGE（2022 年发布）
- 至今: **MySQL 仍未实现 MERGE**

**可能的原因分析**：
1. **Oracle 的利益冲突**：Oracle 于 2010 年收购了 MySQL。MERGE 是 Oracle Database 的强势特性，在 MySQL 中实现 MERGE 可能削弱 Oracle Database 的差异化优势
2. **ON DUPLICATE KEY UPDATE 已有**：MySQL 认为 INSERT ... ON DUPLICATE KEY UPDATE 已经解决了 UPSERT 需求（虽然功能弱于 MERGE）
3. **实现复杂度**：MERGE 的 WHEN MATCHED/NOT MATCHED/NOT MATCHED BY SOURCE 多分支语义比 ON DUPLICATE KEY UPDATE 复杂得多
4. **SQL Server 的前车之鉴**：SQL Server 的 MERGE 实现有[大量已知 Bug](https://www.mssqltips.com/sqlservertip/3074/use-caution-with-sql-servers-merge-statement/)，多位 MVP 公开建议避免使用。MySQL 团队可能因此更加谨慎

**对引擎开发者的启示**：MERGE 的标准化是一个典型案例——标准定义了语义，但实现质量参差不齐。如果要实现 MERGE，参考 PostgreSQL 15 的实现（最新最干净），而非 SQL Server 的实现（Bug 多）。
