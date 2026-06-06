/****************************************************************************
 *
 * (c) 2009-2024 QGROUNDCONTROL PROJECT <http://www.qgroundcontrol.org>
 *
 * QGroundControl is licensed according to the terms in the file
 * COPYING.md in the root of the source code directory.
 *
 * @brief Innovatech inspection project metadata model
 * @file InspectionProject.cc
 */

#include "InspectionProject.h"
#include "CustomPointCloudReceiver.h"
#include "CustomStatusReceiver.h"

#include <QtCore/QCoreApplication>
#include <QtCore/QDateTime>
#include <QtCore/QDir>
#include <QtCore/QFile>
#include <QtCore/QFileInfo>
#include <QtCore/QJsonArray>
#include <QtCore/QJsonDocument>
#include <QtCore/QJsonObject>
#include <QtCore/QRegularExpression>
#include <QtCore/QSettings>
#include <QtCore/QStandardPaths>
#include <QtCore/QTimeZone>
#include <QtCore/QStorageInfo>

namespace {
constexpr int kSchemaVersion = 1;
constexpr auto kProjectSettingsGroup = "Project";
constexpr auto kBaseDirKey = "baseDir";
constexpr auto kLastInspectionKey = "lastInspectionId";
constexpr auto kLastFlightKey = "lastFlightId";
constexpr auto kProtocolClpcVersion = "1";
constexpr auto kProtocolClstVersion = "1";
}

static QString settingName(const char* name)
{
    return QString::fromLatin1(name);
}

InspectionProject::InspectionProject(QObject* parent)
    : QObject(parent)
{
    _loadSettings();
    reload();

    QSettings settings;
    settings.beginGroup(settingName(kProjectSettingsGroup));
    const QString lastInspectionId = settings.value(settingName(kLastInspectionKey)).toString();
    settings.endGroup();
    if (!lastInspectionId.isEmpty()) {
        _loadInspection(lastInspectionId, true);
    }
}

void InspectionProject::_loadSettings()
{
    QSettings settings;
    settings.beginGroup(settingName(kProjectSettingsGroup));
    _baseDir = settings.value(settingName(kBaseDirKey), _defaultBaseDir()).toString();
    settings.endGroup();
    if (_baseDir.trimmed().isEmpty()) {
        _baseDir = _defaultBaseDir();
    }
}

void InspectionProject::_saveSettings()
{
    QSettings settings;
    settings.beginGroup(settingName(kProjectSettingsGroup));
    settings.setValue(settingName(kBaseDirKey), _baseDir);
    settings.setValue(settingName(kLastInspectionKey), _inspectionId);
    settings.setValue(settingName(kLastFlightKey), _flightOpen ? _activeFlightId : QString());
    settings.endGroup();
}

QString InspectionProject::_defaultBaseDir() const
{
    QString documents = QStandardPaths::writableLocation(QStandardPaths::DocumentsLocation);
    if (documents.isEmpty()) {
        documents = QDir::homePath() + QStringLiteral("/Documents");
    }
    return QDir(documents).filePath(QStringLiteral("Innovatech/inspections"));
}

double InspectionProject::baseDirFreeGb() const
{
    QString probePath = QDir(_baseDir).absolutePath();
    if (!QDir(probePath).exists()) {
        probePath = QFileInfo(probePath).absolutePath();
    }

    const QStorageInfo storage(probePath);
    if (!storage.isValid() || !storage.isReady()) {
        return -1.0;
    }
    return static_cast<double>(storage.bytesAvailable()) / (1024.0 * 1024.0 * 1024.0);
}

QString InspectionProject::_inspectionDirForId(const QString& inspectionId) const
{
    return QDir(_baseDir).filePath(QStringLiteral("inspection_%1").arg(inspectionId));
}

QString InspectionProject::_inspectionJsonPath(const QString& inspectionId) const
{
    return QDir(_inspectionDirForId(inspectionId)).filePath(QStringLiteral("inspection.json"));
}

QString InspectionProject::_flightDirForId(const QString& flightId) const
{
    return QDir(_inspectionPath).filePath(QStringLiteral("flight_%1").arg(flightId));
}

