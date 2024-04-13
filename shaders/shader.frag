#version 330 core
out vec4 FragColor;

in vec3 oColor;
in vec2 texCoord;

uniform sampler2D tex;

void main()
{
    FragColor = texture(tex, texCoord) * vec4(oColor, 1.0);
}