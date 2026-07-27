import Toybox.Lang;

//! IDLE / LIFT / DESCENT state machine (spec §4.3).
//!
//! Pure logic: it takes `(altitude, speed, heading, accelVariance, timestamp)`
//! and emits `onRunStart` / `onRunEnd` through two callbacks. No watch API is
//! used, which is what makes it testable outside the simulator (spec §9).
class LiftDetector {

    //! Current state, one of `Config.STATE_*`.
    public var state as Number = Config.STATE_IDLE;

    private var _t as Config.Thresholds;
    private var _onRunStart as Method or Null;
    private var _onRunEnd as Method or Null;

    // Raw barometer samples awaiting the 3 s moving average (spec §4.4).
    private var _rawAlt as Array<Float>;
    private var _rawCount as Number = 0;
    private var _rawNext as Number = 0;

    // Ring buffer of smoothed samples over `Config.HISTORY_SEC` (spec §4.2).
    private var _alt as Array<Float>;
    private var _time as Array<Number>;
    private var _size as Number;
    private var _count as Number = 0;
    private var _next as Number = 0;

    // Hysteresis and the DESCENT -> IDLE dwell timer.
    private var _lockedUntilMs as Number or Null = null;
    private var _idleSinceMs as Number or Null = null;
    private var _idleRefAlt as Float or Null = null;

    private var _smoothedAlt as Float or Null = null;
    private var _lastSampleMs as Number or Null = null;

    //! @param thresholds resolved detector thresholds
    //! @param onRunStart called with the timestamp on entry into DESCENT
    //! @param onRunEnd   called with the timestamp on exit from DESCENT
    function initialize(thresholds as Config.Thresholds,
                        onRunStart as Method or Null,
                        onRunEnd as Method or Null) {
        _t = thresholds;
        _onRunStart = onRunStart;
        _onRunEnd = onRunEnd;
        _size = Config.HISTORY_SEC;
        _alt = new Array<Float>[_size];
        _time = new Array<Number>[_size];
        _rawAlt = new Array<Float>[Config.ALT_SMOOTH_SEC];
    }

    //! Swap in a new threshold set — used when the user edits the settings
    //! from Garmin Connect Mobile mid-day. History is kept.
    function setThresholds(thresholds as Config.Thresholds) as Void {
        _t = thresholds;
    }

    //! Drop all history and return to IDLE. Does not emit events.
    function reset() as Void {
        state = Config.STATE_IDLE;
        _rawCount = 0;
        _rawNext = 0;
        _count = 0;
        _next = 0;
        _lockedUntilMs = null;
        _idleSinceMs = null;
        _idleRefAlt = null;
        _smoothedAlt = null;
        _lastSampleMs = null;
    }

    //! Smoothed altitude of the most recent sample, or null before the first
    //! usable reading.
    function altitude() as Float or Null {
        return _smoothedAlt;
    }

    //! Smoothed altitude roughly `secondsAgo` seconds back, or null when the
    //! buffer does not reach that far.
    //!
    //! A run is only recognised once 8 m have been lost, i.e. a few seconds
    //! after the rider actually dropped in, so the caller needs to look back to
    //! recover the real top of the run.
    function altitudeBefore(secondsAgo as Number) as Float or Null {
        var now = _lastSampleMs;
        if (now == null) {
            return null;
        }
        return _sampleAtOrBefore(now - secondsAgo * 1000);
    }

    //! True while the hysteresis lock blocks transitions (spec §4.4).
    function isLocked(timeMs as Number) as Boolean {
        var until = _lockedUntilMs;
        return until != null && timeMs < until;
    }

    //! Feed one 1 Hz sample and return the (possibly new) state.
    //!
    //! `altitudeM` null (barometer not ready yet) or `speedMps` null (GPS lost
    //! under tree cover) are treated as "condition not satisfied" — never as a
    //! reason to crash or to change state (spec §4.4).
    //!
    //! `headingRad` is part of the input tuple fixed by spec §9 and is accepted
    //! for that reason, but none of the §4.3 transition conditions gate on it:
    //! the straight-line track of a cable (§4.1) is already covered, more
    //! robustly, by altitude monotonicity plus the accelerometer.
    function update(altitudeM as Float or Null, speedMps as Float or Null,
                    headingRad as Float or Null, accelVarianceMg as Float or Null,
                    timeMs as Number) as Number {
        if (altitudeM == null) {
            return state;
        }

        var smoothed = _pushRaw(altitudeM);
        _smoothedAlt = smoothed;
        _lastSampleMs = timeMs;
        _pushSample(smoothed, timeMs);
        _updateIdleDwell(speedMps, smoothed, timeMs);

        if (isLocked(timeMs)) {
            return state;
        }

        if (state == Config.STATE_DESCENT) {
            if (_liftConditionsMet(accelVarianceMg, timeMs)) {
                _transitionTo(Config.STATE_LIFT, timeMs);
            } else if (_idleConditionsMet(timeMs)) {
                _transitionTo(Config.STATE_IDLE, timeMs);
            }
        } else {
            if (_descentConditionsMet(speedMps, accelVarianceMg, timeMs)) {
                _transitionTo(Config.STATE_DESCENT, timeMs);
            } else if (state == Config.STATE_IDLE
                       && _liftConditionsMet(accelVarianceMg, timeMs)) {
                _transitionTo(Config.STATE_LIFT, timeMs);
            }
        }

        return state;
    }

    //! Manual override for when detection gets it wrong (spec §6, START button).
    //! Bypasses every condition but still arms the hysteresis lock.
    function forceState(newState as Number, timeMs as Number) as Void {
        if (newState != state) {
            _transitionTo(newState, timeMs);
        }
    }

