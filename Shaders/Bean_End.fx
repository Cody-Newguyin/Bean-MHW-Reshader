#include "ReShade.fxh"
#include "Bean_Common.fxh"

float4 PS_End(float4 position : SV_Position, float2 texcoord : TexCoord) : SV_Target
{
	float4 pixel = tex2D(Common::BeanBuffer, texcoord);
	return pixel;
}

// End by sampling custom HDR texture buffer to backbuffer
technique Bean_End <ui_tooltip = "(REQUIRED) Put after all Bean shaders";>
{
	pass
	{
		VertexShader = PostProcessVS;
		PixelShader = PS_End;
	}
}