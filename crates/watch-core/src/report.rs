use serde_json::Value;
fn xml(s: &str) -> String {
    s.replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
        .replace('"', "&quot;")
        .replace('\'', "&apos;")
}
pub fn report_svg(document: &Value) -> String {
    let name = document["records"]["player_name"]
        .as_str()
        .unwrap_or("Watch Overwatch");
    let rows = document["records"]["matches"]
        .as_array()
        .cloned()
        .unwrap_or_default();
    let mut svg = format!(
        r##"<svg xmlns="http://www.w3.org/2000/svg" width="1200" height="{}" viewBox="0 0 1200 {}"><rect width="100%" height="100%" fill="#202124"/><g font-family="Segoe UI,Microsoft YaHei,sans-serif" fill="#e9e9ed"><text x="48" y="66" font-size="30">{}</text><text x="48" y="100" font-size="14" fill="#a1a1a7">Watch Overwatch · {} · {} · exported at {} Unix ms</text>"##,
        180 + rows.len().min(20) * 45,
        180 + rows.len().min(20) * 45,
        xml(name),
        xml(document["query"]["view"].as_str().unwrap_or("report")),
        xml(document["query"]["mode"].as_str().unwrap_or("")),
        document["generated_at_unix_ms"]
    );
    for (index, row) in rows.iter().take(20).enumerate() {
        let hero = row["hero_name"].as_str().unwrap_or("未知英雄");
        let map = row["map_name"].as_str().unwrap_or("未知地图");
        let outcome = row["outcome"].as_str().unwrap_or("unknown");
        let color = match outcome {
            "win" => "#7ed5a0",
            "loss" => "#ff8585",
            _ => "#a1a1a7",
        };
        let y = 150 + index * 45;
        svg.push_str(&format!(r##"<path d="M48 {}H1152" stroke="#414144"/><text x="48" y="{}" font-size="16" fill="{}">{}</text><text x="160" y="{}" font-size="16">{} / {}</text><text x="650" y="{}" font-size="16">K / A / D: {} / {} / {}</text>"##,y+14,y,color,xml(outcome),y,xml(map),xml(hero),y,row["stats"]["kills"],row["stats"]["assists"],row["stats"]["deaths"]));
    }
    if rows.is_empty() {
        svg.push_str(r#"<text x="48" y="150" font-size="16">此视图没有可用于对局卡片的记录；完整字段请使用 JSON 导出。</text>"#);
    }
    svg.push_str("</g></svg>");
    svg
}
#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;
    #[test]
    fn untrusted_names_are_xml_escaped() {
        let svg = report_svg(&json!({"records":{"player_name":"<script>&"}}));
        assert!(!svg.contains("<script>"));
        assert!(svg.contains("&lt;script&gt;&amp;"));
    }
}
