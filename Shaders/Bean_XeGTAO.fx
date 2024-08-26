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

#define BEAN_DENOISE_BLUR (1e4f)

#define XE_HILBERT_LEVEL (6U)
#define XE_HILBERT_WIDTH (1U << XE_HILBERT_LEVEL)
#define XE_HILBERT_AREA (XE_HILBERT_WIDTH * XE_HILBERT_WIDTH)

#ifndef BEAN_SLICE_COUNT
    #define BEAN_SLICE_COUNT 3
#endif

#ifndef BEAN_STEPS_PER_SLICE
    #define BEAN_STEPS_PER_SLICE 3
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
    float depth = tex2Dfetch(ReShade::DepthBuffer, position.xy).x;
    #if RESHADE_DEPTH_INPUT_IS_REVERSED
        depth = 1.0 - depth;
    #endif
    // Transform depth into view space
    depth = XeGTAO::ClampDepth(XeGTAO::ScreenSpaceToViewSpaceDepth(depth));
    return depth.x;
}

void PS_Main(float4 position : SV_Position, float2 texcoord : TexCoord, out float edge : SV_Target0, out float aoTerm : SV_Target1)
{
    const float2 viewportPixelSize = float2(BUFFER_RCP_WIDTH, BUFFER_RCP_HEIGHT);
    // honestly no idea how this works bruh...
    float2 normalizedScreenPos = (position.xy + 1.0f) * viewportPixelSize;
    normalizedScreenPos = texcoord;
    float4 valuesUL = tex2DgatherR(ViewSpaceDepth, position.xy * viewportPixelSize);

    float viewspaceZ = valuesUL.y;

    float pixLZ = valuesUL.x;
    float pixTZ = valuesUL.z;
    float pixRZ = valuesUL.z;
    float pixBZ = valuesUL.x;

    float4 edgesLRTB = XeGTAO::CalculateEdges(viewspaceZ, pixLZ, pixRZ, pixTZ, pixBZ);
	edge = XeGTAO::PackEdges(edgesLRTB).x;

    float height = 1.0f;
    float width = height * (BUFFER_WIDTH / BUFFER_HEIGHT);

    float2 CameraTanHalfFOV = float2(height, width);

    float2 NDCToViewMul = float2(CameraTanHalfFOV.x * 2.0f, CameraTanHalfFOV.y * -2.0f);
    float2 NDCToViewAdd = float2(CameraTanHalfFOV.x * -1.0f, CameraTanHalfFOV.y * 1.0f);
    float4 NDCToView = float4(NDCToViewMul, NDCToViewAdd);

    float3 center = XeGTAO::ComputeViewspacePosition(normalizedScreenPos, viewspaceZ, NDCToView);
    float3 left   = XeGTAO::ComputeViewspacePosition(normalizedScreenPos + float2(-1,  0) * viewportPixelSize, pixLZ, NDCToView);
    float3 right  = XeGTAO::ComputeViewspacePosition(normalizedScreenPos + float2( 1,  0) * viewportPixelSize, pixRZ, NDCToView);
    float3 top    = XeGTAO::ComputeViewspacePosition(normalizedScreenPos + float2( 0, -1) * viewportPixelSize, pixTZ, NDCToView);
    float3 bottom = XeGTAO::ComputeViewspacePosition(normalizedScreenPos + float2( 0,  1) * viewportPixelSize, pixBZ, NDCToView);
    float3 viewspaceNormal = XeGTAO::CalculateNormal(edgesLRTB, center, left, right, top, bottom);

    viewspaceZ *= 0.99999;

    const float3 viewVec = normalize(-center);

    viewspaceNormal = normalize(viewspaceNormal + max(0, -dot(viewspaceNormal, viewVec)) * viewVec);

    const float effectRadius = _EffectRadius * _RadiusMultiplier;
    const float sampleDistributionPower = _SampleDistributionPower;
    const float thinOccluderCompensation = _ThinOccluderCompensation;
    const float falloffRange = _EffectFalloffRange * effectRadius;

    const float falloffFrom = effectRadius * (1.0f - _EffectFalloffRange);

    const float falloffMul = -1.0f / falloffRange;
    const float falloffAdd = falloffFrom / falloffRange + 1.0f;

    float visibility = 0.0f;
    float3 bentNormal = viewspaceNormal;

    float2 localNoise = SpatioTemporalNoise(position.xy, 0);

    const float noiseSlice = localNoise.x;
    const float noiseSample = localNoise.y;

    const float pixelTooCloseThreshold = 1.0f;
    const float2 pixelDirRBViewspaceSizeAtCenterZ = (NDCToView.xy * viewportPixelSize.xy) * viewspaceZ;
    float screenspaceRadius = effectRadius / pixelDirRBViewspaceSizeAtCenterZ.x;
    
    visibility += saturate((10.0f - screenspaceRadius) / 100.0f) * 0.5f;

    const float minS = pixelTooCloseThreshold / screenspaceRadius;

    const float sliceCount = (float)BEAN_SLICE_COUNT;
    const float stepsPerSlice = (float)BEAN_STEPS_PER_SLICE;

    [unroll]
    for (float slice = 0; slice < sliceCount; ++slice) {
        float sliceK = (slice + noiseSlice) / sliceCount;
        
        float phi = sliceK * PI;
        float cosPhi = cos(phi);
        float sinPhi = sin(phi);
        float2 omega = float2(cosPhi, -sinPhi);

        omega *= screenspaceRadius;

        float3 directionVec = float3(cosPhi, sinPhi, 0);
        float3 orthoDirectionVec = directionVec - (dot(directionVec, viewVec) * viewVec);

        float3 axisVec = normalize(cross(orthoDirectionVec, viewVec));
        float3 projectedNormalVec = viewspaceNormal - axisVec * dot(viewspaceNormal, axisVec);

        float signNorm = (float)sign(dot(orthoDirectionVec, projectedNormalVec));

        float projectedNormalVecLength = length(projectedNormalVec);
        float cosNorm = (float)saturate(dot(projectedNormalVec, viewVec) / projectedNormalVecLength);

        float n = signNorm * FastACos(cosNorm);

        const float lowHorizonCos0 = cos(n + HALF_PI);
        const float lowHorizonCos1 = cos(n - HALF_PI);

        float horizonCos0 = lowHorizonCos0;
        float horizonCos1 = lowHorizonCos1;
        
        [unroll]
        for (int step = 0; step < stepsPerSlice; ++step) {
            const float stepBaseNoise = (float)(slice + step * stepsPerSlice) * 0.6180339887498948482f;
            float stepNoise = frac(noiseSample + stepBaseNoise);

            float s = (step + stepNoise) / (stepsPerSlice);
            s = (float)pow(s, sampleDistributionPower);
            s += minS;

            float2 sampleOffset = s * omega;
            float sampleOffsetLength = length(sampleOffset);

            sampleOffset = round(sampleOffset) * viewportPixelSize;

            float2 sampleScreenPos0 = normalizedScreenPos + sampleOffset;
            float SZ0 = tex2Dfetch(ViewSpaceDepth, sampleScreenPos0 * float2(BUFFER_WIDTH, BUFFER_HEIGHT)).r;
            float3 samplePos0 = XeGTAO::ComputeViewspacePosition(sampleScreenPos0, SZ0, NDCToView);

            float2 sampleScreenPos1 = normalizedScreenPos - sampleOffset;
            float SZ1 = tex2Dfetch(ViewSpaceDepth, sampleScreenPos1 * float2(BUFFER_WIDTH, BUFFER_HEIGHT)).r;
            float3 samplePos1 = XeGTAO::ComputeViewspacePosition(sampleScreenPos1, SZ1, NDCToView);

            float3 sampleDelta0 = (samplePos0 - float3(center));
            float3 sampleDelta1 = (samplePos1 - float3(center));
            float sampleDist0 = (float)length(sampleDelta0);
            float sampleDist1 = (float)length(sampleDelta1);

            float3 sampleHorizonVec0 = (float3)(sampleDelta0 / sampleDist0);
            float3 sampleHorizonVec1 = (float3)(sampleDelta1 / sampleDist1);

            float falloffBase0 = length(float3(sampleDelta0.x, sampleDelta0.y, sampleDelta0.z * (1.0f + thinOccluderCompensation)));
            float falloffBase1 = length(float3(sampleDelta1.x, sampleDelta1.y, sampleDelta1.z * (1.0f + thinOccluderCompensation)));
            float weight0 = saturate(falloffBase0 * falloffMul + falloffAdd);
            float weight1 = saturate(falloffBase1 * falloffMul + falloffAdd);

            float shc0 = (float)dot(sampleHorizonVec0, viewVec);
            float shc1 = (float)dot(sampleHorizonVec1, viewVec);

            shc0 = lerp(lowHorizonCos0, shc0, weight0);
            shc1 = lerp(lowHorizonCos1, shc1, weight1);

            horizonCos0 = max(horizonCos0, shc0);
            horizonCos1 = max(horizonCos1, shc1);
        }

        projectedNormalVecLength = lerp(projectedNormalVecLength, 1.0f, _SlopeCompensation);

        float h0 = -FastACos(horizonCos1);
        float h1 = FastACos(horizonCos0);

        float iarc0 = (cosNorm + 2.0f * h0 * sin(n) - cos(2.0f * h0 - n)) / 4.0f;
        float iarc1 = (cosNorm + 2.0f * h1 * sin(n) - cos(2.0f * h1 - n)) / 4.0f;
        float localVisibility = projectedNormalVecLength * (iarc0 + iarc1);
        visibility += localVisibility;
    }

    visibility /= sliceCount;
    visibility = pow(abs(visibility), _FinalValuePower);
    visibility = max(0.03, visibility);

    visibility = saturate(visibility / 1.5f);
    visibility = visibility * 255.0f + 0.5f;
    aoTerm = visibility;
}

