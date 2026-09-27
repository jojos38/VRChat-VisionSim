#ifndef VISION_CORE_INCLUDED
#define VISION_CORE_INCLUDED

#include "UnityCG.cginc"

// Upper bound of the tap loops
#define VISION_MAX_TAPS 64

// Below this the blur breaks into visible steps
#define VISION_MIN_TAPS 8

// Golden angle, and one and four turns of it as (cos, sin)
#define VISION_GOLDEN 2.3999632
static const float2 VISION_TURN = float2(-0.7373689, 0.6754903);
static const float2 VISION_TURN4 = float2(-0.9847135, -0.1741820);

// Blur radius, in screen heights, below which a pixel is left sharp
#define VISION_MIN_RADIUS 0.0004

// Widest blur radius, in screen heights
#define VISION_MAX_RADIUS 0.09

// Widest blur, in dioptres, the scout searches for a nearer surface
#define VISION_SEARCH 8.0

// Pixels per side sharing one noise value. 2 is kinder to the texture cache but shows blocks
#define VISION_NOISE_CELL 1.0

// Vergence range stored in the grab's alpha, 20 D being 5 cm
#define VISION_VERGENCE_RANGE 20.0

// Blur radius, in degrees, over which the small blur boost fades out. About 1.5 pixels
// on a 25 px/deg headset, and unaffected by supersampling
#define VISION_BOOST_FADE 0.06

// Spectacle lens to eye, in metres, which the prescription is written for. 0 for contact lenses
#define VISION_VERTEX_DISTANCE 0.012

float _IsLocal;
float _Enabled;

float _SphereL, _SphereR;
float _CylinderL, _CylinderR;
float _AxisL, _AxisR;
float _SyncRight;

float _PupilMM;
float _Gain;

// How many times a blur too small for the headset to show is grown. Large blurs are left
// as they are. 1 is physically exact
float _Boost;

// Closest distance the eye can focus, in metres, about 12 cm when young and past 1 m by sixty
// A distance rather than dioptres so a slider spreads evenly over it
float _NearPoint;

// Taps per pixel
float _Quality;

// Whether taps check depth, so a sharp foreground cannot spill over a blurred background
float _DepthReject;

// Whether the denoise pass smooths the blur's grain
float _Denoise;

// Colour vision, 0 normal, 1 protan, 2 deutan, 3 tritan, 4 achromat
float _ColorType;

// From mild anomalous trichromacy near 0 to full dichromacy at 1
float _ColorSeverity;

// Set by VRChat while rendering a mirror or a camera
float _VRChatMirrorMode;
float _VRChatCameraMode;


struct appdata
{
    float4 vertex : POSITION;
    UNITY_VERTEX_INPUT_INSTANCE_ID
};

struct v2f
{
    float4 pos  : SV_POSITION;
    float2 uv   : TEXCOORD0;
    float4 grab : TEXCOORD1;
    UNITY_VERTEX_OUTPUT_STEREO
};

v2f vert(appdata v)
{
    v2f o;
    UNITY_SETUP_INSTANCE_ID(v);
    UNITY_INITIALIZE_OUTPUT(v2f, o);
    UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);

    float2 quad = v.vertex.xy * 2.0;
    o.uv = v.vertex.xy + 0.5;

    // Straight to clip space, so the quad fills each eye whatever its projection
    o.pos = float4(quad, UNITY_NEAR_CLIP_VALUE, 1.0);
    o.grab = ComputeGrabScreenPos(o.pos);
    return o;
}

// Two uncorrelated values per cell, for the spiral's rotation and radial jitter
float2 VisionNoise(float2 pos, float cell)
{
    float3 p = frac(float3(floor(pos / cell).xyx) * float3(0.1031, 0.1030, 0.0973));
    p += dot(p, p.yzx + 33.33);
    return frac((p.xx + p.yz) * p.zy);
}

