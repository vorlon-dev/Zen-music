//! Network policy and the host calls exposed to extension scripts.

use base64::{engine::general_purpose::STANDARD, Engine};
use hmac::{Hmac, Mac};
use serde_json::{json, Map, Value};
use sha2::{Digest, Sha256};
use std::io::Read;
use std::net::{IpAddr, ToSocketAddrs};
use std::sync::atomic::{AtomicUsize, Ordering};
use std::time::Duration;

const MAX_RESPONSE: u64 = 2 * 1024 * 1024;
const MAX_REQUESTS: usize = 8;

pub struct Policy {
    hosts: Vec<String>,
}

impl Policy {
    pub fn new(hosts: Vec<String>) -> Self {
        Self {
            hosts: hosts.into_iter().map(|h| h.to_lowercase()).collect(),
        }
    }

    /// https only, declared hosts only, never a private/loopback address.
    pub fn check(&self, raw: &str) -> Result<url::Url, String> {
        let u = url::Url::parse(raw).map_err(|_| "invalid URL".to_string())?;
        if u.scheme() != "https" {
            return Err("only https URLs are allowed".into());
        }
        let host = u.host_str().ok_or("URL has no host")?.to_lowercase();
        if !self.hosts.iter().any(|h| host == *h || host.ends_with(&format!(".{h}"))) {
            return Err(format!("host {host} not declared by extension"));
        }
        let bare = host.trim_start_matches('[').trim_end_matches(']');
        if let Ok(ip) = bare.parse::<IpAddr>() {
            if private(&ip) {
                return Err("private addresses are blocked".into());
            }
        } else {
            if host == "localhost" || host.ends_with(".localhost") || host.ends_with(".local") {
                return Err("private addresses are blocked".into());
            }
            let port = u.port_or_known_default().unwrap_or(443);
            let addrs = (host.as_str(), port)
                .to_socket_addrs()
                .map_err(|e| format!("DNS failed: {e}"))?;
            for a in addrs {
                if private(&a.ip()) {
                    return Err("host resolves to a private address".into());
                }
            }
        }
        Ok(u)
    }
}

pub fn private(ip: &IpAddr) -> bool {
    match ip {
        IpAddr::V4(v) => {
            v.is_private()
                || v.is_loopback()
                || v.is_link_local()
                || v.is_unspecified()
                || v.is_broadcast()
                || v.is_multicast()
        }
        IpAddr::V6(v) => {
            if let Some(m) = v.to_ipv4_mapped() {
                return private(&IpAddr::V4(m));
            }
            v.is_loopback()
                || v.is_unspecified()
                || v.is_multicast()
                || (v.segments()[0] & 0xfe00) == 0xfc00 // fc00::/7
                || (v.segments()[0] & 0xffc0) == 0xfe80 // fe80::/10
        }
    }
}

/// Returns a JSON string: {status, body, headers} or {error}.
pub fn request(
    policy: &Policy,
    count: &AtomicUsize,
    method: &str,
    url: &str,
    headers_json: &str,
    body: &str,
) -> String {
    let result = (|| -> Result<Value, String> {
        if count.fetch_add(1, Ordering::SeqCst) >= MAX_REQUESTS {
            return Err("too many requests".into());
        }
        let method = method.to_uppercase();
        if !["GET", "POST", "PUT", "DELETE", "PATCH"].contains(&method.as_str()) {
            return Err("method not allowed".into());
        }
        let u = policy.check(url)?;
        let agent = ureq::AgentBuilder::new()
            .redirects(0) // a 30x could leave the approved hosts
            .timeout(Duration::from_secs(12))
            .user_agent("ZenMusic/1.0")
            .build();
        let mut rq = agent.request(&method, u.as_str());
        if let Ok(Value::Object(h)) = serde_json::from_str::<Value>(headers_json) {
            for (k, v) in h {
                let key = k.to_lowercase();
                if key == "cookie" || key == "host" {
                    continue; // the app stays in charge of identity
                }
                if let Some(s) = v.as_str() {
                    rq = rq.set(&k, s);
                }
            }
        }
        let sent = if body.is_empty() || method == "GET" || method == "DELETE" {
            rq.call()
        } else {
            rq.send_string(body)
        };
        let resp = match sent {
            Ok(r) => r,
            Err(ureq::Error::Status(_, r)) => r,
            Err(e) => return Err(format!("network error: {e}")),
        };
        let status = resp.status();
        let mut hdrs = Map::new();
        for name in resp.headers_names() {
            if let Some(v) = resp.header(&name) {
                hdrs.insert(name.to_lowercase(), Value::String(v.to_string()));
            }
        }
        let mut buf = Vec::new();
        resp.into_reader()
            .take(MAX_RESPONSE + 1)
            .read_to_end(&mut buf)
            .map_err(|e| format!("read error: {e}"))?;
        if buf.len() as u64 > MAX_RESPONSE {
            return Err("response too large".into());
        }
        Ok(json!({
            "status": status,
            "body": String::from_utf8_lossy(&buf),
            "headers": hdrs,
        }))
    })();
    match result {
        Ok(v) => v.to_string(),
        Err(e) => json!({ "error": e }).to_string(),
    }
}

/// Hash helpers for `utils.md5/sha256/hmacSHA256(/Base64)`.
pub fn calc(func: &str, a: &str, b: &str) -> String {
    match func {
        "md5" => format!("{:x}", md5::compute(a.as_bytes())),
        "sha256" => format!("{:x}", Sha256::digest(a.as_bytes())),
        "hmacSHA256" | "hmacSHA256Base64" => {
            let Ok(mut mac) = Hmac::<Sha256>::new_from_slice(b.as_bytes()) else {
                return String::new();
            };
            mac.update(a.as_bytes());
            let out = mac.finalize().into_bytes();
            if func == "hmacSHA256" {
                format!("{:x}", out)
            } else {
                STANDARD.encode(out)
            }
        }
        _ => String::new(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn policy_blocks_the_usual_suspects() {
        let p = Policy::new(vec!["example.com".into(), "127.0.0.1".into()]);
        assert!(p.check("http://example.com/x").is_err());
        assert!(p.check("https://evil.test/x").is_err());
        assert!(p.check("https://127.0.0.1/x").is_err());
        assert!(p.check("https://notexample.com/x").is_err());
    }

    #[test]
    fn hashes_match_known_vectors() {
        assert_eq!(calc("md5", "abc", ""), "900150983cd24fb0d6963f7d28e17f72");
        assert_eq!(
            calc("sha256", "abc", ""),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        );
        assert_eq!(
            calc("hmacSHA256", "The quick brown fox jumps over the lazy dog", "key"),
            "f7bc83f430538424b13298e6aa6fb143ef4d59a14946175997479dbc2d1a3cd8"
        );
    }
}
