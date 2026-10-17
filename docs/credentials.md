# 获取账号凭据

本应用查询玩家需要一个网易大神账号的两个值：`role_id` 和 `token`。本页说明怎么拿到它们，以及怎么填进应用。

流程于 2026 年 10 月在 Windows、Microsoft Edge 上实测成功。网易可能调整网页和接口，不保证长期有效。

## 要准备的

| 值 | 是什么 |
|---|---|
| `role_id` | 你的战网数字 ID（一串数字，例如 `123456789`） |
| `token` | 大神的业务令牌，应用用它读取战绩 |
| 名称 | 在应用里区分账号的叫法，随便起 |

开始前确认：

- 用 Microsoft Edge 或 Google Chrome；
- 大神账号已经绑定了国服战网账号；
- 知道自己的战网数字 ID。

> 不知道数字 ID 时，可以在大神充值中心的守望先锋页面按 F12，切到 Network，刷新页面后搜索 `role_id`，复制属于你账号的那串数字。这是参考项目 Overstats 的做法，这里没有再单独验证。拿到数字后回到大神官网主站，继续下面的步骤。

## 步骤

### 1. 打开大神官网并登录

在浏览器打开 <https://ds.163.com/> 并登录。**后面的操作都在这个主站页面里做。**

### 2. 运行脚本，拿到 token

1. 在本应用的“设置”里点“复制获取脚本”（也可以直接复制下面的代码，源文件是 `app/assets/tools/get-token.js`）。
2. 回到大神官网页面，按 `F12`，切到 Console（控制台）。
3. 粘贴，回车。
4. 弹出的框里输入你的战网数字 ID，确定。
5. 控制台显示“成功……token 已复制到剪贴板”就完成了。

脚本只用页面自带的签名模块向大神请求令牌，不会把 token 打印出来，也不会发到别处。

```javascript
// 在 https://ds.163.com/ 主站（已登录）的开发者工具 Console 里粘贴运行。
// 会问你的战网数字 ID（role_id），然后把 token 复制到剪贴板。
// 脚本不会把 token 打印出来，也不会发送到别处。
(async () => {
  if (typeof window.sig?.default !== "function") {
    console.error("当前页面没有签名模块。请确认你在 https://ds.163.com/ 主站并且已登录，刷新后重试。");
    return;
  }

  const roleId = (prompt("请输入你的战网数字 ID（role_id）") || "").trim();
  if (!/^\d+$/.test(roleId)) {
    console.error("role_id 应该是一串数字。");
    return;
  }

  const payload = { appKey: "bn", roleId, server: "1", source: 1, type: "yearly" };
  const cookie = (name) =>
    document.cookie.split("; ").find((r) => r.startsWith(name + "="))?.slice(name.length + 1) || "";

  try {
    const body = JSON.stringify(payload);
    const sign = JSON.parse((await window.sig.default()).gen_sign(body));

    const resp = await fetch("https://inf.ds.163.com/v1/web/game/report/getReportToken", {
      method: "POST",
      credentials: "include",
      headers: {
        "Content-Type": "application/json;charset=UTF-8",
        "GL-ClientType": "61",
        "GL-DeviceId":
          localStorage.getItem("ns-client-id") || localStorage.getItem("ds-website-uuid") || "",
        "GL-Uid": cookie("GOD_UUID"),
        "GL-X-XSRF-TOKEN": cookie("GL-XSRF-TOKEN"),
        "GL-CheckSum": sign.sign,
        "GL-Nonce": String(sign.timestamp),
      },
      body,
    });
    const json = JSON.parse(await resp.text());
    const token = json?.result?.token;

    if (!token) {
      console.error(`没有拿到 token（HTTP ${resp.status}，业务码 ${json?.code ?? "无"}）。确认已登录、数字 ID 正确后重试。`);
      return;
    }
    copy(token); // 开发者工具自带：只写入剪贴板，不打印
    console.log(`成功。role_id = ${roleId}，token 已复制到剪贴板（${token.length} 个字符）。回到应用的“设置”里粘贴即可。`);
  } catch (err) {
    console.error("请求失败：", err.name, err.message);
  }
})();
```

如果脚本提示“没有签名模块”，确认你在 `https://ds.163.com/` 主站、已经登录，刷新页面后再运行一次。

**手动取 token（脚本复制失败时）**：打开开发者工具的 Network，选 Fetch/XHR，搜索 `getReportToken`，点开状态码 200 的那条 POST 请求，在 **Response**（响应）里展开 `result`，复制 `token`。Payload 里是你发出去的参数，没有 token。

### 3. 填进应用

1. 打开应用，进入“设置”（左下角或 Ctrl+,）。
2. 在“添加或更新账号”里填：名称（随便起）、`role_id`（你的数字 ID）、`token`（直接粘贴）。
3. 点“保存账号”。账号表格里状态变成“可用”即成功。
4. 回到主界面，在左上角搜索一个玩家的战网昵称，能查到就说明凭据可用。

凭据只保存在本机：`%LOCALAPPDATA%\Watch Overwatch\secrets.json`，不会出现在界面、日志和导出文件里。

## 之后

- **更新**：token 有效期很长，但失效后账号会显示不可用。重新运行脚本，用同一个名称保存就会覆盖旧的。
- **多个账号**：可以添加多个，应用会轮流使用，一个被限速或失效时自动用下一个。
- **移除**：在设置的账号表格里点“移除账号”，本机保存的 `role_id` 和 `token` 会被删除。

## 安全

`token`、Cookie 和签名信息都是敏感的登录凭据：

- 不要把完整的 token 或 Cookie 发给别人；
- 不要公开上传带有认证信息的 Network 导出文件（HAR），也不要在公开的截图里露出认证参数；
- 不要把真实的 token 提交到 GitHub（本仓库的 `.gitignore` 已排除 `secrets.json`）；
- 凭据泄露后，退出大神重新登录，让旧的失效，再按上面的步骤重新获取；
- 只在自己信任的设备和浏览器上做这些操作。