// Keeps a UV inside this eye's part of the capture
float2 VisionClampUv(float2 p)
{
    #if defined(UNITY_SINGLE_PASS_STEREO)
        p = UnityStereoClamp(p, unity_StereoScaleOffset[unity_StereoEyeIndex]);
        p.y = saturate(p.y);
    #else
        p = saturate(p);
    #endif

    return p;
}

// Blur pass output, its radius passed on in alpha for the denoise pass
fixed4 VisionOut(float3 colour, float radius)
{
    return fixed4(colour, saturate(radius / VISION_MAX_RADIUS));
}

// Colour, and the vergence the first pass left in alpha
float4 VisionGrab(float2 uv)
{
    float4 texel = VISION_SAMPLE(VisionClampUv(uv));
    texel.a *= VISION_VERGENCE_RANGE;
    return texel;
}

// Without a depth pass the texture is left as a tiny placeholder
bool VisionHasDepth()
{
    VISION_DEPTH_DIMS size;
    VISION_DEPTH_SIZE(size);
    return size.x > 16;
}

// The wearer's own eyes, never a mirror or a camera
bool VisionLocal()
{
    return _IsLocal > 0.5 && _Enabled > 0.5
        && _VRChatMirrorMode < 0.5 && _VRChatCameraMode < 0.5;
}

// Whether the blur runs. Shared by every pass, so alpha is only written where it is read
bool VisionActive()
{
    return VisionLocal() && VisionHasDepth();
}

// Colour vision needs no depth, so it still runs where the blur cannot
bool VisionColourActive()
{
    return VisionLocal() && _ColorType > 0.5;
}

// Machado, Oliveira & Fernandes 2009, applied to linear RGB. One matrix per tenth of severity,
// from normal vision at 0 to the full dichromat at 10. Their tritan model is the least reliable
static const float3x3 VISION_PROTAN[11] =
{
    float3x3(1.000000, 0.000000, 0.000000, 0.000000, 1.000000, 0.000000, 0.000000, 0.000000, 1.000000),
    float3x3(0.856167, 0.182038, -0.038205, 0.029342, 0.955115, 0.015544, -0.002880, -0.001563, 1.004443),
    float3x3(0.734766, 0.334872, -0.069637, 0.051840, 0.919198, 0.028963, -0.004928, -0.004209, 1.009137),
    float3x3(0.630323, 0.465641, -0.095964, 0.069181, 0.890046, 0.040773, -0.006308, -0.007724, 1.014032),
    float3x3(0.539009, 0.579343, -0.118352, 0.082546, 0.866121, 0.051332, -0.007136, -0.011959, 1.019095),
    float3x3(0.458064, 0.679578, -0.137642, 0.092785, 0.846313, 0.060902, -0.007494, -0.016807, 1.024301),
    float3x3(0.385450, 0.769005, -0.154455, 0.100526, 0.829802, 0.069673, -0.007442, -0.022190, 1.029632),
    float3x3(0.319627, 0.849633, -0.169261, 0.106241, 0.815969, 0.077790, -0.007025, -0.028051, 1.035076),
    float3x3(0.259411, 0.923008, -0.182420, 0.110296, 0.804340, 0.085364, -0.006276, -0.034346, 1.040622),
    float3x3(0.203876, 0.990338, -0.194214, 0.112975, 0.794542, 0.092483, -0.005222, -0.041043, 1.046265),
    float3x3(0.152286, 1.052583, -0.204868, 0.114503, 0.786281, 0.099216, -0.003882, -0.048116, 1.051998)
};

