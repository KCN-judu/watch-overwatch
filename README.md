# Watch Overwatch

国服守望先锋的对局与数据分析桌面应用（Windows）。从网易大神读取玩家的对局、英雄和段位数据，整理成统一的数据结构，再做对局强度等分析。

界面是 Flutter 原生程序，数据由同目录的本机服务 `watchd`（Rust）读取。两者都只在本机运行。

## 快速开始

1. 双击 `watch-overwatch.exe`。它会自动启动同目录的 `watchd.exe`，关闭窗口时一起退出。
2. 打开“设置”，添加一个大神账号（名称、role_id、token）。凭据只保存在本机。
3. 在左上角搜索框输入完整的战网昵称（如 `Player#12345`），按 Enter。

role_id 和 token 怎么拿，见 [获取账号凭据](docs/credentials.md)。详细步骤、每个页面怎么看、读数里 `—`、`≈` 的含义，见 [使用指引](docs/user-guide.md)。

## 功能

- **对局**：以地图图为背景的列表，只显示胜负、比分、地图和英雄。首次查询读完全部历史，之后只补新对局。点开是两层页面：整场对局（双方 10 人的数据、段位徽标，查询中的显示“查询中”），再点一名玩家是他的个人卡片（数据、段位、Fleta 指数）。
- **英雄**：每个英雄一行，可按场次、胜率、时长、熟练度和每 10 分钟的消灭、伤害、治疗、阻挡排序；点开是海报式的英雄详情页（赛季数据、近期对局、技能和威能）。
- **对局强度**：可以分析全部职责，也可以只分析一个职责；每个职责取最近 N 场，比较己方与对方的段位，逐场画出平均和最低到最高的分布。对局和每人的段位快照都保存在本机（对局库 `matches.db`），后台分小批把段位查好（失败的重新排队），分析本身只是计算。没有定级的对局保留为空位，不被丢掉。
- **成长**：存活时长（保活能力）、Fleta、KDA、治疗量、阻挡量的局间折线图，页首是各指标的走势卡片（含趋势检验的 p 值），可分职责看。
- **赛季走势**、**档案**：往期赛季的胜率和段位，身份与近期表现。
- **导出**：统一格式的 JSON 数据集，不含凭据。弹出系统保存对话框选路径和文件名；可选模式、对局数量（20 / 50 / 100 / 全部 / 自定义）和是否带段位。

## 文档

文档站：<https://kcn-judu.github.io/watch-overwatch/>（内容就是 `docs/` 下的这些文件，加上截图；本地预览见 [命令行](docs/cli.md) 末尾）。

| 文档 | 内容 |
|---|---|
| [docs/overview.md](docs/overview.md) | 概览：能做什么、安装、页面表、阅读路径 |
| [docs/getting-started.md](docs/getting-started.md) | 快速开始，以及从源码构建 |
| [docs/user-guide.md](docs/user-guide.md) | 使用指引：各页面、读数符号、快捷键、常见问题 |
| [docs/credentials.md](docs/credentials.md) | 如何获取大神账号的 role_id 和 token |
| [docs/http-api.md](docs/http-api.md) | 本机接口（`watchd` 的 HTTP 接口） |
| [docs/cli.md](docs/cli.md) | 命令行：`watchd`、`cargo xtask`、文档站 |
| [docs/data-model.md](docs/data-model.md) | 统一数据结构（IR） |
| [docs/export.md](docs/export.md) | 导出协议 |
| [docs/architecture.md](docs/architecture.md) | 架构：模块、数据流、本地数据库、图片缓存 |
| [docs/algorithms.md](docs/algorithms.md) | 算法：段位换算、对局强度、成长、英雄数据补全 |
| [docs/ui-design.md](docs/ui-design.md)、[docs/product-design.md](docs/product-design.md) | 界面设计、产品设计 |
| [docs/game-data.md](docs/game-data.md)、[docs/icon-audit.md](docs/icon-audit.md) | 游戏数据与图标盘点 |
| [docs/reference-projects.md](docs/reference-projects.md) | 对标项目 |
| [docs/audit-2026-10.md](docs/audit-2026-10.md) | 审计记录 |
| [CHANGELOG.md](CHANGELOG.md) | 版本变更记录 |

