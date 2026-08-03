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
    if !identity_verified || peer_policy == "deny" {
        return false;
    }
    peer_policy == "allow" || !trusted_only
}

#[cfg(test)]
mod tests {
    use super::direct_chat_access_allowed;

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
    fn verified_stranger_requires_everyone_mode() {
        assert!(!direct_chat_access_allowed(
            false, true, true, true, "ask"
        ));
        assert!(direct_chat_access_allowed(
            false, true, true, false, "ask"
        ));
    }

    #[test]
    fn denied_or_unverified_peer_is_rejected() {
        assert!(!direct_chat_access_allowed(
            false, true, true, false, "deny"
        ));
        assert!(!direct_chat_access_allowed(
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