static const float3x3 VISION_DEUTAN[11] =
{
    float3x3(1.000000, 0.000000, 0.000000, 0.000000, 1.000000, 0.000000, 0.000000, 0.000000, 1.000000),
    float3x3(0.866435, 0.177704, -0.044139, 0.049567, 0.939063, 0.011370, -0.003453, 0.007233, 0.996220),
    float3x3(0.760729, 0.319078, -0.079807, 0.090568, 0.889315, 0.020117, -0.006027, 0.013325, 0.992702),
    float3x3(0.675425, 0.433850, -0.109275, 0.125303, 0.847755, 0.026942, -0.007950, 0.018572, 0.989378),
    float3x3(0.605511, 0.528560, -0.134071, 0.155318, 0.812366, 0.032316, -0.009376, 0.023176, 0.986200),
    float3x3(0.547494, 0.607765, -0.155259, 0.181692, 0.781742, 0.036566, -0.010410, 0.027275, 0.983136),
    float3x3(0.498864, 0.674741, -0.173604, 0.205199, 0.754872, 0.039929, -0.011131, 0.030969, 0.980162),
    float3x3(0.457771, 0.731899, -0.189670, 0.226409, 0.731012, 0.042579, -0.011595, 0.034333, 0.977261),
    float3x3(0.422823, 0.781057, -0.203881, 0.245752, 0.709602, 0.044646, -0.011843, 0.037423, 0.974421),
    float3x3(0.392952, 0.823610, -0.216562, 0.263559, 0.690210, 0.046232, -0.011910, 0.040281, 0.971630),
    float3x3(0.367322, 0.860646, -0.227968, 0.280085, 0.672501, 0.047413, -0.011820, 0.042940, 0.968881)
};

static const float3x3 VISION_TRITAN[11] =
{
    float3x3(1.000000, 0.000000, 0.000000, 0.000000, 1.000000, 0.000000, 0.000000, 0.000000, 1.000000),
    float3x3(0.926670, 0.092514, -0.019184, 0.021191, 0.964503, 0.014306, 0.008437, 0.054813, 0.936750),
    float3x3(0.895720, 0.133330, -0.029050, 0.029997, 0.945400, 0.024603, 0.013027, 0.104707, 0.882266),
    float3x3(0.905871, 0.127791, -0.033662, 0.026856, 0.941251, 0.031893, 0.013410, 0.148296, 0.838294),
    float3x3(0.948035, 0.089490, -0.037526, 0.014364, 0.946792, 0.038844, 0.010853, 0.193991, 0.795156),
    float3x3(1.017277, 0.027029, -0.044306, -0.006113, 0.958479, 0.047634, 0.006379, 0.248708, 0.744913),
    float3x3(1.104996, -0.046633, -0.058363, -0.032137, 0.971635, 0.060503, 0.001336, 0.317922, 0.680742),
    float3x3(1.193214, -0.109812, -0.083402, -0.058496, 0.979410, 0.079086, -0.002346, 0.403492, 0.598854),
    float3x3(1.257728, -0.139648, -0.118081, -0.078003, 0.975409, 0.102594, -0.003316, 0.501214, 0.502102),
    float3x3(1.278864, -0.125333, -0.153531, -0.084748, 0.957674, 0.127074, -0.000989, 0.601151, 0.399838),
    float3x3(1.255528, -0.076749, -0.178779, -0.078411, 0.930809, 0.147602, 0.004733, 0.691367, 0.303900)
};

float3 VisionColour(float3 rgb)
{
    int type = (int)round(_ColorType);
    float severity = saturate(_ColorSeverity);

    if (type <= 0) return rgb;
    if (type >= 4) return lerp(rgb, dot(rgb, float3(0.2126, 0.7152, 0.0722)).xxx, severity);

    // Blended between the two nearest tabulated severities
    float step = severity * 10.0;
    int i = min((int)step, 9);
    float t = step - i;

    float3x3 a = type == 1 ? VISION_PROTAN[i] : type == 2 ? VISION_DEUTAN[i] : VISION_TRITAN[i];
    float3x3 b = type == 1 ? VISION_PROTAN[i + 1] : type == 2 ? VISION_DEUTAN[i + 1] : VISION_TRITAN[i + 1];

    // Clamped, the matrices reaching slightly outside the gamut
    return max(mul(lerp(a, b, t), rgb), 0.0);
}

// Screen heights of blur radius per dioptre, the angle being half the pupil times the defocus
float VisionUvPerDioptre()
{
    return _PupilMM * 0.0005 * abs(UNITY_MATRIX_P._m11) * 0.5 * _Gain;
}