## 目录

| 位置 | 内容 |
|---|---|
| `crates/watch-core` | 请求调度、数据结构（`ir.rs`）、原始数据到 IR 的转换（`dashen/`）、采集（`collect.rs`）、分析（`analysis.rs`、`strength.rs`） |
| `crates/watchd` | 本机 HTTP 服务与命令行；`store/` 是本机数据库（对局库，含段位快照）和全部 SQL |
| `site/` | 文档站（Astro Starlight），内容取自 `docs/` 和 `CHANGELOG.md` |
| `crates/xtask` | 开发任务：`cargo xtask sync-assets`、`slim-catalog`、`package` |
| `app/` | Flutter 界面 |
| `resources/game/` | 从游戏解包的英雄资料与图标（`app/assets/game/` 是打进应用的副本） |
| `resources/brand/` | 应用图标原图 |
| `ui/` | 旧的网页界面，仍随 `watchd` 提供，不再更新（见 `docs/legacy-ui.md`） |

## 构建

需要 Rust、Flutter（Windows 桌面）和 Windows SDK（用来给可执行文件嵌入图标；没有也能构建，只是没有图标）。

```powershell
cargo build --release -p watchd
cd app
flutter build windows --release
cd ..
cargo xtask package
```

`cargo xtask package` 把上面两步的产物打成 `dist\watch-overwatch-v<版本>-windows-x64.zip`，并写出同名 `.sha256`。

把 `target\release\watchd.exe` 和 `app\build\windows\x64\runner\Release\` 里的 `watch-overwatch.exe`、`flutter_windows.dll`、`data\` 放在同一个目录即可运行。

验证（与 CI `.github/workflows/ci.yml` 相同，PR 和推送到 `main` 时自动运行；推送 `v*` 标签时还会打包并附到 GitHub Release）：

```powershell
cargo fmt --all --check
cargo clippy --all-targets -- -D warnings
cargo test --all-targets
cd app; dart format --output=none --set-exit-if-changed lib test; flutter analyze; flutter test
```

## 命令行

```powershell
.\watchd.exe dataset "Player#12345" --modes competitive,quick --pages 5 --details 20 --lobby
# 只分析一个职责：每个职责取最近 5 场，只看重装
.\watchd.exe dataset "Player#12345" --modes quick --per-role 5 --roles tank --lobby
.\watchd.exe analyze path\to\dataset.json
```

不导入目录时使用内置的目录快照（`crates/watch-core/data/query_tool.min.json`，用 `cargo xtask slim-catalog` 重新生成）。

## 数据与隐私

- 账号凭据：`%LOCALAPPDATA%\Watch Overwatch\secrets.json`，不会出现在界面、日志、导出或仓库里。
- 界面状态：同目录的 `ui-state.json`。图片缓存：同目录的 `img-cache\`，可以随时删除，会重新下载。
- 本地数据库：同目录的 `cache\matches.db`（对局列表、对局详情，含双方玩家的昵称、编号和段位快照），没有任何令牌，设置页可清除。
- 请求只发往网易大神的接口；图片取自大神和暴雪的图片地址。

## 说明

- 请求并发上限 2，每个账号每秒最多 5 次；401 或 403 会停用这个凭据，429 会按服务端要求等待。
- 快速比赛没有段位，对局强度用参与者的竞技段位代替，细节见算法文档。
- 职责、子职责、技能等图标和资料来自游戏本体和暴雪、大神的公开资源，仅供个人使用，不属于本项目的开源内容。
- 旧网页界面不再更新。它的赛事、商店、补丁等与战绩分析无关的功能不迁移，逐项决定和退役计划见 [旧网页界面的退役](docs/legacy-ui.md)。
