#include "ReShade.fxh"
#include "Bean_Common.fxh"

#ifndef BEAN_NUM_DOWNSCALES
    #define BEAN_NUM_DOWNSCALES 0
#endif

uniform int _SampleMode <
    ui_type = "combo";
    ui_label = "Sample mode";
    ui_items = "Point\0"
               "Box\0"
               "Box13\0";
> = 0;

uniform int _BlendMode <
    ui_type = "combo";
    ui_label = "Blend mode";
    ui_items = "Add\0"
               "Screen\0"
               "Color Dodge\0";
> = 0;

uniform float _Threshold <
    ui_min = 0.0f; ui_max = 1.0f;
    ui_label = "Threshold";
    ui_type = "drag";
> = 0.8f;

uniform float _SoftThreshold <
    ui_min = 0.0f; ui_max = 1.0f;
    ui_label = "Soft Threshold";
    ui_type = "drag";
> =  0.75;

uniform float _Intensity <
    ui_min = 0.0f; ui_max = 10.0f;
    ui_label = "Intensity";
    ui_type = "drag";
> = 1.0f;

uniform bool _UseKarisAvg <
    ui_category = "Advanced settings";
    ui_category_closed = true;
    ui_label = "Use Karis Average";
    ui_tooltip = "Suppress very bright outlying hdr values to prevent fireflies (pixel flickering)";
> = true;

uniform float _LuminanceBias <
    ui_category = "Advanced settings";
    ui_category_closed = true;
    ui_min = 0.0f; ui_max = 2.0f;
    ui_label = "Luminance Bias";
    ui_type = "drag";
    ui_tooltip = "Luminance bias for karis average";
> = 1.0f;

uniform float _Delta <
    ui_category = "Advanced settings";
    ui_category_closed = true;
    ui_min = 0.01f; ui_max = 2.0f;
    ui_label = "Sampling Delta";
    ui_type = "drag";
> = 1.0f;

uniform bool _Debug <
    ui_category_closed = true;
    ui_category = "Advanced settings";
    ui_label = "Debug";
    ui_tooltip = "Show values in prefiltered";
> = false;

texture2D HalfTex {
    Width = BUFFER_WIDTH / 2;
    Height = BUFFER_HEIGHT / 2;

    Format = RGBA16F;
}; sampler2D Half { Texture = HalfTex; };

texture2D QuarterTex {
    Width = BUFFER_WIDTH / 4;
    Height = BUFFER_HEIGHT / 4;

    Format = RGBA16F;
}; sampler2D Quarter { Texture = QuarterTex; };

texture2D EighthTex {
    Width = BUFFER_WIDTH / 8;
    Height = BUFFER_HEIGHT / 8;

    Format = RGBA16F;
}; sampler2D Eighth { Texture = EighthTex; };

texture2D SixteenthTex {
    Width = BUFFER_WIDTH / 16;
    Height = BUFFER_HEIGHT / 16;

    Format = RGBA16F;
}; sampler2D Sixteenth { Texture = SixteenthTex; };

texture2D ThirtySecondthTex {
    Width = BUFFER_WIDTH / 32;
    Height = BUFFER_HEIGHT / 32;

    Format = RGBA16F;
}; sampler2D ThirtySecondth { Texture = ThirtySecondthTex; };

texture2D SixtyFourthTex {
    Width = BUFFER_WIDTH / 64;
    Height = BUFFER_HEIGHT / 64;

    Format = RGBA16F;
}; sampler2D SixtyFourth { Texture = SixtyFourthTex; };

texture2D OneTwentyEighthTex {
    Width = BUFFER_WIDTH / 128;
    Height = BUFFER_HEIGHT / 128;

    Format = RGBA16F;
}; sampler2D OneTwentyEighth { Texture = OneTwentyEighthTex; };

texture2D TwoFiftySixthTex {
    Width = BUFFER_WIDTH / 256;
    Height = BUFFER_HEIGHT / 256;

    Format = RGBA16F;
}; sampler2D TwoFiftySixth { Texture = TwoFiftySixthTex; };

// https://catlikecoding.com/unity/tutorials/advanced-rendering/bloom/
float3 Prefilter(float3 color) {
    float luminance = Common::Luminance(color);

    float knee = _Threshold * _SoftThreshold;
    float soft = luminance - _Threshold + knee;
    soft = clamp(soft, 0, 2 * knee);
    soft = soft * soft / (4 * knee + 0.00001);
    float contribution = max(soft, luminance - _Threshold);
    contribution /= max(luminance, 0.00001);

    return color * contribution;
}

