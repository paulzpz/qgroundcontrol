/****************************************************************************
 *
 * (c) 2009-2024 QGROUNDCONTROL PROJECT <http://www.qgroundcontrol.org>
 *
 * QGroundControl is licensed according to the terms in the file
 * COPYING.md in the root of the source code directory.
 *
 * @brief CLPC Point Cloud Receiver implementation
 * @file CustomPointCloudReceiver.cc
 */

#include "CustomPointCloudReceiver.h"
#include "QGCLoggingCategory.h"

#include <QtCore/QPointer>
#include <QtCore/QSettings>
#include <algorithm>
#include <cmath>
#include <cstring>
#include <memory>

QGC_LOGGING_CATEGORY(CustomPointCloudLog, "gcs.custom.pointcloud")

namespace {
constexpr int CLPC_OK_MAX_MS = 700;
constexpr int CLPC_LAG_MAX_MS = 1000;
constexpr int STATUS_UPDATE_MS = 100;
constexpr int RECONNECT_INTERVAL_MS = 3000;
constexpr int TEST_TIMEOUT_MS = 2000;
constexpr int MAX_BUFFER_SIZE = 10 * 1024 * 1024;
constexpr auto DEFAULT_CLPC_HOST = "127.0.0.1";
constexpr quint16 DEFAULT_CLPC_PORT = 7777;
}

CustomPointCloudReceiver::CustomPointCloudReceiver(QObject *parent)
    : QObject(parent)
    , _socket(new QTcpSocket(this))
    , _reconnectTimer(new QTimer(this))
    , _statusTimer(new QTimer(this))
{
    _loadNetworkSettings();

    connect(_socket, &QTcpSocket::connected, this, &CustomPointCloudReceiver::_onConnected);
    connect(_socket, &QTcpSocket::disconnected, this, &CustomPointCloudReceiver::_onDisconnected);
    connect(_socket, &QTcpSocket::readyRead, this, &CustomPointCloudReceiver::_onReadyRead);
    connect(_socket, &QTcpSocket::errorOccurred, this, &CustomPointCloudReceiver::_onError);

    connect(_statusTimer, &QTimer::timeout, this, &CustomPointCloudReceiver::_onStatusTimer);
    _statusTimer->start(STATUS_UPDATE_MS);

    _reconnectTimer->setSingleShot(true);
    connect(_reconnectTimer, &QTimer::timeout, this, &CustomPointCloudReceiver::_onReconnectTimer);

    qCDebug(CustomPointCloudLog) << "CustomPointCloudReceiver created";
}

CustomPointCloudReceiver::~CustomPointCloudReceiver()
{
    disconnectFromServer();
    qCDebug(CustomPointCloudLog) << "CustomPointCloudReceiver destroyed";
}

void CustomPointCloudReceiver::_loadNetworkSettings()
{
    QSettings settings;
    settings.beginGroup(QStringLiteral("Network"));
    _serverHost = settings.value(QStringLiteral("clpcHost"), QString::fromLatin1(DEFAULT_CLPC_HOST)).toString();
    _serverPort = static_cast<quint16>(settings.value(QStringLiteral("clpcPort"), DEFAULT_CLPC_PORT).toUInt());
    settings.endGroup();
}

void CustomPointCloudReceiver::_saveNetworkSettings()
{
    QSettings settings;
    settings.beginGroup(QStringLiteral("Network"));
    settings.setValue(QStringLiteral("clpcHost"), _serverHost);
    settings.setValue(QStringLiteral("clpcPort"), _serverPort);
    settings.endGroup();
}

void CustomPointCloudReceiver::connectToConfiguredServer()
{
    _loadNetworkSettings();
    emit networkSettingsChanged();
    connectToServer(_serverHost, _serverPort);
}

void CustomPointCloudReceiver::applyNetworkSettings(const QString& host, int port)
{
    const QString cleanHost = host.trimmed().isEmpty() ? QString::fromLatin1(DEFAULT_CLPC_HOST) : host.trimmed();
    const quint16 cleanPort = static_cast<quint16>(std::clamp(port, 1, 65535));
    if (_serverHost == cleanHost && _serverPort == cleanPort) {
        return;
    }

    _serverHost = cleanHost;
    _serverPort = cleanPort;
    _saveNetworkSettings();
    emit networkSettingsChanged();
    _autoReconnect = true;
    connectToServer(_serverHost, _serverPort);
}

int CustomPointCloudReceiver::lastFrameAgeMs() const
{
    if (!_lastFrameTime.isValid()) {
        return -1;
    }
    return static_cast<int>(_lastFrameTime.elapsed());
}

QString CustomPointCloudReceiver::linkState() const
{
    if (!_connected) {
        return QStringLiteral("LOST");
    }

    const int age = lastFrameAgeMs();
    if (age >= 0 && age < CLPC_OK_MAX_MS) {
        return QStringLiteral("OK");
    }
    if (age >= 0 && age <= CLPC_LAG_MAX_MS) {
        return QStringLiteral("LAG");
    }
    return QStringLiteral("STALE");
}

