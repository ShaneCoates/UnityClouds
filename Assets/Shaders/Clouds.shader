// Upgrade NOTE: replaced '_Object2World' with 'unity_ObjectToWorld'
// Upgrade NOTE: replaced 'mul(UNITY_MATRIX_MVP,*)' with 'UnityObjectToClipPos(*)'

Shader "Unlit/Clouds"
{
	Properties
	{
		_Density("Cloud Density", Range(-0.5, 0.5)) = 0.5
		_Horizon("Horizon Strength", Range(0.0, 1.5)) = 0.6

		_MarchSteps("March Steps", Int) = 48
		_MinHeight("Min Height", Float) = 2000
		_MaxHeight("Max Height", Float) = 2800

	}
	SubShader
	{ 
		Tags{ "Queue" = "Background"}
		LOD 100
		ZWrite Off
		Pass
		{
			CGPROGRAM
			#pragma vertex vert
			#pragma fragment frag
			
			

			#include "UnityCG.cginc"
			#include "Lighting.cginc"


			struct appdata
			{
				fixed4 vertex : POSITION;
				fixed2 uv : TEXCOORD0;
			};

			struct v2f
			{
				fixed4 vertexWorldPos : TEXCOORD0;
				fixed4 vertex : SV_POSITION;
			};

			fixed _Density;
			fixed _Horizon;
			int _MarchSteps;
			fixed _MinHeight;
			fixed _MaxHeight;
#define MOD2 fixed2(.16632,.17369)
#define MOD3 fixed3(.16532,.17369,.15787)
			v2f vert (appdata v)
			{
				v2f o;
				o.vertex = UnityObjectToClipPos(v.vertex);
				o.vertexWorldPos = mul(unity_ObjectToWorld, v.vertex);
				UNITY_TRANSFER_FOG(o,o.vertex);
				return o;
			}
			fixed Hash(fixed p)
			{
				fixed2 p2 = frac(fixed2(p, p) * MOD2);
				p2 += dot(p2.yx, p2.xy + 19.19);
				return frac(p2.x * p2.y);
			}
			fixed Hash(fixed3 p)
			{
				p = frac(p * MOD3);
				p += dot(p.xyz, p.yzx + 19.19);
				return frac(p.x * p.y * p.z);
			}
			fixed Noise(in fixed2 x)
			{
				fixed2 p = floor(x);
				fixed2 f = frac(x);
				f = f*f*(3.0 - 2.0*f);
				fixed n = p.x + p.y*57.0;
				fixed res = lerp(lerp(Hash(n + 0.0), Hash(n + 1.0), f.x),
					lerp(Hash(n + 57.0), Hash(n + 58.0), f.x), f.y);
				return res;
			}
			fixed Noise(in fixed3 p)
			{
				fixed3 i = floor(p);
				fixed3 f = frac(p);
				f *= f * (3.0 - 2.0*f);

				return lerp(
					lerp(lerp(Hash(i + fixed3(0., 0., 0.)), Hash(i + fixed3(1., 0., 0.)), f.x),
						lerp(Hash(i + fixed3(0., 1., 0.)), Hash(i + fixed3(1., 1., 0.)), f.x),
						f.y),
					lerp(lerp(Hash(i + fixed3(0., 0., 1.)), Hash(i + fixed3(1., 0., 1.)), f.x),
						lerp(Hash(i + fixed3(0., 1., 1.)), Hash(i + fixed3(1., 1., 1.)), f.x),
						f.y),
					f.z);
			}

			// Maps x from the range [minX, maxX] to the range [minY, maxY]
			// The function does not clamp the result, as it may be useful
			fixed mapTo(fixed x, fixed minX, fixed maxX, fixed minY, fixed maxY)
			{
				fixed a = (maxY - minY) / (maxX - minX);
				fixed b = minY - a * minX;
				return a * x + b;
			}
			fixed FBM(fixed3 p)
			{
				p *= .25;
				fixed f;

				f = 0.5000 * Noise(p); p = p * 3.02; p.z -= _Time.x;
				f += 0.2500 * Noise(p); p = p * 3.03; p.z += _Time.y;
				f += 0.1250 * Noise(p); p = p * 3.01;
				f += 0.0625   * Noise(p); p = p * 3.03;
				f += 0.03125  * Noise(p); p = p * 3.02;
				f += 0.015625 * Noise(p);
				return f;
			}
			fixed Map(fixed3 p)
			{
				p *= .002;
				p.x += _Time.x;
				fixed h = FBM(p);
				return h - _Density - .5;
			}
			

			//--------------------------------------------------------------------------
			// Grab all sky information for a given ray from camera
			fixed3 GetSky(in fixed3 pos, in fixed3 rd, out fixed2 outPos)
			{
				fixed sunAmount = max(dot(rd, _WorldSpaceLightPos0.xyz), 0.0);
				// Do the blue and sun...	
				fixed3  sky = lerp(fixed3(.0, .1, .4), fixed3(.3, .6, .8), 1.0 - rd.y);
				sky = sky + _WorldSpaceLightPos0.xyz * min(pow(sunAmount, 1500.0) * 5.0, 1.0);
				sky = sky + _WorldSpaceLightPos0.xyz * min(pow(sunAmount, 10.0) * .6, 1.0);

				// Find the start and end of the cloud layer...
				fixed beg = ((_MinHeight - pos.y) / rd.y);
				fixed end = ((_MaxHeight - pos.y) / rd.y);

				// Start position...
				fixed3 p = fixed3(pos.x + rd.x * beg, 0.0, pos.z + rd.z * beg);
				outPos = p.xz;
				beg += Hash(p)*150.0;

				// Trace clouds through that layer...
				fixed d = 0.0;
				fixed3 add = rd * ((end - beg) / _MarchSteps);
				fixed2 shade;
				fixed2 shadeSum = fixed2(0.0, .0);
				fixed difference = _MaxHeight - _MinHeight;
				shade.x = .01;
				for (int i = 0; i < _MarchSteps; i++)
				{
					if (shadeSum.y >= 1.0) break;
					fixed h = Map(p);
					shade.y = max(-h, 0.0);
					shade.x = p.y / difference;  // Grade according to height
					shadeSum += shade * (1.0 - shadeSum.y);

					p += add;
				}
				shadeSum.x /= 10.0;
				shadeSum = min(shadeSum, 1.0);

				fixed3 clouds = lerp(fixed3(pow(shadeSum.x, .4), pow(shadeSum.x, .4), pow(shadeSum.x, .4)), _LightColor0.xyz, (1.0 - shadeSum.y)*.4);

				clouds += min((1.0 - sqrt(shadeSum.y)) * pow(sunAmount, 4.0), 1.0) * 2.0;

				sky = lerp(sky, min(clouds, 1.0), shadeSum.y);

				return clamp(sky, 0.0, 1.0);
			}

			fixed4 frag (v2f i) : SV_Target
			{
				fixed3 ro = _WorldSpaceCameraPos;
				fixed3 rd = normalize(i.vertexWorldPos - ro);
				fixed gTime = _Time.w*.5+ 75.5;
				fixed2 pos;
				fixed4 col = fixed4(0, 0, 0, 0);
				if (rd.y >= -0.01)
				{
					col = fixed4(GetSky(ro, rd, pos), 1.0);
					fixed l = exp(-length(pos) * .00002);
					fixed horiz = _Horizon - _Density*1.2;
					col.rgb = lerp(fixed3(horiz, horiz, horiz), col, max(l, .2));

					col.rgb = pow(col, fixed3(.7, .7, .7));
				}
				else
				{
					clip(-1);
					return fixed4(0, 0, 0, 0);
				}
				


				return col;
			}
			ENDCG
		}
	}
}
