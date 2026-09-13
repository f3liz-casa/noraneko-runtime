#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Prepare build environment for Noraneko
set -eu

source $BSYS6/exports/target.sh

# LLVM version to install
LLVM_VERSION="${LLVM_VERSION:-20}"

# Function to install LLVM on Debian/Ubuntu
install_llvm() {
  if command -v apt-get &> /dev/null; then
    echo "-> Installing LLVM/Clang $LLVM_VERSION"
    
    # Detect the distribution codename
    if [ -f /etc/os-release ]; then
      . /etc/os-release
      case "$ID" in
        ubuntu)
          case "$VERSION_CODENAME" in
            noble) LLVM_CODENAME="noble" ;;
            jammy) LLVM_CODENAME="jammy" ;;
            focal) LLVM_CODENAME="focal" ;;
            *) LLVM_CODENAME="jammy" ;;  # Default to jammy for unknown Ubuntu versions
          esac
          ;;
        debian)
          case "$VERSION_CODENAME" in
            trixie) LLVM_CODENAME="unstable" ;;
            bookworm) LLVM_CODENAME="bookworm" ;;
            bullseye) LLVM_CODENAME="bullseye" ;;
            *) LLVM_CODENAME="bookworm" ;;  # Default to bookworm for unknown Debian versions
          esac
          ;;
        *)
          # For other distros, try lsb_release
          LLVM_CODENAME=$(lsb_release -cs 2>/dev/null || echo "jammy")
          ;;
      esac
    else
      LLVM_CODENAME="jammy"  # Fallback default
    fi
    
    echo "   Using LLVM repository for: $LLVM_CODENAME"
    wget -qO- https://apt.llvm.org/llvm-snapshot.gpg.key | sudo gpg --dearmor -o /etc/apt/trusted.gpg.d/llvm.gpg || true
    echo "deb http://apt.llvm.org/$LLVM_CODENAME/ llvm-toolchain-$LLVM_CODENAME-$LLVM_VERSION main" | sudo tee /etc/apt/sources.list.d/llvm.list || true
    sudo apt-get update -qq
    sudo apt-get install -y --no-install-recommends "llvm-$LLVM_VERSION" "clang-$LLVM_VERSION" "lld-$LLVM_VERSION" "libclang-$LLVM_VERSION-dev" "libclang-rt-$LLVM_VERSION-dev-wasm32" || true

    # Create symlinks for the specific LLVM version
    sudo ln -sf "/usr/bin/clang-$LLVM_VERSION" /usr/bin/clang
    sudo ln -sf "/usr/bin/clang++-$LLVM_VERSION" /usr/bin/clang++
    sudo ln -sf "/usr/bin/lld-$LLVM_VERSION" /usr/bin/lld
    sudo ln -sf "/usr/bin/llvm-profdata-$LLVM_VERSION" /usr/bin/llvm-profdata
  fi
}

case $TARGET in

linux)
  echo "-> Preparing build environment for Linux (target: $TARGET, arch: $ARCH)"

  # Install base dependencies
  $BSYS6/utils/dependencies.sh "python3-pip curl gnupg2 jq build-essential autoconf2.13 yasm libgtk-3-dev libxtst6 libxrandr2 libasound2-dev libpango1.0-dev libatk1.0-dev libcairo-gobject2 libgdk-pixbuf2.0-dev libdbus-glib-1-dev xvfb mesa-utils msitools wget lsb-release" "python-pip curl gnupg jq base-devel autoconf yasm gtk3 libxtst libxrandr alsa-lib pango atk cairo gdk-pixbuf2 dbus-glib xorg-server-xvfb mesa msitools wget"

  # Install LLVM/Clang
  install_llvm

  # Cross-compilation dependencies (x86_64 ホストから aarch64 を焼くときだけ。
  # native aarch64 ホストには cross パッケージが無い/不要)
  if [ "$ARCH" == "aarch64" ] && [ "$(uname -m)" != "aarch64" ]; then
    $BSYS6/utils/dependencies.sh "gcc-aarch64-linux-gnu g++-aarch64-linux-gnu binutils-aarch64-linux-gnu" "aarch64-linux-gnu-gcc aarch64-linux-gnu-binutils"
  fi

  # Bootstrap mach
  source $BSYS6/exports/version.sh
  $BSYS6/bootstrap.sh

  # Add Rust targets
  $BSYS6/utils/rustup_target.sh "x86_64-unknown-linux-gnu" "aarch64-unknown-linux-gnu"
  ;;

windows)
  echo "-> Preparing build environment for Windows cross-compilation (target: $TARGET)"

  # build-essential は make(mach が gmake を探す)のため。linux の一覧には元からあり、素の ubuntu コンテナには無い
  $BSYS6/utils/dependencies.sh "python3-pip curl msitools zstd libc6-i386 p7zip-full jq zip unzip wget mono-complete gettext-base pkg-config wine64 lsb-release gnupg2 build-essential" "python-pip curl msitools zstd lib32-glibc p7zip jq zip unzip wget mono gettext pkgconf wine base-devel"

  # Install LLVM/Clang
  install_llvm

  source $BSYS6/exports/version.sh
  $BSYS6/bootstrap.sh

  # Add Windows Rust targets
  $BSYS6/utils/rustup_target.sh "x86_64-pc-windows-msvc" "aarch64-pc-windows-msvc" "i686-pc-windows-msvc"
  ;;

macos)
  echo "-> Preparing build environment for macOS cross-compilation (target: $TARGET)"

  # Install base dependencies
  $BSYS6/utils/dependencies.sh "python3-pip curl rsync zip unzip python3-testresources jq file nodejs wget lsb-release gnupg2 build-essential" "python-pip curl rsync zip unzip python-testresources jq nodejs wget base-devel"

  # Install LLVM/Clang
  install_llvm

  source $BSYS6/exports/version.sh
  $BSYS6/bootstrap.sh

  # Add macOS Rust targets
  $BSYS6/utils/rustup_target.sh "x86_64-apple-darwin" "aarch64-apple-darwin"

  # Install macOS specific toolchain artifacts
  # ホストの arch で fetch する物を変える。x86_64 は従来どおり。
  # aarch64 ホスト用には linux64-aarch64-{clang,cbindgen} が公式にある。
  # dmg/cctools/hfsplus/binutils に aarch64 版は無い(dmg は焼かず tar で出す)。
  if [ "$(uname -m)" == "aarch64" ]; then
    $BSYS6/utils/install_toolchain_artifact.sh "sysroot-wasm32-wasi" "linux64-aarch64-cbindgen" "linux64-aarch64-clang"
  else
    $BSYS6/utils/install_toolchain_artifact.sh "sysroot-wasm32-wasi" "linux64-cbindgen" "linux64-clang" "linux64-libdmg" "linux64-cctools-port" "linux64-hfsplus" "linux64-binutils"
  fi

  # Install macOS SDK
  $BSYS6/utils/install_macos_sdk.sh
  ;;

*)
  echo "Cannot prepare build environment for target '$TARGET'"
  exit 1
  ;;
esac

echo "-> Build environment prepared successfully" >&2
