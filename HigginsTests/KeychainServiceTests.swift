import XCTest
@testable import Higgins

final class KeychainServiceTests: XCTestCase {
    func testKeychainSetGetDelete() throws {
        try runOffMainThread {
            let service = KeychainService(service: "HigginsTests.Keychain.\(UUID().uuidString)")
            let key = "openaiKey"

            try service.set("secret", for: key)
            XCTAssertEqual(try service.get(key), "secret")

            try service.delete(key)
            XCTAssertNil(try service.get(key))
        }
    }

    private func runOffMainThread(_ work: @escaping () throws -> Void) throws {
        let expectation = expectation(description: "Keychain work off main thread")
        let queue = DispatchQueue(label: "HigginsTests.Keychain", qos: .userInitiated)
        var capturedError: Error?

        queue.async {
            do {
                try work()
            } catch {
                capturedError = error
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5)

        if let capturedError {
            throw capturedError
        }
    }
}
