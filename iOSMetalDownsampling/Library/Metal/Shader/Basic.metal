//
//  Basic.metal
//  iOSMetalDownsampling
//
//  Created by Bradley Griffith on 5/23/15.
//  Copyright (c) 2015 Bradley Griffith. All rights reserved.
//

#include <metal_stdlib>
using namespace metal;


struct VertexIn
{
	packed_float4 position [[attribute(0)]];
	packed_float4 normal [[attribute(1)]];
	packed_float2 texCoords [[attribute(2)]];
};

struct VertexOut
{
	float4 position [[position]];
	float3 normal [[user(normal)]];
	float2 texCoords [[user(tex_coords)]];
};

struct Uniforms
{
	float4x4 modelMatrix;
	float3x3 normalMatrix;
	float4x4 modelViewProjectionMatrix;
};


/* Vertex Shaders
	------------------------------------------*/

vertex VertexOut basic_vertex(const device VertexIn *vertices [[buffer(0)]],
										const device Uniforms &uniforms [[ buffer(1) ]],
										unsigned     short    vid       [[vertex_id]])
{
	VertexOut out;
	out.position = float4(vertices[vid].position);
	out.normal = uniforms.normalMatrix * float4(vertices[vid].normal).xyz;
	out.texCoords = vertices[vid].texCoords;
	return out;
}

fragment float4 basic_fragment(VertexOut vert									  [[ stage_in ]],
										 texture2d<float, access::sample> texture   [[ texture(0) ]],
										 sampler                          sampler2D [[ sampler(0) ]])
{
	return texture.sample(sampler2D, vert.texCoords);
}
