//! Legacy UI projections of the IR. The browser UI still consumes these shapes;
//! new consumers should read `ir` and `analysis` directly.
use crate::analysis;
use crate::ir::{EntityRef, MatchSummary, Outcome};
use serde::Serialize;
use serde_json::{Value, json};

#[derive(Debug, Clone, Serialize)]
pub struct MatchView {
    pub id: String,
    pub outcome: &'static str,
    pub begin_ms: Option<u64>,
    pub hero: String,
    pub hero_ref: Value,
    pub map_ref: Value,
    pub role: String,
    pub icon: String,
    pub map: String,
    pub score: [Option<u64>; 2],
    pub kills: Option<u64>,
    pub assists: Option<u64>,
    pub deaths: Option<u64>,
    pub damage: Option<u64>,
    pub healing: Option<u64>,
    pub mitigation: Option<u64>,
}

pub fn role_name(role: &str) -> &str {
    match crate::ir::Role::parse(role) {
        crate::ir::Role::Unknown => role,
        known => known.name_zh(),
    }
}

pub fn outcome_zh(outcome: Outcome) -> &'static str {
    match outcome {
        Outcome::Win => "胜利",
        Outcome::Draw => "平局",
        Outcome::Loss => "失败",
        Outcome::Unknown => "未知",
    }
}

/// The JSON reference shape used by UI enrichment and export `entities`.
pub fn legacy_ref(e: Option<&EntityRef>) -> Value {
    e.map_or(Value::Null, |e| {
        json!({"id":e.stable_id(),"kind":e.kind.as_str(),"dashen_guid":e.guid,"official_id":e.official_id,"name_zh":e.name,"mapping_status":if e.name.is_some(){"resolved"}else{"unresolved"}})
    })
}

fn count(v: Option<f64>) -> Option<u64> {
    v.filter(|n| *n >= 0.0).map(|n| n.round() as u64)
}

impl From<&MatchSummary> for MatchView {
    fn from(m: &MatchSummary) -> Self {
        let role = m.role.name_zh().to_string();
        let name = |e: Option<&EntityRef>| e.and_then(|e| e.name.clone()).unwrap_or_default();
        let hero = name(m.hero.as_ref());
        Self {
            id: m.id.clone(),
            outcome: outcome_zh(m.outcome),
            begin_ms: m.started_at_ms.and_then(|t| u64::try_from(t).ok()),
            hero: if hero.is_empty() { role.clone() } else { hero },
            hero_ref: legacy_ref(m.hero.as_ref()),
            map_ref: legacy_ref(m.map.as_ref()),
            role,
            icon: m.hero_icon_url.clone().unwrap_or_default(),
            map: name(m.map.as_ref()),
            score: [
                m.score.team.and_then(|s| u64::try_from(s).ok()),
                m.score.opponent.and_then(|s| u64::try_from(s).ok()),
            ],
            kills: count(m.stats.kills),
            assists: count(m.stats.assists),
            deaths: count(m.stats.deaths),
            damage: count(m.stats.damage),
            healing: count(m.stats.healing),
            mitigation: count(m.stats.mitigation),
        }
    }
}

pub fn views(rows: &[MatchSummary]) -> Vec<MatchView> {
    rows.iter().map(MatchView::from).collect()
}

#[derive(Debug, Serialize)]
pub struct Summary {
    pub matches: usize,
    pub wins: usize,
    pub losses: usize,
    pub draws: usize,
    pub unknown: usize,
    pub win_rate: Option<f64>,
    /// Totals over the matches that report the stat; `None` when none does (missing is
    /// never 0).
    pub kills: Option<u64>,
    pub assists: Option<u64>,
    pub deaths: Option<u64>,
    pub damage: Option<u64>,
    pub healing: Option<u64>,
    pub kda: Option<f64>,
    pub best_streak: usize,
}

pub fn summarize(rows: &[MatchSummary]) -> Summary {
    let a = analysis::aggregate(rows);
    let total = |v: Option<f64>| v.map(|n| n.round() as u64);
    Summary {
        matches: a.record.matches,
        wins: a.record.wins,
        losses: a.record.losses,
        draws: a.record.draws,
        unknown: a.record.unknown,
        win_rate: a.record.win_rate_pct,
        kills: total(a.totals.kills),
        assists: total(a.totals.assists),
        deaths: total(a.totals.deaths),
        damage: total(a.totals.damage),
        healing: total(a.totals.healing),
        kda: a.kda,
        best_streak: a.streaks.best_win,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{
        Catalog,
        dashen::{Mode, normalize},
    };
    #[test]
    fn summary_distinguishes_draw_unknown_and_zero_deaths() {
        let rows = normalize::match_list(
            &json!([{"matchRet":1,"kill":10,"assist":3,"death":0},{"matchRet":0},{"matchRet":2},{"matchRet":99}]),
            Mode::Competitive,
            &Catalog::default(),
        );
        let s = summarize(&rows);
        assert_eq!((s.wins, s.draws, s.losses, s.unknown), (1, 1, 1, 1));
        assert_eq!(s.win_rate, Some(50.0));
        assert_eq!(s.kda, None);
        // Only the first match reports kills and deaths; none reports damage.
        assert_eq!((s.kills, s.deaths), (Some(10), Some(0)));
        assert_eq!(s.damage, None);
        assert_eq!(MatchView::from(&rows[0]).damage, None);
    }
}
