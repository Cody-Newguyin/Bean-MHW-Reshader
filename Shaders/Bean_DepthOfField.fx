#include "ReShade.fxh"
#include "Bean_Common.fxh"

uniform float _FocalPlaneDistance <
    ui_min = 0.0f; ui_max = 1000.0f;
    ui_label = "Focal Plane";
    ui_type = "slider";
> = 40.0f;

uniform float _FocusRange <
    ui_min = 0.0f; ui_max = 1000.0f;
    ui_label = "Focus Range";
    ui_type = "slider";
> = 20.0f;

texture2D CoCTex { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RG8; };
sampler2D CoC { Texture = CoCTex; MagFilter = POINT; MinFilter = POINT; MipFilter = POINT;};


float2 PS_CoC(float4 position : SV_Position, float2 texcoord : TexCoord) : SV_Target
{
	float depth = ReShade::GetLinearizedDepth(texcoord) * 1000.0f;

	float nearStart = max(0.0f, _FocalPlaneDistance - _FocusRange);
    float nearEnd = _FocalPlaneDistance;
    float farStart = _FocalPlaneDistance;
    float farEnd = _FocalPlaneDistance + _FocusRange;

	float near = 0.0f;
	if (near < nearEnd) 
		near = 1.0f - (depth - nearStart) / (nearEnd - nearStart);
	float far = 0.0f;
   	if (depth > farStart)
        far = (depth - farStart) / (farEnd - farStart);

	return saturate(float2(near, far));
}

technique Bean_DepthOfField
{
	pass
	{
		RenderTarget0 = CoCTex;
		VertexShader = PostProcessVS;
		PixelShader = PS_CoC;
	}
	// pass
	// {
	// 	RenderTarget = Common::BeanBufferTex;
	// 	VertexShader = PostProcessVS;
	// 	PixelShader = Common::PS_EndPass;
	// }
}