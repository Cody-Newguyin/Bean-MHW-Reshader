#include "ReShade.fxh"
#include "Bean_Common.fxh"

float3 PS_Invert(float4 position : SV_Position, float2 texcoord : TexCoord) : SV_Target
{
	float3 color = float3(1.0, 1.0, 1.0) - tex2D(Common::BeanBuffer, texcoord).rgb;
	return color;
}

technique Bean_Invert
{
	pass
	{
		RenderTarget = Common::BeanBufferTexTemp;
		VertexShader = PostProcessVS;
		PixelShader = PS_Invert;
	}
	pass
	{
		RenderTarget = Common::BeanBufferTex;
		VertexShader = PostProcessVS;
		PixelShader = Common::PS_EndPass;
	}
}