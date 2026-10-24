# 快速开始

从下载到看到自己的对局，大约十分钟。

## 一、下载并启动

1. 到 [发布页](https://github.com/KCN-judu/watch-overwatch/releases) 下载最新的 `watch-overwatch-v<版本>-windows-x64.zip`，解压到任意目录。`watch-overwatch.exe`、`watchd.exe` 和 `data` 文件夹**要在同一个目录**。
2. 双击 `watch-overwatch.exe`。状态栏左下角显示“本地服务已连接”即可用。
3. 可选：用同名的 `.sha256` 文件校验压缩包（SHA-256）。

已经装了 1.3.0 以上的版本，之后在应用里直接更新即可（帮助 → 检查更新…）。

![首次运行](images/first-run.png)

## 示例玩家（仅开发构建）

从源码运行的开发构建里，首次运行页有“打开示例玩家”（或搜索 `示例玩家#0000`）：对局是生成的，不需要账号，不联网。发布包不带，要带上的构建方法见 [命令行](cli.md#示例玩家)。

## 二、添加账号

查询玩家需要一个网易大神账号的 `role_id` 和 `token`：

1. 设置（左下角或 Ctrl+,）里点“复制获取脚本”。
2. 浏览器打开 <https://ds.163.com/> 并登录，F12 → Console，粘贴运行。脚本从账号绑定的守望先锋角色读出 `role_id`，把 `token` 复制到剪贴板。
3. 回到设置的“添加或更新账号”，填名称（随便起）、`role_id`、`token`，点“保存账号”。

细节和出错时的处理见 [获取账号凭据](credentials.md)。可以加多个账号，轮流使用。凭据只保存在本机。

## 三、查询玩家

左上角搜索框输入完整的战网昵称（`名字#数字`），按 Enter。第一次读这名玩家的全部历史对局，列表先出来，段位在后台补齐（对局页写“段位同步中”）；之后只读新对局。查过的玩家留在左侧“玩家库”，重启后还在。

![对局列表](images/matches.png)

## 四、看什么

- **概览**：近 20 场胜率、战绩、KDA，近期动态，常用英雄和地图。
- **每日总结**：某一天的战绩和高光时刻。
- **对局**：点一场看整场，再点一名玩家看他的卡片。
- **英雄**：点一个英雄看赛季数据、同分段对比、近期对局。
- **对局强度**：选职责和场数，点“开始分析”，看己方和对方的段位。
- **成长**：存活时长、Fleta 指数、KDA、治疗量、阻挡量的走势。
- **导出**：头部右侧的导出按钮，选模式和场数。

每个页面的细节、读数里的符号和快捷键见 [使用指引](user-guide.md)。常用快捷键：Ctrl+K 命令面板，Ctrl+1 … Ctrl+0 切换页面，F1 快捷键参考。

## 从源码构建

需要 Rust、Flutter（Windows 桌面）和 Windows SDK（用来给可执行文件嵌入图标；没有也能构建，只是没有图标）。

```powershell
cargo build --release -p watchd
cd app
flutter build windows --release
cd ..
cargo xtask package
```

`cargo xtask package` 把两步的产物打成 `dist\watch-overwatch-v<版本>-windows-x64.zip` 并写出同名 `.sha256`。验证：

```powershell
cargo fmt --all --check
cargo clippy --all-targets -- -D warnings
cargo test --workspace
cd app; flutter analyze; flutter test
```

仓库不需要 Rust 以外的脚本语言：资源同步、目录精简、打包都是 `cargo xtask` 任务，见 [命令行](cli.md)。
