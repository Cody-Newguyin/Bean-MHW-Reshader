#include "ReShade.fxh"
#include "Bean_Common.fxh"

uniform float _FocalPlaneDistance <
    ui_min = 0.0f; ui_max = 1000.0f;
	ui_step = 0.5f;
    ui_label = "Focal Plane";
    ui_type = "slider";
> = 20.0f;

uniform float _FocusRange <
    ui_min = 0.0f; ui_max = 1000.0f;
	ui_step = 0.5f;
    ui_label = "Focus Range";
    ui_type = "slider";
> = 100.0f;

uniform float _BokehDelta <
    ui_min = 0.25f; ui_max = 3.0f;
    ui_label = "Bokeh Sampling Delta";
    ui_type = "drag";
> = 1.0f;

uniform int _NearBorder <
    ui_category = "Advanced Settings";
    ui_category_closed = true;
    ui_min = 0; ui_max = 10;
    ui_label = "Near CoC Border Size";
    ui_type = "slider";
> = 3;

uniform int _FillRange <
    ui_category = "Advanced Settings";
    ui_category_closed = true;
    ui_min = 0; ui_max = 10;
    ui_label = "Bokeh Fill Size";
    ui_type = "slider";
> = 1;

#ifndef BEAN_COC_DOWNSAMPLE
    #define BEAN_COC_DOWNSAMPLE 0
#endif

#ifndef BEAN_BOKEH_DOWNSAMPLE
	#define BEAN_BOKEH_DOWNSAMPLE 0
#endif

#ifndef BEAN_BOKEH_POST
	#define BEAN_BOKEH_POST 0
#endif

texture2D CoCTex { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RG8; };
sampler2D CoC { Texture = CoCTex; MagFilter = POINT; MinFilter = POINT; MipFilter = POINT;};

texture2D CoCTempTex { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RG8; };
sampler2D CoCTemp { Texture = CoCTempTex; MagFilter = POINT; MinFilter = POINT; MipFilter = POINT;};

#if BEAN_COC_DOWNSAMPLE 
	texture2D CoCHalfTex {
		Width = BUFFER_WIDTH / 2;
		Height = BUFFER_HEIGHT / 2;
		Format = R8;
	}; sampler2D CoCHalf { Texture = CoCHalfTex; };
	
	texture2D CoCQuarterTex {
		Width = BUFFER_WIDTH / 4;
		Height = BUFFER_HEIGHT / 4;
		Format = R8;
	}; sampler2D CoCQuarter { Texture = CoCQuarterTex; };

	float SampleBox(sampler2D texSampler, float2 texcoord, int sizeFactor) {
		float2 texelSize = float2(BUFFER_RCP_WIDTH, BUFFER_RCP_HEIGHT) * sizeFactor;
		float4 o = texelSize.xyxy * float2(-1, 1).xxyy;
		float s1 = tex2D(texSampler, texcoord + o.xy).r;
		float s2 = tex2D(texSampler, texcoord + o.zy).r;
		float s3 = tex2D(texSampler, texcoord + o.xw).r;
		float s4 = tex2D(texSampler, texcoord + o.zw).r;

		return (s1 + s2 + s3 + s4) / 4.0f;
	}

	float PS_CoCDownHalf(float4 position : SV_Position, float2 texcoord : TexCoord) : SV_Target { return SampleBox(CoC, texcoord, 1); }

	float PS_CoCDownQuarter(float4 position : SV_Position, float2 texcoord : TexCoord) : SV_Target { return SampleBox(CoCHalf, texcoord, 2); }

	float PS_CoCUpQuarter(float4 position : SV_Position, float2 texcoord : TexCoord) : SV_Target { return SampleBox(CoCQuarter, texcoord, 4); }

	float2 PS_CoCUpHalf(float4 position : SV_Position, float2 texcoord : TexCoord) : SV_Target { 
		float farCoC = tex2D(CoCTemp, texcoord).g;
		float nearCoC =  SampleBox(CoCHalf, texcoord, 2);
		return float2(nearCoC, farCoC); 
	}
