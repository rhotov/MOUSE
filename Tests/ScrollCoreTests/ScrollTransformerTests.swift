import CoreGraphics
import Foundation
import Testing
@testable import ScrollCore

struct ScrollTransformerTests {
    private let mouse = ScrollSample(
        lines: .init(vertical: 2, horizontal: -3, third: 1),
        points: .init(vertical: 40, horizontal: -61, third: 9),
        fixed: .init(vertical: 2.25, horizontal: -3.5, third: 0.125)
    )

    @Test func testMouseReversesAllDeltaRepresentationsAndAxes() {
        let result = ScrollTransformer.reversedIfMouse(mouse)
        #expect(result.lines == .init(vertical: -2, horizontal: 3, third: -1))
        #expect(result.points == .init(vertical: -40, horizontal: 61, third: -9))
        #expect(result.fixed == .init(vertical: -2.25, horizontal: 3.5, third: -0.125))
        #expect(ScrollTransformer.reversedIfMouse(result) == mouse)
    }

    @Test func testDisabledTransformationIsIdentity() {
        for isContinuous in [false, true] {
            var sample = mouse
            sample.isContinuous = isContinuous
            #expect(ScrollTransformer.reversedIfMouse(sample, enabled: false) == sample)
        }
    }

    @Test func testZeroStaysZeroAndMinimumIntegerDoesNotOverflow() {
        let boundary = ScrollSample(
            lines: .init(vertical: .min, horizontal: .max, third: 0),
            points: .init(vertical: .min, horizontal: 0, third: .max)
        )
        let result = ScrollTransformer.reversedIfMouse(boundary)
        #expect(result.lines == .init(vertical: .max, horizontal: -.max, third: 0))
        #expect(result.points == .init(vertical: .max, horizontal: 0, third: -.max))
        #expect(result.fixed == boundary.fixed)
    }

