// ZenMusic · offline romanizer (pure Dart, no Flutter imports).
// Hindi/Marathi (Devanagari), Bengali, Punjabi, Gujarati, Odia, Tamil, Telugu,
// Kannada, Malayalam, Japanese kana, Korean Hangul and Russian/Cyrillic.
// Kanji, Arabic and Chinese are left as they are (they need a dictionary).
// Output is a readable "Hinglish"-style spelling, not a scholarly transliteration.

class Romanizer {
  Romanizer._();

  /// True when [s] has any letter this romanizer can convert.
  static bool needs(String s) {
    for (final r in s.runes) {
      if (r < 0x250) continue;
      if (_indicBase(r) != null || _isKana(r) || _isHangul(r) || _isCyrillic(r)) {
        return true;
      }
    }
    return false;
  }

  static String romanize(String s) {
    final runes = s.runes.toList();
    final out = StringBuffer();
    var i = 0;
    while (i < runes.length) {
      final r = runes[i];
      if (r < 0x250) {
        out.writeCharCode(r);
        i++;
        continue;
      }
      final base = _indicBase(r);
      if (base != null) {
        var j = i;
        while (j < runes.length &&
            (_indicBase(runes[j]) == base || runes[j] == 0x200C || runes[j] == 0x200D)) {
          j++;
        }
        out.write(_indic(runes.sublist(i, j), base));
        i = j;
        continue;
      }
      if (_isKana(r)) {
        var j = i;
        while (j < runes.length && (_isKana(runes[j]) || runes[j] == 0x30FC)) {
          j++;
        }
        out.write(_kana(runes.sublist(i, j)));
        i = j;
        continue;
      }
      if (_isHangul(r)) {
        var j = i;
        while (j < runes.length && _isHangul(runes[j])) {
          j++;
        }
        out.write(_hangul(runes.sublist(i, j)));
        i = j;
        continue;
      }
      if (_isCyrillic(r)) {
        out.write(_cyr(r));
        i++;
        continue;
      }
      out.writeCharCode(r);
      i++;
    }
    return out.toString().replaceAll(RegExp(r' {2,}'), ' ').trim();
  }

  // ------------------------------------------------------------------ Indic
  static const _bases = <int>[0x900, 0x980, 0xA00, 0xA80, 0xB00, 0xB80, 0xC00, 0xC80, 0xD00];

  static int? _indicBase(int r) {
    if (r < 0x900 || r > 0xD7F) return null;
    final b = r & ~0x7F;
    return _bases.contains(b) ? b : null;
  }

  // consonants, offsets 0x15..0x39 (37 entries)
  static const _cons = <String>[
    'k', 'kh', 'g', 'gh', 'ng', 'ch', 'chh', 'j', 'jh', 'ny', //            15-1E
    't', 'th', 'd', 'dh', 'n', //                                             1F-23 retroflex
    't', 'th', 'd', 'dh', 'n', //                                             24-28 dental
    'n', 'p', 'ph', 'b', 'bh', 'm', //                                        29-2E
    'y', 'r', 'r', 'l', 'l', 'zh', 'v', 'sh', 'sh', 's', 'h', //              2F-39
  ];
  // independent vowels, offsets 0x05..0x14 (16 entries)
  static const _ivow = <String>[
    'a', 'aa', 'i', 'ee', 'u', 'oo', 'ri', 'li', 'e', 'e', 'e', 'ai', 'o', 'o', 'o', 'au',
  ];
  // vowel signs, offsets 0x3E..0x4C (15 entries)
  static const _svow = <String>[
    'aa', 'i', 'ee', 'u', 'oo', 'ri', 'ri', 'e', 'e', 'e', 'ai', 'o', 'o', 'o', 'au',
  ];
  // precomposed nukta letters 0x58..0x5F
  static const _nuktaPre = <String>['q', 'kh', 'gh', 'z', 'r', 'rh', 'f', 'y'];

  static bool _isCons(int o) => (o >= 0x15 && o <= 0x39) || (o >= 0x58 && o <= 0x5F);
  static bool _isVowSign(int o) => o >= 0x3E && o <= 0x4C;
  static bool _isIndVow(int o) => o >= 0x05 && o <= 0x14;

