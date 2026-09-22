#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/search-evaluation
# Compile the exact search data types and isolated summarizer used by the app.
# Synthetic public-domain fixtures only: no API key, network or account access.
xcrun swiftc -parse-as-library -O -target "$(uname -m)-apple-macos26.0" \
  -module-cache-path .build/ModuleCache -emit-library -emit-module -module-name MateCore \
  -emit-module-path .build/search-evaluation/MateCore.swiftmodule \
  Sources/MateCore/WebSearch.swift -o .build/search-evaluation/libMateSearchCore.dylib
xcrun swiftc -parse-as-library -O -target "$(uname -m)-apple-macos26.0" \
  -module-cache-path .build/ModuleCache -I .build/search-evaluation -L .build/search-evaluation -lMateSearchCore \
  -Xlinker -rpath -Xlinker "$PWD/.build/search-evaluation" \
  apps/ios/ZeroKeyMate/LocalSearchSummary.swift scripts/evaluate-web-search.swift \
  -o .build/search-evaluation/runner
.build/search-evaluation/runner
