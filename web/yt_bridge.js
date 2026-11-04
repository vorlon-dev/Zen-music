// ZenMusic · vorlon-dev
// Thin wrapper over the official YouTube IFrame Player API, used by the web
// player for YouTube Music tracks. Dart talks to it through `window.zenYT`.
(function () {
  var player = null;
  var ready = false;
  var queued = null; // video id waiting for the player to become ready
  var state = { s: -1, t: 0, d: 0, e: 0 };
  var volume = 100;
  var rate = 1;

  function host() {
    var el = document.getElementById('zen-yt-host');
    if (!el) {
      el = document.createElement('div');
      el.id = 'zen-yt-host';
      el.style.cssText =
        'position:fixed;right:0;bottom:0;width:2px;height:2px;opacity:0.01;pointer-events:none;overflow:hidden;';
      var inner = document.createElement('div');
      inner.id = 'zen-yt-player';
      el.appendChild(inner);
      document.body.appendChild(el);
    }
    return el;
  }

  function create() {
    host();
    player = new YT.Player('zen-yt-player', {
      width: '2',
      height: '2',
      playerVars: { playsinline: 1, controls: 0, disablekb: 1, rel: 0 },
      events: {
        onReady: function () {
          ready = true;
          player.setVolume(volume);
          if (queued) {
            var id = queued;
            queued = null;
            player.loadVideoById(id);
            player.setPlaybackRate(rate);
          }
        },
        onStateChange: function (e) {
          state.s = e.data;
        },
        onError: function (e) {
          state.e = e.data;
        },
      },
    });
  }

  function boot() {
    if (player) return;
    if (window.YT && window.YT.Player) {
      create();
      return;
    }
    window.onYouTubeIframeAPIReady = create;
    var s = document.createElement('script');
    s.src = 'https://www.youtube.com/iframe_api';
    document.head.appendChild(s);
  }

  window.zenYT = {
    load: function (id) {
      state = { s: -1, t: 0, d: 0, e: 0 };
      boot();
      if (ready) {
        player.loadVideoById(id);
        player.setPlaybackRate(rate);
      } else {
        queued = id;
      }
    },
    play: function () { if (ready) player.playVideo(); },
    pause: function () { if (ready) player.pauseVideo(); },
    stop: function () {
      queued = null;
      if (ready) player.stopVideo();
    },
    seek: function (sec) { if (ready) player.seekTo(sec, true); },
    setVolume: function (v) {
      volume = v;
      if (ready) player.setVolume(v);
    },
    setRate: function (r) {
      rate = r;
      if (ready) player.setPlaybackRate(r);
    },
    // JSON string: s = player state (0 ended, 1 playing, 2 paused, 3 buffering),
    // t = seconds played, d = duration, e = error code (0 = none).
    state: function () {
      if (ready) {
        try {
          state.t = player.getCurrentTime() || 0;
          state.d = player.getDuration() || 0;
        } catch (_) {}
      }
      return JSON.stringify(state);
    },
  };
})();
