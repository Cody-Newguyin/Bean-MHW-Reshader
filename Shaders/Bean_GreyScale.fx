#include "ReShade.fxh"
#include "Bean_Common.fxh"

uniform int _GreyScaleMode < 
    ui_type = "combo";
    ui_label = "Mode";
    ui_items = "Photometric\0"
                "Digital\0";
> = 0;

float3 PS_GreyScale(float4 position : SV_Position, float2 texcoord : TexCoord) : SV_Target
{
	float3 color = tex2D(ReShade::BackBuffer, texcoord).rgb;

    float luminance = 0.0f;
    if (_GreyScaleMode == 0) {
        luminance = Common::Luminance(color);
    } else {
        luminance = Common::LuminanceAlt(color);
    }

    color = float3(luminance, luminance, luminance);
	return color;
}

technique Bean_GreyScale
{
	pass
	{
		VertexShader = PostProcessVS;
		PixelShader = PS_GreyScale;
	}
}