float3 SampleBox(sampler2D texSampler, float2 texcoord, float2 texelSize, float delta) {
    float4 o = texelSize.xyxy * float2(-delta, delta).xxyy;
    float3 s1 = tex2D(texSampler, texcoord + o.xy).rgb;
    float3 s2 = tex2D(texSampler, texcoord + o.zy).rgb;
    float3 s3 = tex2D(texSampler, texcoord + o.xw).rgb;
    float3 s4 = tex2D(texSampler, texcoord + o.zw).rgb;

    float3 s = 0.0f;
    if (_UseKarisAvg) {
        float s1w = rcp(Common::MaxLuminance(s1) + _LuminanceBias);
        float s2w = rcp(Common::MaxLuminance(s2) + _LuminanceBias);
        float s3w = rcp(Common::MaxLuminance(s3) + _LuminanceBias);
        float s4w = rcp(Common::MaxLuminance(s4) + _LuminanceBias);
        s = s1 * s1w + s2 * s2w + s3 * s3w + s4 * s4w;
        
        return s * rcp(s1w + s2w + s3w + s4w);
    }
    else {
        s = s1 + s2 + s3 + s4;
        return s * 0.25f;
    }
}

// https://www.iryoku.com/next-generation-post-processing-in-call-of-duty-advanced-warfare/
float3 SampleBox13Down(sampler2D texSampler, float2 texcoord, float2 texelSize, float delta) {
    float x = texelSize.x * delta;
    float y = texelSize.y * delta;

    float3 a = tex2D(texSampler, float2(texcoord.x - 2*x, texcoord.y + 2*y)).rgb;
    float3 b = tex2D(texSampler, float2(texcoord.x,       texcoord.y + 2*y)).rgb;
    float3 c = tex2D(texSampler, float2(texcoord.x + 2*x, texcoord.y + 2*y)).rgb;

    float3 d = tex2D(texSampler, float2(texcoord.x - 2*x, texcoord.y)).rgb;
    float3 e = tex2D(texSampler, float2(texcoord.x,       texcoord.y)).rgb;
    float3 f = tex2D(texSampler, float2(texcoord.x + 2*x, texcoord.y)).rgb;

    float3 g = tex2D(texSampler, float2(texcoord.x - 2*x, texcoord.y - 2*y)).rgb;
    float3 h = tex2D(texSampler, float2(texcoord.x,       texcoord.y - 2*y)).rgb;
    float3 i = tex2D(texSampler, float2(texcoord.x + 2*x, texcoord.y - 2*y)).rgb;

    float3 j = tex2D(texSampler, float2(texcoord.x - x, texcoord.y + y)).rgb;
    float3 k = tex2D(texSampler, float2(texcoord.x + x, texcoord.y + y)).rgb;
    float3 l = tex2D(texSampler, float2(texcoord.x - x, texcoord.y - y)).rgb;
    float3 m = tex2D(texSampler, float2(texcoord.x + x, texcoord.y - y)).rgb;

    float3 s1 = (e)       * 0.125;
    float3 s2 = (a+c+g+i) * 0.03125;
    float3 s3 = (b+d+f+h) * 0.0625;
    float3 s4 = (j+k+l+m) * 0.125;

    float3 s = 0.0f;
    if (_UseKarisAvg) {
        float s1w = rcp(Common::MaxLuminance(s1) + _LuminanceBias);
        float s2w = rcp(Common::MaxLuminance(s2) + _LuminanceBias);
        float s3w = rcp(Common::MaxLuminance(s3) + _LuminanceBias);
        float s4w = rcp(Common::MaxLuminance(s4) + _LuminanceBias);
        s = s1 * s1w + s2 * s2w + s3 * s3w + s4 * s4w;
        return s * rcp(s1w + s2w + s3w + s4w);
    }
    else {
        s = s1 + s2 + s3 + s4;
        return s;
    }
}

float3 SampleBox13Up(sampler2D texSampler, float2 texcoord, float2 texelSize, float delta) {
    float x = texelSize.x * delta;
    float y = texelSize.y * delta;

    float3 a = tex2D(texSampler, float2(texcoord.x - x, texcoord.y + y)).rgb;
    float3 b = tex2D(texSampler, float2(texcoord.x,     texcoord.y + y)).rgb;
    float3 c = tex2D(texSampler, float2(texcoord.x + x, texcoord.y + y)).rgb;

    float3 d = tex2D(texSampler, float2(texcoord.x - x, texcoord.y)).rgb;
    float3 e = tex2D(texSampler, float2(texcoord.x,     texcoord.y)).rgb;
    float3 f = tex2D(texSampler, float2(texcoord.x + x, texcoord.y)).rgb;

    float3 g = tex2D(texSampler, float2(texcoord.x - x, texcoord.y - y)).rgb;
    float3 h = tex2D(texSampler, float2(texcoord.x,     texcoord.y - y)).rgb;
    float3 i = tex2D(texSampler, float2(texcoord.x + x, texcoord.y - y)).rgb;


    float3 s = 0.0f;
    s += e*4.0;
    s += (b+d+f+h)*2.0;
    s += (a+c+g+i);
    s *= 1.0 / 16.0;

    return s;
}

