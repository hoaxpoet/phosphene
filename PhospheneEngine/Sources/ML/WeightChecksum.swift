// WeightChecksum — load-time SHA-256 content integrity for on-disk ML weights (CLEAN.5.5).
//
// Complements the per-tensor byte-count guard in each +Weights loader: the
// size check catches truncation cheaply; this catches bit-rot, partial LFS
// smudges, wrong-version checkpoints, and tampering — any corruption that
// preserves length but changes content. Fail-loud by design: a mismatch
// throws rather than feeding plausible-but-garbage weights into the stem
// separator / beat tracker (which would emit bad stems / wrong beats with no
// crash). Run once per model at construction (session prep), not per-frame.

import CryptoKit
import Foundation

// MARK: - WeightChecksum

enum WeightChecksum {

    /// Lowercase, no-separator SHA-256 hex of `data`.
    /// Matches the weight-manifest digests and `shasum -a 256 <file>` exactly.
    static func hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Throw `makeError(key, expected, got)` unless `data` hashes to `expected`.
    ///
    /// `expected` is the lowercase-hex digest from the weight manifest. The
    /// error is built by the caller so each model keeps its own error type.
    static func verify(
        _ data: Data,
        expected: String,
        key: String,
        else makeError: (_ key: String, _ expected: String, _ got: String) -> Error
    ) throws {
        let got = hex(data)
        guard got == expected else { throw makeError(key, expected, got) }
    }
}
