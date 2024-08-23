#include "ReShade.fxh"
#include "Bean_Common.fxh"

uniform bool _DebugHDR <
    ui_category_closed = true;
    ui_category = "Advanced settings";
    ui_label = "Debug HDR";
    ui_tooltip = "Show values in hdr (> 1)";
> = false;

float3 NarkowiczACES(float3 col) {
    return saturate((col * (2.51f * col + 0.03f)) / (col * (2.43f * col + 0.59f) + 0.14f));
}

float4 PS_Tonemap(float4 position : SV_Position, float2 texcoord : TexCoord) : SV_Target
{
	float4 pixel = tex2D(Common::BeanBuffer, texcoord);
	float3 color = pixel.rgb;

    if (_DebugHDR) {
        if (color.r > 1.0f || color.g > 1.0f || color.b > 1.0f) {
            return float4(color, pixel.a);
        }
        return 0.0f;
    }

    color = NarkowiczACES(color);
    return float4(color, pixel.a);
}

technique Bean_Tonemap
{
	pass
	{
		RenderTarget = Common::BeanBufferTexTemp;
		VertexShader = PostProcessVS;
		PixelShader = PS_Tonemap;
	}
	pass
	{
		RenderTarget = Common::BeanBufferTex;
		VertexShader = PostProcessVS;
		PixelShader = Common::PS_EndPass;
	}
}