#include "ReShade.fxh"
#include "Bean_Common.fxh"

uniform int _TonemapMode <
    ui_type = "combo";
    ui_label = "Tonemap Mode";
    ui_items = "RGB Clamp\0"
               "Hill ACES\0"
               "Narkowicz ACES\0"
               "Reinhard Extended\0"
               "Hable\0";
> = 0;

uniform float _Cwhite <
    ui_category_closed = true;
    ui_category = "Reinhard Extended";
    ui_min = 0.0f; ui_max = 10.0f;
    ui_label = "White Point";
    ui_type = "drag";
    ui_tooltip = "Adjust white point of the screen.";
> = 1.0f;

uniform float _A <
    ui_category_closed = true;
    ui_category = "Hable";
    ui_min = 0.0f; ui_max = 1.0f;
    ui_label = "Shoulder Strength";
    ui_type = "drag";
    ui_tooltip = "Adjust shoulder strength of film curve.";
> = 0.15f;

uniform float _B <
    ui_category_closed = true;
    ui_category = "Hable";
    ui_min = 0.0f; ui_max = 1.0f;
    ui_label = "Linear Strength";
    ui_type = "drag";
    ui_tooltip = "Adjust linear strength of film curve.";
> = 0.5f;

uniform float _C <
    ui_category_closed = true;
    ui_category = "Hable";
    ui_min = 0.0f; ui_max = 1.0f;
    ui_label = "Linear Angle";
    ui_type = "drag";
    ui_tooltip = "Adjust linear angle of film curve.";
> = 0.1f;

uniform float _D <
    ui_category_closed = true;
    ui_category = "Hable";
    ui_min = 0.0f; ui_max = 1.0f;
    ui_label = "Toe Strength";
    ui_type = "drag";
    ui_tooltip = "Adjust toe strength of film curve.";
> = 0.2f;

uniform float _E <
    ui_category_closed = true;
    ui_category = "Hable";
    ui_min = 0.0f; ui_max = 1.0f;
    ui_label = "Toe Numerator";
    ui_type = "drag";
    ui_tooltip = "Adjust toe numerator of film curve.";
> = 0.02f;

uniform float _F <
    ui_category_closed = true;
    ui_category = "Hable";
    ui_min = 0.0f; ui_max = 1.0f;
    ui_label = "Toe Denominator";
    ui_type = "drag";
    ui_tooltip = "Adjust toe denominator of film curve.";
> = 0.3f;

uniform float _W <
    ui_category_closed = true;
    ui_category = "Hable";
    ui_min = 0.0f; ui_max = 60.0f;
    ui_label = "Linear White Point";
    ui_type = "drag";
    ui_tooltip = "Adjust linear white point of film curve.";
> = 11.2f;

uniform bool _DebugHDR <
    ui_category_closed = true;
    ui_category = "Advanced settings";
    ui_label = "Debug HDR";
    ui_tooltip = "Show values in hdr (> 1)";
> = false;

static const float3x3 ACESInputMat = float3x3(
    float3(0.59719, 0.35458, 0.04823),
    float3(0.07600, 0.90834, 0.01566),
    float3(0.02840, 0.13383, 0.83777)
);

static const float3x3 ACESOutputMat = float3x3(
    float3( 1.60475, -0.53108, -0.07367),
    float3(-0.10208,  1.10813, -0.00605),
    float3(-0.00327, -0.07276,  1.07602)
);

float3 RRTAndODTFit(float3 v) {
    float3 a = v * (v + 0.0245786f) - 0.000090537f;
    float3 b = v * (0.983729f * v + 0.4329510f) + 0.238081f;
    return a / b;
}

float3 HillACES(float3 col) {
    col = mul(ACESInputMat, col);
    col = RRTAndODTFit(col);
    return saturate(mul(ACESOutputMat, col));
}

float3 NarkowiczACES(float3 col) {
    return saturate((col * (2.51f * col + 0.03f)) / (col * (2.43f * col + 0.59f) + 0.14f));
}

float3 ReinhardExtended(float3 col) {
    float Lin = Common::Luminance(col);
    float3 Lout = (Lin * (1.0f + Lin / (_Cwhite * _Cwhite))) / (1.0f + Lin);
    float3 Cout = col / Lin * Lout;
    return saturate(Cout);
}

float3 Uncharted2Tonemap(float3 col) {
    return ((col * (_A * col + _C * _B) + _D * _E) / (col * (_A * col + _B) + _D * _F)) - _E / _F;
}

float3 Hable(float3 col) {
    float ExposureBias = 2.0f;
    float3 curr = ExposureBias * Uncharted2Tonemap(col);
    float3 whiteScale = 1.0f / Uncharted2Tonemap(float3(_W, _W, _W));
    float3 Cout = curr * whiteScale;
    return saturate(Cout);
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

    if (_TonemapMode == 0)
        color = saturate(color);
    else if (_TonemapMode == 1)
        color = HillACES(color);
    else if (_TonemapMode == 2)
        color = NarkowiczACES(color);
    else if (_TonemapMode == 3)
        color = ReinhardExtended(color);
    else if (_TonemapMode == 4)
        color = Hable(color);

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