# Codemagic unsigned IPA

This workflow builds the iOS device app with code signing disabled and packages the `.app` into a conventional `Payload/*.app` IPA container.

Workflow: `ios-unsigned-ipa`

Important: an unsigned IPA is **not installable on a normal iPhone**. It is useful for verifying the complete iOS/native build and inspecting the IPA container. To install on a physical iPhone, the app must ultimately be code signed (Apple Developer provisioning, or an appropriate personal/team signing workflow).

No App Store Connect API key or paid Apple Developer Program membership is required for this unsigned CI build itself.
