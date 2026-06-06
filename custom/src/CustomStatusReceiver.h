/****************************************************************************
 *
 * (c) 2009-2024 QGROUNDCONTROL PROJECT <http://www.qgroundcontrol.org>
 *
 * QGroundControl is licensed according to the terms in the file
 * COPYING.md in the root of the source code directory.
 *
 * @brief CLST Status Receiver for custom QGC layer
 * @file CustomStatusReceiver.h
 */

#pragma once

#include <QtCore/QByteArray>
#include <QtCore/QElapsedTimer>
#include <QtCore/QObject>
#include <QtCore/QStringList>
#include <QtCore/QTimer>
#include <QtCore/QVariantList>
#include <QtNetwork/QAbstractSocket>
#include <QtNetwork/QTcpSocket>

#include "ErrorCatalog.h"

class CustomStatusReceiver : public QObject
{
    Q_OBJECT

    Q_PROPERTY(bool linkAlive READ linkAlive NOTIFY linkAliveChanged)
    Q_PROPERTY(bool connected READ connected NOTIFY connectionChanged)
    Q_PROPERTY(int lastAgeMs READ lastAgeMs NOTIFY statusUpdated)
    Q_PROPERTY(QString source READ source NOTIFY statusReceived)
    Q_PROPERTY(QString missionState READ missionState NOTIFY statusReceived)
    Q_PROPERTY(QString missionStage READ missionStage NOTIFY statusReceived)
    Q_PROPERTY(float progress READ progress NOTIFY statusReceived)
    Q_PROPERTY(QString message READ message NOTIFY statusReceived)
    Q_PROPERTY(bool canAbort READ canAbort NOTIFY statusReceived)
    Q_PROPERTY(QVariantList sectorsM READ sectorsM NOTIFY statusReceived)
    Q_PROPERTY(float frontM READ frontM NOTIFY statusReceived)
    Q_PROPERTY(QString slamStatus READ slamStatus NOTIFY statusReceived)
    Q_PROPERTY(bool lidarAlive READ lidarAlive NOTIFY statusReceived)
    Q_PROPERTY(float cpuPct READ cpuPct NOTIFY statusReceived)
    Q_PROPERTY(float evRateHz READ evRateHz NOTIFY statusReceived)
    Q_PROPERTY(bool recActive READ recActive NOTIFY statusReceived)
    Q_PROPERTY(QStringList errors READ errors NOTIFY statusReceived)
    Q_PROPERTY(QVariantList activeErrors READ activeErrors NOTIFY statusUpdated)
    Q_PROPERTY(bool scanBlockedByError READ scanBlockedByError NOTIFY statusUpdated)
    Q_PROPERTY(QString scanBlockReason READ scanBlockReason NOTIFY statusUpdated)
    Q_PROPERTY(QString proximityContext READ proximityContext NOTIFY statusUpdated)
    Q_PROPERTY(QString proximityContextLabel READ proximityContextLabel NOTIFY statusUpdated)
    Q_PROPERTY(QString host READ host NOTIFY networkSettingsChanged)
    Q_PROPERTY(int port READ port NOTIFY networkSettingsChanged)
    Q_PROPERTY(QString lastTestResult READ lastTestResult NOTIFY lastTestResultChanged)

public:
    explicit CustomStatusReceiver(QObject *parent = nullptr);
    ~CustomStatusReceiver();

    bool linkAlive() const { return _linkAlive; }
    bool connected() const { return _connected; }
    int lastAgeMs() const;
    QString source() const { return _source; }
    QString missionState() const { return _missionState; }
    QString missionStage() const { return _missionStage; }
    float progress() const { return _progress; }
    QString message() const { return _message; }
    bool canAbort() const { return _canAbort; }
    QVariantList sectorsM() const { return _sectorsM; }
    float frontM() const { return _frontM; }
    QString slamStatus() const { return _slamStatus; }
    bool lidarAlive() const { return _lidarAlive; }
    float cpuPct() const { return _cpuPct; }
    float evRateHz() const { return _evRateHz; }
    bool recActive() const { return _recActive; }
    QStringList errors() const { return _errors; }
    QVariantList activeErrors() const;
    bool scanBlockedByError() const;
    QString scanBlockReason() const;
    QString proximityContext() const;
    QString proximityContextLabel() const;
    Q_INVOKABLE QString proximityContextFor(const QString& missionState, const QString& missionStage) const;
    Q_INVOKABLE QString proximityColor(int sectorIndex, double distance) const;
    QString host() const { return _serverHost; }
    int port() const { return _serverPort; }
    QString lastTestResult() const { return _lastTestResult; }

    Q_INVOKABLE void connectToConfiguredServer();
    Q_INVOKABLE void applyNetworkSettings(const QString& host, int port);
    Q_INVOKABLE void testConnection(const QString& host, int port);

public slots:
    void connectToServer(const QString& host, quint16 port);
    void disconnectFromServer();
    void setAutoReconnect(bool enable);

signals:
    void statusReceived();
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
    bool _parseLine(const QByteArray& line);
    void _resetData();

    QTcpSocket* _socket = nullptr;
    QString _serverHost;
    quint16 _serverPort = 7778;
    bool _autoReconnect = true;
    QTimer* _reconnectTimer = nullptr;
    QByteArray _receiveBuffer;

    QString _source = QStringLiteral("LIVE");
    QString _missionState = QStringLiteral("IDLE");
    QString _missionStage = QStringLiteral("IDLE");
    float _progress = 0.0f;
    QString _message = QStringLiteral("NO DATA");
    bool _canAbort = false;
    QVariantList _sectorsM;
    float _frontM = -1.0f;
    QString _slamStatus = QStringLiteral("LOST");
    bool _lidarAlive = false;
    float _cpuPct = 0.0f;
    float _evRateHz = 0.0f;
    bool _recActive = false;
    QStringList _errors;
    QString _lastProximityContext = QStringLiteral("FREE_FLIGHT");
    ErrorCatalog _errorCatalog;

    QElapsedTimer _lastStatusTime;
    QTimer* _statusTimer = nullptr;
    bool _linkAlive = false;
    bool _connected = false;
    QString _lastTestResult;
};
