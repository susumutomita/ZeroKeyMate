#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/conversation-evaluation
# Compile the exact local generation source used by the iOS app. No mocked
# replies or separately reimplemented prompts. Requires Apple Intelligence.
xcrun swiftc -parse-as-library -O -target "$(uname -m)-apple-macos26.0" \
  -module-cache-path .build/ModuleCache \
  apps/ios/ZeroKeyMate/LocalConversationSession.swift apps/ios/ZeroKeyMate/PurchaseConversation.swift scripts/evaluate-conversation.swift \
  -o .build/conversation-evaluation/runner
.build/conversation-evaluation/runner
