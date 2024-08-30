#include "ReShade.fxh"
#include "Bean_Common.fxh"

#define BEAN_EDGE_STEP_COUNT 10
#define BEAN_EDGE_STEPS 1, 1.5, 2, 2, 2, 2, 2, 2, 2, 4
#define BEAN_EDGE_GUESS 8

static const float edgeSteps[BEAN_EDGE_STEP_COUNT] = { BEAN_EDGE_STEPS };

uniform float _ContrastThreshold <
    ui_min = 0.0312f; ui_max = 0.0833f;
    ui_label = "Contrast Threshold";
    ui_type = "drag";
> = 0.0312f;

uniform float _RelativeThreshold <
    ui_min = 0.063f; ui_max = 0.333f;
    ui_label = "Relative Threshold";
    ui_type = "drag";
> = 0.063f;

uniform float _SubpixelBlending <
    ui_min = 0.0f; ui_max = 1.0f;
    ui_label = "Subpixel Blending";
    ui_type = "drag";
> = 1.0f;

texture2D LuminanceTex {
    Width = BUFFER_WIDTH;
    Height = BUFFER_HEIGHT;
    Format = R8;
}; sampler2D Luminance { Texture = LuminanceTex; };

float PS_Luminance(float4 position : SV_Position, float2 texcoord : TexCoord) : SV_Target
{
    float4 pixel = tex2D(Common::BeanBuffer, texcoord);
	float3 color = pixel.rgb;

	return Common::Luminance(color);
}

float4 PS_FXAA(float4 position : SV_Position, float2 texcoord : TexCoord) : SV_Target
{
    float2 texelSize = float2(BUFFER_RCP_WIDTH, BUFFER_RCP_HEIGHT);

    // Luminance for 3x3 grid around pixel
    float m = tex2D(Luminance, texcoord + float2(0, 0) * texelSize).r;
    
    float n = tex2D(Luminance, texcoord + float2(0, 1) * texelSize).r;
    float e = tex2D(Luminance, texcoord + float2(1, 0) * texelSize).r;
    float s = tex2D(Luminance, texcoord + float2(0, -1) * texelSize).r;
    float w = tex2D(Luminance, texcoord + float2(-1, 0) * texelSize).r;
    
    float ne = tex2D(Luminance, texcoord + float2(1, 1) * texelSize).r;
    float nw = tex2D(Luminance, texcoord + float2(-1, 1) * texelSize).r;
    float se = tex2D(Luminance, texcoord + float2(1, -1) * texelSize).r;
    float sw = tex2D(Luminance, texcoord + float2(-1, -1) * texelSize).r;


    float maxLum = max(max(max(max(m, n), e), s), w);
    float minLum = min(min(min(min(m, n), e), s), w);
    float contrast = maxLum - minLum;

    // Skip low contrast pixels
    if (contrast < max(_ContrastThreshold, _RelativeThreshold * maxLum)) return tex2D(Common::BeanBuffer, texcoord);

    // Get average luminance of neighbors with diagonals weighted less
    float filter = 2 * (n + e + s + w) + ne + nw + se + sw;
    filter *= 1.0f/ 12.0f;

    // Determine blend factor
    filter = abs(filter - m);
    filter = saturate(filter / contrast);
    float blendFactor = smoothstep(0, 1, filter);
    blendFactor *= blendFactor * _SubpixelBlending;

    // Determine blend direction
    float horizontal = abs(n + s - 2 * m) * 2 + abs(ne + se - 2 * e) + abs(nw + sw - 2 * w);
    float vertical = abs(e + w - 2 * m) * 2 + abs(ne + nw - 2 * n) + abs(se + sw - 2 * s);
    bool isHorizontal = horizontal >= vertical;
    float pLuminance = isHorizontal ? n : e;
    float nLuminance = isHorizontal ? s : w;
    float pGradient = abs(pLuminance - m);
    float nGradient = abs(nLuminance - m);

    float2 pixelStep = isHorizontal ? float2(0, texelSize.y) : float2(texelSize.x, 0);
    float2 edgeStep = texelSize - pixelStep;
    float oppositeLuminance = pLuminance;
    float gradient = pGradient;
    // flip direction if positive side is darker
    if (pGradient < nGradient) {
        pixelStep = -pixelStep;
        oppositeLuminance = nLuminance;
        gradient = nGradient;
    }
    
    // sample at edge between pixels
    float2 uvEdge = texcoord + pixelStep * 0.5f;
    
    float edgeLuminance = (m + oppositeLuminance) * 0.5f;
    float gradientThreshold = gradient * 0.25f;

    // moving the first check inside the loop is probably a missed optimization but whatever
    float2 puv = uvEdge;
    float pLuminanceDelta;
    bool pAtEnd = false;
    [unroll]
    for (int j = 0; j < BEAN_EDGE_STEP_COUNT && !pAtEnd; j++) {
        puv += edgeStep * edgeSteps[j];
        pLuminanceDelta = tex2D(Luminance, puv).r - edgeLuminance;
        pAtEnd = abs(pLuminanceDelta) >= gradientThreshold;
    }
    
    if (!pAtEnd)
        puv += edgeStep * BEAN_EDGE_GUESS;

    float2 nuv = uvEdge;
    float nLuminanceDelta;
    bool nAtEnd = false;
    [unroll]
    for (int k = 0; k < BEAN_EDGE_STEP_COUNT && !nAtEnd; k++) {
        nuv -= edgeStep * edgeSteps[k];
        nLuminanceDelta = tex2D(Luminance, nuv).r - edgeLuminance;
        nAtEnd = abs(nLuminanceDelta) >= gradientThreshold;
    }

     if (!nAtEnd)
        nuv -= edgeStep * BEAN_EDGE_GUESS;

    float pDistance, nDistance;
    if (isHorizontal) {
        pDistance = puv.x - texcoord.x;
        nDistance = texcoord.x - nuv.x;
    } else {
        pDistance = puv.y - texcoord.y;
        nDistance = texcoord.y - nuv.y;
    }


    float shortestDistance = nDistance;
    bool deltaSign = nLuminanceDelta >= 0;

    if (pDistance <= nDistance) {
        shortestDistance = pDistance;
        deltaSign = pLuminanceDelta >= 0;
    }

    if (deltaSign == (m - edgeLuminance >= 0)) return tex2D(Common::BeanBuffer, texcoord);

    float edgeBlendFactor = 0.5f - shortestDistance / (pDistance + nDistance);

    float finalBlendFactor = max(edgeBlendFactor, blendFactor);

    float2 offset = pixelStep * finalBlendFactor;
	return tex2D(Common::BeanBuffer, texcoord + offset);
}

technique Bean_FXAA
{
    pass
    {
        RenderTarget = LuminanceTex;
        VertexShader = PostProcessVS;
		PixelShader = PS_Luminance;
    }
	pass
	{
		RenderTarget = Common::BeanBufferTexTemp;
		VertexShader = PostProcessVS;
		PixelShader = PS_FXAA;
	}
	pass
	{
		RenderTarget = Common::BeanBufferTex;
		VertexShader = PostProcessVS;
		PixelShader = Common::PS_EndPass;
	}
}