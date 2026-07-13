use std::net::Ipv4Addr;

#[derive(Clone, Debug)]
pub(crate) struct LanAddressCandidate {
    pub address: Ipv4Addr,
    pub name: String,
    pub is_default: bool,
    pub has_gateway: bool,
    pub is_physical: bool,
}

pub(crate) fn choose_lan_ipv4(candidates: &[LanAddressCandidate]) -> Option<Ipv4Addr> {
    candidates
        .iter()
        .filter(|candidate| {
            candidate.address.is_private()
                && candidate.is_physical
                && !is_virtual_or_non_lan(&candidate.name)
        })
        .max_by_key(|candidate| lan_candidate_score(candidate))
        .map(|candidate| candidate.address)
}

fn is_virtual_or_non_lan(name: &str) -> bool {
    let name = name.to_ascii_lowercase();
    let first = name.split_whitespace().next().unwrap_or_default();
    [
        "tun", "tap", "utun", "wg", "ppp", "veth", "br-", "rmnet", "ccmni", "pdp_ip",
    ]
    .iter()
    .any(|prefix| first.starts_with(prefix))
        || [
            "virtual",
            "vethernet",
            "vmware",
            "virtualbox",
            "vbox",
            "hyper-v",
            "wsl",
            "docker",
            "tailscale",
            "wireguard",
            "vpn",
            "tunnel",
            "loopback",
            "cellular",
            "mobile broadband",
        ]
        .iter()
        .any(|marker| name.contains(marker))
}

fn lan_candidate_score(candidate: &LanAddressCandidate) -> i32 {
    let mut score = 0;
    if candidate.is_default {
        score += 1000;
    }
    if candidate.has_gateway {
        score += 200;
    }
    if candidate.is_physical {
        score += 100;
    }
    // Address ranges only break ties after route and adapter quality.
    let oct = candidate.address.octets();
    if oct[0] == 192 && oct[1] == 168 {
        score += 30;
    } else if oct[0] == 10 {
        score += 20;
    } else if oct[0] == 172 && (16..=31).contains(&oct[1]) {
        score += 10;
    }
    score
}

pub(crate) fn is_public_ipv4(address: Ipv4Addr) -> bool {
    let [first, second, _, _] = address.octets();
    let is_shared = first == 100 && (64..=127).contains(&second);
    let is_benchmark = first == 198 && (18..=19).contains(&second);
    !address.is_private()
        && !address.is_loopback()
        && !address.is_link_local()
        && !address.is_documentation()
        && !address.is_multicast()
        && !address.is_broadcast()
        && !address.is_unspecified()
        && !is_shared
        && !is_benchmark
        && first != 0
        && first < 240
}

#[cfg(test)]
mod tests {
    use super::{choose_lan_ipv4, is_public_ipv4, LanAddressCandidate};
    use std::net::Ipv4Addr;

    fn candidate(
        address: [u8; 4],
        name: &str,
        is_default: bool,
        has_gateway: bool,
        is_physical: bool,
    ) -> LanAddressCandidate {
        LanAddressCandidate {
            address: Ipv4Addr::from(address),
            name: name.to_owned(),
            is_default,
            has_gateway,
            is_physical,
        }
    }

    #[test]
    fn physical_lan_adapter_beats_virtual_and_vpn_adapters() {
        let candidates = [
            candidate([10, 8, 0, 2], "WireGuard Tunnel", true, true, false),
            candidate([192, 168, 1, 22], "Ethernet", false, true, true),
            candidate([172, 20, 0, 1], "vEthernet (WSL)", false, false, true),
        ];

        assert_eq!(
            choose_lan_ipv4(&candidates),
            Some(Ipv4Addr::new(192, 168, 1, 22))
        );
    }

    #[test]
    fn default_physical_adapter_wins_between_real_adapters() {
        let candidates = [
            candidate([192, 168, 2, 10], "Ethernet 2", false, true, true),
            candidate([10, 16, 1, 20], "Wi-Fi", true, true, true),
        ];

        assert_eq!(
            choose_lan_ipv4(&candidates),
            Some(Ipv4Addr::new(10, 16, 1, 20))
        );
    }

    #[test]
    fn private_range_only_breaks_ties() {
        let candidates = [
            candidate([10, 16, 1, 20], "Ethernet", false, true, true),
            candidate([192, 168, 2, 10], "Wi-Fi", false, true, true),
        ];

        assert_eq!(
            choose_lan_ipv4(&candidates),
            Some(Ipv4Addr::new(192, 168, 2, 10))
        );
    }

    #[test]
    fn rejects_vpn_virtual_and_cellular_interfaces() {
        let candidates = [
            candidate([10, 8, 0, 2], "tun0 VPN", true, true, true),
            candidate([172, 20, 0, 1], "vEthernet (WSL)", false, false, true),
            candidate([10, 0, 0, 4], "rmnet_data0 cellular", false, true, true),
        ];

        assert_eq!(choose_lan_ipv4(&candidates), None);
    }

    #[test]
    fn rejects_non_lan_and_non_public_addresses() {
        let candidates = [candidate([169, 254, 10, 1], "Ethernet", true, true, true)];
        assert_eq!(choose_lan_ipv4(&candidates), None);

        assert!(is_public_ipv4(Ipv4Addr::new(101, 87, 127, 173)));
        assert!(!is_public_ipv4(Ipv4Addr::new(10, 0, 0, 1)));
        assert!(!is_public_ipv4(Ipv4Addr::new(100, 64, 0, 1)));
        assert!(!is_public_ipv4(Ipv4Addr::new(127, 0, 0, 1)));
        assert!(!is_public_ipv4(Ipv4Addr::new(169, 254, 1, 1)));
    }
}
