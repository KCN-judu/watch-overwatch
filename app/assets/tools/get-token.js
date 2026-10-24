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
