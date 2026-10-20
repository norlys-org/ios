// The aurora the website opens on (public/assets/norlys-animation.json, a Unicorn Studio scene),
// ported pass for pass so the app can play it natively while the site loads behind it:
//
//   four bands drawn on a black canvas → liquify → noise blur (×2) → god rays (bright areas, rays,
//   composite over the blurred scene)
//
// Shader bodies follow the scene's compiled GLSL, constants included. Coordinates are kept the GL
// way, `uv` (0, 0) at the bottom left, and flipped only where a texture is read.

#include <metal_stdlib>
using namespace metal;

/// Mirrors `IntroUniforms` in AuroraIntroView.swift
struct IntroUniforms {
    /// Canvas size in points, the liquify clock, and the brightness the whole scene is drawn at
    float4 canvas;
    /// Liquify's amplitude, mix and position, as its appear state drives them
    float4 liquify;
    /// Each band's left, top, width and height in points, before rotation
    float4 bands[4];
    /// Each band's rotation, in radians
    float4 bandAngles;
    /// The first band's opacity, which fades in
    float4 bandOpacity;
};

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

constant float PI = 3.14159265;
constexpr sampler linearClamp(filter::linear, address::clamp_to_edge);

/// A texture written by an earlier pass, read at a GL-style coordinate
static float4 read(texture2d<float> texture, float2 uv) {
    return texture.sample(linearClamp, float2(uv.x, 1.0 - uv.y));
}

/// GLSL's `mod`, which floors where Metal's `fmod` truncates
template <typename T> static T glslMod(T x, T y) { return x - y * floor(x / y); }

static float2x2 rot(float a) { return float2x2(float2(cos(a), -sin(a)), float2(sin(a), cos(a))); }

vertex VertexOut introVertex(uint vid [[vertex_id]]) {
    // One triangle over the whole target
    float2 position = float2((vid << 1) & 2, vid & 2) * 2.0 - 1.0;
    VertexOut out;
    out.position = float4(position, 0, 1);
    out.uv = position * 0.5 + 0.5;
    return out;
}

// MARK: - Bands

constant float3 bandGradient[3] = { float3(0), float3(5, 144, 46) / 255.0, float3(51, 245, 107) / 255.0 };
constant float3 bandColors[4] = {
    float3(0), // the gradient above
    float3(13, 83, 33) / 255.0,
    float3(215, 255, 226) / 255.0,
    float3(255, 199, 230) / 255.0
};

/// The black canvas and its four rectangles, as the scene's 2D canvas draws them: each rotated
/// about its own centre, and laid over what is below it in order
static float3 bands(float2 uv, constant IntroUniforms &u) {
    float2 size = u.canvas.xy;
    // Canvas pixels, y down. Clamped like the texture the scene samples, which repeats its edge
    float2 point = float2(clamp(uv.x, 0.0, 1.0), 1.0 - clamp(uv.y, 0.0, 1.0)) * size;

    float3 color = float3(0);
    for (int i = 0; i < 4; i++) {
        float4 band = u.bands[i];
        float2 half_ = band.zw * 0.5;
        if (band.w <= 0.0) continue;

        float angle = u.bandAngles[i];
        float2 offset = point - (band.xy + half_);
        // Undo the canvas rotation, which turns clockwise in y-down coordinates
        float2 local = float2(
            offset.x * cos(angle) + offset.y * sin(angle),
            -offset.x * sin(angle) + offset.y * cos(angle)
        ) + half_;

        float edge = min(min(local.x, band.z - local.x), min(local.y, band.w - local.y));
        float coverage = clamp(edge + 0.5, 0.0, 1.0);
        if (coverage <= 0.0) continue;

        float3 fill = bandColors[i];
        float opacity = 1.0;
        if (i == 0) {
            // Linear gradient across the band's height, at the scene's `gradientAngle` of a quarter turn
            float t = clamp(local.y / band.w, 0.0, 1.0);
            fill = t < 0.5
                ? mix(bandGradient[0], bandGradient[1], t * 2.0)
                : mix(bandGradient[1], bandGradient[2], t * 2.0 - 1.0);
            opacity = u.bandOpacity.x;
        }
        color = mix(color, fill, coverage * opacity);
    }
    return color;
}

// MARK: - Liquify

static float2 liquify(float2 st, constant IntroUniforms &u) {
    float aspectRatio = u.canvas.x / u.canvas.y;
    float time = u.canvas.z;
    float2 pos = u.liquify.zw;
    st -= pos;
    st.x *= aspectRatio;
    st = st * rot(-0.0972 * 2. * PI);
    float amplitude = u.liquify.x * mix(0.2, 0.2 / (0.1800 + 0.05), 0.25);
    for (float i = 1.0; i <= 5.0; i++) {
        st = st * rot(i / 5. * PI * 2.);
        float cosFactor = cos(i * (5.0 * (0.1800 + 0.1)) * st.y + time * 0.025);
        st.x += amplitude * cosFactor;
        float sinFactor = sin(i * (5.0 * (0.1800 + 0.1)) * st.x + time * 0.025);
        st.y += amplitude * sinFactor;
    }
    st = st * rot(-0.0972 * -1. * 2. * PI);
    st.x /= aspectRatio;
    st += pos;
    return st;
}

