#import "@preview/codly:1.3.0": *
#import "@preview/codly-languages:0.1.1": *
#import "@preview/glossarium:0.5.10": gls, glspl, make-glossary, print-glossary, register-glossary

#let glossary = (
  (key: "dsr", short: "DSR", long: "Dark Souls Remastered"),
  (key: "iat", short: "IAT", long: "Import Address Table"),
  (key: "aes", short: "AES", long: "Advanced Encryption Standard"),
  (key: "mcp", short: "MCP", long: "Model Context Protocol"),
  (
    key: "ce",
    short: "Cheat Engine",
    description: "A popular memory scanning and debugging tool used in reverse engineering",
  ),
  (
    key: "nsa",
    short: "NSA",
    long: "National Security Agency",
    description: "United States intelligence agency responsible for signals intelligence and cybersecurity. Creator of the Ghidra reverse engineering framework.",
  ),
)

#show: make-glossary
#register-glossary(glossary)

#set page(
  paper: "a4",
  margin: (x: 2.5cm, y: 3cm),
  header: context if counter(page).get().first() > 1 [
    #set text(size: 9pt)
    #grid(
      columns: (1fr, 1fr),
      align(left)[Breaking AES Encryption in Dark Souls Remastered], align(right)[Antoine Sutter],
    )
  ],
  footer: context if counter(page).get().first() > 1 [
    #set text(size: 9pt)
    #align(center)[#counter(page).display()]
  ],
)

#set heading(numbering: "1.")
#show heading: set block(below: 1em)

#align(center + horizon)[
  #image("images/dsr.png")
  #text(size: 24pt, weight: "bold")[Breaking AES Encryption in#linebreak()Dark Souls Remastered]
  #v(1em)
  #text(size: 14pt)[Reverse Engineering Savefile Encryption]
  #v(0em)
  #text(size: 12pt)[Antoine Sutter]
]

#show: codly-init.with()
#codly(zebra-fill: none)
#codly(number-format: none)

#pagebreak()

#outline(title: "Table of Contents")

#pagebreak()

= Introduction

Dark Souls is an action role-playing game developed by Japanese studio FromSoftware#footnote("https://www.fromsoftware.jp") and released in 2011. Progress is persisted in a save file. The game writes the player's current state, inventory, and statistics to disk whenever it performs a save operation.

In 2018, a remastered edition was released, developed by QLOC#footnote("https://q-loc.com/"). Dark Souls Remastered brought welcome improvements over the original, such as a stable 60 fps framerate, higher resolution textures and improved mouse and keyboard support just to name a few. Alongside these improvements however, QLOC also introduced measures that were absent from the original release, anti-cheating measures and encrypted save files.

The save file encryption presents an obvious fundamental flaw. Dark Souls Remastered is a game that can be played entirely offline, and the save file is read and written locally by the executable. For the game to decrypt its own save files at runtime, the decryption key must be present in the executable itself. An attacker with access to the binary, which is every player, therefore has everything needed to recover the key. The encryption provides no real security guarantee; it only raises the bar for how much effort is required to find it. The goal of this report is to document the full process of locating that key through static and dynamic analysis of the game binary.

== Disclaimer

The AES key has already been reverse engineered by other members of the Dark Souls modding community and documentation about the save file format is available on the `?WikiName?` modding wiki#footnote("https://www.soulsmodding.com/doku.php?id=format:sl2"). In this report, the wiki sections about the save file format will not be used and the reverse engineering process will be done from scratch. The code is available on my personal Github account#footnote("https://github.com/CapitaineToinon/dsr-savefiles").

#pagebreak()

= Running a Windows Game on Linux

Because I enjoy making things more difficult for myself, I've decided to do this entire process on Linux, as I have uninstalled Windows on all of my computers recently. This presents a few problems as Dark Souls Remastered is a Windows game. Gaming on Linux has greatly improved in the last couple of years though and now, thanks to Steam#footnote("https://store.steampowered.com/") and the Proton compatibility layer#footnote("https://en.wikipedia.org/wiki/Proton_(software)"), running #gls("dsr") on Linux is now trivial.

