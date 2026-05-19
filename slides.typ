#import "@preview/slydst:0.1.3": *

#show: slides.with(
  title: "Breaking AES Encryption in\nDark Souls Remastered",
  date: "2026",
  authors: ("Antoine Sutter",),
  layout: "large",
  ratio: 4 / 3,
  title-color: none,
)

#set quote(block: true)

==  /* empty title */

#let socials = (
  ("github", "https://github.com/CapitaineToinon/dsr-savefiles", "CapitaineToinon/dsr-savefiles"),
  ("github", "https://github.com/CapitaineToinon", "CapitaineToinon"),
  ("envelope", "mailto:antoine.sutter@etu.unige.ch", "antoine.sutter@etu.unige.ch"),
  ("bluesky", "https://bsky.app/profile/capitainetoinon.bsky.social", "@capitainetoinon.bsky.social"),
)

#align(center + horizon)[
  #block(radius: 999pt, clip: true)[
    #image("./images/me.png", width: 80pt)
  ]
  #grid(
    columns: auto,
    row-gutter: 5pt,
    ..for (svg, url, text) in socials {
      (
        grid(
          columns: (auto, auto),
          column-gutter: 0.5em,
          image("images/" + svg + ".svg", width: 1em),
          link(url)[
            #text
          ],
        ),
      )
    }
  )
]

#pagebreak()

== Dark Souls

- Action role-playing game created by FROMSOFTWARE#footnote(link("https://www.fromsoftware.jp"))
- Released in 2011 on the Xbox 360 & PlayStation 3
- Released for the PC in 2012

#align(right + bottom)[
  #image("./images/cover.webp", width: 35%)
]

#pagebreak()

== Dark Souls Remastered

- Created by QLOC#footnote(link("https://q-loc.com/"))
- Released in 2018
- Quality of life features, better framerate, textures, resolutions, etc.

#align(right + bottom)[
  #image("./images/cover_remastered.webp", width: 40%)
]

#pagebreak()

== Save System

- Periodically save progress into a file on disk
  - Current stats
  - Current positions
  - Health
  - Time elapsed
  - etc
- Total of 10 characters can be saved
- Located in `/My Documents/NBGI/DARK SOULS REMASTERED`

#align(right + bottom)[
  #image("./images/characters.png", width: 55%)
]

#pagebreak()

== Encrypted Save Files

#align(center)[
  #figure(
    image("./images/aes-side-by-side.png"),
    caption: "Save File: DSR vs Original",
  )
]

#pagebreak()

== Ghidra

- Reverse engineering software#footnote(link("https://ghidra-sre.org/"))
- Created by the NSA

#align(center + bottom)[
  #figure(image("./images/ghidra.png", width: 80%), caption: "Dark Souls Remastered in Ghidra")
]

#pagebreak()

#align(center + horizon)[
  #figure(image("./images/aes-tree.png", width: 50%), caption: "Mentions of AES in DSR")
]

#pagebreak()

#align(center + horizon)[
  #figure(image("./images/read-file-winapi.png", width: 50%), caption: "Usages of the Windows API ReadFile")
]

== Cheat Engine & anti-debugger

- Dark Souls Remastered comes with anti-debugger
- When attaching debugger, game crashes after couple of seconds
- Can be bypassed with dearxan#footnote(link("https://github.com/tremwil/dearxan"))
- Ended up not using Cheat Engine

#align(center + bottom)[
  #figure(image("./images/debugger.png", width: 60%), caption: "Cheat Engine's debugger attached to DSR")
]

== Detouring ReadFile

- Dark Souls uses DirectX#footnote(link("https://learn.microsoft.com/en-us/windows/win32/directx")) and DirectInput#footnote(link("https://learn.microsoft.com/en-us/previous-versions/windows/desktop/ee416842(v=vs.85)"))
- Game loads our own `dinput8.dll` at startup
- We then just proxy the real `dinput8.dll`, more specifically `DirectInput8Create`
- We now have access to the game's memory

#pagebreak()

- Detour ReadFile, external function from `kernel32.dll`
- Patch the Import Address Table (IAT) to call our own function instead

#align(center + horizon)[
  #figure(image("./images/iat.png"))
]

#pagebreak()