struct VisionRx
{
    float sphere;
    float cylinder;
    float axis;

    // Spherical equivalents of both eyes, lower first
    float2 lead;

    // Accommodation available, the vergence of the near point
    float reserve;

    // VISION_BOOST_FADE in dioptres
    float fade;
};

// Sphere and cylinder moved from the spectacle lens to the eye, one meridian at a time
float3 VisionAtEye(float3 rx)
{
    float2 meridians = float2(rx.x, rx.x + rx.y);
    meridians /= 1.0 - VISION_VERTEX_DISTANCE * meridians;
    return float3(meridians.x, meridians.y - meridians.x, rx.z);
}

VisionRx VisionPrescription()
{
    #if defined(USING_STEREO_MATRICES)
        bool right = unity_StereoEyeIndex == 1;
    #else
        bool right = false;
    #endif

    float3 leftRx = VisionAtEye(float3(_SphereL, _CylinderL, _AxisL));
    float3 rightRx = _SyncRight > 0.5 ? leftRx : VisionAtEye(float3(_SphereR, _CylinderR, _AxisR));
    float3 own = right ? rightRx : leftRx;

    // An astigmatic eye focuses on the circle of least confusion, at sphere + cylinder / 2
    float2 equivalent = float2(leftRx.x + leftRx.y * 0.5, rightRx.x + rightRx.y * 0.5);

    VisionRx rx;
    rx.sphere = own.x;
    rx.cylinder = own.y;
    rx.axis = own.z;
    rx.lead = float2(min(equivalent.x, equivalent.y), max(equivalent.x, equivalent.y));
    rx.reserve = 1.0 / max(_NearPoint, 0.01);
    rx.fade = radians(VISION_BOOST_FADE) / (_PupilMM * 0.0005 * _Gain);
    return rx;
}

// Residual defocus in dioptres, x along the axis (sphere only), y across it (plus cylinder)
// Accommodation only adds power, up to the reserve, so a myope blurs past the far point
// and a hypermetrope spends reserve just to see far
float2 VisionDefocus(VisionRx rx, float vergence)
{
    // One accommodation for both eyes, the least that focuses either, none if neither needs any
    float2 needed = vergence + rx.lead;
    float used = clamp(needed.x >= 0.0 ? needed.x : needed.y, 0.0, rx.reserve);

    float focus = vergence + rx.sphere;
    float2 defocus = abs(float2(focus, focus + rx.cylinder) - used);

    return defocus * (1.0 + (_Boost - 1.0) * exp(-defocus / rx.fade));
}

// Maps the unit disc, in the axis frame, to a grab UV offset
float2x2 VisionEllipse(float2x2 axis, float2 extent)
{
    float2x2 k = mul(axis, float2x2(extent.x, 0.0, 0.0, extent.y));
    k[0] *= _ScreenParams.y / _ScreenParams.x;
    return k;
}

float2 VisionDirection(float angle)
{
    float2 dir;
    sincos(angle, dir.y, dir.x);
    return dir;
}

// Next spiral tap, stepping the squared radius so taps stay uniform by area
void VisionStep(inout float2 dir, inout float rr, float2 turn, float rrStep)
{
    dir = float2(dir.x * turn.x - dir.y * turn.y,
                 dir.x * turn.y + dir.y * turn.x);
    rr += rrStep;
}

// Max over the 2x2 quad. No pixel of the quad may have returned before this
float VisionQuadMax(float v, uint2 pixel)
{
    // A fine derivative is the odd pixel minus the even one, so each recovers its neighbour
    float2 side = 1.0 - 2.0 * (float2)(pixel & 1);
    v = max(v, v + side.x * ddx_fine(v));
    v = max(v, v + side.y * ddy_fine(v));
    return v;
}

