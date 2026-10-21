# 导出协议

当前协议版本 1.1.0（`schema_version`）。所有导出含 schema_version、generated_at_unix_ms、source、query、completeness、units、entities、records、provider_data。兼容性变更升级主版本；仅新增可选字段升级次版本。

默认导出是第三方分析友好的匿名化视图。records.player_name 是玩家显示名；records.matches 使用 match_index、player_name、outcome、started_at_unix_ms、hero_name、hero_role、map_name、score、stats、teammates 和 enemies。每个队友/敌人包含 player_name、hero_name、hero_role 和 stats。stats 包含 kills、assists、deaths、damage、healing、blocked_damage、mitigation；其中 blocked_damage 与上游 resistDamage 相同，表示阻挡/减免的伤害量，不是阻挡次数。默认不输出 match ID、官方 UID、大神 GUID 或原始上游 JSON。

实体：id、kind（hero/map）、dashen_guid、official_id、name_zh、mapping_status。官方 ID 是字符串，避免 JS 大整数精度损失。已映射 ID 如 overwatch:hero:0x02e0000000000002；未知使用 dashen:hero:207165582859042818，保留原 GUID，mapping_status=unresolved。修改显示名字不影响已知实体 ID。映射变更需通过 GUID 对接，不能用中文名连接数据。

completeness.status：complete 表示读完上游可用记录；partial 表示达到分页上限；page 表示单页；provider_snapshot 表示上游快照。它不意味着提供了玩家全部历史。query.season 当前为空时记录目录认为的当前赛季；这不是上游响应确认的赛季。

默认 provider_data 为 null。API 请求体显式加入 technical:true 时，才会返回递归脱敏后的上游快照，适合调试，不适合作为第三方分析输入。

导出递归移除包含 token、apiKey、cookie、authorization、password、traceId 的字段及 session 字段。资料库目前只保留 envelope 和 provider_data，稳定化 records 尚未覆盖全部公共业务。