#endif

#if BEAN_BOKEH_DOWNSAMPLE
	texture2D MainHalfTex {
		Width = BUFFER_WIDTH / 2;
		Height = BUFFER_HEIGHT / 2;
		Format = RGBA16F;
	}; sampler2D MainHalf { Texture = MainHalfTex; };

	texture2D BokehHalfTex {
		Width = BUFFER_WIDTH / 2;
		Height = BUFFER_HEIGHT / 2;
		Format = RGBA16F;
	}; sampler2D BokehHalf { Texture = BokehHalfTex; };

	float4 PS_MainDownHalf(float4 position : SV_Position, float2 texcoord : TexCoord) : SV_Target { return tex2D(Common::BeanBuffer, texcoord); }

	float4 PS_BokehUpHalf(float4 position : SV_Position, float2 texcoord : TexCoord) : SV_Target { return tex2D(BokehHalf, texcoord); }
#endif

texture2D BokehTex {
    Width = BUFFER_WIDTH;
    Height = BUFFER_HEIGHT;
    Format = RGBA16F;
}; sampler2D Bokeh { Texture = BokehTex; };

texture2D BokehTempTex {
    Width = BUFFER_WIDTH;
    Height = BUFFER_HEIGHT;
    Format = RGBA16F;
}; sampler2D BokehTemp { Texture = BokehTempTex; };

float2 PS_CoC(float4 position : SV_Position, float2 texcoord : TexCoord) : SV_Target
{
	float depth = ReShade::GetLinearizedDepth(texcoord) * 1000.0f;

	float nearStart = max(0.0f, _FocalPlaneDistance - _FocusRange);
    float nearEnd = _FocalPlaneDistance;
    float farStart = _FocalPlaneDistance;
    float farEnd = _FocalPlaneDistance + _FocusRange;

	float near = 0.0f;
	if (near < nearEnd) 
		near = 1.0f - (depth - nearStart) / (nearEnd - nearStart);
	float far = 0.0f;
   	if (depth > farStart)
        far = (depth - farStart) / (farEnd - farStart);

	return saturate(float2(near, far));
}

float2 PS_ExpandCoCHorizontal(float4 position : SV_Position, float2 texcoord : TexCoord) : SV_Target
{
	float2 coc = tex2D(CoC, texcoord).rg;
	float2 texelSize = float2(BUFFER_RCP_WIDTH, BUFFER_RCP_HEIGHT);

	float maxCoC = coc.r;
	float2 offset;
	[loop]
	for (int x = -_NearBorder; x <= _NearBorder; x++) {
		if (x == 0) continue;
		offset = float2(x, 0) * texelSize.x;
		maxCoC = max(maxCoC, tex2D(CoC, texcoord + offset).r);
	}
	return float2(maxCoC, coc.g);
}

float2 PS_ExpandCoCVertical(float4 position : SV_Position, float2 texcoord : TexCoord) : SV_Target
{
	float2 coc = tex2D(CoCTemp, texcoord).rg;
	float2 texelSize = float2(BUFFER_RCP_WIDTH, BUFFER_RCP_HEIGHT);

	float maxCoC = coc.r;
	float2 offset;
	[loop]
	for (int y = -_NearBorder; y <= _NearBorder; y++) {
		if (y == 0) continue;
		offset = float2(0, y) * texelSize.y;
		maxCoC = max(maxCoC, tex2D(CoCTemp, texcoord + offset).r);
	}
	return float2(maxCoC, coc.g);
}

