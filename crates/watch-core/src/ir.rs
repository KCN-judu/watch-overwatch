//! Provider-neutral intermediate representation of everything Watch Overwatch can
//! extract from NetEase Dashen. Everything downstream (UI projections, export,
//! analysis) reads these types instead of raw upstream JSON.
//!
//! Conventions: `None` means the provider did not supply a value; zero is a real
//! zero. Timestamps are Unix milliseconds, durations seconds, rates percent 0-100
//! unless a field name says otherwise (`share` is 0-1). Credentials never enter
//! the IR; participant identity is limited to display name and Battle.net id.
pub use crate::dashen::Mode;
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;

pub const IR_VERSION: &str = "1.0.0";

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, PartialOrd, Ord, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum EntityKind {
    Hero,
    Map,
    Stat,
    Perk,
    /// Stadium powers (`traitGuids`) and items (`modGuids`).
    StadiumUpgrade,
}

impl EntityKind {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Hero => "hero",
            Self::Map => "map",
            Self::Stat => "stat",
            Self::Perk => "perk",
            Self::StadiumUpgrade => "stadium_upgrade",
        }
    }
}

/// A catalog-backed reference. `guid` is the provider's decimal 64-bit id and is
/// the join key; `official_id` is the same number in Blizzard's `0x…` form, so it
/// is known even when the catalog does not name the entity.
#[derive(Debug, Clone, PartialEq, Eq, Hash, PartialOrd, Ord, Serialize, Deserialize)]
pub struct EntityRef {
    pub kind: EntityKind,
    pub guid: String,
    pub official_id: Option<String>,
    pub name: Option<String>,
}

impl EntityRef {
    pub fn new(kind: EntityKind, guid: &str, name: Option<String>) -> Self {
        Self {
            kind,
            guid: guid.to_owned(),
            official_id: official_id(guid),
            name,
        }
    }
    /// Stable id that never depends on display names or catalog contents.
    pub fn stable_id(&self) -> String {
        match &self.official_id {
            Some(id) => format!(
                "overwatch:{}:{}",
                self.kind.as_str(),
                id.to_ascii_lowercase()
            ),
            None => format!("dashen:{}:{}", self.kind.as_str(), self.guid),
        }
    }
}

