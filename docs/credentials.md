# 获取账号凭据

本应用查询玩家需要一个网易大神账号的两个值：`role_id` 和 `token`。本页说明怎么拿到它们，以及怎么填进应用。

流程（自动读取 `role_id`、要 token、复制到剪贴板）于 2026-10-25 在 Windows、Microsoft Edge 上实测成功。网易可能调整网页和接口，不保证长期有效。

## 要准备的

| 值 | 是什么 |
|---|---|
| `role_id` | 你的战网数字 ID（一串数字，例如 `123456789`）。脚本从大神账号绑定的守望先锋角色里读出来，不用自己找 |
| `token` | 大神的业务令牌，应用用它读取战绩 |
| 名称 | 在应用里区分账号的叫法，随便起 |

开始前确认：

- 用 Microsoft Edge 或 Google Chrome；
- 大神账号已经绑定了国服战网账号（大神 App 里能看到守望先锋角色）。

## 步骤

### 1. 打开大神官网并登录

在浏览器打开 <https://ds.163.com/> 并登录。**后面的操作都在这个主站页面里做。**

### 2. 运行脚本，拿到 role_id 和 token

1. 在本应用的“设置”里点“复制获取脚本”（也可以直接复制下面的代码，源文件是 `app/assets/tools/get-token.js`）。
2. 回到大神官网页面，按 `F12`，切到 Console（控制台）。
3. 粘贴，回车。
4. 脚本先读这个大神账号绑定的守望先锋角色：只有一个时直接用；有多个时弹框列出昵称、服务器和数字 ID，输入序号选一个。
5. 控制台显示“成功。role_id = ……，token 已复制到剪贴板”就完成了。记下这里的 `role_id`。

脚本用页面自带的签名模块发两个请求，和大神网页自己发的一样：`getRoleBindingListByAppKey`（绑定的角色，`role_id` 和服务器从这里来）和 `getReportToken`（用这个角色要 token）。token 不会打印出来，也不会发到别处。读不到绑定的角色时（接口变了、网络出错），脚本会退回让你手动输入数字 ID。

```javascript
// 在 https://ds.163.com/ 主站（已登录）的开发者工具 Console 里粘贴运行。
// 先读大神账号绑定的守望先锋角色，拿到 role_id，再把 token 复制到剪贴板。
// 脚本不会把 token 打印出来，也不会发送到别处。
// 控制台自带的 copy 只在粘贴的代码同步运行时存在，await 之后就没了，所以先存下来。
const consoleCopy = typeof copy === "function" ? copy : null;
(async () => {
  if (typeof window.sig?.default !== "function") {
    console.error("当前页面没有签名模块。请确认你在 https://ds.163.com/ 主站并且已登录，刷新后重试。");
    return;
  }

  const appKey = "bn"; // 守望先锋在大神里的游戏标识
  const cookie = (name) =>
    document.cookie.split("; ").find((r) => r.startsWith(name + "="))?.slice(name.length + 1) || "";
  const signer = await window.sig.default();

  // 大神网页自己的请求方式：同一组请求头，签名随请求体变。
  const post = async (path, payload) => {
    const body = JSON.stringify(payload);
    const sign = JSON.parse(signer.gen_sign(body));
    const resp = await fetch("https://inf.ds.163.com" + path, {
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
    return { status: resp.status, json: JSON.parse(await resp.text()) };
  };

  // 1. role_id：账号绑定的守望先锋角色（战网数字 ID）。读不到时退回手动输入。
  let role = null;
  try {
    const { json } = await post("/v1/web/role-web/list/getRoleBindingListByAppKey", { appKey });
    const roles = (json?.result || []).map((r) => r?.appRoleDto).filter((r) => r?.roleId);
    if (roles.length === 1) {
      role = roles[0];
    } else if (roles.length > 1) {
      const list = roles
        .map((r, i) => `${i + 1}. ${r.nick || "未命名"}（${r.serverName || "服务器 " + r.server}，${r.roleId}）`)
        .join("\n");
      const pick = Number((prompt(`这个大神账号绑定了 ${roles.length} 个角色，输入序号：\n${list}`) || "").trim());
      role = roles[pick - 1] || null;
      if (!role) {
        console.error("序号不对，重新运行脚本。");
        return;
      }
    } else if (json?.code === 200) {
      console.error("这个大神账号还没有绑定守望先锋角色。先在大神 App 里绑定国服战网账号，再运行脚本。");
      return;
    }
  } catch (err) {
    console.warn("读取绑定角色失败：", err.name, err.message);
  }
  if (!role) {
    const typed = (prompt("没读到绑定的角色，请输入你的战网数字 ID（role_id）") || "").trim();
    if (!/^\d+$/.test(typed)) {
      console.error("role_id 应该是一串数字。");
      return;
    }
    role = { roleId: typed, server: "1" };
  }
  const roleId = String(role.roleId);

  // 2. token：用这个角色向大神要战绩令牌。
  try {
    const { status, json } = await post("/v1/web/game/report/getReportToken", {
      appKey,
      roleId,
      server: String(role.server ?? "1"),
      source: 1,
      type: "yearly",
    });
    const token = json?.result?.token;
    if (!token) {
      console.error(`没有拿到 token（HTTP ${status}，业务码 ${json?.code ?? "无"}）。确认已登录后重试。`);
      return;
    }
    const done = () =>
      console.log(
        `成功。role_id = ${roleId}${role.nick ? `（${role.nick}）` : ""}，token 已复制到剪贴板（${token.length} 个字符）。` +
          "回到应用的“设置”里填 role_id、粘贴 token 即可。",
      );
    // 只写入剪贴板，不打印。
    if (consoleCopy) {
      consoleCopy(token);
      done();
      return;
    }
    try {
      await navigator.clipboard.writeText(token);
      done();
    } catch {
      // 页面没有焦点时浏览器不让写剪贴板：等点一下页面再写。
      console.log(`role_id = ${roleId}。token 已拿到，点一下网页（不是控制台）任意位置就会复制到剪贴板。`);
      document.addEventListener(
        "click",
        () => navigator.clipboard.writeText(token).then(done, (e) => console.error("复制失败：", e.message)),
        { once: true },
      );
    }
  } catch (err) {
    console.error("请求失败：", err.name, err.message);
  }
})();
```

如果脚本提示“没有签名模块”，确认你在 `https://ds.163.com/` 主站、已经登录，刷新页面后再运行一次。提示“还没有绑定守望先锋角色”时，先在大神 App 里绑定国服战网账号。

**手动取（脚本失败时）**：打开开发者工具的 Network，选 Fetch/XHR，刷新页面。`role_id`：搜索 `getRoleBindingListByAppKey`，在 Response 的 `result[].appRoleDto.roleId` 里。`token`：运行一次脚本后搜索 `getReportToken`，点开状态码 200 的那条 POST 请求，在 **Response**（响应）里展开 `result`，复制 `token`。Payload 里是你发出去的参数，没有 token。

### 3. 填进应用

1. 打开应用，进入“设置”（左下角或 Ctrl+,）。
2. 在“添加或更新账号”里填：名称（随便起）、`role_id`（脚本打印的数字 ID）、`token`（直接粘贴）。
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
