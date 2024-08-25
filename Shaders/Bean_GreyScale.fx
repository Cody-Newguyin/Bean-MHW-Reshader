#include "ReShade.fxh"
#include "Bean_Common.fxh"

uniform int _GreyScaleMode < 
    ui_type = "combo";
    ui_label = "Mode";
    ui_items = "Photometric\0"
                "Digital\0";
> = 0;

float4 PS_GreyScale(float4 position : SV_Position, float2 texcoord : TexCoord) : SV_Target
{
	float4 pixel = tex2D(Common::BeanBuffer, texcoord);
	float3 color = pixel.rgb;

    float luminance = 0.0f;
    if (_GreyScaleMode == 0) {
        luminance = Common::Luminance(color);
    } else {
        luminance = Common::LuminanceAlt(color);
    }

    color = float3(luminance, luminance, luminance);
	return float4(color, pixel.a);
}

technique Bean_GreyScale
{
	pass
	{
		RenderTarget = Common::BeanBufferTexTemp;
		VertexShader = PostProcessVS;
		PixelShader = PS_GreyScale;
	}
	pass
	{
		RenderTarget = Common::BeanBufferTex;
		VertexShader = PostProcessVS;
		PixelShader = Common::PS_EndPass;
	}
}