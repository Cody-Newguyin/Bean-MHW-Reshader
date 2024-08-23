#include "ReShade.fxh"
#include "ReShadeUI.fxh"

float3 PS_Invert(float4 position : SV_Position, float2 texcoord : TexCoord) : SV_Target
{
	float3 color = float3(1.0, 1.0, 1.0) - tex2D(ReShade::BackBuffer, texcoord).rgb;
	return color;
}

technique Bean_Invert
{
	pass
	{
		VertexShader = PostProcessVS;
		PixelShader = PS_Invert;
	}
}