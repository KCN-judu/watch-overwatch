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
