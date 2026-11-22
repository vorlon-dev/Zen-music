(function () {
  function hdrs(h) {
    var o = {};
    if (h && typeof h === 'object') for (var k in h) o[k] = String(h[k]);
    return o;
  }
  function bodyOf(b) {
    if (b === undefined || b === null) return '';
    if (typeof b === 'string') return b;
    try { return JSON.stringify(b); } catch (_) { return String(b); }
  }
  function wrap(r, isFetch) {
    if (r.error !== undefined) {
      return isFetch
        ? { ok: false, status: 0, statusText: 'Network Error', error: r.error,
            text: function () { return ''; }, json: function () { return undefined; } }
        : { error: r.error };
    }
    return {
      ok: r.status >= 200 && r.status < 300, status: r.status, statusText: '',
      body: r.body, headers: r.headers || {},
      text: function () { return r.body; },
      json: function () { try { return JSON.parse(r.body); } catch (_) { return undefined; } }
    };
  }
  function net(method, url, headers, body, isFetch) {
    return wrap(JSON.parse(__net(method, String(url), JSON.stringify(hdrs(headers)), bodyOf(body))), isFetch);
  }
  globalThis.fetch = function (url, o) {
    o = o || {};
    return net(String(o.method || 'GET').toUpperCase(), url, o.headers, o.body, true);
  };
  globalThis.http = {
    get: function (u, h) { return net('GET', u, h, '', false); },
    delete: function (u, h) { return net('DELETE', u, h, '', false); },
    post: function (u, b, h) { return net('POST', u, h, b, false); },
    put: function (u, b, h) { return net('PUT', u, h, b, false); },
    patch: function (u, b, h) { return net('PATCH', u, h, b, false); },
    request: function (u, o) { o = o || {}; return net(String(o.method || 'GET').toUpperCase(), u, o.headers, o.body, false); },
    clearCookies: function () {}
  };
  function store(prefix) {
    return {
      get: function (k, fb) { var v = __store[prefix + String(k)]; return v === undefined ? fb : JSON.parse(v); },
      set: function (k, v) { __store[prefix + String(k)] = JSON.stringify(v); return true; },
      store: function (k, v) { __store[prefix + String(k)] = JSON.stringify(v); return { success: true }; },
      remove: function (k) { delete __store[prefix + String(k)]; return true; }
    };
  }
  var st = store('s:'), cr = store('c:');
  globalThis.storage = { get: st.get, set: st.set, remove: st.remove };
  globalThis.credentials = { get: cr.get, store: cr.store, remove: cr.remove };
  var nop = function () {};
  globalThis.log = { debug: nop, info: nop, warn: nop, error: nop };
  globalThis.console = { log: nop, info: nop, warn: nop, error: nop, debug: nop };
  var B = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  globalThis.btoa = function (s) {
    s = String(s); var o = '';
    for (var i = 0; i < s.length; i += 3) {
      var a = s.charCodeAt(i), b = s.charCodeAt(i + 1), c = s.charCodeAt(i + 2);
      o += B[a >> 2] + B[((a & 3) << 4) | ((b || 0) >> 4)] +
        (i + 1 < s.length ? B[((b & 15) << 2) | ((c || 0) >> 6)] : '=') +
        (i + 2 < s.length ? B[c & 63] : '=');
    }
    return o;
  };
  globalThis.atob = function (s) {
    s = String(s).replace(/=+$/, ''); var o = '', bits = 0, n = 0;
    for (var i = 0; i < s.length; i++) {
      var v = B.indexOf(s[i]); if (v < 0) continue;
      bits = (bits << 6) | v; n += 6;
      if (n >= 8) { n -= 8; o += String.fromCharCode((bits >> n) & 255); }
    }
    return o;
  };
  function utf8(s) { return unescape(encodeURIComponent(String(s))); }
  function calc(fn) {
    return function (a, b) { return __calc(fn, String(a === undefined ? '' : a), String(b === undefined ? '' : b)); };
  }
  globalThis.utils = {
    isDownloadCancelled: function () { return false; },
    isRequestCancelled: function () { return false; },
    randomUserAgent: function () { return 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Chrome/120 Mobile Safari/537.36'; },
    appVersion: function () { return '1.0'; },
    appUserAgent: function () { return 'ZenMusic/1.0'; },
    getResolutionRemainingMs: function () { return 20000; },
    base64Encode: function (v) { return btoa(utf8(v)); },
    base64Decode: function (v) { try { return decodeURIComponent(escape(atob(v))); } catch (_) { return atob(v); } },
    md5: calc('md5'), sha256: calc('sha256'),
    hmacSHA256: calc('hmacSHA256'), hmacSHA256Base64: calc('hmacSHA256Base64'),
    parseJSON: function (v) { try { return JSON.parse(String(v)); } catch (_) { return undefined; } },
    stringifyJSON: function (v) { try { return JSON.stringify(v); } catch (_) { return ''; } },
    sleep: function () { return true; }
  };
  globalThis.URLSearchParams = function (init) {
    var list = [], self = this;
    if (typeof init === 'string') {
      init.replace(/^\?/, '').split('&').forEach(function (p) {
        if (!p) return; var kv = p.split('=');
        list.push([decodeURIComponent(kv[0].replace(/\+/g, ' ')), decodeURIComponent((kv[1] || '').replace(/\+/g, ' '))]);
      });
    } else if (init && typeof init === 'object') {
      for (var k in init) list.push([k, String(init[k])]);
    }
    self.append = function (k, v) { list.push([String(k), String(v)]); };
    self.set = function (k, v) { self['delete'](k); self.append(k, v); };
    self['delete'] = function (k) { list = list.filter(function (e) { return e[0] !== String(k); }); };
    self.get = function (k) { for (var i = 0; i < list.length; i++) if (list[i][0] === String(k)) return list[i][1]; return null; };
    self.has = function (k) { return self.get(k) !== null; };
    self.toString = function () {
      return list.map(function (e) { return encodeURIComponent(e[0]) + '=' + encodeURIComponent(e[1]); }).join('&');
    };
  };
  globalThis.registerExtension = function (v) { if (arguments.length) globalThis.extension = v; };
})();
