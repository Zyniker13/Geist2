/// The recipe module format: reading, writing, validation, integrity checks, and signatures.
///
/// Builds on `BarCore` and, like it, must stay portable: no Apple-only frameworks.
public enum BarModules {
    /// The version of the Geist package, matching the app's `vA.B.C` version.
    public static let version = "1.0.0"

    /// Report whether `raw` looks like the package's `vA.B.C` version scheme.
    ///
    /// Gives the coverage gate a line to measure while the module is still a
    /// placeholder; the module format lands in milestone M3.
    public static func isVersionScheme(_ raw: String) -> Bool {
        raw.hasPrefix("v")
    }
}
