# Runtime Console package icons

`runtime-console-512.png` is the VitalDB product mark copied from the existing
repository-owned PWA icon source. `runtime-console.icns` is its deterministic
macOS conversion. They are product presentation assets only: they do not
carry Host, Guest, Recorder, endpoint, or configuration state.

The Electron package declaration assigns the ICNS asset to macOS and the PNG
asset to Windows and Linux. Packaging verification must reject a fallback to
the Electron default icon.
