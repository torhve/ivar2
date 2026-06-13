#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TOOLS_DIR="$PROJECT_ROOT/tools"
CACHE_DIR="$PROJECT_ROOT/cache"
CACHE_DB="$CACHE_DIR/unicode.sql"
BACKUP_DB="$CACHE_DIR/unicode.sql.bak"

log() { echo "[$(date +%H:%M:%S)] $*"; }
die() { log "ERROR: $*"; exit 1; }

# ── Detect latest Unicode version with ucdxml ──────────────────────────
detect_version() {
    local page
    page=$(curl -sfL --max-time 15 "https://www.unicode.org/Public/" || true)
    [[ -z "$page" ]] && { log "Warning: could not fetch unicode.org, using fallback 17.0.0"; echo "17.0.0"; return; }

    # Find all version dirs that contain ucdxml, pick the highest semver
    local best=""
    while IFS= read -r ver; do
        [[ -z "$ver" ]] && continue
        if [[ -z "$best" ]]; then
            best="$ver"
        else
            # Compare semver: split on dots, compare numerically
            local IFS=.
            read -ra a <<< "$ver"
            read -ra b <<< "$best"
            for i in 0 1 2; do
                local va=${a[$i]:-0} vb=${b[$i]:-0}
                if (( va > vb )); then best="$ver"; break; fi
                if (( va < vb )); then break; fi
            done
        fi
    done < <(echo "$page" | grep -oP 'href="(\K[0-9]+\.[0-9]+\.[0-9]+)(?=/)"' | sort -u | while read -r v; do
        curl -sfI --max-time 5 "https://www.unicode.org/Public/${v}/ucdxml/" >/dev/null 2>&1 && echo "$v"
    done)

    [[ -z "$best" ]] && best="17.0.0"
    echo "$best"
}

# ── Main ───────────────────────────────────────────────────────────────
log "Detecting latest Unicode version..."
VERSION=$(detect_version)
log "Using Unicode version $VERSION"

ZIP_URL="https://www.unicode.org/Public/${VERSION}/ucdxml/ucd.all.flat.zip"
XML_FILE="$TOOLS_DIR/ucd.all.flat.xml"
ZIP_FILE="$TOOLS_DIR/ucd.all.flat.zip"
OUTPUT_DB="$TOOLS_DIR/unicode.sql"

cd "$TOOLS_DIR"

# Backup existing cache
if [[ -f "$CACHE_DB" ]]; then
    log "Backing up $CACHE_DB..."
    cp "$CACHE_DB" "$BACKUP_DB"
fi

# Download
log "Downloading $ZIP_URL ..."
wget -q --show-progress -O "$ZIP_FILE" "$ZIP_URL" || die "Download failed"
log "Downloaded $(du -h "$ZIP_FILE" | cut -f1)"

# Extract
log "Extracting XML..."
unzip -o -q "$ZIP_FILE" -d "$TOOLS_DIR" || die "Extraction failed"
[[ -f "$XML_FILE" ]] || die "XML file not found after extraction"
log "Extracted $(du -h "$XML_FILE" | cut -f1)"

# Convert
log "Converting XML → SQLite (this may take a few minutes)..."
lua5.1 "$TOOLS_DIR/ucdxml2sqlite.lua" || die "Conversion failed"
[[ -f "$OUTPUT_DB" ]] || die "Output DB not found after conversion"
log "Generated $(du -h "$OUTPUT_DB" | cut -f1)"

# Install
log "Installing to cache..."
mv "$OUTPUT_DB" "$CACHE_DB"

# Verify
RECORDS=$(sqlite3 "$CACHE_DB" "SELECT COUNT(*) FROM unicode;")
log "Installed $RECORDS records"

# Cleanup
log "Cleaning up..."
rm -f "$ZIP_FILE" "$XML_FILE"
if [[ -f "$BACKUP_DB" ]]; then
    rm -f "$BACKUP_DB"
fi

log "Done! Reload the unicode module on your running bot:"
log "  echo 'reloadmodule unicode' > <fifo_name>"
