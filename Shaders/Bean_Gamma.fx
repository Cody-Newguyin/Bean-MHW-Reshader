#include "ReShade.fxh"
#include "Bean_Common.fxh"

uniform float _Gamma <
    ui_min = 0.0f; ui_max = 5.0f;
    ui_label = "Gamma";
    ui_type = "drag";
> = 2.2f;

float4 PS_Gamma(float4 position : SV_Position, float2 texcoord : TexCoord) : SV_Target
{
	float4 pixel = saturate(tex2D(Common::BeanBuffer, texcoord));
	float3 color = pixel.rgb;

	color = saturate(pow(abs(color), _Gamma));
	return float4(color, pixel.a);
}

technique Bean_Gamma
{
	pass
	{
		RenderTarget = Common::BeanBufferTexTemp;
		VertexShader = PostProcessVS;
		PixelShader = PS_Gamma;
	}
	pass
	{
		RenderTarget = Common::BeanBufferTex;
		VertexShader = PostProcessVS;
		PixelShader = Common::PS_EndPass;
	}
}