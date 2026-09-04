# Public references

Implementation references checked for the initial slice. No private repository is an implementation source. This list is a provenance record, not a certification of legal non-infringement.

- Apple DockKit overview: https://developer.apple.com/documentation/dockkit
- Dock connection state stream: https://developer.apple.com/documentation/dockkit/dockaccessorymanager/accessorystatechanges
- Dock state-change fields: https://developer.apple.com/documentation/dockkit/dockaccessory/statechange
- System tracking: https://developer.apple.com/documentation/dockkit/dockaccessorymanager/setsystemtrackingenabled(_:)
- Capture session lifecycle and blocking calls: https://developer.apple.com/documentation/avfoundation/avcapturesession
- XcodeGen project specification: https://github.com/yonaskolb/XcodeGen/blob/master/Docs/ProjectSpec.md

These references are consulted for API contracts, not copied source files. The app currently depends at runtime only on Apple system frameworks and its own local MateCore package. XcodeGen is a development-time tool, not shipped in the app.
