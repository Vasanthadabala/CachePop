#!/bin/bash
# Builds CachePop for Developer ID distribution: archives the app, exports it signed with your
# Developer ID, puts it in a disk image with an Applications shortcut, signs and notarizes the
# disk image and staples the ticket to it. The DMG lands in build/.
#
# One-time setup:
#   1. A "Developer ID Application" certificate in your keychain:
#      Xcode › Settings › Accounts › Manage Certificates › + › Developer ID Application.
#   2. Notary credentials in your keychain, under a profile name ("CachePop" by default):
#        xcrun notarytool store-credentials CachePop --apple-id <your Apple ID> --team-id 4R2U97FG78
#      It asks for an app-specific password (account.apple.com › Sign-In and Security).
#
# Usage:
#   scripts/make-dmg.sh                  signed, notarized and stapled: ready to share
#   scripts/make-dmg.sh --skip-notarize  signed with Developer ID but not notarized: other Macs refuse it
#   scripts/make-dmg.sh --dev            signed with your development certificate, to check the DMG on
#                                        this Mac before you have a Developer ID certificate
# Options:
#   --profile NAME   notarytool keychain profile (default: $CACHEPOP_NOTARY_PROFILE, else CachePop)
#   --output DIR     where the DMG and the archive go (default: build/)

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$ROOT/CachePop.xcodeproj"
SCHEME="CachePop"
APP_NAME="CachePop"
TEAM_ID="4R2U97FG78"
APP_ID="com.piggylabs.CachePop"
HELPER_ID="com.piggylabs.CachePop.FanHelper"

MODE="release"
PROFILE="${CACHEPOP_NOTARY_PROFILE:-CachePop}"
OUT="$ROOT/build"

while [ $# -gt 0 ]; do
    case "$1" in
        --skip-notarize) MODE="unnotarized" ;;
        --dev) MODE="dev" ;;
        --profile) PROFILE="${2:?--profile needs a name}"; shift ;;
        --output) OUT="${2:?--output needs a folder}"; shift ;;
        -h | --help) sed -n '2,23p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "Unknown option: $1 (see --help)" >&2; exit 64 ;;
    esac
    shift
done

step() { printf '\n==> %s\n' "$*"; }
fail() { printf '\nerror: %s\n' "$*" >&2; exit 1; }

# MARK: Checks that fail fast, before the long build

if [ "$MODE" != "dev" ]; then
    IDENTITY="$(security find-identity -v -p codesigning \
        | grep -o "\"Developer ID Application: [^\"]*($TEAM_ID)\"" | head -n 1 | tr -d '"' || true)"
    [ -n "$IDENTITY" ] || fail "No \"Developer ID Application\" certificate for team $TEAM_ID in your keychain.
Create one in Xcode › Settings › Accounts › Manage Certificates, or run with --dev to try the DMG on this Mac."
fi

if [ "$MODE" = "release" ]; then
    xcrun notarytool history --keychain-profile "$PROFILE" > /dev/null 2>&1 \
        || fail "No notary credentials in your keychain under the profile \"$PROFILE\". Save them once with:
  xcrun notarytool store-credentials $PROFILE --apple-id <your Apple ID> --team-id $TEAM_ID"
fi

mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
WORK="$OUT/work"
rm -rf "$WORK"
mkdir -p "$WORK"
ARCHIVE="$WORK/$APP_NAME.xcarchive"
APP="$WORK/export/$APP_NAME.app"

# MARK: Build

step "Archiving a Release build"
xcodebuild archive -quiet \
    -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
    -destination "generic/platform=macOS" \
    -archivePath "$ARCHIVE" -derivedDataPath "$WORK/DerivedData"

if [ "$MODE" = "dev" ]; then
    step "Taking the app as Xcode signed it (development certificate)"
    mkdir -p "$WORK/export"
    ditto "$ARCHIVE/Products/Applications/$APP_NAME.app" "$APP"
else
    step "Exporting with your Developer ID"
    cat > "$WORK/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string>$TEAM_ID</string>
    <key>signingStyle</key>
    <string>automatic</string>
</dict>
</plist>
EOF
    xcodebuild -exportArchive -quiet -allowProvisioningUpdates \
        -archivePath "$ARCHIVE" -exportOptionsPlist "$WORK/ExportOptions.plist" -exportPath "$WORK/export"
fi

# MARK: Check the signatures

