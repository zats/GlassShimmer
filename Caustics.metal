#include <metal_stdlib>
using namespace metal;

struct RasterData {
    float4 position [[position]];
    float2 uv;
};

vertex RasterData causticVertex(uint vertexID [[vertex_id]]) {
    const float2 vertices[] = {float2(-1, -1), float2(3, -1), float2(-1, 3)};
    float2 position = vertices[vertexID];
    return {float4(position, 0, 1), position * 0.5f + 0.5f};
}

static float4 permute(float4 value) {
    return fmod((value * 34.0f + 1.0f) * value, 289.0f);
}

static float4 noiseCorners(float4 hash, float3 offset) {
    float4 gx = fract(hash / 7.0f);
    float4 gy = fract(floor(hash / 7.0f) / 7.0f) - 0.5f;
    float4 gz = 0.5f - abs(gx) - abs(gy);
    float4 fold = step(gz, float4(0));
    gx -= fold * (step(float4(0), gx) - 0.5f);
    gy -= fold * (step(float4(0), gy) - 0.5f);
    float4 normalization = 1.792842914f - 0.853734721f * (gx * gx + gy * gy + gz * gz);
    gx *= normalization;
    gy *= normalization;
    gz *= normalization;
    return gx * float4(offset.x, offset.x - 1, offset.x, offset.x - 1)
         + gy * float4(offset.y, offset.y, offset.y - 1, offset.y - 1)
         + gz * offset.z;
}

static float cnoise(float3 point) {
    float3 lattice0 = fmod(floor(point), 289.0f);
    float3 lattice1 = fmod(floor(point) + 1.0f, 289.0f);
    float3 offset = fract(point);
    float4 ix = float4(lattice0.x, lattice1.x, lattice0.x, lattice1.x);
    float4 iy = float4(lattice0.y, lattice0.y, lattice1.y, lattice1.y);
    float4 xy = permute(permute(ix) + iy);
    float4 lower = noiseCorners(permute(xy + lattice0.z), offset);
    float4 upper = noiseCorners(permute(xy + lattice1.z), offset - float3(0, 0, 1));
    float3 fade = offset * offset * offset * (offset * (offset * 6.0f - 15.0f) + 10.0f);
    float4 z = mix(lower, upper, fade.z);
    float2 yz = mix(z.xy, z.zw, fade.y);
    return 2.2f * mix(yz.x, yz.y, fade.x);
}

// Continuous corner distance and normal, reconstructed from the original shader IR.
static float continuousDistance(float2 point, float2 halfSize, float radius) {
    float2 q = abs(point) - halfSize + radius;
    if (q.x > 0 && q.y > 0) {
        float power = mix(5.0f, 2.0f, radius / max(min(halfSize.x, halfSize.y), 0.001f));
        return pow(pow(q.x, power) + pow(q.y, power), 1.0f / power) - radius;
    }
    return max(q.x, q.y) - radius;
}

static float2 continuousNormal(float2 point, float2 halfSize, float radius) {
    const float epsilon = 0.0001f;
    float2 gradient = float2(
        continuousDistance(point + float2(epsilon, 0), halfSize, radius)
          - continuousDistance(point - float2(epsilon, 0), halfSize, radius),
        continuousDistance(point + float2(0, epsilon), halfSize, radius)
          - continuousDistance(point - float2(0, epsilon), halfSize, radius));
    float magnitude = length(gradient);
    return magnitude > 1e-8f ? gradient / magnitude : float2(0, 1);
}

static float ring(float2 point, float2 center) {
    float distance = length(point - center) - 0.3f;
    return smoothstep(0.0f, 0.13f, distance) + smoothstep(0.0f, 0.13f, -distance);
}

fragment float4 causticFragment(RasterData input [[stage_in]],
                               constant float2 &resolution [[buffer(0)]],
                               constant float4 &shape [[buffer(1)]],
                               constant float &time [[buffer(2)]],
                               constant float &opacity [[buffer(3)]]) {
    float scale = min(resolution.x, resolution.y);
    float2 point = (input.uv - 0.5f) * resolution / scale;
    float2 halfSize = shape.xy * 0.5f / scale;
    float minimumHalfSize = min(halfSize.x, halfSize.y);
    float radius = min(shape.z / scale, minimumHalfSize);
    float distance = continuousDistance(point, halfSize, radius);
    float2 normal = continuousNormal(point, halfSize, radius);
    float edgeWidth = minimumHalfSize * 0.15f;
    float bend = pow(saturate((distance + edgeWidth) / edgeWidth), 3.0f);
    point += (normal + 1.0f) * -0.05f * bend;

    float3 transmission = float3(1);
    for (int index = 0; index < 4; ++index) {
        float seed = fract(sin(float(index)) * 43758.5469f);
        float xTime = time * 0.1f + 242.2f + seed * 233.0f;
        float yTime = time * 0.1f + 100.0f + seed * 133.0f;
        float2 red = float2(cnoise(float3(index, 0, xTime)), cnoise(float3(index * 5252, 20, yTime)));
        float2 green = float2(cnoise(float3(index, 0, xTime + 0.03f)), cnoise(float3(index * 5252, 20, yTime + 0.03f)));
        float2 blue = float2(cnoise(float3(index, 0, xTime + 0.06f)), cnoise(float3(index * 5252, 20, yTime + 0.09f)));
        transmission *= float3(ring(point, red), ring(point, green), ring(point, blue));
    }

    float fadeWidth = mix(minimumHalfSize * 2.0f, minimumHalfSize * 0.1f, shape.w);
    float fade = pow(saturate((distance + fadeWidth) / fadeWidth), 3.0f);
    float3 color = (1.0f - transmission) * fade * opacity;
    return float4(color, max(color.r, max(color.g, color.b)));
}
