/****************************************************************************
 *
 * (c) 2009-2024 QGROUNDCONTROL PROJECT <http://www.qgroundcontrol.org>
 *
 * QGroundControl is licensed according to the terms in the file
 * COPYING.md in the root of the source code directory.
 *
 * @brief Point Cloud Geometry implementation
 * @file PointCloudGeometry.cc
 */

#include "PointCloudGeometry.h"
#include "CustomPointCloudReceiver.h"
#include "QGCLoggingCategory.h"

#include <cmath>
#include <cstring>
#include <algorithm>
QGC_LOGGING_CATEGORY(PointCloudGeometryLog, "gcs.custom.pointcloudgeometry")

// Vertex stride: position (3 floats) + color (4 floats) = 28 bytes
constexpr int VERTEX_STRIDE = 7 * sizeof(float);

// EWMA smoothing factor for Z bounds (prevents flickering)
constexpr float BOUNDS_SMOOTH = 0.2f;
constexpr float SLICE_MIN_THICKNESS = 0.1f;
constexpr float SLICE_MAX_THICKNESS = 5.0f;
constexpr float SLICE_MIN_OFFSET = -5.0f;
constexpr float SLICE_MAX_OFFSET = 5.0f;

PointCloudGeometry::PointCloudGeometry(QQuick3DObject *parent)
    : QQuick3DGeometry(parent)
{
    addAttribute(QQuick3DGeometry::Attribute::PositionSemantic,
                 0,
                 QQuick3DGeometry::Attribute::F32Type);

    addAttribute(QQuick3DGeometry::Attribute::ColorSemantic,
                 3 * sizeof(float),
                 QQuick3DGeometry::Attribute::F32Type);

    setPrimitiveType(QQuick3DGeometry::PrimitiveType::Points);
    setStride(VERTEX_STRIDE);

    qCDebug(PointCloudGeometryLog) << "PointCloudGeometry created";
}

PointCloudGeometry::~PointCloudGeometry()
{
    qCDebug(PointCloudGeometryLog) << "PointCloudGeometry destroyed";
}

void PointCloudGeometry::setReceiver(CustomPointCloudReceiver* receiver)
{
    if (_receiver == receiver) return;

    if (_receiver) {
        disconnect(_receiver, &CustomPointCloudReceiver::frameReceived,
                   this, &PointCloudGeometry::updateFromReceiver);
    }

    _receiver = receiver;

    if (_receiver) {
        connect(_receiver, &CustomPointCloudReceiver::frameReceived,
                this, &PointCloudGeometry::updateFromReceiver);
        updateFromReceiver();
    }

    emit receiverChanged();
}

void PointCloudGeometry::setColorMode(int mode)
{
    auto newMode = static_cast<PointCloudColorMode>(mode);
    if (_colorMode == newMode) return;

    _colorMode = newMode;
    emit colorModeChanged();

    // Rebuild with new colors
    if (_receiver) {
        updateFromReceiver();
    }
}

void PointCloudGeometry::setPointDiameter(float diameter)
{
    const float newDiameter = std::max(0.001f, diameter);
    if (std::abs(_pointDiameter - newDiameter) < 0.0001f) return;

    _pointDiameter = newDiameter;
    emit pointDiameterChanged();
}

void PointCloudGeometry::setSliceEnabled(bool enabled)
{
    if (_sliceEnabled == enabled) return;

    _sliceEnabled = enabled;
    if (_receiver) {
        _sliceCenterZ = _receiver->dronePose().z();
        updateFromReceiver();
    }
    emit sliceChanged();
}

void PointCloudGeometry::setSliceHeight(float height)
{
    setSliceThickness(height);
}

void PointCloudGeometry::setSliceThickness(float thickness)
{
    const float newThickness = std::clamp(thickness, SLICE_MIN_THICKNESS, SLICE_MAX_THICKNESS);
    if (std::abs(_sliceThickness - newThickness) < 0.0001f) return;

    _sliceThickness = newThickness;
    if (_receiver) {
        updateFromReceiver();
    }
    emit sliceChanged();
}

