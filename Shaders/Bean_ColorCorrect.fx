#include "ReShade.fxh"
#include "Bean_Common.fxh"

uniform float _Exposure <
    ui_min = 0.0f; ui_max = 10.0f;
    ui_label = "Exposure";
    ui_type = "drag";
> = 1.0f;

uniform float _Temperature <
    ui_min = -1.0f; ui_max = 1.0f;
    ui_label = "Temperature";
    ui_type = "drag";
    ui_tooltip = "Shifts values towards yellow or blue";
> = 0.0f;

uniform float _Tint <
    ui_min = -1.0f; ui_max = 1.0f;
    ui_label = "Tint";
    ui_type = "drag";
    ui_tooltip = "Shifts values towards pink or green";
> = 0.0f;

uniform float3 _Contrast <
    ui_min = 0.0f; ui_max = 5.0f;
    ui_label = "Contrast";
    ui_type = "drag";
> = 1.0f;

uniform float3 _Brightness <
    ui_min = 0.0f; ui_max = 1.0f;
    ui_label = "Brightness";
    ui_type = "drag";
> = 0.0f;

uniform float3 _Saturation < 
    ui_min = 0.0f; ui_max = 5.0f;
    ui_label = "Saturation";
    ui_type = "drag";
> = 1.0f;

float3 PS_ColorCorrect(float4 position : SV_Position, float2 texcoord : TexCoord) : SV_Target
{
	float3 color = tex2D(ReShade::BackBuffer, texcoord).rgb;

    color = color * _Exposure;

    color = Common::WhiteBalance(color, _Temperature, _Tint);
    color = max(0.0f, color);

    color = _Contrast * (color - 0.5f) + 0.5f + _Brightness;
    color = max(0.0f, color);

    color = lerp(Common::Luminance(color), color, _Saturation);
	return color;
}

technique Bean_ColorCorrect
{
	pass
	{
		VertexShader = PostProcessVS;
		PixelShader = PS_ColorCorrect;
	}
}