    // ------------------------------------------------------------------
    // Transition conditions (spec §4.3)
    // ------------------------------------------------------------------

    //! Altitude loss >= threshold over 6 s, AND speed >= 5 km/h, AND rough
    //! ground under the wheels.
    private function _descentConditionsMet(speedMps as Float or Null,
                                           accelVarianceMg as Float or Null,
                                           timeMs as Number) as Boolean {
        if (speedMps == null || speedMps < _t.descentMinSpeedMps) {
            return false;
        }

        var reference = _sampleAtOrBefore(timeMs - Config.DESCENT_WINDOW_SEC * 1000);
        if (reference == null) {
            return false;
        }
        var current = _smoothedAlt;
        if (current == null || reference - current < _t.descentDropM) {
            return false;
        }

        // Vibration is the strongest discriminator against a lift (spec §4.1),
        // but if the accelerometer is unavailable we degrade to altitude +
        // speed rather than never detecting a run at all.
        var rough = _t.accelRoughMg;
        if (rough != null && accelVarianceMg != null && accelVarianceMg < rough) {
            return false;
        }
        return true;
    }

    //! Altitude gain >= threshold over 20 s, AND a monotonic climb, AND
    //! (depending on the lift type) a quiet accelerometer.
    private function _liftConditionsMet(accelVarianceMg as Float or Null,
                                        timeMs as Number) as Boolean {
        var targetMs = timeMs - Config.LIFT_WINDOW_SEC * 1000;
        var referenceIndex = _indexAtOrBefore(targetMs);
        if (referenceIndex < 0) {
            return false;
        }

        var current = _smoothedAlt;
        var reference = _alt[_physical(referenceIndex)];
        if (current == null || current - reference < _t.liftGainM) {
            return false;
        }

        var deltas = _count - 1 - referenceIndex;
        if (deltas < Config.LIFT_MIN_SAMPLES) {
            return false;
        }
        var rising = 0;
        for (var i = referenceIndex; i < _count - 1; i++) {
            if (_alt[_physical(i + 1)] > _alt[_physical(i)]) {
                rising += 1;
            }
        }
        if (rising.toFloat() / deltas.toFloat() < _t.liftMonotonicRatio) {
            return false;
        }

        var smooth = _t.accelSmoothMg;
        if (smooth != null && accelVarianceMg != null && accelVarianceMg >= smooth) {
            return false;
        }
        return true;
    }

    //! Speed below 3 km/h and altitude stable for 90 s straight. Short stops
    //! on the trail must not stop the timer (spec §4.3).
    private function _idleConditionsMet(timeMs as Number) as Boolean {
        var since = _idleSinceMs;
        return since != null && timeMs - since >= Config.IDLE_HOLD_SEC * 1000;
    }

    //! Runs on every sample, including while the hysteresis lock is armed, so
    //! that a long stop is not restarted by an unrelated transition.
    private function _updateIdleDwell(speedMps as Float or Null,
                                      smoothedAlt as Float,
                                      timeMs as Number) as Void {
        var stopped = speedMps != null && speedMps < _t.idleMaxSpeedMps;
        var reference = _idleRefAlt;
        var stable = reference != null
                     && (smoothedAlt - reference).abs() <= _t.idleAltToleranceM;

        if (stopped && stable) {
            return; // keep the running dwell timer
        }
        _idleSinceMs = stopped ? timeMs : null;
        _idleRefAlt = stopped ? smoothedAlt : null;
    }

    private function _transitionTo(newState as Number, timeMs as Number) as Void {
        var previous = state;
        state = newState;
        _lockedUntilMs = timeMs + Config.TRANSITION_LOCK_SEC * 1000;
        _idleSinceMs = null;
        _idleRefAlt = null;

        var onRunEnd = _onRunEnd;
        if (previous == Config.STATE_DESCENT && onRunEnd != null) {
            onRunEnd.invoke(timeMs);
        }
        var onRunStart = _onRunStart;
        if (newState == Config.STATE_DESCENT && onRunStart != null) {
            onRunStart.invoke(timeMs);
        }
    }

    // ------------------------------------------------------------------
    // Ring buffers
    // ------------------------------------------------------------------

    //! Push a raw barometer reading and return the moving average over the
    //! last `Config.ALT_SMOOTH_SEC` samples (spec §4.4).
    private function _pushRaw(altitudeM as Float) as Float {
        _rawAlt[_rawNext] = altitudeM;
        _rawNext = (_rawNext + 1) % Config.ALT_SMOOTH_SEC;
        if (_rawCount < Config.ALT_SMOOTH_SEC) {
            _rawCount += 1;
        }
        var sum = 0.0;
        for (var i = 0; i < _rawCount; i++) {
            sum += _rawAlt[i];
        }
        return sum / _rawCount;
    }

    private function _pushSample(altitudeM as Float, timeMs as Number) as Void {
        _alt[_next] = altitudeM;
        _time[_next] = timeMs;
        _next = (_next + 1) % _size;
        if (_count < _size) {
            _count += 1;
        }
    }

    //! Physical slot of the `index`-th oldest buffered sample.
    private function _physical(index as Number) as Number {
        return (_next - _count + index + _size) % _size;
    }

    //! Chronological index of the newest sample at or before `targetMs`, or -1
    //! when the buffer does not reach that far back yet.
    private function _indexAtOrBefore(targetMs as Number) as Number {
        for (var i = _count - 1; i >= 0; i--) {
            if (_time[_physical(i)] <= targetMs) {
                return i;
            }
        }
        return -1;
    }

    private function _sampleAtOrBefore(targetMs as Number) as Float or Null {
        var index = _indexAtOrBefore(targetMs);
        return index < 0 ? null : _alt[_physical(index)];
    }
}
