/****************************************************************************
 *
 * Innovatech CLST error catalog helper.
 *
 ****************************************************************************/

#pragma once

#include <QtCore/QHash>
#include <QtCore/QString>
#include <QtCore/QStringList>
#include <QtCore/QVariantList>
#include <QtCore/QVariantMap>

class ErrorCatalog
{
public:
    struct Entry {
        QString code;
        QString severity = QStringLiteral("warning");
        QString title;
        QString requiredAction;
        bool blocksFlight = false;
        bool blocksScan = false;
        bool blocksMeasure = false;
        QString module;
        bool uncatalogued = false;
    };

    explicit ErrorCatalog();

    bool load(const QString& path = QStringLiteral(":/Custom/data/error_catalog.json"));
    Entry entryForCode(const QString& code) const;
    QVariantList activeErrorList(const QStringList& codes) const;
    QString firstScanBlockReason(const QStringList& codes) const;

private:
    static QVariantMap _toVariantMap(const Entry& entry);
    static Entry _fallbackEntry(const QString& code);

    QHash<QString, Entry> _entries;
};