float2 PS_BlurCoCHorizontal(float4 position : SV_Position, float2 texcoord : TexCoord) : SV_Target
{
	float2 coc = tex2D(CoC, texcoord).rg;
	float2 texelSize = float2(BUFFER_RCP_WIDTH, BUFFER_RCP_HEIGHT);

	float nearCoC = coc.r;
	float2 offset;
	[loop]
	for (int x = -_NearBorder; x <= _NearBorder; x++) {
		if (x == 0) continue;
		offset = float2(x, 0) * texelSize.x;
		nearCoC += tex2D(CoC, texcoord + offset).r;
	}
	nearCoC /= (_NearBorder * 2 + 1);
	return float2(nearCoC, coc.g);
}

float2 PS_BlurCoCVertical(float4 position : SV_Position, float2 texcoord : TexCoord) : SV_Target
{
	float2 coc = tex2D(CoCTemp, texcoord).rg;
	float2 texelSize = float2(BUFFER_RCP_WIDTH, BUFFER_RCP_HEIGHT);

	float nearCoC = coc.r;
	float2 offset;
	[loop]
	for (int y = -_NearBorder; y <= _NearBorder; y++) {
		if (y == 0) continue;
		offset = float2(0, y) * texelSize.y;
		nearCoC += tex2D(CoCTemp, texcoord + offset).r;
	}
	nearCoC /= (_NearBorder * 2 + 1);
	return float2(nearCoC, coc.g);
}

// Circular Kernel from GPU Zen 'Practical Gather-based Bokeh Depth of Field' by Wojciech Sterna
static const float2 offsets48[] =
{
	2.0f * float2(1.000000f, 0.000000f),
	2.0f * float2(0.707107f, 0.707107f),
	2.0f * float2(-0.000000f, 1.000000f),
	2.0f * float2(-0.707107f, 0.707107f),
	2.0f * float2(-1.000000f, -0.000000f),
	2.0f * float2(-0.707106f, -0.707107f),
	2.0f * float2(0.000000f, -1.000000f),
	2.0f * float2(0.707107f, -0.707107f),
	
	4.0f * float2(1.000000f, 0.000000f),
	4.0f * float2(0.923880f, 0.382683f),
	4.0f * float2(0.707107f, 0.707107f),
	4.0f * float2(0.382683f, 0.923880f),
	4.0f * float2(-0.000000f, 1.000000f),
	4.0f * float2(-0.382684f, 0.923879f),
	4.0f * float2(-0.707107f, 0.707107f),
	4.0f * float2(-0.923880f, 0.382683f),
	4.0f * float2(-1.000000f, -0.000000f),
	4.0f * float2(-0.923879f, -0.382684f),
	4.0f * float2(-0.707106f, -0.707107f),
	4.0f * float2(-0.382683f, -0.923880f),
	4.0f * float2(0.000000f, -1.000000f),
	4.0f * float2(0.382684f, -0.923879f),
	4.0f * float2(0.707107f, -0.707107f),
	4.0f * float2(0.923880f, -0.382683f),

	6.0f * float2(1.000000f, 0.000000f),
	6.0f * float2(0.965926f, 0.258819f),
	6.0f * float2(0.866025f, 0.500000f),
	6.0f * float2(0.707107f, 0.707107f),
	6.0f * float2(0.500000f, 0.866026f),
	6.0f * float2(0.258819f, 0.965926f),
	6.0f * float2(-0.000000f, 1.000000f),
	6.0f * float2(-0.258819f, 0.965926f),
	6.0f * float2(-0.500000f, 0.866025f),
	6.0f * float2(-0.707107f, 0.707107f),
	6.0f * float2(-0.866026f, 0.500000f),
	6.0f * float2(-0.965926f, 0.258819f),
	6.0f * float2(-1.000000f, -0.000000f),
	6.0f * float2(-0.965926f, -0.258820f),
	6.0f * float2(-0.866025f, -0.500000f),
	6.0f * float2(-0.707106f, -0.707107f),
	6.0f * float2(-0.499999f, -0.866026f),
	6.0f * float2(-0.258819f, -0.965926f),
	6.0f * float2(0.000000f, -1.000000f),
	6.0f * float2(0.258819f, -0.965926f),
	6.0f * float2(0.500000f, -0.866025f),
	6.0f * float2(0.707107f, -0.707107f),
	6.0f * float2(0.866026f, -0.499999f),
	6.0f * float2(0.965926f, -0.258818f),
};

