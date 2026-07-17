use std::time::Duration;

use luoda::viewer_registry::Registry;

#[test]
fn reusable_invite_admits_multiple_direct_viewers() {
    let registry = Registry::new();
    let invite = registry.issue_token_with_policy(
        "host-reusable",
        "session-reusable",
        Some(Duration::from_secs(60)),
        false,
    );

    assert_eq!(
        registry.consume_token(&invite.token).as_deref(),
        Some("host-reusable"),
    );
    assert_eq!(
        registry.consume_token(&invite.token).as_deref(),
        Some("host-reusable"),
    );
}

#[test]
fn one_shot_invite_is_removed_after_first_viewer() {
    let registry = Registry::new();
    let invite = registry.issue_token_with_policy(
        "host-once",
        "session-once",
        Some(Duration::from_secs(60)),
        true,
    );

    assert!(registry.consume_token(&invite.token).is_some());
    assert!(registry.consume_token(&invite.token).is_none());
}
