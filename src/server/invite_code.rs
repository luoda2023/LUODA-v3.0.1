//! `libpi` helper utilities for invite tokens.
//!
//! The host-side UI wants a short, human-typable code that uniquely identifies
//! a freshly minted InviteToken (the join URL itself is long and contains the
//! raw UUID token). We derive a 12-character Crockford Base32 short code from
//! a SHA-256 hash of the token:
//!
//! * Crockford Base32 alphabet: `0123456789ABCDEFGHJKMNPQRSTVWXYZ` (no I, L,
//!   O, U to avoid ambiguity with 1, 1, 0, V).
//! * 12 chars = 60 bits of hash entropy -- collision probability across the
//!   bounded registry active set (thousands of tokens) is negligible.
//! * The decoder accepts both upper and lower case, and normalises visually
//!   confusable characters (`I`/`L` -> `1`, `O` -> `0`) so the viewer can type
//!   it loosely and still join the right session.
//!
//! This module is pure-Rust with no extra deps, so it works in libpi builds
//! (including android / ios where the host-side UI is Flutter).

use sha2::{Digest, Sha256};

/// Crockford Base32 alphabet, indexed by 5-bit groups.
pub const CROCKFORD_ALPHABET: &[u8; 32] = b"0123456789ABCDEFGHJKMNPQRSTVWXYZ";

/// Recommended short-code length. 12 chars = 60 bits of entropy.
pub const SHORT_CODE_LEN: usize = 12;

/// Encode a 12-char Crockford base32 short code from a token (UUID hex).
///
/// We hash the token with SHA-256 and take the first 60 bits of the digest
/// (12 chars * 5 bits = 60). This gives a stable, uniform short code for any
/// given token, suitable for display in the host UI:
///
/// ```text
///   Invite URL: https://luoda.example/j?t=abcd...        (long, QR code)
///   Short code:  J6K2-9P47-NQXR                          (human-typable)
/// ```
pub fn encode_short_code(token: &str) -> String {
    let digest = Sha256::digest(token.as_bytes());
    // 60 bits = 7.5 bytes; we consume 8 bytes but mask the final nibble.
    let bytes = &digest[..8];
    let mut bits: u64 = 0;
    for (i, byte) in bytes.iter().enumerate() {
        bits |= (*byte as u64) << (56 - 8 * i);
    }
    // We only need 60 bits, so drop the low 4.
    bits >>= 4;
    let mut out = String::with_capacity(SHORT_CODE_LEN);
    for _ in 0..SHORT_CODE_LEN {
        let idx = (bits & 0x1F) as usize;
        out.insert(0, CROCKFORD_ALPHABET[idx] as char);
        bits >>= 5;
    }
    out
}

/// Decode a Crockford base32 short code back to the raw 60-bit value, after
/// normalisation. Returns `None` if the input contains any character that
/// is not part of the (case-insensitive, confusable-normalised) alphabet.
///
/// Normalisation rules (matches Crockford spec):
/// * lowercase -> uppercase
/// * `I`, `L`  -> `1`
/// * `O`       -> `0`
/// * `U`       -> `V`
/// * hyphens and whitespace are stripped
pub fn decode_short_code(input: &str) -> Option<[u8; 8]> {
    let mut cleaned = String::with_capacity(input.len());
    for ch in input.chars() {
        match ch {
            '-' | ' ' | '\t' => continue,
            _ => cleaned.push(ch),
        }
    }
    if cleaned.len() != SHORT_CODE_LEN {
        return None;
    }
    let mut bits: u64 = 0;
    for ch in cleaned.chars() {
        let normalised = match ch {
            'I' | 'L' | 'i' | 'l' => '1',
            'O' | 'o' => '0',
            'U' | 'u' => 'V',
            _ => ch.to_ascii_uppercase(),
        };
        let idx = CROCKFORD_ALPHABET
            .iter()
            .position(|&c| c as char == normalised)?;
        bits <<= 5;
        bits |= idx as u64;
    }
    // 12 chars * 5 bits = 60 bits -> shift left 4 to land in the top 60 bits
    // of a u64, then split into 8 bytes.
    bits <<= 4;
    let mut out = [0u8; 8];
    for (i, byte) in out.iter_mut().enumerate() {
        *byte = ((bits >> (56 - 8 * i)) & 0xFF) as u8;
    }
    Some(out)
}