#figure(
  image("images/neofetch.png", width: 75%),
  caption: "Dark Souls Remastered running in Arch Linux",
)

In order to help working common paths, some scripts have been created in order to directly work with the files in the correct locations, all in the `scripts/` folder:

- `env.sh`: contains environment variables
- `game_logs.sh`: shows the logs created at the root of the C drive in the game's prefix
- `game_output.sh`: shows the steam's game output
- `install_cheatengine.sh`: installs cheat engine in the game's prefix
- `install_windows_dependencies.sh`: installs the windows dependencies in the game's prefix
- `run_cheatengine.sh`: starts cheat engine.

Many of these scripts are using ProtonTricks#footnote("https://protontricks.com/").

#pagebreak()

= Code injection using `dinput8.dll`

#gls("dsr") being a Windows game, it uses DirectInput 8 for input handling, loading `dinput8.dll` at startup. A common way to inject code into games that use DirectInput is to proxy that call to `dinput8.dll` that the game tries to load dynamically at runtime, using the WinAPI `LoadLibraryA`. By compiling our own `dinput8.dll` file and placing it alongside the executable, the game will load our dll instead of the windows one. We then need to proxy the real `dinput8.dll` by loading the library ourselves whenever the game asks for it by exposing a `DirectInput8Create` symbol, otherwise the game crashes. In order to successfully compile the dll for Windows from my Linux machine, I need to use MinGW#footnote("https://www.mingw-w64.org/") and the `x86_64-w64-mingw32-gcc` compiler.

```c
#include <windows.h>

typedef HRESULT(WINAPI *dinp8crt_t)(HINSTANCE, DWORD, REFIID, LPVOID *, LPUNKNOWN);

static dinp8crt_t OrigDirectInput8Create;

__attribute__((dllexport)) HRESULT WINAPI DirectInput8Create(
    HINSTANCE inst, DWORD ver, REFIID id, LPVOID *pout, LPUNKNOWN outer) {
  return OrigDirectInput8Create(inst, ver, id, pout, outer);
}

void setup_d8proxy(void) {
  char syspath[320];
  GetSystemDirectoryA(syspath, 320);
  strcat(syspath, "\\dinput8.dll");
  HMODULE mod = LoadLibraryA(syspath);
  OrigDirectInput8Create = (dinp8crt_t)GetProcAddress(mod, "DirectInput8Create");
}

BOOL APIENTRY DllMain(HMODULE mod, DWORD reason, LPVOID reserved) {
  switch (reason) {
  case DLL_PROCESS_ATTACH:
    setup_d8proxy();
    break;
  }

  return TRUE;
}
```

Once this is done and the game has successfully loaded the real DirectInput via our proxy dll, we have access to the game's memory directly, allowing us to read and write to the game's memory without having to use WinAPIs such as `WriteProcessMemory` and `ReadProcessMemory`.

#pagebreak()

= Static Analysis with Ghidra

Ghidra#footnote("https://ghidra-sre.org/") is a reverse engineering software written in Java by the #gls("nsa") and allows the decompilation of executables. This produces pseudo code in C you can easily inspect, functions you can rename and other useful features.

#figure(
  image("images/ghidra.png", width: 75%),
  caption: "Dark Souls Remastered in Ghidra",
)

From there, I managed to confirm the game probably used #gls("aes") to encrypt its save files by looking for symbols named AES in the executable. These symbols do not exist in the original version of the game.


#figure(
  image("images/aes-tree.png", width: 50%),
  caption: "Mentions of AES in the symbol tree",
)

#pagebreak()

The next step from there was to locate where the game reads the save file. Being a Windows game, I assumed the game would use the `ReadFile` WinAPI. Using Ghidra, we can easily locate where the `ReadFile` WinAPI is being used in the executable. We can indeed see the game imports the function from `kernel32.dll` and is available at `0x140d08781`.