float4 PS_BokehBlur(float4 position : SV_Position, float2 texcoord : TexCoord) : SV_Target { 
	// In the downsampled bokeh the higher texel size counteracts the lower delta 
	float2 texelSize = float2(BUFFER_RCP_WIDTH, BUFFER_RCP_HEIGHT);

	float3 total = 0.0f;
	for (int i = 0; i < 48; i++) {
		float2 offset = offsets48[i] * texelSize * _BokehDelta;
		#if BEAN_BOKEH_DOWNSAMPLE
			total += tex2D(MainHalf, texcoord + offset).rgb;
		#else
			total += tex2D(Common::BeanBuffer, texcoord + offset).rgb;
		#endif
	}

	float3 color = 0.0f;
	color = total / 48;
	return float4(color, 1.0f);
}

float4 PS_BokehPost(float4 position : SV_Position, float2 texcoord : TexCoord) : SV_Target { 
	float3 color = tex2D(Bokeh, texcoord).rgb;
	float2 texelSize = float2(BUFFER_RCP_WIDTH, BUFFER_RCP_HEIGHT);

	#if BEAN_BOKEH_POST
		// tent filter
		float4 o = texelSize.xyxy * float2(-0.5, 0.5).xxyy;
		float3 s =
			tex2D(Bokeh, texcoord + o.xy).rgb +
			tex2D(Bokeh, texcoord + o.zy).rgb +
			tex2D(Bokeh, texcoord + o.xw).rgb +
			tex2D(Bokeh, texcoord + o.zw).rgb;
		s *= 0.25;
	#else
		// max filter
		float3 s = color;
		[loop]
		for (int x = -_FillRange; x <= _FillRange; x++) {
			[loop]
			for (int y = -_FillRange; y <= _FillRange; y++) {
				s = max(s, tex2D(Bokeh, texcoord + float2(x, y) * texelSize).rgb);
			}
		}
	#endif
	return float4(s, 1.0f);
}

float4 PS_BokehCompose(float4 position : SV_Position, float2 texcoord : TexCoord) : SV_Target {
	float4 pixel = tex2D(Common::BeanBuffer, texcoord);
	float3 color = pixel.rgb;
	float2 texelSize = float2(BUFFER_RCP_WIDTH, BUFFER_RCP_HEIGHT);

	float2 uv00 = texcoord;
    float2 uv10 = texcoord + float2(texelSize.x, 0.0f);
    float2 uv01 = texcoord + float2(0.0f, texelSize.y);
    float2 uv11 = texcoord + float2(texelSize.x, texelSize.y);

	float cocFar = tex2D(CoC, texcoord).g;
    float4 cocsFar_x4 = tex2DgatherG(CoC, texcoord).wzxy;
    float4 cocsFarDiffs = abs(cocFar.xxxx - cocsFar_x4);

	float4 dofFar00 = tex2D(BokehTemp, uv00);
    float4 dofFar10 = tex2D(BokehTemp, uv10);
    float4 dofFar01 = tex2D(BokehTemp, uv01);
    float4 dofFar11 = tex2D(BokehTemp, uv11);


	float2 imageCoord = texcoord / texelSize;
    float2 fractional = frac(imageCoord);
    float a = (1.0f - fractional.x) * (1.0f - fractional.y);
    float b = fractional.x * (1.0f - fractional.y);
    float c = (1.0f - fractional.x) * fractional.y;
    float d = fractional.x * fractional.y;

	float4 dofFar = 0.0f;
    float weightsSum = 0.0f;

    float weight00 = a / (cocsFarDiffs.x + 0.001f);
    dofFar += weight00 * dofFar00;
    weightsSum += weight00;

    float weight10 = b / (cocsFarDiffs.y + 0.001f);
    dofFar += weight10 * dofFar10;
    weightsSum += weight10;

    float weight01 = c / (cocsFarDiffs.z + 0.001f);
    dofFar += weight01 * dofFar01;
    weightsSum += weight01;

    float weight11 = d / (cocsFarDiffs.w + 0.001f);
    dofFar += weight11 * dofFar11;
    weightsSum += weight11;

    dofFar /= weightsSum;

	color = lerp(color, dofFar.rgb, cocFar);
	float cocNear = tex2D(CoC, texcoord).r;
    float4 dofNear = tex2D(BokehTemp, texcoord);
    color = lerp(color, (dofNear.rgb), cocNear);

	return float4(color, pixel.a);
}

