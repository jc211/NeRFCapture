//
//  Shaders.metal
//  NeRFCapture
//
//  Created by Jad Abou-Chakra on 19/12/2022.
//

#include <metal_stdlib>
using namespace metal;


kernel void yuv2rgb_kernel(texture2d<float, access::sample> capturedImageTextureY [[ texture(0) ]],
                           texture2d<float, access::sample> capturedImageTextureCbCr [[ texture(1) ]],
                           device uint8_t* result [[buffer(0)]],
                           uint2 position [[thread_position_in_grid]]) {
    
    const auto textureSize = ushort2(capturedImageTextureY.get_width(),
                                     capturedImageTextureY.get_height());
    
    constexpr sampler colorSampler(mip_filter::linear,
                                   mag_filter::linear,
                                   min_filter::linear);
    
    const float4x4 ycbcrToRGBTransform = float4x4(
        float4(+1.0000f, +1.0000f, +1.0000f, +0.0000f),
        float4(+0.0000f, -0.3441f, +1.7720f, +0.0000f),
        float4(+1.4020f, -0.7141f, +0.0000f, +0.0000f),
        float4(-0.7010f, +0.5291f, -0.8860f, +1.0000f)
    );
    float2 texCoord = float2(position)/float2(textureSize);
    
    // Sample Y and CbCr textures to get the YCbCr color at the given texture coordinate
    float4 ycbcr = float4(capturedImageTextureY.sample(colorSampler, texCoord).r,
                          capturedImageTextureCbCr.sample(colorSampler, texCoord).rg, 1.0);
    
    // Return converted RGB color
    float4 res = ycbcrToRGBTransform * ycbcr * 255.0;
    int ind = position.y*textureSize[0] + position.x;
    result[3*ind + 0] = res[0];
    result[3*ind + 1] = res[1];
    result[3*ind + 2] = res[2];
}
