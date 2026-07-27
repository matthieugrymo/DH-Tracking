import Toybox.Lang;
import Toybox.Math;

//! Per-run accumulator — one instance per descent, i.e. one FIT lap
//! (spec §3.1).
//!
//! Pure logic, fed with values sampled by the caller, so it can be unit tested
//! outside the simulator (spec §9).
class RunStats {

    //! 1-based run number, matching "DESCENTE N°x" on screen.
    public var index as Number;

    public var startTimeMs as Number;
    public var endTimeMs as Number or Null = null;
    public var startAltitudeM as Float;
    public var endAltitudeM as Float;
    //! Lowest altitude reached during the run — see `dropM`.
    public var lowestAltitudeM as Float;
    public var distanceM as Float = 0.0;
    public var maxSpeedMps as Float = 0.0;
    public var maxHeartRate as Number = 0;

    private var _hrSum as Number = 0;
    private var _hrCount as Number = 0;
    private var _lastTimeMs as Number;
    private var _lastCumulativeDistanceM as Float or Null = null;

    function initialize(runIndex as Number, timeMs as Number, altitudeM as Float) {
        index = runIndex;
        startTimeMs = timeMs;
        _lastTimeMs = timeMs;
        startAltitudeM = altitudeM;
        endAltitudeM = altitudeM;
        lowestAltitudeM = altitudeM;
    }

    //! Feed one 1 Hz sample taken while the run is in progress.
    //!
    //! @param cumulativeDistanceM the activity's elapsed distance, preferred
    //!        because the watch fuses GPS and wheel data; when null (GPS lost)
    //!        the distance falls back to integrating `speedMps`.
    function update(altitudeM as Float or Null, speedMps as Float or Null,
                    cumulativeDistanceM as Float or Null,
                    heartRate as Number or Null, timeMs as Number) as Void {
        var deltaMs = timeMs - _lastTimeMs;
        _lastTimeMs = timeMs;

        if (altitudeM != null) {
            endAltitudeM = altitudeM;
            if (altitudeM < lowestAltitudeM) {
                lowestAltitudeM = altitudeM;
            }
        }

        if (cumulativeDistanceM != null) {
            var previous = _lastCumulativeDistanceM;
            if (previous != null && cumulativeDistanceM > previous) {
                distanceM += cumulativeDistanceM - previous;
            }
            _lastCumulativeDistanceM = cumulativeDistanceM;
        } else if (speedMps != null && deltaMs > 0) {
            distanceM += speedMps * deltaMs / 1000.0;
        }

        if (speedMps != null && speedMps > maxSpeedMps) {
            maxSpeedMps = speedMps;
        }

        if (heartRate != null && heartRate > 0) {
            _hrSum += heartRate;
            _hrCount += 1;
            if (heartRate > maxHeartRate) {
                maxHeartRate = heartRate;
            }
        }
    }

    function close(timeMs as Number) as Void {
        endTimeMs = timeMs;
    }

    //! Spec §3.1: altitude at run start minus altitude at run end.
    //!
    //! "Run end" is the *lowest* point reached rather than the altitude at the
    //! instant the state machine switched away from DESCENT. The LIFT condition
    //! needs 10 m of gain measured over a 20 s window, so the switch happens
    //! roughly 20 s after boarding, by which time a chairlift has already
    //! climbed tens of metres. Taking the altitude at that instant would shave
    //! that climb off every single run and blow the +/-3 % accuracy target in
    //! spec §11. The bottom of a lift-served descent is always the minimum, so
    //! the minimum is the honest end point.
    //!
    //! Clamped at zero so a degenerate run never subtracts from the day.
    function dropM() as Float {
        var drop = startAltitudeM - lowestAltitudeM;
        return drop > 0.0 ? drop : 0.0;
    }

    function durationMs() as Number {
        var end = endTimeMs;
        return (end == null ? _lastTimeMs : end) - startTimeMs;
    }

    function durationSec() as Number {
        return durationMs() / 1000;
    }

