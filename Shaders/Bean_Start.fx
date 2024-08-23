#include "ReShade.fxh"
#include "Bean_Common.fxh"

float4 PS_Start(float4 position : SV_Position, float2 texcoord : TexCoord) : SV_Target
{
	float4 pixel = tex2D(ReShade::BackBuffer, texcoord);
	return pixel;
}

// Start by sampling backbuffer to custom HDR texture buffer
technique Bean_Start <ui_tooltip = "(REQUIRED) Put before all Bean shaders";>
{
	pass
	{
		RenderTarget = Common::BeanBufferTex;
		VertexShader = PostProcessVS;
		PixelShader = PS_Start;
	}
}