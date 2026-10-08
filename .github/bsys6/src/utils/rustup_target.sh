#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Add Rust targets via rustup
set -eu

source $BSYS6/source.sh

# 木が要求する最小版に toolchain を固定する。新しすぎる stable(1.98)だと
# encoding_rs の unstable SIMD で割れた(2026-09、149 の木)。値は木から読む。
# RUST_VERSION を渡せば木の値より優先する(prepare.sh の macOS 行を参照)。
min="${RUST_VERSION:-$(sed -n 's/^MINIMUM_RUST_VERSION = "\(.*\)"/\1/p' "$SOURCE/python/mozboot/mozboot/util.py")}"
if [ -n "$min" ]; then
  echo "-> Pinning Rust toolchain to $min (tree MINIMUM_RUST_VERSION)"
  rustup toolchain install "$min" --profile minimal
  rustup default "$min"
fi

for target in "$@"; do
  echo "-> Adding Rust target: $target"
  rustup target add "$target" || true
done