void PointCloudGeometry::setSliceCenterOffset(float offset)
{
    const float newOffset = std::clamp(offset, SLICE_MIN_OFFSET, SLICE_MAX_OFFSET);
    if (std::abs(_sliceCenterOffset - newOffset) < 0.0001f) return;

    _sliceCenterOffset = newOffset;
    if (_receiver) {
        updateFromReceiver();
    }
    emit sliceChanged();
}

void PointCloudGeometry::_applyColor(float* data, int idx, float x, float y, float z, uint8_t intensity)
{
    Q_UNUSED(x)
    Q_UNUSED(y)

    float r, g, b;

    if (_colorMode == PointCloudColorMode::Height) {
        // Height-based coloring: blue (low) -> green (mid) -> red (high)
        float range = _smoothMaxZ - _smoothMinZ;
        if (range < 0.1f) range = 0.1f;
        float t = std::clamp((z - _smoothMinZ) / range, 0.0f, 1.0f);

        if (t < 0.5f) {
            const float s = t * 2.0f;
            r = 0.0f;
            g = s;
            b = 1.0f - s;
        } else {
            const float s = (t - 0.5f) * 2.0f;
            r = s;
            g = 1.0f - s;
            b = 0.0f;
        }
    } else {
        // Intensity mode: bright grayscale
        float intens = static_cast<float>(intensity) / 255.0f;
        // Boost brightness: map 0-1 to 0.3-1.0
        intens = 0.3f + 0.7f * intens;
        r = g = b = intens;
    }

    data[idx * 7 + 3] = r;
    data[idx * 7 + 4] = g;
    data[idx * 7 + 5] = b;
    data[idx * 7 + 6] = 1.0f;
}

void PointCloudGeometry::generateTestPoints()
{
    qCInfo(PointCloudGeometryLog) << "Generating metric test points";

    const int gridSize = 20;
    const float spacing = 0.05f;
    const float wallDistance = 0.25f;

    _pointCount = gridSize * gridSize;
    _totalPointCount = _pointCount;
    _vertexBuffer.resize(_pointCount * VERTEX_STRIDE);

    float* data = reinterpret_cast<float*>(_vertexBuffer.data());

    QVector3D minBounds(1e6f, 1e6f, 1e6f);
    QVector3D maxBounds(-1e6f, -1e6f, -1e6f);

    _minZ = 0.0f;
    _maxZ = gridSize * spacing;
    _smoothMinZ = _minZ;
    _smoothMaxZ = _maxZ;
    _hasSmoothBounds = true;

    int idx = 0;
    for (int iy = 0; iy < gridSize; ++iy) {
        for (int iz = 0; iz < gridSize; ++iz) {
            float x = wallDistance;
            float y = (iy - gridSize / 2) * spacing;
            float z = iz * spacing;

            data[idx * 7 + 0] = x;
            data[idx * 7 + 1] = y;
            data[idx * 7 + 2] = z;

            uint8_t intensity = static_cast<uint8_t>(255.0f * iz / gridSize);
            _applyColor(data, idx, x, y, z, intensity);

            minBounds.setX(qMin(minBounds.x(), x));
            minBounds.setY(qMin(minBounds.y(), y));
            minBounds.setZ(qMin(minBounds.z(), z));
            maxBounds.setX(qMax(maxBounds.x(), x));
            maxBounds.setY(qMax(maxBounds.y(), y));
            maxBounds.setZ(qMax(maxBounds.z(), z));

            ++idx;
        }
    }

    _minX = minBounds.x();
    _maxX = maxBounds.x();
    _minY = minBounds.y();
    _maxY = maxBounds.y();

    setVertexData(_vertexBuffer);
    _updateBounds(minBounds, maxBounds);
    update();

    emit geometryChanged();
    emit boundsChanged();
    emit sliceChanged();
}

