# 本机接口

`watchd` 是只在本机运行的 HTTP 服务。应用（Flutter）和旧网页界面都通过它读数据，也可以直接用它写脚本。

## 约定

- **地址和端口**：单独运行 `watchd.exe` 默认 `http://127.0.0.1:18180`。应用默认用 18280：端口上已有服务就直接用，没有就自己拉起一个 `watchd.exe` 并把端口传给它。服务和应用都读环境变量 `WATCHD_PORT` 改端口。
- **应用找服务**：环境变量 `WATCHD_PATH` 指向的 `watchd.exe` 存在时总用它；否则在应用旁边和上层目录（含 `target\release`、`target\debug`）里找，取最新构建的那个。
- **数据文件夹**：默认 `%LOCALAPPDATA%\Watch Overwatch\`，环境变量 `WATCH_DATA_DIR` 可改（服务和应用都认）。
- **只接受本机**：`Host` 必须是 `127.0.0.1` 或 `localhost` 加端口；非 GET 请求必须带头 `x-watch-client: watch-overwatch`，有 `Origin` 时必须是本机。不满足时返回 403，防止网页向它发请求。请求体最大 64 KB。
- **请求和返回都是 JSON**：字段名用 snake_case；缺失的值是 `null`，不用 0。
- **模式**：`mode` 取 `competitive`、`quick`、`stadium`（也接受大神的 `sport`、`leisure`、`SportFight`），省略时为竞技。
- **会话**：先用 `/api/player/search` 查玩家，拿到会话编号 `session`，其余玩家接口都带它。查找先试本账号的资料卡和本机的共同对局，都不行才按昵称搜索，见 [数据模型](data-model.md#大神接口)。会话只在内存里，一小时过期，过期后重新查找。一小时内再查同一个昵称（不分大小写）返回同一个会话，不再向大神查；同时到达的同名查找只发一次请求。
- **本机数据**：标“只用本机数据”的接口不请求大神，本机对局库打不开时返回 `{"enabled": false}`。
- **错误**：返回 `{"error": {"kind": …, "message": …}}`。`kind` 决定状态码：`validation` → 400，`busy`、`rate_limited` → 429，`timeout` → 504，`no_account`、`auth` → 503，其余 → 502。`message` 是给人看的说明。查找玩家时，大神返回 `success` 但 `data` 为空，`kind` 是 `empty`；有玩家记录但没有玩家令牌，`kind` 是 `business`。凭据被大神拒绝（401/403）时这个账号停用，直到更新凭据。
- **安全**：任何返回里都没有令牌；`/api/request` 只转发白名单内的大神接口。

```powershell
$h = @{ 'x-watch-client' = 'watch-overwatch'; 'content-type' = 'application/json' }
$s = Invoke-RestMethod http://127.0.0.1:18180/api/player/search -Method Post -Headers $h `
       -Body '{"name":"Player#12345"}'
Invoke-RestMethod http://127.0.0.1:18180/api/player/growth -Method Post -Headers $h `
       -Body (@{ session = $s.session; mode = 'quick' } | ConvertTo-Json)