float4 Scale(sampler2D texSampler, float2 texcoord, int sizeFactor, float delta, bool down ) {
    float2 texelSize = float2(1.0f / (BUFFER_WIDTH / sizeFactor), 1.0f / (BUFFER_HEIGHT / sizeFactor));
    float4 pixel = tex2D(texSampler, texcoord);
	float3 color;

    if (_SampleMode == 0) {
        color = pixel.rgb;
    } else if (_SampleMode == 1) {
        color = SampleBox(texSampler, texcoord, texelSize, delta);
    } else if (_SampleMode == 2) {
        if (down == 1) {
            color = SampleBox13Down(texSampler, texcoord, texelSize, delta);
        } else {
            color = SampleBox13Up(texSampler, texcoord, texelSize, delta);
        }
    }

    return float4(color, pixel.a);
}

// Add downscale passes based on BEAN_NUM_DOWNSCALES, see the passes
#if BEAN_NUM_DOWNSCALES > 1
float4 PS_DownScale1(float4 position : SV_Position, float2 texcoord : TexCoord) : SV_Target { return Scale(Half, texcoord, 2, _Delta, 1); }
#if BEAN_NUM_DOWNSCALES > 2
float4 PS_DownScale2(float4 position : SV_Position, float2 texcoord : TexCoord) : SV_Target { return Scale(Quarter, texcoord, 4, _Delta, 1); }
#if BEAN_NUM_DOWNSCALES > 3
float4 PS_DownScale3(float4 position : SV_Position, float2 texcoord : TexCoord) : SV_Target { return Scale(Eighth, texcoord, 8, _Delta, 1); }
#if BEAN_NUM_DOWNSCALES > 4
float4 PS_DownScale4(float4 position : SV_Position, float2 texcoord : TexCoord) : SV_Target { return Scale(Sixteenth, texcoord, 16, _Delta, 1); }
#if BEAN_NUM_DOWNSCALES > 5
float4 PS_DownScale5(float4 position : SV_Position, float2 texcoord : TexCoord) : SV_Target { return Scale(ThirtySecondth, texcoord, 32, _Delta, 1); }
#if BEAN_NUM_DOWNSCALES > 6
float4 PS_DownScale6(float4 position : SV_Position, float2 texcoord : TexCoord) : SV_Target { return Scale(SixtyFourth, texcoord, 64, _Delta, 1); }
#if BEAN_NUM_DOWNSCALES > 7
float4 PS_DownScale7(float4 position : SV_Position, float2 texcoord : TexCoord) : SV_Target { return Scale(OneTwentyEighth, texcoord, 128, _Delta, 1); }

float4 PS_UpScale7(float4 position : SV_Position, float2 texcoord : TexCoord) : SV_Target { return Scale(TwoFiftySixth, texcoord, 256, _Delta, 0); }
#endif
float4 PS_UpScale6(float4 position : SV_Position, float2 texcoord : TexCoord) : SV_Target { return Scale(OneTwentyEighth, texcoord, 128, _Delta, 0); }
#endif
float4 PS_UpScale5(float4 position : SV_Position, float2 texcoord : TexCoord) : SV_Target { return Scale(SixtyFourth, texcoord, 64, _Delta, 0); }
#endif
float4 PS_UpScale4(float4 position : SV_Position, float2 texcoord : TexCoord) : SV_Target { return Scale(ThirtySecondth, texcoord, 32, _Delta, 0); }
#endif
float4 PS_UpScale3(float4 position : SV_Position, float2 texcoord : TexCoord) : SV_Target { return Scale(Sixteenth, texcoord, 16, _Delta, 0); }
#endif
float4 PS_UpScale2(float4 position : SV_Position, float2 texcoord : TexCoord) : SV_Target { return Scale(Eighth, texcoord, 8, _Delta, 0); }
#endif
float4 PS_UpScale1(float4 position : SV_Position, float2 texcoord : TexCoord) : SV_Target { return Scale(Quarter, texcoord, 4, _Delta, 0); }
#endif