technique Bean_DepthOfField
{
	pass
	{
		RenderTarget0 = CoCTex;
		VertexShader = PostProcessVS;
		PixelShader = PS_CoC;
	}

	// next 2 passes do the equivalent of find max within a box
	// saves on samples by seperating it into 2 passes
	pass 
	{
		RenderTarget = CoCTempTex;
		VertexShader = PostProcessVS;
		PixelShader = PS_ExpandCoCHorizontal;
	}
	pass 
	{
		RenderTarget = CoCTex;
		VertexShader = PostProcessVS;
		PixelShader = PS_ExpandCoCVertical;
	}

	// Blur Expanded CoC texture so that near field bleeds onto the rest
	#if BEAN_COC_DOWNSAMPLE == 0
		// Blur passes using cross sampling
		pass 
		{
			RenderTarget = CoCTempTex;
			VertexShader = PostProcessVS;
			PixelShader = PS_BlurCoCHorizontal;
		}
		pass 
		{
			RenderTarget = CoCTex;
			VertexShader = PostProcessVS;
			PixelShader = PS_BlurCoCVertical;
		}
	#else
		// Blur passes downsampling
		pass 
		{
			RenderTarget = CoCHalfTex;
			VertexShader = PostProcessVS;
			PixelShader = PS_CoCDownHalf;
		}
		pass 
		{
			RenderTarget = CoCQuarterTex;
			VertexShader = PostProcessVS;
			PixelShader = PS_CoCDownQuarter;
		}
		pass 
		{
			RenderTarget = CoCHalfTex;
			VertexShader = PostProcessVS;
			PixelShader = PS_CoCUpQuarter;
		}
		pass 
		{
			RenderTarget = CoCTex;
			VertexShader = PostProcessVS;
			PixelShader = PS_CoCUpHalf;
		}
	#endif

	// Bokeh blur downscaled image
	#if BEAN_BOKEH_DOWNSAMPLE
		pass
		{
			RenderTarget = MainHalfTex;
			VertexShader = PostProcessVS;
			PixelShader = PS_MainDownHalf;
		}
	#endif
	pass
	{
		#if BEAN_BOKEH_DOWNSAMPLE
			RenderTarget = BokehHalfTex;
		#else
			RenderTarget = BokehTex;
		#endif
		VertexShader = PostProcessVS;
		PixelShader = PS_BokehBlur;
	}
	#if BEAN_BOKEH_DOWNSAMPLE
		pass 
		{
			RenderTarget = BokehTex;
			VertexShader = PostProcessVS;
			PixelShader = PS_BokehUpHalf;
		}
	#endif

	pass 
	{
		RenderTarget = BokehTempTex;
		VertexShader = PostProcessVS;
		PixelShader = PS_BokehPost;
	}
	pass 
	{
		RenderTarget = Common::BeanBufferTexTemp;
		VertexShader = PostProcessVS;
		PixelShader = PS_BokehCompose;
	}
	pass
	{
		RenderTarget = Common::BeanBufferTex;
		VertexShader = PostProcessVS;
		PixelShader = Common::PS_EndPass;
	}
}