QString InspectionProject::_flightJsonPath(const QString& flightId) const
{
    return QDir(_flightDirForId(flightId)).filePath(QStringLiteral("flight.json"));
}

QString InspectionProject::_isoNow() const
{
    return QDateTime::currentDateTime().toString(Qt::ISODate);
}

QString InspectionProject::_timezoneName() const
{
    return QString::fromUtf8(QTimeZone::systemTimeZoneId());
}

bool InspectionProject::_ensureBaseDir()
{
    QDir dir(_baseDir);
    if (dir.exists()) {
        return true;
    }
    if (!dir.mkpath(QStringLiteral("."))) {
        _setError(QStringLiteral("Cannot create base directory: %1").arg(_baseDir));
        return false;
    }
    return true;
}

void InspectionProject::reload()
{
    _inspections.clear();
    _ensureBaseDir();

    QDir dir(_baseDir);
    const QFileInfoList entries = dir.entryInfoList(QStringList() << QStringLiteral("inspection_*"), QDir::Dirs | QDir::NoDotAndDotDot, QDir::Name);
    for (const QFileInfo& entry : entries) {
        const QString jsonPath = QDir(entry.absoluteFilePath()).filePath(QStringLiteral("inspection.json"));
        bool ok = false;
        const QJsonObject object = _readJsonFile(jsonPath, &ok);
        if (!ok) {
            continue;
        }

        QVariantMap item;
        const QString inspectionId = object.value(QStringLiteral("inspection_id")).toString();
        const QString assetName = object.value(QStringLiteral("asset_name")).toString();
        const QString clientName = object.value(QStringLiteral("client_name")).toString();
        const QString siteName = object.value(QStringLiteral("site_name")).toString();
        item.insert(QStringLiteral("inspection_id"), inspectionId);
        item.insert(QStringLiteral("label"), QStringLiteral("%1 / %2 / %3").arg(assetName, inspectionId, clientName));
        item.insert(QStringLiteral("client_name"), clientName);
        item.insert(QStringLiteral("site_name"), siteName);
        item.insert(QStringLiteral("asset_name"), assetName);
        item.insert(QStringLiteral("path"), entry.absoluteFilePath());
        _inspections.append(item);
    }

    emit inspectionsChanged();
}

bool InspectionProject::applyBaseDir(const QString& baseDir)
{
    const QString clean = baseDir.trimmed().isEmpty() ? _defaultBaseDir() : QDir::cleanPath(baseDir.trimmed());
    if (_baseDir == clean) {
        reload();
        return true;
    }

    _baseDir = clean;
    _inspectionId.clear();
    _activeFlightId.clear();
    _activeFlightPath.clear();
    _flightOpen = false;
    _saveSettings();
    reload();
    emit baseDirChanged();
    emit selectionChanged();
    return true;
}

QString InspectionProject::_slugify(const QString& input)
{
    QString s = input.toLower().trimmed();
    s.replace(QRegularExpression(QStringLiteral("\\s+")), QStringLiteral("-"));
    s.replace(QRegularExpression(QStringLiteral("[^a-z0-9-]+")), QStringLiteral("-"));
    s.replace(QRegularExpression(QStringLiteral("-+")), QStringLiteral("-"));
    s.replace(QRegularExpression(QStringLiteral("^-|-$")), QString());
    if (s.isEmpty()) {
        s = QStringLiteral("asset");
    }
    if (s.size() > 40) {
        s = s.left(40);
        s.replace(QRegularExpression(QStringLiteral("-+$")), QString());
    }
    return s.isEmpty() ? QStringLiteral("asset") : s;
}

QString InspectionProject::slugForName(const QString& name) const
{
    return _slugify(name);
}

