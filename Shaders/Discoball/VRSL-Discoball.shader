﻿Shader "VRSL/Other/Discoball"
 {
     Properties
     {
         [HideInInspector]_Sector ("DMX Fixture Number/Sector (Per 13 Channels)", Int) = 0

         [Toggle] _EnableCompatibilityMode ("Enable Compatibility Mode", Int) = 0
         [Toggle] _EnableOSC ("Enable Stream OSC/DMX Control", Int) = 0
         [NoScaleOffset] _OSCGridRenderTextureRAW("OSC Grid Render Texture (RAW Unsmoothed)", 2D) = "white" {}
         _GlobalIntensity("Global Intensity", Range(0,1)) = 1
         _FinalIntensity("Final Intensity", Range(0,1)) = 1
         _UniversalIntensity ("Universal Intensity", Range (0,1)) = 1
         [HDR]_Emission ("Color", Color) = (1.0, 1.0, 1.0, .2)
         _Cube ("Projection Map", Cube) = "" {}
         [Toggle] _UseWorldNorm("Use World Normal vs View Normal", Float) = 0
         _RotationSpeed ("Rotation Speed", Range (-180,180)) = 8.2
         _Multiplier("Brightness Multiplier", Range(0, 10)) = 1

     }
     SubShader
     {
         Tags{ "Queue" = "Transparent+1" "ForceNoShadowCasting"="True" "IgnoreProjector"="True" "RenderType" = "Transparent" }
         Offset -1, -5
        	Stencil
			{
				Ref 148
				Comp NotEqual
				Pass Keep
			}

         Pass
         {
            Cull Off
            Ztest Greater
            ZWrite Off
            Blend DstColor One 
            Lighting Off
		    SeparateSpecular Off
             CGPROGRAM
             #pragma vertex vert
             #pragma fragment frag
            uniform samplerCUBE _Cube;
            float4 _Cube_ST;
            float _RotationSpeed;
            #include "UnityCG.cginc"
             struct appdata
             {
                 float4 vertex : POSITION;
                 float2 uv : TEXCOORD0;
                 float3 texcoord : TEXCOORD1;
             };
             struct v2f
             {
                 float4 vertex : SV_POSITION;
                 float2 uv : TEXCOORD0;
                 float3 ray : TEXCOORD2;
                 float4 screenPos : TEXCOORD4;
                 float4 worldDirection : TEXCOORD5;
                 float4 worldPos : TEXCOORD6;
                 float2 sectorIntensity: TEXCOORD7;
             };
            #include "../Shared/VRSL-Defines.cginc"
            half _Multiplier;
			#include "../Shared/VRSL-DMXFunctions.cginc"

             float4 Rotation(float4 vertPos)
             {
                 
	            //CALCULATE BASE ROTATION. MORE FUN MATH. THIS IS FOR PAN.
                float angleY = radians(_Time.y * _RotationSpeed);
                float c = cos(angleY);
                float s = sin(angleY);
                float4x4 rotateYMatrix = float4x4(c, 0, s, 0,
                    0, 1, 0, 0,
                    -s, 0, c, 0,
                    0, 0, 0, 1);

                return mul(rotateYMatrix, vertPos);
             }
            inline float4 CalculateFrustumCorrection()
            {
                float x1 = -UNITY_MATRIX_P._31/(UNITY_MATRIX_P._11*UNITY_MATRIX_P._34);
                float x2 = -UNITY_MATRIX_P._32/(UNITY_MATRIX_P._22*UNITY_MATRIX_P._34);
                return float4(x1, x2, 0, UNITY_MATRIX_P._33/UNITY_MATRIX_P._34 + x1*UNITY_MATRIX_P._13 + x2*UNITY_MATRIX_P._23);
            }

             
            //CREDIT TO DJ LUKIS FOR MIRROR DEPTH CORRECTION
            inline float CorrectedLinearEyeDepth(float z, float B)
            {
                return 1.0 / (z/UNITY_MATRIX_P._34 + B);
            }


             v2f vert(appdata v)
             {
                v2f o;
                UNITY_INITIALIZE_OUTPUT(v2f, o);
                UNITY_SETUP_INSTANCE_ID(v);

                o.vertex = UnityObjectToClipPos(v.vertex);
                o.ray = UnityObjectToViewPos(v.vertex).xyz;
                o.ray = o.ray.xyz * float3(-1,-1,1);
                o.ray = lerp(o.ray, v.texcoord, v.texcoord.z != 0);
                o.worldPos = mul(unity_ObjectToWorld, v.vertex);
                o.screenPos = ComputeScreenPos(o.vertex);
                o.worldDirection.xyz = o.worldPos.xyz - _WorldSpaceCameraPos;
                // pack correction factor into direction w component to save space
                o.worldDirection.w = dot(o.vertex, CalculateFrustumCorrection());
                uint sector = getChannelSectorX();
                o.sectorIntensity = IF(_EnableCompatibilityMode == 1, float2(sector, getValueAtCoords(0.019231, 0.019231, sector, _OSCGridRenderTextureRAW)), float2(sector, getValueAtCoords(0.038017, standardSampleYAxis, sector, _OSCGridRenderTextureRAW)));
                if(o.sectorIntensity.y <= 0.05 && _EnableOSC == 1)
                {
                    v.vertex = float4(0,0,0,0);
                    o.vertex = UnityObjectToClipPos(v.vertex);

                }
                return o;
             }

             #define IF(a, b, c) lerp(b, c, step((fixed) (a), 0));


             fixed4 frag(v2f i) : SV_Target
             {
                if(i.sectorIntensity.y <= 0.05 && _EnableOSC == 1)
                {
                    return half4(0,0,0,0);
                }
                float4 depthdirect = i.worldDirection * (1.0f / i.vertex.w);
                float sceneZ = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, i.screenPos.xy / i.screenPos.w);
                #if UNITY_REVERSED_Z
                    if (sceneZ == 0)
                #else
                    if (sceneZ == 1)
                #endif
                        return half4(0,0,0,0);
                        
                float depth = CorrectedLinearEyeDepth(sceneZ, depthdirect.w);
                i.ray = i.ray * (_ProjectionParams.z / i.ray.z); 
                depth = Linear01Depth((1.0 - (depth * _ZBufferParams.w)) / (depth * _ZBufferParams.z));
                float3 wpos = mul(unity_CameraToWorld, float4(i.ray * depth, 1)).xyz;
                float UVscale = pow(abs(distance( mul(unity_ObjectToWorld, float4(0.0,0.0,0.0,1.0) ).xyz,wpos)),-1);
                float3 projPos = (mul(unity_WorldToObject,float4(wpos, 1)));
                if(0.0 < abs(projPos.x) < 0.1)
                {
                    return half4(0,0,0,0);
                }
                projPos = Rotation(float4(projPos, 0)).xyz;
                float4 col = (texCUBE (_Cube, projPos));
                col = col *(_Emission * (4*UVscale));
                col = IF(_EnableOSC == 1, col * i.sectorIntensity.y, col);
                col = (col * _Multiplier)*((col * getGlobalIntensity()) * getFinalIntensity());
                col = col * _UniversalIntensity;
                return col;
             }
             ENDCG
         }//end color pass
     }
     CustomEditor "VRSLInspector"
 }