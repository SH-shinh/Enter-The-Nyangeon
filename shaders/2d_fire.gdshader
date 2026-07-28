shader_type canvas_item;

uniform sampler2D Base_Texture : filter_nearest;
uniform sampler2D Noise_Texture : filter_nearest;
uniform float Noise_Power = 1.0;
uniform vec2 Noise_Scroll = vec2(1.0);

uniform sampler2D Modulate_Out_Line : filter_nearest, source_color;
uniform float Wave_Amp = 0.05;
uniform vec2 Scale = vec2(1.0);
uniform float Wave_Freq = 10.0;
uniform float Wave_Speed = 2.0;
uniform float Sin_Start_Offset = 0.0;

vec2 Scroll_UV(vec2 Uv, vec2 Speed) {
    return fract(Uv + TIME * Speed);
}

void fragment() {
    vec2 UV_Coord = UV;
    UV_Coord = (UV_Coord - 0.5) * Scale + 0.5;

    vec4 Noise_Val = texture(Noise_Texture, Scroll_UV(UV_Coord, Noise_Scroll));
    float Noise_Offset = (Noise_Val.r * 2.0 - 1.0) * Wave_Amp;

    UV_Coord.x += (sin(Sin_Start_Offset + (UV_Coord.y * Wave_Freq + TIME * Wave_Speed)) + Noise_Offset * Noise_Power) * Wave_Amp * (1.0 - UV_Coord.y);

    vec4 Final_Color = texture(Base_Texture, UV_Coord);

    float Alpha_Value = Final_Color.a;

    vec4 Out_Line_Tex = texture(Modulate_Out_Line, vec2(Alpha_Value, Alpha_Value));
    Out_Line_Tex.a = Alpha_Value * Out_Line_Tex.a;

    if (Final_Color.a > 0.1) {
        COLOR = Out_Line_Tex;
    } else {
        discard;
    }
}
