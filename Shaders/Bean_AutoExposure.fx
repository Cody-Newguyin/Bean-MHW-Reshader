#include "ReShade.fxh"
#include "Bean_Common.fxh"

uniform float _MinLogLuminance <
    ui_min = -20.0f; ui_max = 20.0f;
    ui_label = "Min Log Luminance";
    ui_type = "drag";
> = -5.0f;

uniform float _MaxLogLuminance <
    ui_min = -20.0f; ui_max = 20.0f;
    ui_label = "Max Log Luminance";
    ui_type = "drag";
> = -2.5f;

uniform float _Tau <
    ui_category = "Advanced Settings";
    ui_category_closed = true;
    ui_min = 0.01f; ui_max = 10.0f;
    ui_label = "Tau";
    ui_type = "drag";
    ui_tooltip = "Adjust rate at which auto exposure adjusts.";
> = 5.0f;

uniform float _S1 <
    ui_category = "Advanced Settings";
    ui_category_closed = true;
    ui_min = 0.01f; ui_max = 200.0f;
    ui_label = "Sensitivity Constant 1";
    ui_type = "drag";
    ui_tooltip = "Adjust sensor sensitivity ratio 1.";
> = 100.0f;

uniform float _S2 <
    ui_category = "Advanced Settings";
    ui_category_closed = true;
    ui_min = 0.01f; ui_max = 200.0f;
    ui_label = "Sensitivity Constant 2";
    ui_type = "drag";
    ui_tooltip = "Adjust sensor sensitivity ratio 2.";
> = 100.0f;

uniform float _K <
    ui_category = "Advanced Settings";
    ui_category_closed = true;
    ui_min = 1.0f; ui_max = 100.0f;
    ui_label = "Calibration Constant";
    ui_type = "drag";
    ui_tooltip = "Adjust reflected-light meter calibration constant.";
> = 12.5f;

uniform float _q <
    ui_category = "Advanced Settings";
    ui_category_closed = true;
    ui_min = 0.01f; ui_max = 10.0f;
    ui_label = "Lens Attenuation";
    ui_type = "drag";
    ui_tooltip = "Adjust lens and vignetting attenuation.";
> = 0.65f;

uniform float _DeltaTime < source = "frametime"; >;

#define BEAN_DIVIDE_ROUNDING_UP(n, d) uint((n + d - 1) / d)
#define BEAN_NUM_TILES_WIDE BEAN_DIVIDE_ROUNDING_UP(BUFFER_WIDTH, 16)
#define BEAN_NUM_TILES_HIGH BEAN_DIVIDE_ROUNDING_UP(BUFFER_HEIGHT, 16)
#define BEAN_NUM_TILES (BEAN_NUM_TILES_WIDE * BEAN_NUM_TILES_HIGH)

#define BEAN_LOG_RANGE (_MaxLogLuminance - _MinLogLuminance)
#define BEAN_LOG_RANGE_RCP 1.0f / BEAN_LOG_RANGE

// Stores histogram for each tile
texture2D BEAN_HistogramTileTex {
    Width = BEAN_NUM_TILES; 
    Height = 256; 
    Format = R32F;
}; storage2D HistogramTileBuffer { Texture = BEAN_HistogramTileTex; };
sampler2D HistogramTileSampler { Texture = BEAN_HistogramTileTex; };

// Stores totalled histogram for whole image
texture2D BEAN_HistogramTex {
    Width = 256; Height = 1; Format = R32F;
}; storage2D HistogramBuffer { Texture = BEAN_HistogramTex; };
sampler2D HistogramSampler { Texture = BEAN_HistogramTex; };

// Stores a single value: Average luminance
texture2D BEAN_HistogramAverageTex { 
    Format = R32F; 
}; storage2D HistogramAverageBuffer { Texture = BEAN_HistogramAverageTex; };
sampler2D HistogramAverage { Texture = BEAN_HistogramAverageTex; MagFilter = POINT; MinFilter = POINT; MipFilter = POINT; };

texture2D BEAN_LuminanceScaleTex { 
    Format = R32F; 
}; storage2D LuminanceScaleBuffer { Texture = BEAN_LuminanceScaleTex; };
sampler2D LuminanceScale { Texture = BEAN_LuminanceScaleTex; MagFilter = POINT; MinFilter = POINT; MipFilter = POINT; };


uint ColorToHistogramBin(float3 color) {
    float luminance = Common::Luminance(color);
    
    if (luminance < 0.001f)
        return 0;

    float logLuminance = saturate((log2(luminance) - _MinLogLuminance) *  BEAN_LOG_RANGE_RCP);

    return (uint)(logLuminance * 254.0f + 1.0f);
}


