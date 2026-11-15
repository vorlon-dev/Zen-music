// ZenMusic · vorlon-dev
//
// SP71 — Blowfish for the Deezer mirror probe (Kotlin port of
// lib/desktop/lossless/blowfish.dart). The Deezer CDN encrypts every third
// 2048-byte block with Blowfish-CBC (fixed IV 00 01 02 03 04 05 06 07, key
// handed over by the mirror as raw ASCII bytes). The Kotlin engine uses it
// for the pre-serve STREAMINFO duration probe only — serving stays on the
// Dart loopback, which has its own already-verified Dart implementation.
//
// Algorithm identical to the Dart file: pi-derived subkey tables
// (identical to OpenSSL's crypto/bf/bf_pi.h), Schneier's key schedule and
// the 16-round Feistel network. Tables below are GENERATED from
// blowfish.dart by scripts/gen_blowfish_kt.py; the cipher was validated
// against the published vectors (FEDCBA9876543210 / 0123456789ABCDEF ->
// 0ACEAB0FC6A0A28D and 7CA110454A1A6E57 / 01A1D6D039776742 ->
// 59C68245EB05282B) and against pycryptodome CBC.

package com.zen.music.zenmusic.mirror

// SP71: generated from lib/desktop/lossless/blowfish.dart (_pInit/_sInit)
// by scripts/gen_blowfish_kt.py — do not edit by hand.
private val BF_P = intArrayOf(
    0x243f6a88, 0x85a308d3.toInt(), 0x13198a2e, 0x03707344, 0xa4093822.toInt(), 0x299f31d0,
    0x082efa98, 0xec4e6c89.toInt(), 0x452821e6, 0x38d01377, 0xbe5466cf.toInt(), 0x34e90c6c,
    0xc0ac29b7.toInt(), 0xc97c50dd.toInt(), 0x3f84d5b5, 0xb5470917.toInt(), 0x9216d5d9.toInt(), 0x8979fb1b.toInt(),
)

