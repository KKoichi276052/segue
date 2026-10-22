import Testing
@testable import SegueCore

@Suite struct PermissionsTests {
    let none = PermissionStatus(accessibility: false, inputMonitoring: false, screenRecording: false)
    let control = PermissionStatus(accessibility: true, inputMonitoring: true, screenRecording: false)
    let all = PermissionStatus(accessibility: true, inputMonitoring: true, screenRecording: true)

    @Test func controlComesFirst() {
        #expect(PermissionsFlow.step(for: none, screenRecordingSkipped: false) == .control)
        #expect(PermissionsFlow.step(for: none, screenRecordingSkipped: true) == .control)
    }

    @Test func screenRecordingIsOptional() {
        #expect(PermissionsFlow.step(for: control, screenRecordingSkipped: false) == .screenRecording)
        #expect(PermissionsFlow.step(for: control, screenRecordingSkipped: true) == .done)
        #expect(PermissionsFlow.step(for: all, screenRecordingSkipped: false) == .done)
    }

    @Test func paneNamesFollowTheOS() {
        #expect(PermissionKind.control.paneName(macOSMajor: 26) == "Accessibility")
        #expect(PermissionKind.control.paneName(macOSMajor: 27) == "Device Control and Data Access")
    }

    @Test func warnings() {
        #expect(PermissionsFlow.warnings(for: all, macOSMajor: 27).isEmpty)
        #expect(PermissionsFlow.warnings(for: control, macOSMajor: 27).count == 1)
        #expect(PermissionsFlow.warnings(for: none, macOSMajor: 27).first?.contains("Device Control") == true)
    }
}
