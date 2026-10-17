//! The single place that knows Dashen paths, methods, credential placement
//! and which endpoint serves which game mode.
use serde::{Deserialize, Serialize};

/// Game mode as a user selects it. Provider spellings stay in this module.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, PartialOrd, Ord, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Mode {
    Competitive,
    Quick,
    Stadium,
}

impl Mode {
    pub const ALL: [Mode; 3] = [Mode::Competitive, Mode::Quick, Mode::Stadium];

    /// Accepts the provider query values used by the UI as well as IR names.
    pub fn parse(value: &str) -> Option<Self> {
        match value {
            "sport" | "competitive" => Some(Self::Competitive),
            "leisure" | "quick" => Some(Self::Quick),
            "SportFight" | "stadium" => Some(Self::Stadium),
            _ => None,
        }
    }
    /// `gameMode` query value.
    pub fn provider_value(self) -> &'static str {
        match self {
            Self::Competitive => "sport",
            Self::Quick => "leisure",
            Self::Stadium => "SportFight",
        }
    }
    pub fn career(self) -> Endpoint {
        match self {
            Self::Stadium => Endpoint::FightCount,
            _ => Endpoint::CareerCount,
        }
    }
    pub fn match_list(self) -> Endpoint {
        match self {
            Self::Stadium => Endpoint::FightMatchList,
            _ => Endpoint::MatchList,
        }
    }
    pub fn match_info(self) -> Endpoint {
        match self {
            Self::Stadium => Endpoint::FightMatchInfo,
            _ => Endpoint::MatchInfo,
        }
    }
    /// Stadium rank scores are continuous; normal modes use the compact tier encoding.
    pub fn continuous_rank_score(self) -> bool {
        self == Self::Stadium
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum Endpoint {
    SearchAccount,
    Card,
    CareerCount,
    MatchList,
    MatchInfo,
    FightCount,
    FightMatchList,
    FightMatchInfo,
    FightRoleCard,
    ProvinceRank,
    HeroBoard,
    PlayerHeroBoard,
}

impl Endpoint {
    pub const ALL: [Endpoint; 12] = [
        Self::SearchAccount,
        Self::Card,
        Self::CareerCount,
        Self::MatchList,
        Self::MatchInfo,
        Self::FightCount,
        Self::FightMatchList,
        Self::FightMatchInfo,
        Self::FightRoleCard,
        Self::ProvinceRank,
        Self::HeroBoard,
        Self::PlayerHeroBoard,
    ];

    pub fn path(self) -> &'static str {
        match self {
            Self::SearchAccount => "searchBnetAccount",
            Self::Card => "customer/queryCard",
            Self::CareerCount => "customer/queryCountInfo",
            Self::MatchList => "customer/queryMatchList",
            Self::MatchInfo => "customer/queryMatchInfo",
            Self::FightCount => "customer/fight/queryCount",
            Self::FightMatchList => "customer/fight/queryMatchList",
            Self::FightMatchInfo => "customer/fight/queryMatchInfo",
            Self::FightRoleCard => "customer/fight/getLeisureFightRoleCard",
            Self::ProvinceRank => "queryProvinceRank",
            Self::HeroBoard => "billboard/getHeroBillboard",
            Self::PlayerHeroBoard => "billboard/customGetUserHeroBillboard",
        }
    }
    /// Exact allowlist match; anything else is rejected before a request is built.
    pub fn parse(path: &str) -> Option<Self> {
        Self::ALL.into_iter().find(|e| e.path() == path)
    }
    /// Only account search is a JSON POST; everything else is a GET with query parameters.
    pub fn is_post(self) -> bool {
        self == Self::SearchAccount
    }
    /// These endpoints authenticate with the bot account in the payload as well as the
    /// headers; customer endpoints instead carry the target player's `customerToken`.
    pub fn account_in_payload(self) -> bool {
        matches!(
            self,
            Self::SearchAccount | Self::ProvinceRank | Self::HeroBoard
        )
    }
}

pub fn endpoint_paths() -> Vec<&'static str> {
    Endpoint::ALL.into_iter().map(Endpoint::path).collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn paths_round_trip_and_reject_unknown() {
        for e in Endpoint::ALL {
            assert_eq!(Endpoint::parse(e.path()), Some(e));
        }
        assert_eq!(Endpoint::parse("../customer/queryCard"), None);
        assert_eq!(
            Mode::parse("SportFight").unwrap().match_info(),
            Endpoint::FightMatchInfo
        );
    }
}
