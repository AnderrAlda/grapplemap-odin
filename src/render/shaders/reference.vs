#version 330

// Reference path (ADR 0006 d3): the original's fixed-function lighting (docs/original.md §7.3) per vertex.
// Two directional lights in world space (the model matrix is the identity, so no normal matrix), GL_COLOR_MATERIAL
// ambient and diffuse, no specular; the constants come from render/constants.odin as uniforms.

in vec3 vertexPosition;
in vec3 vertexNormal;
in vec3 vertexColor;

uniform mat4 mvp;
uniform vec3 lightDir0;
uniform vec3 lightDir1;
uniform float lightDiffuse;
uniform float lightAmbient; // global ambient + both lights' ambient

out vec3 fragColor;

void main()
{
    float lit = lightAmbient + lightDiffuse * (max(0.0, dot(vertexNormal, lightDir0)) +
                                               max(0.0, dot(vertexNormal, lightDir1)));
    fragColor = clamp(vertexColor * lit, 0.0, 1.0);
    gl_Position = mvp * vec4(vertexPosition, 1.0);
}
