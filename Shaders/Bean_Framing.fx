#include "ReShade.fxh"
#include "Bean_Common.fxh"

uniform int _Shape < 
    ui_type = "combo";
    ui_label = "Shape";
    ui_items = "Rectangle\0"
                "Circle\0";
> = 0;

uniform float3 _Color <
    ui_type = "color";
    ui_label = "Frame Color";
> = 0.0f;

uniform float _Alpha <
    ui_min = 0f; ui_max = 1.0f;
    ui_type = "drag";
    ui_label = "Frame Alpha";
> = 1.0f;

uniform float2 _Radius <
    ui_min = 0f; ui_max = BUFFER_WIDTH;
    ui_label = "Shape Dimensions";
    ui_type = "drag";
    ui_step = 0.5f;
> = 500.0f;

uniform int2 _Offset <
    ui_type = "drag";
    ui_label = "Position";
> = 0;

uniform float _Theta <
    ui_min = -180.0f; ui_max = 180.0f;
    ui_label = "Rotation";
    ui_type = "drag";
    ui_step = 0.5f;
> = 0;


uniform float _DepthCutoff <
    ui_min = 0f; ui_max = 1.0f;
    ui_type = "drag";
    ui_label = "Depth Cutoff";
> = 0.0f;

float4 PS_Framing(float4 position : SV_Position, float2 texcoord : TexCoord) : SV_Target
{
	float4 pixel = tex2D(Common::BeanBuffer, texcoord);
	float3 color = pixel.rgb;
    float depth = ReShade::GetLinearizedDepth(texcoord);

    if (depth <= _DepthCutoff) {
        return float4(color, pixel.a);
    }

    float2 center = float2(BUFFER_WIDTH / 2, BUFFER_HEIGHT / 2) + _Offset;
    float theta = radians(_Theta);
    float2x2 rotationMatrix = float2x2(float2(cos(theta), -sin(theta)), float2(sin(theta), cos (theta)));
    float alpha = 0.0f;

    if (_Shape == 0) {
        float2 M = position.xy;
        float2 A = mul(rotationMatrix, float2(- _Radius.x, - _Radius.y)) + center;
        float2 B = mul(rotationMatrix, float2(  _Radius.x, -  _Radius.y)) + center;
        float2 D = mul(rotationMatrix, float2(- _Radius.x,    _Radius.y)) + center;
        float2 AM = M - A;
        float2 AB = B - A;
        float2 AD = D - A;
        alpha = 0 < dot(AM, AB) && dot(AM, AB) < dot(AB, AB) && 0 < dot(AM, AD) && dot(AM, AD) < dot(AD, AD);
    } else if (_Shape == 1) {
        float2 M = mul(rotationMatrix, position.xy - center ) + center;
        float2 C = center;
        alpha = (((M.x - C.x) * (M.x - C.x)) / (_Radius.x * _Radius.x) + ((M.y - C.y) * (M.y - C.y)) / (_Radius.y * _Radius.y)) < 1;
    }
    alpha = 1.0f - alpha;
    alpha *= _Alpha;
    color = lerp(color, _Color, alpha);
	return float4(color, pixel.a);
}

technique Bean_Framing
{
	pass
	{
        RenderTarget = Common::BeanBufferTexTemp;
		VertexShader = PostProcessVS;
		PixelShader = PS_Framing;
	}
    pass
	{
		RenderTarget = Common::BeanBufferTex;
		VertexShader = PostProcessVS;
		PixelShader = Common::PS_EndPass;
	}
}