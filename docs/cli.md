# 命令行

两类命令：`watchd` 的离线数据命令（不启动服务，直接采集或分析），和开发用的 `cargo xtask`。

## watchd

不带参数运行 `watchd.exe` 会启动本机服务，见 [本机接口](http-api.md)。带子命令则是离线命令：

```powershell
# 采集一个玩家的完整数据集（竞技和快速，每个模式最多 5 页对局列表，读 20 场详情，并做对局强度）
.\watchd.exe dataset "Player#12345" --modes competitive,quick --pages 5 --details 20 --lobby

# 只分析一个职责：每个职责取最近 5 场，只看重装
.\watchd.exe dataset "Player#12345" --modes quick --per-role 5 --roles tank --lobby

# 分析一份已有的数据集
.\watchd.exe analyze path\to\dataset.json
```

### `dataset`

| 选项 | 含义 |
|---|---|
| `--modes a,b` | 模式，`competitive`、`quick`、`stadium`，默认竞技和快速 |
| `--season N` | 只读某个赛季 |
| `--career-seasons 20,21` | 另外读这些赛季的生涯 |
| `--pages N` | 每个模式最多读几页对局列表 |
| `--details N` | 读多少场对局详情 |
| `--per-role N`、`--roles tank,damage,support` | 每个职责取最近 N 场，可限定职责 |
| `--no-hero-board` | 不读英雄榜 |
| `--lobby`、`--max-rated N` | 查参与者段位并做对局强度，最多查 N 名玩家 |
| `--no-cache` | 不用本机数据库（已结束的对局和段位默认会保存、复用） |
| `--out PATH` | 输出文件，默认写到 `%LOCALAPPDATA%\Watch Overwatch\exports\` |

### `analyze`

`analyze <dataset.json> [--utc-offset 分钟] [--out PATH]`：对一份数据集做全部分析（汇总、分时段、分职责、分英雄、对局强度等），输出 JSON。

凭据从 `%LOCALAPPDATA%\Watch Overwatch\secrets.json` 读取。不导入目录时使用内置的目录快照（`crates/watch-core/data/query_tool.min.json`）；`watchd import-catalog` 可以导入新版。

## cargo xtask

在仓库任意位置运行，只需要 Rust 工具链，任务有自己的测试：

| 命令 | 作用 |
|---|---|
| `cargo xtask sync-assets` | 把 `resources/game/` 复制进 `app/assets/game/`，并登记到 `app/pubspec.yaml` |
| `cargo xtask slim-catalog <完整文件> <输出文件>` | 把完整的 `query_tool.json` 精简成程序读取的快照 |
| `cargo xtask update-catalog <目录>` | 用下载到 `<目录>` 的大神线上配置重建内置快照（见下） |
| `cargo xtask package` | 把 `cargo build --release -p watchd` 和 `flutter build windows --release` 的产物打成 `dist\watch-overwatch-v<版本>-windows-x64.zip`，并写出 `.sha256` |

### 更新内置目录

内置快照 `crates/watch-core/data/query_tool.min.json` 来自网易大神公开的配置文件。英雄、地图、段位名称和图标、角斗领域的异能与装备都在里面。大神更新后（新英雄、新地图、改名、换图），按下面的步骤更新：

```powershell
$dir = "$env:TEMP\ds_ow"; New-Item -ItemType Directory -Force $dir | Out-Null
foreach ($f in 'ow_record_query_tool','ow_hero_config','ow_map_config','ow_record_query_tool_mod_trait','ow_hero_attr','ow_perk_list') {
  Invoke-WebRequest "https://s.166.net/config/ds_ow/$f.json" -OutFile "$dir\$f.json"
}
cargo xtask update-catalog $dir
```

`update-catalog` 不联网，合并规则和大神自己的查询工具一致：

- 先取 `ow_record_query_tool.json`，去掉其中由其他文件提供的部分。
- 再合并另外五个文件：英雄、地图、异能与装备、统计项、威能。
- `seasonList` 没有线上文件提供，沿用现有快照里的。

合并后精简，覆盖快照。改完运行 `cargo test`，并看一下 `git diff` 里有哪些变化。

## 示例玩家

示例玩家（`watch_core::demo`，按固定规则生成对局、不联网）只编进开发构建：`cargo build`、`flutter run` 都有，`cargo build --release` 和 `flutter build windows --release` 默认不带，发布包也就没有。要在发布构建里带上，两边一起打开：

```powershell
cargo build --release -p watchd --features demo
flutter build windows --release --dart-define=WATCH_DEMO=true
```

服务端的开关是 `watch_core::DEMO_AVAILABLE`（`/api/state` 的 `demo`），应用的开关是 `lib/core/build.dart` 的 `demoBuild`，两边都有才显示“打开示例玩家”。不带示例的构建会把开发构建留在玩家库里的 `示例玩家#0000` 隐藏起来（文件本身不改）。

## 文档截图

概览、地图、常遇玩家三页的截图由测试渲染生成，不用手动截：

```powershell
cd app
flutter test --update-goldens screenshots
```

数据是 `app/screenshots/docs_screenshots_test.dart` 里编的，图片写到 `docs/images/`。需要 Windows 自带的微软雅黑字体。这个目录不在 `flutter test` 的默认范围里，CI 不跑它。

## 文档站

文档站在 `site/` 下，是一个 Astro 项目；内容来自 `docs/` 和 `CHANGELOG.md`，构建前由 `site/scripts/prepare.mjs` 整理。本地预览：

```powershell
cd site
npm ci
npm run dev
```

推送到 `main` 后，GitHub Actions 会构建并发布到 GitHub Pages。
