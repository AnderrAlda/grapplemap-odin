#version 330

// Gouraud: the per-vertex colour of reference.vs, interpolated.

in vec3 fragColor;

out vec4 finalColor;

void main()
{
    finalColor = vec4(fragColor, 1.0);
}
