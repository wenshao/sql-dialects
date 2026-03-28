# Markus Winand - SQL 标准布道者

> 信息来源：
> - [modern-sql.com](https://modern-sql.com)
> - [use-the-index-luke.com](https://use-the-index-luke.com)
> - [Winand, *SQL Performance Explained* (2012)](https://sql-performance-explained.com/)
> - [Markus Winand Twitter/X: @MarkusWinand](https://x.com/MarkusWinand)

---

Markus Winand 是 SQL 标准合规性和现代 SQL 特性的最大推动者之一。
他通过著作、网站和全球演讲，致力于让开发者了解和使用 SQL 标准的现代功能。

## 背景

Markus Winand 来自奥地利，是一位独立的数据库顾问和培训师。
他专注于 SQL 性能优化和 SQL 标准的推广工作，
在数据库社区中以深入理解 SQL 标准和各方言差异而闻名。

## modern-sql.com

Winand 创办并维护的 modern-sql.com 是 SQL 标准领域最重要的参考网站之一。
网站系统性地介绍了 SQL 标准的现代功能，
并比较了各主要数据库方言对这些功能的支持程度。

网站涵盖的主题包括：
- SQL:2003 以来引入的新功能
- 窗口函数（Window Functions）的详细教程
- FETCH FIRST / OFFSET 分页语法
- LATERAL JOIN
- WITH 子句（CTE，公用表表达式）
- FILTER 子句
- WITHIN GROUP 聚合
- JSON 支持（SQL/JSON）
- 行模式匹配（MATCH_RECOGNIZE）

每个功能页面都会列出各数据库的支持情况，
涵盖 Oracle、PostgreSQL、MySQL、SQL Server、
MariaDB、SQLite、DB2 等主流数据库。

> 来源：[modern-sql.com](https://modern-sql.com)

## use-the-index-luke.com

Winand 创办的另一个重要网站是 use-the-index-luke.com，
这是一个关于 SQL 索引和查询性能优化的免费在线教程。

网站的核心思想是：
- 大多数 SQL 性能问题可以通过正确使用索引来解决
- 开发者需要理解索引的工作原理，而不仅仅是 DBA
- B-tree 索引是最重要的性能工具

网站内容按数据库方言组织，
同时讲解了 Oracle、PostgreSQL、MySQL 和 SQL Server 的索引使用。

> 来源：[use-the-index-luke.com](https://use-the-index-luke.com)

## "SQL Performance Explained"

Winand 著有 *SQL Performance Explained*（2012, ISBN 978-3-9503078-0-2；中文版：《SQL 性能详解》），
这本书深入讲解了 SQL 索引和查询优化的原理。

> 来源：[sql-performance-explained.com](https://sql-performance-explained.com/)

书中的核心内容包括：
- 索引的物理结构（B-tree）
- WHERE 子句的索引使用
- JOIN 操作的性能优化
- 排序与分组的索引优化
- 分页查询的性能陷阱
- INSERT、UPDATE、DELETE 的索引影响

这本书的特色是同时覆盖多种数据库方言，
帮助读者理解不同数据库在查询优化方面的异同。

## SQL 标准倡导

### 推动标准合规性

Winand 可能是全球最积极推动数据库厂商提高 SQL 标准合规性的个人。
他通过以下方式推动这一目标：

- 详细记录各数据库与 SQL 标准的差异
- 在各大数据库的 Bug 跟踪系统中提交标准合规性问题
- 在会议和博客中呼吁厂商实现标准功能
- 教育开发者使用标准语法而非厂商特有语法

### 关注的标准版本

Winand 特别关注 SQL:2003 及之后版本引入的新功能：

| 标准版本 | Winand 关注的关键功能 |
|----------|----------------------|
| SQL:2003 | 窗口函数、MERGE、XML 支持 |
| SQL:2008 | FETCH FIRST、TRUNCATE TABLE |
| SQL:2011 | 时态数据（Temporal Data） |
| SQL:2016 | JSON 支持、行模式匹配 |
| SQL:2023 | 属性图查询（SQL/PGQ）、JSON 增强 |

## 公开演讲

Winand 在全球各地的数据库和开发者会议上频繁演讲，
主题涵盖：

- **"Modern SQL"**：介绍 SQL 标准的最新功能
- **"Indexing Beyond the Basics"**：高级索引技巧
- **SQL 标准合规性评估**：比较各数据库的标准支持情况

他的演讲以清晰的可视化和实际例子著称，
能够将复杂的 SQL 概念变得易于理解。

演讲视频可在各大会议网站和 YouTube 上找到。

## 对数据库社区的贡献

Winand 的工作有几个重要意义：

### 桥梁作用
他在 SQL 标准委员会（ISO/IEC JTC 1/SC 32）的工作
和数据库开发者之间建立了桥梁。
很多开发者通过他的网站第一次了解到 SQL 标准的现代功能。

### 推动方言趋同
通过持续的标准倡导和厂商沟通，
Winand 在推动各 SQL 方言向标准靠拢方面发挥了独特的作用。

### 实用主义
Winand 的方法是实用主义的——他不是教条地要求完全标准化，
而是帮助开发者在可能的情况下选择标准语法，
同时理解各方言的合理差异。

## 公开信息

- **网站**: [modern-sql.com](https://modern-sql.com)
- **网站**: [use-the-index-luke.com](https://use-the-index-luke.com)
- **Twitter/X**: [@MarkusWinand](https://x.com/MarkusWinand)

## 影响

在数据库领域，很少有人像 Winand 这样专注于推广 SQL 标准的现代功能。
他的工作帮助了无数开发者写出更好的 SQL，
也推动了数据库厂商提高对 SQL 标准的支持。

对于本项目（SQL 方言参考）而言，
Winand 的 modern-sql.com 是评估各方言标准合规性的重要参考来源。

---

*注：本页信息均来自公开渠道。如有不准确之处欢迎指正。*
