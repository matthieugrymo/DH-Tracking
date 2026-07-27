import Toybox.Lang;
import Toybox.Activity;
import Toybox.ActivityRecording;
import Toybox.FitContributor;
import Toybox.WatchUi;

//! Thin wrapper around `ActivityRecording` plus the four FIT developer fields
//! Garmin does not expose natively for cycling (spec §3.3, §8).
class SessionManager {

    // Developer field ids — stable, they identify the fields in the FIT file.
    private const FIELD_RUN_COUNT    = 0;
    private const FIELD_TOTAL_DROP   = 1;
    private const FIELD_RUN_DROP     = 2;
    private const FIELD_LIFT_TIME    = 3;

    private var _session as ActivityRecording.Session or Null = null;
    private var _runCountField as FitContributor.Field or Null = null;
    private var _totalDropField as FitContributor.Field or Null = null;
    private var _runDropField as FitContributor.Field or Null = null;
    private var _liftTimeField as FitContributor.Field or Null = null;
    private var _finished as Boolean = false;

    function initialize() {
    }

    //! Create the recording session and its developer fields. The timer is not
    //! started here: spec §8 starts it on the first DESCENT.
    function open() as Boolean {
        if (_session != null) {
            return true;
        }
        try {
            var session = ActivityRecording.createSession({
                :name => WatchUi.loadResource($.Rez.Strings.SessionName) as String,
                :sport => Activity.SPORT_CYCLING,
                :subSport => Activity.SUB_SPORT_DOWNHILL
            });
            _session = session;
            _createFields(session);
            _finished = false;
            return true;
        } catch (ex) {
            // A field allocation can fail after the Session itself was created.
            // Close that partial session so a later START can retry cleanly.
            var partial = _session;
            if (partial != null) {
                try {
                    partial.discard();
                } catch (discardEx) {
                    // The caller still receives false and keeps the UI unarmed.
                }
            }
            _release();
            return false;
        }
    }

    private function _createFields(session as ActivityRecording.Session) as Void {
        var runsUnit = WatchUi.loadResource($.Rez.Strings.FitRunsUnit) as String;
        var metersUnit = WatchUi.loadResource($.Rez.Strings.FitMetersUnit) as String;
        var secondsUnit = WatchUi.loadResource($.Rez.Strings.FitSecondsUnit) as String;
        _runCountField = session.createField(
            "run_count", FIELD_RUN_COUNT, FitContributor.DATA_TYPE_UINT16,
            {:mesgType => FitContributor.MESG_TYPE_SESSION, :units => runsUnit});
        _totalDropField = session.createField(
            "total_vertical_drop", FIELD_TOTAL_DROP, FitContributor.DATA_TYPE_FLOAT,
            {:mesgType => FitContributor.MESG_TYPE_SESSION, :units => metersUnit});
        _runDropField = session.createField(
            "run_vertical_drop", FIELD_RUN_DROP, FitContributor.DATA_TYPE_FLOAT,
            {:mesgType => FitContributor.MESG_TYPE_LAP, :units => metersUnit});
        _liftTimeField = session.createField(
            "lift_time", FIELD_LIFT_TIME, FitContributor.DATA_TYPE_UINT32,
            {:mesgType => FitContributor.MESG_TYPE_SESSION, :units => secondsUnit});
    }

    function isOpen() as Boolean {
        return _session != null;
    }

    function isRecording() as Boolean {
        var session = _session;
        return session != null && session.isRecording();
    }

    //! Resume the timer — called on every entry into DESCENT (spec §8).
    function startTimer() as Boolean {
        var session = _session;
        if (session == null) {
            return false;
        }
        if (session.isRecording()) {
            return true;
        }
        try {
            return session.start();
        } catch (ex) {
            return false;
        }
    }

    //! Pause the timer — called on every exit from DESCENT. Does not close the
    //! session (spec §8).
    function stopTimer() as Boolean {
        var session = _session;
        if (session == null) {
            return false;
        }
        if (!session.isRecording()) {
            return true;
        }
        try {
            return session.stop();
        } catch (ex) {
            return false;
        }
    }

    //! One lap per run, exactly like the alpine ski profile (spec §8).
    //! `setRunDrop` must be called first so the value lands on this lap.
    function addLap() as Boolean {
        var session = _session;
        if (session == null || !session.isRecording()) {
            return false;
        }
        try {
            return session.addLap();
        } catch (ex) {
            return false;
        }
    }

    function setRunDrop(dropM as Float) as Void {
        var field = _runDropField;
        if (field != null) {
            field.setData(dropM);
        }
    }

    //! Session-scope developer fields. Written on every run end so a crash or a
    //! flat battery still leaves usable totals in the FIT file.
    function setSessionTotals(runCount as Number, totalDropM as Float,
                              liftTimeSec as Number) as Void {
        var runCountField = _runCountField;
        if (runCountField != null) {
            runCountField.setData(runCount);
        }
        var totalDropField = _totalDropField;
        if (totalDropField != null) {
            totalDropField.setData(totalDropM);
        }
        var liftTimeField = _liftTimeField;
        if (liftTimeField != null) {
            liftTimeField.setData(liftTimeSec);
        }
    }

    //! End of day (spec §8): the only place the session is closed.
    function save() as Boolean {
        var session = _session;
        if (session == null || _finished) {
            return false;
        }
        if (session.isRecording() && !stopTimer()) {
            return false;
        }
        var saved = false;
        try {
            saved = session.save();
        } catch (ex) {
            return false;
        }
        if (saved) {
            _finished = true;
            _release();
        }
        return saved;
    }

    function discard() as Boolean {
        var session = _session;
        if (session == null || _finished) {
            return false;
        }
        if (session.isRecording() && !stopTimer()) {
            return false;
        }
        var discarded = false;
        try {
            discarded = session.discard();
        } catch (ex) {
            return false;
        }
        if (discarded) {
            _finished = true;
            _release();
        }
        return discarded;
    }

    //! Drop every reference so the VM can reclaim the session allocation.
    private function _release() as Void {
        _runCountField = null;
        _totalDropField = null;
        _runDropField = null;
        _liftTimeField = null;
        _session = null;
    }
}
