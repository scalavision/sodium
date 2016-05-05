/**
 * A timer system implementation where the clock is a floating point number of seconds
 * since program start.
 */
public class SecondsTimerSystem: TimerSystem<Double> {
    public init() {
        super.init(impl: SecondsTimerSystemImpl())
    }
}

