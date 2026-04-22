My journey working on reverse engineering Dark Souls Remastered savefile encryption.

== Useful links

- How to speedrun souls games on Linux: https://hackmd.io/VaKWRwy8ScKjU_d-107nZw
- How to use ghidra: https://picoctfsolutions.com/posts/ghidra-reverse-engineering
- me3: https://me3.help/en/latest/
- Anti anti debug for DSR: https://github.com/tremwil/dearxan

== Linux

I'm doing all of this on Linux despite DSR being a Windows game. Stuff I need:

- Steam
- Proton Tricks
- Cheat Engine (via protontricks)
- Ghidra
- mingw-w64-gcc to compile windows c code on linux
- me3 to bypass anti anti debugger for FROMSOFTWARE games https://me3.help/en/latest/
- actually me3 is no good, deaxran is working though

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
- Managed to detour ReadFile!