// First pass, writes each pixel's vergence to alpha so one grab fetch gives colour and depth
float4 fragVergence(v2f i) : SV_Target
{
    UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(i);

    if (!VisionActive()) discard;

    // The depth texture never took the grab's platform flip
    float2 uv = i.grab.xy / i.grab.w;
    float2 depthUv = float2(uv.x, _ProjectionParams.x * (0.5 - uv.y) + 0.5);

    // The eye focuses on the slant distance, not the depth along the view axis
    float2 tangent = (i.uv * 2.0 - 1.0) / float2(abs(UNITY_MATRIX_P._m00), abs(UNITY_MATRIX_P._m11));

    // Vergence is linear in raw depth, and the sky lands on the far plane
    float vergence = (_ZBufferParams.z * VISION_SAMPLE_DEPTH(depthUv) + _ZBufferParams.w)
                   * rsqrt(1.0 + dot(tangent, tangent));

    return float4(0.0, 0.0, 0.0, saturate(vergence / VISION_VERGENCE_RANGE));
}

fixed4 frag(v2f i) : SV_Target
{
    UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(i);

    if (!VisionActive()) discard;

    // ComputeGrabScreenPos already handles the platform flip
    float2 uv = i.grab.xy / i.grab.w;

    float4 centre = VisionGrab(uv);
    float vergence = centre.a;

    VisionRx rx = VisionPrescription();
    float2 defocus = VisionDefocus(rx, vergence);
    float ownMax = max(defocus.x, defocus.y);

    float uvPerDioptre = VisionUvPerDioptre();
    float minDioptres = VISION_MIN_RADIUS / uvPerDioptre;

    float s, c;
    sincos(radians(rx.axis), s, c);
    float2x2 axis = float2x2(c, -s, s, c);

    float2 noise = VisionNoise(i.pos.xy, VISION_NOISE_CELL);

    int taps = (int)clamp(_Quality, VISION_MIN_TAPS, VISION_MAX_TAPS);
    float rrStep = 1.0 / taps;
    float rr = noise.y * rrStep;
    float2 dir = VisionDirection(noise.x * UNITY_TWO_PI);

    // The centre always counts, so a fully rejected pixel keeps its colour
    float3 sum = centre.rgb;
    float weight = 1.0;

    // Uniform branch, so every quad reaches the scout whole
    if (_DepthReject < 0.5)
    {
        if (ownMax < minDioptres) return VisionOut(centre.rgb, 0.0);

        float2 plainExtent = min(defocus * uvPerDioptre, VISION_MAX_RADIUS);
        float2x2 plain = VisionEllipse(axis, plainExtent);

        [loop]
        for (int t = 0; t < VISION_MAX_TAPS; t++)
        {
            if (t >= taps) break;

            float2 p = mul(plain, dir * sqrt(rr));
            VisionStep(dir, rr, VISION_TURN, rrStep);

            sum += VisionGrab(uv + p).rgb;
            weight += 1.0;
        }

        return VisionOut(sum / weight, max(plainExtent.x, plainExtent.y));
    }

    // Scout for the widest blur among nearer surfaces, the only ones that can spill here
    // The quad shares one spiral, each pixel taking every fourth tap
    uint2 pixel = (uint2)i.pos.xy;
    uint lane = (pixel.x & 1) + (pixel.y & 1) * 2;

    int laneTaps = (max(taps >> 1, VISION_MIN_TAPS) + 3) >> 2;
    float scoutStep = 1.0 / (laneTaps * 4);

    float scoutExtent = min(VISION_SEARCH * uvPerDioptre, VISION_MAX_RADIUS);
    float2x2 scout = VisionEllipse(axis, float2(scoutExtent, scoutExtent));

    float2 quadNoise = VisionNoise(i.pos.xy, 2.0);
    float2 sdir = VisionDirection(quadNoise.x * UNITY_TWO_PI + lane * VISION_GOLDEN);
    float srr = (quadNoise.y + lane) * scoutStep;
    float reach = 0.0;

    [loop]
    for (int k = 0; k < VISION_MAX_TAPS / 4; k++)
    {
        if (k >= laneTaps) break;

        float2 sp = mul(scout, sdir * sqrt(srr));
        VisionStep(sdir, srr, VISION_TURN4, scoutStep * 4.0);

        float sVergence = VisionGrab(uv + sp).a;
        float2 sDefocus = VisionDefocus(rx, sVergence);

        reach = max(reach, sVergence > vergence ? max(sDefocus.x, sDefocus.y) : 0.0);
    }

    reach = VisionQuadMax(reach, pixel);

    if (max(reach, ownMax) < minDioptres) return VisionOut(centre.rgb, 0.0);

    // Disc to sample, in dioptres per meridian. The own ellipse, or a circle covering what
    // was found in front, since the ellipse can be as thin as a focal line
    float wide = max(reach, ownMax);
    float2 discDioptres = reach > min(defocus.x, defocus.y) ? float2(wide, wide) : defocus;

    // Taken back through the cap, so the weights match the disc actually sampled
    float2 extent = min(discDioptres * uvPerDioptre, VISION_MAX_RADIUS);
    discDioptres = extent / uvPerDioptre;

    float2x2 kernel = VisionEllipse(axis, extent);

    float invOwn = 1.0 / max(defocus.x + defocus.y, 2e-4);
    float2 invDefocus = 1.0 / max(defocus, 1e-4);

    [loop]
    for (int t = 0; t < VISION_MAX_TAPS; t++)
    {
        if (t >= taps) break;

        // Position in the unit disc, and its offset in dioptres per meridian
        float2 q = dir * sqrt(rr);
        float2 offset = q * discDioptres;
        float2 p = mul(kernel, q);
        VisionStep(dir, rr, VISION_TURN, rrStep);

        float4 tap = VisionGrab(uv + p);
        float2 tapDefocus = VisionDefocus(rx, tap.a);

        // Inside the own blur, weighted by how blurred the tap is, so sharp surfaces cannot spill
        float ownWeight = saturate((tapDefocus.x + tapDefocus.y) * invOwn);

        // Outside it, only a nearer surface whose blur reaches here counts, fading over its last quarter
        float tapReach = length(offset / max(tapDefocus, 1e-4));
        float frontWeight = saturate((1.0 - tapReach) * 4.0) * (tap.a > vergence ? 1.0 : 0.0);

        float w = length(offset * invDefocus) <= 1.0 ? ownWeight : frontWeight;

        sum += tap.rgb * w;
        weight += w;
    }

    return VisionOut(sum / weight, max(extent.x, extent.y));
}

