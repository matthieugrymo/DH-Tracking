import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

//! Button handling (spec §6).
//!
//! START (top right)  : first press starts the day, later presses force the
//!                      transition the detector missed.
//! UP / DOWN          : switch between the two screens.
//! BACK/LAP           : swallowed — nothing must happen with gloves on.
//! MENU (long UP)     : end-of-day menu. The fenix 7 shares one physical
//!                      button between START and STOP and Connect IQ does not
//!                      report long presses on it, so MENU carries the STOP
//!                      role described in the spec.
class DhTrackerDelegate extends WatchUi.BehaviorDelegate {

    private var _view as DhTrackerView;

    function initialize(view as DhTrackerView) {
        BehaviorDelegate.initialize();
        _view = view;
    }

    function onSelect() as Boolean {
        var app = $.getApp();
        if (!app.armed) {
            app.startDay();
        } else {
            app.forceTransition();
        }
        WatchUi.requestUpdate();
        return true;
    }

    function onNextPage() as Boolean {
        _view.nextPage();
        WatchUi.requestUpdate();
        return true;
    }

    function onPreviousPage() as Boolean {
        _view.previousPage();
        WatchUi.requestUpdate();
        return true;
    }

    //! Inactive during the activity (spec §6).
    function onBack() as Boolean {
        return true;
    }

    function onMenu() as Boolean {
        showEndMenu();
        return true;
    }

    function showEndMenu() as Void {
        var menu = new WatchUi.Menu2({
            :title => WatchUi.loadResource($.Rez.Strings.MenuTitle) as String
        });
        menu.addItem(new WatchUi.MenuItem(
            WatchUi.loadResource($.Rez.Strings.MenuSave) as String, null, :save, null));
        menu.addItem(new WatchUi.MenuItem(
            WatchUi.loadResource($.Rez.Strings.MenuResume) as String, null, :resume, null));
        menu.addItem(new WatchUi.MenuItem(
            WatchUi.loadResource($.Rez.Strings.MenuDiscard) as String, null, :discard, null));
        WatchUi.pushView(menu, new EndMenuDelegate(), WatchUi.SLIDE_UP);
    }
}

//! Enregistrer / Reprendre / Supprimer (spec §6).
class EndMenuDelegate extends WatchUi.Menu2InputDelegate {

    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        var app = $.getApp();

        if (id == :save) {
            app.saveDay();
            System.exit();
        } else if (id == :discard) {
            app.discardDay();
            System.exit();
        } else {
            WatchUi.popView(WatchUi.SLIDE_DOWN);
        }
    }

    function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }
}