groupshared uint HistogramShared[256];
void ConstructHistogramTiles(uint groupIndex : SV_GROUPINDEX, uint3 gid : SV_GROUPID, uint3 tid : SV_DISPATCHTHREADID) 
{
    // Cheeky histogram table construction by Acerola
    // Conveniently because our thread group is for a 16x16 tile each thread clears
    // the histogram at a luminance level based on its group index (256 threads, 256 luminance levels).
    // It then adds to the histogram based on the pixel's luminance level.
    // Finally it writes to the Buffer in its respective tile and
    // at a the group index luminance level (unrelated to the luminance level of the pixel).
    HistogramShared[groupIndex] = 0;

    barrier();

    if (tid.x < BUFFER_WIDTH && tid.y < BUFFER_HEIGHT) {
        float3 color = tex2Dfetch(Common::BeanBuffer, tid.xy).rgb;
        uint binIndex = ColorToHistogramBin(color);
        atomicAdd(HistogramShared[binIndex], 1);
    }

    barrier();

    // dispatchIndex is tile we are in 
    // uint dispatchIndex = tid.x / 16 + (tid.y / 16) * BEAN_NUM_TILES_WIDE;
    uint dispatchIndex = gid.x + gid.y * BEAN_NUM_TILES_WIDE;
    // threadIndex is the pixel we are on relative to the 16x16 tile, equivalent to group index
    // uint threadIndex = gtid.x + gtid.y * 16;
    tex2Dstore(HistogramTileBuffer, uint2(dispatchIndex, groupIndex), HistogramShared[groupIndex]);
}


groupshared uint mergedBin;
void MergeHistogramTiles(uint3 tid : SV_DISPATCHTHREADID, uint3 gtid : SV_GROUPTHREADID) {
    // Each group handles a luminance level and each thread handles 16 tiles in said luminance level
    // Only the first thread of each group modifies the final histogram table
    if (all(gtid.xy == 0))
        mergedBin = 0;

    barrier();
     
    // Get the center of the pixel
    float2 coord = float2(tid.x * 16, tid.y) + 0.5;
    uint histValues = 0;
    // Sum counts on group luminance level for 16 tiles
    [unroll]
    for (int i = 0; i < 16; i++)
        histValues += tex2Dfetch(HistogramTileSampler, coord + float2(i, 0)).r;

    atomicAdd(mergedBin, histValues);

    barrier();

    if (all(gtid.xy ==0))
        tex2Dstore(HistogramBuffer, uint2(tid.y, 0), mergedBin);
}

// https://bruop.github.io/exposure/
groupshared float HistogramAvgShared[256];
void CalculateHistogramAverage(uint3 tid : SV_DISPATCHTHREADID) {
    float countForThisBin = (float)tex2Dfetch(HistogramSampler, tid.xy).r;

    HistogramAvgShared[tid.x] = countForThisBin * (float)tid.x;

    barrier();

    // Does a weighted count of histogram
    // Iteravely sums the lower half of the table with the upper half, halving the table every loop
    // The final sum is stored in the first index
    [unroll]
    for (uint histogramSampleIndex = (256 >> 1); histogramSampleIndex > 0; histogramSampleIndex >>= 1) {
        if (tid.x < histogramSampleIndex) {
            HistogramAvgShared[tid.x] += HistogramAvgShared[tid.x + histogramSampleIndex];
        }

        barrier();
    }

    if (tid.x == 0) {
        // ignore black pixels
        float weightedLogAverage = (HistogramAvgShared[0] / max((float)(BUFFER_WIDTH * BUFFER_HEIGHT) - countForThisBin, 1.0f)) - 1.0f;
        float weightedAverageLuminance = exp2(((weightedLogAverage / 254.0f) * BEAN_LOG_RANGE) + _MinLogLuminance);
        float luminanceLastFrame = tex2Dfetch(HistogramAverage, uint2(0, 0)).r;
        float adaptedLuminance = luminanceLastFrame + (weightedAverageLuminance - luminanceLastFrame) * (1 - exp(-_DeltaTime * _Tau));
        tex2Dstore(HistogramAverageBuffer, uint2(0, 0), adaptedLuminance);

        float luminanceScale = (78.0f / (_q * _S1)) * (_S2 / _K) * adaptedLuminance;
        tex2Dstore(LuminanceScaleBuffer, uint2(0, 0), luminanceScale);
    }
}

float4 PS_AutoExposure(float4 position : SV_Position, float2 texcoord : TexCoord) : SV_Target
{
	float4 pixel = tex2D(Common::BeanBuffer, texcoord);
	float3 color = pixel.rgb;

    float luminanceScale = tex2Dfetch(LuminanceScale, 0).r;

    float3 yxy = Common::convertRGB2Yxy(color.rgb);
    yxy.x /= luminanceScale;
    color.rgb = Common::convertYxy2RGB(yxy);

	return float4(color, pixel.a);
}

technique Bean_AutoExposure
{
    pass
    {
        ComputeShader = ConstructHistogramTiles<16, 16>;
        DispatchSizeX = BEAN_NUM_TILES_WIDE;
        DispatchSizeY = BEAN_NUM_TILES_HIGH;
    }
    pass {
        ComputeShader = MergeHistogramTiles<BEAN_DIVIDE_ROUNDING_UP(BEAN_NUM_TILES, 16), 1>;
        DispatchSizeX = 1;
        DispatchSizeY = 256;
    }
    pass AverageHistogram {
        ComputeShader = CalculateHistogramAverage<256, 1>;
        DispatchSizeX = 1;
        DispatchSizeY = 1;
    }
	pass
	{
		RenderTarget = Common::BeanBufferTexTemp;
		VertexShader = PostProcessVS;
		PixelShader = PS_AutoExposure;
	}
	pass
	{
		RenderTarget = Common::BeanBufferTex;
		VertexShader = PostProcessVS;
		PixelShader = Common::PS_EndPass;
	}
}