QString InspectionProject::_nextInspectionId(const QString& assetSlug, const QDate& date) const
{
    const QString prefix = QStringLiteral("%1_%2_").arg(date.toString(QStringLiteral("yyyyMMdd")), assetSlug);
    int nextSeq = 1;

    QDir dir(_baseDir);
    const QFileInfoList entries = dir.entryInfoList(QStringList() << QStringLiteral("inspection_%1??").arg(prefix), QDir::Dirs | QDir::NoDotAndDotDot, QDir::Name);
    for (const QFileInfo& entry : entries) {
        const QString name = entry.fileName();
        const QString id = name.mid(QStringLiteral("inspection_").size());
        if (!id.startsWith(prefix)) {
            continue;
        }
        bool ok = false;
        const int seq = id.mid(prefix.size(), 2).toInt(&ok);
        if (ok) {
            nextSeq = qMax(nextSeq, seq + 1);
        }
    }

    return QStringLiteral("%1%2").arg(prefix, QString::number(nextSeq).rightJustified(2, QLatin1Char('0')));
}

bool InspectionProject::createInspection(const QString& clientName,
                                         const QString& siteName,
                                         const QString& assetName,
                                         const QString& objective,
                                         const QString& notes)
{
    _clearError();
    if (!_ensureBaseDir()) {
        return false;
    }

    const QString cleanClient = clientName.trimmed();
    const QString cleanSite = siteName.trimmed();
    const QString cleanAsset = assetName.trimmed();
    if (cleanClient.isEmpty() || cleanSite.isEmpty() || cleanAsset.isEmpty()) {
        _setError(QStringLiteral("Client, Site and Asset are required"));
        return false;
    }

    const QString inspectionId = _nextInspectionId(_slugify(cleanAsset), QDate::currentDate());
    const QString inspectionPath = _inspectionDirForId(inspectionId);
    QDir dir;
    if (!dir.mkpath(inspectionPath)) {
        _setError(QStringLiteral("Cannot create inspection directory: %1").arg(inspectionPath));
        return false;
    }

    _clientName = cleanClient;
    _siteName = cleanSite;
    _assetName = cleanAsset;
    _inspectionId = inspectionId;
    _objective = objective.trimmed();
    _notes = notes.trimmed();
    _inspectionPath = inspectionPath;
    _createdAt = _isoNow();
    _timezone = _timezoneName();
    _appVersion = QCoreApplication::applicationVersion();
    if (_appVersion.isEmpty()) {
        _appVersion = QStringLiteral("unknown");
    }
    _activeFlightId.clear();
    _activeFlightPath.clear();
    _flightOpen = false;
    _sourcesSeen.clear();

    if (!_writeJsonFile(_inspectionJsonPath(_inspectionId), _currentInspectionJson())) {
        return false;
    }

    _saveSettings();
    reload();
    emit selectionChanged();
    return true;
}

bool InspectionProject::_loadInspection(const QString& inspectionId, bool restoreFlight)
{
    _clearError();
    bool ok = false;
    const QJsonObject object = _readJsonFile(_inspectionJsonPath(inspectionId), &ok);
    if (!ok) {
        _setError(QStringLiteral("Cannot load inspection: %1").arg(inspectionId));
        return false;
    }

    _clientName = object.value(QStringLiteral("client_name")).toString();
    _siteName = object.value(QStringLiteral("site_name")).toString();
    _assetName = object.value(QStringLiteral("asset_name")).toString();
    _inspectionId = object.value(QStringLiteral("inspection_id")).toString(inspectionId);
    _objective = object.value(QStringLiteral("objective")).toString();
    _notes = object.value(QStringLiteral("notes")).toString();
    _createdAt = object.value(QStringLiteral("created_at")).toString();
    _timezone = object.value(QStringLiteral("timezone")).toString();
    _appVersion = object.value(QStringLiteral("app_version")).toString();
    _inspectionPath = _inspectionDirForId(_inspectionId);

    _activeFlightId.clear();
    _activeFlightPath.clear();
    _flightCreatedAt.clear();
    _operatorId.clear();
    _pilotId.clear();
    _vehicleId.clear();
    _companionId.clear();
    _px4ParamsProfile.clear();
    _sourcesSeen.clear();
    _flightOpen = false;

    if (restoreFlight) {
        QSettings settings;
        settings.beginGroup(settingName(kProjectSettingsGroup));
        const QString lastFlightId = settings.value(settingName(kLastFlightKey)).toString();
        settings.endGroup();
        if (!lastFlightId.isEmpty()) {
            bool flightOk = false;
            const QJsonObject flight = _readJsonFile(_flightJsonPath(lastFlightId), &flightOk);
            if (flightOk && flight.value(QStringLiteral("status")).toString() == QStringLiteral("open")) {
                _activeFlightId = flight.value(QStringLiteral("flight_id")).toString(lastFlightId);
                _activeFlightPath = _flightDirForId(_activeFlightId);
                _flightCreatedAt = flight.value(QStringLiteral("created_at")).toString();
                _operatorId = flight.value(QStringLiteral("operator_id")).toString();
                _pilotId = flight.value(QStringLiteral("pilot_id")).toString();
                _vehicleId = flight.value(QStringLiteral("vehicle_id")).toString();
                _companionId = flight.value(QStringLiteral("companion_id")).toString();
                _px4ParamsProfile = flight.value(QStringLiteral("px4_params_profile")).toString();
                for (const QJsonValue& value : flight.value(QStringLiteral("sources_seen")).toArray()) {
                    const QString source = value.toString().trimmed().toUpper();
                    if (!source.isEmpty() && !_sourcesSeen.contains(source)) {
                        _sourcesSeen.append(source);
                    }
                }
                _flightOpen = true;
            }
        }
    }

    _saveSettings();
    emit selectionChanged();
    return true;
}

