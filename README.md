# GDB (GNU Debugger)

Precompiled portable GDB binaries for Linux and Android.

## Features

* Both `libgcc` and `libstdc++` are bundled within the Linux packages.
* Android packages target API level 21 and statically link the GCC runtime and required third-party libraries.
* Target older OS releases (increases compatibility).

## Android

The Android packages contain native GDB binaries for Android 5.0 (API level 21) and later, built with [android-gcc-cross](https://github.com/AmanoTeam/android-gcc-cross). Packages are available for all four primary Android architectures:

* `aarch64-unknown-linux-android21` (ARM64)
* `armv7-unknown-linux-androideabi21` (ARMv7)
* `i686-unknown-linux-android21` (x86)
* `x86_64-unknown-linux-android21` (x86-64)

## Downloads

You can obtain releases from the [releases](https://github.com/AmanoTeam/GDB-Builds/releases) page.
