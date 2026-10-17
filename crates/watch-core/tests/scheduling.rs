use axum::{
    Json, Router,
    extract::{Query, State},
    http::StatusCode,
    routing::get,
};
use serde_json::json;
use std::{
    sync::{
        Arc,
        atomic::{AtomicUsize, Ordering},
    },
    time::Duration,
};
use watch_core::{AccountSecret, Policy, RequestSpec, SecretsFile, WatchClient};

fn secrets() -> SecretsFile {
    SecretsFile {
        accounts: vec![AccountSecret {
            name: "test".into(),
            role_id: 1,
            token: "test-secret-do-not-log".into(),
            dts: 2026,
            server: 1,
        }],
    }
}
fn spec() -> RequestSpec {
    RequestSpec {
        endpoint: "customer/queryCountInfo".into(),
        payload: json!({"token":"player-secret","gameMode":"sport"}),
    }
}
async fn client(router: Router, policy: Policy) -> WatchClient {
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let base = format!("http://{}", listener.local_addr().unwrap());
    tokio::spawn(async move {
        axum::serve(listener, router).await.unwrap();
    });
    WatchClient::with_base(secrets(), &base, policy).unwrap()
}
#[tokio::test]
async fn uses_get_query_and_checks_business_failures() {
    let router = Router::new().route(
        "/customer/queryCountInfo",
        get(
            |Query(params): Query<std::collections::HashMap<String, String>>| async move {
                assert_eq!(params["token"], "player-secret");
                Json(json!({"code":12,"success":false,"message":"private upstream detail"}))
            },
        ),
    );
    let c = client(router, Policy::default()).await;
    let e = c.request(spec()).await.unwrap_err();
    assert_eq!(e.kind, "business");
    assert!(!e.message.contains("private upstream detail"));
    assert_eq!(c.metrics().await[0].status, "business");
}
#[tokio::test]
async fn retries_server_errors_but_not_client_errors() {
    let calls = Arc::new(AtomicUsize::new(0));
    let router = Router::new()
        .route(
            "/customer/queryCountInfo",
            get(|State(c): State<Arc<AtomicUsize>>| async move {
                if c.fetch_add(1, Ordering::SeqCst) == 0 {
                    (StatusCode::SERVICE_UNAVAILABLE, Json(json!({})))
                } else {
                    (StatusCode::OK, Json(json!({"code":0,"data":{}})))
                }
            }),
        )
        .with_state(calls.clone());
    let c = client(router, Policy::default()).await;
    let (metric, _) = c.request(spec()).await.unwrap();
    assert_eq!(metric.attempts, 2);
    assert_eq!(calls.load(Ordering::SeqCst), 2);
    let router = Router::new().route(
        "/customer/queryCountInfo",
        get(|| async { StatusCode::BAD_REQUEST }),
    );
    let c = client(router, Policy::default()).await;
    assert_eq!(c.request(spec()).await.unwrap_err().kind, "upstream");
    assert_eq!(c.metrics().await[0].attempts, 1);
}
#[tokio::test]
async fn rate_window_is_shared_across_concurrent_tasks() {
    let router = Router::new().route(
        "/customer/queryCountInfo",
        get(|| async { Json(json!({"code":0})) }),
    );
    let policy = Policy {
        rate: 1,
        rate_window: Duration::from_millis(100),
        ..Policy::default()
    };
    let c = Arc::new(client(router, policy).await);
    let started = std::time::Instant::now();
    let (a, b) = tokio::join!(c.request(spec()), c.request(spec()));
    assert!(a.is_ok() && b.is_ok());
    assert!(started.elapsed() >= Duration::from_millis(95));
}
#[tokio::test]
async fn cooldown_does_not_send_requests_early_and_deadline_includes_wait() {
    let calls = Arc::new(AtomicUsize::new(0));
    let router = Router::new()
        .route(
            "/customer/queryCountInfo",
            get(|State(c): State<Arc<AtomicUsize>>| async move {
                c.fetch_add(1, Ordering::SeqCst);
                (
                    StatusCode::TOO_MANY_REQUESTS,
                    [("retry-after", "1")],
                    Json(json!({})),
                )
            }),
        )
        .with_state(calls.clone());
    let c = client(
        router,
        Policy {
            timeout: Duration::from_millis(150),
            ..Policy::default()
        },
    )
    .await;
    assert_eq!(c.request(spec()).await.unwrap_err().kind, "timeout");
    assert_eq!(calls.load(Ordering::SeqCst), 1);
    assert_eq!(c.account_views().await[0].status, "cooldown");
    assert_eq!(c.request(spec()).await.unwrap_err().kind, "timeout");
    assert_eq!(calls.load(Ordering::SeqCst), 1);
}
#[tokio::test]
async fn admission_is_bounded_and_cancellation_releases_permits() {
    let router = Router::new().route(
        "/customer/queryCountInfo",
        get(|| async {
            tokio::time::sleep(Duration::from_secs(1)).await;
            Json(json!({"code":0}))
        }),
    );
    let c = Arc::new(
        client(
            router,
            Policy {
                capacity: 1,
                concurrency: 1,
                ..Policy::default()
            },
        )
        .await,
    );
    let worker = {
        let c = c.clone();
        tokio::spawn(async move { c.request(spec()).await })
    };
    tokio::time::sleep(Duration::from_millis(30)).await;
    assert_eq!(c.request(spec()).await.unwrap_err().kind, "busy");
    worker.abort();
    let _ = worker.await;
    assert!(c.request(spec()).await.is_ok());
}
#[tokio::test]
async fn auth_errors_disable_account_until_updated_and_views_do_not_expose_secrets() {
    let c = client(
        Router::new().route(
            "/customer/queryCountInfo",
            get(|| async { StatusCode::UNAUTHORIZED }),
        ),
        Policy::default(),
    )
    .await;
    assert_eq!(c.request(spec()).await.unwrap_err().kind, "auth");
    assert_eq!(c.account_views().await[0].status, "expired");
    let views = serde_json::to_string(&c.account_views().await).unwrap();
    assert!(!views.contains("test-secret"));
    assert!(
        !serde_json::to_string(&c.metrics().await)
            .unwrap()
            .contains("player-secret")
    );
    c.replace_accounts(secrets()).await.unwrap();
    assert_eq!(c.account_views().await[0].status, "ready");
}
#[tokio::test]
async fn endpoint_allowlist_prevents_path_and_redirect_credential_leaks() {
    let c = client(
        Router::new().route(
            "/customer/queryCountInfo",
            get(|| async {
                (
                    StatusCode::TEMPORARY_REDIRECT,
                    [("location", "https://example.com/")],
                )
            }),
        ),
        Policy::default(),
    )
    .await;
    assert_eq!(
        c.request(RequestSpec {
            endpoint: "../other".into(),
            payload: json!({})
        })
        .await
        .unwrap_err()
        .kind,
        "validation"
    );
    assert_eq!(c.request(spec()).await.unwrap_err().kind, "upstream");
}
#[tokio::test]
async fn late_auth_failure_is_not_lost_after_concurrent_cooldown() {
    let count = Arc::new(AtomicUsize::new(0));
    let router = Router::new().route(
        "/customer/queryCountInfo",
        get(move || {
            let count = count.clone();
            async move {
                let index = count.fetch_add(1, Ordering::SeqCst);
                if index == 0 {
                    tokio::time::sleep(Duration::from_millis(100)).await;
                    (StatusCode::UNAUTHORIZED, [("retry-after", "0")])
                } else {
                    (StatusCode::TOO_MANY_REQUESTS, [("retry-after", "1")])
                }
            }
        }),
    );
    let c = Arc::new(
        client(
            router,
            Policy {
                timeout: Duration::from_millis(300),
                max_attempts: 1,
                ..Policy::default()
            },
        )
        .await,
    );
    let (a, b) = tokio::join!(c.request(spec()), c.request(spec()));
    assert!(a.is_err() && b.is_err());
    assert_eq!(c.account_views().await[0].status, "expired");
}
