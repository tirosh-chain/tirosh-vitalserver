# `.vital` replay wire corpus

The `synthetic-v1` through `synthetic-v3` fixtures are deterministic,
non-clinical wire fixtures. They contain one PLETH waveform track and one
PLETH_HR numeric track. The numeric track deliberately has `srate=0`.

Each fixture is stored as base64 text so source review remains possible. Tests
verify the encoded artifact digest before decoding it. These fixtures prove the
supported versioned wire contract; they are not evidence that a real Recorder
artifact was accepted.

An approved real-file corpus must be non-identifying and carry explicit
redistribution provenance. Files under the repository's ignored `data/`
directory must not be copied here merely because they parse successfully.