    function avgSpeedMps() as Float {
        var ms = durationMs();
        return ms > 0 ? distanceM * 1000.0 / ms : 0.0;
    }

    //! Vertical speed in metres per hour (spec §3.1).
    function verticalSpeedMph() as Float {
        var ms = durationMs();
        return ms > 0 ? dropM() * 3600000.0 / ms : 0.0;
    }

    //! Average grade in percent: drop over *horizontal* distance (spec §3.1).
    function avgSlopePct() as Float {
        var drop = dropM();
        var horizontal = distanceM * distanceM - drop * drop;
        if (horizontal <= 0.0) {
            return 0.0;
        }
        horizontal = Math.sqrt(horizontal).toFloat();
        return horizontal > 0.0 ? drop * 100.0 / horizontal : 0.0;
    }

    function avgHeartRate() as Number {
        return _hrCount > 0 ? _hrSum / _hrCount : 0;
    }
}

//! Day aggregates (spec §3.2). Owns the run currently in progress.
class SessionStats {

    public var runCount as Number = 0;
    public var totalDropM as Float = 0.0;
    public var totalDistanceM as Float = 0.0;
    public var totalDescentMs as Number = 0;
    public var maxSpeedMps as Float = 0.0;
    public var bestRun as RunStats or Null = null;
    public var liftMs as Number = 0;
    public var idleMs as Number = 0;
    public var dayStartMs as Number;
    public var currentRun as RunStats or Null = null;

    function initialize(timeMs as Number) {
        dayStartMs = timeMs;
    }

    //! @param altitudeM altitude at the *top* of the run — the caller should
    //!        look back over the detection window rather than pass the altitude
    //!        at the instant of detection (see `LiftDetector.altitudeBefore`).
    function startRun(timeMs as Number, altitudeM as Float or Null) as RunStats {
        runCount += 1;
        var run = new RunStats(runCount, timeMs, altitudeM == null ? 0.0 : altitudeM);
        currentRun = run;
        return run;
    }

    function updateRun(altitudeM as Float or Null, speedMps as Float or Null,
                       cumulativeDistanceM as Float or Null,
                       heartRate as Number or Null, timeMs as Number) as Void {
        var run = currentRun;
        if (run != null) {
            run.update(altitudeM, speedMps, cumulativeDistanceM, heartRate, timeMs);
            if (run.maxSpeedMps > maxSpeedMps) {
                maxSpeedMps = run.maxSpeedMps;
            }
        }
    }

    //! Close the run in progress and fold it into the day totals.
    //! Returns the finished run, or null when no run was open.
    function endRun(timeMs as Number) as RunStats or Null {
        var run = currentRun;
        if (run == null) {
            return null;
        }
        run.close(timeMs);
        currentRun = null;

        totalDropM += run.dropM();
        totalDistanceM += run.distanceM;
        totalDescentMs += run.durationMs();

        var best = bestRun;
        if (best == null || run.dropM() > best.dropM()) {
            bestRun = run;
        }
        return run;
    }

    //! Accumulate wall time against the state it was spent in. Descent time is
    //! the sum of the run durations, so only lift and idle are tracked here.
    function addStateTime(state as Number, deltaMs as Number) as Void {
        if (deltaMs <= 0) {
            return;
        }
        if (state == Config.STATE_LIFT) {
            liftMs += deltaMs;
        } else if (state == Config.STATE_IDLE) {
            idleMs += deltaMs;
        }
    }

    //! Descent time including the run in progress.
    function descentMs() as Number {
        var run = currentRun;
        return run == null ? totalDescentMs : totalDescentMs + run.durationMs();
    }

    function elapsedMs(nowMs as Number) as Number {
        return nowMs - dayStartMs;
    }

    //! Spec §3.2: descent time over total elapsed time, in percent.
    function descentRatioPct(nowMs as Number) as Float {
        var elapsed = elapsedMs(nowMs);
        return elapsed > 0 ? descentMs() * 100.0 / elapsed : 0.0;
    }
}
