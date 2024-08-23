#include "ReShade.fxh"
#include "Bean_Common.fxh"

#ifndef SKY_SOURCE
#define SKY_SOURCE "crash1.png"
#endif
#ifndef SKY_SIZE_X
#define SKY_SIZE_X BUFFER_WIDTH
#endif
#ifndef SKY_SIZE_Y
#define SKY_SIZE_Y BUFFER_HEIGHT
#endif

uniform float2 _Position < 
    ui_min = 0.0; ui_max = 1.0;
    ui_label = "Position";
    ui_type = "drag";
    ui_step = (1.0 / 200.0);
> = float2(0.5, 0.5);

uniform float _Scale < 
    ui_min = (1.0 / 100.0); ui_max = 4.0;
    ui_label = "Scale";
    ui_type = "drag";
    ui_step = (1.0 / 250.0);
> = 1.0;

uniform float _Blend < 
    ui_min = 0.0; ui_max = 1.0;
    ui_label = "Blend";
    ui_type = "drag";
    ui_step = (1.0 / 255.0); // for slider and drag
> = 1.0;

texture2D SkyTex <
    source = SKY_SOURCE;
> {
    Format = RGBA8;
    Width  = SKY_SIZE_X;
    Height = SKY_SIZE_Y;
};
sampler2D SkySampler { Texture = SkyTex; };

float3 PS_ReplaceSky(float4 position : SV_Position, float2 texcoord : TexCoord) : SV_Target
{
	float3 color = tex2D(ReShade::BackBuffer, texcoord).rgb;

    float depth = ReShade::GetLinearizedDepth(texcoord);

    if (depth > 0.99f) {
        const float2 pixelSize = 1.0 / (float2(SKY_SIZE_X, SKY_SIZE_Y) * _Scale / BUFFER_SCREEN_SIZE);
        const float4 layer     = tex2D(SkySampler, texcoord * pixelSize + _Position * (1.0 - pixelSize));

        color = lerp(color, layer.rgb, layer.a * _Blend);
    }

	return color;
}

technique Bean_ReplaceSky
{
	pass
	{
		VertexShader = PostProcessVS;
		PixelShader = PS_ReplaceSky;
	}
}