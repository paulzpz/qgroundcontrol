/****************************************************************************
 *
 * (c) 2009-2024 QGROUNDCONTROL PROJECT <http://www.qgroundcontrol.org>
 *
 * QGroundControl is licensed according to the terms in the file
 * COPYING.md in the root of the source code directory.
 *
 * @brief Metric line grid geometry for the custom point cloud view
 * @file PointCloudGridGeometry.cc
 */

#include "PointCloudGridGeometry.h"

#include <QtGui/QVector3D>
#include <algorithm>
#include <cmath>

namespace {
constexpr int GRID_VERTEX_STRIDE = 7 * sizeof(float);
}

PointCloudGridGeometry::PointCloudGridGeometry(QQuick3DObject *parent)
    : QQuick3DGeometry(parent)
{
    addAttribute(QQuick3DGeometry::Attribute::PositionSemantic,
                 0,
                 QQuick3DGeometry::Attribute::F32Type);

    addAttribute(QQuick3DGeometry::Attribute::ColorSemantic,
                 3 * sizeof(float),
                 QQuick3DGeometry::Attribute::F32Type);

    setPrimitiveType(QQuick3DGeometry::PrimitiveType::Lines);
    setStride(GRID_VERTEX_STRIDE);
    _rebuild();
}

void PointCloudGridGeometry::setSize(float size)
{
    const float newSize = std::max(0.0f, size);
    if (std::abs(_size - newSize) < 0.0001f) {
        return;
    }

    _size = newSize;
    _rebuild();
    emit gridChanged();
}

void PointCloudGridGeometry::setCellSize(float cellSize)
{
    const float newCellSize = std::max(0.0f, cellSize);
    if (std::abs(_cellSize - newCellSize) < 0.0001f) {
        return;
    }

    _cellSize = newCellSize;
    _rebuild();
    emit gridChanged();
}

void PointCloudGridGeometry::_rebuild()
{
    if (_size <= 0.0f || _cellSize <= 0.0f) {
        _vertexBuffer.clear();
        setVertexData(_vertexBuffer);
        setBounds(QVector3D(0.0f, 0.0f, 0.0f), QVector3D(0.0f, 0.0f, 0.0f));
        update();
        return;
    }

    const int cells = std::max(1, static_cast<int>(std::round(_size / _cellSize)));
    const int lineCount = (cells + 1) * 2;
    const int vertexCount = lineCount * 2;
    const float halfSize = _size * 0.5f;

    _vertexBuffer.resize(vertexCount * GRID_VERTEX_STRIDE);
    float* data = reinterpret_cast<float*>(_vertexBuffer.data());

    int idx = 0;
    auto addVertex = [&](float x, float y, float z, bool centerLine) {
        data[idx * 7 + 0] = x;
        data[idx * 7 + 1] = y;
        data[idx * 7 + 2] = z;
        const float color = centerLine ? 0.55f : 0.30f;
        data[idx * 7 + 3] = color;
        data[idx * 7 + 4] = color;
        data[idx * 7 + 5] = color;
        data[idx * 7 + 6] = 1.0f;
        ++idx;
    };

    for (int i = 0; i <= cells; ++i) {
        const float coord = -halfSize + i * _cellSize;
        const bool centerLine = std::abs(coord) < _cellSize * 0.5f;

        addVertex(-halfSize, coord, 0.0f, centerLine);
        addVertex(halfSize, coord, 0.0f, centerLine);

        addVertex(coord, -halfSize, 0.0f, centerLine);
        addVertex(coord, halfSize, 0.0f, centerLine);
    }

    setVertexData(_vertexBuffer);
    setBounds(QVector3D(-halfSize, -halfSize, 0.0f), QVector3D(halfSize, halfSize, 0.0f));
    update();
}
