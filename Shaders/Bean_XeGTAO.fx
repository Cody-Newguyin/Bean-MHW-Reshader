#include "ReShade.fxh"
#include "Bean_Common.fxh"
#include "Bean_XeGTAO.fxh"

uniform float _EffectRadius <
    ui_category = "SSAO Settings";
    ui_category_closed = true;
    ui_min = 0.01f; ui_max = 100.0f;
    ui_label = "Effect Radius";
    ui_type = "drag";
    ui_tooltip = "Modify radius of sampling.";
> = 0.5f;

uniform float _RadiusMultiplier <
    ui_category = "SSAO Settings";
    ui_category_closed = true;
    ui_min = 0.01f; ui_max = 5.0f;
    ui_label = "Radius Multiplier";
    ui_type = "drag";
    ui_tooltip = "Modify sampling radius multiplier.";
> = 1.457f;

uniform float _EffectFalloffRange <
    ui_category = "SSAO Settings";
    ui_category_closed = true;
    ui_min = 0.01f; ui_max = 5.0f;
    ui_label = "Falloff Range";
    ui_type = "drag";
    ui_tooltip = "Distant samples contribute less.";
> = 0.615f;

uniform float _SampleDistributionPower <
    ui_category = "SSAO Settings";
    ui_category_closed = true;
    ui_min = 0.01f; ui_max = 10.0f;
    ui_label = "Sample Distribution Power";
    ui_type = "drag";
    ui_tooltip = "Small crevices more important that big surfaces."; 
> = 2.0f;

uniform float _ThinOccluderCompensation <
    ui_category = "SSAO Settings";
    ui_category_closed = true;
    ui_min = 0.0f; ui_max = 10.0f;
    ui_label = "Thin Occluder Compensation";
    ui_tooltip = "Adjust how much the samples account for thin objects.";
    ui_type = "drag";
> = 0.0f;

uniform float _SlopeCompensation <
    ui_category = "SSAO Settings";
    ui_category_closed = true;
    ui_min = 0.0f; ui_max = 1.0f;
    ui_label = "Slope Compensation";
    ui_tooltip = "Slopes get darkened for some reason sometimes so this compensates if it's bad.";
    ui_type = "drag";
> = 0.05f;

uniform float _FinalValuePower <
    ui_category = "SSAO Settings";
    ui_category_closed = true;
    ui_min = 0.01f; ui_max = 5.0f;
    ui_label = "Final Value Power";
    ui_type = "drag";
    ui_tooltip = "Modify the final ambient occlusion value exponent.";
> = 2.2f;

uniform float _SigmaD <
    ui_category = "Blur Settings";
    ui_category_closed = true;
    ui_min = 0.01f; ui_max = 10.0f;
    ui_label = "SigmaD";
    ui_type = "drag";
    ui_tooltip = "Modify the distance of bilateral filter samples (if you set this too high it will crash the game probably so I have taken that power away from you).";
> = 1.0f;

uniform float _SigmaR <
    ui_category = "Blur Settings";
    ui_category_closed = true;
    ui_min = 0.01f; ui_max = 5.0f;
    ui_label = "SigmaR";
    ui_type = "drag";
    ui_tooltip = "Modify the blur range, higher values approach a normal gaussian blur.";
> = 1.0f;

#define XE_HILBERT_LEVEL (6U)
#define XE_HILBERT_WIDTH (1U << XE_HILBERT_LEVEL)
#define XE_HILBERT_AREA (XE_HILBERT_WIDTH * XE_HILBERT_WIDTH)

#ifndef BEAN_SLICE_COUNT
    #define BEAN_SLICE_COUNT 3
#endif

texture2D ViewSpaceDepthTex {
    Width = BUFFER_WIDTH;
    Height = BUFFER_HEIGHT;
    Format = R32F;
}; sampler2D ViewSpaceDepth { Texture = ViewSpaceDepthTex; MagFilter = POINT; MinFilter = POINT; MipFilter = POINT;};
storage2D s_ViewSpaceDepth { Texture = ViewSpaceDepthTex; };

texture2D NoiseTex { 
    Width = 64; 
    Height = 64; 
    Format = R8; 
}; sampler2D Noise { Texture = NoiseTex; MagFilter = POINT; MinFilter = POINT; MipFilter = POINT; };
storage2D s_Noise { Texture = NoiseTex; };

texture2D UnfilteredAOTex {
    Width = BUFFER_WIDTH;
    Height = BUFFER_HEIGHT;
    Format = R32F;
}; sampler2D UnfilteredAO { Texture = UnfilteredAOTex; MagFilter = POINT; MinFilter = POINT; MipFilter = POINT;};
storage2D s_UnfilteredAO { Texture = UnfilteredAOTex; };