// Third pass. Averages each pixel with its 8 neighbours to smooth the gather's grain, only
// where the blur is a few pixels wide so the extra pixel cannot show, then applies colour vision
fixed4 fragDenoise(v2f i) : SV_Target
{
    UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(i);

    bool blurred = VisionActive();
    if (!blurred && !VisionColourActive()) discard;

    float2 uv = i.grab.xy / i.grab.w;
    float4 centre = VISION_SAMPLE_BLUR(VisionClampUv(uv));
    float3 colour = centre.rgb;

    // Without the blur passes the alpha holds no radius, only whatever the scene left
    float radiusPixels = blurred ? centre.a * VISION_MAX_RADIUS * _ScreenParams.y : 0.0;
    float strength = saturate((radiusPixels - 1.0) / 4.0) * _Denoise;

    [branch]
    if (strength > 0.0)
    {
        float2 texel = 1.0 / _ScreenParams.xy;
        float3 sum = centre.rgb;
        float weight = 1.0;

        [unroll]
        for (int y = -1; y <= 1; y++)
        {
            [unroll]
            for (int x = -1; x <= 1; x++)
            {
                if (x == 0 && y == 0) continue;

                float4 n = VISION_SAMPLE_BLUR(VisionClampUv(uv + float2(x, y) * texel));

                // A sharper neighbour is another surface, kept from bleeding into this blur
                float w = saturate(n.a / centre.a);
                sum += n.rgb * w;
                weight += w;
            }
        }

        colour = lerp(centre.rgb, sum / weight, strength);
    }

    return fixed4(VisionColour(colour), 1.0);
}

#endif