#figure(
  image("images/read-file-winapi.png", width: 50%),
  caption: "Dark Souls Remastered importing kernel32",
)

Now that we know where the game attempts to read files, the next step is to find out at runtime when it tries to read the save file specifically and then go up the call stack to hopefully find where the game decrypts the data.

#pagebreak()

= Cheat Engine

In order to inspect the game's memory and code execution at runtime, I've installed and configured #gls("ce"), a popular reverse engineering tool. In order to get it working properly on Linux, I've used the ProtonTricks#footnote("https://protontricks.com/") project in order to properly run CE in the right Wine prefix.

However, once Cheat Engine was up and running, I faced a new problem unique to #gls("dsr"): anti debug measures. Indeed, when trying to attach a debugger to the process, the game would crash a few seconds later. This is of course intentional and meant to make my life more difficult.

Thanks to the thriving modding community and the aptly named `?WikiName?`#footnote("https://www.soulsmodding.com") modding wiki, I found a project that managed to bypass these anti debugging measures, an anti-anti debugging library if you will. The project is called `dearxan` and is available on Github#footnote("https://github.com/tremwil/dearxan") and can be used as a C library by cloning the repository, including `dearxan.h` and calling `dearxan_neuter_arxan()` from my dll before any of the game's code could run.

I also needed to compile dearxan from source targetting `x86_64-pc-windows-gnu` as the compiled binaries assumed a Windows environment and produced linking issues when compiled using MinGW on my Linux machine.

#figure(
  image("images/debugger.png", width: 75%),
  caption: "Cheat Engine attached to Dark Souls Remastered",
)

However, despite going through all these efforts to setup #gls("ce"), I ended up not using it as the UI is very clunky on Linux. Also, in order for Cheat Engine, running inside of Wine, to see Dark Souls Remastered's process, also running in Wine, both programs need to run in the same Wine prefix. This is easily done but the problem is that Steam uses the presence of any program inside the prefix to detect if the game is running.

This means if the game crashes, for example because of a logic error on my `dinput8.dll`, in order to restart the game I also need to restart #gls("ce"), making its usage very tedious. This is why moving forward, I've been using my dll exclusively to reverse engineer the game at runtime.

#pagebreak()

= Detouring ReadFile via IAT Patching

Instead of using Cheat Engine to analyse what the game is reading using the WinAPI `ReadFile`, we're going to write a detour using our `dinput8.dll` file. A detour consists of finding the pointer to the real `ReadFile` function, replacing it with a pointer to our own function that will log the arguments and proxy the real `ReadFile` call to preserve the functionality. This is done by patching the Import Address Table, or #gls("iat")#footnote("https://www.ired.team/offensive-security/code-injection-process-injection/import-adress-table-iat-hooking"). The #gls("iat") is a region in memory which lists pointers to imported functions, such as `ReadFile` which comes from `kernel32`.

#figure(
  image("images/iat.png", width: 75%),
  caption: "Example of ReadFile being detoured",
)

#pagebreak()

With such a detour function, we can now log everything whenever the game tries to read the save file, which happened to be a file ending with the `sl2` extension.

