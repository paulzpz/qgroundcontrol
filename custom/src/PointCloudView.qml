/****************************************************************************
 *
 * (c) 2009-2024 QGROUNDCONTROL PROJECT <http://www.qgroundcontrol.org>
 *
 * QGroundControl is licensed according to the terms in the file
 * COPYING.md in the root of the source code directory.
 *
 * @file PointCloudView.qml
 * @brief 3D view for point cloud visualization with controls
 */

import QtQuick
import QtQuick.Controls
import QtQuick3D

import QGroundControl
import QGroundControl.ScreenTools

import Custom.PointCloud

Item {
    id: root

    property var pointCloudReceiver: QGroundControl.corePlugin.pointCloudReceiver
    property var statusReceiver: QGroundControl.corePlugin.statusReceiver
    property var inspectionProject: QGroundControl.corePlugin.inspectionProject
    property var activeVehicle: QGroundControl.multiVehicleManager.activeVehicle
    property var videoManager: QGroundControl.videoManager

    readonly property int viewModeFree: 0
    readonly property int viewModeFollow: 1
    readonly property int viewModeTop: 2
    property int viewMode: viewModeFree

    // Render settings. CLPC coordinates and scene helpers are in meters.
    property real pointDiameter: 0.02
    readonly property real pointDiameterMin: 0.005
    readonly property real pointDiameterMax: 0.10
    readonly property real pointDiameterStep: 0.005
    property int colorMode: 1  // 0=Intensity, 1=Height
    property bool showGrid: true
    property bool showAxes: true
    property bool showSlice: false
    property real sliceThickness: 1.0
    readonly property real sliceThicknessMin: 0.1
    readonly property real sliceThicknessMax: 5.0
    readonly property real sliceThicknessStep: 0.1
    property real sliceCenterOffset: 0.0
    readonly property real sliceCenterOffsetMin: -5.0
    readonly property real sliceCenterOffsetMax: 5.0
    readonly property real sliceCenterOffsetStep: 0.1

    property real droneLength: 0.7
    property real droneWidth: 0.45
    property real droneHeight: 0.18
    property real droneNoseLength: 0.22
    property real droneNoseDiameter: 0.16
    property real axesLength: 2.0
    property real axesThickness: 0.1
    property real groundGridSize: 20.0
    property real groundGridCell: 1.0
    property real minPointPixels: 1.0
    property bool darkBackground: true
    property bool errorCatalogExpanded: false

    readonly property real followDistance: 6.0
    readonly property real followPitch: -25.0
    readonly property real followTargetAlpha: 0.3
    property vector3d followTarget: Qt.vector3d(0, 0, 0)
    property bool followTargetInitialized: false

    property real topHeight: 5.0
    property real topOrthoSpan: 5.0
    property vector3d topTarget: Qt.vector3d(0, 0, 0)
    property bool topUserPanned: false
    property bool topUserZoomed: false

    property real pointSizePixels: {
        if (root.viewMode === root.viewModeTop) {
            return Math.max(root.minPointPixels, root.pointDiameter * view3d.height / Math.max(root.topOrthoSpan, 0.1));
        }

        var distance = root.viewMode === root.viewModeFollow ? root.followDistance : root.cameraDistance;
        return Math.max(root.minPointPixels, root.pointDiameter * view3d.height / (2.0 * Math.tan(perspectiveCamera.fieldOfView * Math.PI / 360.0) * Math.max(distance, 0.1)));
    }

    function quick3DScale(meters) {
        return meters / 100.0;
    }
    function clamp(value, low, high) {
        return Math.max(low, Math.min(high, value));
    }

    function clstFresh() {
        return root.statusReceiver && root.statusReceiver.linkAlive;
    }

    function clpcState() {
        return root.pointCloudReceiver ? root.pointCloudReceiver.linkState : "LOST";
    }

    function statusChipColor(state) {
        if (!root.clstFresh()) {
            return "#666666";
        }
        if (state === "OK" || state === true) {
            return "#12b886";
        }
        if (state === "DEGRADED" || state === "LAG" || state === "STALE") {
            return "#f08c00";
        }
        if (state === "LOST" || state === false) {
            return "#e03131";
        }
        return "#666666";
    }

    function clpcChipColor() {
        var state = root.clpcState();
        if (state === "OK")
            return "#12b886";
        if (state === "LAG")
            return "#ffd43b";
        if (state === "STALE")
            return "#f08c00";
        return "#e03131";
    }

    function clstChipColor() {
        return root.clstFresh() ? "#12b886" : "#666666";
    }

    function stageColor() {
        if (!root.clstFresh())
            return "#666666";
        var state = root.statusReceiver.missionState;
        var stage = root.statusReceiver.missionStage;
        if (state === "ERROR")
            return "#e03131";
        if (stage === "HOLD" || stage === "EXTEND" || stage === "MEASURE" || stage === "RETRACT")
            return "#f08c00";
        if (state === "RUN")
            return "#12b886";
        if (state === "ARMED")
            return "#228be6";
        return "#666666";
    }

    function proximityColorForSector(sectorIndex, distance) {
        if (!root.statusReceiver)
            return "#666666";
        return root.statusReceiver.proximityColor(sectorIndex, distance);
    }

    function proximityColor(distance) {
        return root.proximityColorForSector(0, distance);
    }

    function sourceBadgeText() {
        if (root.clstFresh() && root.statusReceiver.source !== "LIVE") {
            return root.statusReceiver.source;
        }
        if (root.pointCloudReceiver && root.pointCloudReceiver.source !== "LIVE") {
            return root.pointCloudReceiver.source;
        }
        return "";
    }

    function sourceBadgeColor() {
        var source = sourceBadgeText();
        if (source === "SIM")
            return "#f08c00";
        if (source === "REPLAY")
            return "#228be6";
        return "transparent";
    }

    function batteryOk() {
        var vehicle = root.activeVehicle;
        if (!vehicle || !vehicle.battery || !vehicle.battery.percentRemaining) {
            return false;
        }
        var pct = vehicle.battery.percentRemaining.rawValue;
        return !isNaN(pct) && pct > 20;
    }

    function flightReadyText() {
        if (!root.activeVehicle)
            return "FLIGHT NOT READY: PX4 not connected";
        if (!root.batteryOk())
            return "FLIGHT NOT READY: battery <= 20%";
        return "FLIGHT READY";
    }

    function scanReadyText() {
        if (!root.statusReceiver || !root.clstFresh())
            return "SCAN NOT READY: CLST no data";
        if (root.statusReceiver.scanBlockedByError)
            return "SCAN NOT READY: " + root.statusReceiver.scanBlockReason;
        if (root.clpcState() !== "OK")
            return "SCAN NOT READY: CLPC " + root.clpcState();
        if (!root.statusReceiver.lidarAlive)
            return "SCAN NOT READY: LIDAR not OK";
        if (root.statusReceiver.slamStatus !== "OK")
            return "SCAN NOT READY: SLAM " + root.statusReceiver.slamStatus;
        return "SCAN READY";
    }

    function readinessColor(text) {
        return text.indexOf(" READY") >= 0 && text.indexOf("NOT READY") < 0 ? "#12b886" : "#e03131";
    }

    function errorSeverityColor(severity) {
        if (severity === "critical")
            return "#e03131";
        if (severity === "error")
            return "#f08c00";
        if (severity === "warning")
            return "#ffd43b";
        return "#868e96";
    }

    function activeErrorRows() {
        if (!root.statusReceiver)
            return [];
        var errors = root.statusReceiver.activeErrors;
        if (!errors || errors.length === 0)
            return [];
        var rows = [];
        var limit = root.errorCatalogExpanded ? errors.length : Math.min(errors.length, 3);
        for (var i = 0; i < limit; i++) {
            rows.push(errors[i]);
        }
        return rows;
    }

    function openPreflightChecklistDialog() {
        preflightChecklistDialogLoader.active = true;
    }

    function applyClpcSettings() {
        if (root.pointCloudReceiver) {
            root.pointCloudReceiver.applyNetworkSettings(clpcHostField.text, parseInt(clpcPortField.text));
        }
    }

    function applyClstSettings() {
        if (root.statusReceiver) {
            root.statusReceiver.applyNetworkSettings(clstHostField.text, parseInt(clstPortField.text));
        }
    }

    function modeLabel() {
        if (viewMode === viewModeFollow) {
            return "Follow";
        }
        if (viewMode === viewModeTop) {
            return "Top";
        }
        return "Free";
    }

    function dronePoseVector() {
        if (!root.pointCloudReceiver) {
            return Qt.vector3d(0, 0, 0);
        }

        return Qt.vector3d(root.pointCloudReceiver.dronePose.x, root.pointCloudReceiver.dronePose.y, root.pointCloudReceiver.dronePose.z);
    }

    function updateFollowTarget(force) {
        var pose = dronePoseVector();
        if (force || !followTargetInitialized) {
            followTarget = pose;
            followTargetInitialized = true;
            return;
        }

        followTarget = Qt.vector3d(followTarget.x * (1.0 - followTargetAlpha) + pose.x * followTargetAlpha, followTarget.y * (1.0 - followTargetAlpha) + pose.y * followTargetAlpha, followTarget.z * (1.0 - followTargetAlpha) + pose.z * followTargetAlpha);
    }

    function updateFreeCameraPosition() {
        var yawRad = cameraYaw * Math.PI / 180;
        var pitchRad = cameraPitch * Math.PI / 180;

        var x = cameraTarget.x + cameraDistance * Math.cos(pitchRad) * Math.sin(yawRad);
        var y = cameraTarget.y + cameraDistance * Math.sin(pitchRad);
        var z = cameraTarget.z + cameraDistance * Math.cos(pitchRad) * Math.cos(yawRad);

        perspectiveCamera.position = Qt.vector3d(x, y, z);
        perspectiveCamera.lookAt(cameraTarget);
    }

    function updateFollowCamera(force) {
        updateFollowTarget(force);

        var yawRad = cameraYaw * Math.PI / 180;
        var pitchRad = followPitch * Math.PI / 180;

        var x = followTarget.x + followDistance * Math.cos(pitchRad) * Math.sin(yawRad);
        var y = followTarget.y + followDistance * Math.sin(pitchRad);
        var z = followTarget.z + followDistance * Math.cos(pitchRad) * Math.cos(yawRad);

        perspectiveCamera.position = Qt.vector3d(x, y, z);
        perspectiveCamera.lookAt(followTarget);
    }

    function updatePerspectiveCamera() {
        if (viewMode === viewModeFollow) {
            updateFollowCamera(false);
        } else {
            updateFreeCameraPosition();
        }
    }

    function updateTopCameraFrame(forceFrame) {
        var bboxX = Math.max(0.0, pointCloudGeometry.maxX - pointCloudGeometry.minX);
        var bboxY = Math.max(0.0, pointCloudGeometry.maxY - pointCloudGeometry.minY);
        var bboxMax = Math.max(bboxX, bboxY);
        var span = clamp(1.2 * bboxMax, 5.0, 100.0);

        topHeight = span;
        if (forceFrame) {
            topUserPanned = false;
            topUserZoomed = false;
        }
        if (forceFrame || !topUserZoomed) {
            topOrthoSpan = span;
        }

        if (forceFrame || !topUserPanned) {
            topTarget = Qt.vector3d((pointCloudGeometry.minX + pointCloudGeometry.maxX) * 0.5, (pointCloudGeometry.minY + pointCloudGeometry.maxY) * 0.5, (pointCloudGeometry.minZ + pointCloudGeometry.maxZ) * 0.5);
        }

        updateTopCamera();
    }

    function updateTopCamera() {
        topCamera.position = Qt.vector3d(topTarget.x, topTarget.y, topTarget.z + topHeight);
        topCamera.horizontalMagnification = Math.max(view3d.height, 1) / Math.max(topOrthoSpan, 0.1);
        topCamera.verticalMagnification = Math.max(view3d.height, 1) / Math.max(topOrthoSpan, 0.1);
    }

    function updateCameraPosition() {
        if (viewMode === viewModeTop) {
            updateTopCamera();
        } else {
            updatePerspectiveCamera();
        }
    }

    function autoCameraFrame() {
        var zRange = pointCloudGeometry.maxZ - pointCloudGeometry.minZ;
        if (zRange < 1)
            zRange = 20;

        var estimatedDiagonal = zRange * 3;
        cameraDistance = Math.max(10, Math.min(200, estimatedDiagonal * 1.5));
        cameraTarget = Qt.vector3d(0, 0, (pointCloudGeometry.minZ + pointCloudGeometry.maxZ) / 2);
        updateFreeCameraPosition();
    }

    onViewModeChanged: {
        if (viewMode === viewModeFollow) {
            updateFollowCamera(true);
        } else if (viewMode === viewModeTop) {
            updateTopCameraFrame(true);
        } else {
            updateFreeCameraPosition();
        }
    }

    onWidthChanged: {
        if (viewMode === viewModeTop) {
            updateTopCamera();
        }
    }

    onHeightChanged: {
        if (viewMode === viewModeTop) {
            updateTopCamera();
        }
    }

    Rectangle {
        anchors.fill: parent
        color: root.darkBackground ? "#0d0d0d" : "#2a2a2a"
    }

    View3D {
        id: view3d
        anchors.fill: parent
        camera: root.viewMode === root.viewModeTop ? topCamera : perspectiveCamera

        environment: SceneEnvironment {
            clearColor: root.darkBackground ? "#0d0d0d" : "#2a2a2a"
            backgroundMode: SceneEnvironment.Color
            antialiasingMode: SceneEnvironment.MSAA
            antialiasingQuality: SceneEnvironment.Medium
        }

        PerspectiveCamera {
            id: perspectiveCamera
            position: Qt.vector3d(20, 10, 20)
            eulerRotation: Qt.vector3d(-20, 45, 0)
            fieldOfView: 60
            clipNear: 0.1
            clipFar: 1000
        }

        OrthographicCamera {
            id: topCamera
            position: Qt.vector3d(0, 0, 5)
            eulerRotation: Qt.vector3d(0, 0, -90)
            clipNear: 0.1
            clipFar: 1000
            horizontalMagnification: Math.max(view3d.height, 1) / Math.max(root.topOrthoSpan, 0.1)
            verticalMagnification: Math.max(view3d.height, 1) / Math.max(root.topOrthoSpan, 0.1)
        }

        DirectionalLight {
            eulerRotation: Qt.vector3d(-30, -30, 0)
            ambientColor: "#666666"
        }

        Model {
            id: pointCloudModel

            geometry: PointCloudGeometry {
                id: pointCloudGeometry
                receiver: root.pointCloudReceiver
                colorMode: root.colorMode
                pointDiameter: root.pointDiameter
                sliceEnabled: root.showSlice
                sliceThickness: root.sliceThickness
                sliceCenterOffset: root.sliceCenterOffset
            }

            materials: [
                CustomMaterial {
                    shadingMode: CustomMaterial.Shaded
                    vertexShader: "qrc:/Custom/shaders/pointcloud.vert"
                    fragmentShader: "qrc:/Custom/shaders/pointcloud.frag"
                    property real pointSize: root.pointSizePixels
                }
            ]
        }

        Model {
            id: groundGrid
            visible: root.showGrid
            geometry: PointCloudGridGeometry {
                size: root.groundGridSize
                cellSize: root.groundGridCell
            }
            materials: [
                CustomMaterial {
                    shadingMode: CustomMaterial.Shaded
                    vertexShader: "qrc:/Custom/shaders/pointcloud.vert"
                    fragmentShader: "qrc:/Custom/shaders/pointcloud.frag"
                    property real pointSize: 1.0
                }
            ]
        }

        Node {
            id: droneMarker
            visible: root.pointCloudReceiver !== null && root.pointCloudReceiver.linkAlive

            position: root.pointCloudReceiver ? Qt.vector3d(root.pointCloudReceiver.dronePose.x, root.pointCloudReceiver.dronePose.y, root.pointCloudReceiver.dronePose.z) : Qt.vector3d(0, 0, 0)

            rotation: root.pointCloudReceiver ? root.pointCloudReceiver.droneOrientation : Qt.quaternion(1, 0, 0, 0)

            Model {
                source: "#Sphere"
                scale: Qt.vector3d(root.quick3DScale(root.droneLength), root.quick3DScale(root.droneHeight), root.quick3DScale(root.droneWidth))
                materials: PrincipledMaterial {
                    baseColor: "#ffcc00"
                    lighting: PrincipledMaterial.NoLighting
                }
            }
            Model {
                source: "#Cone"
                position: Qt.vector3d((root.droneLength - root.droneNoseLength) * 0.5, 0, 0)
                eulerRotation: Qt.vector3d(0, 0, -90)
                scale: Qt.vector3d(root.quick3DScale(root.droneNoseDiameter), root.quick3DScale(root.droneNoseLength), root.quick3DScale(root.droneNoseDiameter))
                materials: PrincipledMaterial {
                    baseColor: "#ff3333"
                    lighting: PrincipledMaterial.NoLighting
                }
            }
        }

        Node {
            id: axesHelper
            visible: root.showAxes

            Model {
                source: "#Cylinder"
                position: Qt.vector3d(root.axesLength * 0.5, 0, 0)
                eulerRotation: Qt.vector3d(0, 0, 90)
                scale: Qt.vector3d(root.quick3DScale(root.axesThickness), root.quick3DScale(root.axesLength), root.quick3DScale(root.axesThickness))
                materials: PrincipledMaterial {
                    baseColor: "#ff0000"
                    lighting: PrincipledMaterial.NoLighting
                }
            }
            Model {
                source: "#Cylinder"
                position: Qt.vector3d(0, root.axesLength * 0.5, 0)
                scale: Qt.vector3d(root.quick3DScale(root.axesThickness), root.quick3DScale(root.axesLength), root.quick3DScale(root.axesThickness))
                materials: PrincipledMaterial {
                    baseColor: "#00ff00"
                    lighting: PrincipledMaterial.NoLighting
                }
            }
            Model {
                source: "#Cylinder"
                position: Qt.vector3d(0, 0, root.axesLength * 0.5)
                eulerRotation: Qt.vector3d(90, 0, 0)
                scale: Qt.vector3d(root.quick3DScale(root.axesThickness), root.quick3DScale(root.axesLength), root.quick3DScale(root.axesThickness))
                materials: PrincipledMaterial {
                    baseColor: "#0088ff"
                    lighting: PrincipledMaterial.NoLighting
                }
            }
        }
    }

    property real rotationSpeed: 0.3
    property real moveSpeed: 0.01
    property real zoomSpeed: 0.05

    property real cameraYaw: 45
    property real cameraPitch: -25
    property real cameraDistance: 50.0
    property vector3d cameraTarget: Qt.vector3d(0, 0, 10)

    Component.onCompleted: {
        updateFreeCameraPosition();
        updateTopCameraFrame(true);
        console.log("PointCloudView loaded");
    }

    Connections {
        target: pointCloudGeometry
        function onBoundsChanged() {
            if (root.viewMode === root.viewModeFree) {
                if (Math.abs(root.cameraTarget.z - (pointCloudGeometry.minZ + pointCloudGeometry.maxZ) / 2) > 5) {
                    root.autoCameraFrame();
                }
            } else if (root.viewMode === root.viewModeTop) {
                root.updateTopCameraFrame(false);
            }
        }
    }

    Connections {
        target: root.pointCloudReceiver
        function onFrameReceived() {
            if (root.viewMode === root.viewModeFollow) {
                root.updateFollowCamera(false);
            }
        }
    }

    Connections {
        target: root.statusReceiver
        function onStatusReceived() {
            proximityCanvas.requestPaint();
        }
        function onStatusUpdated() {
            proximityCanvas.requestPaint();
        }
    }

    Loader {
        id: preflightChecklistDialogLoader
        active: false
        source: "qrc:/Custom/qml/Custom/PreflightChecklistDialog.qml"
        onLoaded: {
            item.host = root;
            item.pointCloudReceiver = root.pointCloudReceiver;
            item.statusReceiver = root.statusReceiver;
            item.inspectionProject = root.inspectionProject;
            item.activeVehicle = root.activeVehicle;
            item.videoManager = root.videoManager;
            item.closed.connect(function () {
                preflightChecklistDialogLoader.active = false;
            });
            item.open();
        }
    }

    DragHandler {
        id: rotateHandler
        target: null
        acceptedButtons: Qt.RightButton
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        property point lastPos

        onActiveChanged: {
            if (active)
                lastPos = centroid.position;
        }
        onCentroidChanged: {
            if (active && root.viewMode !== root.viewModeTop) {
                var delta = Qt.point(centroid.position.x - lastPos.x, centroid.position.y - lastPos.y);
                root.cameraYaw += delta.x * root.rotationSpeed;
                if (root.viewMode === root.viewModeFree) {
                    root.cameraPitch = Math.max(-89, Math.min(89, root.cameraPitch - delta.y * root.rotationSpeed));
                    root.updateFreeCameraPosition();
                } else {
                    root.updateFollowCamera(false);
                }
                lastPos = centroid.position;
            }
        }
    }

    DragHandler {
        id: panHandler
        target: null
        acceptedButtons: Qt.LeftButton
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        property point lastPos

        onActiveChanged: {
            if (active)
                lastPos = centroid.position;
        }
        onCentroidChanged: {
            if (active) {
                var delta = Qt.point(centroid.position.x - lastPos.x, centroid.position.y - lastPos.y);

                if (root.viewMode === root.viewModeFree) {
                    var yawRad = root.cameraYaw * Math.PI / 180;
                    var dx = -delta.x * root.moveSpeed * root.cameraDistance;
                    var dy = delta.y * root.moveSpeed * root.cameraDistance;

                    root.cameraTarget.x += dx * Math.cos(yawRad);
                    root.cameraTarget.z -= dx * Math.sin(yawRad);
                    root.cameraTarget.y += dy;
                    root.updateFreeCameraPosition();
                } else if (root.viewMode === root.viewModeTop) {
                    var metersPerPixel = root.topOrthoSpan / Math.max(view3d.height, 1);
                    root.topUserPanned = true;
                    root.topTarget = Qt.vector3d(root.topTarget.x + delta.y * metersPerPixel, root.topTarget.y + delta.x * metersPerPixel, root.topTarget.z);
                    root.updateTopCamera();
                }

                lastPos = centroid.position;
            }
        }
    }

    WheelHandler {
        target: null
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: function (event) {
            if (root.viewMode === root.viewModeTop) {
                var scale = event.angleDelta.y > 0 ? 0.90 : 1.10;
                root.topUserZoomed = true;
                root.topOrthoSpan = root.clamp(root.topOrthoSpan * scale, 5.0, 100.0);
                root.updateTopCamera();
            } else if (root.viewMode === root.viewModeFree) {
                root.cameraDistance = Math.max(5, Math.min(500, root.cameraDistance - event.angleDelta.y * root.zoomSpeed));
                root.updateFreeCameraPosition();
            }
        }
    }

    Rectangle {
        id: modeBar
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.topMargin: 8
        width: modeRow.width + 8
        height: 32
        radius: 4
        color: "#cc000000"

        Row {
            id: modeRow
            anchors.centerIn: parent
            spacing: 4

            Rectangle {
                width: 58
                height: 24
                radius: 3
                color: root.viewMode === root.viewModeFree ? "#12b886" : "#444444"
                Text {
                    anchors.centerIn: parent
                    text: "Free"
                    color: "white"
                    font.pixelSize: 10
                    font.bold: true
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: root.viewMode = root.viewModeFree
                }
            }
            Rectangle {
                width: 58
                height: 24
                radius: 3
                color: root.viewMode === root.viewModeFollow ? "#12b886" : "#444444"
                Text {
                    anchors.centerIn: parent
                    text: "Follow"
                    color: "white"
                    font.pixelSize: 10
                    font.bold: true
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: root.viewMode = root.viewModeFollow
                }
            }
            Rectangle {
                width: 58
                height: 24
                radius: 3
                color: root.viewMode === root.viewModeTop ? "#12b886" : "#444444"
                Text {
                    anchors.centerIn: parent
                    text: "Top"
                    color: "white"
                    font.pixelSize: 10
                    font.bold: true
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: root.viewMode = root.viewModeTop
                }
            }
        }
    }

    Rectangle {
        id: statusPanel
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.topMargin: 46
        width: Math.min(parent.width - 24, 450)
        height: 318
        radius: 4
        color: "#cc000000"
        border.color: root.clstFresh() ? "#12b886" : "#666666"
        border.width: 1

        Column {
            anchors.fill: parent
            anchors.margins: 8
            spacing: 8

            Row {
                id: healthStrip
                height: 26
                spacing: 4

                Rectangle {
                    width: 66
                    height: 26
                    radius: 3
                    color: root.statusChipColor(root.statusReceiver ? root.statusReceiver.slamStatus : "LOST")
                    Text {
                        anchors.centerIn: parent
                        text: "SLAM"
                        color: "white"
                        font.pixelSize: 10
                        font.bold: true
                    }
                }
                Rectangle {
                    width: 66
                    height: 26
                    radius: 3
                    color: root.statusChipColor(root.statusReceiver ? root.statusReceiver.lidarAlive : false)
                    Text {
                        anchors.centerIn: parent
                        text: "LIDAR"
                        color: "white"
                        font.pixelSize: 10
                        font.bold: true
                    }
                }
                Rectangle {
                    width: 56
                    height: 26
                    radius: 3
                    color: !root.clstFresh() ? "#666666" : ((root.statusReceiver && root.statusReceiver.cpuPct < 80) ? "#12b886" : "#f08c00")
                    Text {
                        anchors.centerIn: parent
                        text: "CPU"
                        color: "white"
                        font.pixelSize: 10
                        font.bold: true
                    }
                }
                Rectangle {
                    width: 66
                    height: 26
                    radius: 3
                    color: root.clpcChipColor()
                    Text {
                        anchors.centerIn: parent
                        text: "CLPC"
                        color: "white"
                        font.pixelSize: 10
                        font.bold: true
                    }
                }
                Rectangle {
                    width: 66
                    height: 26
                    radius: 3
                    color: root.clstChipColor()
                    Text {
                        anchors.centerIn: parent
                        text: "CLST"
                        color: "white"
                        font.pixelSize: 10
                        font.bold: true
                    }
                }
                Rectangle {
                    width: 56
                    height: 26
                    radius: 3
                    color: root.statusChipColor(root.statusReceiver ? root.statusReceiver.recActive : false)
                    Text {
                        anchors.centerIn: parent
                        text: "REC"
                        color: "white"
                        font.pixelSize: 10
                        font.bold: true
                    }
                }
            }

            Row {
                width: parent.width
                height: ScreenTools.defaultFontPixelHeight * 2.1
                spacing: 8

                Text {
                    text: root.flightReadyText()
                    color: root.readinessColor(text)
                    font.pointSize: 20
                    font.bold: true
                    width: parent.width - checklistButton.width - parent.spacing
                    elide: Text.ElideRight
                    anchors.verticalCenter: parent.verticalCenter
                }

                Button {
                    id: checklistButton
                    width: 104
                    height: 28
                    text: "CHECKLIST"
                    font.pixelSize: 10
                    anchors.verticalCenter: parent.verticalCenter
                    onClicked: root.openPreflightChecklistDialog()
                }
            }
            Text {
                text: root.scanReadyText() + " | MEASURE READY: UNAVAILABLE"
                color: root.scanReadyText() === "SCAN READY" ? "#12b886" : "#e03131"
                font.pixelSize: 13
                width: parent.width
                elide: Text.ElideRight
            }

            Row {
                spacing: 12

                Column {
                    width: 250
                    spacing: 6

                    Rectangle {
                        width: 250
                        height: 82
                        radius: 4
                        color: root.stageColor()

                        Column {
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: 4

                            Row {
                                spacing: 8
                                Text {
                                    text: root.clstFresh() ? root.statusReceiver.missionStage : "NO DATA"
                                    color: "white"
                                    font.pointSize: 24
                                    font.bold: true
                                    width: 168
                                    elide: Text.ElideRight
                                }
                                Rectangle {
                                    visible: root.sourceBadgeText() !== ""
                                    width: 56
                                    height: 24
                                    radius: 3
                                    color: root.sourceBadgeColor()
                                    Text {
                                        anchors.centerIn: parent
                                        text: root.sourceBadgeText()
                                        color: "white"
                                        font.pointSize: 12
                                        font.bold: true
                                    }
                                }
                            }
                            Text {
                                text: root.clstFresh() ? root.statusReceiver.message : "NO DATA"
                                color: "white"
                                font.pointSize: 13
                                width: 232
                                elide: Text.ElideRight
                            }
                            Rectangle {
                                width: 240
                                height: 6
                                radius: 3
                                color: "#55000000"
                                Rectangle {
                                    width: root.clstFresh() ? parent.width * root.statusReceiver.progress : 0
                                    height: parent.height
                                    radius: 3
                                    color: "white"
                                }
                            }
                        }
                    }

                    Column {
                        width: 250
                        spacing: 3

                        Repeater {
                            model: root.activeErrorRows()

                            Rectangle {
                                width: 250
                                height: 38
                                radius: 3
                                color: "#202328"
                                border.width: 1
                                border.color: root.errorSeverityColor(modelData.severity)

                                MouseArea {
                                    id: errorMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: root.errorCatalogExpanded = !root.errorCatalogExpanded
                                }

                                Column {
                                    anchors.fill: parent
                                    anchors.margins: 4
                                    spacing: 1

                                    Text {
                                        width: parent.width
                                        text: (modelData.uncatalogued ? "? " : "") + modelData.title + (root.errorCatalogExpanded ? " [" + modelData.code + "]" : "")
                                        color: root.errorSeverityColor(modelData.severity)
                                        font.pixelSize: 13
                                        font.bold: true
                                        elide: Text.ElideRight
                                    }
                                    Text {
                                        width: parent.width
                                        text: modelData.required_action
                                        color: "#f1f3f5"
                                        font.pixelSize: 12
                                        elide: Text.ElideRight
                                    }
                                }

                                ToolTip.visible: errorMouse.containsMouse
                                ToolTip.text: modelData.code
                            }
                        }

                        Text {
                            visible: root.statusReceiver && root.statusReceiver.activeErrors.length === 0
                            text: "Errors: none"
                            color: "#aaaaaa"
                            font.pixelSize: 11
                            width: 250
                            elide: Text.ElideRight
                        }

                        Text {
                            visible: root.statusReceiver && root.statusReceiver.activeErrors.length > 3
                            text: root.errorCatalogExpanded ? "show less" : "+" + (root.statusReceiver.activeErrors.length - 3) + " more"
                            color: "#74c0fc"
                            font.pixelSize: 11
                            width: 250
                            elide: Text.ElideRight

                            MouseArea {
                                anchors.fill: parent
                                onClicked: root.errorCatalogExpanded = !root.errorCatalogExpanded
                            }
                        }
                    }
                }

                Column {
                    width: 150
                    spacing: 4
                    Canvas {
                        id: proximityCanvas
                        width: 150
                        height: 150
                        onPaint: {
                            var ctx = getContext("2d");
                            ctx.clearRect(0, 0, width, height);
                            var cx = width / 2;
                            var cy = height / 2;
                            var r = 72;
                            var sectors = root.statusReceiver ? root.statusReceiver.sectorsM : [];
                            for (var i = 0; i < 8; i++) {
                                var d = i < sectors.length ? sectors[i] : -1;
                                var start = (-90 + i * 45) * Math.PI / 180;
                                var end = (-90 + (i + 1) * 45) * Math.PI / 180;
                                ctx.beginPath();
                                ctx.moveTo(cx, cy);
                                ctx.arc(cx, cy, r, start, end, false);
                                ctx.closePath();
                                ctx.fillStyle = root.proximityColorForSector(i, d);
                                ctx.fill();
                                ctx.strokeStyle = "#222222";
                                ctx.lineWidth = 2;
                                ctx.stroke();
                            }
                            ctx.beginPath();
                            ctx.arc(cx, cy, 22, 0, Math.PI * 2, false);
                            ctx.fillStyle = "#111111";
                            ctx.fill();
                        }
                    }
                    Text {
                        text: root.statusReceiver ? root.statusReceiver.proximityContextLabel : "FREE"
                        color: root.clstFresh() ? "#ced4da" : "#666666"
                        font.pixelSize: 11
                        font.bold: true
                        width: 150
                        horizontalAlignment: Text.AlignHCenter
                    }
                    Text {
                        text: root.clstFresh() && root.statusReceiver.frontM >= 0 ? root.statusReceiver.frontM.toFixed(2) + " m" : "NO DATA"
                        color: root.statusReceiver ? root.proximityColorForSector(0, root.statusReceiver.frontM) : "#666666"
                        font.pointSize: 28
                        font.bold: true
                        width: 150
                        horizontalAlignment: Text.AlignHCenter
                    }
                }
            }
        }
    }

    Rectangle {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.margins: 8
        width: infoColumn.width + 16
        height: infoColumn.height + 12
        radius: 4
        color: "#cc000000"

        Column {
            id: infoColumn
            anchors.centerIn: parent
            spacing: 2

            Text {
                text: "Point Cloud"
                color: "#12b886"
                font.pixelSize: 12
                font.bold: true
            }
            Text {
                text: root.showSlice ? "Points: " + pointCloudGeometry.pointCount + " of " + pointCloudGeometry.totalPointCount : "Points: " + pointCloudGeometry.pointCount
                color: "white"
                font.pixelSize: 10
            }
            Text {
                text: "Mode: " + root.modeLabel()
                color: "#aaaaaa"
                font.pixelSize: 10
            }
            Text {
                text: "Point: " + root.pointDiameter.toFixed(3) + " m"
                color: "#aaaaaa"
                font.pixelSize: 10
            }
            Text {
                text: "Z: " + pointCloudGeometry.minZ.toFixed(1) + " - " + pointCloudGeometry.maxZ.toFixed(1) + " m"
                color: "#aaaaaa"
                font.pixelSize: 10
            }
            Text {
                visible: root.showSlice
                text: "Slice: [" + pointCloudGeometry.sliceMinZ.toFixed(1) + " ... " + pointCloudGeometry.sliceMaxZ.toFixed(1) + "] m, " + pointCloudGeometry.pointCount + " of " + pointCloudGeometry.totalPointCount + " pts"
                color: "#ffd43b"
                font.pixelSize: 10
            }
        }
    }

    Rectangle {
        id: closeButton
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: 8
        width: 24
        height: 24
        radius: 12
        color: closeMouseArea.containsMouse ? "#e03131" : "#80000000"

        Text {
            anchors.centerIn: parent
            text: "X"
            color: "white"
            font.pixelSize: 14
            font.bold: true
        }

        MouseArea {
            id: closeMouseArea
            anchors.fill: parent
            hoverEnabled: true
            onClicked: root.visible = false
        }
    }

    Rectangle {
        id: controlPanel
        anchors.top: parent.top
        anchors.right: closeButton.left
        anchors.margins: 8
        width: controlsVisible ? 220 : 32
        height: controlsVisible ? controlColumn.height + 16 : 32
        radius: 4
        color: "#cc000000"

        property bool controlsVisible: false

        Behavior on width {
            NumberAnimation {
                duration: 150
            }
        }
        Behavior on height {
            NumberAnimation {
                duration: 150
            }
        }

        Text {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.margins: 7
            text: "⚙"
            color: "white"
            font.pixelSize: 16
            font.bold: true

            MouseArea {
                anchors.fill: parent
                anchors.margins: -6
                onClicked: controlPanel.controlsVisible = !controlPanel.controlsVisible
            }
        }

        Column {
            id: controlColumn
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: 8
            anchors.topMargin: 30
            spacing: 8
            visible: controlPanel.controlsVisible
            opacity: controlPanel.controlsVisible ? 1 : 0

            Text {
                text: "Point size " + root.pointDiameter.toFixed(3) + " m"
                color: "white"
                font.pixelSize: 10
            }
            Slider {
                width: parent.width
                from: root.pointDiameterMin
                to: root.pointDiameterMax
                value: root.pointDiameter
                stepSize: root.pointDiameterStep
                snapMode: Slider.SnapAlways
                live: true
                onMoved: root.pointDiameter = value
            }

            Text {
                text: "Color"
                color: "white"
                font.pixelSize: 10
            }
            Row {
                spacing: 6
                Rectangle {
                    width: 92
                    height: 24
                    radius: 3
                    color: root.colorMode === 0 ? "#12b886" : "#444444"
                    Text {
                        anchors.centerIn: parent
                        text: "Intensity"
                        color: "white"
                        font.pixelSize: 10
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.colorMode = 0
                    }
                }
                Rectangle {
                    width: 92
                    height: 24
                    radius: 3
                    color: root.colorMode === 1 ? "#12b886" : "#444444"
                    Text {
                        anchors.centerIn: parent
                        text: "Height"
                        color: "white"
                        font.pixelSize: 10
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.colorMode = 1
                    }
                }
            }

            Row {
                spacing: 6
                Rectangle {
                    width: 60
                    height: 24
                    radius: 3
                    color: root.showGrid ? "#12b886" : "#444444"
                    Text {
                        anchors.centerIn: parent
                        text: "Grid"
                        color: "white"
                        font.pixelSize: 10
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.showGrid = !root.showGrid
                    }
                }
                Rectangle {
                    width: 60
                    height: 24
                    radius: 3
                    color: root.showAxes ? "#12b886" : "#444444"
                    Text {
                        anchors.centerIn: parent
                        text: "Axes"
                        color: "white"
                        font.pixelSize: 10
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.showAxes = !root.showAxes
                    }
                }
                Rectangle {
                    width: 60
                    height: 24
                    radius: 3
                    color: root.showSlice ? "#12b886" : "#444444"
                    Text {
                        anchors.centerIn: parent
                        text: "Slice"
                        color: "white"
                        font.pixelSize: 10
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.showSlice = !root.showSlice
                    }
                }
            }

            Text {
                text: "Slice offset " + root.sliceCenterOffset.toFixed(1) + " m"
                color: "white"
                font.pixelSize: 10
            }
            Slider {
                width: parent.width
                from: root.sliceCenterOffsetMin
                to: root.sliceCenterOffsetMax
                value: root.sliceCenterOffset
                stepSize: root.sliceCenterOffsetStep
                snapMode: Slider.SnapAlways
                live: true
                enabled: root.showSlice
                opacity: root.showSlice ? 1.0 : 0.45
                onMoved: root.sliceCenterOffset = value
            }

            Text {
                text: "Slice thickness " + root.sliceThickness.toFixed(1) + " m"
                color: "white"
                font.pixelSize: 10
            }
            Slider {
                width: parent.width
                from: root.sliceThicknessMin
                to: root.sliceThicknessMax
                value: root.sliceThickness
                stepSize: root.sliceThicknessStep
                snapMode: Slider.SnapAlways
                live: true
                enabled: root.showSlice
                opacity: root.showSlice ? 1.0 : 0.45
                onMoved: root.sliceThickness = value
            }

            Text {
                text: "Network"
                color: "white"
                font.pixelSize: 10
                font.bold: true
            }
            Row {
                spacing: 4
                Text {
                    width: 30
                    text: "CLPC"
                    color: "#aaaaaa"
                    font.pixelSize: 10
                    anchors.verticalCenter: parent.verticalCenter
                }
                TextField {
                    id: clpcHostField
                    width: 74
                    height: 24
                    text: root.pointCloudReceiver ? root.pointCloudReceiver.host : ""
                    font.pixelSize: 10
                    onEditingFinished: root.applyClpcSettings()
                }
                TextField {
                    id: clpcPortField
                    width: 38
                    height: 24
                    text: root.pointCloudReceiver ? root.pointCloudReceiver.port.toString() : ""
                    font.pixelSize: 10
                    validator: IntValidator {
                        bottom: 1
                        top: 65535
                    }
                    onEditingFinished: root.applyClpcSettings()
                }
                Button {
                    width: 42
                    height: 24
                    text: "TEST"
                    font.pixelSize: 8
                    onClicked: if (root.pointCloudReceiver)
                        root.pointCloudReceiver.testConnection(clpcHostField.text, parseInt(clpcPortField.text))
                }
            }
            Text {
                text: root.pointCloudReceiver ? root.pointCloudReceiver.lastTestResult : ""
                color: "#aaaaaa"
                font.pixelSize: 9
                width: parent.width
                elide: Text.ElideRight
            }

            Row {
                spacing: 4
                Text {
                    width: 30
                    text: "CLST"
                    color: "#aaaaaa"
                    font.pixelSize: 10
                    anchors.verticalCenter: parent.verticalCenter
                }
                TextField {
                    id: clstHostField
                    width: 74
                    height: 24
                    text: root.statusReceiver ? root.statusReceiver.host : ""
                    font.pixelSize: 10
                    onEditingFinished: root.applyClstSettings()
                }
                TextField {
                    id: clstPortField
                    width: 38
                    height: 24
                    text: root.statusReceiver ? root.statusReceiver.port.toString() : ""
                    font.pixelSize: 10
                    validator: IntValidator {
                        bottom: 1
                        top: 65535
                    }
                    onEditingFinished: root.applyClstSettings()
                }
                Button {
                    width: 42
                    height: 24
                    text: "TEST"
                    font.pixelSize: 8
                    onClicked: if (root.statusReceiver)
                        root.statusReceiver.testConnection(clstHostField.text, parseInt(clstPortField.text))
                }
            }
            Text {
                text: root.statusReceiver ? root.statusReceiver.lastTestResult : ""
                color: "#aaaaaa"
                font.pixelSize: 9
                width: parent.width
                elide: Text.ElideRight
            }
        }
    }
}
