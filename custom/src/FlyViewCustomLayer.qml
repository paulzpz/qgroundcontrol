/****************************************************************************
 *
 * (c) 2009-2019 QGROUNDCONTROL PROJECT <http://www.qgroundcontrol.org>
 *
 * QGroundControl is licensed according to the terms in the file
 * COPYING.md in the root of the source code directory.
 *
 * @file
 *   @author Gus Grubba <gus@auterion.com>
 */

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtCore

import QGroundControl
import QGroundControl.Controls
import QGroundControl.Palette
import QGroundControl.ScreenTools

import Custom.Widgets

Item {
    property var parentToolInsets                       // These insets tell you what screen real estate is available for positioning the controls in your overlay
    property var totalToolInsets: _totalToolInsets    // The insets updated for the custom overlay additions
    property var mapControl

    readonly property string noGPS: qsTr("NO GPS")

    Settings {
        id: flightBudgetSettings
        category: "InnovatechFlightBudget"

        property int safetyBufferS: 120
    }

    on_ActiveVehicleChanged: resetFlightBudget()

    // Innovatech Control marker - proves custom layer is active
    Rectangle {
        id: innovatechMarker
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: ScreenTools.defaultFontPixelHeight * 0.5
        anchors.rightMargin: ScreenTools.defaultFontPixelWidth * 0.5
        width: innovatechLabel.contentWidth + ScreenTools.defaultFontPixelWidth * 2
        height: innovatechLabel.contentHeight + ScreenTools.defaultFontPixelHeight * 0.5
        radius: ScreenTools.defaultFontPixelWidth * 0.5
        color: "#4012b886"
        border.color: "#12b886"
        border.width: 1
        z: 1000

        QGCLabel {
            id: innovatechLabel
            anchors.centerIn: parent
            text: "Innovatech Control"
            color: "#12b886"
            font.pointSize: ScreenTools.smallFontPointSize
            font.bold: true
        }
    }

    // Point cloud view state
    property bool _pointCloudViewVisible: false

    // CLPC Point Cloud debug label - shows reception status
    Rectangle {
        id: clpcDebugPanel
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.topMargin: parentToolInsets.topEdgeLeftInset + ScreenTools.defaultFontPixelHeight * 0.5
        anchors.leftMargin: ScreenTools.defaultFontPixelWidth * 0.5
        width: clpcRow.width + ScreenTools.defaultFontPixelWidth * 2
        height: clpcRow.height + ScreenTools.defaultFontPixelHeight * 0.5
        radius: ScreenTools.defaultFontPixelWidth * 0.5
        color: _clpcReceiver && _clpcReceiver.linkState === "OK" ? "#40228be6" : (_clpcReceiver && _clpcReceiver.linkState === "LAG" ? "#40ffd43b" : (_clpcReceiver && _clpcReceiver.linkState === "STALE" ? "#40f08c00" : "#40e03131"))
        border.color: _clpcReceiver && _clpcReceiver.linkState === "OK" ? "#228be6" : (_clpcReceiver && _clpcReceiver.linkState === "LAG" ? "#ffd43b" : (_clpcReceiver && _clpcReceiver.linkState === "STALE" ? "#f08c00" : "#e03131"))
        border.width: 1
        z: 1000
        visible: true

        property var _clpcReceiver: QGroundControl.corePlugin.pointCloudReceiver

        Row {
            id: clpcRow
            anchors.centerIn: parent
            spacing: ScreenTools.defaultFontPixelWidth

            QGCLabel {
                id: clpcDebugLabel
                anchors.verticalCenter: parent.verticalCenter
                font.pointSize: ScreenTools.smallFontPointSize
                font.family: "monospace"
                color: clpcDebugPanel._clpcReceiver && clpcDebugPanel._clpcReceiver.linkState === "OK" ? "#228be6" : (clpcDebugPanel._clpcReceiver && clpcDebugPanel._clpcReceiver.linkState === "LAG" ? "#ffd43b" : (clpcDebugPanel._clpcReceiver && clpcDebugPanel._clpcReceiver.linkState === "STALE" ? "#f08c00" : "#e03131"))
                text: {
                    var receiver = clpcDebugPanel._clpcReceiver;
                    if (!receiver) {
                        return "CLPC: NO RECEIVER";
                    }
                    if (!receiver.connected) {
                        return "CLPC: LOST | " + receiver.host + ":" + receiver.port;
                    }
                    return "CLPC: frame " + receiver.frameId + " | " + receiver.pointCount + " pts" + " | pose (" + receiver.dronePose.x.toFixed(2) + ", " + receiver.dronePose.y.toFixed(2) + ", " + receiver.dronePose.z.toFixed(2) + ")" + " | age " + receiver.lastFrameAgeMs + " ms | " + receiver.linkState + " | " + receiver.source;
                }
            }

            // Cloud toggle button
            Rectangle {
                id: cloudToggleButton
                anchors.verticalCenter: parent.verticalCenter
                width: cloudButtonLabel.contentWidth + ScreenTools.defaultFontPixelWidth
                height: cloudButtonLabel.contentHeight + ScreenTools.defaultFontPixelHeight * 0.3
                radius: ScreenTools.defaultFontPixelWidth * 0.3
                color: _pointCloudViewVisible ? "#12b886" : (cloudButtonMouseArea.containsMouse ? "#40ffffff" : "transparent")
                border.color: _pointCloudViewVisible ? "#12b886" : "#888888"
                border.width: 1

                QGCLabel {
                    id: cloudButtonLabel
                    anchors.centerIn: parent
                    text: "Cloud"
                    color: _pointCloudViewVisible ? "white" : "#cccccc"
                    font.pointSize: ScreenTools.smallFontPointSize
                    font.bold: true
                }

                MouseArea {
                    id: cloudButtonMouseArea
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                        _pointCloudViewVisible = !_pointCloudViewVisible;
                    }
                }
            }
        }
    }

    Timer {
        id: flightBudgetTimer
        interval: 1000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: updateFlightBudget()
    }

    Rectangle {
        id: flightBudgetPanel
        anchors.top: clpcDebugPanel.bottom
        anchors.left: parent.left
        anchors.topMargin: ScreenTools.defaultFontPixelHeight * 0.5
        anchors.leftMargin: ScreenTools.defaultFontPixelWidth * 0.5
        width: ScreenTools.defaultFontPixelWidth * 34
        height: flightBudgetColumn.height + ScreenTools.defaultFontPixelHeight
        radius: ScreenTools.defaultFontPixelWidth * 0.5
        color: Qt.rgba(0.05, 0.06, 0.07, 0.78)
        border.color: flightBudgetColor(_flightBudgetStatus)
        border.width: 1
        visible: !!_activeVehicle
        z: 990

        Column {
            id: flightBudgetColumn
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: ScreenTools.defaultFontPixelWidth
            anchors.rightMargin: ScreenTools.defaultFontPixelWidth
            spacing: ScreenTools.defaultFontPixelHeight * 0.22

            Row {
                width: parent.width
                height: Math.max(flightBudgetStatusLabel.height, flightBudgetTimeLabel.height)
                spacing: ScreenTools.defaultFontPixelWidth

                QGCLabel {
                    id: flightBudgetStatusLabel
                    width: parent.width - flightBudgetTimeLabel.width - parent.spacing
                    anchors.verticalCenter: parent.verticalCenter
                    text: _flightBudgetStatus
                    color: flightBudgetColor(_flightBudgetStatus)
                    elide: Text.ElideRight
                    font.pixelSize: 20
                    font.bold: true
                }

                QGCLabel {
                    id: flightBudgetTimeLabel
                    anchors.verticalCenter: parent.verticalCenter
                    text: flightBudgetMMSS(_flightBudgetInspectionS)
                    color: "white"
                    font.pixelSize: 24
                    font.bold: true
                    font.family: "monospace"
                }
            }

            Rectangle {
                width: 200
                height: 8
                radius: 2
                color: "#343a40"
                border.color: "#495057"
                border.width: 1
                clip: true

                Rectangle {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: parent.width * flightBudgetBarFraction()
                    radius: 2
                    color: flightBudgetColor(_flightBudgetStatus)
                }
            }

            Row {
                width: parent.width
                spacing: ScreenTools.defaultFontPixelWidth

                QGCLabel {
                    width: (parent.width - parent.spacing) * 0.5
                    text: "BATT " + flightBudgetMMSS(_flightBudgetRemainingS)
                    color: "#dee2e6"
                    font.pixelSize: 11
                    font.family: "monospace"
                    elide: Text.ElideRight
                }

                QGCLabel {
                    width: (parent.width - parent.spacing) * 0.5
                    text: "RETURN " + flightBudgetMMSS(_flightBudgetReturnS)
                    color: "#dee2e6"
                    font.pixelSize: 11
                    font.family: "monospace"
                    horizontalAlignment: Text.AlignRight
                    elide: Text.ElideRight
                }
            }

            QGCLabel {
                width: parent.width
                text: _flightBudgetMethod + (_flightBudgetStatus === "UNKNOWN" && _flightBudgetUnknownReason !== "" ? " / " + _flightBudgetUnknownReason : "")
                color: "#adb5bd"
                font.pixelSize: 11
                elide: Text.ElideRight
            }

            QGCLabel {
                width: parent.width
                text: _flightBudgetRemainingMethod
                color: "#868e96"
                font.pixelSize: 10
                elide: Text.ElideRight
            }

            Row {
                width: parent.width
                spacing: ScreenTools.defaultFontPixelWidth * 0.5

                QGCLabel {
                    width: ScreenTools.defaultFontPixelWidth * 10
                    anchors.verticalCenter: parent.verticalCenter
                    text: "BUFFER " + _flightBudgetSafetyBufferS + "s"
                    color: "#dee2e6"
                    font.pixelSize: 11
                }

                Slider {
                    width: parent.width - ScreenTools.defaultFontPixelWidth * 10 - parent.spacing
                    anchors.verticalCenter: parent.verticalCenter
                    from: 0
                    to: 300
                    stepSize: 30
                    snapMode: Slider.SnapAlways
                    live: true
                    value: _flightBudgetSafetyBufferS
                    onMoved: _flightBudgetSafetyBufferS = Math.round(value / 30) * 30
                }
            }
        }
    }

    // Point Cloud View Panel (right half of screen)
    Rectangle {
        id: pointCloudPanel
        visible: _pointCloudViewVisible
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        width: parent.width * 0.5
        color: "#1a1c1f"
        z: 500

        Loader {
            id: pointCloudViewLoader
            anchors.fill: parent
            active: _pointCloudViewVisible
            source: "qrc:/Custom/qml/Custom/PointCloudView.qml"

            onLoaded: {
                console.log("PointCloudView loaded");
            }
        }
    }
    readonly property real indicatorValueWidth: ScreenTools.defaultFontPixelWidth * 7

    property var _activeVehicle: QGroundControl.multiVehicleManager.activeVehicle
    property real _indicatorDiameter: ScreenTools.defaultFontPixelWidth * 18
    property real _indicatorsHeight: ScreenTools.defaultFontPixelHeight
    property var _sepColor: qgcPal.globalTheme === QGCPalette.Light ? Qt.rgba(0, 0, 0, 0.5) : Qt.rgba(1, 1, 1, 0.5)
    property color _indicatorsColor: qgcPal.text
    property bool _isVehicleGps: _activeVehicle ? _activeVehicle.gps.count.rawValue > 1 && _activeVehicle.gps.hdop.rawValue < 1.4 : false
    property string _altitude: _activeVehicle ? (isNaN(_activeVehicle.altitudeRelative.value) ? "0.0" : _activeVehicle.altitudeRelative.value.toFixed(1)) + ' ' + _activeVehicle.altitudeRelative.units : "0.0"
    property string _distanceStr: isNaN(_distance) ? "0" : _distance.toFixed(0) + ' ' + QGroundControl.unitsConversion.appSettingsHorizontalDistanceUnitsString
    property real _heading: _activeVehicle ? _activeVehicle.heading.rawValue : 0
    property real _distance: _activeVehicle ? _activeVehicle.distanceToHome.rawValue : 0
    property string _messageTitle: ""
    property string _messageText: ""
    property real _toolsMargin: ScreenTools.defaultFontPixelWidth * 0.75

    readonly property real _flightBudgetReturnSpeedMps: 1.0
    readonly property real _flightBudgetLandingBudgetS: 30
    readonly property real _flightBudgetEwmaAlpha: 0.2
    readonly property real _flightBudgetMinWindowS: 60
    readonly property real _flightBudgetBreadcrumbStepM: 0.5
    readonly property int _flightBudgetBreadcrumbCap: 10000
    property var _statusReceiver: QGroundControl.corePlugin.statusReceiver
    property int _flightBudgetSafetyBufferS: Math.max(0, Math.min(300, flightBudgetSettings.safetyBufferS))
    property real _flightBudgetRemainingS: NaN
    property real _flightBudgetReturnS: NaN
    property real _flightBudgetInspectionS: NaN
    property string _flightBudgetStatus: "UNKNOWN"
    property string _flightBudgetMethod: "return estimate: unknown"
    property string _flightBudgetRemainingMethod: "remaining: unknown"
    property string _flightBudgetUnknownReason: "NO VEHICLE"
    property real _flightBudgetLastPct: NaN
    property real _flightBudgetEwmaPctPerS: NaN
    property double _flightBudgetLastPctMs: 0
    property double _flightBudgetFirstPctMs: 0
    property var _flightBudgetLastCoord: null
    property var _flightBudgetSegments: []
    property real _flightBudgetPathLengthM: 0

    on_FlightBudgetSafetyBufferSChanged: flightBudgetSettings.safetyBufferS = _flightBudgetSafetyBufferS

    function isValidFlightBudgetNumber(value) {
        return typeof value === "number" && !isNaN(value) && isFinite(value);
    }

    function readFlightBudgetFactNumber(fact) {
        if (!fact) {
            return NaN;
        }
        var value = Number(fact.rawValue);
        return isValidFlightBudgetNumber(value) ? value : NaN;
    }

    function flightBudgetBatteryGroup() {
        if (!_activeVehicle) {
            return null;
        }
        if (_activeVehicle.battery) {
            return _activeVehicle.battery;
        }
        if (_activeVehicle.batteries && _activeVehicle.batteries.count > 0) {
            return _activeVehicle.batteries.get(0);
        }
        return null;
    }

    function resetFlightBudget() {
        _flightBudgetRemainingS = NaN;
        _flightBudgetReturnS = NaN;
        _flightBudgetInspectionS = NaN;
        _flightBudgetStatus = "UNKNOWN";
        _flightBudgetMethod = "return estimate: unknown";
        _flightBudgetRemainingMethod = "remaining: unknown";
        _flightBudgetUnknownReason = _activeVehicle ? "WAITING FOR DATA" : "NO VEHICLE";
        _flightBudgetLastPct = NaN;
        _flightBudgetEwmaPctPerS = NaN;
        _flightBudgetLastPctMs = 0;
        _flightBudgetFirstPctMs = 0;
        _flightBudgetLastCoord = null;
        _flightBudgetSegments = [];
        _flightBudgetPathLengthM = 0;
    }

    function updateFlightBudgetBattery(nowMs) {
        var battery = flightBudgetBatteryGroup();
        if (!battery) {
            _flightBudgetRemainingMethod = "remaining: no battery";
            return NaN;
        }

        var timeRemaining = readFlightBudgetFactNumber(battery.timeRemaining);
        if (isValidFlightBudgetNumber(timeRemaining) && timeRemaining > 0) {
            _flightBudgetRemainingMethod = "remaining: battery fact";
            return timeRemaining;
        }

        var pct = readFlightBudgetFactNumber(battery.percentRemaining);
        if (!isValidFlightBudgetNumber(pct) || pct < 0) {
            _flightBudgetRemainingMethod = "remaining: no percent";
            return NaN;
        }

        if (!isValidFlightBudgetNumber(_flightBudgetLastPct) || _flightBudgetLastPctMs <= 0) {
            _flightBudgetLastPct = pct;
            _flightBudgetLastPctMs = nowMs;
            _flightBudgetFirstPctMs = nowMs;
            _flightBudgetRemainingMethod = "remaining: learning";
            return NaN;
        }

        var dtS = (nowMs - _flightBudgetLastPctMs) / 1000.0;
        if (dtS >= 0.5) {
            var drainPctPerS = (_flightBudgetLastPct - pct) / dtS;
            if (drainPctPerS > 0) {
                _flightBudgetEwmaPctPerS = isValidFlightBudgetNumber(_flightBudgetEwmaPctPerS) ? (_flightBudgetEwmaAlpha * drainPctPerS + (1.0 - _flightBudgetEwmaAlpha) * _flightBudgetEwmaPctPerS) : drainPctPerS;
            }
            _flightBudgetLastPct = pct;
            _flightBudgetLastPctMs = nowMs;
        }

        var windowS = (nowMs - _flightBudgetFirstPctMs) / 1000.0;
        if (windowS >= _flightBudgetMinWindowS && isValidFlightBudgetNumber(_flightBudgetEwmaPctPerS) && _flightBudgetEwmaPctPerS > 0.0001) {
            _flightBudgetRemainingMethod = "remaining: EWMA";
            return pct / _flightBudgetEwmaPctPerS;
        }

        _flightBudgetRemainingMethod = "remaining: learning";
        return NaN;
    }

    function updateFlightBudgetBreadcrumb() {
        if (!_activeVehicle || !_activeVehicle.coordinate || !_activeVehicle.coordinate.isValid) {
            return;
        }

        var coord = _activeVehicle.coordinate;
        if (!_flightBudgetLastCoord || !_flightBudgetLastCoord.isValid) {
            _flightBudgetLastCoord = coord;
            return;
        }

        var deltaM = coord.distanceTo(_flightBudgetLastCoord);
        if (!isValidFlightBudgetNumber(deltaM) || deltaM < _flightBudgetBreadcrumbStepM) {
            return;
        }

        var segments = _flightBudgetSegments;
        segments.push(deltaM);
        _flightBudgetPathLengthM += deltaM;
        if (segments.length > _flightBudgetBreadcrumbCap) {
            _flightBudgetPathLengthM -= segments.shift();
        }
        _flightBudgetSegments = segments;
        _flightBudgetLastCoord = coord;
    }

    function updateFlightBudgetReturnTime() {
        if (!_statusReceiver || !_statusReceiver.linkAlive) {
            _flightBudgetMethod = "return estimate: unknown";
            _flightBudgetUnknownReason = "CLST NO DATA";
            return NaN;
        }
        if (_statusReceiver.slamStatus === "LOST") {
            _flightBudgetMethod = "return estimate: unknown";
            _flightBudgetUnknownReason = "SLAM LOST";
            return NaN;
        }
        if (!_activeVehicle || !_activeVehicle.coordinate || !_activeVehicle.coordinate.isValid) {
            _flightBudgetMethod = "return estimate: unknown";
            _flightBudgetUnknownReason = "NO POSE";
            return NaN;
        }

        updateFlightBudgetBreadcrumb();

        var straightM = readFlightBudgetFactNumber(_activeVehicle.distanceToHome);
        var returnDistanceM = NaN;
        if (_flightBudgetPathLengthM >= _flightBudgetBreadcrumbStepM) {
            returnDistanceM = isValidFlightBudgetNumber(straightM) ? Math.max(_flightBudgetPathLengthM, straightM) : _flightBudgetPathLengthM;
            _flightBudgetMethod = "return estimate: path";
        } else if (isValidFlightBudgetNumber(straightM) && straightM >= 0) {
            returnDistanceM = straightM;
            _flightBudgetMethod = "return estimate: approximate";
        } else {
            _flightBudgetMethod = "return estimate: unknown";
            _flightBudgetUnknownReason = "NO HOME DISTANCE";
            return NaN;
        }

        return returnDistanceM / _flightBudgetReturnSpeedMps + _flightBudgetLandingBudgetS;
    }

    function updateFlightBudgetStatus() {
        if (!isValidFlightBudgetNumber(_flightBudgetInspectionS)) {
            _flightBudgetStatus = "UNKNOWN";
            return;
        }
        if (_flightBudgetInspectionS > 180) {
            _flightBudgetStatus = "SAFE";
        } else if (_flightBudgetInspectionS >= 60) {
            _flightBudgetStatus = "RETURN SOON";
        } else if (_flightBudgetInspectionS >= 0) {
            _flightBudgetStatus = "RETURN NOW";
        } else {
            _flightBudgetStatus = "LAND NOW";
        }
    }

    function updateFlightBudget() {
        if (!_activeVehicle) {
            resetFlightBudget();
            return;
        }

        var nowMs = Date.now();
        _flightBudgetUnknownReason = "";
        _flightBudgetRemainingS = updateFlightBudgetBattery(nowMs);
        _flightBudgetReturnS = updateFlightBudgetReturnTime();

        if (isValidFlightBudgetNumber(_flightBudgetRemainingS) && isValidFlightBudgetNumber(_flightBudgetReturnS)) {
            _flightBudgetInspectionS = _flightBudgetRemainingS - _flightBudgetReturnS - _flightBudgetSafetyBufferS;
            _flightBudgetUnknownReason = "";
        } else {
            _flightBudgetInspectionS = NaN;
            if (_flightBudgetUnknownReason === "") {
                _flightBudgetUnknownReason = "WAITING FOR DATA";
            }
        }
        updateFlightBudgetStatus();
    }

    function flightBudgetColor(status) {
        if (status === "SAFE") {
            return "#2f9e44";
        }
        if (status === "RETURN SOON") {
            return "#f2c94c";
        }
        if (status === "RETURN NOW") {
            return "#f08c00";
        }
        if (status === "LAND NOW") {
            return "#e03131";
        }
        return "#868e96";
    }

    function flightBudgetMMSS(valueS) {
        if (!isValidFlightBudgetNumber(valueS)) {
            return "--:--";
        }
        var sign = valueS < 0 ? "-" : "";
        var sec = Math.round(Math.abs(valueS));
        var minutes = Math.floor(sec / 60);
        var seconds = sec - minutes * 60;
        return sign + minutes + ":" + (seconds < 10 ? "0" : "") + seconds;
    }

    function flightBudgetBarFraction() {
        if (!isValidFlightBudgetNumber(_flightBudgetInspectionS)) {
            return 0.0;
        }
        return Math.max(0.0, Math.min(1.0, _flightBudgetInspectionS / 300.0));
    }

    function secondsToHHMMSS(timeS) {
        var sec_num = parseInt(timeS, 10);
        var hours = Math.floor(sec_num / 3600);
        var minutes = Math.floor((sec_num - (hours * 3600)) / 60);
        var seconds = sec_num - (hours * 3600) - (minutes * 60);
        if (hours < 10) {
            hours = "0" + hours;
        }
        if (minutes < 10) {
            minutes = "0" + minutes;
        }
        if (seconds < 10) {
            seconds = "0" + seconds;
        }
        return hours + ':' + minutes + ':' + seconds;
    }

    QGCToolInsets {
        id: _totalToolInsets
        leftEdgeTopInset: parentToolInsets.leftEdgeTopInset
        leftEdgeCenterInset: exampleRectangle.leftEdgeCenterInset
        leftEdgeBottomInset: parentToolInsets.leftEdgeBottomInset
        rightEdgeTopInset: parentToolInsets.rightEdgeTopInset
        rightEdgeCenterInset: parentToolInsets.rightEdgeCenterInset
        rightEdgeBottomInset: parent.width - compassBackground.x
        topEdgeLeftInset: parentToolInsets.topEdgeLeftInset
        topEdgeCenterInset: compassArrowIndicator.y + compassArrowIndicator.height
        topEdgeRightInset: parentToolInsets.topEdgeRightInset
        bottomEdgeLeftInset: parentToolInsets.bottomEdgeLeftInset
        bottomEdgeCenterInset: parentToolInsets.bottomEdgeCenterInset
        bottomEdgeRightInset: parent.height - attitudeIndicator.y
    }

    // This is an example of how you can use parent tool insets to position an element on the custom fly view layer
    // - we use parent topEdgeLeftInset to position the widget below the toolstrip
    // - we use parent bottomEdgeLeftInset to dodge the virtual joystick if enabled
    // - we use the parent leftEdgeTopInset to size our element to the same width as the ToolStripAction
    // - we export the width of this element as the leftEdgeCenterInset so that the map will recenter if the vehicle flys behind this element
    Rectangle {
        id: exampleRectangle
        visible: false // to see this example, set this to true. To view insets, enable the insets viewer FlyView.qml
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.topMargin: parentToolInsets.topEdgeLeftInset + _toolsMargin
        anchors.bottomMargin: parentToolInsets.bottomEdgeLeftInset + _toolsMargin
        anchors.leftMargin: _toolsMargin
        width: parentToolInsets.leftEdgeTopInset - _toolsMargin
        color: 'red'

        property real leftEdgeCenterInset: visible ? x + width : 0
    }

    //-------------------------------------------------------------------------
    //-- Heading Indicator
    Rectangle {
        id: compassBar
        height: ScreenTools.defaultFontPixelHeight * 1.5
        width: ScreenTools.defaultFontPixelWidth * 50
        anchors.bottom: parent.bottom
        anchors.bottomMargin: _toolsMargin
        color: "#DEDEDE"
        radius: 2
        clip: true
        anchors.horizontalCenter: parent.horizontalCenter
        Repeater {
            model: 720
            QGCLabel {
                function _normalize(degrees) {
                    var a = degrees % 360;
                    if (a < 0)
                        a += 360;
                    return a;
                }
                property int _startAngle: modelData + 180 + _heading
                property int _angle: _normalize(_startAngle)
                anchors.verticalCenter: parent.verticalCenter
                x: visible ? ((modelData * (compassBar.width / 360)) - (width * 0.5)) : 0
                visible: _angle % 45 == 0
                color: "#75505565"
                font.pointSize: ScreenTools.smallFontPointSize
                text: {
                    switch (_angle) {
                    case 0:
                        return "N";
                    case 45:
                        return "NE";
                    case 90:
                        return "E";
                    case 135:
                        return "SE";
                    case 180:
                        return "S";
                    case 225:
                        return "SW";
                    case 270:
                        return "W";
                    case 315:
                        return "NW";
                    }
                    return "";
                }
            }
        }
    }
    Rectangle {
        id: headingIndicator
        height: ScreenTools.defaultFontPixelHeight
        width: ScreenTools.defaultFontPixelWidth * 4
        color: qgcPal.windowShadeDark
        anchors.top: compassBar.top
        anchors.topMargin: -headingIndicator.height / 2
        anchors.horizontalCenter: parent.horizontalCenter
        QGCLabel {
            text: _heading
            color: qgcPal.text
            font.pointSize: ScreenTools.smallFontPointSize
            anchors.centerIn: parent
        }
    }
    Image {
        id: compassArrowIndicator
        height: _indicatorsHeight
        width: height
        source: "/custom/img/compass_pointer.svg"
        fillMode: Image.PreserveAspectFit
        sourceSize.height: height
        anchors.top: compassBar.bottom
        anchors.topMargin: -height / 2
        anchors.horizontalCenter: parent.horizontalCenter
    }

    Rectangle {
        id: compassBackground
        anchors.bottom: attitudeIndicator.bottom
        anchors.right: attitudeIndicator.left
        anchors.rightMargin: -attitudeIndicator.width / 2
        width: -anchors.rightMargin + compassBezel.width + (_toolsMargin * 2)
        height: attitudeIndicator.height * 0.75
        radius: 2
        color: qgcPal.window

        Rectangle {
            id: compassBezel
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: _toolsMargin
            anchors.left: parent.left
            width: height
            height: parent.height - (northLabelBackground.height / 2) - (headingLabelBackground.height / 2)
            radius: height / 2
            border.color: qgcPal.text
            border.width: 1
            color: Qt.rgba(0, 0, 0, 0)
        }

        Rectangle {
            id: northLabelBackground
            anchors.top: compassBezel.top
            anchors.topMargin: -height / 2
            anchors.horizontalCenter: compassBezel.horizontalCenter
            width: northLabel.contentWidth * 1.5
            height: northLabel.contentHeight * 1.5
            radius: ScreenTools.defaultFontPixelWidth * 0.25
            color: qgcPal.windowShade

            QGCLabel {
                id: northLabel
                anchors.centerIn: parent
                text: "N"
                color: qgcPal.text
                font.pointSize: ScreenTools.smallFontPointSize
            }
        }

        Image {
            id: headingNeedle
            anchors.centerIn: compassBezel
            height: compassBezel.height * 0.75
            width: height
            source: "/custom/img/compass_needle.svg"
            fillMode: Image.PreserveAspectFit
            sourceSize.height: height
            transform: [
                Rotation {
                    origin.x: headingNeedle.width / 2
                    origin.y: headingNeedle.height / 2
                    angle: _heading
                }
            ]
        }

        Rectangle {
            id: headingLabelBackground
            anchors.top: compassBezel.bottom
            anchors.topMargin: -height / 2
            anchors.horizontalCenter: compassBezel.horizontalCenter
            width: headingLabel.contentWidth * 1.5
            height: headingLabel.contentHeight * 1.5
            radius: ScreenTools.defaultFontPixelWidth * 0.25
            color: qgcPal.windowShade

            QGCLabel {
                id: headingLabel
                anchors.centerIn: parent
                text: _heading
                color: qgcPal.text
                font.pointSize: ScreenTools.smallFontPointSize
            }
        }
    }

    Rectangle {
        id: attitudeIndicator
        anchors.bottomMargin: _toolsMargin + parentToolInsets.bottomEdgeRightInset
        anchors.rightMargin: _toolsMargin
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        height: ScreenTools.defaultFontPixelHeight * 6
        width: height
        radius: height * 0.5
        color: qgcPal.windowShade

        CustomAttitudeWidget {
            size: parent.height * 0.95
            vehicle: _activeVehicle
            showHeading: false
            anchors.centerIn: parent
        }
    }
}
