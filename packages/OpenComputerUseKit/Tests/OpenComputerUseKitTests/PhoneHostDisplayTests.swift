import XCTest
@testable import OpenComputerUseKit
final class PhoneHostDisplayTests: XCTestCase {
 func args() -> [String: Any] { ["action":"park", "instance_id":"aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee", "pid":123, "process_start_time":1234.5, "window_id":99] }
 func testRequiresExactTuple() throws { let (_, b) = try PhoneHostDisplayPolicy.validate(args()); XCTAssertEqual(b.windowID,99); XCTAssertEqual(b.processStartTime,1234.5); for key in ["instance_id","pid","process_start_time","window_id"] { var a=args();a.removeValue(forKey:key);XCTAssertThrowsError(try PhoneHostDisplayPolicy.validate(a)) } }
 func testRejectsAmbiguousAndMalformedArguments() { for value: Any in [true,0,-1,1.5,Double.nan] { var a=args();a["pid"]=value;XCTAssertThrowsError(try PhoneHostDisplayPolicy.validate(a)) }; var a=args();a["extra"]=1;XCTAssertThrowsError(try PhoneHostDisplayPolicy.validate(a)) }
 func testOldGlobalFlagsCannotEnablePhoneRoute() { XCTAssertFalse(PhoneHostDisplayPolicy.enabled(document:["virtualDisplay":["enabled":true]],namespace:PhoneHostDisplayPolicy.namespace));XCTAssertFalse(PhoneHostDisplayPolicy.enabled(document:["phoneHostDisplay":["enabled":true]],namespace:"persistent-display"));XCTAssertTrue(PhoneHostDisplayPolicy.enabled(document:["phoneHostDisplay":["enabled":true]],namespace:PhoneHostDisplayPolicy.namespace)) }
 func testChangedInstanceOrBirthNotSameHost() throws { let (_, a)=try PhoneHostDisplayPolicy.validate(args()); var v=args();v["process_start_time"]=1234.6;let (_,b)=try PhoneHostDisplayPolicy.validate(v);XCTAssertFalse(PhoneHostDisplayPolicy.sameHost(a,b));v=args();v["instance_id"]="11111111-bbbb-cccc-dddd-eeeeeeeeeeee";let (_,c)=try PhoneHostDisplayPolicy.validate(v);XCTAssertFalse(PhoneHostDisplayPolicy.sameHost(a,c)) }
 func testUnknownBirthDoesNotProveGone() { XCTAssertFalse(PhoneHostDisplayPolicy.processGone(exists:true,observedStart:nil,expectedStart:12)); XCTAssertTrue(PhoneHostDisplayPolicy.processGone(exists:false,observedStart:nil,expectedStart:12)); XCTAssertTrue(PhoneHostDisplayPolicy.processGone(exists:true,observedStart:13,expectedStart:12)); XCTAssertFalse(PhoneHostDisplayPolicy.processGone(exists:true,observedStart:12,expectedStart:12)) }
 func testSameProcessOtherWindowIsNotAdmitted() throws { let (_,a)=try PhoneHostDisplayPolicy.validate(args());var v=args();v["window_id"]=100;let (_,b)=try PhoneHostDisplayPolicy.validate(v);XCTAssertFalse(PhoneHostDisplayPolicy.admitted(b,by:a));XCTAssertTrue(PhoneHostDisplayPolicy.admitted(a,by:a)) }
 func testCoveredWindowCannotBeReadyWithoutPin() { XCTAssertFalse(PhoneHostDisplayPolicy.ready(contained:true,renderPinned:false));XCTAssertFalse(PhoneHostDisplayPolicy.ready(contained:false,renderPinned:true));XCTAssertTrue(PhoneHostDisplayPolicy.ready(contained:true,renderPinned:true)) }
 func testDisplayModeContainsSelectedWindowUnderHiDPI() { XCTAssertFalse(PhoneHostDisplayPolicy.fitsPhone(width:960,height:540));XCTAssertTrue(PhoneHostDisplayPolicy.fitsPhone(width:960,height:720));XCTAssertFalse(PhoneHostDisplayPolicy.fitsPhone(width:.nan,height:720)) }
 func testGenericRouteRemainsRetired() { XCTAssertThrowsError(try VirtualDisplayConfig(enabled:true,restoreOnSessionEnd:false).requireEnabled()) }
}

