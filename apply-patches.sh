#!/bin/bash

# submodules
git apply patches/0001-patch-to-work.patch --directory=libs/zig-serve/ 
git apply patches/0001-regex-zig-0.10-compat.patch --directory=libs/zig-regex/

# zigmod
git apply patches/0001-wolfssl-changes-to-work.patch --directory=libs/zig-serve/vendor/wolfssl
git apply patches/0001-uri-patches-to-work.patch --directory=libs/zig-serve/vendor/uri
git apply patches/0001-sqlite-patches-to-work.patch --directory=.zigmod/deps/git/github.com/vrischmann/zig-sqlite