QString CustomPointCloudReceiver::statusText() const
{
    if (!_connected) {
        return QStringLiteral("DISCONNECTED");
    }

    return QStringLiteral("frame %1 | %2 pts | pose (%3, %4, %5) | age %6 ms | %7 | %8")
        .arg(_currentFrameId)
        .arg(_currentPointCount)
        .arg(_dronePose.x(), 0, 'f', 2)
        .arg(_dronePose.y(), 0, 'f', 2)
        .arg(_dronePose.z(), 0, 'f', 2)
        .arg(lastFrameAgeMs())
        .arg(linkState())
        .arg(_source);
}

void CustomPointCloudReceiver::connectToServer(const QString& host, quint16 port)
{
    _reconnectTimer->stop();
    if (_socket->state() != QAbstractSocket::UnconnectedState) {
        qCDebug(CustomPointCloudLog) << "Already connected or connecting, reconnecting";
        _socket->disconnectFromHost();
        _socket->abort();
    }

    _serverHost = host;
    _serverPort = port;
    _receiveBuffer.clear();

    qCInfo(CustomPointCloudLog) << "Connecting to CLPC server at" << host << ":" << port;
    _socket->connectToHost(host, port);
}

void CustomPointCloudReceiver::disconnectFromServer()
{
    _reconnectTimer->stop();
    _autoReconnect = false;

    if (_socket->state() != QAbstractSocket::UnconnectedState) {
        _socket->disconnectFromHost();
        if (_socket->state() != QAbstractSocket::UnconnectedState) {
            _socket->abort();
        }
    }

    _resetState();
}

void CustomPointCloudReceiver::setAutoReconnect(bool enable)
{
    _autoReconnect = enable;
    if (!enable) {
        _reconnectTimer->stop();
    }
}

void CustomPointCloudReceiver::_onConnected()
{
    qCInfo(CustomPointCloudLog) << "Connected to CLPC server";
    _connected = true;
    _lastFrameTime.invalidate();
    emit connectionChanged();
}

void CustomPointCloudReceiver::_onDisconnected()
{
    qCInfo(CustomPointCloudLog) << "Disconnected from CLPC server";
    _connected = false;
    const bool wasAlive = _linkAlive;
    _linkAlive = false;
    emit connectionChanged();
    if (wasAlive) {
        emit linkAliveChanged();
    }

    if (_autoReconnect && !_reconnectTimer->isActive()) {
        _reconnectTimer->start(RECONNECT_INTERVAL_MS);
    }
}

void CustomPointCloudReceiver::_onError(QAbstractSocket::SocketError error)
{
    const QString errorStr = _socket->errorString();
    qCWarning(CustomPointCloudLog) << "Socket error:" << error << errorStr;
    emit errorOccurred(errorStr);

    if (_autoReconnect && !_reconnectTimer->isActive()) {
        _reconnectTimer->start(RECONNECT_INTERVAL_MS);
    }
}

void CustomPointCloudReceiver::_onReconnectTimer()
{
    if (_autoReconnect && _socket->state() == QAbstractSocket::UnconnectedState) {
        connectToServer(_serverHost, _serverPort);
    }
}

void CustomPointCloudReceiver::_onReadyRead()
{
    const QByteArray data = _socket->readAll();
    _totalBytesReceived += data.size();
    _receiveBuffer.append(data);

    if (_receiveBuffer.size() > MAX_BUFFER_SIZE) {
        qCWarning(CustomPointCloudLog) << "Receive buffer overflow, clearing";
        _receiveBuffer.clear();
        return;
    }

    bool gotFrame = false;
    while (_parseFrame()) {
        gotFrame = true;
    }

    if (gotFrame) {
        emit frameReceived();
    }
}