/// `207165582859042818` → `0x02E0000000000002`.
pub fn official_id(guid: &str) -> Option<String> {
    guid.parse::<u64>()
        .ok()
        .filter(|n| *n > 0)
        .map(|n| format!("0x{n:016X}"))
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, PartialOrd, Ord, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Role {
    Tank,
    Damage,
    Support,
    /// Open-queue aggregate rows (`open` / `all`).
    Open,
    Unknown,
}

impl Role {
    /// The three roles a player queues as, in display order.
    pub const PLAYABLE: [Role; 3] = [Role::Tank, Role::Damage, Role::Support];
    pub fn parse(raw: &str) -> Self {
        match raw {
            "tank" => Self::Tank,
            "dps" | "damage" | "offense" => Self::Damage,
            "healer" | "support" => Self::Support,
            "open" | "all" => Self::Open,
            _ => Self::Unknown,
        }
    }
    /// The wire name (`tank`, `damage`, …), as serialised.
    pub fn id(self) -> &'static str {
        match self {
            Self::Tank => "tank",
            Self::Damage => "damage",
            Self::Support => "support",
            Self::Open => "open",
            Self::Unknown => "unknown",
        }
    }
    pub fn name_zh(self) -> &'static str {
        match self {
            Self::Tank => "重装",
            Self::Damage => "输出",
            Self::Support => "支援",
            Self::Open => "综合",
            Self::Unknown => "",
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, PartialOrd, Ord, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Outcome {
    Win,
    Loss,
    Draw,
    Unknown,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum OutcomeSource {
    /// `matchRet` was present and recognized.
    Provider,
    /// Inferred from the final score because `matchRet` was absent (stadium).
    Score,
    Unknown,
}

/// Queue flavour, from the provider row `gameMode` suffix.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, PartialOrd, Ord, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Queue {
    RoleQueue,
    OpenQueue,
    SixVsSix,
    Unknown,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct MatchKind {
    pub mode: Mode,
    pub queue: Queue,
    /// From `instanceType` (`IT_RANKED` / `IT_UNRANKED` / `IT_RULESET`).
    pub ranked: Option<bool>,
    pub provider_mode: Option<String>,
    pub instance_type: Option<String>,
}

#[derive(Debug, Clone, Copy, Default, PartialEq, Serialize, Deserialize)]
pub struct Score {
    pub team: Option<i64>,
    pub opponent: Option<i64>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Rank {
    /// Provider tier key, e.g. `Platinum`.
    pub tier: Option<String>,
    /// 1 (highest) to 5.
    pub division: Option<u8>,
    /// Raw `rankScore`: compact `tier*100+suffix` in normal modes, continuous in stadium.
    pub score: Option<i64>,
    /// Continuous rating on the 500-5000 scale used by leaderboards.
    pub skill_rating: Option<i64>,
    pub at_ms: Option<i64>,
}

/// Combat counters. Per-match values in match rows; averages in career summaries.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct StatLine {
    pub kills: Option<f64>,
    pub assists: Option<f64>,
    pub deaths: Option<f64>,
    pub damage: Option<f64>,
    pub healing: Option<f64>,
    /// `resistDamage`: damage blocked or mitigated, not a count of blocks.
    pub mitigation: Option<f64>,
    pub final_blows: Option<f64>,
    pub solo_kills: Option<f64>,
    pub damage_taken: Option<f64>,
    pub healing_taken: Option<f64>,
    pub objective_time_s: Option<f64>,
}

impl StatLine {
    pub const FIELDS: [&'static str; 11] = [
        "kills",
        "assists",
        "deaths",
        "damage",
        "healing",
        "mitigation",
        "final_blows",
        "solo_kills",
        "damage_taken",
        "healing_taken",
        "objective_time_s",
    ];
    pub fn get(&self, field: &str) -> Option<f64> {
        match field {
            "kills" => self.kills,
            "assists" => self.assists,
            "deaths" => self.deaths,
            "damage" => self.damage,
            "healing" => self.healing,
            "mitigation" => self.mitigation,
            "final_blows" => self.final_blows,
            "solo_kills" => self.solo_kills,
            "damage_taken" => self.damage_taken,
            "healing_taken" => self.healing_taken,
            "objective_time_s" => self.objective_time_s,
            _ => None,
        }
    }
    pub fn set(&mut self, field: &str, value: Option<f64>) {
        let slot = match field {
            "kills" => &mut self.kills,
            "assists" => &mut self.assists,
            "deaths" => &mut self.deaths,
            "damage" => &mut self.damage,
            "healing" => &mut self.healing,
            "mitigation" => &mut self.mitigation,
            "final_blows" => &mut self.final_blows,
            "solo_kills" => &mut self.solo_kills,
            "damage_taken" => &mut self.damage_taken,
            "healing_taken" => &mut self.healing_taken,
            "objective_time_s" => &mut self.objective_time_s,
            _ => return,
        };
        *slot = value;
    }
}

/// Provider "best in match" flags (`killMax`, `heroDamageMax`, …).
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct Highlights {
    pub kills: bool,
    pub damage: bool,
    pub healing: bool,
    pub mitigation: bool,
}

/// One row of a match list: the subject player's view of a match.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct MatchSummary {
    pub id: String,
    pub started_at_ms: Option<i64>,
    pub kind: MatchKind,
    pub outcome: Outcome,
    pub map: Option<EntityRef>,
    pub hero: Option<EntityRef>,
    pub role: Role,
    pub score: Score,
    pub stats: StatLine,
    pub highlights: Option<Highlights>,
    pub rank: Option<Rank>,
    pub hero_icon_url: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct StatValue {
    pub stat: EntityRef,
    pub value: f64,
}

/// Time on one hero within a match. Only the token owner receives these.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct HeroSegment {
    pub hero: EntityRef,
    pub play_time_s: Option<f64>,
    /// 0-1 share of the match.
    pub share: Option<f64>,
    pub stats: Vec<StatValue>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct PerkPick {
    pub perk: EntityRef,
    pub level: Option<u8>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct StadiumBuild {
    pub worth: Option<f64>,
    pub powers: Vec<EntityRef>,
    pub items: Vec<EntityRef>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Participant {
    pub name: Option<String>,
    pub bnet_id: Option<String>,
    /// The player whose token produced this detail.
    pub is_subject: bool,
    pub hero: Option<EntityRef>,
    pub hero_icon_url: Option<String>,
    pub role: Role,
    pub stats: StatLine,
    /// The rank the match itself reported (competitive and Stadium only).
    pub rank: Option<Rank>,
    /// The player's own competitive rank for this role, current season or else the one
    /// before, taken from what was looked up for the lobby-strength analysis. Not stored
    /// with the match: it is attached when a detail is shown, and it is the rank *now*,
    /// not at the time of the match.
    #[serde(default)]
    pub career_rank: Option<Rank>,
    /// `career_rank` is the highest of the player's ranks in other roles (they have none for
    /// the role they played).
    #[serde(default)]
    pub career_other_roles: bool,
    pub perks: Vec<PerkPick>,
    /// Pre-made group members (`friendBnetIds`).
    pub party_bnet_ids: Vec<String>,
    pub endorsed_by_bnet_ids: Vec<String>,
    pub suspended: bool,
    pub stadium: Option<StadiumBuild>,
}

#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct Bans {
    pub ally: Vec<EntityRef>,
    pub enemy: Vec<EntityRef>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Round {
    pub index: usize,
    pub map: Option<EntityRef>,
    pub score: Score,
    pub duration_s: Option<f64>,
    pub allies: Vec<Participant>,
    pub enemies: Vec<Participant>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct MatchDetail {
    pub id: String,
    pub mode: Mode,
    pub map: Option<EntityRef>,
    pub outcome: Outcome,
    pub outcome_source: OutcomeSource,
    pub started_at_ms: Option<i64>,
    pub duration_s: Option<f64>,
    pub score: Score,
    pub bans: Bans,
    pub subject_heroes: Vec<HeroSegment>,
    pub allies: Vec<Participant>,
    pub enemies: Vec<Participant>,
    /// Stadium only.
    pub rounds: Vec<Round>,
}

impl MatchDetail {
    pub fn subject(&self) -> Option<&Participant> {
        self.allies.iter().find(|p| p.is_subject)
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Suspension {
    pub status: Option<String>,
    pub expires_at_ms: Option<i64>,
}

#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct PlayerProfile {
    pub name: Option<String>,
    pub bnet_id: Option<String>,
    pub avatar_url: Option<String>,
    pub title: Option<String>,
    pub title_icon_url: Option<String>,
    /// Endorsement level 1-5.
    pub endorsement_level: Option<i64>,
    /// Card `gameTime` is hours (unlike hero usage, which is seconds).
    pub play_time_hours: Option<f64>,
    pub total_matches: Option<i64>,
    pub suspension: Option<Suspension>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct RoleCareer {
    pub role: Role,
    pub current_rank: Option<Rank>,
    pub peak_rank: Option<Rank>,
    pub matches: Option<i64>,
    pub win_rate_pct: Option<f64>,
    pub kda: Option<f64>,
    /// Upstream `coreCount`; semantics are not documented by the provider.
    pub core_score: Option<f64>,
    pub max_win_streak: Option<i64>,
    pub queue_guid: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct QueueSummary {
    pub queue: Queue,
    pub matches: Option<i64>,
    pub wins: Option<i64>,
    pub losses: Option<i64>,
    pub win_rate_pct: Option<f64>,
    pub per_match: StatLine,
    /// `serverMapCountData`: server-wide reference averages and maxima.
    pub server_average: Option<StatLine>,
    pub server_max: Option<StatLine>,
}

/// `recentMatchCount`, documented upstream as the last 12 matches.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct RecentForm {
    pub role: Role,
    pub win_rate_pct: Option<f64>,
    pub per_match: StatLine,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct HeroUsage {
    pub queue: Queue,
    pub hero: EntityRef,
    pub hero_level: Option<i64>,
    pub matches: Option<i64>,
    pub wins: Option<i64>,
    pub win_rate_pct: Option<f64>,
    pub kda: Option<f64>,
    pub play_time_s: Option<f64>,
    pub per_match: Vec<StatValue>,
    pub per_10min: Vec<StatValue>,
    /// `heroRankInfo.rank`, 0-based upstream tier index.
    pub rank_tier_index: Option<i64>,
    pub ranked_level: Option<i64>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ProvinceRank {
    pub role: Role,
    pub province: Option<String>,
    pub rank: Option<i64>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Behavior {
    pub comment: Option<String>,
    pub honors_received: Option<i64>,
    pub honors_sent: Option<i64>,
    pub reports: Option<i64>,
}

/// One `queryCountInfo` / `fight/queryCount` response.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct CareerSnapshot {
    pub mode: Mode,
    /// Requested season; `None` is the provider's current season.
    pub season: Option<u32>,
    pub roles: Vec<RoleCareer>,
    pub queues: Vec<QueueSummary>,
    pub recent_form: Option<RecentForm>,
    pub frequent_heroes: Vec<EntityRef>,
    pub heroes: Vec<HeroUsage>,
    pub province_ranks: Vec<ProvinceRank>,
    pub behavior: Option<Behavior>,
    pub recent_matches: Vec<MatchSummary>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct HeroBoardEntry {
    pub queue: Queue,
    pub hero: Option<EntityRef>,
    pub province: Option<String>,
    pub rank: Option<i64>,
    pub ranked_level: Option<i64>,
    pub matches: Option<i64>,
    pub win_rate_pct: Option<f64>,
}

/// A participant's competitive career rank for one role, looked up separately
/// from the match (`queryCountInfo` with that participant's own token).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct RoleRating {
    pub role: Role,
    /// Season the rank came from; `None` is the current season.
    pub season: Option<u32>,
    pub rank: Rank,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct PlayerRating {
    pub bnet_id: String,
    pub name: Option<String>,
    pub roles: Vec<RoleRating>,
}

/// Whose rank a player's rating is.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RatingFit {
    /// Their rank for the role they played.
    SameRole,
    /// They have no rank for that role, so it is the highest of their ranks in other roles.
    OtherRoles,
}

impl PlayerRating {
    /// Current-season rating for `role`, falling back to an older season.
    pub fn for_role(&self, role: Role) -> Option<&RoleRating> {
        self.roles
            .iter()
            .filter(|r| r.role == role && r.rank.skill_rating.is_some())
            .min_by_key(|r| r.season.map_or(0, |s| u32::MAX - s))
    }

    /// The rating to use for a player who played `role`. Their rank for that role when
    /// they have one. Otherwise, a player who is ranked, only in other roles, still counts
    /// as ranked: the highest of those ranks (this season's if there are any, else the
    /// earlier season's), so that a lobby is not judged on the few players who happen to
    /// have a rank in exactly the role they played. `None` for a player with no rank at all.
    pub fn rating_for(&self, role: Role) -> Option<(f64, RatingFit)> {
        if role == Role::Unknown {
            return None;
        }
        if let Some(r) = self.for_role(role) {
            return Some((r.rank.skill_rating? as f64, RatingFit::SameRole));
        }
        let others = |current: bool| -> Vec<f64> {
            self.roles
                .iter()
                .filter(|r| r.role != role && r.season.is_none() == current)
                .filter_map(|r| r.rank.skill_rating)
                .map(|v| v as f64)
                .collect()
        };
        let this_season = others(true);
        let pool = if this_season.is_empty() {
            others(false)
        } else {
            this_season
        };
        pool.into_iter()
            .reduce(f64::max)
            .map(|best| (best, RatingFit::OtherRoles))
    }
}

/// One upstream call made while collecting a dataset.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct FetchRecord {
    pub endpoint: String,
    pub mode: Option<Mode>,
    pub season: Option<u32>,
    pub page: Option<u32>,
    pub match_id: Option<String>,
    pub ok: bool,
    pub cached: bool,
    pub error_kind: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ListCoverage {
    pub mode: Mode,
    pub season: Option<u32>,
    pub pages_fetched: u32,
    /// True when an empty or repeating page proved there is nothing further.
    pub exhausted: bool,
    /// Matches added to the local store by this read (newer than the newest stored).
    #[serde(default)]
    pub new_matches: usize,
    /// Matches in the list after this read; with a local store, all of what is kept.
    #[serde(default)]
    pub total_matches: usize,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Coverage {
    pub match_lists: Vec<ListCoverage>,
    pub details_requested: usize,
    pub details_ok: usize,
    /// Details and ratings taken from the local cache rather than fetched.
    #[serde(default)]
    pub cache_hits: usize,
    pub fetches: Vec<FetchRecord>,
}

impl Coverage {
    pub fn failures(&self) -> usize {
        self.fetches.iter().filter(|f| !f.ok).count()
    }
}

/// Everything collected for one player in one run.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct PlayerDataset {
    pub ir_version: String,
    pub provider: String,
    pub generated_at_ms: i64,
    pub profile: PlayerProfile,
    pub careers: Vec<CareerSnapshot>,
    /// Deduplicated by match id across modes, newest first.
    pub matches: Vec<MatchSummary>,
    pub details: BTreeMap<String, MatchDetail>,
    pub hero_boards: Vec<HeroBoardEntry>,
    /// Career ranks of players met in `details`, keyed by Battle.net id.
    /// Only collected when the plan asks for lobby ratings.
    #[serde(default)]
    pub player_ratings: Vec<PlayerRating>,
    pub coverage: Coverage,
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn official_ids_derive_from_guids() {
        assert_eq!(
            official_id("207165582859042818").as_deref(),
            Some("0x02E0000000000002")
        );
        assert_eq!(
            official_id("920986123797276132").as_deref(),
            Some("0x0CC80000000025E4")
        );
        assert_eq!(official_id("0"), None);
        assert_eq!(official_id("abc"), None);
        let hero = EntityRef::new(EntityKind::Hero, "207165582859042818", None);
        assert_eq!(hero.stable_id(), "overwatch:hero:0x02e0000000000002");
    }
}