private val BF_S = intArrayOf(
    0xd1310ba6.toInt(), 0x98dfb5ac.toInt(), 0x2ffd72db, 0xd01adfb7.toInt(), 0xb8e1afed.toInt(), 0x6a267e96, 0xba7c9045.toInt(), 0xf12c7f99.toInt(),
    0x24a19947, 0xb3916cf7.toInt(), 0x0801f2e2, 0x858efc16.toInt(), 0x636920d8, 0x71574e69, 0xa458fea3.toInt(), 0xf4933d7e.toInt(),
    0x0d95748f, 0x728eb658, 0x718bcd58, 0x82154aee.toInt(), 0x7b54a41d, 0xc25a59b5.toInt(), 0x9c30d539.toInt(), 0x2af26013,
    0xc5d1b023.toInt(), 0x286085f0, 0xca417918.toInt(), 0xb8db38ef.toInt(), 0x8e79dcb0.toInt(), 0x603a180e, 0x6c9e0e8b, 0xb01e8a3e.toInt(),
    0xd71577c1.toInt(), 0xbd314b27.toInt(), 0x78af2fda, 0x55605c60, 0xe65525f3.toInt(), 0xaa55ab94.toInt(), 0x57489862, 0x63e81440,
    0x55ca396a, 0x2aab10b6, 0xb4cc5c34.toInt(), 0x1141e8ce, 0xa15486af.toInt(), 0x7c72e993, 0xb3ee1411.toInt(), 0x636fbc2a,
    0x2ba9c55d, 0x741831f6, 0xce5c3e16.toInt(), 0x9b87931e.toInt(), 0xafd6ba33.toInt(), 0x6c24cf5c, 0x7a325381, 0x28958677,
    0x3b8f4898, 0x6b4bb9af, 0xc4bfe81b.toInt(), 0x66282193, 0x61d809cc, 0xfb21a991.toInt(), 0x487cac60, 0x5dec8032,
    0xef845d5d.toInt(), 0xe98575b1.toInt(), 0xdc262302.toInt(), 0xeb651b88.toInt(), 0x23893e81, 0xd396acc5.toInt(), 0x0f6d6ff3, 0x83f44239.toInt(),
    0x2e0b4482, 0xa4842004.toInt(), 0x69c8f04a, 0x9e1f9b5e.toInt(), 0x21c66842, 0xf6e96c9a.toInt(), 0x670c9c61, 0xabd388f0.toInt(),
    0x6a51a0d2, 0xd8542f68.toInt(), 0x960fa728.toInt(), 0xab5133a3.toInt(), 0x6eef0b6c, 0x137a3be4, 0xba3bf050.toInt(), 0x7efb2a98,
    0xa1f1651d.toInt(), 0x39af0176, 0x66ca593e, 0x82430e88.toInt(), 0x8cee8619.toInt(), 0x456f9fb4, 0x7d84a5c3, 0x3b8b5ebe,
    0xe06f75d8.toInt(), 0x85c12073.toInt(), 0x401a449f, 0x56c16aa6, 0x4ed3aa62, 0x363f7706, 0x1bfedf72, 0x429b023d,
    0x37d0d724, 0xd00a1248.toInt(), 0xdb0fead3.toInt(), 0x49f1c09b, 0x075372c9, 0x80991b7b.toInt(), 0x25d479d8, 0xf6e8def7.toInt(),
    0xe3fe501a.toInt(), 0xb6794c3b.toInt(), 0x976ce0bd.toInt(), 0x04c006ba, 0xc1a94fb6.toInt(), 0x409f60c4, 0x5e5c9ec2, 0x196a2463,
    0x68fb6faf, 0x3e6c53b5, 0x1339b2eb, 0x3b52ec6f, 0x6dfc511f, 0x9b30952c.toInt(), 0xcc814544.toInt(), 0xaf5ebd09.toInt(),
    0xbee3d004.toInt(), 0xde334afd.toInt(), 0x660f2807, 0x192e4bb3, 0xc0cba857.toInt(), 0x45c8740f, 0xd20b5f39.toInt(), 0xb9d3fbdb.toInt(),
    0x5579c0bd, 0x1a60320a, 0xd6a100c6.toInt(), 0x402c7279, 0x679f25fe, 0xfb1fa3cc.toInt(), 0x8ea5e9f8.toInt(), 0xdb3222f8.toInt(),
    0x3c7516df, 0xfd616b15.toInt(), 0x2f501ec8, 0xad0552ab.toInt(), 0x323db5fa, 0xfd238760.toInt(), 0x53317b48, 0x3e00df82,
    0x9e5c57bb.toInt(), 0xca6f8ca0.toInt(), 0x1a87562e, 0xdf1769db.toInt(), 0xd542a8f6.toInt(), 0x287effc3, 0xac6732c6.toInt(), 0x8c4f5573.toInt(),
    0x695b27b0, 0xbbca58c8.toInt(), 0xe1ffa35d.toInt(), 0xb8f011a0.toInt(), 0x10fa3d98, 0xfd2183b8.toInt(), 0x4afcb56c, 0x2dd1d35b,
    0x9a53e479.toInt(), 0xb6f84565.toInt(), 0xd28e49bc.toInt(), 0x4bfb9790, 0xe1ddf2da.toInt(), 0xa4cb7e33.toInt(), 0x62fb1341, 0xcee4c6e8.toInt(),
    0xef20cada.toInt(), 0x36774c01, 0xd07e9efe.toInt(), 0x2bf11fb4, 0x95dbda4d.toInt(), 0xae909198.toInt(), 0xeaad8e71.toInt(), 0x6b93d5a0,
    0xd08ed1d0.toInt(), 0xafc725e0.toInt(), 0x8e3c5b2f.toInt(), 0x8e7594b7.toInt(), 0x8ff6e2fb.toInt(), 0xf2122b64.toInt(), 0x8888b812.toInt(), 0x900df01c.toInt(),
    0x4fad5ea0, 0x688fc31c, 0xd1cff191.toInt(), 0xb3a8c1ad.toInt(), 0x2f2f2218, 0xbe0e1777.toInt(), 0xea752dfe.toInt(), 0x8b021fa1.toInt(),
    0xe5a0cc0f.toInt(), 0xb56f74e8.toInt(), 0x18acf3d6, 0xce89e299.toInt(), 0xb4a84fe0.toInt(), 0xfd13e0b7.toInt(), 0x7cc43b81, 0xd2ada8d9.toInt(),
    0x165fa266, 0x80957705.toInt(), 0x93cc7314.toInt(), 0x211a1477, 0xe6ad2065.toInt(), 0x77b5fa86, 0xc75442f5.toInt(), 0xfb9d35cf.toInt(),
    0xebcdaf0c.toInt(), 0x7b3e89a0, 0xd6411bd3.toInt(), 0xae1e7e49.toInt(), 0x00250e2d, 0x2071b35e, 0x226800bb, 0x57b8e0af,
    0x2464369b, 0xf009b91e.toInt(), 0x5563911d, 0x59dfa6aa, 0x78c14389, 0xd95a537f.toInt(), 0x207d5ba2, 0x02e5b9c5,
    0x83260376.toInt(), 0x6295cfa9, 0x11c81968, 0x4e734a41, 0xb3472dca.toInt(), 0x7b14a94a, 0x1b510052, 0x9a532915.toInt(),
    0xd60f573f.toInt(), 0xbc9bc6e4.toInt(), 0x2b60a476, 0x81e67400.toInt(), 0x08ba6fb5, 0x571be91f, 0xf296ec6b.toInt(), 0x2a0dd915,
    0xb6636521.toInt(), 0xe7b9f9b6.toInt(), 0xff34052e.toInt(), 0xc5855664.toInt(), 0x53b02d5d, 0xa99f8fa1.toInt(), 0x08ba4799, 0x6e85076a,
    0x4b7a70e9, 0xb5b32944.toInt(), 0xdb75092e.toInt(), 0xc4192623.toInt(), 0xad6ea6b0.toInt(), 0x49a7df7d, 0x9cee60b8.toInt(), 0x8fedb266.toInt(),
    0xecaa8c71.toInt(), 0x699a17ff, 0x5664526c, 0xc2b19ee1.toInt(), 0x193602a5, 0x75094c29, 0xa0591340.toInt(), 0xe4183a3e.toInt(),
    0x3f54989a, 0x5b429d65, 0x6b8fe4d6, 0x99f73fd6.toInt(), 0xa1d29c07.toInt(), 0xefe830f5.toInt(), 0x4d2d38e6, 0xf0255dc1.toInt(),
    0x4cdd2086, 0x8470eb26.toInt(), 0x6382e9c6, 0x021ecc5e, 0x09686b3f, 0x3ebaefc9, 0x3c971814, 0x6b6a70a1,
    0x687f3584, 0x52a0e286, 0xb79c5305.toInt(), 0xaa500737.toInt(), 0x3e07841c, 0x7fdeae5c, 0x8e7d44ec.toInt(), 0x5716f2b8,
    0xb03ada37.toInt(), 0xf0500c0d.toInt(), 0xf01c1f04.toInt(), 0x0200b3ff, 0xae0cf51a.toInt(), 0x3cb574b2, 0x25837a58, 0xdc0921bd.toInt(),
    0xd19113f9.toInt(), 0x7ca92ff6, 0x94324773.toInt(), 0x22f54701, 0x3ae5e581, 0x37c2dadc, 0xc8b57634.toInt(), 0x9af3dda7.toInt(),
    0xa9446146.toInt(), 0x0fd0030e, 0xecc8c73e.toInt(), 0xa4751e41.toInt(), 0xe238cd99.toInt(), 0x3bea0e2f, 0x3280bba1, 0x183eb331,
    0x4e548b38, 0x4f6db908, 0x6f420d03, 0xf60a04bf.toInt(), 0x2cb81290, 0x24977c79, 0x5679b072, 0xbcaf89af.toInt(),
    0xde9a771f.toInt(), 0xd9930810.toInt(), 0xb38bae12.toInt(), 0xdccf3f2e.toInt(), 0x5512721f, 0x2e6b7124, 0x501adde6, 0x9f84cd87.toInt(),
    0x7a584718, 0x7408da17, 0xbc9f9abc.toInt(), 0xe94b7d8c.toInt(), 0xec7aec3a.toInt(), 0xdb851dfa.toInt(), 0x63094366, 0xc464c3d2.toInt(),
    0xef1c1847.toInt(), 0x3215d908, 0xdd433b37.toInt(), 0x24c2ba16, 0x12a14d43, 0x2a65c451, 0x50940002, 0x133ae4dd,
    0x71dff89e, 0x10314e55, 0x81ac77d6.toInt(), 0x5f11199b, 0x043556f1, 0xd7a3c76b.toInt(), 0x3c11183b, 0x5924a509,
    0xf28fe6ed.toInt(), 0x97f1fbfa.toInt(), 0x9ebabf2c.toInt(), 0x1e153c6e, 0x86e34570.toInt(), 0xeae96fb1.toInt(), 0x860e5e0a.toInt(), 0x5a3e2ab3,
    0x771fe71c, 0x4e3d06fa, 0x2965dcb9, 0x99e71d0f.toInt(), 0x803e89d6.toInt(), 0x5266c825, 0x2e4cc978, 0x9c10b36a.toInt(),
    0xc6150eba.toInt(), 0x94e2ea78.toInt(), 0xa5fc3c53.toInt(), 0x1e0a2df4, 0xf2f74ea7.toInt(), 0x361d2b3d, 0x1939260f, 0x19c27960,
    0x5223a708, 0xf71312b6.toInt(), 0xebadfe6e.toInt(), 0xeac31f66.toInt(), 0xe3bc4595.toInt(), 0xa67bc883.toInt(), 0xb17f37d1.toInt(), 0x018cff28,
    0xc332ddef.toInt(), 0xbe6c5aa5.toInt(), 0x65582185, 0x68ab9802, 0xeecea50f.toInt(), 0xdb2f953b.toInt(), 0x2aef7dad, 0x5b6e2f84,
    0x1521b628, 0x29076170, 0xecdd4775.toInt(), 0x619f1510, 0x13cca830, 0xeb61bd96.toInt(), 0x0334fe1e, 0xaa0363cf.toInt(),
    0xb5735c90.toInt(), 0x4c70a239, 0xd59e9e0b.toInt(), 0xcbaade14.toInt(), 0xeecc86bc.toInt(), 0x60622ca7, 0x9cab5cab.toInt(), 0xb2f3846e.toInt(),
    0x648b1eaf, 0x19bdf0ca, 0xa02369b9.toInt(), 0x655abb50, 0x40685a32, 0x3c2ab4b3, 0x319ee9d5, 0xc021b8f7.toInt(),
    0x9b540b19.toInt(), 0x875fa099.toInt(), 0x95f7997e.toInt(), 0x623d7da8, 0xf837889a.toInt(), 0x97e32d77.toInt(), 0x11ed935f, 0x16681281,
    0x0e358829, 0xc7e61fd6.toInt(), 0x96dedfa1.toInt(), 0x7858ba99, 0x57f584a5, 0x1b227263, 0x9b83c3ff.toInt(), 0x1ac24696,
    0xcdb30aeb.toInt(), 0x532e3054, 0x8fd948e4.toInt(), 0x6dbc3128, 0x58ebf2ef, 0x34c6ffea, 0xfe28ed61.toInt(), 0xee7c3c73.toInt(),
    0x5d4a14d9, 0xe864b7e3.toInt(), 0x42105d14, 0x203e13e0, 0x45eee2b6, 0xa3aaabea.toInt(), 0xdb6c4f15.toInt(), 0xfacb4fd0.toInt(),
    0xc742f442.toInt(), 0xef6abbb5.toInt(), 0x654f3b1d, 0x41cd2105, 0xd81e799e.toInt(), 0x86854dc7.toInt(), 0xe44b476a.toInt(), 0x3d816250,
    0xcf62a1f2.toInt(), 0x5b8d2646, 0xfc8883a0.toInt(), 0xc1c7b6a3.toInt(), 0x7f1524c3, 0x69cb7492, 0x47848a0b, 0x5692b285,
    0x095bbf00, 0xad19489d.toInt(), 0x1462b174, 0x23820e00, 0x58428d2a, 0x0c55f5ea, 0x1dadf43e, 0x233f7061,
    0x3372f092, 0x8d937e41.toInt(), 0xd65fecf1.toInt(), 0x6c223bdb, 0x7cde3759, 0xcbee7460.toInt(), 0x4085f2a7, 0xce77326e.toInt(),
    0xa6078084.toInt(), 0x19f8509e, 0xe8efd855.toInt(), 0x61d99735, 0xa969a7aa.toInt(), 0xc50c06c2.toInt(), 0x5a04abfc, 0x800bcadc.toInt(),
    0x9e447a2e.toInt(), 0xc3453484.toInt(), 0xfdd56705.toInt(), 0x0e1e9ec9, 0xdb73dbd3.toInt(), 0x105588cd, 0x675fda79, 0xe3674340.toInt(),
    0xc5c43465.toInt(), 0x713e38d8, 0x3d28f89e, 0xf16dff20.toInt(), 0x153e21e7, 0x8fb03d4a.toInt(), 0xe6e39f2b.toInt(), 0xdb83adf7.toInt(),
    0xe93d5a68.toInt(), 0x948140f7.toInt(), 0xf64c261c.toInt(), 0x94692934.toInt(), 0x411520f7, 0x7602d4f7, 0xbcf46b2e.toInt(), 0xd4a20068.toInt(),
    0xd4082471.toInt(), 0x3320f46a, 0x43b7d4b7, 0x500061af, 0x1e39f62e, 0x97244546.toInt(), 0x14214f74, 0xbf8b8840.toInt(),
    0x4d95fc1d, 0x96b591af.toInt(), 0x70f4ddd3, 0x66a02f45, 0xbfbc09ec.toInt(), 0x03bd9785, 0x7fac6dd0, 0x31cb8504,
    0x96eb27b3.toInt(), 0x55fd3941, 0xda2547e6.toInt(), 0xabca0a9a.toInt(), 0x28507825, 0x530429f4, 0x0a2c86da, 0xe9b66dfb.toInt(),
    0x68dc1462, 0xd7486900.toInt(), 0x680ec0a4, 0x27a18dee, 0x4f3ffea2, 0xe887ad8c.toInt(), 0xb58ce006.toInt(), 0x7af4d6b6,
    0xaace1e7c.toInt(), 0xd3375fec.toInt(), 0xce78a399.toInt(), 0x406b2a42, 0x20fe9e35, 0xd9f385b9.toInt(), 0xee39d7ab.toInt(), 0x3b124e8b,
    0x1dc9faf7, 0x4b6d1856, 0x26a36631, 0xeae397b2.toInt(), 0x3a6efa74, 0xdd5b4332.toInt(), 0x6841e7f7, 0xca7820fb.toInt(),
    0xfb0af54e.toInt(), 0xd8feb397.toInt(), 0x454056ac, 0xba489527.toInt(), 0x55533a3a, 0x20838d87, 0xfe6ba9b7.toInt(), 0xd096954b.toInt(),
    0x55a867bc, 0xa1159a58.toInt(), 0xcca92963.toInt(), 0x99e1db33.toInt(), 0xa62a4a56.toInt(), 0x3f3125f9, 0x5ef47e1c, 0x9029317c.toInt(),
    0xfdf8e802.toInt(), 0x04272f70, 0x80bb155c.toInt(), 0x05282ce3, 0x95c11548.toInt(), 0xe4c66d22.toInt(), 0x48c1133f, 0xc70f86dc.toInt(),
    0x07f9c9ee, 0x41041f0f, 0x404779a4, 0x5d886e17, 0x325f51eb, 0xd59bc0d1.toInt(), 0xf2bcc18f.toInt(), 0x41113564,
    0x257b7834, 0x602a9c60, 0xdff8e8a3.toInt(), 0x1f636c1b, 0x0e12b4c2, 0x02e1329e, 0xaf664fd1.toInt(), 0xcad18115.toInt(),
    0x6b2395e0, 0x333e92e1, 0x3b240b62, 0xeebeb922.toInt(), 0x85b2a20e.toInt(), 0xe6ba0d99.toInt(), 0xde720c8c.toInt(), 0x2da2f728,
    0xd0127845.toInt(), 0x95b794fd.toInt(), 0x647d0862, 0xe7ccf5f0.toInt(), 0x5449a36f, 0x877d48fa.toInt(), 0xc39dfd27.toInt(), 0xf33e8d1e.toInt(),
    0x0a476341, 0x992eff74.toInt(), 0x3a6f6eab, 0xf4f8fd37.toInt(), 0xa812dc60.toInt(), 0xa1ebddf8.toInt(), 0x991be14c.toInt(), 0xdb6e6b0d.toInt(),
    0xc67b5510.toInt(), 0x6d672c37, 0x2765d43b, 0xdcd0e804.toInt(), 0xf1290dc7.toInt(), 0xcc00ffa3.toInt(), 0xb5390f92.toInt(), 0x690fed0b,
    0x667b9ffb, 0xcedb7d9c.toInt(), 0xa091cf0b.toInt(), 0xd9155ea3.toInt(), 0xbb132f88.toInt(), 0x515bad24, 0x7b9479bf, 0x763bd6eb,
    0x37392eb3, 0xcc115979.toInt(), 0x8026e297.toInt(), 0xf42e312d.toInt(), 0x6842ada7, 0xc66a2b3b.toInt(), 0x12754ccc, 0x782ef11c,
    0x6a124237, 0xb79251e7.toInt(), 0x06a1bbe6, 0x4bfb6350, 0x1a6b1018, 0x11caedfa, 0x3d25bdd8, 0xe2e1c3c9.toInt(),
    0x44421659, 0x0a121386, 0xd90cec6e.toInt(), 0xd5abea2a.toInt(), 0x64af674e, 0xda86a85f.toInt(), 0xbebfe988.toInt(), 0x64e4c3fe,
    0x9dbc8057.toInt(), 0xf0f7c086.toInt(), 0x60787bf8, 0x6003604d, 0xd1fd8346.toInt(), 0xf6381fb0.toInt(), 0x7745ae04, 0xd736fccc.toInt(),
    0x83426b33.toInt(), 0xf01eab71.toInt(), 0xb0804187.toInt(), 0x3c005e5f, 0x77a057be, 0xbde8ae24.toInt(), 0x55464299, 0xbf582e61.toInt(),
    0x4e58f48f, 0xf2ddfda2.toInt(), 0xf474ef38.toInt(), 0x8789bdc2.toInt(), 0x5366f9c3, 0xc8b38e74.toInt(), 0xb475f255.toInt(), 0x46fcd9b9,
    0x7aeb2661, 0x8b1ddf84.toInt(), 0x846a0e79.toInt(), 0x915f95e2.toInt(), 0x466e598e, 0x20b45770, 0x8cd55591.toInt(), 0xc902de4c.toInt(),
    0xb90bace1.toInt(), 0xbb8205d0.toInt(), 0x11a86248, 0x7574a99e, 0xb77f19b6.toInt(), 0xe0a9dc09.toInt(), 0x662d09a1, 0xc4324633.toInt(),
    0xe85a1f02.toInt(), 0x09f0be8c, 0x4a99a025, 0x1d6efe10, 0x1ab93d1d, 0x0ba5a4df, 0xa186f20f.toInt(), 0x2868f169,
    0xdcb7da83.toInt(), 0x573906fe, 0xa1e2ce9b.toInt(), 0x4fcd7f52, 0x50115e01, 0xa70683fa.toInt(), 0xa002b5c4.toInt(), 0x0de6d027,
    0x9af88c27.toInt(), 0x773f8641, 0xc3604c06.toInt(), 0x61a806b5, 0xf0177a28.toInt(), 0xc0f586e0.toInt(), 0x006058aa, 0x30dc7d62,
    0x11e69ed7, 0x2338ea63, 0x53c2dd94, 0xc2c21634.toInt(), 0xbbcbee56.toInt(), 0x90bcb6de.toInt(), 0xebfc7da1.toInt(), 0xce591d76.toInt(),
    0x6f05e409, 0x4b7c0188, 0x39720a3d, 0x7c927c24, 0x86e3725f.toInt(), 0x724d9db9, 0x1ac15bb4, 0xd39eb8fc.toInt(),
    0xed545578.toInt(), 0x08fca5b5, 0xd83d7cd3.toInt(), 0x4dad0fc4, 0x1e50ef5e, 0xb161e6f8.toInt(), 0xa28514d9.toInt(), 0x6c51133c,
    0x6fd5c7e7, 0x56e14ec4, 0x362abfce, 0xddc6c837.toInt(), 0xd79a3234.toInt(), 0x92638212.toInt(), 0x670efa8e, 0x406000e0,
    0x3a39ce37, 0xd3faf5cf.toInt(), 0xabc27737.toInt(), 0x5ac52d1b, 0x5cb0679e, 0x4fa33742, 0xd3822740.toInt(), 0x99bc9bbe.toInt(),
    0xd5118e9d.toInt(), 0xbf0f7315.toInt(), 0xd62d1c7e.toInt(), 0xc700c47b.toInt(), 0xb78c1b6b.toInt(), 0x21a19045, 0xb26eb1be.toInt(), 0x6a366eb4,
    0x5748ab2f, 0xbc946e79.toInt(), 0xc6a376d2.toInt(), 0x6549c2c8, 0x530ff8ee, 0x468dde7d, 0xd5730a1d.toInt(), 0x4cd04dc6,
    0x2939bbdb, 0xa9ba4650.toInt(), 0xac9526e8.toInt(), 0xbe5ee304.toInt(), 0xa1fad5f0.toInt(), 0x6a2d519a, 0x63ef8ce2, 0x9a86ee22.toInt(),
    0xc089c2b8.toInt(), 0x43242ef6, 0xa51e03aa.toInt(), 0x9cf2d0a4.toInt(), 0x83c061ba.toInt(), 0x9be96a4d.toInt(), 0x8fe51550.toInt(), 0xba645bd6.toInt(),
    0x2826a2f9, 0xa73a3ae1.toInt(), 0x4ba99586, 0xef5562e9.toInt(), 0xc72fefd3.toInt(), 0xf752f7da.toInt(), 0x3f046f69, 0x77fa0a59,
    0x80e4a915.toInt(), 0x87b08601.toInt(), 0x9b09e6ad.toInt(), 0x3b3ee593, 0xe990fd5a.toInt(), 0x9e34d797.toInt(), 0x2cf0b7d9, 0x022b8b51,
    0x96d5ac3a.toInt(), 0x017da67d, 0xd1cf3ed6.toInt(), 0x7c7d2d28, 0x1f9f25cf, 0xadf2b89b.toInt(), 0x5ad6b472, 0x5a88f54c,
    0xe029ac71.toInt(), 0xe019a5e6.toInt(), 0x47b0acfd, 0xed93fa9b.toInt(), 0xe8d3c48d.toInt(), 0x283b57cc, 0xf8d56629.toInt(), 0x79132e28,
    0x785f0191, 0xed756055.toInt(), 0xf7960e44.toInt(), 0xe3d35e8c.toInt(), 0x15056dd4, 0x88f46dba.toInt(), 0x03a16125, 0x0564f0bd,
    0xc3eb9e15.toInt(), 0x3c9057a2, 0x97271aec.toInt(), 0xa93a072a.toInt(), 0x1b3f6d9b, 0x1e6321f5, 0xf59c66fb.toInt(), 0x26dcf319,
    0x7533d928, 0xb155fdf5.toInt(), 0x03563482, 0x8aba3cbb.toInt(), 0x28517711, 0xc20ad9f8.toInt(), 0xabcc5167.toInt(), 0xccad925f.toInt(),
    0x4de81751, 0x3830dc8e, 0x379d5862, 0x9320f991.toInt(), 0xea7a90c2.toInt(), 0xfb3e7bce.toInt(), 0x5121ce64, 0x774fbe32,
    0xa8b6e37e.toInt(), 0xc3293d46.toInt(), 0x48de5369, 0x6413e680, 0xa2ae0810.toInt(), 0xdd6db224.toInt(), 0x69852dfd, 0x09072166,
    0xb39a460a.toInt(), 0x6445c0dd, 0x586cdecf, 0x1c20c8ae, 0x5bbef7dd, 0x1b588d40, 0xccd2017f.toInt(), 0x6bb4e3bb,
    0xdda26a7e.toInt(), 0x3a59ff45, 0x3e350a44, 0xbcb4cdd5.toInt(), 0x72eacea8, 0xfa6484bb.toInt(), 0x8d6612ae.toInt(), 0xbf3c6f47.toInt(),
    0xd29be463.toInt(), 0x542f5d9e, 0xaec2771b.toInt(), 0xf64e6370.toInt(), 0x740e0d8d, 0xe75b1357.toInt(), 0xf8721671.toInt(), 0xaf537d5d.toInt(),
    0x4040cb08, 0x4eb4e2cc, 0x34d2466a, 0x0115af84, 0xe1b00428.toInt(), 0x95983a1d.toInt(), 0x06b89fb4, 0xce6ea048.toInt(),
    0x6f3f3b82, 0x3520ab82, 0x011a1d4b, 0x277227f8, 0x611560b1, 0xe7933fdc.toInt(), 0xbb3a792b.toInt(), 0x344525bd,
    0xa08839e1.toInt(), 0x51ce794b, 0x2f32c9b7, 0xa01fbac9.toInt(), 0xe01cc87e.toInt(), 0xbcc7d1f6.toInt(), 0xcf0111c3.toInt(), 0xa1e8aac7.toInt(),
    0x1a908749, 0xd44fbd9a.toInt(), 0xd0dadecb.toInt(), 0xd50ada38.toInt(), 0x0339c32a, 0xc6913667.toInt(), 0x8df9317c.toInt(), 0xe0b12b4f.toInt(),
    0xf79e59b7.toInt(), 0x43f5bb3a, 0xf2d519ff.toInt(), 0x27d9459c, 0xbf97222c.toInt(), 0x15e6fc2a, 0x0f91fc71, 0x9b941525.toInt(),
    0xfae59361.toInt(), 0xceb69ceb.toInt(), 0xc2a86459.toInt(), 0x12baa8d1, 0xb6c1075e.toInt(), 0xe3056a0c.toInt(), 0x10d25065, 0xcb03a442.toInt(),
    0xe0ec6e0e.toInt(), 0x1698db3b, 0x4c98a0be, 0x3278e964, 0x9f1f9532.toInt(), 0xe0d392df.toInt(), 0xd3a0342b.toInt(), 0x8971f21e.toInt(),
    0x1b0a7441, 0x4ba3348c, 0xc5be7120.toInt(), 0xc37632d8.toInt(), 0xdf359f8d.toInt(), 0x9b992f2e.toInt(), 0xe60b6f47.toInt(), 0x0fe3f11d,
    0xe54cda54.toInt(), 0x1edad891, 0xce6279cf.toInt(), 0xcd3e7e6f.toInt(), 0x1618b166, 0xfd2c1d05.toInt(), 0x848fd2c5.toInt(), 0xf6fb2299.toInt(),
    0xf523f357.toInt(), 0xa6327623.toInt(), 0x93a83531.toInt(), 0x56cccd02, 0xacf08162.toInt(), 0x5a75ebb5, 0x6e163697, 0x88d273cc.toInt(),
    0xde966292.toInt(), 0x81b949d0.toInt(), 0x4c50901b, 0x71c65614, 0xe6c6c7bd.toInt(), 0x327a140a, 0x45e1d006, 0xc3f27b9a.toInt(),
    0xc9aa53fd.toInt(), 0x62a80f00, 0xbb25bfe2.toInt(), 0x35bdd2f6, 0x71126905, 0xb2040222.toInt(), 0xb6cbcf7c.toInt(), 0xcd769c2b.toInt(),
    0x53113ec0, 0x1640e3d3, 0x38abbd60, 0x2547adf0, 0xba38209c.toInt(), 0xf746ce76.toInt(), 0x77afa1c5, 0x20756060,
    0x85cbfe4e.toInt(), 0x8ae88dd8.toInt(), 0x7aaaf9b0, 0x4cf9aa7e, 0x1948c25c, 0x02fb8a8c, 0x01c36ae4, 0xd6ebe1f9.toInt(),
    0x90d4f869.toInt(), 0xa65cdea0.toInt(), 0x3f09252d, 0xc208e69f.toInt(), 0xb74e6132.toInt(), 0xce77e25b.toInt(), 0x578fdfe3, 0x3ac372e6,
)

