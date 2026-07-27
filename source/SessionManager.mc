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
            _session = null;
            return false;
        }
    }

    private function _createFields(session as ActivityRecording.Session) as Void {
        _runCountField = session.createField(
            "run_count", FIELD_RUN_COUNT, FitContributor.DATA_TYPE_UINT16,
            {:mesgType => FitContributor.MESG_TYPE_SESSION, :units => "runs"});
        _totalDropField = session.createField(
            "total_vertical_drop", FIELD_TOTAL_DROP, FitContributor.DATA_TYPE_FLOAT,
            {:mesgType => FitContributor.MESG_TYPE_SESSION, :units => "m"});
        _runDropField = session.createField(
            "run_vertical_drop", FIELD_RUN_DROP, FitContributor.DATA_TYPE_FLOAT,
            {:mesgType => FitContributor.MESG_TYPE_LAP, :units => "m"});
        _liftTimeField = session.createField(
            "lift_time", FIELD_LIFT_TIME, FitContributor.DATA_TYPE_UINT32,
            {:mesgType => FitContributor.MESG_TYPE_SESSION, :units => "s"});
    }

    function isOpen() as Boolean {
        return _session != null;
    }

    function isRecording() as Boolean {
        var session = _session;
        return session != null && session.isRecording();
    }

    //! Resume the timer — called on every entry into DESCENT (spec §8).
    function startTimer() as Void {
        var session = _session;
        if (session != null && !session.isRecording()) {
            session.start();
        }
    }

    //! Pause the timer — called on every exit from DESCENT. Does not close the
    //! session (spec §8).
    function stopTimer() as Void {
        var session = _session;
        if (session != null && session.isRecording()) {
            session.stop();
        }
    }

    //! One lap per run, exactly like the alpine ski profile (spec §8).
    //! `setRunDrop` must be called first so the value lands on this lap.
    function addLap() as Void {
        var session = _session;
        if (session != null) {
            session.addLap();
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
        if (session.isRecording()) {
            session.stop();
        }
        var saved = session.save();
        _finished = true;
        _release();
        return saved;
    }

    function discard() as Boolean {
        var session = _session;
        if (session == null || _finished) {
            return false;
        }
        if (session.isRecording()) {
            session.stop();
        }
        var discarded = session.discard();
        _finished = true;
        _release();
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