```
[CAPITAINE] sl2 read 16 bytes: 1B 4A 57 81 19 EC 05 4C
[CAPITAINE]   [ 0] +0x6ffffc9e17d3
[CAPITAINE]   [ 1] +0x140d08787
[CAPITAINE]   [ 2] +0x140d0560b
[CAPITAINE]   [ 3] +0x140cf3758
[CAPITAINE]   [ 4] +0x140d027a4
[CAPITAINE]   [ 5] +0x140d027a4
[CAPITAINE]   [ 6] +0x140d0dcb2
[CAPITAINE]   [ 7] +0x140d0bfe0
[CAPITAINE]   [ 8] +0x140cf3758
[CAPITAINE]   [ 9] +0x140db35cd
[CAPITAINE]   [10] +0x1410da1fa
[CAPITAINE]   [11] +0x1410d84e4
[CAPITAINE]   [12] +0x1410d0800
[CAPITAINE]   [13] +0x1410c4ffa
[CAPITAINE]   [14] +0x1410ce1c2
[CAPITAINE]   [15] +0x140cce31f
[CAPITAINE]   [16] +0x6fffff9610fb
[CAPITAINE]   [17] +0x6fffffec0ca9
[CAPITAINE]   [18] +0x6ffffff3fbaf
```

#pagebreak()

== Finding AES key

- Ended up finding promising code at `0x140db35cd`
- Going up the call stack seemed obfuscated
- AI to the rescue

#align(center + horizon)[
  #figure(
    image("./images/ghidra_mcp.png"),
    caption: [Logo for the Ghidra MCP plugin#footnote(link("https://github.com/LaurieWired/GhidraMCP"))],
  )
]

#pagebreak()

```
$ Good. The patch offset is wrong. Let me disassemble FUN_1410c3db0 to find the actual location of the SETNZ AL.

  Called ghidra (ctrl+o to expand)

$ Found it. The patch address is definitely correct — SETNZ AL is at 0x1410c446f, immediately followed by MOV byte ptr [RBX + 0xa0], AL at 0x1410c4472. The patch bytes are right too.
```

#pagebreak()


- Key located at `[DarkSoulsRemastered.exe+0x1d053c0]+0x90`.

```c
void read_key() {
  uintptr_t base = (uintptr_t)GetModuleHandleA(NULL);
  uintptr_t *config_ptr = (uintptr_t *)(base + 0x1d053c0);
  BYTE *key = (BYTE *)(*config_ptr + 0x90);
  DEBUG("AES key: %02X%02X%02X%02X %02X%02X%02X%02X %02X%02X%02X%02X "
        "%02X%02X%02X%02X\n",
        key[0], key[1], key[2], key[3], key[4], key[5], key[6], key[7],
        key[8], key[9], key[10], key[11], key[12], key[13], key[14], key[15]);
}
```

#pagebreak()

#align(center + horizon)[
  ```
  [CAPITAINE] AES key: 01234567 89ABCDEF FEDCBA98 76543210
  ```
]

== Example

#align(center + horizon)[
  #figure(
    image("./images/read-example.png"),
    caption: "Dotnet successfully reading encrypted data from the DSR savefile",
  )
]

= Demo

#pagebreak()

== Better decryption

- Existing code in LiveSplit Dark Souls In-Game Timer (written by myself)#footnote(link("https://github.com/CapitaineToinon/LiveSplit.DarkSoulsIGT"))
- Used to decrypt the whole file (4.2M)
- In reality, only characters are encrypted, seperately
- Read only 32 bytes instead
- Over \~500x faster

#align(center + horizon)[
  ```
  1000 iterations each:
  Old: 5264ms total, 5265.0µs/iter
  New: 10ms total, 10.5µs/iter
  ```
]

== Linux Problems

- Had to install MinGW#footnote(link("https://www.mingw-w64.org/")) to compile windows executables on Linux
- Had to compile dearxan from source using MinGW
- Ended up not using Cheat Engine because of clanky UI and Wine problems
- Had to tinker using ProtonTricks#footnote(link("https://protontricks.com/"))
- Otherwise, pretty smooth! Gaming on Linux is awesome.

== Conclusion

- We successfully broke AES in Dark Souls Remastered's save file system
- Similar AES in following FromSoftware games
  - Dark Souls 2, Dark Souls 3, Elden Ring & Sekiro
- Client side encryption is useless
- Managed to improve existing code's speed by \~500x

#align(center + bottom)[
  #image("./images/keep-out.jpg", width: 50%)
]

= Thank you

== Sources

- FromSoftware. #link("https://www.fromsoftware.jp")
- QLOC. #link("https://q-loc.com/")
- NSA / CISA. _Ghidra_. #link("https://ghidra-sre.org/")
- LaurieWired. _GhidraMCP_. #link("https://github.com/LaurieWired/GhidraMCP")
- MinGW-w64 Project. _MinGW-w64_. #link("https://www.mingw-w64.org/")
- ProtonTricks. #link("https://protontricks.com/")
- tremwil. _dearxan_. #link("https://github.com/tremwil/dearxan")
- "Keep out or enter, I'm a sign not a cop". #link("https://www.picturequotes.com/keep-out-or-enter-im-a-sign-not-a-cop-quote-83753")
