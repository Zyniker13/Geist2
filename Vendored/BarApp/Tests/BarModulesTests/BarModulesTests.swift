import Testing

@testable import BarModules

@Test func versionConstantIsSet() {
    #expect(!BarModules.version.isEmpty)
    #expect(BarModules.version.split(separator: ".").count == 3)
}

@Test func versionSchemeCheck() {
    #expect(BarModules.isVersionScheme("v1.0.0"))
    #expect(!BarModules.isVersionScheme("1.0.0"))
}
