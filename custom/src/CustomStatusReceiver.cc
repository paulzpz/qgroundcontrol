/****************************************************************************
 *
 * (c) 2009-2024 QGROUNDCONTROL PROJECT <http://www.qgroundcontrol.org>
 *
 * QGroundControl is licensed according to the terms in the file
 * COPYING.md in the root of the source code directory.
 *
 * @brief CLST Status Receiver implementation
 * @file CustomStatusReceiver.cc
 */

#include "CustomStatusReceiver.h"
#include "QGCLoggingCategory.h"

#include <QtCore/QJsonArray>
#include <QtCore/QJsonDocument>
#include <QtCore/QJsonObject>
#include <QtCore/QPointer>
#include <QtCore/QSettings>
#include <algorithm>
#include <memory>

QGC_LOGGING_CATEGORY(CustomStatusLog, "gcs.custom.status")

namespace {
constexpr int STATUS_STALE_MS = 1500;
constexpr int STATUS_UPDATE_MS = 100;
constexpr int RECONNECT_INTERVAL_MS = 3000;
constexpr int TEST_TIMEOUT_MS = 2000;
constexpr int MAX_BUFFER_SIZE = 256 * 1024;
constexpr auto DEFAULT_CLST_HOST = "127.0.0.1";
constexpr quint16 DEFAULT_CLST_PORT = 7778;
}

CustomStatusReceiver::CustomStatusReceiver(QObject *parent)
    : QObject(parent)
    , _socket(new QTcpSocket(this))
    , _reconnectTimer(new QTimer(this))
    , _statusTimer(new QTimer(this))
{
    _loadNetworkSettings();
    _sectorsM = QVariantList({-1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0});

    connect(_socket, &QTcpSocket::connected, this, &CustomStatusReceiver::_onConnected);
    connect(_socket, &QTcpSocket::disconnected, this, &CustomStatusReceiver::_onDisconnected);
    connect(_socket, &QTcpSocket::readyRead, this, &CustomStatusReceiver::_onReadyRead);
    connect(_socket, &QTcpSocket::errorOccurred, this, &CustomStatusReceiver::_onError);

    _reconnectTimer->setSingleShot(true);
    connect(_reconnectTimer, &QTimer::timeout, this, &CustomStatusReceiver::_onReconnectTimer);

    connect(_statusTimer, &QTimer::timeout, this, &CustomStatusReceiver::_onStatusTimer);
    _statusTimer->start(STATUS_UPDATE_MS);

    qCDebug(CustomStatusLog) << "CustomStatusReceiver created";
}

CustomStatusReceiver::~CustomStatusReceiver()
{
    disconnectFromServer();
    qCDebug(CustomStatusLog) << "CustomStatusReceiver destroyed";
}

int CustomStatusReceiver::lastAgeMs() const
{
    if (!_lastStatusTime.isValid()) {
        return -1;
    }
    return static_cast<int>(_lastStatusTime.elapsed());
}

void CustomStatusReceiver::_loadNetworkSettings()
{
    QSettings settings;
    settings.beginGroup(QStringLiteral("Network"));
    _serverHost = settings.value(QStringLiteral("clstHost"), QString::fromLatin1(DEFAULT_CLST_HOST)).toString();
    _serverPort = static_cast<quint16>(settings.value(QStringLiteral("clstPort"), DEFAULT_CLST_PORT).toUInt());
    settings.endGroup();
}

void CustomStatusReceiver::_saveNetworkSettings()
{
    QSettings settings;
    settings.beginGroup(QStringLiteral("Network"));
    settings.setValue(QStringLiteral("clstHost"), _serverHost);
    settings.setValue(QStringLiteral("clstPort"), _serverPort);
    settings.endGroup();
}

void CustomStatusReceiver::connectToConfiguredServer()
{
    _loadNetworkSettings();
    emit networkSettingsChanged();
    connectToServer(_serverHost, _serverPort);
}