```

## 路径

| 路径 | 作用 |
|---|---|
| `GET /healthz` | 存活检查：`ok`、`service`、`version` |
| `GET /api/state` | 账号状态（`accounts`）、请求记录（`metrics`）、白名单（`endpoints`）、`current_season`、样本门槛 `thresholds`（`group`、`trend`）、`secrets_path`、`version`、是否带示例玩家 `demo` |
| `GET /api/players`、`POST /api/players` | 玩家库（数据文件夹的 `players.json`）：GET 返回名字列表；POST `{name, remove}` 加到最前或移除 |
| `POST /api/accounts` | 添加、更新、移除大神账号：`{name, role_id, token, remove}`；更新时 `token` 留空则保留原值 |
| `POST /api/player/search` | `{name}` 查玩家，返回 `session` 和 `identity` |
| `POST /api/player/view` | 一个视图，返回统一数据结构（IR），见下 |
| `POST /api/player/dataset` | 完整数据集和分析 `{dataset, analysis}`，见下面的采集计划；可带 `progress_id`、`fresh` |
| `GET /api/progress?id=…` | 带 `progress_id` 的采集的实时进度；不存在时 404 |
| `POST /api/player/stored` | `{name, mode}`：本机已有的这个名字的对局列表和最近的玩家资料，形状同数据集；没查过的名字返回 `known: false`。不需要会话，不请求大神 |
| `POST /api/player/prepare` | 分小批给已读的对局读详情、取段位快照，见下 |
| `POST /api/ranks/start`、`POST /api/ranks/status` | 段位同步的后台任务，见下 |
| `POST /api/player/overview` | 概览页：近 20 场与前 20 场、今天 / 昨天 / 近 7 天、按英雄 / 地图 / 职责的战绩（带置信区间）、星期 × 小时的时段胜率、最近 3 段对局、最近 20 场、每 10 场的滚动胜率、近期动态（最多 5 条，门槛见 [指标口径](metrics.md#threshold)）。只用本机数据（对局、详情、段位快照） |
| `POST /api/player/maps` | 地图页：按地图类型分组的地图战绩（带置信区间、是否参与比较）、平均时长（来自已存详情）、每张图最常用的英雄。只用本机数据 |
| `POST /api/player/daily` | 每日总结：`day` 为 `YYYY-MM-DD`，省略时取最近有对局的一天；返回有对局的日子和这一天的战绩、时长、段位变化、高光、和平时比、英雄、地图、对局。只用本机数据 |
| `POST /api/player/people` | 常遇玩家：常同场的玩家（同队 / 对方战绩、组排场次、共同对局编号）、组排与单排战绩、每场的组排人数。只用本机详情 |
| `POST /api/player/duo` | 与一名常遇玩家（`other` 为 `people` 返回的 `key`）的共同对局，双方英雄和数据并列，以及同队 / 对方时的战绩。只用本机详情 |
| `POST /api/player/ranks` | 段位轨迹：各职责每场的段位分（带推算的赛季、对局强度）、各赛季在列表里的起止、最近几段掉分及对方强度；`season_matches` 传各赛季的生涯场次（来自赛季走势），用来划分赛季。只用本机数据 |
| `POST /api/player/benchmark` | 同分段基准：本人各英雄的典型一场在同分段玩家里的百分位（每 10 分钟的伤害、治疗、阻挡、消灭、最后一击、阵亡），口径见 [指标口径](metrics.md#percentile)；另返回 `matches`（用到的对局数）、`peer_matches`。只用本机详情 |
| `POST /api/player/growth` | 成长面板，见下 |
| `POST /api/player/stadium` | 角斗领域构筑：按英雄统计异能、物品的选取率、通常回合、胜率，以及常用异能组合；`scope` 为 `own`（本人，默认）或 `everyone`（本机所有玩家）。只用本机详情 |
| `GET /api/cache`、`POST /api/cache/clear` | 查看、清除本机对局库（`cache\matches.db`，含段位快照），返回 `{store}` |
| `POST /api/player/export` | 匿名化导出，见 [导出协议](export.md) |
| `POST /api/player/replies` | 旧网页界面用：一句文字摘要、一张 SVG 报告和导出文档，参数同 `export` |
| `GET /api/catalog` | 目录：英雄、地图、统计项、威能、英雄配置、当前赛季、段位图标与名称；`stadium_upgrades` 为角斗领域的异能与装备（按 `0x…` 编号给出名称、图标、说明、分类和稀有度） |
| `POST /api/community` | 旧网页界面用：省榜、英雄榜、选取率、商店、补丁说明、暴雪玩家搜索与生涯页、赛事等公共数据（`kind` 选择），缓存 5 分钟 |
| `POST /api/request` | 白名单内的大神接口原样转发（调试用），返回 `{metric, data}`，`data` 已脱敏 |
| `POST /api/update/check` | 本版本与 GitHub 最新发布版的比较：`current`、`latest`（版本、更新说明、发布时间、发布页、安装包大小）、`newer`、`installable`（是否为可被更新的发布目录）、`download`。`force: true` 重新查询，否则 6 小时内复用上次结果。只访问本项目公开的发布页，不带凭据 |
| `POST /api/update/download`、`POST /api/update/status` | 后台下载最新版安装包，用发布页附带的 `.sha256` 校验，解压到数据文件夹的 `updates\`；返回 `download`：`state`（`idle` / `downloading` / `verifying` / `ready` / `failed`）、`version`、`received`、`total`、`error` |
| `POST /api/update/apply` | 下载就绪后，启动一份临时的安装程序（`watchd.exe` 的副本）并退出服务；安装程序等应用和服务退出后把新文件覆盖到程序目录，再启动新版本，结果写在 `updates\update.log` |

## 视图（`/api/player/view`）

请求体：`session`、`view`，以及按视图需要的 `mode`、`season`（1–100，省略为当前赛季）、`page`（1–100，默认 1）、`match_id`、`scope`、`start_season`、`second_session`、`fresh`（绕过会话内的短时缓存，`detail` 还会绕过本机已存的详情）。超过 45 秒返回 `timeout`。

| `view` | 返回 |
|---|---|
| `profile` | 某模式某赛季的生涯：各职责数据、英雄使用统计、省榜、行为与荣誉 |
| `card` | 玩家资料卡 |
| `matches` | 一页对局列表 |
| `detail` | 一场对局的详情，需要 `match_id`。本机已存时直接返回，否则读大神并存下。带 Fleta 指数和每名参与者的显示段位 `shown_rank`（见 [数据结构](data-model.md)）；竞技、快速另带 `ratings_pending`：段位快照是否还没查完（用 `prepare` 带 `match_id` 查完这一场）；角斗领域另带 `stadium_timeline`：本人每回合的胜负和新选的异能、物品 |
| `heroes` | 本人的英雄榜排名 |
| `summary` | 最多 5 页对局列表里落在 `scope` 内的对局：`recent` / `all`（全部，默认）、`today`、`yesterday`、`week`（近 7×24 小时） |
| `history` | `start_season` 到 `season` 的生涯和赛季走势，一次最多 11 个赛季，默认 5 个；已结束的赛季读过一次后存在本机 |
| `sameplay` | 与 `second_session` 那名玩家的共同对局（各读最多 5 页列表，按对局编号求交集） |

返回：`identity`、`ir`（IR 结构）、`matches`、`summary`、`data`（脱敏后的大神原始数据，旧网页界面用）、`metric`、`cached`，以及各视图自己的字段。

## 准备（`/api/player/prepare`）

读取对局列表后，详情和段位快照分小批准备好，之后对局强度、成长和导出只做计算。

| 字段 | 默认 | 含义 |
|---|---|---|
| `session`、`mode` | | 角斗领域只能 `ratings: false` |
| `window` | 30 | 只看最新的多少场，1–5000 |
| `ratings` | `true` | 同时取参与者的段位快照；否则只读详情 |
| `batch` | 3 | 这次准备几场，1–10 |
| `match_id` | | 只准备这一场 |

返回 `prepared`（这次准备了几场）、`remaining`（还剩几场）、`total`、`enabled`。

## 段位同步（`/api/ranks/*`）

请求体 `{session, mode}`，模式只能是竞技或快速。`start` 给这名玩家和模式排一个任务（已有则提前），从新到旧给最新 300 场里缺段位快照的对局读详情、取快照，每步 3 场；`status` 返回同样的 `job`，本次运行没有任务时为 `null`。

| `job` 字段 | 含义 |
|---|---|
| `state` | `waiting`：排在别的任务后；`running`；`paused`：给其他查询让路；`retrying`：只剩查询失败的对局，`retry_in_s` 秒后重试；`done` |
| `done`、`remaining` | 本任务已完成、还剩的场数 |

有其他查询进行时，任务在下一个大神请求前暂停，空闲 1.5 秒后自动继续。查询失败的对局分别在 30、60、120 秒后重试，三轮后留到下次 `start`。进度存在对局里，重启服务后再 `start` 接着读。

## 成长（`/api/player/growth`）

请求体：`session`、`mode`。只用本机已存的详情，约几十毫秒。返回：

| 字段 | 内容 |
|---|---|
| `listed` | 对局列表里有几场 |
| `stored` | 其中详情已存在本机的有几场 |
| `report.points` | 逐局（旧的在前）：`life_s`、`deathless`、`fleta`、`kda`、`healing10`（只算支援对局）、`mitigation10`（只算重装对局），以及对局时长、阵亡数、职责、英雄、结果 |
| `report.skipped` | 不足 2 分钟或缺阵亡数而没计入的场数 |
| `report.metrics` | 每个指标的均值、整体走势（较早一半与较新一半、斜率、`p`、`trend`）和分职责的走势 |

每个值的算法见 [指标口径](metrics.md) 和 [算法](algorithms.md) 的“成长面板”。

## 采集计划（`CollectPlan`）

`/api/player/dataset` 的 `plan` 字段，超出范围时返回 `validation` 错误：

| 字段 | 默认 | 含义 |
|---|---|---|
| `modes` | 竞技、快速 | 读哪些模式 |
| `season` | 当前赛季 | 对局列表和生涯的赛季，1–100 |
| `career_seasons` | 无 | 另外读这些赛季的生涯，最多 11 个 |
| `max_pages` | 5 | **每次调用**最多读几页列表，1–20；没读完时 `coverage.match_lists[].exhausted` 为假，再调一次从上次停的地方继续 |
| `max_details` | 20 | 读最新多少场的详情，最多 5000 |
| `details_per_role` | 不设 | 改为每个职责取最新这么多场，1–50；`max_details` 不再生效 |
| `roles` | 全部 | 只分析这些职责 |
| `list_quota` | 不设 | 读列表时每个职责有这么多场就不再往更早读，1–300；不设时读完全部 |
| `match_limit` | 不设 | 每个模式只保留最新这么多场，1–5000 |
| `known_matches` | 空 | 调用方已选好的对局（最多 300 场），不空时不再读列表 |
| `profile` | `true` | 读资料卡和生涯 |
| `hero_board` | `true` | 读英雄榜 |
| `lobby_ratings` | `false` | 给详情里的参与者取段位快照 |
| `max_rated_players` | 60 | 最多查多少名参与者，最多 5000 |

超过 180 秒返回 `timeout`。

## 请求节奏

同时最多 2 个大神请求，每个账号每秒最多 5 次；401、403 停用这个凭据，429 按大神给的时间等待（没给时 60 秒）。已结束对局的详情和段位快照存在本机，不再请求。