    @Test func testQuartzEventFieldsAndMetadata() throws {
        let event = try #require(CGEvent(
            scrollWheelEvent2Source: nil, units: .line, wheelCount: 2,
            wheel1: 2, wheel2: -3, wheel3: 0
        ))
        mouse.writeDeltas(to: event)
        event.flags = [.maskShift, .maskControl]
        event.setIntegerValueField(.eventSourceUserData, value: 12345)
        event.setIntegerValueField(.scrollWheelEventScrollCount, value: 6)
        let original = ScrollSample(event: event)
        let timestamp = event.timestamp

        #expect(ScrollTransformer.reverseMouseEvent(event))
        #expect(ScrollSample(event: event) == ScrollTransformer.reversedIfMouse(original))
        #expect(event.flags == [.maskShift, .maskControl])
        #expect(event.timestamp == timestamp)
        #expect(event.getIntegerValueField(.eventSourceUserData) == 12345)
        #expect(event.getIntegerValueField(.scrollWheelEventScrollCount) == 6)
    }

    @Test func testUnphasedPixelMouseReversesAllDeltasAndPreservesMetadata() throws {
        // MX Master 3 reports precise pixel deltas without gesture or momentum phases.
        let event = try scrollEvent(isContinuous: true)
        let timestamp = event.timestamp
        let original = ScrollSample(event: event)
        #expect(original.isContinuous)
        #expect(original.scrollPhase == 0)
        #expect(original.momentumPhase == 0)
        #expect(original.lines == mouse.lines)
        #expect(original.points == mouse.points)
        #expect(original.fixed == mouse.fixed)

        #expect(ScrollTransformer.reverseMouseEvent(event))
        #expect(ScrollSample(event: event) == reversedMouse(isContinuous: true))
        #expect(event.flags == [.maskShift, .maskControl])
        #expect(event.timestamp == timestamp)
        #expect(event.getIntegerValueField(.eventSourceUserData) == 12345)
        #expect(event.getIntegerValueField(.scrollWheelEventScrollCount) == 6)

        #expect(ScrollTransformer.reverseMouseEvent(event))
        #expect(ScrollSample(event: event) == original)
    }

    // Quartz phase values, including combined gesture bits and a reserved bit.
    @Test(arguments: [Int64(1), 2, 4, 8, 128, 3, 129, 256], [false, true])
    func testGestureEventIsUntouchedIncludingMetadata(phase: Int64, isContinuous: Bool) throws {
        let event = try scrollEvent(isContinuous: isContinuous, scrollPhase: phase)
        let sample = ScrollSample(event: event)
        let original = try #require(event.data) as Data

        #expect(ScrollTransformer.reversedIfMouse(sample) == sample)
        #expect(!ScrollTransformer.reverseMouseEvent(event))
        #expect(try #require(event.data) as Data == original)
    }

    // Quartz momentum uses 1 = begin, 2 = continue, and 3 = end.
    @Test(arguments: [Int64(1), 2, 3], [false, true])
    func testMomentumEventIsUntouchedIncludingMetadata(momentumPhase: Int64, isContinuous: Bool) throws {
        let event = try scrollEvent(isContinuous: isContinuous, momentumPhase: momentumPhase)
        let sample = ScrollSample(event: event)
        let original = try #require(event.data) as Data

        #expect(sample.scrollPhase == 0)
        #expect(sample.momentumPhase == momentumPhase)
        #expect(ScrollTransformer.reversedIfMouse(sample) == sample)
        #expect(!ScrollTransformer.reverseMouseEvent(event))
        #expect(try #require(event.data) as Data == original)
    }

    @Test func testUnknownNonzeroPhasesArePreserved() {
        // Quartz normalizes unsupported momentum values when writing events;
        // exercise future/unknown phases directly through the public snapshot.
        for isContinuous in [false, true] {
            for phase: Int64 in [-1, 128, 256] {
                var sample = mouse
                sample.isContinuous = isContinuous
                sample.scrollPhase = phase
                #expect(ScrollTransformer.reversedIfMouse(sample) == sample)
                sample.scrollPhase = 0
                sample.momentumPhase = phase
                #expect(ScrollTransformer.reversedIfMouse(sample) == sample)
            }
        }
    }

    @Test func testPixelMouseReversesImmediatelyAfterTrackpadGestureAndMomentum() throws {
        let trackpadPhases: [(scroll: Int64, momentum: Int64)] = [
            (128, 0), (1, 0), (2, 0), (4, 0),
            (0, 1), (0, 2), (0, 3)
        ]
        for phase in trackpadPhases {
            let event = try scrollEvent(
                isContinuous: true, scrollPhase: phase.scroll, momentumPhase: phase.momentum
            )
            let original = try #require(event.data) as Data
            #expect(!ScrollTransformer.reverseMouseEvent(event))
            #expect(try #require(event.data) as Data == original)
        }

        let mouseEvent = try scrollEvent(isContinuous: true)
        #expect(ScrollTransformer.reverseMouseEvent(mouseEvent))
        #expect(ScrollSample(event: mouseEvent) == reversedMouse(isContinuous: true))
    }

    @Test func testNonScrollEventIsIgnored() throws {
        let event = try #require(CGEvent(
            mouseEventSource: nil, mouseType: .mouseMoved,
            mouseCursorPosition: .zero, mouseButton: .left
        ))
        #expect(!ScrollTransformer.reverseMouseEvent(event))
    }

    private func scrollEvent(
        isContinuous: Bool, scrollPhase: Int64 = 0, momentumPhase: Int64 = 0
    ) throws -> CGEvent {
        let event = try #require(CGEvent(
            scrollWheelEvent2Source: nil, units: isContinuous ? .pixel : .line, wheelCount: 3,
            wheel1: 2, wheel2: -3, wheel3: 1
        ))
        mouse.writeDeltas(to: event)
        event.flags = [.maskShift, .maskControl]
        event.setIntegerValueField(.eventSourceUserData, value: 12345)
        event.setIntegerValueField(.scrollWheelEventScrollCount, value: 6)
        event.setIntegerValueField(.scrollWheelEventScrollPhase, value: scrollPhase)
        event.setIntegerValueField(.scrollWheelEventMomentumPhase, value: momentumPhase)
        return event
    }

    private func reversedMouse(isContinuous: Bool) -> ScrollSample {
        ScrollSample(
            isContinuous: isContinuous,
            lines: .init(vertical: -2, horizontal: 3, third: -1),
            points: .init(vertical: -40, horizontal: 61, third: -9),
            fixed: .init(vertical: -2.25, horizontal: 3.5, third: -0.125)
        )
    }
}
