#!/bin/bash
# Builds CachePop for Developer ID distribution: archives the app, exports it signed with your
# Developer ID, puts it in a disk image with an Applications shortcut, signs and notarizes the
# disk image and staples the ticket to it. The DMG lands in build/.
#
# Signing takes one of two routes:
#   - A "Developer ID Application" certificate in this Mac's keychain, plus notary credentials
#     saved under a profile name ("CachePop" by default):
#        xcrun notarytool store-credentials CachePop --apple-id <your Apple ID> --team-id 4R2U97FG78
#     The disk image is signed, notarized and stapled.
#   - Without one: Xcode's cloud-managed Developer ID certificate, for an Apple ID in
#     Xcode › Settings › Accounts that may use it. Xcode signs and notarizes the app and the
#     ticket is stapled to it. The disk image stays unsigned: only a local certificate signs it.
#
# One-time setup: the Finder layout tool, installed once in an isolated build folder:
#        python3 -m venv build/dmg-tools
#        build/dmg-tools/bin/python -m pip install -r scripts/dmg-requirements.txt
#
# Usage:
#   scripts/make-dmg.sh                  signed, notarized and stapled: ready to share
#   scripts/make-dmg.sh --skip-notarize  signed with Developer ID but not notarized: other Macs refuse it
#   scripts/make-dmg.sh --dev            signed with your development certificate, to check the DMG on
#                                        this Mac before you have a Developer ID certificate
# Options:
#   --repackage      reuse build/work/export/CachePop.app; only rebuild the disk image
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
REPACKAGE=false
PROFILE="${CACHEPOP_NOTARY_PROFILE:-CachePop}"
OUT="$ROOT/build"

while [ $# -gt 0 ]; do
    case "$1" in
        --skip-notarize) MODE="unnotarized" ;;
        --dev) MODE="dev" ;;
        --repackage) REPACKAGE=true ;;
        --profile) PROFILE="${2:?--profile needs a name}"; shift ;;
        --output) OUT="${2:?--output needs a folder}"; shift ;;
        -h | --help) sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "Unknown option: $1 (see --help)" >&2; exit 64 ;;
    esac
    shift
done

step() { printf '\n==> %s\n' "$*"; }
fail() { printf '\nerror: %s\n' "$*" >&2; exit 1; }

# MARK: Checks that fail fast, before the long build

IDENTITY=""
SIGNING="local"
if [ "$MODE" != "dev" ]; then
    IDENTITY="$(security find-identity -v -p codesigning \
        | grep -o "\"Developer ID Application: [^\"]*($TEAM_ID)\"" | head -n 1 | tr -d '"' || true)"
    if [ -z "$IDENTITY" ]; then
        SIGNING="cloud"
        echo "No Developer ID certificate in this Mac's keychain: Xcode's cloud-managed one signs the app."
    fi
fi

if [ "$MODE" = "release" ] && [ "$SIGNING" = "local" ]; then
    xcrun notarytool history --keychain-profile "$PROFILE" > /dev/null 2>&1 \
        || fail "No notary credentials in your keychain under the profile \"$PROFILE\". Save them once with:
  xcrun notarytool store-credentials $PROFILE --apple-id <your Apple ID> --team-id $TEAM_ID"
fi

mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
DMG_PYTHON="${CACHEPOP_DMG_PYTHON:-$OUT/dmg-tools/bin/python}"
if [ ! -x "$DMG_PYTHON" ]; then
    DMG_PYTHON="$(command -v python3 || true)"
fi
[ -n "$DMG_PYTHON" ] && "$DMG_PYTHON" -c 'import dmgbuild, ds_store' > /dev/null 2>&1 \
    || fail "Install the Finder layout tool once:
  python3 -m venv build/dmg-tools
  build/dmg-tools/bin/python -m pip install -r scripts/dmg-requirements.txt
For a custom output directory, set CACHEPOP_DMG_PYTHON to that Python executable's full path."
WORK="$OUT/work"
ARCHIVE="$WORK/$APP_NAME.xcarchive"
APP="$WORK/export/$APP_NAME.app"
if [ "$REPACKAGE" = true ]; then
    [ -d "$APP" ] || fail "No exported app at $APP. Run without --repackage first."
else
    rm -rf "$WORK"
    mkdir -p "$WORK"
fi
# Build intermediates are large: they go whether the run succeeds or stops partway. The archive
# stays, with its debug symbols, to read crash reports from this build.
trap 'rm -rf "$WORK/DerivedData" "$WORK/SwiftModuleCache"' EXIT

SIGNING_HELP="Xcode couldn't sign the app. If Apple says the team's program membership isn't eligible,
the Apple Developer Program membership for team $TEAM_ID needs renewing: see developer.apple.com/account."


# MARK: Build

