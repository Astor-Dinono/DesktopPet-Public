import AppKit
import ServiceManagement
import XCTest
@testable import DesktopPet

final class LoginAtStartupTests: XCTestCase, @unchecked Sendable {
    @MainActor
    private final class Service: LoginItemService {
        var status = SMAppService.Status.notRegistered
        var nextRegistrationStatus = SMAppService.Status.enabled
        var registrationError: NSError?
        var unregisterError: NSError?
        var registrations = 0
        var removals = 0

        func register() throws {
            registrations += 1
            status = nextRegistrationStatus
            if let registrationError { throw registrationError }
        }

        func unregister() throws {
            removals += 1
            if let unregisterError { throw unregisterError }
            status = .notRegistered
        }
    }

    func testOpeningMenuReadsSystemWithoutChangingRegistration() async {
        await MainActor.run {
            let service = Service()
            let control = LoginAtStartup(service: service)
            let menu = NSMenu()
            for (status, state) in [(SMAppService.Status.notRegistered, NSControl.StateValue.off),
                                    (.enabled, .on), (.requiresApproval, .mixed), (.notFound, .off)] {
                service.status = status
                control.menuNeedsUpdate(menu)
                XCTAssertEqual(control.item.state, state)
            }
            XCTAssertEqual(service.registrations + service.removals, 0)
        }
    }

    func testExplicitChoicesAreIdempotentAndExternalChangesAreRespected() async throws {
        try await MainActor.run {
            let service = Service()
            let control = LoginAtStartup(service: service)
            XCTAssertEqual(try control.setEnabled(true), .enabled)
            XCTAssertEqual(try control.setEnabled(true), .enabled)
            service.status = .requiresApproval
            XCTAssertEqual(try control.setEnabled(true), .requiresApproval)
            XCTAssertEqual(try control.setEnabled(false), .notRegistered)
            XCTAssertEqual(try control.setEnabled(false), .notRegistered)
            XCTAssertEqual(service.registrations, 1)
            XCTAssertEqual(service.removals, 1)
        }
    }

    func testDeniedRegistrationAndFailedRemovalReflectActualState() async throws {
        try await MainActor.run {
            let service = Service()
            let control = LoginAtStartup(service: service)
            service.registrationError = NSError(domain: "TestService", code: 1)
            service.nextRegistrationStatus = .requiresApproval
            XCTAssertEqual(try control.setEnabled(true), .requiresApproval)
            service.unregisterError = NSError(domain: "TestService", code: 2)
            XCTAssertThrowsError(try control.setEnabled(false))
            control.menuNeedsUpdate(NSMenu())
            XCTAssertEqual(control.item.state, .mixed)
            service.status = .notRegistered
            service.nextRegistrationStatus = .notRegistered
            XCTAssertThrowsError(try control.setEnabled(true))
            control.menuNeedsUpdate(NSMenu())
            XCTAssertEqual(control.item.state, .off)
        }
    }
}
