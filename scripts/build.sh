#!/bin/zsh
# Builds Foglio.app (universal arm64 + x86_64): Rust core -> static lib, Swift/AppKit shell -> app bundle.
# Usage: scripts/build.sh [--arm64-only]
set -euo pipefail
ROOT=${0:A:h:h}
OUT=$ROOT/build
export PATH="/opt/homebrew/opt/rustup/bin:$HOME/.cargo/bin:$PATH"
ARCHS=(arm64 x86_64)
[[ "${1:-}" == "--arm64-only" ]] && ARCHS=(arm64)
MIN_OS=14.0
mkdir -p $OUT

libs=() bins=()
for arch in $ARCHS; do
  triple=$([[ $arch == arm64 ]] && echo aarch64-apple-darwin || echo x86_64-apple-darwin)
  echo "▸ Rust core ($arch)"
  MACOSX_DEPLOYMENT_TARGET=$MIN_OS cargo build --release --quiet --manifest-path $ROOT/core/Cargo.toml --target $triple
  libs+=$ROOT/core/target/$triple/release/libfoglio_core.a

  echo "▸ Swift app ($arch)"
  swiftc -O -wmo -swift-version 5 -module-name Foglio \
    -target $arch-apple-macos$MIN_OS \
    -import-objc-header $ROOT/app/Bridging.h \
    $ROOT/app/Sources/*.swift \
    -L $ROOT/core/target/$triple/release -lfoglio_core \
    -Xlinker -dead_strip \
    -o $OUT/Foglio-$arch
  bins+=$OUT/Foglio-$arch
done

APP=$OUT/Foglio.app
rm -rf $APP
mkdir -p $APP/Contents/MacOS $APP/Contents/Resources
lipo -create $bins -output $APP/Contents/MacOS/Foglio
strip -x $APP/Contents/MacOS/Foglio
cp $ROOT/app/Info.plist $APP/Contents/Info.plist
for lproj in $ROOT/app/Resources/*.lproj(N); do cp -R $lproj $APP/Contents/Resources/; done
[[ -f $ROOT/assets/Foglio.icns ]] && cp $ROOT/assets/Foglio.icns $APP/Contents/Resources/Foglio.icns
codesign --force --sign - $APP >/dev/null 2>&1
echo "✓ $APP"
lipo -info $APP/Contents/MacOS/Foglio
du -sh $APP
