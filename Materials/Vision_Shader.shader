Shader "Moontail/Vision"
{
    Properties
    {
        [HideInInspector] _IsLocal ("Worn locally", Float) = 0
        [Toggle] _Enabled ("Enabled", Float) = 1

        _SphereL ("Sphere left", Range(-8.0, 8.0)) = 0.0
        _CylinderL ("Cylinder left", Range(-4.0, 0.0)) = 0.0
        _AxisL ("Axis left", Range(0.0, 180.0)) = 0.0

        _SphereR ("Sphere right", Range(-8.0, 8.0)) = 0.0
        _CylinderR ("Cylinder right", Range(-4.0, 0.0)) = 0.0
        _AxisR ("Axis right", Range(0.0, 180.0)) = 0.0

        [Toggle] _SyncRight ("Sync right eye to left", Float) = 1

        _PupilMM ("Pupil diameter (mm)", Range(2.0, 8.0)) = 4.0

        // Raise for presbyopia
        _NearPoint ("Near point (m)", Range(0.12, 1.5)) = 0.12

        // Scales every blur, 1 is physically true
        _Gain ("Exaggeration", Range(1.0, 12.0)) = 1.0

        // Grows blurs too small for the headset to show, leaving large ones alone. 1 is physically exact
        _Boost ("Small blur boost", Range(1.0, 8.0)) = 4.0

        // Taps per pixel, the cost scales with it
        _Quality ("Quality (taps)", Range(8.0, 64.0)) = 24.0

        // Keeps a sharp foreground from spilling over a blurred background
        [Toggle] _DepthReject ("Depth rejection", Float) = 1

        // Smooths the blur's grain, at the cost of a second grab
        [Toggle] _Denoise ("Denoise", Float) = 1

        // 0 normal, 1 protan, 2 deutan, 3 tritan, 4 achromat
        [IntRange] _ColorType ("Color vision", Range(0, 4)) = 0

        // From mild anomalous trichromacy near 0 to full dichromacy at 1
        _ColorSeverity ("Color vision severity", Range(0.0, 1.0)) = 1.0

    }

    SubShader
    {
        Tags { "Queue" = "Overlay+3" "RenderType" = "Overlay" "IgnoreProjector" = "True" "VRCFallback" = "Hidden" }

        CGINCLUDE
        #include "UnityCG.cginc"

        // Unity reads the filter and wrap from the name
        SamplerState sampler_point_clamp;

        // An array where each eye owns a slice. Point sampled, so a tap on an edge cannot
        // blend in a rejected surface or average two vergences
        #if defined(UNITY_STEREO_INSTANCING_ENABLED) || defined(UNITY_STEREO_MULTIVIEW_ENABLED)
            Texture2DArray<float4> _VisionGrabTex;
            Texture2DArray<float4> _VisionBlurTex;
            #define VISION_SAMPLE(uv) _VisionGrabTex.SampleLevel(sampler_point_clamp, float3((uv).xy, (float)unity_StereoEyeIndex), 0)
            #define VISION_SAMPLE_BLUR(uv) _VisionBlurTex.SampleLevel(sampler_point_clamp, float3((uv).xy, (float)unity_StereoEyeIndex), 0)
        #else
            Texture2D<float4> _VisionGrabTex;
            Texture2D<float4> _VisionBlurTex;
            #define VISION_SAMPLE(uv) _VisionGrabTex.SampleLevel(sampler_point_clamp, (uv).xy, 0)
            #define VISION_SAMPLE_BLUR(uv) _VisionBlurTex.SampleLevel(sampler_point_clamp, (uv).xy, 0)
        #endif

        // Typed rather than UNITY_DECLARE_DEPTH_TEXTURE, so its size can be queried
        #if defined(UNITY_STEREO_INSTANCING_ENABLED) || defined(UNITY_STEREO_MULTIVIEW_ENABLED)
            Texture2DArray<float> _CameraDepthTexture;
            #define VISION_DEPTH_SIZE(d) _CameraDepthTexture.GetDimensions((d).x, (d).y, (d).z)
            #define VISION_DEPTH_DIMS float3
            #define VISION_SAMPLE_DEPTH(uv) _CameraDepthTexture.SampleLevel(sampler_point_clamp, float3((uv).xy, (float)unity_StereoEyeIndex), 0)
        #else
            Texture2D<float> _CameraDepthTexture;
            #define VISION_DEPTH_SIZE(d) _CameraDepthTexture.GetDimensions((d).x, (d).y)
            #define VISION_DEPTH_DIMS float2
            #define VISION_SAMPLE_DEPTH(uv) _CameraDepthTexture.SampleLevel(sampler_point_clamp, (uv).xy, 0)
        #endif

        #include "Vision_Core.cginc"
        ENDCG

        // Vergence into alpha, for the grab below to carry
        Pass
        {
            Cull Off
            ZWrite Off
            ZTest Always
            Blend Off
            ColorMask A

            CGPROGRAM
            #pragma vertex vert
            #pragma fragment fragVergence
            #pragma multi_compile_instancing

            // Texture arrays need a recent target
            #pragma target 5.0
            ENDCG
        }

        // Named, so shaders using the default grab keep theirs
        GrabPass { "_VisionGrabTex" }

        Pass
        {
            Cull Off
            ZWrite Off
            ZTest Always
            Blend Off

            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_instancing
            #pragma target 5.0
            ENDCG
        }

        // The blurred frame, with its blur radius in alpha
        GrabPass { "_VisionBlurTex" }

        Pass
        {
            Cull Off
            ZWrite Off
            ZTest Always
            Blend Off

            CGPROGRAM
            #pragma vertex vert
            #pragma fragment fragDenoise
            #pragma multi_compile_instancing
            #pragma target 5.0
            ENDCG
        }
    }

    Fallback Off
}
