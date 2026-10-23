# 数据结构

界面和导出都不直接读上游的原始 JSON，而是读统一的数据结构，叫 IR（intermediate representation）。它定义在 `crates/watch-core/src/ir.rs`，由 `dashen::normalize` 从大神的原始数据转换而来；界面里 `app/lib/core/models.dart` 是它的镜像。

> 大神原始 JSON → `dashen::normalize` → IR → `analysis` / `strength` / `growth` → 界面或导出

## 约定

- 字段名用 snake_case；枚举的取值也是 snake_case（`win`、`loss`、`support`……）。
- **缺失用 `null`，不用 0。** 上游没有给的数字不会被当成 0；界面里显示为 `—`。
- 英雄、地图、统计项、威能都用 `EntityRef` 引用，名称可能缺失，所以**不能靠名称做连接**，要用 `guid` 或 `official_id`。
- 官方 ID 在 JSON 里是字符串，避免 JavaScript 大整数丢精度。
- 部分请求失败不会让整个采集失败：`Coverage` 记录每个请求是否成功。
- 版本：`IR_VERSION`（当前 1.1.0）随 IR 的变化升级；只新增可选字段升次版本。

## 主要类型

| 类型 | 内容 |
|---|---|
| `PlayerDataset` | 一个玩家的完整数据集：资料、生涯、对局、对局详情、英雄榜、参与者段位、采集覆盖情况 |
| `PlayerProfile` | 昵称、玩家编号、头像、称号、荣誉等级、游戏时长、总场次、封禁状态 |
| `CareerSnapshot` | 某模式某赛季的生涯：各职责数据、英雄使用统计、省榜、行为与荣誉 |
| `MatchSummary` | 列表里的一场：地图、结果、比分、英雄、职责、统计 |
| `MatchDetail` | 一场的详情：时长、比分、禁用、查询对象用过的英雄、双方各 5 人；角斗还有回合 |
| `Participant` | 一名参与者：英雄、职责、统计、对局报告的段位、威能、组队成员、点赞者；`career_rank`（段位快照：为这场对局查到的竞技段位，和对局一起存，取到后不再变）、`career_rank_at_ms`（取快照的时间；有时间而 `career_rank` 为空表示查过、没有段位）、`career_other_roles`（该段位是其他职责里最高的）；详情展示时另带 `fleta` |
| `StatLine` | 一场的统计：消灭、助攻、阵亡、伤害、治疗、阻挡、最后一击、单独消灭、承受伤害、承受治疗、目标时间 |
| `HeroUsage` | 一个英雄的赛季统计：场次、胜率、时长、熟练度、每场平均、每 10 分钟 |
| `EntityRef` | 英雄、地图、统计项、威能的引用：大神 `guid`、官方 `official_id`（`0x…`）、名称 |
| `Rank` | 段位名、小段、分数、段位分（500–5000 的刻度） |
| `PlayerRating` | 一名玩家各职责在某赛季的竞技段位，用于对局强度；规则见 [算法](algorithms.md) 的 4.2 |
| `Coverage` | 每个请求是否成功、每个模式的列表读了几页、是否已读到最早一场（`exhausted`）、新增了几场 |

分析结果（`PlayerAnalysis`）由 `analysis::analyze` 生成：总体和分窗口的汇总、按模式/队列/职责/英雄/地图的拆分、连续对局、按小时、段位时间线、队内占比、同队玩家、赛季走势、对局强度。成长面板的数据来自单独的 `growth` 模块（`POST /api/player/growth`），不放在每次的数据集里。

## 从哪里取

| 想要 | 用什么 |
|---|---|
| 一个玩家的全部数据 | `POST /api/player/dataset`，或命令行 `watchd dataset` |
| 一个视图 | `POST /api/player/view`，见 [本机接口](http-api.md) |
| 给别人用的、匿名化的版本 | 导出，见 [导出协议](export.md) |
| 逐局的成长指标 | `POST /api/player/growth` |

## 上游接口

IR 的数据来自这些大神接口（`dashen/endpoint.rs`）：

| 接口 | 用途 |
|---|---|
| `searchBnetAccount` | 按战网昵称查玩家，拿到 token（POST，其余为 GET） |
| `customer/queryCard` | 玩家资料卡 |
| `customer/queryCountInfo` | 竞技、快速的生涯：各职责、英雄使用统计、近期对局、省榜、荣誉 |
| `customer/queryMatchList`、`queryMatchInfo` | 对局列表、对局详情 |
| `customer/fight/queryCount`、`queryMatchList`、`queryMatchInfo` | 角斗领域的对应接口 |
| `queryProvinceRank`、`billboard/*` | 省榜、英雄榜 |

英雄统计和段位、近期对局来自同一个 `queryCountInfo`：一次请求返回该玩家本赛季打过的全部英雄，与界面是否显示无关。上游**不提供**每次阵亡的时间点，所以存活时长只能按对局时长和阵亡数估计，见 [算法](algorithms.md)。
