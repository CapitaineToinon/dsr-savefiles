My journey working on reverse engineering Dark Souls Remastered savefile encryption.

== Useful links

- How to speedrun souls games on Linux: https://hackmd.io/VaKWRwy8ScKjU_d-107nZw
- How to use ghidra: https://picoctfsolutions.com/posts/ghidra-reverse-engineering
- me3 (not used in the end): https://me3.help/en/latest/
- Anti anti debug for DSR: https://github.com/tremwil/dearxan

== Linux

I'm doing all of this on Linux despite DSR being a Windows game. Stuff I need:

- Steam
- Proton Tricks
- Cheat Engine (via protontricks)
- Ghidra
- mingw-w64-gcc to compile windows c code on linux
- me3 to bypass anti anti debugger for FROMSOFTWARE games https://me3.help/en/latest/
- actually me3 is no good, dearxan is working though

== Debug game output

- To see the game output, add `PROTON_LOG=1 %command%` as launch options and view the output with the `game_output.sh` scripts.
- Also have a debug macro that writes to a file in the prefix C drive, `capitaine.log`

== Simple DLL using dinput8

Got a simple dll to be loaded by the game, compiled a dllmain that is a simple wrapper around dinput8 to be able to inject code to, in the future, disable savefile encryption entirely.

== Debugger nightmare

Turns out DSR has anti debug, meaning I can't attach the debugger to the game using Cheat Engine. It should be possible to bypass that with dearxan but can't get it to work right now:

- Can't compile msvc on linux, missing some symbols
- Even with stubs, doesn't work

Skipping anti-anti debug for now.

Update: thanks to people on the modding discord, including the creator of deaxran, I managed to get it working:

- Need to compile from source using cargo for target windows-gnu, with feature ffi
- Link that lib instead
- Also link libc

== Find the code using Ghidra

Using ghidra to decompile, we can try to find where the game saves and read savefiles.

=== WriteFile, ReadFile

My first instinct, trying to find where the game uses windows APIs to read and write files to disk.

- Seems like ReadFile reads the savefile at DarkSoulsRemastered.exe+D08781
- Seems like FROM is using its own AES implementation, not symbols for obvious third party library
- Managed to detour ReadFile by patching the iat table

== Looking for AES stuff

- There are a lot of AES entries in a vtable, need to find out where it's used.
- Found what looks like an encryption factory, could be useful to find out which method is used for the savefile

== SL2 format

- I used to think the entire savefile was encrypted, but clearly when looking at a savefile in hex we can see the header of the file is in plain text, meaning that save slots are probably encrpted seperately.
- This is also clear looking at the hooked ReadFile calls. One call reads 704 bytes (0x2c0) which is the size of the header
- It then reads 16 bytes many many times, implying it's decrypting block by block
- However the old code works, which implies I might be able to read IGT by only reading 32 bytes

Update:
- Rewrote the SL2 reading to only read 32 bytes, 1000x speedup!
- Added C\# example code

== Looking at 16 bytes call stack

- Looking at the call stack when ReadFile is called reading 16 bytes (probably decrypting something)

[CAPITAINE] sl2 read 16 bytes: 1B 4A 57 81 19 EC 05 4C  : starting bytes of the save slot
[CAPITAINE]   [ 0] +0x6ffffc9e17d3                      : where my detour function lives
[CAPITAINE]   [ 1] +0x140d08787                         : a thin wrapper around ReadFile (unknown struct as argument with FILE handle at +0x60)
[CAPITAINE]   [ 2] +0x140d0560b                         : a streaming code, probably checks if stream is still open, then keep advancing by moving the file handle
[CAPITAINE]   [ 3] +0x140cf3758                         : a wrapper around DLFileInputStream.cpp, that dynamically calls the other codes
[CAPITAINE]   [ 4] +0x140d027a4                         : a wrapper around the above function, with boundery checking. Skipping a few...
[CAPITAINE]   [ 5] +0x140d027a4
[CAPITAINE]   [ 6] +0x140d0dcb2
[CAPITAINE]   [ 7] +0x140d0bfe0
[CAPITAINE]   [ 8] +0x140cf3758
[CAPITAINE]   [ 9] +0x140db35cd                         : HIT GOLD, function that seems to call AES in a loop
[CAPITAINE]   [10] +0x1410da1fa
[CAPITAINE]   [11] +0x1410d84e4
[CAPITAINE]   [12] +0x1410d0800
[CAPITAINE]   [13] +0x1410c4ffa
[CAPITAINE]   [14] +0x1410ce1c2
[CAPITAINE]   [15] +0x140cce31f
[CAPITAINE]   [16] +0x6fffff9610fb
[CAPITAINE]   [17] +0x6fffffec0ca9
[CAPITAINE]   [18] +0x6ffffff3fbaf

- Found something at FUN_140db3500!
- A do...while(true) look that calls the stack, hardcoded 0x10 everyone (AES BLOCK SIZE).
- Calls FUN_140db5c70 which does bitwise operations, seems to be the actual decrypting

== Using Ghidra MCP to keep going

- Installed Ghidra MCP https://github.com/LaurieWired/GhidraMCP
- Going up in Ghidra can only do so much, eventually hit code that looks obfuscated, just get the value from memory instead
- Managed to write a detour to read the AES KEY at [0x1d053c0]+0x90
- Hilariously, the key is  01234567 89ABCDEF FEDCBA98 7654321

== Same thing but for WriteFile

[CAPITAINE] sl2 written 393264 bytes: D1 CD CB 3A 1F 2C 96 62
[CAPITAINE]   [ 0] +0x6ffffc9e1693
[CAPITAINE]   [ 1] +0x6ffffc9e17dc
[CAPITAINE]   [ 2] +0x140d05714                         : Calls WriteFile
[CAPITAINE]   [ 3] +0x140cf3ec7
[CAPITAINE]   [ 4] +0x1410d7111
[CAPITAINE]   [ 5] +0x1410cfe09
[CAPITAINE]   [ 6] +0x1410c4ffa
[CAPITAINE]   [ 7] +0x1410ce1c2
[CAPITAINE]   [ 8] +0x140cce31f
[CAPITAINE]   [ 9] +0x6fffff9610fb
[CAPITAINE]   [10] +0x6fffffec0ca9
[CAPITAINE]   [11] +0x6ffffff3fbaf