  static String _consRoman(int o, int base, bool first, bool nukta, String pending) {
    if (o >= 0x58) return _nuktaPre[o - 0x58];
    var c = _cons[o - 0x15];
    if (nukta) {
      switch (o) {
        case 0x15: return 'q';
        case 0x16: return 'kh';
        case 0x17: return 'gh';
        case 0x1C: return 'z';
        case 0x21: return 'r';
        case 0x22: return 'rh';
        case 0x2B: return 'f';
      }
    }
    if (base == 0xB80) {
      // Tamil: stops are voiced after a nasal and between vowels (handled later)
      final nasal = pending.endsWith('n') || pending.endsWith('m') || pending.endsWith('ng');
      if (nasal) {
        switch (o) {
          case 0x15: return 'g';
          case 0x1A: return 'j';
          case 0x1F: return 'd';
          case 0x24: return 'dh';
          case 0x2A: return 'b';
        }
      }
      if (o == 0x1A) c = first ? 'ch' : 's'; // ச
      if (o == 0x24 && first) c = 'th'; // word-initial த
    }
    return c;
  }

  static String _indic(List<int> run, int base) {
    // Devanagari-like scripts lose the final / medial schwa; the Dravidian ones keep it.
    final deleteSchwa = base == 0x900 || base == 0xA00 || base == 0xA80 || base == 0x980 || base == 0xB00;
    final medialDelete = base == 0x900 || base == 0xA00 || base == 0xA80;
    final inherentVowel = (base == 0x980 || base == 0xB00) ? 'o' : 'a';

    final syls = <_Syl>[];
    var pending = '';
    var i = 0;
    int off(int k) => run[k] - base;

    void addTail(String t) {
      if (syls.isEmpty) {
        syls.add(_Syl(t, null, false));
      } else {
        syls.last.tail += t;
      }
    }

    while (i < run.length) {
      final r = run[i];
      if (r == 0x200C || r == 0x200D) {
        i++;
        continue;
      }
      final o = r - base;
      // Malayalam chillu letters
      if (base == 0xD00 && o >= 0x7A && o <= 0x7F) {
        const ch = ['n', 'n', 'r', 'l', 'l', 'k'];
        syls.add(_Syl(pending + ch[o - 0x7A], '', false));
        pending = '';
        i++;
        continue;
      }
      if (_isCons(o)) {
        var j = i + 1;
        var nukta = false;
        if (o < 0x58 && j < run.length && off(j) == 0x3C) {
          nukta = true;
          j++;
        }
        final c = _consRoman(o, base, syls.isEmpty && pending.isEmpty, nukta, pending);
        while (j < run.length && (run[j] == 0x200C || run[j] == 0x200D)) {
          j++;
        }
        if (j < run.length && off(j) == 0x4D) {
          pending += c; // halant: joins the next consonant
          i = j + 1;
        } else if (j < run.length && _isVowSign(off(j))) {
          syls.add(_Syl(pending + c, _svow[off(j) - 0x3E], false, o, pending.isEmpty));
          pending = '';
          i = j + 1;
        } else {
          syls.add(_Syl(pending + c, null, true, o, pending.isEmpty));
          pending = '';
          i = j;
        }
        continue;
      }
      if (_isIndVow(o)) {
        syls.add(_Syl(pending, _ivow[o - 0x05], false));
        pending = '';
        i++;
        continue;
      }
      if (o == 0x01 || o == 0x02) {
        // chandrabindu / anusvara: m before p/b/m, otherwise n
        // before a consonant: m before p/b/m, else n. At the end of a word: m for the
        // Dravidian scripts (enikkam, ishtam), n for the northern ones.
        var m = 'n';
        if (i + 1 >= run.length) {
          if (base == 0xB80 || base == 0xC00 || base == 0xC80 || base == 0xD00) m = 'm';
        } else {
          final n = off(i + 1);
          if (n == 0x2A || n == 0x2B || n == 0x2C || n == 0x2D || n == 0x2E) m = 'm';
        }
        addTail(m);
        i++;
        continue;
      }
      if (o == 0x03) {
        addTail('h');
        i++;
        continue;
      }
      if (o == 0x64 || o == 0x65) {
        i++; // danda
        continue;
      }
      if (o == 0x4D || o == 0x3C || o == 0x3D) {
        i++; // stray virama / nukta / avagraha
        continue;
      }
      i++; // anything else in the block (digits etc.) is dropped
    }
    if (pending.isNotEmpty) syls.add(_Syl(pending, '', false)); // trailing halant (Tamil pulli)

    // schwa deletion
    final n = syls.length;
    if (deleteSchwa && n > 1 && syls.last.inherent && syls.last.vow == null) {
      syls.last.dropped = true;
    }
    if (medialDelete) {
      bool hasV(int k) => !syls[k].noVowel && (!syls[k].inherent || !syls[k].dropped);
      for (var k = n - 2; k >= 1; k--) {
        if (syls[k].inherent && hasV(k - 1) && syls[k - 1].tail.isEmpty && k + 1 < n && hasV(k + 1)) {
          syls[k].dropped = true;
        }
      }
    }
    if (base == 0xB80) {
      const voiced = <int, String>{0x15: 'g', 0x1F: 'd', 0x24: 'dh', 0x2A: 'b'};
      for (var k = 1; k < n; k++) {
        final s = syls[k], p = syls[k - 1];
        final v = voiced[s.lastOff];
        final prevVowel = p.tail.isEmpty && (p.inherent || (p.vow != null && p.vow != ''));
        if (v != null && s.single && prevVowel) s.cons = v;
      }
    }
    final north = base == 0x900 || base == 0x980 || base == 0xA00 || base == 0xA80 || base == 0xB00;
    if (north && n > 0) {
      // Hinglish habit: a long vowel at the end of a word is written short (karta, mera, teri, hi)
      final l = syls.last;
      if (l.tail.isEmpty && l.vow != null && !(n == 1 && l.cons.isEmpty)) {
        if (l.vow == 'aa') l.vow = 'a';
        if (l.vow == 'ee') l.vow = 'i';
        if (l.vow == 'oo') l.vow = 'u';
      }
    }
    final sb = StringBuffer();
    for (final s in syls) {
      sb.write(s.cons);
      if (s.inherent) {
        if (!s.dropped) sb.write(inherentVowel);
      } else {
        sb.write(s.vow ?? '');
      }
      sb.write(s.tail);
    }
    var res = sb.toString();
    if (base == 0x900) res = res.replaceAll('jny', 'gy');
    return res;
  }