texture2D EdgesTex { 
    Width = BUFFER_WIDTH; 
    Height = BUFFER_HEIGHT; 
    Format = R8; 
}; sampler2D Edges { Texture = EdgesTex; MagFilter = POINT; MinFilter = POINT; MipFilter = POINT; };
storage2D s_Edges { Texture = EdgesTex; };

uint HilbertIndex(uint2 pos) {
    uint index = 0U;

    for (uint curLevel = XE_HILBERT_WIDTH / 2U; curLevel > 0U; curLevel /= 2U) {
        uint regionX = (pos.x & curLevel) > 0U;
        uint regionY = (pos.y & curLevel) > 0U;

        index += curLevel * curLevel * ((3U * regionX) ^ regionY);
        if (regionY == 0U) {
            if (regionX == 1U) {
                pos.x = uint((XE_HILBERT_WIDTH - 1U)) - pos.x;
                pos.y = uint((XE_HILBERT_WIDTH - 1U)) - pos.y;
            }

            uint temp = pos.x;
            pos.x = pos.y;
            pos.y = temp;
        }
    }

    return index;
}

uint GenerateNoise(uint2 pixCoord) {
    return HilbertIndex(pixCoord);
}

float2 SpatioTemporalNoise(uint2 pixCoord, uint temporalIndex) {
    float2 noise;
    uint index = tex2Dfetch(Noise, pixCoord).r;
    index += 288 * (temporalIndex % 64);
    return float2(frac(0.5f + index * float2(0.75487766624669276005f, 0.5698402909980532659114f)));
}

float FastSqrt(float x) {
    return (float)(asfloat(0x1fbd1df5 + (asint(x) >> 1))); 
}

float FastACos(float inX) {
    float x = abs(inX); 
    float res = -0.156583 * x + HALF_PI; 
    res *= FastSqrt(1.0 - x); 
    return (inX >= 0) ? res : PI - res; 
}

void CS_CalculateNoise(uint3 tid : SV_DISPATCHTHREADID) {
    tex2Dstore(s_Noise, tid.xy, GenerateNoise(tid.xy));
}

float PS_PreFilterDepths(float4 position : SV_Position, float2 texcoord : TexCoord) : SV_Target
{
	// float depth = ReShade::GetLinearizedDepth(texcoord);
    float depth = tex2D(ReShade::DepthBuffer, texcoord).x;
    #if RESHADE_DEPTH_INPUT_IS_REVERSED
        depth = 1.0 - depth;
    #endif
    // Transform depth into view space
    depth = XeGTAO::ClampDepth(XeGTAO::ScreenSpaceToViewSpaceDepth(depth));
    return depth;
}

void PS_Main(float4 position : SV_Position, float2 texcoord : TexCoord, out float edge : SV_Target0, out float aoTerm : SV_Target1)
{
    float4 valuesUL = tex2DgatherR(ViewSpaceDepth, texcoord);

    float viewspaceZ = valuesUL.y;

    float pixLZ = valuesUL.x;
    float pixTZ = valuesUL.z;
    float pixRZ = valuesUL.z;
    float pixBZ = valuesUL.x;

    float4 edgesLRTB = XeGTAO::CalculateEdges(viewspaceZ, pixLZ, pixRZ, pixTZ, pixBZ);
	edge = XeGTAO::PackEdges(edgesLRTB);

}

float4 PS_XeGTAO(float4 position : SV_Position, float2 texcoord : TexCoord) : SV_Target
{
	float4 pixel = tex2D(Common::BeanBuffer, texcoord);
	float3 color = pixel.rgb;

	return float4(color, pixel.a);
}

technique BEAN_SetupSSAO < hidden = true; enabled = true; timeout = 1; > {
    pass CalculateNoise {
        ComputeShader = CS_CalculateNoise<8, 8>;
        DispatchSizeX = 8;
        DispatchSizeY = 8;
    }
}


technique Bean_XeGTAO
{
    pass
    {
        RenderTarget = ViewSpaceDepthTex;
        VertexShader = PostProcessVS;
		PixelShader = PS_PreFilterDepths;
        
    }
    pass
    {
        RenderTarget0 = EdgesTex;
        RenderTarget1 = UnfilteredAOTex;
        VertexShader = PostProcessVS;
		PixelShader = PS_Main;
    }
	pass
	{
		RenderTarget = Common::BeanBufferTexTemp;
		VertexShader = PostProcessVS;
		PixelShader = PS_XeGTAO;
	}
	pass
	{
		RenderTarget = Common::BeanBufferTex;
		VertexShader = PostProcessVS;
		PixelShader = Common::PS_EndPass;
	}
}