bool InspectionProject::selectInspection(const QString& inspectionId)
{
    return _loadInspection(inspectionId, true);
}

QString InspectionProject::_nextFlightId() const
{
    int nextSeq = 1;
    QDir dir(_inspectionPath);
    const QFileInfoList entries = dir.entryInfoList(QStringList() << QStringLiteral("flight_???"), QDir::Dirs | QDir::NoDotAndDotDot, QDir::Name);
    for (const QFileInfo& entry : entries) {
        const QString id = entry.fileName().mid(QStringLiteral("flight_").size());
        bool ok = false;
        const int seq = id.toInt(&ok);
        if (ok) {
            nextSeq = qMax(nextSeq, seq + 1);
        }
    }
    return QString::number(nextSeq).rightJustified(3, QLatin1Char('0'));
}

bool InspectionProject::createFlight(const QString& operatorId,
                                     const QString& pilotId,
                                     const QString& vehicleId,
                                     const QString& companionId,
                                     const QString& px4ParamsProfile)
{
    _clearError();
    if (!inspectionSelected()) {
        _setError(QStringLiteral("Select or create an inspection first"));
        return false;
    }

    _activeFlightId = _nextFlightId();
    _activeFlightPath = _flightDirForId(_activeFlightId);
    QDir dir;
    if (!dir.mkpath(_activeFlightPath)) {
        _setError(QStringLiteral("Cannot create flight directory: %1").arg(_activeFlightPath));
        return false;
    }

    _flightCreatedAt = _isoNow();
    _operatorId = operatorId.trimmed();
    _pilotId = pilotId.trimmed();
    _vehicleId = vehicleId.trimmed();
    _companionId = companionId.trimmed();
    _px4ParamsProfile = px4ParamsProfile.trimmed();
    _sourcesSeen.clear();
    _flightOpen = true;

    if (!_writeJsonFile(_flightJsonPath(_activeFlightId), _currentFlightJson())) {
        return false;
    }

    _saveSettings();
    emit selectionChanged();
    return true;
}

bool InspectionProject::closeFlight()
{
    _clearError();
    if (!_flightOpen || _activeFlightId.isEmpty()) {
        return true;
    }

    _flightOpen = false;
    if (!_writeJsonFile(_flightJsonPath(_activeFlightId), _currentFlightJson())) {
        _flightOpen = true;
        return false;
    }

    _activeFlightId.clear();
    _activeFlightPath.clear();
    _saveSettings();
    emit selectionChanged();
    return true;
}

QJsonObject InspectionProject::_currentInspectionJson() const
{
    QJsonObject protocols;
    protocols.insert(QStringLiteral("clpc"), QString::fromLatin1(kProtocolClpcVersion));
    protocols.insert(QStringLiteral("clst"), QString::fromLatin1(kProtocolClstVersion));

    QJsonObject object;
    object.insert(QStringLiteral("schema_version"), kSchemaVersion);
    object.insert(QStringLiteral("client_name"), _clientName);
    object.insert(QStringLiteral("site_name"), _siteName);
    object.insert(QStringLiteral("asset_name"), _assetName);
    object.insert(QStringLiteral("inspection_id"), _inspectionId);
    object.insert(QStringLiteral("objective"), _objective);
    object.insert(QStringLiteral("notes"), _notes);
    object.insert(QStringLiteral("created_at"), _createdAt);
    object.insert(QStringLiteral("timezone"), _timezone);
    object.insert(QStringLiteral("app_version"), _appVersion);
    object.insert(QStringLiteral("protocol_versions"), protocols);
    return object;
}