/// Expanded Blowfish subkey state (18 P words + 1024 S words).
class BlowfishKey internal constructor(
    val p: IntArray,
    val s: IntArray
)

/// Expands [key] (8..56 bytes) into the Blowfish subkey state — a
/// line-by-line port of `blowfishExpandKey` in blowfish.dart.
fun blowfishExpandKey(key: ByteArray): BlowfishKey {
    require(key.isNotEmpty()) { "Blowfish key must not be empty" }
    val p = BF_P.copyOf()
    val s = BF_S.copyOf()

    // XOR the P-array with the key, cycling over the key bytes.
    var j = 0
    for (i in 0 until 18) {
        var word = 0
        for (k in 0 until 4) {
            word = ((word shl 8) or (key[(j + k) % key.size].toInt() and 0xFF))
        }
        p[i] = p[i] xor word
        j = (j + 4) % key.size
    }

    fun f(boxes: IntArray, x: Int): Int {
        val a = (x ushr 24) and 0xFF
        val b = (x ushr 16) and 0xFF
        val c = (x ushr 8) and 0xFF
        val d = x and 0xFF
        return ((boxes[a] + boxes[256 + b]) xor boxes[512 + c]) + boxes[768 + d]
    }

    // Encrypt one block with the current state. Returns (r, l) — the same
    // word order the Dart encryptBlock writes into `out`.
    fun encryptBlock(l0: Int, r0: Int): Pair<Int, Int> {
        var l = l0
        var r = r0
        l = l xor p[0]
        var i = 1
        while (i <= 16) {
            r = r xor (f(s, l) xor p[i])
            l = l xor (f(s, r) xor p[i + 1])
            i += 2
        }
        r = r xor p[17]
        return r to l
    }

    // Chain-encrypt the P array, then the S boxes (Schneier's schedule).
    var l = 0
    var r = 0
    var i = 0
    while (i < 18) {
        val (rOut, lOut) = encryptBlock(l, r)
        p[i] = rOut
        p[i + 1] = lOut
        l = p[i]
        r = p[i + 1]
        i += 2
    }
    i = 0
    while (i < 1024) {
        val (rOut, lOut) = encryptBlock(l, r)
        s[i] = rOut
        s[i + 1] = lOut
        l = s[i]
        r = s[i + 1]
        i += 2
    }
    return BlowfishKey(p, s)
}

