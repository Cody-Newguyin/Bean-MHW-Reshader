#include "ReShade.fxh"
#include "Bean_Common.fxh"

float4 PS_Invert(float4 position : SV_Position, float2 texcoord : TexCoord) : SV_Target
{
	float4 pixel = tex2D(Common::BeanBuffer, texcoord);
	float3 color = pixel.rgb;

	color = float3(1.0, 1.0, 1.0) - color;
	return float4(color, pixel.a);
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