void CustomStatusReceiver::applyNetworkSettings(const QString& host, int port)
{
    const QString cleanHost = host.trimmed().isEmpty() ? QString::fromLatin1(DEFAULT_CLST_HOST) : host.trimmed();
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

void CustomStatusReceiver::connectToServer(const QString& host, quint16 port)
{
    _reconnectTimer->stop();
    if (_socket->state() != QAbstractSocket::UnconnectedState) {
        _socket->disconnectFromHost();
        _socket->abort();
    }

    _serverHost = host;
    _serverPort = port;
    _receiveBuffer.clear();

    qCInfo(CustomStatusLog) << "Connecting to CLST server at" << host << ":" << port;
    _socket->connectToHost(host, port);
}

void CustomStatusReceiver::disconnectFromServer()
{
    _reconnectTimer->stop();
    _autoReconnect = false;

    if (_socket->state() != QAbstractSocket::UnconnectedState) {
        _socket->disconnectFromHost();
        if (_socket->state() != QAbstractSocket::UnconnectedState) {
            _socket->abort();
        }
    }

    _connected = false;
    _linkAlive = false;
    _receiveBuffer.clear();
    emit connectionChanged();
    emit linkAliveChanged();
}

void CustomStatusReceiver::setAutoReconnect(bool enable)
{
    _autoReconnect = enable;
    if (!enable) {
        _reconnectTimer->stop();
    }
}

void CustomStatusReceiver::_onConnected()
{
    qCInfo(CustomStatusLog) << "Connected to CLST server";
    _connected = true;
    emit connectionChanged();
}

void CustomStatusReceiver::_onDisconnected()
{
    qCInfo(CustomStatusLog) << "Disconnected from CLST server";
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

void CustomStatusReceiver::_onError(QAbstractSocket::SocketError error)
{
    const QString errorStr = _socket->errorString();
    qCWarning(CustomStatusLog) << "Socket error:" << error << errorStr;
    emit errorOccurred(errorStr);

    if (_autoReconnect && !_reconnectTimer->isActive()) {
        _reconnectTimer->start(RECONNECT_INTERVAL_MS);
    }
}

void CustomStatusReceiver::_onReconnectTimer()
{
    if (_autoReconnect && _socket->state() == QAbstractSocket::UnconnectedState) {
        connectToServer(_serverHost, _serverPort);
    }
}

void CustomStatusReceiver::_onReadyRead()
{
    _receiveBuffer.append(_socket->readAll());
    if (_receiveBuffer.size() > MAX_BUFFER_SIZE) {
        qCWarning(CustomStatusLog) << "Receive buffer overflow, clearing";
        _receiveBuffer.clear();
        return;
    }

    bool parsed = false;
    int newline = -1;
    while ((newline = _receiveBuffer.indexOf('\n')) >= 0) {
        const QByteArray line = _receiveBuffer.left(newline).trimmed();
        _receiveBuffer = _receiveBuffer.mid(newline + 1);
        if (!line.isEmpty()) {
            parsed = _parseLine(line) || parsed;
        }
    }

    if (parsed) {
        emit statusReceived();
        emit statusUpdated();
    }
}

bool CustomStatusReceiver::_parseLine(const QByteArray& line)
{
    QJsonParseError parseError;
    const QJsonDocument doc = QJsonDocument::fromJson(line, &parseError);
    if (parseError.error != QJsonParseError::NoError || !doc.isObject()) {
        qCWarning(CustomStatusLog) << "Invalid CLST JSON:" << parseError.errorString();
        return false;
    }

    const QJsonObject root = doc.object();
    if (root.value(QStringLiteral("version")).toInt() != 1) {
        qCWarning(CustomStatusLog) << "Unsupported CLST version" << root.value(QStringLiteral("version")).toInt();
        return false;
    }

    const QString source = root.value(QStringLiteral("source")).toString();
    if (source.isEmpty()) {
        qCWarning(CustomStatusLog) << "CLST message missing mandatory source";
        return false;
    }

    const QJsonObject mission = root.value(QStringLiteral("mission")).toObject();
    const QJsonObject proximity = root.value(QStringLiteral("proximity")).toObject();
    const QJsonObject health = root.value(QStringLiteral("health")).toObject();

    _source = source;
    _missionState = mission.value(QStringLiteral("state")).toString(QStringLiteral("IDLE"));
    _missionStage = mission.value(QStringLiteral("stage")).toString(QStringLiteral("IDLE"));
    _progress = static_cast<float>(std::clamp(mission.value(QStringLiteral("progress")).toDouble(0.0), 0.0, 1.0));
    _message = mission.value(QStringLiteral("message")).toString();
    _canAbort = mission.value(QStringLiteral("can_abort")).toBool(false);

    QVariantList sectors;
    const QJsonArray sectorArray = proximity.value(QStringLiteral("sectors_m")).toArray();
    for (int i = 0; i < 8; ++i) {
        sectors.append(i < sectorArray.size() ? sectorArray.at(i).toDouble(-1.0) : -1.0);
    }
    _sectorsM = sectors;
    _frontM = static_cast<float>(proximity.value(QStringLiteral("front_m")).toDouble(-1.0));

    _slamStatus = health.value(QStringLiteral("slam")).toString(QStringLiteral("LOST"));
    _lidarAlive = health.value(QStringLiteral("lidar")).toBool(false);
    _cpuPct = static_cast<float>(health.value(QStringLiteral("cpu_pct")).toDouble(0.0));
    _evRateHz = static_cast<float>(health.value(QStringLiteral("ev_rate_hz")).toDouble(0.0));
    _recActive = health.value(QStringLiteral("rec")).toBool(false);

    QStringList errors;
    const QJsonArray errorArray = root.value(QStringLiteral("errors")).toArray();
    for (const QJsonValue& value : errorArray) {
        errors.append(value.toString());
    }
    _errors = errors;

    _lastStatusTime.restart();
    const bool wasAlive = _linkAlive;
    _linkAlive = true;
    if (wasAlive != _linkAlive) {
        emit linkAliveChanged();
    }

    qCDebug(CustomStatusLog) << "CLST" << _missionState << _missionStage << _source;
    return true;
}

void CustomStatusReceiver::_onStatusTimer()
{
    const bool wasAlive = _linkAlive;
    _linkAlive = _connected && _lastStatusTime.isValid() && _lastStatusTime.elapsed() < STATUS_STALE_MS;
    if (wasAlive != _linkAlive) {
        emit linkAliveChanged();
    }
    emit statusUpdated();
}

void CustomStatusReceiver::_resetData()
{
    _source = QStringLiteral("LIVE");
    _missionState = QStringLiteral("IDLE");
    _missionStage = QStringLiteral("IDLE");
    _progress = 0.0f;
    _message = QStringLiteral("NO DATA");
    _canAbort = false;
    _sectorsM = QVariantList({-1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0});
    _frontM = -1.0f;
    _slamStatus = QStringLiteral("LOST");
    _lidarAlive = false;
    _cpuPct = 0.0f;
    _evRateHz = 0.0f;
    _recActive = false;
    _errors.clear();
}

void CustomStatusReceiver::testConnection(const QString& host, int port)
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
