# D. Richard Hipp - SQLite 创始人

> 信息来源：
> - [SQLite 官网: About](https://www.sqlite.org/about.html)
> - [SQLite 官网: Most Widely Deployed](https://www.sqlite.org/mostdeployed.html)
> - [Fossil SCM](https://fossil-scm.org/)
> - [Wikipedia: SQLite](https://en.wikipedia.org/wiki/SQLite)
> - [SQLite 官网: Testing](https://www.sqlite.org/testing.html)
> - [SQLite 官网: Copyright](https://www.sqlite.org/copyright.html)

---

D. Richard Hipp 是 SQLite 的唯一原始作者和首席架构师。
SQLite 是全世界部署量最大的数据库引擎，
几乎存在于每一部智能手机、每一个浏览器和无数嵌入式设备中。

> 来源：[SQLite: Most Widely Deployed](https://www.sqlite.org/mostdeployed.html)

## 背景

Richard Hipp 拥有杜克大学的计算机科学博士学位（1992 年）。
他创办了 Hwaci（Hipp, Wyrick & Company, Inc.），
这是一家位于美国北卡罗来纳州夏洛特市的小型软件咨询公司。

> 来源：[SQLite: About](https://www.sqlite.org/about.html)、[Wikipedia: SQLite](https://en.wikipedia.org/wiki/SQLite)

## SQLite 的起源 (2000)

SQLite 的首个版本发布于 2000 年 8 月 17 日，起因是 Hipp 在为美国海军做一个合同项目时，
需要一个不依赖独立服务器进程的数据库。

> 来源：[SQLite: About](https://www.sqlite.org/about.html)、[Wikipedia: SQLite](https://en.wikipedia.org/wiki/SQLite)
当时可用的数据库要么需要单独的服务端进程（如 PostgreSQL），
要么需要复杂的安装配置。

Hipp 决定从零开始编写一个嵌入式 SQL 数据库引擎：
- 无需服务器进程
- 零配置
- 单一文件存储整个数据库
- 跨平台

## 设计哲学

SQLite 的设计哲学体现在多个方面：

### 代码规模

SQLite 的核心源代码约 15 万行 C 代码。
Hipp 坚持代码的可读性和简洁性，
拒绝为了追求特性而盲目增加代码复杂度。

### 测试覆盖率

SQLite 拥有数据库领域（乃至整个软件行业）最严格的测试标准之一：
- 100% 的分支覆盖率（MC/DC - Modified Condition/Decision Coverage）
- 测试代码量超过产品代码的 590 倍（截至官方文档记录）
- 超过数百万个测试用例
- 使用 OOM（Out-Of-Memory）测试确保内存分配失败时的正确行为

> 来源：[SQLite: How SQLite Is Tested](https://www.sqlite.org/testing.html)

### 公有领域许可

SQLite 不使用任何开源许可证，而是将代码放入公有领域（Public Domain）。
这意味着任何人都可以以任何目的使用 SQLite 的代码，
无需署名、无需开源衍生作品、无需支付费用。

> 来源：[SQLite: Copyright](https://www.sqlite.org/copyright.html)

这个决定使得 SQLite 能够被嵌入到几乎任何软件中，
包括许多不接受 GPL 或其他开源许可证的商业产品。

## 技术特点

Hipp 在 SQLite 中实现了一些独特的技术决策：

- **动态类型系统**：与大多数 SQL 数据库不同，SQLite 使用动态类型
- **单写多读**：使用文件级锁而非行级锁
- **WAL 模式**：2010 年引入的 Write-Ahead Logging 提高了并发性能
- **R-Tree 索引**：支持空间数据查询
- **JSON 支持**：通过扩展支持 JSON 数据操作
- **全文搜索**：FTS5 扩展提供全文检索功能

## Fossil 版本控制

Hipp 还创建了 Fossil 版本控制系统，用于管理 SQLite 的源代码。
Fossil 本身使用 SQLite 作为其数据存储。

Hipp 选择不使用 Git/GitHub 来管理 SQLite，
而是使用自己开发的 Fossil 系统。
SQLite 的源代码仓库位于 https://www.sqlite.org/src/。

> 来源：[Fossil SCM](https://fossil-scm.org/)、[SQLite Source Repository](https://www.sqlite.org/src/)

这是一个有意识的技术选择——Hipp 认为 Fossil 更适合 SQLite 项目的需求，
包括集成的 Bug 跟踪、Wiki 和即时的 Web 界面。

## 部署规模

SQLite 的部署量是惊人的。它被嵌入在：
- 每一部 Android 和 iOS 手机
- 每一个主流浏览器（Chrome、Firefox、Safari）
- Python、PHP 等编程语言的标准库
- 大量的桌面应用和嵌入式系统

保守估计，全球活跃的 SQLite 实例数以万亿计，
使其成为世界上部署最广泛的数据库引擎——也可能是部署最广泛的软件之一。

## SQLite 联盟

SQLite 的开发由 SQLite Consortium 赞助，
成员包括多家大型科技公司。
Hipp 和 Hwaci 的小团队负责 SQLite 的核心开发，
保持着对代码质量的极高标准。

## 公开演讲

Hipp 在多个技术会议上做过演讲，主题包括：
- SQLite 的设计决策与取舍
- 软件测试方法论
- 如何维护长寿命的开源项目

他的演讲风格朴实直接，强调工程实践而非炒作。

## 影响

SQLite 证明了一个小团队（甚至一个人）可以创建
全球使用最广泛的软件之一。Hipp 对质量和简洁性的坚持，
以及公有领域的许可选择，使 SQLite 成为了软件工程的典范。

---

*注：本页信息均来自公开渠道。如有不准确之处欢迎指正。*
