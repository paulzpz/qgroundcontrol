/****************************************************************************
 *
 * Innovatech CLST error catalog helper.
 *
 ****************************************************************************/

#include "ErrorCatalog.h"

#include <QtCore/QFile>
#include <QtCore/QJsonDocument>
#include <QtCore/QJsonObject>
#include <QtCore/QJsonParseError>
#include <QtCore/QIODevice>
#include <QtCore/QJsonValue>
#include <QtCore/QVariant>
#include <QtCore/QDebug>

ErrorCatalog::ErrorCatalog()
{
    load();
}

bool ErrorCatalog::load(const QString& path)
{
    _entries.clear();

    QFile file(path);
    if (!file.open(QIODevice::ReadOnly)) {
        qWarning() << "ErrorCatalog: cannot open" << path << file.errorString();
        return false;
    }

    QJsonParseError parseError;
    const QJsonDocument doc = QJsonDocument::fromJson(file.readAll(), &parseError);
    if (parseError.error != QJsonParseError::NoError || !doc.isObject()) {
        qWarning() << "ErrorCatalog: invalid JSON" << path << parseError.errorString();
        _entries.clear();
        return false;
    }

    const QJsonObject root = doc.object();
    for (auto it = root.constBegin(); it != root.constEnd(); ++it) {
        if (!it.value().isObject()) {
            qWarning() << "ErrorCatalog: skipping non-object entry" << it.key();
            continue;
        }

        const QJsonObject object = it.value().toObject();
        Entry entry;
        entry.code = it.key().trimmed().toUpper();
        entry.severity = object.value(QStringLiteral("severity")).toString(QStringLiteral("warning")).trimmed().toLower();
        entry.title = object.value(QStringLiteral("title")).toString(entry.code).trimmed();
        entry.requiredAction = object.value(QStringLiteral("required_action")).toString().trimmed();
        entry.blocksFlight = object.value(QStringLiteral("blocks_flight")).toBool(false);
        entry.blocksScan = object.value(QStringLiteral("blocks_scan")).toBool(false);
        entry.blocksMeasure = object.value(QStringLiteral("blocks_measure")).toBool(false);
        entry.module = object.value(QStringLiteral("module")).toString().trimmed();
        entry.uncatalogued = false;

        if (entry.requiredAction.isEmpty()) {
            entry.requiredAction = QStringLiteral("Review system status and report missing operator guidance.");
        }
        _entries.insert(entry.code, entry);
    }

    return !_entries.isEmpty();
}

ErrorCatalog::Entry ErrorCatalog::entryForCode(const QString& code) const
{
    const QString cleanCode = code.trimmed().toUpper();
    if (cleanCode.isEmpty()) {
        return _fallbackEntry(QStringLiteral("UNKNOWN"));
    }
    const auto it = _entries.constFind(cleanCode);
    if (it != _entries.constEnd()) {
        return it.value();
    }
    return _fallbackEntry(cleanCode);
}

QVariantList ErrorCatalog::activeErrorList(const QStringList& codes) const
{
    QVariantList list;
    for (const QString& code : codes) {
        const QString cleanCode = code.trimmed().toUpper();
        if (!cleanCode.isEmpty()) {
            list.append(_toVariantMap(entryForCode(cleanCode)));
        }
    }
    return list;
}

QString ErrorCatalog::firstScanBlockReason(const QStringList& codes) const
{
    for (const QString& code : codes) {
        const Entry entry = entryForCode(code);
        if (entry.blocksScan) {
            return entry.title;
        }
    }
    return QString();
}

QVariantMap ErrorCatalog::_toVariantMap(const Entry& entry)
{
    QVariantMap map;
    map.insert(QStringLiteral("code"), entry.code);
    map.insert(QStringLiteral("severity"), entry.severity);
    map.insert(QStringLiteral("title"), entry.title);
    map.insert(QStringLiteral("required_action"), entry.requiredAction);
    map.insert(QStringLiteral("blocks_flight"), entry.blocksFlight);
    map.insert(QStringLiteral("blocks_scan"), entry.blocksScan);
    map.insert(QStringLiteral("blocks_measure"), entry.blocksMeasure);
    map.insert(QStringLiteral("module"), entry.module);
    map.insert(QStringLiteral("uncatalogued"), entry.uncatalogued);
    return map;
}

ErrorCatalog::Entry ErrorCatalog::_fallbackEntry(const QString& code)
{
    Entry entry;
    entry.code = code.trimmed().isEmpty() ? QStringLiteral("UNKNOWN") : code.trimmed().toUpper();
    entry.severity = QStringLiteral("warning");
    entry.title = entry.code;
    entry.requiredAction = QStringLiteral("Uncatalogued error - report to engineering");
    entry.module = QStringLiteral("Unknown");
    entry.uncatalogued = true;
    return entry;
}
