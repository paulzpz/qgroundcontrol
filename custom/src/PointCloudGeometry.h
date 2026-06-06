/****************************************************************************
 *
 * (c) 2009-2024 QGROUNDCONTROL PROJECT <http://www.qgroundcontrol.org>
 *
 * QGroundControl is licensed according to the terms in the file
 * COPYING.md in the root of the source code directory.
 *
 * @brief Point Cloud Geometry for Qt Quick 3D rendering
 * @file PointCloudGeometry.h
 */

#pragma once

#include <QtQuick3D/QQuick3DGeometry>
#include <QtGui/QVector3D>
#include <QtCore/QObject>

class CustomPointCloudReceiver;

/**
 * @brief Color mode for point cloud rendering
 */
enum class PointCloudColorMode {
    Intensity = 0,  // Grayscale from CLPC intensity
    Height = 1      // Gradient by Z coordinate (blue->green->red)
};

/**
 * @brief Point cloud geometry for Qt Quick 3D
 */
class PointCloudGeometry : public QQuick3DGeometry
{
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(CustomPointCloudReceiver* receiver READ receiver WRITE setReceiver NOTIFY receiverChanged)
    Q_PROPERTY(int pointCount READ pointCount NOTIFY geometryChanged)
    Q_PROPERTY(int totalPointCount READ totalPointCount NOTIFY geometryChanged)
    Q_PROPERTY(int colorMode READ colorMode WRITE setColorMode NOTIFY colorModeChanged)
    Q_PROPERTY(float pointDiameter READ pointDiameter WRITE setPointDiameter NOTIFY pointDiameterChanged)
    Q_PROPERTY(bool sliceEnabled READ sliceEnabled WRITE setSliceEnabled NOTIFY sliceChanged)
    Q_PROPERTY(float sliceHeight READ sliceHeight WRITE setSliceHeight NOTIFY sliceChanged)
    Q_PROPERTY(float sliceThickness READ sliceThickness WRITE setSliceThickness NOTIFY sliceChanged)
    Q_PROPERTY(float sliceCenterOffset READ sliceCenterOffset WRITE setSliceCenterOffset NOTIFY sliceChanged)
    Q_PROPERTY(float sliceMinZ READ sliceMinZ NOTIFY sliceChanged)
    Q_PROPERTY(float sliceMaxZ READ sliceMaxZ NOTIFY sliceChanged)
    Q_PROPERTY(float minX READ minX NOTIFY boundsChanged)
    Q_PROPERTY(float maxX READ maxX NOTIFY boundsChanged)
    Q_PROPERTY(float minY READ minY NOTIFY boundsChanged)
    Q_PROPERTY(float maxY READ maxY NOTIFY boundsChanged)
    Q_PROPERTY(float minZ READ minZ NOTIFY boundsChanged)
    Q_PROPERTY(float maxZ READ maxZ NOTIFY boundsChanged)

public:
    explicit PointCloudGeometry(QQuick3DObject *parent = nullptr);
    ~PointCloudGeometry() override;

    CustomPointCloudReceiver* receiver() const { return _receiver; }
    void setReceiver(CustomPointCloudReceiver* receiver);

    int pointCount() const { return _pointCount; }
    int totalPointCount() const { return _totalPointCount; }

    int colorMode() const { return static_cast<int>(_colorMode); }
    void setColorMode(int mode);

    float pointDiameter() const { return _pointDiameter; }
    void setPointDiameter(float diameter);

    bool sliceEnabled() const { return _sliceEnabled; }
    void setSliceEnabled(bool enabled);

    float sliceHeight() const { return _sliceThickness; }
    void setSliceHeight(float height);

    float sliceThickness() const { return _sliceThickness; }
    void setSliceThickness(float thickness);

    float sliceCenterOffset() const { return _sliceCenterOffset; }
    void setSliceCenterOffset(float offset);

    float sliceMinZ() const { return _sliceCenterZ + _sliceCenterOffset - _sliceThickness * 0.5f; }
    float sliceMaxZ() const { return _sliceCenterZ + _sliceCenterOffset + _sliceThickness * 0.5f; }

    float minX() const { return _minX; }
    float maxX() const { return _maxX; }
    float minY() const { return _minY; }
    float maxY() const { return _maxY; }
    float minZ() const { return _minZ; }
    float maxZ() const { return _maxZ; }

    Q_INVOKABLE void generateTestPoints();

signals:
    void receiverChanged();
    void geometryChanged();
    void colorModeChanged();
    void pointDiameterChanged();
    void sliceChanged();
    void boundsChanged();

public slots:
    void updateFromReceiver();

private:
    void _updateBounds(const QVector3D& min, const QVector3D& max);
    void _applyColor(float* data, int idx, float x, float y, float z, uint8_t intensity);

    CustomPointCloudReceiver* _receiver = nullptr;
    int _pointCount = 0;
    int _totalPointCount = 0;
    PointCloudColorMode _colorMode = PointCloudColorMode::Height;
    float _pointDiameter = 0.02f;
    bool _sliceEnabled = false;
    float _sliceThickness = 1.0f;
    float _sliceCenterOffset = 0.0f;
    float _sliceCenterZ = 0.0f;

    // Bounds for height coloring (smoothed)
    float _minX = 0.0f;
    float _maxX = 0.0f;
    float _minY = 0.0f;
    float _maxY = 0.0f;
    float _minZ = 0.0f;
    float _maxZ = 10.0f;
    float _smoothMinZ = 0.0f;
    float _smoothMaxZ = 10.0f;
    bool _hasSmoothBounds = false;

    QByteArray _vertexBuffer;
};