/// Streaming-style CBC decryption over 8-byte ciphertext blocks — port of
/// `BlowfishCbcDecryptor` in blowfish.dart. The chaining state (previous
/// ciphertext block) is kept internally, IV first.
class BlowfishCbcDecryptor(key: ByteArray, iv: ByteArray) {
    private val kf: BlowfishKey = blowfishExpandKey(key)
    private var prev: ByteArray = iv.copyOf()

    /// Decrypts exactly 8 ciphertext bytes from [block] at [off].
    fun decryptBlock(block: ByteArray, off: Int = 0): ByteArray {
        // Feistel with P used in reverse (p[17] first, p[0] last).
        var l = ((block[off].toInt() and 0xFF) shl 24) or
            ((block[off + 1].toInt() and 0xFF) shl 16) or
            ((block[off + 2].toInt() and 0xFF) shl 8) or
            (block[off + 3].toInt() and 0xFF)
        var r = ((block[off + 4].toInt() and 0xFF) shl 24) or
            ((block[off + 5].toInt() and 0xFF) shl 16) or
            ((block[off + 6].toInt() and 0xFF) shl 8) or
            (block[off + 7].toInt() and 0xFF)
        val p = kf.p
        val s = kf.s
        l = l xor p[17]
        var i = 16
        while (i >= 1) {
            r = r xor (f(s, l) xor p[i])
            l = l xor (f(s, r) xor p[i - 1])
            i -= 2
        }
        r = r xor p[0]
        val raw = byteArrayOf(
            ((r ushr 24) and 0xFF).toByte(), ((r ushr 16) and 0xFF).toByte(),
            ((r ushr 8) and 0xFF).toByte(), (r and 0xFF).toByte(),
            ((l ushr 24) and 0xFF).toByte(), ((l ushr 16) and 0xFF).toByte(),
            ((l ushr 8) and 0xFF).toByte(), (l and 0xFF).toByte()
        )
        val out = ByteArray(8)
        for (k in 0 until 8) out[k] = (raw[k].toInt() xor prev[k].toInt()).toByte()
        prev = block.copyOfRange(off, off + 8)
        return out
    }

