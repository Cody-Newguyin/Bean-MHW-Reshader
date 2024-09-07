#include "ReShade.fxh"
#include "Bean_Common.fxh"

uniform float3 _Color <
    ui_type = "color";
    ui_label = "Color";
> = 0.0f;

uniform float _Intensity <
    ui_min = 0f; ui_max = 5.0f;
    ui_label = "Intensity";
    ui_type = "slider";
> = 1.0f;

uniform float _Smoothness <
    ui_min = 0.01f; ui_max = 10.0f;
    ui_label = "Smoothness";
    ui_type = "slider";
> = 1.0f;


// uniform float _Inner <
//     ui_min = 0f; ui_max = 1.0f;
//     ui_label = "Inner Radius";
//     ui_type = "slider";
// > = 0.1f;

// uniform float _Outer <
//     ui_min = 0f; ui_max = 1.0f;
//     ui_label = "Outer Radius";
//     ui_type = "slider";
// > = 1.0f;

// uniform float _Dither <
//     ui_min = 0f; ui_max = 1.0f;
//     ui_label = "Dither Strength";
//     ui_type = "slider";
// > = 0.03f;

float4 PS_Vignette(float4 position : SV_Position, float2 texcoord : TexCoord) : SV_Target
{
	float4 pixel = tex2D(Common::BeanBuffer, texcoord);
	float3 color = pixel.rgb;

    float2 dist = abs(texcoord - float2(0.5f, 0.5f)) * _Intensity;
    float vignette = saturate(dot(dist, dist)) * _Smoothness;

    color = lerp(color, _Color, vignette);

    // https://godotshaders.com/shader/vignette-with-reduced-banding-artifacts/
    // float dist = distance(texcoord, float2(0.5f, 0.5f));
	
	// float vignette = smoothstep(_Inner, _Outer, dist) * _Intensity;
	// float dither = frac(sin(dot(texcoord, float2(12.9898f, 78.233f))) * 43758.5453123f) * _Dither;
	
    // color = lerp(color, _Color, vignette + dither); 

	return float4(color, pixel.a);
}

technique Bean_Vignette
{
	pass
	{
		RenderTarget = Common::BeanBufferTexTemp;
		VertexShader = PostProcessVS;
		PixelShader = PS_Vignette;
	}
	pass
	{
		RenderTarget = Common::BeanBufferTex;
		VertexShader = PostProcessVS;
		PixelShader = Common::PS_EndPass;
	}
}