  // ------------------------------------------------------------------ Kana
  static bool _isKana(int r) =>
      (r >= 0x3041 && r <= 0x3096) || (r >= 0x30A1 && r <= 0x30FA) || r == 0x30FC;

  static const _kanaBase = <String, String>{
    'あ': 'a', 'い': 'i', 'う': 'u', 'え': 'e', 'お': 'o',
    'か': 'ka', 'き': 'ki', 'く': 'ku', 'け': 'ke', 'こ': 'ko',
    'が': 'ga', 'ぎ': 'gi', 'ぐ': 'gu', 'げ': 'ge', 'ご': 'go',
    'さ': 'sa', 'し': 'shi', 'す': 'su', 'せ': 'se', 'そ': 'so',
    'ざ': 'za', 'じ': 'ji', 'ず': 'zu', 'ぜ': 'ze', 'ぞ': 'zo',
    'た': 'ta', 'ち': 'chi', 'つ': 'tsu', 'て': 'te', 'と': 'to',
    'だ': 'da', 'ぢ': 'ji', 'づ': 'zu', 'で': 'de', 'ど': 'do',
    'な': 'na', 'に': 'ni', 'ぬ': 'nu', 'ね': 'ne', 'の': 'no',
    'は': 'ha', 'ひ': 'hi', 'ふ': 'fu', 'へ': 'he', 'ほ': 'ho',
    'ば': 'ba', 'び': 'bi', 'ぶ': 'bu', 'べ': 'be', 'ぼ': 'bo',
    'ぱ': 'pa', 'ぴ': 'pi', 'ぷ': 'pu', 'ぺ': 'pe', 'ぽ': 'po',
    'ま': 'ma', 'み': 'mi', 'む': 'mu', 'め': 'me', 'も': 'mo',
    'や': 'ya', 'ゆ': 'yu', 'よ': 'yo',
    'ら': 'ra', 'り': 'ri', 'る': 'ru', 'れ': 're', 'ろ': 'ro',
    'わ': 'wa', 'ゐ': 'i', 'ゑ': 'e', 'を': 'o', 'ん': 'n', 'ゔ': 'vu',
  };
  static const _kanaSmall = <String, String>{
    'ゃ': 'ya', 'ゅ': 'yu', 'ょ': 'yo',
    'ぁ': 'a', 'ぃ': 'i', 'ぅ': 'u', 'ぇ': 'e', 'ぉ': 'o',
  };

  static String _toHira(int r) =>
      String.fromCharCode((r >= 0x30A1 && r <= 0x30F6) ? r - 0x60 : r);

