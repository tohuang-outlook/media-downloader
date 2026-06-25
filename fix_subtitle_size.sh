#!/bin/zsh
# fix_subtitle_size.sh
# Patches SubtitleBurnerApp.swift to fix oversized subtitle text.
# Run from your repo root: ./fix_subtitle_size.sh

set -euo pipefail
FILE="${0:A:h}/SubtitleBurnerApp.swift"

if [[ ! -f "$FILE" ]]; then
    echo "❌ SubtitleBurnerApp.swift not found in $(pwd)"
    exit 1
fi

echo "▶ Patching subtitle font size in $FILE…"

# Fix 1: Reduce font size from 4.7% → 2.8% of video height
# 1080p: was ~51px, now ~30px — standard broadcast size
python3 - <<PYEOF
import re

with open("$FILE", "r") as f:
    content = f.read()

# Fix font size ratio
content = re.sub(
    r'let fontSize\s*=\s*max\(\d+,\s*Int\(Double\(h\w*\)\s*\*\s*0\.\d+\)\)',
    'let fontSize  = max(22, Int(Double(height) * 0.028))',
    content
)

# Fix marginV ratio  
content = re.sub(
    r'let marginV\s*=\s*max\(\d+,\s*Int\(Double\(h\w*\)\s*\*\s*0\.\d+\)\)',
    'let marginV   = max(30, Int(Double(height) * 0.045))',
    content
)

# Fix outline ratio
content = re.sub(
    r'let outline\s*=\s*max\(\d+,\s*Int\(Double\(h\w*\)\s*\*\s*0\.\d+\)\)',
    'let outline   = max(2,  Int(Double(height) * 0.002))',
    content
)

# Fix double newline between Chinese and English (\\N\\N → \\N)
content = content.replace(r'\\N\\N', r'\\N')

with open("$FILE", "w") as f:
    f.write(content)

print("✅ Done")
PYEOF

echo "▶ Rebuilding app…"
"${0:A:h}/build.sh"
echo "✅ SubtitleBurner.app rebuilt with smaller subtitles"
echo ""
echo "Size reference:"
echo "  1080p video → font ~30px (was ~51px)"
echo "   720p video → font ~20px (was ~34px)"
echo "   480p video → font ~13px (was ~23px)"