void AddSample(float4 ssaoValue, float edgeValue, inout float4 sum, inout float sumWeight) {
    float weight = edgeValue;

    sum += (weight * ssaoValue);
    sumWeight += weight;
}

void CS_Denoise(uint2 tid : SV_DISPATCHTHREADID) {
    const float2 viewportPixelSize = float2(BUFFER_RCP_WIDTH, BUFFER_RCP_HEIGHT);
    const uint2 pixCoordBase = (tid) * uint2(2, 1);

    bool finalApply = true;

    const float blurAmount = (finalApply) ? BEAN_DENOISE_BLUR : (BEAN_DENOISE_BLUR / 5.0f);
    const float diagWeight = 0.85f * 0.5f;

    float aoTerm[2];
    float4 edgesC_LRTB[2];
    float weightTL[2];
    float weightTR[2];
    float weightBL[2];
    float weightBR[2];

    const float2 gatherCenter = pixCoordBase * viewportPixelSize;

    float4 edgesQ0 = tex2DgatherR(Edges, gatherCenter, int2(0, 0));
    float4 edgesQ1 = tex2DgatherR(Edges, gatherCenter, int2(2, 0));
    float4 edgesQ2 = tex2DgatherR(Edges, gatherCenter, int2(1, 2));

    float visQ0[4]; XeGTAO::DecodeGatherPartial(tex2DgatherR(UnfilteredAO, gatherCenter, int2(0, 0)), visQ0);
    float visQ1[4]; XeGTAO::DecodeGatherPartial(tex2DgatherR(UnfilteredAO, gatherCenter, int2(2, 0)), visQ1);
    float visQ2[4]; XeGTAO::DecodeGatherPartial(tex2DgatherR(UnfilteredAO, gatherCenter, int2(0, 2)), visQ2);
    float visQ3[4]; XeGTAO::DecodeGatherPartial(tex2DgatherR(UnfilteredAO, gatherCenter, int2(2, 2)), visQ3);

    [unroll]
    for (int side = 0; side < 2; ++side) {
        const int2 pixCoord = int2(pixCoordBase.x + side, pixCoordBase.y);

        float4 edgesL_LRTB = XeGTAO::UnpackEdges((side == 0) ? (edgesQ0.x) : (edgesQ0.y));
        float4 edgesT_LRTB = XeGTAO::UnpackEdges((side == 0) ? (edgesQ0.z) : (edgesQ1.w));
        float4 edgesR_LRTB = XeGTAO::UnpackEdges((side == 0) ? (edgesQ1.x) : (edgesQ1.y));
        float4 edgesB_LRTB = XeGTAO::UnpackEdges((side == 0) ? (edgesQ2.w) : (edgesQ2.z));

        edgesC_LRTB[side] = XeGTAO::UnpackEdges((side == 0) ? (edgesQ0.y) : (edgesQ1.x));
        edgesC_LRTB[side] *= float4(edgesL_LRTB.y, edgesR_LRTB.x, edgesT_LRTB.w, edgesB_LRTB.z);
        
        const float leak_threshold = 2.5; 
        const float leak_strength = 0.5;
        
        float edginess = (saturate(4.0f - leak_threshold - dot(edgesC_LRTB[side], 1.0f)) / (4.0f - leak_threshold)) * leak_strength;
        edgesC_LRTB[side] = saturate(edgesC_LRTB[side] + edginess);

        weightTL[side] = diagWeight * (edgesC_LRTB[side].x * edgesL_LRTB.z + edgesC_LRTB[side].z * edgesT_LRTB.x);
        weightTR[side] = diagWeight * (edgesC_LRTB[side].z * edgesT_LRTB.y + edgesC_LRTB[side].y * edgesR_LRTB.z);
        weightBL[side] = diagWeight * (edgesC_LRTB[side].w * edgesB_LRTB.x + edgesC_LRTB[side].x * edgesL_LRTB.w);
        weightBR[side] = diagWeight * (edgesC_LRTB[side].y * edgesR_LRTB.w + edgesC_LRTB[side].w * edgesB_LRTB.y);

        // first pass
        float ssaoValue     = (side == 0) ? (visQ0[1]) : (visQ1[0]);
        float ssaoValueL    = (side == 0) ? (visQ0[0]) : (visQ0[1]);
        float ssaoValueT    = (side == 0) ? (visQ0[2]) : (visQ1[3]);
        float ssaoValueR    = (side == 0) ? (visQ1[0]) : (visQ1[1]);
        float ssaoValueB    = (side == 0) ? (visQ2[2]) : (visQ3[3]);
        float ssaoValueTL   = (side == 0) ? (visQ0[3]) : (visQ0[2]);
        float ssaoValueBR   = (side == 0) ? (visQ3[3]) : (visQ3[2]);
        float ssaoValueTR   = (side == 0) ? (visQ1[3]) : (visQ1[2]);
        float ssaoValueBL   = (side == 0) ? (visQ2[3]) : (visQ2[2]);

        float sumWeight = blurAmount;
        float sum = ssaoValue * sumWeight;

        AddSample(ssaoValueL, edgesC_LRTB[side].x, sum, sumWeight);
        AddSample(ssaoValueR, edgesC_LRTB[side].y, sum, sumWeight);
        AddSample(ssaoValueT, edgesC_LRTB[side].z, sum, sumWeight);
        AddSample(ssaoValueB, edgesC_LRTB[side].w, sum, sumWeight);

        AddSample(ssaoValueTL, weightTL[side], sum, sumWeight);
        AddSample(ssaoValueTR, weightTR[side], sum, sumWeight);
        AddSample(ssaoValueBL, weightBL[side], sum, sumWeight);
        AddSample(ssaoValueBR, weightBR[side], sum, sumWeight);

        aoTerm[side] = sum / sumWeight;

        float visibility = aoTerm[side] * ((finalApply) ? (1.5f) : (1));
        tex2Dstore(s_ViewSpaceDepth, pixCoord, visibility * 255.0f + 0.5f);
    }
}

