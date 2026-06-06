/****************************************************************************
 *
 * Innovatech preflight / scan checklist dialog.
 *
 ****************************************************************************/

import QtQuick
import QtQuick.Controls

import QGroundControl.Controls
import QGroundControl.ScreenTools

Dialog {
    id: root

    property var host
    property var pointCloudReceiver
    property var statusReceiver
    property var inspectionProject
    property var activeVehicle
    property var videoManager
    property int refreshTick: 0

    modal: false
    focus: true
    width: Math.min(420, parent ? parent.width - ScreenTools.defaultFontPixelWidth * 4 : 420)
    height: Math.min(contentColumn.implicitHeight + ScreenTools.defaultFontPixelHeight * 7, parent ? parent.height - ScreenTools.defaultFontPixelHeight * 4 : contentColumn.implicitHeight + 120)
    x: parent ? (parent.width - width) * 0.5 : 0
    y: parent ? (parent.height - height) * 0.5 : 0
    title: "Preflight Checklist"
    closePolicy: Popup.CloseOnEscape

    Timer {
        interval: 1000
        repeat: true
        running: root.visible
        onTriggered: root.refreshTick++
    }

    function clstFresh() {
        return root.statusReceiver && root.statusReceiver.linkAlive;
    }

    function clpcState() {
        return root.pointCloudReceiver ? root.pointCloudReceiver.linkState : "LOST";
    }

    function simActive() {
        return (root.pointCloudReceiver && root.pointCloudReceiver.linkAlive && root.pointCloudReceiver.source === "SIM") || (root.statusReceiver && root.statusReceiver.linkAlive && root.statusReceiver.source === "SIM");
    }

    function flightReadyText() {
        return root.host ? root.host.flightReadyText() : "FLIGHT NOT READY: PX4 not connected";
    }

    function scanReadyText() {
        return root.host ? root.host.scanReadyText() : "SCAN NOT READY: CLST no data";
    }

    function reasonFromReadyText(text) {
        var idx = text.indexOf(": ");
        return idx >= 0 ? text.substring(idx + 2) : text;
    }

    function verdictText() {
        var tick = root.refreshTick;
        var flightText = root.flightReadyText();
        var suffix = root.simActive() ? " (SIM)" : "";
        if (flightText !== "FLIGHT READY") {
            return "NOT READY: " + root.reasonFromReadyText(flightText) + suffix;
        }

        var scanText = root.scanReadyText();
        if (scanText !== "SCAN READY") {
            return "READY TO FLY" + suffix;
        }

        if (!root.inspectionProject || !root.inspectionProject.inspectionSelected) {
            return "READY TO FLY" + suffix;
        }

        return "READY TO SCAN" + suffix;
    }

    function verdictColor() {
        var text = root.verdictText();
        if (text.indexOf("(SIM)") >= 0) {
            return "#f08c00";
        }
        return text.indexOf("READY TO") === 0 ? "#12b886" : "#e03131";
    }

    function batteryGroup() {
        var vehicle = root.activeVehicle;
        if (!vehicle) {
            return null;
        }
        if (vehicle.battery) {
            return vehicle.battery;
        }
        if (vehicle.batteries && vehicle.batteries.count > 0) {
            return vehicle.batteries.get(0);
        }
        return null;
    }

    function batteryPercent() {
        var battery = root.batteryGroup();
        if (!battery || !battery.percentRemaining) {
            return NaN;
        }
        var pct = Number(battery.percentRemaining.rawValue);
        return isNaN(pct) ? NaN : pct;
    }

    function storageFreeGb() {
        if (!root.inspectionProject) {
            return -1.0;
        }
        var tick = root.refreshTick;
        return root.inspectionProject.baseDirFreeGb();
    }

    function checkRows() {
        var tick = root.refreshTick;
        var vehicle = root.activeVehicle;
        var px4Ok = !!vehicle;
        var linkOk = px4Ok && vehicle.vehicleLinkManager && !vehicle.vehicleLinkManager.communicationLost;
        var videoOk = root.videoManager && (root.videoManager.streaming || root.videoManager.decoding || root.videoManager.hasVideo);
        var clpc = root.clpcState();
        var clstOk = root.clstFresh();
        var lidarOk = clstOk && root.statusReceiver.lidarAlive;
        var slamOk = clstOk && root.statusReceiver.slamStatus === "OK";
        var pct = root.batteryPercent();
        var pctKnown = !isNaN(pct);
        var storageGb = root.storageFreeGb();
        var storageKnown = storageGb >= 0.0;
        var inspectionOk = root.inspectionProject && root.inspectionProject.inspectionSelected;
        var sim = root.simActive();

        return [
            {
                "state": px4Ok ? "pass" : "fail",
                "label": "PX4 connected",
                "reason": px4Ok ? "active vehicle detected" : "PX4 not connected"
            },
            {
                "state": !px4Ok ? "fail" : (linkOk ? "pass" : "fail"),
                "label": "RC/H16 link OK",
                "reason": !px4Ok ? "no vehicle link" : (linkOk ? "communication OK" : "communication lost")
            },
            {
                "state": videoOk ? "pass" : "fail",
                "label": "Video stream receiving",
                "reason": videoOk ? "video manager active" : "no video frames"
            },
            {
                "state": clpc === "OK" ? "pass" : "fail",
                "label": "CLPC OK",
                "reason": "CLPC " + clpc
            },
            {
                "state": clstOk ? "pass" : "none",
                "label": "CLST OK",
                "reason": clstOk ? "CLST live" : "no CLST data"
            },
            {
                "state": !clstOk ? "none" : (lidarOk ? "pass" : "fail"),
                "label": "LIDAR OK",
                "reason": !clstOk ? "no CLST data" : (lidarOk ? "lidar alive" : "lidar not OK")
            },
            {
                "state": !clstOk ? "none" : (slamOk ? "pass" : "fail"),
                "label": "SLAM OK",
                "reason": !clstOk ? "no CLST data" : (slamOk ? "SLAM OK" : "SLAM " + root.statusReceiver.slamStatus)
            },
            {
                "state": !pctKnown ? "none" : (pct > 20.0 ? "pass" : "fail"),
                "label": "Battery > 20%",
                "reason": !pctKnown ? "battery percent unavailable" : pct.toFixed(0) + "% remaining"
            },
            {
                "state": !storageKnown ? "none" : (storageGb >= 5.0 ? "pass" : "fail"),
                "label": "Storage free >= 5 GB",
                "reason": !storageKnown ? "free space unavailable" : storageGb.toFixed(1) + " GB free"
            },
            {
                "state": inspectionOk ? "pass" : "fail",
                "label": "Inspection selected",
                "reason": inspectionOk ? root.inspectionProject.inspectionId : "no inspection selected"
            },
            {
                "state": sim ? "warn" : "pass",
                "label": "Source != SIM",
                "reason": sim ? "SIM data active - NOT a production flight" : "production source"
            }
        ];
    }

    function lineColor(state) {
        if (state === "pass") {
            return "#12b886";
        }
        if (state === "fail") {
            return "#e03131";
        }
        if (state === "warn") {
            return "#f08c00";
        }
        return "#777777";
    }

    Column {
        id: contentColumn
        width: root.availableWidth
        spacing: ScreenTools.defaultFontPixelHeight * 0.45

        QGCLabel {
            width: parent.width
            text: root.verdictText()
            color: root.verdictColor()
            font.pixelSize: 20
            font.bold: true
            elide: Text.ElideRight
        }

        Repeater {
            model: root.checkRows()

            Row {
                width: contentColumn.width
                height: 28
                spacing: ScreenTools.defaultFontPixelWidth * 0.6

                Rectangle {
                    width: 16
                    height: 16
                    radius: 8
                    color: root.lineColor(modelData.state)
                    anchors.verticalCenter: parent.verticalCenter
                }

                Column {
                    width: parent.width - 16 - parent.spacing
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 0

                    QGCLabel {
                        width: parent.width
                        text: modelData.label
                        color: "white"
                        font.pixelSize: 12
                        elide: Text.ElideRight
                    }
                    QGCLabel {
                        width: parent.width
                        text: modelData.reason
                        color: modelData.state === "pass" ? "#9be7c7" : (modelData.state === "warn" ? "#ffd8a8" : "#ced4da")
                        font.pixelSize: 10
                        elide: Text.ElideRight
                    }
                }
            }
        }
    }

    footer: DialogButtonBox {
        Button {
            text: "Close"
            DialogButtonBox.buttonRole: DialogButtonBox.RejectRole
        }
    }
}
