#!/usr/bin/env bash
# Installs Tobias without cloning the repo:
#   curl -fsSL https://github.com/andreyabpaiva/tobias/releases/latest/download/install.sh | bash
# Downloads a release tarball, verifies its SHA-256, builds it locally and installs
# Tobias.app to ~/Applications and the `tobias` command to ~/.local/bin. No sudo.
#
# Environment (all optional):
#   TOBIAS_REPO      owner/name on GitHub              (default andreyabpaiva/tobias)
#   TOBIAS_REF       release tag to install            (default: latest)
#   TOBIAS_TARBALL   local tarball instead of downloading (for testing)
#   TOBIAS_SHA256    expected checksum for TOBIAS_TARBALL
#   TOBIAS_APP_DIR   where to put the app              (default ~/Applications)
#   TOBIAS_BIN_DIR   where to put the command          (default ~/.local/bin)
#   TOBIAS_NO_OPEN   set to 1 to skip opening the app
set -euo pipefail

REPO="${TOBIAS_REPO:-andreyabpaiva/tobias}"
REF="${TOBIAS_REF:-latest}"
APP_DIR="${TOBIAS_APP_DIR:-$HOME/Applications}"
BIN_DIR="${TOBIAS_BIN_DIR:-$HOME/.local/bin}"

say() { printf '%s\n' "$*"; }
fail() { printf 'error: %s\n' "$*" >&2; exit 1; }

# 1. Environment checks
[ "$(uname -s)" = "Darwin" ] || fail "Tobias runs on macOS only."
major="$(sw_vers -productVersion | cut -d. -f1)"
[ "$major" -ge 14 ] || fail "Tobias needs macOS 14 or newer (found $(sw_vers -productVersion))."
xcode-select -p >/dev/null 2>&1 || fail "Install the Command Line Tools first: xcode-select --install"
command -v swift >/dev/null 2>&1 || fail "swift not found. Install the Command Line Tools: xcode-select --install"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# 2. Get the source tarball and verify it
expected=""
if [ -n "${TOBIAS_TARBALL:-}" ]; then
  [ -f "$TOBIAS_TARBALL" ] || fail "TOBIAS_TARBALL not found: $TOBIAS_TARBALL"
  tarball="$TOBIAS_TARBALL"
  expected="${TOBIAS_SHA256:-}"
else
  tag="$REF"
  if [ "$tag" = "latest" ]; then
    tag="$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" \
      | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -1)"
    [ -n "$tag" ] || fail "could not find the latest release of $REPO"
  fi
  url="https://github.com/$REPO/releases/download/$tag/tobias-$tag.tar.gz"
  say "Downloading Tobias $tag…"
  tarball="$tmp/tobias.tar.gz"
  curl -fsSL -o "$tarball" "$url" || fail "download failed: $url"
  curl -fsSL -o "$tmp/tobias.sha256" "$url.sha256" || fail "checksum file missing: $url.sha256"
  expected="$(awk '{print $1}' "$tmp/tobias.sha256")"
  [ -n "$expected" ] || fail "empty checksum file"
fi

if [ -n "$expected" ]; then
  actual="$(shasum -a 256 "$tarball" | awk '{print $1}')"
  [ "$actual" = "$expected" ] || fail "checksum mismatch (expected $expected, got $actual)"
  say "Checksum ok."
else
  say "warning: no checksum given for a local tarball, skipping verification."
fi

# 3. Build
mkdir -p "$tmp/src"
tar -xzf "$tarball" -C "$tmp/src" --strip-components=1
[ -x "$tmp/src/scripts/build-app.sh" ] || fail "the tarball does not look like Tobias (scripts/build-app.sh missing)"
say "Building (this takes a minute)…"
"$tmp/src/scripts/build-app.sh" "$tmp/out" >"$tmp/build.log" 2>&1 || { tail -30 "$tmp/build.log" >&2; fail "build failed"; }

# 4. Install
if pgrep -x Tobias >/dev/null 2>&1; then
  pkill -x Tobias || true
  sleep 1
fi
mkdir -p "$APP_DIR" "$BIN_DIR"
rm -rf "${APP_DIR:?}/Tobias.app"
cp -R "$tmp/out/Tobias.app" "$APP_DIR/"
install -m 755 "$tmp/src/bin/tobias" "$BIN_DIR/tobias"

version="$("$APP_DIR/Tobias.app/Contents/MacOS/Tobias" --version 2>/dev/null || echo unknown)"
say "Installed Tobias $version"
say "  app:     $APP_DIR/Tobias.app"
say "  command: $BIN_DIR/tobias"
case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *) say "Add $BIN_DIR to your PATH to use the 'tobias' command:"
     say "  echo 'export PATH=\"$BIN_DIR:\$PATH\"' >> ~/.zshrc" ;;
esac

if [ "${TOBIAS_NO_OPEN:-}" != "1" ]; then
  open "$APP_DIR/Tobias.app"
fi