if [ "$REPACKAGE" = false ]; then
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
        # The cloud route uploads the app to Apple's notary service as part of the export.
        DESTINATION="export"
        [ "$SIGNING" = "cloud" ] && [ "$MODE" = "release" ] && DESTINATION="upload"
        step "Exporting with your Developer ID ($SIGNING certificate)"
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
    <key>destination</key>
    <string>$DESTINATION</string>
</dict>
</plist>
EOF
        if [ "$DESTINATION" = "upload" ]; then
            xcodebuild -exportArchive -quiet -allowProvisioningUpdates \
                -archivePath "$ARCHIVE" -exportOptionsPlist "$WORK/ExportOptions.plist" -exportPath "$WORK/upload" \
                || fail "$SIGNING_HELP"

            step "Waiting for Apple to notarize the app (usually a few minutes)"
            STARTED=$SECONDS
            until xcodebuild -exportNotarizedApp -allowProvisioningUpdates \
                    -archivePath "$ARCHIVE" -exportPath "$WORK/export" > "$WORK/notarized-export.log" 2>&1; do
                if grep -qiE "invalid|rejected" "$WORK/notarized-export.log"; then
                    cat "$WORK/notarized-export.log" >&2
                    fail "Apple didn't notarize the app. The log above says why."
                fi
                [ $((SECONDS - STARTED)) -lt 2400 ] \
                    || fail "Notarization took over 40 minutes. Check Xcode's Organizer, then run with --repackage once the app is notarized."
                echo "  still waiting ($(( (SECONDS - STARTED) / 60 )) min)…"
                sleep 30
            done
        else
            xcodebuild -exportArchive -quiet -allowProvisioningUpdates \
                -archivePath "$ARCHIVE" -exportOptionsPlist "$WORK/ExportOptions.plist" -exportPath "$WORK/export" \
                || fail "$SIGNING_HELP"
        fi
    fi
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

if [ "$MODE" = "release" ] && [ "$SIGNING" = "cloud" ]; then
    xcrun stapler validate -q "$APP" || fail "The app has no notarization ticket stapled to it."
    spctl --assess --type execute "$APP" || fail "Gatekeeper rejects the app."
fi

# MARK: Disk image

VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")"
DMG="$OUT/$APP_NAME-$VERSION.dmg"
[ "$MODE" = "dev" ] && DMG="$OUT/$APP_NAME-$VERSION-dev.dmg"

step "Making $(basename "$DMG")"
BACKGROUND="$WORK/installer-background.tiff"
xcrun swift -module-cache-path "$WORK/SwiftModuleCache" "$ROOT/scripts/dmg-background.swift" \
    "$BACKGROUND" "$ROOT/CachePop/Assets.xcassets/BrandGlyph.imageset/BrandGlyph.png"
"$DMG_PYTHON" -m dmgbuild -s "$ROOT/scripts/dmg-settings.py" -D "app=$APP" -D "background=$BACKGROUND" \
    "Install $APP_NAME" "$WORK/$APP_NAME-layout.dmg"

step "Verifying the app inside the finished disk image"
VERIFY_MOUNT="$(mktemp -d "${TMPDIR:-/tmp}/CachePop-dmg-verify.XXXXXX")"
hdiutil attach -readonly -nobrowse -noautoopen -mountpoint "$VERIFY_MOUNT" "$WORK/$APP_NAME-layout.dmg" \
    > "$WORK/verify-mount.log"
PACKAGED_APP_VALID=true
codesign --verify --deep --strict "$VERIFY_MOUNT/$APP_NAME.app" || PACKAGED_APP_VALID=false
if [ "$MODE" = "release" ] && [ "$SIGNING" = "cloud" ]; then
    xcrun stapler validate -q "$VERIFY_MOUNT/$APP_NAME.app" || PACKAGED_APP_VALID=false
fi
hdiutil detach -quiet "$VERIFY_MOUNT"
rmdir "$VERIFY_MOUNT"
[ "$PACKAGED_APP_VALID" = true ] || fail "The packaged app's signature doesn't verify."
hdiutil verify -quiet "$WORK/$APP_NAME-layout.dmg"
mv -f "$WORK/$APP_NAME-layout.dmg" "$DMG"

if [ "$SIGNING" = "local" ] && [ "$MODE" != "dev" ]; then
    step "Signing the disk image"
    codesign --sign "$IDENTITY" --timestamp "$DMG"
    codesign --verify "$DMG" || fail "The disk image's signature doesn't verify."
fi

# MARK: Notarize

if [ "$MODE" = "release" ] && [ "$SIGNING" = "local" ]; then
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

step "Done: $DMG"
case "$MODE" in
    release)
        if [ "$SIGNING" = "local" ]; then
            echo "Signed, notarized and stapled: ready to share."
        else
            echo "The app inside is signed, notarized and stapled: ready to share. The disk image itself is unsigned."
        fi ;;
    unnotarized) echo "Not notarized: other Macs refuse to open it. Leave out --skip-notarize to share it." ;;
    dev) echo "Signed with your development certificate: it opens on this Mac only. Don't share it." ;;
esac