```c
static void log_callstack(void) {
  void *stack[32];
  USHORT frames = RtlCaptureStackBackTrace(0, 32, stack, NULL);
  uintptr_t base = (uintptr_t)GetModuleHandleA(NULL);

  for (USHORT i = 0; i < frames; i++) {
    uintptr_t addr = (uintptr_t)stack[i];
    DEBUG("  [%2d] +0x%llx\n", i, addr);
  }
}

DWORD is_sl2(HANDLE hFile) {
  char path[MAX_PATH];
  return GetFinalPathNameByHandleA(hFile, path, MAX_PATH,
                                   FILE_NAME_NORMALIZED) &&
         strstr(path, ".sl2");
}

static WINBOOL WINAPI detour_ReadFile(HANDLE hFile, LPVOID lpBuffer,
                                      DWORD nNumberOfBytesToRead,
                                      LPDWORD lpNumberOfBytesRead,
                                      LPOVERLAPPED lpOverlapped) {

  WINBOOL result = OrigReadFile(hFile, lpBuffer, nNumberOfBytesToRead,
                                lpNumberOfBytesRead, lpOverlapped);
  if (is_sl2(hFile)) {
    BYTE *buf = (BYTE *)lpBuffer;
    DEBUG("sl2 read %lu bytes: %02X %02X %02X %02X %02X %02X %02X %02X\n",
          *lpNumberOfBytesRead, buf[0], buf[1], buf[2], buf[3], buf[4], buf[5],
          buf[6], buf[7]);
    log_callstack();
  }

  return result;
}
```

#pagebreak()

By looking at the logs produced by the dll, we can notice a few interesting things. Most notably, the game seems to be reading 16 bytes at a time in multiple succession. This is very good as we assume the game is using #gls("aes") to encrypt the save file and that AES uses a chunk size of 16 bytes. We can therefore safely assume whatever piece of code repeatedly calling ReadFile 16 bytes at a time is decrypting the data on the fly. Finally, we can look at the call stack produced by one of the 16 bytes call to ReadFile and manually check in Ghidra in order to find where the AES decryption is happening.

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

Opening the first address in Ghidra shows what we're starting with.

```c
void FUN_ReadSaveFile(longlong param_1,LPVOID lpBuffer,DWORD nNumberOfBytesToRead, LPDWORD lpNumberOfBytesRead)

{
  ReadFile(*(HANDLE *)(param_1 + 0x60),lpBuffer,nNumberOfBytesToRead,lpNumberOfBytesRead,
           (LPOVERLAPPED)0x0);
  return;
}
```

By manually analysing the call stack, I managed to get all the way up to 0x140db35cd, a function with a `while(true)` loop repeatedly calling functions in the stack. This seems to be a clear indication that we are indeed in a function decrypting AES 16 bytes at a time. I ended up being stuck there, not able to understand where the potential AES key was coming from.

#pagebreak()

= AI to the rescue

So far, all the work was done by hand without the help of AI. This is not for the lack of trying but in such niche scenarios, AI was just not able to produce working code reliably, at least in my experience using Claude Sonnet 4.6. Now that I know where to look however, one use case where AI could be very useful is deciphering obfuscated C code produced by Ghidra. Indeed, while Ghidra can output human readable C code based on the assembly it finds, it's still very hard to grasp higher level concepts.

To get AI to help without having to copy and paste C code into Claude, I've setup an #gls("mcp") plugin for Ghidra#footnote("https://github.com/LaurieWired/GhidraMCP"), plugin created by LaurieWired, a great YouTuber with awesome low level videos#footnote("https://www.youtube.com/@lauriewired"). #gls("mcp") stands for Model Context Protocol#footnote("https://en.wikipedia.org/wiki/Model_Context_Protocol") and is a protocol that allows AI to interact with external programs via an API. That way, once setup, I can share my finding with Claude and the AI can then directly control Ghidra to, for example, disassemble code it wishes to read, as seen for example here where Claude decides to take a look at `FUN_1410c3db0`.

```
$ Good. The patch offset is wrong. Let me disassemble FUN_1410c3db0 to find the actual location of the SETNZ AL.

  Called ghidra (ctrl+o to expand)

$ Found it. The patch address is definitely correct — SETNZ AL is at 0x1410c446f, immediately followed by MOV byte ptr [RBX + 0xa0], AL at 0x1410c4472. The patch bytes are right too.
```

#pagebreak()

= Extracting the AES Key

After some efforts from Claude, it suggested that the AES key could be located at `[DarkSoulsRemastered.exe+0x1d053c0]+0x90`. In order to extract the key, I added the following code to the dll.

