// SpotifyKeychainStoreTests — Unit tests for SpotifyKeychainStore.
// Uses a test-specific Keychain service name to avoid touching production tokens.

import Testing
@testable import PhospheneApp

// MARK: - Tests

@Suite("SpotifyKeychainStore", .serialized)
struct SpotifyKeychainStoreTests {

    /// Unique test service name so production Keychain entries are never touched.
    private static let testService = "com.phosphene.spotify.test"

    private func makeStore() -> SpotifyKeychainStore {
        SpotifyKeychainStore(service: Self.testService, account: "refresh_token_test")
    }

    @Test("save and load round-trip returns same token")
    func saveAndLoadRoundTrip() throws {
        let store = makeStore()
        defer { store.deleteRefreshToken() }

        try store.saveRefreshToken("test_refresh_abc123")
        #expect(store.loadRefreshToken() == "test_refresh_abc123")
    }

    @Test("overwrite replaces previous token")
    func overwriteReplacesToken() throws {
        let store = makeStore()
        defer { store.deleteRefreshToken() }

        try store.saveRefreshToken("first_token")
        try store.saveRefreshToken("second_token")
        #expect(store.loadRefreshToken() == "second_token")
    }

    @Test("delete removes stored token")
    func deleteRemovesToken() throws {
        let store = makeStore()

        try store.saveRefreshToken("token_to_delete")
        store.deleteRefreshToken()
        #expect(store.loadRefreshToken() == nil)
    }

    @Test("load with no stored token returns nil")
    func loadWithNoToken() {
        let store = makeStore()
        store.deleteRefreshToken()  // ensure clean state
        #expect(store.loadRefreshToken() == nil)
    }

    @Test("consecutive deletes are no-op")
    func consecutiveDeletesAreNoOp() throws {
        let store = makeStore()
        store.deleteRefreshToken()
        store.deleteRefreshToken()
    }
}
