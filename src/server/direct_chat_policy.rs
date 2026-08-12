use std::collections::HashMap;

pub(crate) fn direct_chat_id_matches(authenticated_id: Option<&str>, claimed_id: &str) -> bool {
    let Some(authenticated_id) = authenticated_id else {
        return false;
    };
    let claimed = claimed_id.split('@').next().unwrap_or(claimed_id);
    authenticated_id == claimed
}

pub(crate) fn direct_chat_policy_for_peer(
    policies_json: &str,
    pairings_json: &str,
    peer_id: &str,
) -> String {
    direct_chat_policy_for_peer_with_accepted(policies_json, pairings_json, "{}", peer_id)
}

pub(crate) fn direct_chat_policy_for_peer_with_accepted(
    policies_json: &str,
    pairings_json: &str,
    accepted_json: &str,
    peer_id: &str,
) -> String {
    let policies =
        serde_json::from_str::<HashMap<String, String>>(policies_json).unwrap_or_default();
    if let Some(policy) = policies.get(peer_id) {
        return policy.clone();
    }

    let pairings = serde_json::from_str::<serde_json::Value>(pairings_json).unwrap_or_default();
    if let Some(policy) = pairings
        .get(peer_id)
        .and_then(|pairing| pairing.get("account_id"))
        .and_then(|account_id| account_id.as_str())
        .and_then(|account_id| policies.get(account_id))
    {
        return policy.clone();
    }

    let accepted =
        serde_json::from_str::<HashMap<String, String>>(accepted_json).unwrap_or_default();
    if accepted.contains_key(peer_id)
        || pairings
            .get(peer_id)
            .and_then(|pairing| pairing.get("account_id"))
            .and_then(|account_id| account_id.as_str())
            .is_some_and(|account_id| accepted.contains_key(account_id))
    {
        return "allow".to_owned();
    }

    let mut bound_device_allowed = false;
    if let Some(pairings) = pairings.as_object() {
        for (stored_peer_id, pairing) in pairings {
            if pairing.get("account_id").and_then(|value| value.as_str()) != Some(peer_id) {
                continue;
            }
            let paired_peer_id = pairing
                .get("peer_id")
                .and_then(|value| value.as_str())
                .unwrap_or(stored_peer_id);
            if accepted.contains_key(stored_peer_id)
                || accepted.contains_key(paired_peer_id)
                || accepted.contains_key(peer_id)
            {
                bound_device_allowed = true;
            }
            match policies
                .get(paired_peer_id)
                .or_else(|| policies.get(stored_peer_id))
                .map(String::as_str)
            {
                Some("deny") => return "deny".to_owned(),
                Some("allow") => bound_device_allowed = true,
                _ => {}
            }
        }
    }
    if bound_device_allowed {
        "allow".to_owned()
    } else {
        "ask".to_owned()
    }
}

pub(crate) fn direct_chat_identity_allowed(
    authenticated_id_matches: bool,
    actual_key: Option<&str>,
    pinned_key: Option<&str>,
    _peer_policy: &str,
) -> bool {
    if !authenticated_id_matches {
        return false;
    }
    let Some(actual_key) = actual_key else {
        return false;
    };
    let normalize = |value: &str| {
        value
            .chars()
            .filter(|c| !c.is_whitespace() && *c != ':')
            .flat_map(char::to_lowercase)
            .collect::<String>()
    };

    match pinned_key {
        Some(pinned_key) => normalize(pinned_key) == normalize(actual_key),
        None => true,
    }
}

pub(crate) fn direct_chat_access_allowed(
    companion_verified: bool,
    identity_verified: bool,
    always_on: bool,
    trusted_only: bool,
    peer_policy: &str,
) -> bool {
    if !always_on {
        return false;
    }
    if companion_verified {
        return true;
    }
    if peer_policy == "deny" {
        return false;
    }
    // "Everyone" audience: accept any non-denied peer, even when the identity
    // is not yet verified. Direct LAN/public-IP chat must work out of the box
    // once the host allowed messages from strangers (this is what previously
    // made B->A messages fail while the host had "strangers can chat" on).
    if !trusted_only {
        return true;
    }
    // Trusted-only: only identity-verified friends.
    identity_verified && peer_policy == "allow"
}

