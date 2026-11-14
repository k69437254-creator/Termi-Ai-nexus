# Linux runtime third-party notices

This update packages the following ARM64 runtime components as separate executable/shared-object files. No PRoot application source code is copied into TermiAI-Nexus.

- **PRoot 5.1.107.89** and its loader binaries: Android-patched Termux PRoot build, GPL-2.0-or-later. Upstream source and build recipe: https://github.com/termux/proot/tree/v5.1.107.89 and https://github.com/termux/termux-packages/blob/master/packages/proot/build.sh.
- The binary files are obtained from the pinned source artifact revision https://github.com/Bentlybro/kern/tree/b73a2d67cd7573e5207a7ad6f37b0c9706652cb0/app/src/main/jniLibs/arm64-v8a. The upstream notice describes their Termux provenance and the one-name ELF dependency adjustment used for Android extraction.
- **talloc 2.4.3**: LGPL-3.0-or-later; source and license information: https://www.samba.org/ftp/talloc/.
- **libandroid-shmem 0.7**: BSD-3-Clause; source: https://github.com/termux/libandroid-shmem.
- **Ubuntu Base 24.04.5 ARM64** is downloaded on first setup from Canonical's official image host, not redistributed in this repository. Its archive SHA-256 is pinned in `LinuxRuntimeChannel.kt`; Canonical's release page and checksums are at https://cdimage.ubuntu.com/ubuntu-base/releases/24.04/release/.

SHA-256 values expected by the installer:

```text
7da118895e971ea9fba4bb250b28af0f8db2edcbfdbaa8075cc645a0d7cf16fe  libproot.so
44ef39c1e1a18c09f6e4c4b5d6f8bba82d30596598bd155ec162d05c5122ff04  libproot_loader.so
25f6bd90bc5a3d3088026289a0d3eaf3e502bd2b00e5cb74fadd9791132efa34  libproot_loader32.so
3c9b207c0a6ea2896b7523e03f55d9ab0d9e88baa115d4c32b84058ff4246fbb  libtalloc.so
84475798e07c8174dbbfaec70a827fdb02f19ffa69a589380c13e7507fd0e731  libandroid-shmem.so
```

The GitHub token remains in Android secure storage and is passed only to the active terminal process environment. The runtime does not write it to Ubuntu's home directory or Git credential files; the Git credential helper stored in the guest reads the session environment variable and only serves requests for `github.com`.
