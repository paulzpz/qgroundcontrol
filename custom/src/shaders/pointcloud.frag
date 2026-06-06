// Point Cloud fragment shader - Qt Quick 3D CustomMaterial
VARYING vec4 vColor;

void MAIN()
{
    // Use vertex color, ensure it's bright (grayscale from intensity)
    vec3 col = vColor.rgb;
    // If color is too dark, brighten it
    float brightness = max(col.r, max(col.g, col.b));
    if (brightness < 0.1) {
        col = vec3(0.8, 0.8, 0.8);  // Default to light gray
    }
    BASE_COLOR = vec4(col, 1.0);
}