float4 PS_PreFilter(float4 position : SV_Position, float2 texcoord : TexCoord) : SV_Target
{
    float3 color = Scale(Common::BeanBuffer, texcoord, 1, 1.0f, 1).rgb;
    float2 texelSize = float2(BUFFER_RCP_WIDTH, BUFFER_RCP_HEIGHT);

    // Ignore Skybox and edges between foreground and skybox
    bool SkyMask = ReShade::GetLinearizedDepth(texcoord) < 0.98f;
    bool leftDepth = ReShade::GetLinearizedDepth(texcoord + texelSize * float2(-1, 0)) < 1.0f;
    bool rightDepth = ReShade::GetLinearizedDepth(texcoord + texelSize * float2(1, 0)) < 1.0f;
    bool upDepth = ReShade::GetLinearizedDepth(texcoord + texelSize * float2(0, -1)) < 1.0f;
    bool downDepth = ReShade::GetLinearizedDepth(texcoord + texelSize * float2(0, 1)) < 1.0f;
    SkyMask *= leftDepth * rightDepth * upDepth * downDepth;

    color = Prefilter(pow(abs(color), 2.2f)) * SkyMask;
	return float4(color, 1.0f);
}

float4 PS_Bloom(float4 position : SV_Position, float2 texcoord : TexCoord) : SV_Target
{
    float4 pixel = tex2D(Common::BeanBuffer, texcoord);
	float3 color = pixel.rgb;

    float3 bloom = Scale(Half, texcoord, 2, 1.0f, 0).rgb;
    bloom = _Intensity * pow(abs(bloom), 1.0f / 2.2f);

    if (_BlendMode == 0) {
        color += bloom;
    } else if (_BlendMode == 1) {
        color = 1.0f - (1.0f - color) * (1.0f - bloom);
    } else if (_BlendMode == 2) {
        color = color / max(0.01f, (1.0f - (bloom - 0.001f)));
    }
    
    if (_Debug) {
        return float4(bloom, pixel.a);
    }

    return float4(color, pixel.a);
}

technique Bean_Bloom
{
    pass Prefilter 
    {
        RenderTarget = HalfTex;
        VertexShader = PostProcessVS;
		PixelShader = PS_PreFilter;
    }
    #if BEAN_NUM_DOWNSCALES > 1
    pass Down1
    {
        RenderTarget = QuarterTex;
        VertexShader = PostProcessVS;
	    PixelShader = PS_DownScale1;
    } 
    #if BEAN_NUM_DOWNSCALES > 2
    pass Down2
    {
        RenderTarget = EighthTex;
        VertexShader = PostProcessVS;
	    PixelShader = PS_DownScale2;
    } 
    #if BEAN_NUM_DOWNSCALES > 3
    pass Down3
    {
        RenderTarget = SixteenthTex;
        VertexShader = PostProcessVS;
	    PixelShader = PS_DownScale3;
    } 
    #if BEAN_NUM_DOWNSCALES > 4
    pass Down4
    {
        RenderTarget = ThirtySecondthTex;
        VertexShader = PostProcessVS;
	    PixelShader = PS_DownScale4;
    } 
    #if BEAN_NUM_DOWNSCALES > 5
    pass Down5
    {
        RenderTarget = SixtyFourthTex;
        VertexShader = PostProcessVS;
	    PixelShader = PS_DownScale5;
    } 
    #if BEAN_NUM_DOWNSCALES > 6
    pass Down6
    {
        RenderTarget = OneTwentyEighthTex;
        VertexShader = PostProcessVS;
	    PixelShader = PS_DownScale6;
    } 
    #if BEAN_NUM_DOWNSCALES > 7
    pass Down7
    {
        RenderTarget = TwoFiftySixthTex;
        VertexShader = PostProcessVS;
	    PixelShader = PS_DownScale7;
    } 
    pass Up7
    {
        RenderTarget = OneTwentyEighthTex;
        VertexShader = PostProcessVS;
	    PixelShader = PS_UpScale7;
    }
    #endif
    pass Up6
    {
        RenderTarget = SixtyFourthTex;
        VertexShader = PostProcessVS;
	    PixelShader = PS_UpScale6;
    }
    #endif
    pass Up5
    {
        RenderTarget = ThirtySecondthTex;
        VertexShader = PostProcessVS;
	    PixelShader = PS_UpScale5;
    }
    #endif
    pass Up4
    {
        RenderTarget = SixteenthTex;
        VertexShader = PostProcessVS;
	    PixelShader = PS_UpScale4;
    }
    #endif
    pass Up3
    {
        RenderTarget = EighthTex;
        VertexShader = PostProcessVS;
	    PixelShader = PS_UpScale3;
    }
    #endif
    pass Up2
    {
        RenderTarget = QuarterTex;
        VertexShader = PostProcessVS;
	    PixelShader = PS_UpScale2;
    }
    #endif
    pass Up1
    {
        RenderTarget = HalfTex;
        VertexShader = PostProcessVS;
	    PixelShader = PS_UpScale1;
    }
    #endif
	pass
	{
        RenderTarget = Common::BeanBufferTexTemp;
		VertexShader = PostProcessVS;
		PixelShader = PS_Bloom;
	}
    pass End
    {
        RenderTarget = Common::BeanBufferTex;
        VertexShader = PostProcessVS;
		PixelShader = Common::PS_EndPass;
    }
}