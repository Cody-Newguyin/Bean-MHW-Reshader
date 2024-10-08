#pragma once

#define PI (3.1415926535897932384626433832795)
#define HALF_PI (1.5707963267948966192313216916398)

namespace Common {

// Shaders should set render target to BeanBufferTex and add PS_EndPass to the end
// HDR Buffer to pass between shaders
texture2D BeanBufferTex {
    Format = RGBA16F;
    Width  = BUFFER_WIDTH;
    Height = BUFFER_HEIGHT;
};
sampler2D BeanBuffer { Texture = BeanBufferTex; };
// Another HDR Buffer to ping pong back 
texture2D BeanBufferTexTemp {
    Format = RGBA16F;
    Width  = BUFFER_WIDTH;
    Height = BUFFER_HEIGHT;
};
sampler2D BeanBufferTemp { Texture = BeanBufferTexTemp; };
float4 PS_EndPass(float4 position : SV_POSITION, float2 texcoord : TEXCOORD) : SV_TARGET { return tex2D(BeanBufferTemp, texcoord); }

// Photometric 
float Luminance(float3 color) {
    return dot(color, float3(0.2127f, 0.7152f, 0.0722f));
}
// Digital
float LuminanceAlt(float3 color) {
    return dot(color, float3(0.299f, 0.587f, 0.114f));
}

float MaxLuminance(float3 color) {
    return max(color.r, max(color.g, color.b));  
}

// https://docs.unity3d.com/Packages/com.unity.shadergraph@6.9/manual/White-Balance-Node.html
float3 WhiteBalance(float3 col, float temp, float tint) {
    float t1 = temp * 10.0f / 6.0f;
    float t2 = tint * 10.0f / 6.0f;

    float x = 0.31271 - t1 * (t1 < 0 ? 0.1 : 0.05);
    float standardIlluminantY = 2.87 * x - 3 * x * x - 0.27509507;
    float y = standardIlluminantY + t2 * 0.05;

    float3 w1 = float3(0.949237, 1.03542, 1.08728);

    float Y = 1;
    float X = Y * x / y;
    float Z = Y * (1 - x - y) / y;
    float L = 0.7328 * X + 0.4296 * Y - 0.1624 * Z;
    float M = -0.7036 * X + 1.6975 * Y + 0.0061 * Z;
    float S = 0.0030 * X + 0.0136 * Y + 0.9834 * Z;
    float3 w2 = float3(L, M, S);

    float3 balance = float3(w1.x / w2.x, w1.y / w2.y, w1.z / w2.z);

    float3x3 LIN_2_LMS_MAT = float3x3(
        float3(3.90405e-1, 5.49941e-1, 8.92632e-3),
        float3(7.08416e-2, 9.63172e-1, 1.35775e-3),
        float3(2.31082e-2, 1.28021e-1, 9.36245e-1)
    );

    float3x3 LMS_2_LIN_MAT = float3x3(
        float3(2.85847e+0, -1.62879e+0, -2.48910e-2),
        float3(-2.10182e-1,  1.15820e+0,  3.24281e-4),
        float3(-4.18120e-2, -1.18169e-1,  1.06867e+0)
    );

    float3 lms = mul(LIN_2_LMS_MAT, col);
    lms *= balance;

    return mul(LMS_2_LIN_MAT, lms);
}

float3 convertRGB2XYZ(float3 col) {
    float3 xyz;
    xyz.x = dot(float3(0.4124564, 0.3575761, 0.1804375), col);
    xyz.y = dot(float3(0.2126729, 0.7151522, 0.0721750), col);
    xyz.z = dot(float3(0.0193339, 0.1191920, 0.9503041), col);

    return xyz;
}

float3 convertXYZ2Yxy(float3 col) {
    float inv = 1.0f / dot(col, 1.0f);

    return float3(col.y, col.x * inv, col.y * inv);
}

float3 convertRGB2Yxy(float3 col) {
    return convertXYZ2Yxy(convertRGB2XYZ(col));
}

float3 convertXYZ2RGB(float3 col) {
    float3 rgb;
    rgb.x = dot(float3( 3.2404542, -1.5371385, -0.4985314), col);
    rgb.y = dot(float3(-0.9692660,  1.8760108,  0.0415560), col);
    rgb.z = dot(float3( 0.0556434, -0.2040259,  1.0572252), col);

    return rgb;
}

float3 convertYxy2XYZ(float3 col) {
    float3 xyz;
    xyz.x = col.x * col.y / col.z;
    xyz.y = col.x;
    xyz.z = col.x * (1.0 - col.y - col.z) / col.z;

    return xyz;
}

float3 convertYxy2RGB(float3 col) {
    return convertXYZ2RGB(convertYxy2XYZ(col));
}


}