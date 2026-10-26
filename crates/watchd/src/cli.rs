//! Offline data commands:
//!   watchd dataset <BattleTag> [--modes competitive,quick,stadium] [--season N]
//!                  [--career-seasons 20,21] [--pages N] [--details N] [--no-hero-board]
//!                  [--lobby [--max-rated N]] [--out PATH]
//!   watchd analyze <dataset.json> [--utc-offset MINUTES] [--out PATH]
use anyhow::{Context, bail};
use serde_json::{Value, json};
use std::path::PathBuf;
use watch_core::{
    Catalog, WatchClient,
    analysis::{self, AnalysisOptions},
    collect::{self, CollectPlan},
    dashen::Mode,
    ir::PlayerDataset,
    load_secrets,
};

struct Args {
    positional: Vec<String>,
    options: Vec<(String, Option<String>)>,
}

impl Args {
    fn parse(raw: &[String]) -> Self {
        let mut positional = Vec::new();
        let mut options = Vec::new();
        let mut iter = raw.iter().peekable();
        while let Some(arg) = iter.next() {
            if let Some(name) = arg.strip_prefix("--") {
                let value = iter.next_if(|v| !v.starts_with("--")).cloned();
                options.push((name.to_owned(), value));
            } else {
                positional.push(arg.clone());
            }
        }
        Self {
            positional,
            options,
        }
    }
    fn value(&self, name: &str) -> Option<&str> {
        self.options
            .iter()
            .find(|(n, _)| n == name)
            .and_then(|(_, v)| v.as_deref())
    }
    fn flag(&self, name: &str) -> bool {
        self.options.iter().any(|(n, _)| n == name)
    }
    fn number<T: std::str::FromStr>(&self, name: &str) -> anyhow::Result<Option<T>> {
        self.value(name)
            .map(|v| {
                v.parse()
                    .map_err(|_| anyhow::anyhow!("--{name} expects a number"))
            })
            .transpose()
    }
}

pub async fn run(command: &str, raw: &[String]) -> anyhow::Result<()> {
    let args = Args::parse(raw);
    match command {
        "dataset" => dataset(&args).await,
        "analyze" => analyze(&args),
        _ => bail!("unknown command"),
    }
}

fn write_output(out: Option<&str>, stem: &str, value: &Value) -> anyhow::Result<PathBuf> {
    let path = match out {
        Some(path) => PathBuf::from(path),
        None => {
            let safe: String = stem
                .chars()
                .take(80)
                .map(|c| {
                    if c.is_alphanumeric() || matches!(c, '-' | '_') {
                        c
                    } else {
                        '_'
                    }
                })
                .collect();
            let dir = watch_core::data_dir().join("exports");
            std::fs::create_dir_all(&dir)?;
            dir.join(format!("{safe}-{}.json", uuid::Uuid::new_v4()))
        }
    };
    let mut bytes = serde_json::to_vec_pretty(value)?;
    bytes.push(b'\n');
    std::fs::write(&path, bytes).with_context(|| format!("cannot write {}", path.display()))?;
    Ok(path)
}

async fn dataset(args: &Args) -> anyhow::Result<()> {
    let name = args
        .positional
        .first()
        .context("Usage: watchd dataset <BattleTag> [options]")?;
    let mut plan = CollectPlan::default();
    if let Some(modes) = args.value("modes") {
        plan.modes = modes
            .split(',')
            .map(|m| Mode::parse(m.trim()).with_context(|| format!("unknown mode {m}")))
            .collect::<anyhow::Result<_>>()?;
    }
    plan.season = args.number("season")?;
    if let Some(seasons) = args.value("career-seasons") {
        plan.career_seasons = seasons
            .split(',')
            .map(|s| s.trim().parse().context("--career-seasons expects numbers"))
            .collect::<anyhow::Result<_>>()?;
    }
    plan.max_pages = args.number("pages")?.unwrap_or(plan.max_pages);
    plan.max_details = args.number("details")?.unwrap_or(plan.max_details);
    plan.hero_board = !args.flag("no-hero-board");
    plan.lobby_ratings = args.flag("lobby");
    plan.max_rated_players = args.number("max-rated")?.unwrap_or(plan.max_rated_players);
    // Per-role selection: the newest N matches of each chosen role (all three by default).
    plan.details_per_role = args.number("per-role")?;
    if let Some(roles) = args.value("roles") {
        plan.roles = roles
            .split(',')
            .map(|r| match watch_core::ir::Role::parse(r.trim()) {
                role if watch_core::ir::Role::PLAYABLE.contains(&role) => Ok(role),
                _ => Err(anyhow::anyhow!("--roles expects tank, damage or support")),
            })
            .collect::<anyhow::Result<_>>()?;
    }
    // Finished matches and ranks are kept between runs unless asked not to.
    if !args.flag("no-cache") {
        plan.cache =
            crate::open_store().map(|c| c as std::sync::Arc<dyn watch_core::StrengthCache>);
    }
    plan.validate().map_err(|e| anyhow::anyhow!(e.message))?;

    let client = WatchClient::new(load_secrets()?)?;
    let catalog = Catalog::load();
    // The account's own player needs no search.
    let own = collect::account_player(&client)
        .await
        .ok()
        .filter(|(_, id)| {
            let wanted = collect::normalize_battletag(name).map(|n| n.to_lowercase());
            id["name"].as_str().map(str::to_lowercase) == wanted
        });
    let (token, identity) = match own {
        Some(found) => found,
        None => collect::search_player(&client, name)
            .await
            .map_err(|e| anyhow::anyhow!(e.message))?,
    };
    let dataset = collect::collect_player(&client, &catalog, &token, &identity, &plan).await;
    drop(token);
    let analysis = analysis::analyze(&dataset, &AnalysisOptions::default());
    let c = &dataset.coverage;
    eprintln!(
        "{}: {} matches, {}/{} details, {} careers, {} rated players, {} requests ({} failed)",
        dataset.profile.name.as_deref().unwrap_or(name),
        dataset.matches.len(),
        c.details_ok,
        c.details_requested,
        dataset.careers.len(),
        dataset.player_ratings.len(),
        c.fetches.len(),
        c.failures(),
    );
    if catalog.heroes.is_empty() {
        eprintln!(
            "note: no catalog imported; hero and map names are empty. Run `watchd import-catalog <query_tool.json>`."
        );
    }
    let path = write_output(
        args.value("out"),
        &format!("dataset-{name}"),
        &json!({"dataset":dataset,"analysis":analysis}),
    )?;
    println!("{}", path.display());
    Ok(())
}

fn analyze(args: &Args) -> anyhow::Result<()> {
    let input = args
        .positional
        .first()
        .context("Usage: watchd analyze <dataset.json> [--utc-offset MINUTES] [--out PATH]")?;
    let value: Value = serde_json::from_slice(&std::fs::read(input)?)?;
    let dataset: PlayerDataset =
        serde_json::from_value(value.get("dataset").cloned().unwrap_or(value))
            .context("file is not a Watch Overwatch dataset")?;
    let mut options = AnalysisOptions::default();
    if let Some(offset) = args.number("utc-offset")? {
        options.utc_offset_minutes = offset;
    }
    let analysis = analysis::analyze(&dataset, &options);
    match args.value("out") {
        Some(_) => println!(
            "{}",
            write_output(args.value("out"), "analysis", &json!(analysis))?.display()
        ),
        None => println!("{}", serde_json::to_string_pretty(&analysis)?),
    }
    Ok(())
}