```c
void read_key() {
  uintptr_t base = (uintptr_t)GetModuleHandleA(NULL);
  uintptr_t *config_ptr = (uintptr_t *)(base + 0x1d053c0);
  if (*config_ptr) {
    BYTE *key = (BYTE *)(*config_ptr + 0x90);
    DEBUG("AES key: %02X%02X%02X%02X %02X%02X%02X%02X %02X%02X%02X%02X "
          "%02X%02X%02X%02X\n",
          key[0], key[1], key[2], key[3], key[4], key[5], key[6], key[7],
          key[8], key[9], key[10], key[11], key[12], key[13], key[14], key[15]);
  }
}
```

Of course this could be wrong, but looking at the log the key shown was very peculiar.

```
[CAPITAINE] AES key: 01234567 89ABCDEF FEDCBA98 76543210
```

Yes, you're seeing this correctly, the potential key seems to be numbers from 0 to F and back to 0. This value seemed so stupid it actually gave me confidence this would be the correct one.

#pagebreak()

= Testing the key using C\#

In order to use the key, I have written some code in C\# instead of regular C I have been using so far. The reason for this being that C does not provide a standard way of using AES while C\# does. I'm also familiar with modding Dark Souls using C\# as I have already written Dark Souls mods in the past in that language.

```cs
Aes encryptor = Aes.Create();
encryptor.Mode = CipherMode.CBC;
encryptor.Padding = PaddingMode.None;

byte[] cipherBytes = new byte[AES_BLOCK_SIZE * 2];

var handle = File.OpenHandle(path);
using (BinaryReader reader = new BinaryReader(new FileStream(handle, FileAccess.Read)))
{
    reader.BaseStream.Seek(HEADER_SIZE + (slot * SLOT_SIZE) + READ_OFFSET, SeekOrigin.Begin);
    reader.Read(cipherBytes, 0, AES_BLOCK_SIZE * 2);
}

byte[] aesKey = new byte[AES_BLOCK_SIZE];
Array.Copy(AES_KEY, 0, aesKey, 0, AES_BLOCK_SIZE);
encryptor.Key = aesKey;
encryptor.IV = cipherBytes.Take(AES_BLOCK_SIZE).ToArray();

MemoryStream memoryStream = new MemoryStream();
ICryptoTransform aesDecryptor = encryptor.CreateDecryptor();
CryptoStream cryptoStream = new CryptoStream(memoryStream, aesDecryptor, CryptoStreamMode.Write);
byte[] plainBytes;

try
{
    cryptoStream.Write(cipherBytes, AES_BLOCK_SIZE, AES_BLOCK_SIZE);
    cryptoStream.FlushFinalBlock();
    plainBytes = memoryStream.ToArray();
}
finally
{
    memoryStream.Close();
    cryptoStream.Close();
}

return BitConverter.ToInt32(plainBytes, IGT_BLOCK_OFFSET);
```

#pagebreak()

With this code, we can see we're only reading 32 bytes in the file as in this example, we're only trying to read the in-game time, which is a 4-byte value. We therefore only need to read the 16 bytes before the chunk the in-game time is in to use as the IV and the following 16 bytes in which the in-game time is.

#figure(
  image("images/aes-read.png", width: 75%),
  caption: "Dotnet successfully reads In-Game Time from the save file by decrypting using AES",
)

With this, we can successfully read the in-game time, despite the save file being encrypted with AES, bypassing the security altogether.

== Improving decryption performance

In a previous implementation of the decrypting of the save file#footnote("https://github.com/CapitaineToinon/LiveSplit.DarkSoulsIGT/blob/master/LiveSplit.DarkSoulsIGT/SL2Reader.cs"), I had wrongly assumed that the entire save file was encrypted at once using AES. However while manually reverse engineering the AES key, it was clear that some parts of the save file were not encrypted at all, such as the first 704 bytes for example containing some header information, and the actual character data read 16 bytes at a time for a total of 0x60030 bytes instead. This means that the old implementation was reading way too much data, making the process unnecessarily slower.