    private fun f(s: IntArray, x: Int): Int {
        val a = (x ushr 24) and 0xFF
        val b = (x ushr 16) and 0xFF
        val c = (x ushr 8) and 0xFF
        val d = x and 0xFF
        return ((s[a] + s[256 + b]) xor s[512 + c]) + s[768 + d]
    }
}

/// Self-test with the published vectors; run once at configure time.
/// Returns null when every vector passes, or a description of the failure.
internal fun blowfishSelfTest(): String? {
    val v1 = runCatching {
        val kf = blowfishExpandKey(hexToBytes("FEDCBA9876543210"))
        encryptBlockForTest(kf, hexToBytes("0123456789ABCDEF"))
    }.getOrNull() ?: return "expand/encrypt threw"
    if (v1 != "0ACEAB0FC6A0A28D") return "vector1 got $v1"
    val v2 = runCatching {
        val kf = blowfishExpandKey(hexToBytes("7CA110454A1A6E57"))
        encryptBlockForTest(kf, hexToBytes("01A1D6D039776742"))
    }.getOrNull() ?: return "expand/encrypt threw"
    if (v2 != "59C68245EB05282B") return "vector2 got $v2"
    return null
}

private fun encryptBlockForTest(kf: BlowfishKey, block: ByteArray): String {
    var l = ((block[0].toInt() and 0xFF) shl 24) or ((block[1].toInt() and 0xFF) shl 16) or
        ((block[2].toInt() and 0xFF) shl 8) or (block[3].toInt() and 0xFF)
    var r = ((block[4].toInt() and 0xFF) shl 24) or ((block[5].toInt() and 0xFF) shl 16) or
        ((block[6].toInt() and 0xFF) shl 8) or (block[7].toInt() and 0xFF)
    val p = kf.p
    val s = kf.s
    l = l xor p[0]
    var i = 1
    while (i <= 16) {
        r = r xor (fTest(s, l) xor p[i])
        l = l xor (fTest(s, r) xor p[i + 1])
        i += 2
    }
    r = r xor p[17]
    return String.format(
        "%08X%08X", r, l
    )
}

private fun fTest(s: IntArray, x: Int): Int {
    val a = (x ushr 24) and 0xFF
    val b = (x ushr 16) and 0xFF
    val c = (x ushr 8) and 0xFF
    val d = x and 0xFF
    return ((s[a] + s[256 + b]) xor s[512 + c]) + s[768 + d]
}

internal fun hexToBytes(hex: String): ByteArray =
    ByteArray(hex.length / 2) { i ->
        ((Character.digit(hex[i * 2], 16) shl 4) + Character.digit(hex[i * 2 + 1], 16)).toByte()
    }
