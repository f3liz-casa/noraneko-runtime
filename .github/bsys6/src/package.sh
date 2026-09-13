#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Package Noraneko browser
set -eu

source $BSYS6/exports/target.sh
source $BSYS6/exports/require_build.sh

echo "-> Running 'mach package'" >&2

# aarch64 ホストの mac は dmg 道具が無いので TAR(mozconfig の export は mach package に届かないことがあるので env で)
if [ "$TARGET" == "macos" ] && [ "$(uname -m)" == "aarch64" ]; then
  export MOZ_PKG_FORMAT=TAR
fi
(cd $SOURCE && ./mach package)

if [ "$TARGET" == "windows" ]; then
  source $BSYS6/exports/move_artifact.sh "PACKAGE" "$SOURCE/obj-$MOZ_TARGET/dist" "$PROJECT_NAME-*.win64.zip"
elif [ "$TARGET" == "macos" ]; then
  if [ "$(uname -m)" == "aarch64" ]; then
    # aarch64 ホスト(dmg 道具なし): MOZ_PKG_FORMAT=TAR の staging(noraneko/Noraneko.app、symlink 無し)を xz で
    dist="$SOURCE/obj-$MOZ_TARGET/dist"
    mactar="$(ls "$dist"/$PROJECT_NAME-*.mac.tar 2>/dev/null | head -n1 || true)"
    [ -n "$mactar" ] || { echo "Error: no *.mac.tar in $dist (MOZ_PKG_FORMAT=TAR?)" >&2; exit 1; }
    xz -T0 -6 -c "$mactar" > "$dist/$PROJECT_NAME-macos-$ARCH-moz-artifact.tar.xz"
    source $BSYS6/exports/move_artifact.sh "PACKAGE" "$dist" "$PROJECT_NAME-macos-*.tar.xz"
  else
    source $BSYS6/exports/move_artifact.sh "PACKAGE" "$SOURCE/obj-$MOZ_TARGET/dist" "$PROJECT_NAME-*.dmg"
  fi
else
  source $BSYS6/exports/move_artifact.sh "PACKAGE" "$SOURCE/obj-$MOZ_TARGET/dist" "$PROJECT_NAME-*.tar.xz"
fi