void PointCloudGeometry::updateFromReceiver()
{
    if (!_receiver) return;

    const auto& points = _receiver->points();
    _totalPointCount = points.size();
    _sliceCenterZ = _receiver->dronePose().z();

    if (points.isEmpty()) {
        _pointCount = 0;
        _vertexBuffer.clear();
        setVertexData(_vertexBuffer);
        setBounds(QVector3D(0.0f, 0.0f, 0.0f), QVector3D(0.0f, 0.0f, 0.0f));
        update();
        emit geometryChanged();
        emit boundsChanged();
        emit sliceChanged();
        return;
    }

    QVector3D frameMin(1e6f, 1e6f, 1e6f);
    QVector3D frameMax(-1e6f, -1e6f, -1e6f);

    for (const CLPCPoint& pt : points) {
        frameMin.setX(qMin(frameMin.x(), pt.x));
        frameMin.setY(qMin(frameMin.y(), pt.y));
        frameMin.setZ(qMin(frameMin.z(), pt.z));
        frameMax.setX(qMax(frameMax.x(), pt.x));
        frameMax.setY(qMax(frameMax.y(), pt.y));
        frameMax.setZ(qMax(frameMax.z(), pt.z));
    }

    _minX = frameMin.x();
    _maxX = frameMax.x();
    _minY = frameMin.y();
    _maxY = frameMax.y();
    _minZ = frameMin.z();
    _maxZ = frameMax.z();

    if (!_hasSmoothBounds) {
        _smoothMinZ = _minZ;
        _smoothMaxZ = _maxZ;
        _hasSmoothBounds = true;
    } else {
        _smoothMinZ = _smoothMinZ * (1.0f - BOUNDS_SMOOTH) + _minZ * BOUNDS_SMOOTH;
        _smoothMaxZ = _smoothMaxZ * (1.0f - BOUNDS_SMOOTH) + _maxZ * BOUNDS_SMOOTH;
    }

    _vertexBuffer.resize(_totalPointCount * VERTEX_STRIDE);
    float* data = reinterpret_cast<float*>(_vertexBuffer.data());

    QVector3D renderMin(1e6f, 1e6f, 1e6f);
    QVector3D renderMax(-1e6f, -1e6f, -1e6f);
    const float sliceMin = sliceMinZ();
    const float sliceMax = sliceMaxZ();

    int visibleCount = 0;
    for (const CLPCPoint& pt : points) {
        if (_sliceEnabled && (pt.z < sliceMin || pt.z > sliceMax)) {
            continue;
        }

        data[visibleCount * 7 + 0] = pt.x;
        data[visibleCount * 7 + 1] = pt.y;
        data[visibleCount * 7 + 2] = pt.z;

        _applyColor(data, visibleCount, pt.x, pt.y, pt.z, pt.intensity);

        renderMin.setX(qMin(renderMin.x(), pt.x));
        renderMin.setY(qMin(renderMin.y(), pt.y));
        renderMin.setZ(qMin(renderMin.z(), pt.z));
        renderMax.setX(qMax(renderMax.x(), pt.x));
        renderMax.setY(qMax(renderMax.y(), pt.y));
        renderMax.setZ(qMax(renderMax.z(), pt.z));

        ++visibleCount;
    }

    _pointCount = visibleCount;
    _vertexBuffer.resize(_pointCount * VERTEX_STRIDE);

    setVertexData(_vertexBuffer);
    if (_pointCount > 0) {
        _updateBounds(renderMin, renderMax);
    } else {
        _updateBounds(frameMin, frameMax);
    }
    update();

    emit geometryChanged();
    emit boundsChanged();
    emit sliceChanged();
}

void PointCloudGeometry::_updateBounds(const QVector3D& min, const QVector3D& max)
{
    const float radius = std::max(_pointDiameter * 0.5f, 0.001f);
    QVector3D padding(radius, radius, radius);
    setBounds(min - padding, max + padding);
}
