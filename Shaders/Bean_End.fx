#include "ReShade.fxh"
#include "Bean_Common.fxh"

float3 PS_End(float4 position : SV_Position, float2 texcoord : TexCoord) : SV_Target
{
	float3 color = tex2D(Common::BeanBuffer, texcoord).rgb;
	return color;
}

// End by sampling custom HDR texture buffer to backbuffer
technique Bean_End
{
	pass
	{
		VertexShader = PostProcessVS;
		PixelShader = PS_End;
	}
}