step "Checking the signatures"
HELPER="$APP/Contents/MacOS/CachePopFanHelper"
[ -f "$HELPER" ] || fail "The fan helper is missing from the app."
[ -f "$APP/Contents/Library/LaunchDaemons/$HELPER_ID.plist" ] || fail "The fan helper's launchd plist is missing from the app."
codesign --verify --deep --strict "$APP" || fail "The app's signature doesn't verify."

# CachePop and its fan helper only talk to each other when both are signed by this team.
codesign --verify -R "=anchor apple generic and identifier \"$APP_ID\" and certificate leaf[subject.OU] = \"$TEAM_ID\"" "$APP" \
    || fail "The app isn't signed by team $TEAM_ID as $APP_ID, so the fan helper would refuse it."
codesign --verify -R "=anchor apple generic and identifier \"$HELPER_ID\" and certificate leaf[subject.OU] = \"$TEAM_ID\"" "$HELPER" \
    || fail "The fan helper isn't signed by team $TEAM_ID as $HELPER_ID, so CachePop would refuse it."

if [ "$MODE" != "dev" ]; then
    # What notarization needs: Developer ID, the hardened runtime, a secure timestamp, and no
    # debugging entitlement.
    DEVELOPER_ID="anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] exists and certificate leaf[field.1.2.840.113635.100.6.1.13] exists"
    for CODE in "$APP" "$HELPER"; do
        NAME="$(basename "$CODE")"
        codesign --verify -R "=$DEVELOPER_ID" "$CODE" || fail "$NAME isn't signed with a Developer ID certificate."
        DETAILS="$(codesign -dv "$CODE" 2>&1)"
        grep -q "flags=.*runtime" <<< "$DETAILS" || fail "$NAME doesn't have the hardened runtime."
        grep -q "^Timestamp=" <<< "$DETAILS" || fail "$NAME has no secure timestamp."
        if codesign -d --entitlements - --xml "$CODE" 2>/dev/null | grep -q "get-task-allow"; then
            fail "$NAME allows debugging (get-task-allow), which notarization rejects."
        fi
    done
fi

# MARK: Disk image

VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")"
DMG="$OUT/$APP_NAME-$VERSION.dmg"
[ "$MODE" = "dev" ] && DMG="$OUT/$APP_NAME-$VERSION-dev.dmg"

step "Making $(basename "$DMG")"
STAGE="$WORK/dmg"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/$APP_NAME.app"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -quiet -volname "$APP_NAME" -srcfolder "$STAGE" -fs HFS+ -format ULFO -ov "$DMG"

if [ "$MODE" != "dev" ]; then
    step "Signing the disk image"
    codesign --sign "$IDENTITY" --timestamp "$DMG"
    codesign --verify "$DMG" || fail "The disk image's signature doesn't verify."
fi

# MARK: Notarize

if [ "$MODE" = "release" ]; then
    step "Notarizing (usually a few minutes)"
    RESULT="$WORK/notarization.json"
    xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait --output-format json > "$RESULT" || true
    STATUS="$(plutil -extract status raw -o - "$RESULT" 2>/dev/null || echo "unknown")"
    if [ "$STATUS" != "Accepted" ]; then
        SUBMISSION="$(plutil -extract id raw -o - "$RESULT" 2>/dev/null || true)"
        [ -n "$SUBMISSION" ] && xcrun notarytool log "$SUBMISSION" --keychain-profile "$PROFILE" >&2
        fail "Notarization ended as \"$STATUS\". Apple's log, above, says why."
    fi

    step "Stapling the ticket to the disk image"
    xcrun stapler staple -q "$DMG"
    xcrun stapler validate -q "$DMG" || fail "The stapled ticket doesn't validate."
    spctl --assess --type open --context context:primary-signature "$DMG" \
        || fail "Gatekeeper rejects the disk image."
    spctl --assess --type execute "$APP" || fail "Gatekeeper rejects the app."
fi

# The archive stays, with its debug symbols, to read crash reports from this build.
rm -rf "$WORK/DerivedData" "$WORK/dmg"

step "Done: $DMG"
case "$MODE" in
    release) echo "Signed, notarized and stapled: ready to share." ;;
    unnotarized) echo "Not notarized: other Macs refuse to open it. Leave out --skip-notarize to share it." ;;
    dev) echo "Signed with your development certificate: it opens on this Mac only. Don't share it." ;;
esac