Also, even if a character is 0x60030 bytes big, if the data we actually care about is less than 16 bytes big, we can read that value by only reading 32 bytes: the 16 bytes before the chunk we care about as the IV and the actual 16 bytes of data. This is the case for the LiveSplit#footnote("https://livesplit.org/") in-game time plugin, which only cares about the time elapsed for a given character, time stored at a 32 bits signed integer.

Creating a new implementation that computed which chunk the in-game time is, open the file, seeks to the correct offsets, reads 32 bytes and decrypts that not only works, but is also much faster than the old implementation that would read the entire file instead. Neat!

```
1000 iterations each:
Old: 5264ms total, 5265.0µs/iter
New: 10ms total, 10.5µs/iter
```

#pagebreak()

= Conclusion

As demonstrated in this report, we managed quite easily to work around the encryption in place in #gls("dsr") by statically analysing the code using Ghidra, inspecting the game's memory by using Cheat Engine and injecting code by proxying DirectInput 8, allowing us to extract the AES key that was embedded inside the executable. Once the key is extracted, we can now encrypt and decrypt save files as we desire, predictably and completely nullifying the security introduced by this change.

This highlights a fundamental limitation of client-side encryption: when the application must be able to decrypt the data on its own, the key is necessarily accessible to anyone with access to the binary, which in the case of a commercial game means every single player. The encryption therefore provides no real confidentiality guarantee and only serves to raise the technical bar for casual inspection. In practice, recovering the key enabled a concrete improvement to the LiveSplit#footnote("https://livesplit.org/") in-game timer plugin for #gls("dsr") speedruns, reducing the time needed to read a character's in-game time by reading and decrypting only the 32 bytes relevant to the timer, rather than the entire save file.

#pagebreak()

= Sources

#set par(hanging-indent: 2em)

[1] FromSoftware. _FromSoftware Official Website_. #link("https://www.fromsoftware.jp")

[2] QLOC. _QLOC Official Website_. #link("https://q-loc.com/")

[3] Valve Corporation. _Steam_. #link("https://store.steampowered.com/")

[4] Wikipedia. _Proton (software)_. #link("https://en.wikipedia.org/wiki/Proton_(software)")

[5] MinGW-w64 Project. _MinGW-w64_. #link("https://www.mingw-w64.org/")

[6] ProtonTricks. _ProtonTricks_. #link("https://protontricks.com/")

[7] tremwil. _dearxan — anti-anti-debug library for Dark Souls_. #link("https://github.com/tremwil/dearxan")

[8] LaurieWired. _GhidraMCP_. #link("https://github.com/LaurieWired/GhidraMCP")

[9] LaurieWired. _LaurieWired on YouTube_. #link("https://www.youtube.com/@lauriewired")

[10] Wikipedia. _Model Context Protocol_. #link("https://en.wikipedia.org/wiki/Model_Context_Protocol")

[11] ired.team. _Import Address Table (IAT) Hooking_. #link("https://www.ired.team/offensive-security/code-injection-process-injection/import-adress-table-iat-hooking")

[12] Dark Souls Modding Wiki. _SL2 File Format_. #link("https://www.soulsmodding.com/doku.php?id=format:sl2")

[13] HackMD. _Speedrunning Souls Games on Linux_. #link("https://hackmd.io/VaKWRwy8ScKjU_d-107nZw")

[14] picoCTF Solutions. _Introduction to Ghidra_. #link("https://picoctfsolutions.com/posts/ghidra-reverse-engineering")

[15] CapitaineToinon. _dsr-savefiles — source code for this project_. #link("https://github.com/CapitaineToinon/dsr-savefiles")

[16] LiveSplit. _LiveSplit_. #link("https://livesplit.org/")

[17] NSA / Cybersecurity and Infrastructure Security Agency. _Ghidra_. #link("https://ghidra-sre.org/")

#pagebreak()

= Glossary

#print-glossary(glossary)
