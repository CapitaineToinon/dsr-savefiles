# DSR Savefile Encryption Research

Reverse engineering project investigating the AES encryption used in Dark Souls Remastered (DSR) save files (`.sl2`). The goal was to understand the save file format well enough to read the in-game timer (IGT) directly from disk without launching the game.

## Overview

DSR encrypts save slots using AES-CBC with a hardcoded key (`0123456789ABCDEFFEDCBA9876543210`). Each slot is stored sequentially in the `.sl2` file after a 704-byte (0x2C0) plain-text header. Reading the IGT only requires decrypting 32 bytes from the start of a slot.

## Repository structure

```
src/           C source for the injected DLL (dinput8 proxy)
sl2-igt/       C# example that reads IGT from the .sl2 file
dearxan/       Arxan anti-tamper disabler library (submodule)
scripts/       Helper shell scripts for running the game with logging
images/        Screenshots and diagrams from the research process
notes.typ      Research journal / reverse engineering notes
report.typ     Write-up of findings
```

## How it works

### DLL injection via dinput8 proxy

The game loads `DINPUT8.dll` from its own directory before the system one, so dropping a custom DLL there is enough to inject code. `src/dinput8.c` proxies `DirectInput8Create` to the real system DLL so the game keeps working normally.

### Anti-tamper bypass (Arxan / GuardIT)

DSR uses Arxan to detect debuggers and verify code integrity. The [dearxan](https://github.com/tremwil/dearxan) library is used to neuter these checks at runtime before any hooks are installed.

### IAT hook on ReadFile

`src/iat.c` patches the Import Address Table entry used by the call site at `DarkSoulsRemastered.exe+D08781` to redirect `ReadFile` through a detour. On each call the detour attempts to read the AES key (once), and logs the first 8 bytes plus a callstack for any `.sl2` read.

### AES key extraction

The AES key lives at `[base+0x1D053C0]+0x90`. The detour logs it on the first `.sl2` read. The key turned out to be the trivial sequence `01234567 89ABCDEF FEDCBA98 76543210`.

### Reading IGT from the save file

`sl2-igt/Program.cs` reads exactly 32 bytes from the correct slot offset and decrypts one AES block (CBC mode, IV = preceding block). The IGT value is a 32-bit integer at offset `0xC` inside the decrypted block. This is ~1000x faster than decrypting the entire file.

```
File layout (per slot):
  0x000000              Header (0x2C0 bytes, plaintext)
  0x0002C0 + slot*SLOT_SIZE  Slot start
    +0x00  IV block (16 bytes, ciphertext)
    +0x10  First data block (16 bytes, ciphertext)
           -> decrypt with AES-CBC(key, IV) -> plaintext
           -> IGT at plaintext[0xC] (uint32, milliseconds)
```

## Building the DLL

Cross-compilation from Linux using `mingw-w64`:

```sh
# Build dearxan first (requires Rust with the windows-gnu target)
cd dearxan && cargo build --release --target x86_64-pc-windows-gnu --features ffi

# Build the DLL
make build

# Install directly into the game directory and relaunch
make install
```

## Running on Linux

All development was done on Linux with the game running under Proton.

Requirements:
- Steam + Proton
- `mingw-w64-gcc` for cross-compilation
- Rust (target `x86_64-pc-windows-gnu`)
- Ghidra for static analysis
- Cheat Engine (via protontricks) for dynamic analysis

Enable Proton logging by adding `PROTON_LOG=1 %command%` as Steam launch options, then use `scripts/game_output.sh` to follow the log. The DLL also writes to `capitaine.log` inside the Proton prefix (`C:\users\steamuser\...`).

## Key findings

| Item | Value |
|------|-------|
| AES mode | CBC |
| Key size | 128-bit |
| Key | `0123456789ABCDEFFEDCBA9876543210` |
| Header size | 0x2C0 bytes (plaintext) |
| Slot size | 0x060030 bytes |
| IGT offset in decrypted block | 0xC |
| AES key address | `[base+0x1D053C0]+0x90` |
| ReadFile call site | `base+0xD08781` |