QJsonObject InspectionProject::_currentFlightJson() const
{
    QJsonArray sources;
    for (const QString& source : _sourcesSeen) {
        sources.append(source);
    }

    QJsonObject object;
    object.insert(QStringLiteral("flight_id"), _activeFlightId);
    object.insert(QStringLiteral("created_at"), _flightCreatedAt);
    object.insert(QStringLiteral("operator_id"), _operatorId);
    object.insert(QStringLiteral("pilot_id"), _pilotId);
    object.insert(QStringLiteral("vehicle_id"), _vehicleId);
    object.insert(QStringLiteral("companion_id"), _companionId);
    object.insert(QStringLiteral("px4_params_profile"), _px4ParamsProfile);
    object.insert(QStringLiteral("sources_seen"), sources);
    object.insert(QStringLiteral("status"), _flightOpen ? QStringLiteral("open") : QStringLiteral("closed"));
    return object;
}

bool InspectionProject::_writeJsonFile(const QString& path, const QJsonObject& object)
{
    QFile file(path);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        _setError(QStringLiteral("Cannot write %1: %2").arg(path, file.errorString()));
        return false;
    }

    file.write(QJsonDocument(object).toJson(QJsonDocument::Indented));
    file.close();
    return true;
}

QJsonObject InspectionProject::_readJsonFile(const QString& path, bool* ok) const
{
    if (ok) {
        *ok = false;
    }

    QFile file(path);
    if (!file.open(QIODevice::ReadOnly)) {
        return {};
    }
    QJsonParseError error;
    const QJsonDocument doc = QJsonDocument::fromJson(file.readAll(), &error);
    if (error.error != QJsonParseError::NoError || !doc.isObject()) {
        return {};
    }
    if (ok) {
        *ok = true;
    }
    return doc.object();
}

QString InspectionProject::chipText() const
{
    if (!inspectionSelected()) {
        return QStringLiteral("NO INSPECTION");
    }
    if (_flightOpen && !_activeFlightId.isEmpty()) {
        return QStringLiteral("%1 / %2 / flight_%3").arg(_assetName, _inspectionId, _activeFlightId);
    }
    return QStringLiteral("%1 / %2 / NO FLIGHT").arg(_assetName, _inspectionId);
}

void InspectionProject::setSourceReceivers(CustomPointCloudReceiver* pointCloudReceiver,
                                           CustomStatusReceiver* statusReceiver)
{
    if (pointCloudReceiver) {
        connect(pointCloudReceiver, &CustomPointCloudReceiver::frameReceived, this, [this, pointCloudReceiver]() {
            _appendSource(pointCloudReceiver->source());
        });
    }
    if (statusReceiver) {
        connect(statusReceiver, &CustomStatusReceiver::statusReceived, this, [this, statusReceiver]() {
            _appendSource(statusReceiver->source());
        });
    }
}

void InspectionProject::_appendSource(const QString& source)
{
    if (!_flightOpen) {
        return;
    }
    const QString clean = source.trimmed().toUpper();
    if (clean.isEmpty() || _sourcesSeen.contains(clean)) {
        return;
    }
    _sourcesSeen.append(clean);
    _rewriteCurrentFlight();
}

void InspectionProject::_rewriteCurrentFlight()
{
    if (_activeFlightId.isEmpty()) {
        return;
    }
    _writeJsonFile(_flightJsonPath(_activeFlightId), _currentFlightJson());
}

void InspectionProject::_setError(const QString& error)
{
    if (_lastError == error) {
        return;
    }
    _lastError = error;
    emit lastErrorChanged();
}

void InspectionProject::_clearError()
{
    _setError(QString());
}
