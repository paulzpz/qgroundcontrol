/****************************************************************************
 *
 * Innovatech inspection root.project selector dialog.
 *
 ****************************************************************************/

import QtQuick
import QtQuick.Controls

import QGroundControl.Controls
import QGroundControl.ScreenTools

Dialog {
    id: root

    property var project

    modal: true
    focus: true
    width: Math.min(480, parent ? parent.width - ScreenTools.defaultFontPixelWidth * 4 : 480)
    height: Math.min(contentColumn.implicitHeight + header.height + footer.height + ScreenTools.defaultFontPixelHeight * 4, parent ? parent.height - ScreenTools.defaultFontPixelHeight * 4 : contentColumn.implicitHeight + 120)
    x: parent ? (parent.width - width) * 0.5 : 0
    y: parent ? (parent.height - height) * 0.5 : 0
    title: "Inspection Project"
    closePolicy: Popup.CloseOnEscape

    function refreshFieldsFromSelection() {
        if (!root.project || !root.project.inspectionSelected) {
            return;
        }
        clientField.text = root.project.clientName;
        siteField.text = root.project.siteName;
        assetField.text = root.project.assetName;
        objectiveField.text = root.project.objective;
        notesField.text = root.project.notes;
    }

    onOpened: {
        if (root.project) {
            root.project.reload();
            baseDirField.text = root.project.baseDir;
            refreshFieldsFromSelection();
        }
    }

    Column {
        id: contentColumn
        width: root.availableWidth
        spacing: ScreenTools.defaultFontPixelHeight * 0.5

        QGCLabel {
            text: "Current"
            font.bold: true
            color: "white"
        }

        Rectangle {
            width: parent.width
            height: currentLabel.contentHeight + ScreenTools.defaultFontPixelHeight * 0.7
            radius: 3
            color: root.project && root.project.inspectionSelected ? "#1f6f5b" : "#664d03"
            border.color: root.project && root.project.inspectionSelected ? "#12b886" : "#f08c00"
            border.width: 1

            QGCLabel {
                id: currentLabel
                anchors.centerIn: parent
                width: parent.width - ScreenTools.defaultFontPixelWidth * 2
                text: root.project ? root.project.chipText : "NO INSPECTION"
                color: "white"
                font.pixelSize: 13
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignHCenter
            }
        }

        QGCLabel {
            text: "Base directory"
            color: "#ced4da"
            font.pixelSize: 11
        }
        Row {
            width: parent.width
            spacing: ScreenTools.defaultFontPixelWidth * 0.5

            TextField {
                id: baseDirField
                width: parent.width - applyBaseDirButton.width - parent.spacing
                height: ScreenTools.defaultFontPixelHeight * 1.8
                text: root.project ? root.project.baseDir : ""
                font.pixelSize: 12
                selectByMouse: true
            }

            Button {
                id: applyBaseDirButton
                width: ScreenTools.defaultFontPixelWidth * 8
                height: baseDirField.height
                text: "Apply"
                onClicked: if (root.project)
                    root.project.applyBaseDir(baseDirField.text)
            }
        }

        QGCLabel {
            text: "Existing inspection"
            color: "#ced4da"
            font.pixelSize: 11
        }
        Row {
            width: parent.width
            spacing: ScreenTools.defaultFontPixelWidth * 0.5

            ComboBox {
                id: existingCombo
                width: parent.width - selectInspectionButton.width - parent.spacing
                model: root.project ? root.project.inspections : []
                textRole: "label"
                valueRole: "inspection_id"
                height: ScreenTools.defaultFontPixelHeight * 1.8
            }

            Button {
                id: selectInspectionButton
                width: ScreenTools.defaultFontPixelWidth * 8
                height: existingCombo.height
                text: "Select"
                enabled: root.project && existingCombo.count > 0
                onClicked: {
                    if (root.project && root.project.selectInspection(existingCombo.currentValue)) {
                        root.refreshFieldsFromSelection();
                    }
                }
            }
        }

        QGCLabel {
            text: "Create inspection"
            font.bold: true
            color: "white"
        }

        Grid {
            width: parent.width
            columns: 2
            columnSpacing: ScreenTools.defaultFontPixelWidth
            rowSpacing: ScreenTools.defaultFontPixelHeight * 0.35

            QGCLabel {
                text: "Client"
                color: "#ced4da"
                width: ScreenTools.defaultFontPixelWidth * 10
            }
            TextField {
                id: clientField
                width: contentColumn.width - ScreenTools.defaultFontPixelWidth * 11
                height: ScreenTools.defaultFontPixelHeight * 1.7
                font.pixelSize: 12
                selectByMouse: true
            }
            QGCLabel {
                text: "Site"
                color: "#ced4da"
                width: ScreenTools.defaultFontPixelWidth * 10
            }
            TextField {
                id: siteField
                width: contentColumn.width - ScreenTools.defaultFontPixelWidth * 11
                height: ScreenTools.defaultFontPixelHeight * 1.7
                font.pixelSize: 12
                selectByMouse: true
            }
            QGCLabel {
                text: "Asset"
                color: "#ced4da"
                width: ScreenTools.defaultFontPixelWidth * 10
            }
            TextField {
                id: assetField
                width: contentColumn.width - ScreenTools.defaultFontPixelWidth * 11
                height: ScreenTools.defaultFontPixelHeight * 1.7
                font.pixelSize: 12
                selectByMouse: true
            }
            QGCLabel {
                text: "Objective"
                color: "#ced4da"
                width: ScreenTools.defaultFontPixelWidth * 10
            }
            TextField {
                id: objectiveField
                width: contentColumn.width - ScreenTools.defaultFontPixelWidth * 11
                height: ScreenTools.defaultFontPixelHeight * 1.7
                font.pixelSize: 12
                selectByMouse: true
            }
            QGCLabel {
                text: "Notes"
                color: "#ced4da"
                width: ScreenTools.defaultFontPixelWidth * 10
            }
            TextField {
                id: notesField
                width: contentColumn.width - ScreenTools.defaultFontPixelWidth * 11
                height: ScreenTools.defaultFontPixelHeight * 1.7
                font.pixelSize: 12
                selectByMouse: true
            }
        }

        Row {
            width: parent.width
            spacing: ScreenTools.defaultFontPixelWidth * 0.5

            QGCLabel {
                width: parent.width - createInspectionButton.width - parent.spacing
                text: assetField.text.length ? "slug: " + (root.project ? root.project.slugForName(assetField.text) : "") : "slug: -"
                color: "#868e96"
                font.pixelSize: 11
                elide: Text.ElideRight
                anchors.verticalCenter: parent.verticalCenter
            }

            Button {
                id: createInspectionButton
                width: ScreenTools.defaultFontPixelWidth * 13
                text: "Create / Select"
                enabled: root.project && clientField.text.trim().length > 0 && siteField.text.trim().length > 0 && assetField.text.trim().length > 0
                onClicked: root.project.createInspection(clientField.text, siteField.text, assetField.text, objectiveField.text, notesField.text)
            }
        }

        QGCLabel {
            text: "Flight"
            font.bold: true
            color: "white"
        }

        Grid {
            width: parent.width
            columns: 2
            columnSpacing: ScreenTools.defaultFontPixelWidth
            rowSpacing: ScreenTools.defaultFontPixelHeight * 0.35

            QGCLabel {
                text: "Operator"
                color: "#ced4da"
                width: ScreenTools.defaultFontPixelWidth * 10
            }
            TextField {
                id: operatorField
                width: contentColumn.width - ScreenTools.defaultFontPixelWidth * 11
                height: ScreenTools.defaultFontPixelHeight * 1.7
                font.pixelSize: 12
                selectByMouse: true
            }
            QGCLabel {
                text: "Pilot"
                color: "#ced4da"
                width: ScreenTools.defaultFontPixelWidth * 10
            }
            TextField {
                id: pilotField
                width: contentColumn.width - ScreenTools.defaultFontPixelWidth * 11
                height: ScreenTools.defaultFontPixelHeight * 1.7
                font.pixelSize: 12
                selectByMouse: true
            }
            QGCLabel {
                text: "Vehicle"
                color: "#ced4da"
                width: ScreenTools.defaultFontPixelWidth * 10
            }
            TextField {
                id: vehicleField
                width: contentColumn.width - ScreenTools.defaultFontPixelWidth * 11
                height: ScreenTools.defaultFontPixelHeight * 1.7
                font.pixelSize: 12
                placeholderText: "vehicle_id"
                selectByMouse: true
            }
            QGCLabel {
                text: "Companion"
                color: "#ced4da"
                width: ScreenTools.defaultFontPixelWidth * 10
            }
            TextField {
                id: companionField
                width: contentColumn.width - ScreenTools.defaultFontPixelWidth * 11
                height: ScreenTools.defaultFontPixelHeight * 1.7
                font.pixelSize: 12
                placeholderText: "companion_id"
                selectByMouse: true
            }
            QGCLabel {
                text: "PX4 profile"
                color: "#ced4da"
                width: ScreenTools.defaultFontPixelWidth * 10
            }
            TextField {
                id: px4ProfileField
                width: contentColumn.width - ScreenTools.defaultFontPixelWidth * 11
                height: ScreenTools.defaultFontPixelHeight * 1.7
                font.pixelSize: 12
                selectByMouse: true
            }
        }

        Row {
            width: parent.width
            spacing: ScreenTools.defaultFontPixelWidth * 0.5

            Button {
                width: (parent.width - parent.spacing) * 0.5
                text: "New flight"
                enabled: root.project && root.project.inspectionSelected
                onClicked: root.project.createFlight(operatorField.text, pilotField.text, vehicleField.text, companionField.text, px4ProfileField.text)
            }

            Button {
                width: (parent.width - parent.spacing) * 0.5
                text: "Close flight"
                enabled: root.project && root.project.flightOpen
                onClicked: root.project.closeFlight()
            }
        }

        QGCLabel {
            width: parent.width
            text: root.project && root.project.lastError.length ? root.project.lastError : ""
            color: "#ff6b6b"
            font.pixelSize: 11
            wrapMode: Text.WordWrap
        }
    }

    footer: DialogButtonBox {
        Button {
            text: "Close"
            DialogButtonBox.buttonRole: DialogButtonBox.RejectRole
        }
    }
}