fragment float4 introLiquify(VertexOut in [[stage_in]], constant IntroUniforms &u [[buffer(0)]]) {
    float2 uv = in.uv;
    float2 liquifiedUV = liquify(uv, u);
    float distanceUv = length(liquifiedUV - uv);
    float2 normalizedUv = distanceUv > 0.0 ? (liquifiedUV - uv) / distanceUv : float2(0);
    float chromAbb = 0.0100 * 0.5;
    float2 offsetR = liquifiedUV + chromAbb * normalizedUv * distanceUv;
    float2 offsetG = liquifiedUV;
    float2 offsetB = liquifiedUV - chromAbb * normalizedUv * distanceUv;
    float mixAmount = u.liquify.y;
    // The bands are evaluated where the scene would sample their texture
    float r = bands(mix(uv, offsetR, mixAmount), u).r;
    float g = bands(mix(uv, offsetG, mixAmount), u).g;
    float b = bands(mix(uv, offsetB, mixAmount), u).b;
    return float4(r, g, b, 1);
}

// MARK: - Noise blur

static float4 permute(float4 t) { return t * (t * 34.0 + 133.0); }

static float3 grad(float hash) {
    float3 cube = glslMod(floor(hash / float3(1.0, 2.0, 4.0)), float3(2.0)) * 2.0 - 1.0;
    float3 cuboct = cube;
    float index0 = step(0.0, 1.0 - floor(hash / 16.0));
    float index1 = step(0.0, floor(hash / 16.0) - 1.0);
    cuboct.x *= 1.0 - index0;
    cuboct.y *= 1.0 - index1;
    cuboct.z *= 1.0 - (1.0 - index0 - index1);
    float type = glslMod(floor(hash / 8.0), 2.0);
    float3 rhomb = (1.0 - type) * cube + type * (cuboct + cross(cube, cuboct));
    float3 g = cuboct * 1.22474487139 + rhomb;
    g *= (1.0 - 0.042942436724648037 * type) * 3.5946317686139184;
    return g;
}

static float4 bccNoiseDerivativesPart(float3 X) {
    float3 b = floor(X);
    float4 i4 = float4(X - b, 2.5);
    float3 v1 = b + floor(dot(i4, float4(.25)));
    float3 v2 = b + float3(1, 0, 0) + float3(-1, 1, 1) * floor(dot(i4, float4(-.25, .25, .25, .35)));
    float3 v3 = b + float3(0, 1, 0) + float3(1, -1, 1) * floor(dot(i4, float4(.25, -.25, .25, .35)));
    float3 v4 = b + float3(0, 0, 1) + float3(1, 1, -1) * floor(dot(i4, float4(.25, .25, -.25, .35)));
    float4 hashes = permute(glslMod(float4(v1.x, v2.x, v3.x, v4.x), float4(289.0)));
    hashes = permute(glslMod(hashes + float4(v1.y, v2.y, v3.y, v4.y), float4(289.0)));
    hashes = glslMod(permute(glslMod(hashes + float4(v1.z, v2.z, v3.z, v4.z), float4(289.0))), float4(48.0));
    float3 d1 = X - v1;
    float3 d2 = X - v2;
    float3 d3 = X - v3;
    float3 d4 = X - v4;
    float4 a = max(0.75 - float4(dot(d1, d1), dot(d2, d2), dot(d3, d3), dot(d4, d4)), 0.0);
    float4 aa = a * a;
    float4 aaaa = aa * aa;
    float3 g1 = grad(hashes.x);
    float3 g2 = grad(hashes.y);
    float3 g3 = grad(hashes.z);
    float3 g4 = grad(hashes.w);
    float4 extrapolations = float4(dot(d1, g1), dot(d2, g2), dot(d3, g3), dot(d4, g4));
    float3 derivative = -8.0 * float4x3(d1, d2, d3, d4) * (aa * a * extrapolations)
        + float4x3(g1, g2, g3, g4) * aaaa;
    return float4(derivative, dot(aaaa, extrapolations));
}

static float4 bccNoiseDerivatives_XYBeforeZ(float3 X) {
    float3x3 orthonormalMap = float3x3(
        float3(0.788675134594813, -0.211324865405187, -0.577350269189626),
        float3(-0.211324865405187, 0.788675134594813, -0.577350269189626),
        float3(0.577350269189626, 0.577350269189626, 0.577350269189626)
    );
    X = orthonormalMap * X;
    float4 result = bccNoiseDerivativesPart(X) + bccNoiseDerivativesPart(X + 144.5);
    return float4(result.xyz * orthonormalMap, result.w);
}

