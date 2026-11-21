/// The recipe collection module format: reading, writing, validation,
/// integrity checks, and signatures.
///
/// Builds on `RecipeCore` and, like it, must stay portable: no Apple-only
/// frameworks.
///
/// Moved from the sibling home bar project's `BarModules` (commit d8dbede,
/// Apache-2.0/MIT) with the drink-specific schema field names replaced by
/// the recipe format's (decision 0006); the archive, canonical JSON,
/// digest and Ed25519 machinery is unchanged.
public enum RecipeModules {
    /// The recipe collection module format version this reader implements.
    public static let currentFormatVersion = 1

    /// The version of the RecipeKit package, matching the app's `vA.B.C` version.
    public static let packageVersion = "0.1.0"
}
