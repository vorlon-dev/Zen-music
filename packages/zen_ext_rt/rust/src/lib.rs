//! Native runtime for ZenMusic extensions: QuickJS plus a real, synchronous
//! host API (fetch/http/storage/utils), so Mornye-style packages run without
//! the Dart-side replay workaround.
//!
//! C ABI (called from Dart through dart:ffi):
//!   char* zen_ext_run(const char* request_json)   -> response_json
//!   void  zen_ext_free(char* ptr)
//!
//! request  = { source, method, args:[..], hosts:[..], store:{k:"json"} }
//! response = { ok: <any>, store:{..} }  or  { err: "message", store:{..} }

mod net;
mod run;

use std::ffi::{CStr, CString};
use std::os::raw::c_char;

/// # Safety
/// `req` must be a valid NUL-terminated UTF-8 string.
#[no_mangle]
pub unsafe extern "C" fn zen_ext_run(req: *const c_char) -> *mut c_char {
    let text = if req.is_null() {
        String::new()
    } else {
        CStr::from_ptr(req).to_string_lossy().into_owned()
    };
    let out = std::panic::catch_unwind(|| run::handle(&text))
        .unwrap_or_else(|_| r#"{"err":"native runtime panicked"}"#.to_string());
    CString::new(out)
        .unwrap_or_else(|_| CString::new(r#"{"err":"bad response"}"#).unwrap())
        .into_raw()
}

/// # Safety
/// `ptr` must come from `zen_ext_run` and be freed exactly once.
#[no_mangle]
pub unsafe extern "C" fn zen_ext_free(ptr: *mut c_char) {
    if !ptr.is_null() {
        drop(CString::from_raw(ptr));
    }
}
