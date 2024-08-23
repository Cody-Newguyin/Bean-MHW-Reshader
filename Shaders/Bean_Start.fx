#include "ReShade.fxh"
#include "Bean_Common.fxh"

float3 PS_Start(float4 position : SV_Position, float2 texcoord : TexCoord) : SV_Target
{
	float3 color = tex2D(ReShade::BackBuffer, texcoord).rgb;
	return color;
}

// Start by sampling backbuffer to custom HDR texture buffer
technique Bean_Start
{
	pass
	{
		RenderTarget = Common::BeanBufferTex;
		VertexShader = PostProcessVS;
		PixelShader = PS_Start;
	}
}