#[cfg(test)]
mod tests {
    use super::{
        direct_chat_access_allowed, direct_chat_id_matches, direct_chat_identity_allowed,
        direct_chat_policy_for_peer,
    };

    #[test]
    fn authenticated_id_matches_claimed_id_with_rendezvous_suffix() {
        assert!(direct_chat_id_matches(Some("423727"), "423727"));
        assert!(direct_chat_id_matches(Some("423727"), "423727@rendezvous.example.com"));
        assert!(!direct_chat_id_matches(Some("423728"), "423727"));
        assert!(!direct_chat_id_matches(None, "423727"));
    }

    #[test]
    fn account_policy_matches_bound_device_id() {
        let policies = r#"{"account-42":"allow"}"#;
        let pairings = r#"{
            "423727": {
                "peer_id": "423727",
                "account_id": "account-42",
                "fingerprint": "aa:bb"
            }
        }"#;

        assert_eq!(
            direct_chat_policy_for_peer(policies, pairings, "423727"),
            "allow"
        );
    }

    #[test]
    fn device_policy_takes_precedence_over_account_policy() {
        let policies = r#"{"423727":"deny","account-42":"allow"}"#;
        let pairings = r#"{
            "423727": {
                "peer_id": "423727",
                "account_id": "account-42"
            }
        }"#;

        assert_eq!(
            direct_chat_policy_for_peer(policies, pairings, "423727"),
            "deny"
        );
    }

    #[test]
    fn bound_device_policy_matches_account_id() {
        let policies = r#"{"423727":"allow"}"#;
        let pairings = r#"{
            "423727": {
                "peer_id": "423727",
                "account_id": "account-42",
                "fingerprint": "aa:bb"
            }
        }"#;

        assert_eq!(
            direct_chat_policy_for_peer(policies, pairings, "account-42"),
            "allow"
        );
    }

    #[test]
    fn history_presence_does_not_grant_chat_access() {
        assert!(!direct_chat_access_allowed(
            false, true, true, true, "ask"
        ));
    }

    #[test]
    fn explicit_friend_is_allowed() {
        assert!(direct_chat_access_allowed(
            false, true, true, true, "allow"
        ));
    }

    #[test]
    fn explicit_friend_accepts_first_signed_identity() {
        assert!(direct_chat_identity_allowed(
            true,
            Some("AA:BB"),
            None,
            "allow"
        ));
    }

    #[test]
    fn pinned_identity_mismatch_is_rejected_even_for_friend() {
        assert!(!direct_chat_identity_allowed(
            true,
            Some("AA:CC"),
            Some("AA:BB"),
            "allow"
        ));
    }

    #[test]
    fn unpinned_signed_identity_can_be_checked_by_audience_policy() {
        assert!(direct_chat_identity_allowed(
            true,
            Some("AA:BB"),
            None,
            "ask"
        ));
    }

    #[test]
    fn verified_stranger_requires_everyone_mode() {
        assert!(!direct_chat_access_allowed(
            false, true, true, true, "ask"
        ));
        assert!(direct_chat_access_allowed(
            false, true, true, false, "ask"
        ));
    }

    #[test]
    fn denied_peer_is_always_rejected() {
        assert!(!direct_chat_access_allowed(
            false, true, true, false, "deny"
        ));
    }

    #[test]
    fn everyone_mode_accepts_unverified_strangers() {
        assert!(direct_chat_access_allowed(
            false, false, true, false, "ask"
        ));
    }

    #[test]
    fn companion_still_requires_always_on_messaging() {
        assert!(direct_chat_access_allowed(
            true, false, true, true, "ask"
        ));
        assert!(!direct_chat_access_allowed(
            true, false, false, true, "allow"
        ));
    }
}
