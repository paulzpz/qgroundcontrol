/****************************************************************************
 *
 * (c) 2009-2024 QGROUNDCONTROL PROJECT <http://www.qgroundcontrol.org>
 *
 * QGroundControl is licensed according to the terms in the file
 * COPYING.md in the root of the source code directory.
 *
 * @brief Innovatech inspection project metadata model
 * @file InspectionProject.h
 */

#pragma once

#include <QtCore/QDate>
#include <QtCore/QJsonObject>
#include <QtCore/QObject>
#include <QtCore/QStringList>
#include <QtCore/QVariantList>

class CustomPointCloudReceiver;
class CustomStatusReceiver;

class InspectionProject : public QObject
{
    Q_OBJECT

    Q_PROPERTY(QString baseDir READ baseDir NOTIFY baseDirChanged)
    Q_PROPERTY(QVariantList inspections READ inspections NOTIFY inspectionsChanged)
    Q_PROPERTY(bool inspectionSelected READ inspectionSelected NOTIFY selectionChanged)
    Q_PROPERTY(QString activeFlightPath READ activeFlightPath NOTIFY selectionChanged)
    Q_PROPERTY(QString chipText READ chipText NOTIFY selectionChanged)
    Q_PROPERTY(QString clientName READ clientName NOTIFY selectionChanged)
    Q_PROPERTY(QString siteName READ siteName NOTIFY selectionChanged)
    Q_PROPERTY(QString assetName READ assetName NOTIFY selectionChanged)
    Q_PROPERTY(QString inspectionId READ inspectionId NOTIFY selectionChanged)
    Q_PROPERTY(QString objective READ objective NOTIFY selectionChanged)
    Q_PROPERTY(QString notes READ notes NOTIFY selectionChanged)
    Q_PROPERTY(QString activeFlightId READ activeFlightId NOTIFY selectionChanged)
    Q_PROPERTY(bool flightOpen READ flightOpen NOTIFY selectionChanged)
    Q_PROPERTY(QString lastError READ lastError NOTIFY lastErrorChanged)

public:
    explicit InspectionProject(QObject* parent = nullptr);

    QString baseDir() const { return _baseDir; }
    QVariantList inspections() const { return _inspections; }
    bool inspectionSelected() const { return !_inspectionId.isEmpty(); }
    QString activeFlightPath() const { return _flightOpen ? _activeFlightPath : QString(); }
    QString chipText() const;
    QString clientName() const { return _clientName; }
    QString siteName() const { return _siteName; }
    QString assetName() const { return _assetName; }
    QString inspectionId() const { return _inspectionId; }
    QString objective() const { return _objective; }
    QString notes() const { return _notes; }
    QString activeFlightId() const { return _activeFlightId; }
    bool flightOpen() const { return _flightOpen; }
    QString lastError() const { return _lastError; }

    Q_INVOKABLE void reload();
    Q_INVOKABLE bool applyBaseDir(const QString& baseDir);
    Q_INVOKABLE bool selectInspection(const QString& inspectionId);
    Q_INVOKABLE bool createInspection(const QString& clientName,
                                      const QString& siteName,
                                      const QString& assetName,
                                      const QString& objective,
                                      const QString& notes);
    Q_INVOKABLE bool createFlight(const QString& operatorId,
                                  const QString& pilotId,
                                  const QString& vehicleId,
                                  const QString& companionId,
                                  const QString& px4ParamsProfile);
    Q_INVOKABLE bool closeFlight();
    Q_INVOKABLE QString slugForName(const QString& name) const;
    Q_INVOKABLE double baseDirFreeGb() const;

    void setSourceReceivers(CustomPointCloudReceiver* pointCloudReceiver,
                            CustomStatusReceiver* statusReceiver);

signals:
    void baseDirChanged();
    void inspectionsChanged();
    void selectionChanged();
    void lastErrorChanged();

private:
    QString _defaultBaseDir() const;
    QString _inspectionDirForId(const QString& inspectionId) const;
    QString _inspectionJsonPath(const QString& inspectionId) const;
    QString _flightDirForId(const QString& flightId) const;
    QString _flightJsonPath(const QString& flightId) const;
    QString _nextInspectionId(const QString& assetSlug, const QDate& date) const;
    QString _nextFlightId() const;
    QString _isoNow() const;
    QString _timezoneName() const;
    bool _ensureBaseDir();
    bool _loadInspection(const QString& inspectionId, bool restoreFlight);
    bool _writeJsonFile(const QString& path, const QJsonObject& object);
    QJsonObject _readJsonFile(const QString& path, bool* ok) const;
    QJsonObject _currentInspectionJson() const;
    QJsonObject _currentFlightJson() const;
    void _loadSettings();
    void _saveSettings();
    void _setError(const QString& error);
    void _clearError();
    void _appendSource(const QString& source);
    void _rewriteCurrentFlight();
    static QString _slugify(const QString& input);

    QString _baseDir;
    QVariantList _inspections;

    QString _clientName;
    QString _siteName;
    QString _assetName;
    QString _inspectionId;
    QString _objective;
    QString _notes;
    QString _inspectionPath;
    QString _createdAt;
    QString _timezone;
    QString _appVersion;

    QString _activeFlightId;
    QString _activeFlightPath;
    QString _flightCreatedAt;
    QString _operatorId;
    QString _pilotId;
    QString _vehicleId;
    QString _companionId;
    QString _px4ParamsProfile;
    QStringList _sourcesSeen;
    bool _flightOpen = false;

    QString _lastError;
};