final class PhoneHostDisplayTopologyTests: XCTestCase {
    typealias T = PhoneHostDisplayTopology
    func screen(_ id: UInt32, _ x: Double = 0, _ y: Double = 0, mirror: UInt32 = 0, member: Bool = false, width: Double = 1512) -> T.Screen {
        T.Screen(id: id, vendor: id == 8 ? 0x0CAC : 1, model: id == 8 ? 0x0CAC : 1,
          serial: id == 8 ? 0x50484F4E : id, bounds: CGRect(x:x,y:y,width:width,height:982),
          mirror:mirror, mirrored:member, mode:[width,982,width,982,60])
    }
    func testOwnedMirrorPrimaryRestoresOriginalPhysicalSlave() throws {
        let before=T.Snapshot(main:1,screens:[1:screen(1),2:screen(2,1512)])
        let after=T.Snapshot(main:8,screens:[1:screen(1,mirror:8,member:true,width:1920),2:screen(2,1512),8:screen(8,member:true,width:1920)])
        let p=try T.plan(before:before,after:after,owned:8)
        XCTAssertEqual(Set(p.mirrors.map { $0.0 }),Set([8,1]));XCTAssertEqual(p.mirrors.map { $0.1 },[0,0])
        XCTAssertEqual(p.origins.last?.0,1);XCTAssertEqual(p.origins.last?.1,.zero)
        XCTAssertEqual(p.origins.first { $0.0 == 8 }?.1,CGPoint(x:3024,y:0))
    }
    func testOwnedPrimaryUniformTranslation() throws {
        let before=T.Snapshot(main:1,screens:[1:screen(1),2:screen(2,1512)])
        let after=T.Snapshot(main:8,screens:[1:screen(1,-1920),2:screen(2,-408),8:screen(8)])
        XCTAssertNoThrow(try T.plan(before:before,after:after,owned:8))
    }
    func testUnrelatedGeometryAndHotplugRejected() {
        let before=T.Snapshot(main:1,screens:[1:screen(1),2:screen(2,1512)])
        XCTAssertThrowsError(try T.plan(before:before,after:T.Snapshot(main:1,screens:[1:screen(1),2:screen(2,1600),8:screen(8)]),owned:8))
        XCTAssertThrowsError(try T.plan(before:before,after:T.Snapshot(main:1,screens:[1:screen(1),2:screen(2,1512),3:screen(3),8:screen(8)]),owned:8))
    }
    func testUnrelatedPreexistingMirrorPreserved() throws {
        let before=T.Snapshot(main:1,screens:[1:screen(1,member:true),2:screen(2,mirror:1,member:true)])
        let after=T.Snapshot(main:1,screens:before.screens.merging([8:screen(8)]) { _,new in new })
        let p=try T.plan(before:before,after:after,owned:8)
        XCTAssertTrue(p.mirrors.isEmpty);XCTAssertEqual(p.origins.map { $0.0 },[8])
    }
    func testOriginalReadbackRequiredAndFailureIsTerminal() {
        let before=T.Snapshot(main:1,screens:[1:screen(1)])
        XCTAssertTrue(T.Snapshot(main:1,screens:[1:screen(1),8:screen(8,1512)]).preserving(before,owned:8))
        XCTAssertFalse(T.Snapshot(main:1,screens:[1:screen(1,1),8:screen(8,1512)]).preserving(before,owned:8))
        XCTAssertFalse(T.Phase.failedUnknown.mayBegin);XCTAssertFalse(T.Phase.failedUnknown.mayPark)
        XCTAssertFalse(T.Phase.verifying.mayPark);XCTAssertTrue(T.Phase.verified.mayPark)
    }
    func testUnrepresentableCoordinateRejected() {
        let before=T.Snapshot(main:1,screens:[1:screen(1),2:screen(2,Double(Int32.max))])
        let after=T.Snapshot(main:1,screens:before.screens.merging([8:screen(8)]) { _,new in new })
        XCTAssertThrowsError(try T.plan(before:before,after:after,owned:8))
    }
}

extension PhoneHostDisplayTopologyTests {
    func testPreexistingMirrorSlaveIsNotDetachedByOriginWhenOwnedTakesMain() throws {
        let before=T.Snapshot(main:1,screens:[1:screen(1,member:true),2:screen(2,mirror:1,member:true)])
        let after=T.Snapshot(main:8,screens:[1:screen(1,-1920,member:true),2:screen(2,-1920,mirror:1,member:true),8:screen(8)])
        let p=try T.plan(before:before,after:after,owned:8)
        XCTAssertFalse(p.origins.contains { $0.0 == 2 })
        XCTAssertTrue(p.mirrors.contains { $0.0 == 2 && $0.1 == 1 })
    }
    func testOriginalSlaveJoiningOwnedRestoresItsOriginalMasterLast() throws {
        let before=T.Snapshot(main:1,screens:[1:screen(1,member:true),2:screen(2,mirror:1,member:true)])
        let after=T.Snapshot(main:8,screens:[1:screen(1,mirror:8,member:true),2:screen(2,mirror:8,member:true),8:screen(8,member:true)])
        let p=try T.plan(before:before,after:after,owned:8)
        XCTAssertFalse(p.origins.contains { $0.0 == 2 })
        XCTAssertEqual(p.mirrors.last?.0,2);XCTAssertEqual(p.mirrors.last?.1,1)
    }
}

extension PhoneHostDisplayTopologyTests {
    func testLossOfVerifiedOwnedTopologyLatchesAcrossRecovery() {
        var phase=T.Phase.verified
        XCTAssertFalse(phase.validate(false));XCTAssertEqual(phase,.failedUnknown)
        XCTAssertFalse(phase.validate(true));XCTAssertFalse(phase.mayBegin);XCTAssertFalse(phase.mayPark)
    }
    func testIncompletePriorSnapshotRejectedBeforeCreationAdmission() {
        XCTAssertFalse(T.Snapshot(main:9,screens:[1:screen(1)]).usable)
        XCTAssertFalse(T.Snapshot(main:1,screens:[1:screen(1,1)]).usable)
        XCTAssertFalse(T.Snapshot(main:1,screens:[1:screen(1,width:Double.nan)]).usable)
    }
}
