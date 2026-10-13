import CoreGraphics

/// The three scroll axes exposed by Quartz: vertical, horizontal, and a reserved third axis.
public struct ScrollAxes<Value: Equatable & Sendable>: Equatable, Sendable {
    public var vertical: Value
    public var horizontal: Value
    public var third: Value

    public init(vertical: Value, horizontal: Value, third: Value) {
        self.vertical = vertical
        self.horizontal = horizontal
        self.third = third
    }
}

/// A value snapshot, so transforming an event never depends on setter side effects.
public struct ScrollSample: Equatable, Sendable {
    public var isContinuous: Bool
    public var scrollPhase: Int64
    public var momentumPhase: Int64
    public var lines: ScrollAxes<Int64>
    public var points: ScrollAxes<Int64>
    public var fixed: ScrollAxes<Double>

    public init(
        isContinuous: Bool = false,
        scrollPhase: Int64 = 0,
        momentumPhase: Int64 = 0,
        lines: ScrollAxes<Int64> = .init(vertical: 0, horizontal: 0, third: 0),
        points: ScrollAxes<Int64> = .init(vertical: 0, horizontal: 0, third: 0),
        fixed: ScrollAxes<Double> = .init(vertical: 0, horizontal: 0, third: 0)
    ) {
        self.isContinuous = isContinuous
        self.scrollPhase = scrollPhase
        self.momentumPhase = momentumPhase
        self.lines = lines
        self.points = points
        self.fixed = fixed
    }

    init(event: CGEvent) {
        self.init(
            isContinuous: event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0,
            scrollPhase: event.getIntegerValueField(.scrollWheelEventScrollPhase),
            momentumPhase: event.getIntegerValueField(.scrollWheelEventMomentumPhase),
            lines: .init(
                vertical: event.getIntegerValueField(.scrollWheelEventDeltaAxis1),
                horizontal: event.getIntegerValueField(.scrollWheelEventDeltaAxis2),
                third: event.getIntegerValueField(.scrollWheelEventDeltaAxis3)
            ),
            points: .init(
                vertical: event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1),
                horizontal: event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2),
                third: event.getIntegerValueField(.scrollWheelEventPointDeltaAxis3)
            ),
            fixed: .init(
                vertical: event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1),
                horizontal: event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2),
                third: event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis3)
            )
        )
    }

    func writeDeltas(to event: CGEvent) {
        event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: lines.vertical)
        event.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: lines.horizontal)
        event.setIntegerValueField(.scrollWheelEventDeltaAxis3, value: lines.third)
        event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: points.vertical)
        event.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: points.horizontal)
        event.setIntegerValueField(.scrollWheelEventPointDeltaAxis3, value: points.third)
        // The double accessors preserve the 16.16 fixed-point fractions.
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: fixed.vertical)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: fixed.horizontal)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis3, value: fixed.third)
    }
}

public enum ScrollTransformer {
    /// Quartz does not expose a reliable mouse-versus-trackpad device ID here.
    /// The continuous flag describes pixel precision, not the input device:
    /// MX Master 3 wheels report continuous events with both phases zero.
    /// Native trackpad gestures have a scroll phase; their inertia has a
    /// momentum phase even when the scroll phase is zero. Preserve both.
    public static func isMouseWheel(_ sample: ScrollSample) -> Bool {
        sample.scrollPhase == 0 && sample.momentumPhase == 0
    }

    public static func reversedIfMouse(_ sample: ScrollSample, enabled: Bool = true) -> ScrollSample {
        guard enabled, isMouseWheel(sample) else { return sample }
        var output = sample
        output.lines = reverse(sample.lines)
        output.points = reverse(sample.points)
        output.fixed = .init(
            vertical: -sample.fixed.vertical,
            horizontal: -sample.fixed.horizontal,
            third: -sample.fixed.third
        )
        return output
    }

    /// Mutates only scroll deltas, keeping the original event and its metadata.
    @discardableResult
    static func reverseMouseEvent(_ event: CGEvent) -> Bool {
        guard event.type == .scrollWheel else { return false }
        let sample = ScrollSample(event: event)
        guard isMouseWheel(sample) else { return false }
        reversedIfMouse(sample).writeDeltas(to: event)
        return true
    }

    private static func reverse(_ axes: ScrollAxes<Int64>) -> ScrollAxes<Int64> {
        .init(vertical: negate(axes.vertical), horizontal: negate(axes.horizontal), third: negate(axes.third))
    }

    private static func negate(_ value: Int64) -> Int64 {
        // Int64.min has no positive counterpart. Saturate rather than overflow.
        value == .min ? .max : -value
    }
}
