#include "ReShade.fxh"
#include "Bean_Common.fxh"

uniform float _Intensity <
    ui_min = 0f; ui_max = 5.0f;
    ui_label = "Intensity";
    ui_type = "slider";
> = 1.0f;

uniform float _Smoothness <
    ui_min = 0.01f; ui_max = 10.0f;
    ui_label = "Smoothness";
    ui_type = "slider";
> = 1.0f;

uniform float3 _Offsets <
    ui_min = -1.0f; ui_max = 1.0f;
    ui_label = "Offsets for RGB channels";
    ui_type = "drag";
> = float3(0.0f, 0.1f, 0.0f);

float4 PS_ChromaticAbberation(float4 position : SV_Position, float2 texcoord : TexCoord) : SV_Target
{
	float4 pixel = tex2D(Common::BeanBuffer, texcoord);
	float3 color = pixel.rgb;

	float2 direction = texcoord - float2(0.5f, 0.5f);
	float factor = saturate(pow(length(direction), _Smoothness)) * _Intensity;

	color.r = tex2D(Common::BeanBuffer, texcoord + direction * _Offsets.r * factor).r;
	color.g = tex2D(Common::BeanBuffer, texcoord + direction * _Offsets.g * factor).g;
	color.b = tex2D(Common::BeanBuffer, texcoord + direction * _Offsets.b * factor).b;

	return float4(color, pixel.a);
}

technique Bean_ChromaticAbberation
{
	pass
	{
		RenderTarget = Common::BeanBufferTexTemp;
		VertexShader = PostProcessVS;
		PixelShader = PS_ChromaticAbberation;
	}
	pass
	{
		RenderTarget = Common::BeanBufferTex;
		VertexShader = PostProcessVS;
		PixelShader = Common::PS_EndPass;
	}
}