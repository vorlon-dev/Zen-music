//! One extension call: fresh QuickJS runtime, prelude, script, method.

use crate::net::{self, Policy};
use rquickjs::{CaughtError, Context, Function, Runtime};
use serde::Deserialize;
use serde_json::{json, Value};
use std::sync::atomic::AtomicUsize;
use std::sync::Arc;
use std::time::{Duration, Instant};

const PRELUDE: &str = include_str!("prelude.js");
const CALL_LIMIT: Duration = Duration::from_secs(20);

#[derive(Deserialize)]
struct Request {
    source: String,
    method: String,
    #[serde(default)]
    args: Vec<Value>,
    #[serde(default)]
    hosts: Vec<String>,
    #[serde(default)]
    store: serde_json::Map<String, Value>,
}

pub fn handle(text: &str) -> String {
    match serde_json::from_str::<Request>(text) {
        Ok(req) => match run(req) {
            Ok(v) => v.to_string(),
            Err(e) => json!({ "err": e }).to_string(),
        },
        Err(e) => json!({ "err": format!("bad request: {e}") }).to_string(),
    }
}

fn es<E: std::fmt::Display>(e: E) -> String {
    e.to_string()
}

fn run(req: Request) -> Result<Value, String> {
    let rt = Runtime::new().map_err(es)?;
    rt.set_memory_limit(64 * 1024 * 1024);
    rt.set_max_stack_size(512 * 1024);
    let started = Instant::now();
    rt.set_interrupt_handler(Some(Box::new(move || started.elapsed() > CALL_LIMIT)));
    let ctx = Context::full(&rt).map_err(es)?;

    let policy = Arc::new(Policy::new(req.hosts));
    let count = Arc::new(AtomicUsize::new(0));
    let store_json = Value::Object(req.store).to_string();
    let args_json = Value::Array(req.args).to_string();

    ctx.with(|ctx| -> Result<(), String> {
        let caught = |e: rquickjs::Error| CaughtError::from_error(&ctx, e).to_string();
        let g = ctx.globals();
        let p = policy.clone();
        let c = count.clone();
        g.set(
            "__net",
            Function::new(
                ctx.clone(),
                move |m: String, u: String, h: String, b: String| -> String {
                    net::request(&p, &c, &m, &u, &h, &b)
                },
            )
            .map_err(caught)?,
        )
        .map_err(caught)?;
        g.set(
            "__calc",
            Function::new(ctx.clone(), |f: String, a: String, b: String| -> String {
                net::calc(&f, &a, &b)
            })
            .map_err(caught)?,
        )
        .map_err(caught)?;
        g.set("__storeJson", store_json).map_err(caught)?;
        g.set("__argsJson", args_json).map_err(caught)?;
        g.set("__method", req.method).map_err(caught)?;
        ctx.eval::<(), _>("globalThis.__store = JSON.parse(__storeJson);")
            .map_err(caught)?;
        ctx.eval::<(), _>(PRELUDE).map_err(caught)?;
        ctx.eval::<(), _>(req.source.as_str())
            .map_err(|e| format!("load: {}", caught(e)))?;
        ctx.eval::<(), _>(
            r#"
(function () {
  function fin(res) { res.store = __store; globalThis.__out = JSON.stringify(res); }
  Promise.resolve().then(function () {
    var ex = globalThis.extension;
    if (!ex) throw new Error('registerExtension() was not called');
    if (typeof ex.initialize === 'function') ex.initialize({});
    if (typeof ex[__method] !== 'function') throw new Error(__method + ' is not implemented');
    return ex[__method].apply(ex, JSON.parse(__argsJson));
  }).then(
    function (v) { fin({ ok: v === undefined ? null : v }); },
    function (e) { fin({ err: String(e && e.message || e) }); }
  );
})();
"#,
        )
        .map_err(caught)?;
        Ok(())
    })?;

    // Drain promise jobs (async extensions); the interrupt handler bounds time.
    while rt.is_job_pending() {
        if rt.execute_pending_job().is_err() {
            break;
        }
    }

    let out: String = ctx.with(|ctx| -> Result<String, String> {
        ctx.eval::<Option<String>, _>("globalThis.__out")
            .map_err(|e| CaughtError::from_error(&ctx, e).to_string())?
            .ok_or_else(|| "extension did not finish (timed out or never resolved)".to_string())
    })?;
    serde_json::from_str(&out).map_err(es)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn call(source: &str, method: &str, args: Value) -> Value {
        let req = json!({ "source": source, "method": method, "args": args, "hosts": ["example.com"] });
        serde_json::from_str(&handle(&req.to_string())).unwrap()
    }

    #[test]
    fn runs_a_sync_lyrics_extension_with_utils_and_storage() {
        let src = r#"
registerExtension({
  fetchLyrics: function (track, artist, album, dur) {
    storage.set('seen', (storage.get('seen', 0)) + 1);
    return { syncType: 'UNSYNCED', plainLyrics: track + '|' + artist + '|' + utils.md5('abc') };
  }
});"#;
        let r = call(src, "fetchLyrics", json!(["T", "A", "", 100]));
        assert_eq!(r["ok"]["plainLyrics"], "T|A|900150983cd24fb0d6963f7d28e17f72");
        assert_eq!(r["store"]["s:seen"], "1");
    }

    #[test]
    fn async_extensions_resolve() {
        let src = "registerExtension({ getTrack: async function (x) { return { id: x }; } });";
        assert_eq!(call(src, "getTrack", json!(["7"]))["ok"]["id"], "7");
    }

    #[test]
    fn undeclared_hosts_are_refused_inside_the_sandbox() {
        let src = r#"
registerExtension({ fetchLyrics: function () {
  var r = fetch('https://evil.test/x');
  return { plainLyrics: String(r.error) };
}});"#;
        let r = call(src, "fetchLyrics", json!([]));
        assert!(r["ok"]["plainLyrics"].as_str().unwrap().contains("not declared"));
    }

    #[test]
    fn errors_and_missing_methods_are_reported() {
        assert!(call("registerExtension({});", "fetchLyrics", json!([]))["err"]
            .as_str()
            .unwrap()
            .contains("not implemented"));
        assert!(call("throw new Error('boom');", "x", json!([]))["err"]
            .as_str()
            .unwrap()
            .contains("boom"));
    }
}