float gaussR(float sigma, float dist) {
	return exp(-(dist * dist) / (2.0 * sigma * sigma));
}

float  gaussD(float sigma, int x, int y) {
	return exp(-((x * x + y * y) / (2.0f * sigma * sigma)));
}

float4 PS_XeGTAO(float4 position : SV_Position, float2 texcoord : TexCoord) : SV_Target
{
	float4 pixel = tex2D(Common::BeanBuffer, texcoord);
	float3 color = pixel.rgb;

     const int kernelRadius = (int)ceil(2.0f * _SigmaD);

    float sum = 0.0f;
    float sumWeight = 0.0f;

    float center = tex2Dfetch(ViewSpaceDepth, position.xy).r / 255.0f;

    int upper = ((kernelRadius - 1) * 0.5f);
    int lower = -upper;

    for (int x = lower; x <= upper; ++x) {
        for(int y = lower; y <= upper; ++y) {
            int2 offset = int2(x, y);

            float intKerPos = tex2Dfetch(ViewSpaceDepth, position.xy + offset).r / 255.0f;
            float weight = gaussD(_SigmaD, (position.x + x) - position.x, (position.y + y) - position.y) * gaussR(_SigmaR, intKerPos - center);

            sumWeight += weight;
            sum += weight * intKerPos;
        }
    }

    float visibility = sumWeight > 0 ? sum / (sumWeight + 0.001f) : center;

    // Apply AO
    float3 normal = ReShade::GetScreenSpaceNormal(texcoord);
    visibility = lerp(visibility, 1.0f, normal.y * normal.y * normal.y);

    float3 a =  2.0404 * color - 0.3324;
    float3 b = -4.7951 * color + 0.6417;
    float3 c =  2.7552 * color + 0.6903;

    float3 output = max(visibility, ((visibility * a + b) * visibility + c) * visibility);

    color = color * output;
    // float3 test = float3(visibility, visibility, visibility);
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
        // Computes 2 horizontal pixels at a time
        ComputeShader = CS_Denoise<8, 8>;
        DispatchSizeX = (BUFFER_WIDTH + (8 * 2) - 1) / (8 * 2);
        DispatchSizeY = (BUFFER_HEIGHT + 8 - 1) / 8;
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