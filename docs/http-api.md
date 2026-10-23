# 本机接口

`watchd` 是一个只在本机运行的 HTTP 服务，界面（Flutter）和旧的网页界面都通过它读数据。你也可以直接调用它写脚本。

## 约定

- **地址和端口**：单独运行 `watchd.exe` 时默认 `http://127.0.0.1:18180`；界面自己拉起服务时用 18280。环境变量 `WATCHD_PORT` 可以改端口。
- **只接受本机**：`Host` 必须是 `127.0.0.1` 或 `localhost` 加端口；非 GET 请求必须带头 `x-watch-client: watch-overwatch`，且来源（如有）必须是本机。这是为了防止网页对它发请求。
- **请求和返回都是 JSON**。字段名用 snake_case；缺失的值是 `null`，不用 0。
- **会话**：先用 `/api/player/search` 查玩家，拿到会话编号（`session`），其余的玩家接口都带它。会话只存在内存里，约一小时过期，过期后重新查找。
- **错误**：失败时返回 `{"error": {"kind": …, "message": …}}`。`kind` 决定状态码：`validation` → 400，`busy`、`rate_limited` → 429，`timeout` → 504，`no_account`、`auth` → 503，其余 → 502。`message` 是给人看的说明。凭据被上游拒绝（401/403）时这个账号会被停用，直到更新凭据。
- **不会发生的事**：任何返回里都没有令牌；`/api/request` 只转发白名单内的接口。

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
| `GET /healthz` | 存活检查 |
| `GET /api/state` | 服务状态、账号状态、请求记录 |
| `GET/POST /api/players` | 玩家库 |
| `POST /api/accounts` | 添加、更新、移除大神账号 |
| `POST /api/player/search` | 查玩家，返回会话编号 |
| `POST /api/player/view` | 某个视图，返回统一数据结构（IR），见下 |
| `POST /api/player/dataset` | 完整数据集和分析；可带 `progress_id` |
| `POST /api/player/stadium` | 角斗领域构筑：按英雄统计异能、物品的选取率、通常回合、胜率，以及常用异能组合；`scope` 为 `own`（该玩家）或 `everyone`（本机所有玩家）；只用本机已存的详情。对局详情（`view: detail`）在角斗领域另带 `stadium_timeline`：该玩家每回合的胜负和新选的异能、物品 |
| `POST /api/player/ranks` | 段位轨迹：各职责每场的段位分（带推算的赛季、对局强度）、各赛季在列表里的起止、最近几段掉分及对面强度；`season_matches` 传各赛季生涯场次（来自赛季走势），用来划分赛季；只用本机已存的数据 |
| `POST /api/player/people` | 常遇玩家：常同场的玩家（同队 / 对面战绩、组排场次、共同对局 id）、组排与单排战绩、每场的组排人数；只用本机已存的详情 |
| `POST /api/player/duo` | 与一位常遇玩家（`other` 为 `people` 返回的 `key`）的共同对局，双方英雄和数据并列，以及同队 / 其他 / 对面时的战绩 |
| `POST /api/player/daily` | 每日总结：有对局的日子（每天的战绩）与某一天的总结（战绩、时长、段位变化、高光、和平时比、英雄、地图、对局）；`day` 为 `YYYY-MM-DD`，省略时取最近一天；只用本机已存的数据 |
| `POST /api/player/maps` | 地图页：按地图类型分组的地图战绩（带胜率区间、是否参与比较）、平均时长（来自已存详情）、每张图最常用的英雄；只用本机已存的数据，不向上游请求 |
| `POST /api/player/overview` | 概览页：近 20 场与之前 20 场、今天 / 昨天 / 近 7 天、按英雄 / 地图 / 职责的战绩（带胜率区间）、星期 × 小时、最近的连续游戏、最近 20 场、几条有把握的发现（规则见 `docs/algorithms.md` 7.3）；只用本机已存的对局、详情和段位分，不向上游请求 |
| `POST /api/player/benchmark` | 同侪基准：该玩家各英雄的典型一场在同段位、同英雄的其他玩家中的百分位（每 10 分钟的伤害、治疗、阻挡、消灭、最后一击、阵亡），只用本机已存的对局 |
| `POST /api/player/growth` | 成长面板：逐局的存活时长、Fleta、KDA、治疗量、阻挡量和各指标的走势（整体和分职责） |
| `POST /api/player/stored` | 本机已有的某个名字的对局列表和最近的玩家资料，不发任何上游请求 |
| `POST /api/player/prepare` | 把已读取的对局里还没准备好的，每次取一小批：读详情并（可选）取参与者的段位快照，存进本机（导出用；打开一场对局时补这一场） |
| `POST /api/ranks/start`、`POST /api/ranks/status` | 段位快照的后台任务：`{session, mode}`。`start` 给这个玩家和模式排一个任务（已有则提前），从新到旧给最新 300 场里缺快照的对局读详情、取段位快照；`status` 返回 `job`：`state`（`waiting` 排在别的任务后 / `running` / `paused` 正在给其他查询让路 / `done`）、`done`、`remaining`。其他任何查询进行中，任务在下一个上游请求前暂停，空闲 1.5 秒后自动继续；进度存在对局详情里，重启服务后再 `start` 会接着读 |
| `GET /api/progress?id=…` | 一次采集的实时进度 |
| `GET /api/cache`、`POST /api/cache/clear` | 查看、清除本机保存的对局和段位（`matches.db`、`ratings.db`） |
| `POST /api/player/export` | 导出数据集 |
| `GET /api/catalog` | 目录（英雄、地图、统计项、威能、段位图标与名称；`stadium_upgrades`：角斗领域的异能与装备，按 `0x…` 编号给出名称、图标、说明、分类和稀有度） |
| `POST /api/request` | 白名单内的原始接口转发（调试用） |
| `POST /api/update/check` | 本版本与 GitHub 上最新发布版的比较（`force: true` 重新查询，否则 6 小时内复用上次结果）：`current`、`latest`（版本、更新说明、发布时间、发布页、安装包大小）、`newer`、`installable`（是否为可被更新的发布目录）、`download`。只访问本项目公开的发布页，不带任何凭据 |
| `POST /api/update/download`、`POST /api/update/status` | 在后台下载最新版的安装包，用发布页附带的 `.sha256` 校验，解压到 `%LOCALAPPDATA%\Watch Overwatch\updates\`；`status` 返回 `download.state`（`idle` / `downloading` / `verifying` / `ready` / `failed`）和已下载字节数 |
| `POST /api/update/apply` | 下载就绪后，启动一份临时的安装程序（`watchd.exe` 的副本）并退出服务；安装程序等应用和服务退出后把新文件覆盖到程序目录，再启动新版本，结果写在 `updates\update.log` |

### 视图（`/api/player/view`）

请求体：`session`、`view`，以及按视图需要的 `mode`（`competitive`、`quick`、`stadium`，默认 `quick`）、`season`、`page`、`match_id`、`fresh`（绕过短时间的服务端缓存）。

| `view` | 返回 |
|---|---|
| `profile` | 某模式某赛季的生涯：各职责数据、英雄使用统计、省榜、行为与荣誉 |
| `card` | 玩家资料卡 |
| `matches` | 一页对局列表 |
| `detail` | 一场对局的详情，需要 `match_id`。立刻返回，带已知的玩家段位和 Fleta 指数；`ratings_pending` 说明段位是否还没查完（用 `prepare` 带 `match_id` 把这一场查完） |
| `heroes` | 英雄榜 |
| `summary`、`history`、`sameplay` | 汇总、往期赛季、和另一名玩家的共同对局 |

### 准备（`/api/player/prepare`）

读取对局列表后，详情和段位在后台分小批准备好，之后对局强度、成长和导出只做计算。请求体：`session`、`mode`、`window`（最新的多少场，最多 5000，默认 30）、`ratings`（是否同时查参与者段位）、`batch`（这次准备几场，1–10）、`match_id`（只准备这一场）。返回 `prepared`（这次准备了几场）、`remaining`（还剩几场）、`total`。

### 成长（`/api/player/growth`）

请求体：`session`、`mode`。只用本机已存的对局详情，不发上游请求，约几十毫秒。返回：

| 字段 | 内容 |
|---|---|
| `listed` | 对局列表里有几场 |
| `stored` | 其中详情已存在本机的有几场 |
| `report.points` | 逐局（旧的在前）：`life_s`、`deathless`、`fleta`、`kda`、`healing10`、`mitigation10`，以及对局时长、阵亡数、职责、英雄、结果 |
| `report.skipped` | 不足 2 分钟或没有阵亡数而没计入的场数 |
| `report.metrics` | 每个指标的均值、整体走势（较早一半与较新一半、斜率、`p`、`trend`）和分职责的走势 |

每个值怎么算见 [算法](algorithms.md) 的“成长面板”。

## 采集计划（`CollectPlan`）

`/api/player/dataset` 的 `plan` 字段：`modes`、`season`、`career_seasons`、`max_pages`（**每次调用**最多读几页，没读完时 `coverage.match_lists[].exhausted` 为假，再调一次就从上次停的地方继续）、`max_details`、`details_per_role`、`roles`（只分析哪些职责，空表示全部）、`list_quota`（读列表时每个职责至少保存这么多场就不再往更早读，不设就读完全部）、`match_limit`、`known_matches`（调用方已选好的对局记录，不空时服务不再翻列表）、`profile`（是否读资料和生涯，默认真）、`hero_board`、`lobby_ratings`、`max_rated_players`、`refresh_ratings`（跳过当前赛季段位的缓存）。数值有上限，超过时返回 `validation` 错误。

## 请求节奏

并发上限 2，每个账号每秒最多 5 次；401 或 403 会停用这个凭据，429 会按服务端要求等待。同一个玩家的详情和段位保存在本机，已经结束的对局不会再次请求。