/// Canonicalise a user-typed short code to the form used as the registry
/// index key: strip hyphens / whitespace, apply Crockford confusable
/// normalisation (I/L -> 1, O -> 0, U -> V), uppercase, and verify it
/// decodes to a valid 60-bit value. Returns `None` if the input is not a
/// well-formed 12-char Crockford base32 short code (after normalisation).
///
/// The returned string is exactly `SHORT_CODE_LEN` chars long and consists
/// of `CROCKFORD_ALPHABET` characters only. Both the host (when storing
/// into the registry) and the viewer (when resolving) route through this
/// helper so that stray hyphens or lowercase characters do not cause a
/// lookup miss.
pub fn normalize_short_code(input: &str) -> Option<String> {
    let mut cleaned = String::with_capacity(input.len());
    for ch in input.chars() {
        match ch {
            '-' | ' ' | '\t' => continue,
            _ => cleaned.push(ch),
        }
    }
    if cleaned.len() != SHORT_CODE_LEN {
        return None;
    }
    let mut out = String::with_capacity(SHORT_CODE_LEN);
    for ch in cleaned.chars() {
        let normalised = match ch {
            'I' | 'L' | 'i' | 'l' => '1',
            'O' | 'o' => '0',
            'U' | 'u' => 'V',
            _ => ch.to_ascii_uppercase(),
        };
        let idx = CROCKFORD_ALPHABET
            .iter()
            .position(|&c| c as char == normalised)?;
        out.push(CROCKFORD_ALPHABET[idx] as char);
    }
    Some(out)
}

/// Format a short code with hyphens every 4 characters for display.
/// `J6K29P47NQXR` -> `J6K2-9P47-NQXR`.
pub fn format_short_code(code: &str) -> String {
    let cleaned: String = code.chars().filter(|c| *c != '-').collect();
    cleaned
        .as_bytes()
        .chunks(4)
        .map(|chunk| std::str::from_utf8(chunk).unwrap_or(""))
        .collect::<Vec<_>>()
        .join("-")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn round_trip_short_code() {
        let token = "deadbeef1234abcd";
        let short = encode_short_code(token);
        assert_eq!(short.len(), SHORT_CODE_LEN);
        assert!(short.chars().all(|c| CROCKFORD_ALPHABET.contains(&(c as u8))));
        let decoded = decode_short_code(&short).expect("decode");
        let expected = {
            let d = Sha256::digest(token.as_bytes());
            let mut bits: u64 = 0;
            for (i, byte) in d[..8].iter().enumerate() {
                bits |= (*byte as u64) << (56 - 8 * i);
            }
            bits >>= 4;
            bits <<= 4;
            let mut out = [0u8; 8];
            for (i, byte) in out.iter_mut().enumerate() {
                *byte = ((bits >> (56 - 8 * i)) & 0xFF) as u8;
            }
            out
        };
        assert_eq!(decoded, expected);
    }

    #[test]
    fn normalises_confusables() {
        let token = "abc123";
        let short = encode_short_code(token);
        // Replace a digit with a confusable letter and re-decode.
        let mangled: String = short
            .chars()
            .map(|c| if c == '0' { 'O' } else { c })
            .collect();
        let decoded = decode_short_code(&mangled);
        assert!(decoded.is_some(), "O should normalise back to 0");
    }

    #[test]
    fn format_renders_hyphens() {
        assert_eq!(format_short_code("J6K29P47NQXR"), "J6K2-9P47-NQXR");
    }

    #[test]
    fn rejects_bad_input() {
        assert!(decode_short_code("ZZZ").is_none(), "too short");
        assert!(decode_short_code("J6K29P47NQX!").is_none(), "bad char");
    }

    #[test]
    fn normalise_round_trips_short_code() {
        let token = "deadbeef1234abcd";
        let short = encode_short_code(token);
        // identity
        assert_eq!(normalize_short_code(&short).as_deref(), Some(short.as_str()));
        // lowercase in -> uppercase out
        let lower = short.to_lowercase();
        assert_eq!(normalize_short_code(&lower).as_deref(), Some(short.as_str()));
        // hyphenated form collapses back to canonical
        let hyphenated = format_short_code(&short);
        assert_eq!(normalize_short_code(&hyphenated).as_deref(), Some(short.as_str()));
        // Crockford confusables (I/L -> 1, O -> 0, U -> V)
        let mangled: String = short.chars().map(|c| match c {
            '0' => 'O',
            '1' => 'I',
            'V' => 'U',
            _ => c,
        }).collect();
        assert_eq!(normalize_short_code(&mangled).as_deref(), Some(short.as_str()));
    }

    #[test]
    fn normalise_rejects_garbage() {
        assert!(normalize_short_code("").is_none());
        assert!(normalize_short_code("ZZZ").is_none());
        assert!(normalize_short_code("J6K29P47NQX!").is_none());
        // 12 chars but outside Crockford alphabet
        assert!(normalize_short_code("!!!!!!!!!!!!").is_none());
    }
}
