#include "ReShade.fxh"
#include "Bean_Common.fxh"

uniform int _FogMode < 
    ui_type = "combo";
    ui_label = "Mode";
    ui_items = "Linear\0"
                "Exp\0"
                "Exp2\0";
> = 2;

uniform float3 _FogColor <
    ui_min = 0.0f; ui_max = 1.0f;
    ui_label = "Color";
    ui_type = "color";
> = float3(1.0f, 1.0f, 1.0f);

uniform float _Density <
    ui_min = 0.0f; ui_max = 0.05f;
    ui_label = "Density";
    ui_type = "slider";
> = 0.001f;

uniform bool _SampleSky <
    ui_label = "Sample Sky";
> = true;

uniform float _ProjectionNear <
    ui_min = 0.0f; ui_max = 5000.0f;
    ui_label = "Projection Near";
    ui_type = "slider";
> = 0.0f;

uniform float _ProjectionFar <
    ui_min = 0.0f; ui_max = 5000.0f;
    ui_label = "Projection Far";
    ui_type = "slider";
> = 1000.0f;

float4 PS_Fog(float4 position : SV_Position, float2 texcoord : TexCoord) : SV_Target
{
	float4 pixel = tex2D(Common::BeanBuffer, texcoord);
	float3 color = pixel.rgb;
    float depth = ReShade::GetLinearizedDepth(texcoord);
    float viewDistance = max(0.0f, depth * _ProjectionFar - _ProjectionNear);

    float fogFactor = 0.0f;

    if (_FogMode == 0) {
        fogFactor = viewDistance / _ProjectionFar;
    } else if (_FogMode == 1) {
        fogFactor = viewDistance * (_Density / log(2));
        fogFactor = 1.0f - exp2(-fogFactor);
    } else if (_FogMode == 2) {
        fogFactor = viewDistance * (_Density / sqrt(log(2)));
        fogFactor = 1.0f - exp2(-fogFactor * fogFactor);
    }

    if (depth > 0.99f && !_SampleSky) {
        fogFactor = 1.0f;
    }

    color = lerp(color, _FogColor, saturate(fogFactor));
	return float4(color, pixel.a);
}

technique Bean_Fog
{
	pass
	{
		VertexShader = PostProcessVS;
		PixelShader = PS_Fog;
	}
}