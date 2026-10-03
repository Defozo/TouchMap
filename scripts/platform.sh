#!/usr/bin/env bash
set -euo pipefail

# Linux/WSL build host. The Windows wrappers pass paths as individual arguments.
action=${1:?doctor, build, install or emulator required}
repository=${2:?repository path required}
product=${3:-openharmonyApi20}
build_mode=${4:-debug}
tools_dir=${TOUCHMAP_TOOLS_DIR:-"$HOME/touchmap-toolchain"}
oniro="$tools_dir/node_modules/.bin/oniro-app"
export ONIRO_SDK_ROOT_DIR=${ONIRO_SDK_ROOT_DIR:-"$HOME/setup-ohos-sdk"}
export ONIRO_CMD_TOOLS_PATH=${ONIRO_CMD_TOOLS_PATH:-"$HOME/command-line-tools"}
export ONIRO_EMULATOR_DIR=${ONIRO_EMULATOR_DIR:-"$HOME/oniro-emulator"}
export PATH="$ONIRO_CMD_TOOLS_PATH/bin:$ONIRO_CMD_TOOLS_PATH/tool/ohpm/bin:$PATH"
test -x "$oniro" || { echo 'Missing Oniro CLI. Run scripts/setup-platform.ps1.' >&2; exit 2; }
hdc="$ONIRO_CMD_TOOLS_PATH/sdk/default/openharmony/toolchains/hdc"
if test -x "$hdc"; then
  python3 "$repository/scripts/start-hdc.py" "$hdc"
fi

case "$action" in
doctor)
  "$oniro" --version
  node --version
  java -version
  "$oniro" sdk list --json
  "$oniro" cmdtools status --json
  test -d "$ONIRO_SDK_ROOT_DIR/linux/20" || { echo 'SDK API 20 missing.' >&2; exit 3; }
  test -r /dev/kvm && test -w /dev/kvm || { echo 'KVM is not accessible for the emulator.' >&2; exit 4; }
  qemu-system-x86_64 --version | head -1
  "$hdc" tconn "${TOUCHMAP_HDC_TARGET:-127.0.0.1:55555}" >/dev/null 2>&1 || true
  devices=$("$oniro" devices --json)
  printf '%s\n' "$devices"
  printf '%s' "$devices" | python3 -c 'import json,sys; devices=json.load(sys.stdin); sys.exit(0 if any(d.get("status") == "Connected" for d in devices) else "No connected HDC target. Start the emulator or connect a device.")'
  ;;
build)
  test "$product" = openharmonyApi20 || { echo 'Unknown product.' >&2; exit 2; }
  test "$build_mode" = debug -o "$build_mode" = release || exit 2
  # The source tree never receives private signing configuration or keys.
  build_root=${TOUCHMAP_BUILD_ROOT:-"$HOME/.cache/touchmap-build"}
  mkdir -p "$build_root" "$repository/dist" "$repository/docs/evidence"
  build_dir=$(mktemp -d "$build_root/build-XXXXXXXX")
  tar -C "$repository/app" --exclude=build --exclude=.hvigor --exclude=oh_modules --exclude=local.properties -cf - . | tar -C "$build_dir" -xf -
  printf 'sdk.dir=%s/linux\n' "$ONIRO_SDK_ROOT_DIR" > "$build_dir/local.properties"
  "$oniro" sign "$build_dir" --bootstrap > "$build_dir/sign.log" 2>&1
  "$oniro" build "$build_dir" --product "$product" --mode "$build_mode" --json 2>&1 | tee "$repository/docs/evidence/native-build.log"
  hap=$(find "$build_dir/entry/build" -name '*-signed.hap' -type f -print -quit)
  test -n "$hap" || { echo 'Build returned no signed HAP.' >&2; exit 5; }
  java -jar "$ONIRO_SDK_ROOT_DIR/linux/20/toolchains/lib/hap-sign-tool.jar" verify-app -inFile "$hap" -outCertChain "$build_dir/verified-certificate.cer" -outProfile "$build_dir/verified-profile.p7b" > "$repository/docs/evidence/signature-verification.log" 2>&1
  cp "$hap" "$repository/dist/touchmap-signed.hap"
  cp "$build_dir/oh-package-lock.json5" "$repository/app/oh-package-lock.json5"
  python3 "$repository/scripts/verify-hap.py" "$repository/dist/touchmap-signed.hap" "$repository/docs/evidence/hap-metadata.json"
  sha256sum "$repository/dist/touchmap-signed.hap" | sed "s|$repository/dist/||" > "$repository/dist/SHA256SUMS"
  printf '%s\n' "$build_dir" > "$repository/.native-build-path"
  echo "Signed HAP: $repository/dist/touchmap-signed.hap"
  ;;
install)
  target=${3:?HDC target required}
  hap="$repository/dist/touchmap-signed.hap"
  test -f "$hap" || { echo 'Run scripts/build.ps1 first.' >&2; exit 5; }
  "$hdc" tconn "$target"
  "$oniro" app install "$repository/app" --hap "$hap" --device "$target"
  "$oniro" app launch "$repository/app" --ability EntryAbility --device "$target"
  "$oniro" wait --bundle org.touchmap.app --device "$target" --timeout 30000
  ;;
emulator)
  "$oniro" emulator start --headless --log "$repository/docs/evidence/emulator.log" --wait-for-hdc 60
  ;;
*) echo "Unsupported command: $action" >&2; exit 2 ;;
esac
