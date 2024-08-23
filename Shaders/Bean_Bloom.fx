#include "ReShade.fxh"
#include "Bean_Common.fxh"

#ifndef BEAN_NUM_DOWNSCALES
    #define BEAN_NUM_DOWNSCALES 0
#endif

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

uniform float _Delta <
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
storage2D s_Half { Texture = HalfTex; };

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

float4 Scale(sampler2D texSampler, float2 texcoord, int sizeFactor, float delta) {
    float2 texelSize = float2(1.0f / (BUFFER_WIDTH / sizeFactor), 1.0f / (BUFFER_HEIGHT / sizeFactor));
    float4 pixel = tex2D(Common::BeanBuffer, texcoord);
	float3 color = pixel.rgb;
    return float4(color, pixel.a);
}

// Add downscale passes based on BEAN_NUM_DOWNSCALES, see the passes
#if BEAN_NUM_DOWNSCALES > 1
float4 PS_DownScale1(float4 position : SV_Position, float2 texcoord : TexCoord) : SV_Target { return Scale(Half, texcoord, 2, _Delta); }
#if BEAN_NUM_DOWNSCALES > 2
float4 PS_DownScale2(float4 position : SV_Position, float2 texcoord : TexCoord) : SV_Target { return Scale(Quarter, texcoord, 4, _Delta); }
#if BEAN_NUM_DOWNSCALES > 3
float4 PS_DownScale3(float4 position : SV_Position, float2 texcoord : TexCoord) : SV_Target { return Scale(Eighth, texcoord, 8, _Delta); }
#if BEAN_NUM_DOWNSCALES > 4
float4 PS_DownScale4(float4 position : SV_Position, float2 texcoord : TexCoord) : SV_Target { return Scale(Sixteenth, texcoord, 16, _Delta); }
#if BEAN_NUM_DOWNSCALES > 5
float4 PS_DownScale5(float4 position : SV_Position, float2 texcoord : TexCoord) : SV_Target { return Scale(ThirtySecondth, texcoord, 32, _Delta); }
#if BEAN_NUM_DOWNSCALES > 6
float4 PS_DownScale6(float4 position : SV_Position, float2 texcoord : TexCoord) : SV_Target { return Scale(SixtyFourth, texcoord, 64, _Delta); }
#if BEAN_NUM_DOWNSCALES > 7
float4 PS_DownScale7(float4 position : SV_Position, float2 texcoord : TexCoord) : SV_Target { return Scale(OneTwentyEighth, texcoord, 128, _Delta); }

float4 PS_UpScale7(float4 position : SV_Position, float2 texcoord : TexCoord) : SV_Target { return Scale(TwoFiftySixth, texcoord, 256, _Delta); }
#endif
float4 PS_UpScale6(float4 position : SV_Position, float2 texcoord : TexCoord) : SV_Target { return Scale(OneTwentyEighth, texcoord, 128, _Delta); }
#endif
float4 PS_UpScale5(float4 position : SV_Position, float2 texcoord : TexCoord) : SV_Target { return Scale(SixtyFourth, texcoord, 64, _Delta); }
#endif
float4 PS_UpScale4(float4 position : SV_Position, float2 texcoord : TexCoord) : SV_Target { return Scale(ThirtySecondth, texcoord, 32, _Delta); }
#endif
float4 PS_UpScale3(float4 position : SV_Position, float2 texcoord : TexCoord) : SV_Target { return Scale(Sixteenth, texcoord, 16, _Delta); }
#endif
float4 PS_UpScale2(float4 position : SV_Position, float2 texcoord : TexCoord) : SV_Target { return Scale(Eighth, texcoord, 8, _Delta); }
#endif
float4 PS_UpScale1(float4 position : SV_Position, float2 texcoord : TexCoord) : SV_Target { return Scale(Quarter, texcoord, 4, _Delta); }
#endif

float4 PS_PreFilter(float4 position : SV_Position, float2 texcoord : TexCoord) : SV_Target
{
    float3 color = tex2D(Common::BeanBuffer, texcoord).rgb;
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

    float3 bloom = tex2D(Half, texcoord).rgb;
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