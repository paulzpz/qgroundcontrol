/****************************************************************************
 *
 * (c) 2009-2024 QGROUNDCONTROL PROJECT <http://www.qgroundcontrol.org>
 *
 * QGroundControl is licensed according to the terms in the file
 * COPYING.md in the root of the source code directory.
 *
 * @brief Metric line grid geometry for the custom point cloud view
 * @file PointCloudGridGeometry.h
 */

#pragma once

#include <QtQuick3D/QQuick3DGeometry>

class PointCloudGridGeometry : public QQuick3DGeometry
{
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(float size READ size WRITE setSize NOTIFY gridChanged)
    Q_PROPERTY(float cellSize READ cellSize WRITE setCellSize NOTIFY gridChanged)

public:
    explicit PointCloudGridGeometry(QQuick3DObject *parent = nullptr);
    ~PointCloudGridGeometry() override = default;

    float size() const { return _size; }
    void setSize(float size);

    float cellSize() const { return _cellSize; }
    void setCellSize(float cellSize);

signals:
    void gridChanged();

private:
    void _rebuild();

    float _size = 20.0f;
    float _cellSize = 1.0f;
    QByteArray _vertexBuffer;
};
