Shader "Unlit/Clouds"
{
	Properties
	{
		_SkyColor("Sky Color", Color) = (.0, .1, .4, 1)
		_HorizonColor("Horizon Color", Color) = (.3, .6, .8, 1)

		_Density("Cloud Density", Range(0.0, 1.0)) = 0.5
		_Horizon("Horizon Strength", Range(0.0, 1.5)) = 0.6

		_MajorSpeed("Major Speed", Float) = 1
		_MinorSpeed("Minor Speed", Float) = 1

		_MinHeight("Min Height", Float) = 2000
		_MaxHeight("Max Height", Float) = 2800


		_MarchSteps("March Steps", Int) = 48
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

			fixed4 _SkyColor;
			fixed4 _HorizonColor;
			
			fixed _MajorSpeed;
			fixed _MinorSpeed;

			int _MarchSteps;

			fixed _MinHeight;
			fixed _MaxHeight;
			
			#define MOD3 fixed3(.16532,.17369,.15787)

			v2f vert (appdata v)
			{
				v2f o;
				o.vertex = UnityObjectToClipPos(v.vertex);
				o.vertexWorldPos = mul(unity_ObjectToWorld, v.vertex);
				return o;
			}
			fixed Hash(fixed3 p)
			{
				p = frac(p * MOD3);
				p += dot(p.xyz, p.yzx + 19.19);
				return frac(p.x * p.y * p.z);
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

			fixed FBM(fixed3 p)
			{
				p *= .25;
				fixed f;

				f = 0.5000		* Noise(p); p = p * 3.02; p.z -= (_Time.y * _MajorSpeed);
				f += 0.2500		* Noise(p); p = p * 3.03; p.z += (_Time.y * _MinorSpeed);
				f += 0.1250		* Noise(p); p = p * 3.01;
				f += 0.0625		* Noise(p); p = p * 3.03;
				f += 0.03125	* Noise(p); p = p * 3.02;
				f += 0.015625	* Noise(p);
				return f;
			}

			fixed Map(fixed3 p)
			{
				//Spread our noise out, like a lot
				p *= .002;
				
				//Add a little bit of movement
				p.x += _Time.x;

				//Get density
				fixed h = FBM(p);

				//Return the calculated density, adjusted by the value set in the inspector
				return h - _Density;
			}
			

			//--------------------------------------------------------------------------
			// Grab all sky information for a given ray from camera
			fixed3 GetSky(in fixed3 pos, in fixed3 rayDirection, out fixed2 outPos)
			{
				
				//Start with a blue gradient for our sky
				fixed3 sky = lerp(_SkyColor, _HorizonColor, 1.0 - rayDirection.y);
				
				//Get start and end of cloud layer
				fixed minCloudHeight = ((_MinHeight - pos.y) / rayDirection.y);
				fixed maxCloudHeight = ((_MaxHeight - pos.y) / rayDirection.y);

				//Start at the bottom of the cloud layer
				fixed3 p = fixed3(pos.x + rayDirection.x * minCloudHeight, 0.0, pos.z + rayDirection.z * minCloudHeight);
				outPos = p.xz;

				//Cache the size of a single step, to add to our position each iteration
				fixed3 step = rayDirection * ((maxCloudHeight - minCloudHeight) / _MarchSteps);

				//Used per iteration to calculate the density
				fixed2 shade;

				//The overall density is stored here throughout the march
				fixed2 shadeSum = fixed2(0.0, 0.0);

				//The distance between top and bottom of the cloud layer
				fixed difference = _MaxHeight - _MinHeight;

				// Trace clouds through that layer...
				for (int i = 0; i < _MarchSteps; i++)
				{
					//If we've reached max density, break - there's no use continuing
					if (shadeSum.y >= 1.0) break;

					//Calculate the density at this position
					fixed h = Map(p);

					shade.y = max(-h, 0.0);
					shade.x = p.y / difference;  // Grade according to height

					shadeSum += shade * (1.0 - shadeSum.y);

					p += step;
				}
				
				shadeSum.x /= 10.0;
				shadeSum = min(shadeSum, 1.0);
				
				fixed3 cloudCol = fixed3(pow(shadeSum.x, .4), pow(shadeSum.x, .4), pow(shadeSum.x, .4));
				fixed3 clouds = lerp(_LightColor0.xyz, cloudCol, shadeSum.y);

				sky = lerp(sky, min(clouds, 1.0), shadeSum.y);

				return clamp(sky, 0.0, 1.0);
			}

			fixed4 frag (v2f i) : SV_Target
			{
				fixed3 rayOrigin = _WorldSpaceCameraPos;
				fixed3 rayDirection = normalize(i.vertexWorldPos - rayOrigin);
				fixed gTime = _Time.w*.5+ 75.5;
				fixed2 pos;
				fixed4 col = fixed4(0, 0, 0, 0);
				//Cull if our ray direction is facing down
				if (rayDirection.y >= -0.01)
				{
					//Get sky and clouds
					col = fixed4(GetSky(rayOrigin, rayDirection, pos), 1.0);

					//Blend into horizon
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