/// Both of the scene's blur passes; the layer does not animate, so its clock stays at zero
fragment float4 introNoiseBlur(
    VertexOut in [[stage_in]],
    constant IntroUniforms &u [[buffer(0)]],
    texture2d<float> source [[texture(0)]]
) {
    const int MAX_ITERATIONS = 32;
    const float MAX_ITERATIONS_F = 32.0;
    const float HALF_ITERATIONS = 16.0;
    float2 uv = in.uv;
    float aspectRatio = u.canvas.x / u.canvas.y;
    float2 noiseUv = rot(0.0891 * -1. * 2.0 * PI)
        * (uv * float2(aspectRatio, 1.) - float2(0.5, 0.5) * float2(aspectRatio, 1.))
        * float2(0.3200, 1. - 0.3200) * 5. * 0.1200;
    float4 noise = bccNoiseDerivatives_XYBeforeZ(float3(noiseUv, 0.1800 * 2.));
    float2 noiseOffset = (noise.xy - 0.5) * (0.5900 + 0.01) * 0.25;
    float4 color = float4(0.0);
    for (int i = 0; i < MAX_ITERATIONS; i++) {
        float offset = float(i) - HALF_ITERATIONS;
        float2 st = uv + noiseOffset * (offset / MAX_ITERATIONS_F);
        color += read(source, st);
    }
    return color / MAX_ITERATIONS_F;
}

// MARK: - God rays

static uint fibonacciHash(uint x) {
    const uint FIB_HASH = 2654435769u;
    uint hash = x * FIB_HASH;
    hash ^= hash >> 16;
    hash *= 0x85ebca6bu;
    hash ^= hash >> 13;
    hash *= 0xc2b2ae35u;
    hash ^= hash >> 16;
    return hash;
}

static float randFibo(float2 xy) {
    uint x_bits = as_type<uint>(xy.x);
    uint y_bits = as_type<uint>(xy.y);
    uint y_hash = fibonacciHash(y_bits);
    uint x_xor_y = x_bits ^ y_hash;
    uint final_hash = fibonacciHash(x_xor_y);
    return float(final_hash) / float(0xffffffffu);
}

fragment float4 introBrightAreas(VertexOut in [[stage_in]], texture2d<float> source [[texture(0)]]) {
    float4 color = read(source, in.uv);
    float lum = dot(color.rgb, float3(0.299, 0.587, 0.114));
    return color * smoothstep(0.5400 - 0.1, 0.5400, lum);
}

fragment float4 introRays(VertexOut in [[stage_in]], texture2d<float> source [[texture(0)]]) {
    const float MAX_ITERATIONS = 64.;
    const float stepFactor = 0.0098;
    // What the scene's `amount` comes to once its scroll state has had its say
    const float amount = 0.5;
    const float decay = 0.972;
    float2 st = in.uv;
    float3 color = float3(0);
    float offset = (0.25 + min(1., amount)) * stepFactor;
    // Straight at the centre, where the scene's rays point without a mouse to follow
    float2 pos = float2(0.5, 0.5);
    float weight = 1.0;
    float bnoz = randFibo(st) * amount;
    float2 marchPos = st;
    for (float i = 0.0; i < MAX_ITERATIONS; i += 4.0) {
        for (float j = 0.0; j < 4.0; j++) {
            float x = min(0.999, (i + j) * offset) + bnoz * 0.02;
            marchPos = st * (1.0 - x) + float2(x * 0.5) + (pos - 0.5) * x;
            color += read(source, marchPos).rgb * weight;
            weight *= decay;
        }
    }
    float3 rays = color / MAX_ITERATIONS * float3(0.9882352941176471, 0.9176470588235294, 1);
    return float4(rays, distance(st, marchPos));
}

fragment float4 introComposite(
    VertexOut in [[stage_in]],
    constant IntroUniforms &u [[buffer(0)]],
    texture2d<float> rays [[texture(0)]],
    texture2d<float> background [[texture(1)]]
) {
    const float PI2 = 6.28318530718;
    float2 uv = in.uv;
    float4 godrays = read(rays, uv);
    float distanceInfo = godrays.a;
    float luminance = dot(godrays.rgb, float3(0.299, 0.587, 0.114));
    // Hashed in place of the scene's blue noise texture, which only jitters the rays' grain
    float blueNoise = glslMod((randFibo(floor(in.position.xy)) - 0.5) * PI2, PI2) - 0.5;
    float2 circNoise = float2(cos(blueNoise), sin(blueNoise));
    // GLSL leaves `pow` of a negative base undefined; the brightest rays get no jitter
    float brightnessScale = max(0.0, 1. - (luminance + 0.25));
    float2 offset = circNoise * 0.05 * pow(brightnessScale, 3.) * distanceInfo * 2.;
    float4 color = read(rays, uv + offset);
    float4 bg = read(background, uv);
    color.rgb = bg.rgb + (color.rgb * 2.9 * 0.5900 + blueNoise * 0.001);
    // Dimmed at night, like the site
    return float4(color.rgb * u.canvas.w, 1);
}