  static String _kana(List<int> run) {
    final sb = StringBuffer();
    var geminate = false;
    for (var i = 0; i < run.length; i++) {
      final r = run[i];
      if (r == 0x30FC) {
        // long vowel mark: repeat the last vowel
        final s = sb.toString();
        if (s.isNotEmpty && 'aeiou'.contains(s[s.length - 1])) sb.write(s[s.length - 1]);
        continue;
      }
      final h = _toHira(r);
      if (h == 'っ') {
        geminate = true;
        continue;
      }
      var syl = _kanaBase[h];
      if (syl == null) {
        sb.write(h);
        continue;
      }
      // contracted sounds: きゃ → kya, しゃ → sha, ちゅ → chu ...
      if (i + 1 < run.length) {
        final nx = _kanaSmall[_toHira(run[i + 1])];
        if (nx != null && 'yaeiou'.contains(nx[0]) && h != 'う' && h != 'い' && h != 'あ' && h != 'え' && h != 'お') {
          if (nx[0] == 'y') {
            var c = syl.substring(0, syl.length - 1);
            if (c == 'sh' || c == 'ch' || c == 'j') {
              syl = c + nx.substring(1);
            } else {
              syl = c + nx;
            }
            i++;
          }
        }
      }
      if (geminate) {
        sb.write(syl[0] == 'c' ? 't' : syl[0]);
        geminate = false;
      }
      sb.write(syl);
    }
    return sb.toString();
  }

  // ---------------------------------------------------------------- Hangul
  static bool _isHangul(int r) => r >= 0xAC00 && r <= 0xD7A3;
  static const _hl = <String>['g', 'kk', 'n', 'd', 'tt', 'r', 'm', 'b', 'pp', 's', 'ss', '', 'j', 'jj', 'ch', 'k', 't', 'p', 'h'];
  static const _hv = <String>['a', 'ae', 'ya', 'yae', 'eo', 'e', 'yeo', 'ye', 'o', 'wa', 'wae', 'oe', 'yo', 'u', 'wo', 'we', 'wi', 'yu', 'eu', 'ui', 'i'];
  static const _ht = <String>['', 'k', 'k', 'k', 'n', 'n', 'n', 't', 'l', 'k', 'm', 'l', 'l', 'l', 'p', 'l', 'm', 'p', 'p', 't', 't', 'ng', 't', 't', 'k', 't', 'p', 't'];

  static String _hangul(List<int> run) {
    final sb = StringBuffer();
    for (final r in run) {
      final x = r - 0xAC00;
      sb.write(_hl[x ~/ 588]);
      sb.write(_hv[(x % 588) ~/ 28]);
      sb.write(_ht[x % 28]);
    }
    return sb.toString();
  }

  // -------------------------------------------------------------- Cyrillic
  static bool _isCyrillic(int r) => r >= 0x400 && r <= 0x45F;
  static const _cy = <String, String>{
    'а': 'a', 'б': 'b', 'в': 'v', 'г': 'g', 'д': 'd', 'е': 'e', 'ё': 'yo', 'ж': 'zh', 'з': 'z',
    'и': 'i', 'й': 'y', 'к': 'k', 'л': 'l', 'м': 'm', 'н': 'n', 'о': 'o', 'п': 'p', 'р': 'r',
    'с': 's', 'т': 't', 'у': 'u', 'ф': 'f', 'х': 'kh', 'ц': 'ts', 'ч': 'ch', 'ш': 'sh',
    'щ': 'shch', 'ъ': '', 'ы': 'y', 'ь': '', 'э': 'e', 'ю': 'yu', 'я': 'ya',
    'є': 'ye', 'і': 'i', 'ї': 'yi', 'ґ': 'g',
  };

  static String _cyr(int r) {
    final ch = String.fromCharCode(r);
    final lower = ch.toLowerCase();
    final m = _cy[lower];
    if (m == null) return ch;
    if (lower == ch || m.isEmpty) return m;
    return m[0].toUpperCase() + m.substring(1);
  }
}

class _Syl {
  _Syl(this.cons, this.vow, this.inherent, [this.lastOff = 0, this.single = true]);
  String cons;
  String? vow; // explicit vowel ('' = no vowel at all)
  final bool inherent;
  final int lastOff; // offset of the last consonant (for Tamil voicing)
  final bool single; // a lone consonant, not a cluster
  String tail = '';
  bool dropped = false;
  bool get noVowel => vow == '';
}