bool CustomPointCloudReceiver::_parseFrame()
{
    if (static_cast<size_t>(_receiveBuffer.size()) < CLPC_HEADER_SIZE) {
        return false;
    }

    const int magicPos = _receiveBuffer.indexOf("CLPC");
    if (magicPos < 0) {
        if (_receiveBuffer.size() > 3) {
            _receiveBuffer = _receiveBuffer.right(3);
        }
        return false;
    }

    if (magicPos > 0) {
        qCDebug(CustomPointCloudLog) << "Discarding" << magicPos << "bytes before magic";
        _receiveBuffer = _receiveBuffer.mid(magicPos);
    }

    if (static_cast<size_t>(_receiveBuffer.size()) < CLPC_HEADER_SIZE) {
        return false;
    }

    CLPCHeader header;
    std::memcpy(&header, _receiveBuffer.constData(), CLPC_HEADER_SIZE);

    if (!_validateHeader(header)) {
        _receiveBuffer = _receiveBuffer.mid(4);
        return _receiveBuffer.size() >= 4;
    }

    const bool hasIntensity = (header.flags & CLPC_FLAG_HAS_INTENSITY) != 0;
    const size_t pointSize = hasIntensity ? CLPC_POINT_SIZE_WITH_INTENSITY : CLPC_POINT_SIZE_NO_INTENSITY;
    const size_t totalFrameSize = CLPC_HEADER_SIZE + header.pointCount * pointSize;

    if (static_cast<size_t>(_receiveBuffer.size()) < totalFrameSize) {
        return false;
    }

    _points.resize(header.pointCount);
    const char* pointData = _receiveBuffer.constData() + CLPC_HEADER_SIZE;

    for (uint32_t i = 0; i < header.pointCount; i++) {
        CLPCPoint& pt = _points[i];
        std::memcpy(&pt.x, pointData, sizeof(float));
        std::memcpy(&pt.y, pointData + 4, sizeof(float));
        std::memcpy(&pt.z, pointData + 8, sizeof(float));

        if (hasIntensity) {
            pt.intensity = static_cast<uint8_t>(pointData[12]);
            pointData += CLPC_POINT_SIZE_WITH_INTENSITY;
        } else {
            pt.intensity = 255;
            pointData += CLPC_POINT_SIZE_NO_INTENSITY;
        }
    }

    _currentFrameId = header.frameId;
    _currentPointCount = header.pointCount;
    _dronePose = QVector3D(header.poseX, header.poseY, header.poseZ);
    _droneOrientation = QQuaternion(header.poseQw, header.poseQx, header.poseQy, header.poseQz);
    _voxelSize = header.voxelSize;
    _source = (header.flags & CLPC_FLAG_SOURCE_REPLAY) ? QStringLiteral("REPLAY")
            : (header.flags & CLPC_FLAG_SOURCE_SIM) ? QStringLiteral("SIM")
            : QStringLiteral("LIVE");
    _lastFrameTime.restart();
    _totalFramesReceived++;

    _receiveBuffer = _receiveBuffer.mid(static_cast<int>(totalFrameSize));

    qCDebug(CustomPointCloudLog) << "Frame" << _currentFrameId << ":" << _currentPointCount << "points" << _source;
    return true;
}

bool CustomPointCloudReceiver::_validateHeader(const CLPCHeader& header)
{
    if (std::memcmp(header.magic, "CLPC", 4) != 0) {
        return false;
    }

    if (header.version == 0 || header.version > 10) {
        qCWarning(CustomPointCloudLog) << "Invalid CLPC version:" << header.version;
        return false;
    }

    if (header.pointCount > 100000) {
        qCWarning(CustomPointCloudLog) << "Unreasonable point count:" << header.pointCount;
        return false;
    }

    return true;
}

void CustomPointCloudReceiver::_onStatusTimer()
{
    const bool wasLinkAlive = _linkAlive;
    const int age = lastFrameAgeMs();
    _linkAlive = _connected && age >= 0 && age <= CLPC_LAG_MAX_MS;

    if (wasLinkAlive != _linkAlive) {
        emit linkAliveChanged();
    }

    emit statusUpdated();
}

void CustomPointCloudReceiver::_resetState()
{
    _receiveBuffer.clear();
    _points.clear();
    _currentFrameId = 0;
    _currentPointCount = 0;
    _dronePose = QVector3D(0, 0, 0);
    _droneOrientation = QQuaternion(1, 0, 0, 0);
    _voxelSize = 0.03f;
    _source = QStringLiteral("LIVE");
    _linkAlive = false;
    _connected = false;
    emit connectionChanged();
    emit linkAliveChanged();
}

void CustomPointCloudReceiver::testConnection(const QString& host, int port)
{
    _lastTestResult = QStringLiteral("TESTING");
    emit lastTestResultChanged();

    auto* probe = new QTcpSocket(this);
    QPointer<QTcpSocket> probePtr(probe);
    auto elapsed = std::make_shared<QElapsedTimer>();
    auto done = std::make_shared<bool>(false);
    elapsed->start();

    const auto finish = [this, probePtr, elapsed, done](const QString& result) {
        if (*done) {
            return;
        }
        *done = true;
        _lastTestResult = result;
        emit lastTestResultChanged();
        if (probePtr) {
            probePtr->abort();
            probePtr->deleteLater();
        }
    };

    connect(probe, &QTcpSocket::connected, this, [finish, elapsed]() {
        finish(QStringLiteral("OK (%1 ms)").arg(elapsed->elapsed()));
    });
    connect(probe, &QTcpSocket::errorOccurred, this, [finish, probePtr](QAbstractSocket::SocketError) {
        finish(QStringLiteral("FAIL: %1").arg(probePtr ? probePtr->errorString() : QStringLiteral("socket closed")));
    });
    QTimer::singleShot(TEST_TIMEOUT_MS, this, [finish]() {
        finish(QStringLiteral("FAIL: timeout"));
    });

    probe->connectToHost(host.trimmed(), static_cast<quint16>(std::clamp(port, 1, 65535)));
}
