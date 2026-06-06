/****************************************************************************
 *
 * (c) 2009-2024 QGROUNDCONTROL PROJECT <http://www.qgroundcontrol.org>
 *
 * QGroundControl is licensed according to the terms in the file
 * COPYING.md in the root of the source code directory.
 *
 * @brief CLPC Point Cloud Receiver for custom QGC layer
 * @file CustomPointCloudReceiver.h
 */

#pragma once

#include <QtCore/QByteArray>
#include <QtCore/QElapsedTimer>
#include <QtCore/QObject>
#include <QtCore/QTimer>
#include <QtCore/QVector>
#include <QtGui/QQuaternion>
#include <QtGui/QVector3D>
#include <QtNetwork/QAbstractSocket>
#include <QtNetwork/QTcpSocket>

struct CLPCPoint {
    float x;
    float y;
    float z;
    uint8_t intensity;
};

#pragma pack(push, 1)
struct CLPCHeader {
    char magic[4];
    uint16_t version;
    uint32_t frameId;
    uint64_t timestampUs;
    uint32_t pointCount;
    uint32_t flags;
    float poseX;
    float poseY;
    float poseZ;
    float poseQw;
    float poseQx;
    float poseQy;
    float poseQz;
    float voxelSize;
};
#pragma pack(pop)

constexpr uint32_t CLPC_FLAG_HAS_INTENSITY = 0x01;
constexpr uint32_t CLPC_FLAG_SOURCE_SIM = 0x02;
constexpr uint32_t CLPC_FLAG_SOURCE_REPLAY = 0x04;

constexpr size_t CLPC_HEADER_SIZE = sizeof(CLPCHeader);
constexpr size_t CLPC_POINT_SIZE_NO_INTENSITY = 12;
constexpr size_t CLPC_POINT_SIZE_WITH_INTENSITY = 13;

class CustomPointCloudReceiver : public QObject
{
    Q_OBJECT

    Q_PROPERTY(bool linkAlive READ linkAlive NOTIFY linkAliveChanged)
    Q_PROPERTY(uint32_t frameId READ frameId NOTIFY frameReceived)
    Q_PROPERTY(uint32_t pointCount READ pointCount NOTIFY frameReceived)
    Q_PROPERTY(QVector3D dronePose READ dronePose NOTIFY frameReceived)
    Q_PROPERTY(QQuaternion droneOrientation READ droneOrientation NOTIFY frameReceived)
    Q_PROPERTY(float voxelSize READ voxelSize NOTIFY frameReceived)
    Q_PROPERTY(int lastFrameAgeMs READ lastFrameAgeMs NOTIFY statusUpdated)
    Q_PROPERTY(QString statusText READ statusText NOTIFY statusUpdated)
    Q_PROPERTY(bool connected READ connected NOTIFY connectionChanged)
    Q_PROPERTY(QString linkState READ linkState NOTIFY statusUpdated)
    Q_PROPERTY(QString source READ source NOTIFY frameReceived)
    Q_PROPERTY(QString host READ host NOTIFY networkSettingsChanged)
    Q_PROPERTY(int port READ port NOTIFY networkSettingsChanged)
    Q_PROPERTY(QString lastTestResult READ lastTestResult NOTIFY lastTestResultChanged)

public:
    explicit CustomPointCloudReceiver(QObject *parent = nullptr);
    ~CustomPointCloudReceiver();

    bool linkAlive() const { return _linkAlive; }
    uint32_t frameId() const { return _currentFrameId; }
    uint32_t pointCount() const { return _currentPointCount; }
    QVector3D dronePose() const { return _dronePose; }
    QQuaternion droneOrientation() const { return _droneOrientation; }
    float voxelSize() const { return _voxelSize; }
    int lastFrameAgeMs() const;
    QString statusText() const;
    bool connected() const { return _connected; }
    QString linkState() const;
    QString source() const { return _source; }
    QString host() const { return _serverHost; }
    int port() const { return _serverPort; }
    QString lastTestResult() const { return _lastTestResult; }

    const QVector<CLPCPoint>& points() const { return _points; }

    Q_INVOKABLE void connectToConfiguredServer();
    Q_INVOKABLE void applyNetworkSettings(const QString& host, int port);
    Q_INVOKABLE void testConnection(const QString& host, int port);

public slots:
    void connectToServer(const QString& host, quint16 port);
    void disconnectFromServer();
    void setAutoReconnect(bool enable);

signals:
    void frameReceived();
    void linkAliveChanged();
    void statusUpdated();
    void connectionChanged();
    void networkSettingsChanged();
    void lastTestResultChanged();
    void errorOccurred(const QString& error);

private slots:
    void _onConnected();
    void _onDisconnected();
    void _onReadyRead();
    void _onError(QAbstractSocket::SocketError error);
    void _onStatusTimer();
    void _onReconnectTimer();

private:
    void _loadNetworkSettings();
    void _saveNetworkSettings();
    bool _parseFrame();
    bool _validateHeader(const CLPCHeader& header);
    void _resetState();

    QTcpSocket* _socket = nullptr;
    QString _serverHost;
    quint16 _serverPort = 7777;
    bool _autoReconnect = true;
    QTimer* _reconnectTimer = nullptr;

    QByteArray _receiveBuffer;

    uint32_t _currentFrameId = 0;
    uint32_t _currentPointCount = 0;
    QVector3D _dronePose = QVector3D(0, 0, 0);
    QQuaternion _droneOrientation = QQuaternion(1, 0, 0, 0);
    float _voxelSize = 0.03f;
    QVector<CLPCPoint> _points;
    QString _source = QStringLiteral("LIVE");

    QElapsedTimer _lastFrameTime;
    QTimer* _statusTimer = nullptr;
    bool _linkAlive = false;
    bool _connected = false;
    uint64_t _totalFramesReceived = 0;
    uint64_t _totalBytesReceived = 0;
    QString _lastTestResult;
};
