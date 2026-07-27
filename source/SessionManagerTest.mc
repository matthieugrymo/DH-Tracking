import Toybox.Lang;
import Toybox.Test;

//! Integration tests for the recording wrapper (spec §3.3, §8).
//!
//! Unlike the detector tests these do touch the watch APIs — they run against
//! the simulator's real `ActivityRecording` implementation, which is the only
//! way to check that the session options and the four developer fields are
//! actually accepted.

//! Ouverture de session, chrono, lap, champs dev, enregistrement (spec §8).
(:test)
function testSessionManagerRecordingCycle(logger as Logger) as Boolean {
    var manager = new SessionManager();

    var opened = manager.open();
    var openTwiceIsIdempotent = manager.open();
    var idleBeforeStart = !manager.isRecording();

    manager.startTimer();
    var recordingAfterStart = manager.isRecording();

    // A run ends: lap field first, then the lap, then the session totals.
    manager.setRunDrop(215.7);
    manager.addLap();
    manager.setSessionTotals(1, 215.7, 120);

    manager.stopTimer();
    var pausedAfterStop = !manager.isRecording();

    // The timer resumes for a second run without reopening the session.
    manager.startTimer();
    var resumed = manager.isRecording();
    manager.setRunDrop(180.2);
    manager.addLap();
    manager.setSessionTotals(2, 395.9, 240);

    var saved = manager.save();
    var closedAfterSave = !manager.isOpen();
    var secondSaveIsNoop = !manager.save();

    logger.debug("opened=" + opened + " idle=" + idleBeforeStart
                 + " recording=" + recordingAfterStart + " paused=" + pausedAfterStop
                 + " resumed=" + resumed + " saved=" + saved
                 + " closed=" + closedAfterSave);

    return opened && openTwiceIsIdempotent && idleBeforeStart
           && recordingAfterStart && pausedAfterStop && resumed
           && saved && closedAfterSave && secondSaveIsNoop;
}

//! « Supprimer » dans le menu de fin (spec §6) libère bien la session.
(:test)
function testSessionManagerDiscard(logger as Logger) as Boolean {
    var manager = new SessionManager();
    manager.open();
    manager.startTimer();
    manager.setRunDrop(42.0);
    manager.addLap();

    var discarded = manager.discard();
    var closed = !manager.isOpen();

    logger.debug("discarded=" + discarded + " closed=" + closed);
    return discarded && closed;
}

//! Les accesseurs ne doivent jamais planter avant l'ouverture de la session —
//! l'app appelle `stopTimer`/`save` depuis `onStop` quoi qu'il arrive.
(:test)
function testSessionManagerIsSafeBeforeOpen(logger as Logger) as Boolean {
    var manager = new SessionManager();

    manager.startTimer();
    manager.stopTimer();
    manager.addLap();
    manager.setRunDrop(10.0);
    manager.setSessionTotals(0, 0.0, 0);

    logger.debug("open=" + manager.isOpen() + " recording=" + manager.isRecording());
    return !manager.isOpen() && !manager.isRecording()
           && !manager.save() && !manager.discard();
}
