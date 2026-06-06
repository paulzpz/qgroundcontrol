// Point Cloud vertex shader - Qt Quick 3D CustomMaterial
VARYING vec4 vColor;

void MAIN()
{
    vColor = COLOR;
    POINT_SIZE = pointSize;
}
