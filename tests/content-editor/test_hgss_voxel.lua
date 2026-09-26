-- Verify geometry, GPU depth ownership and native character isolation contracts.
local root="mods/firered_hgss_voxel/"
local state={}
love={graphics={}}
local g=love.graphics
function g.newShader(source)
 assert(source:find("vp%*vec4") and source:find("discard"),"needs 3D projection and alpha cutout")
 return {send=function(_,key,...) state[key]={...} end}
end
function g.newMesh(format,vertices,mode)
 assert(format[1][3]==3 and mode=="triangles","must use XYZ triangle geometry")
 return {vertices=vertices,setTexture=function()end}
end
function g.newCanvas(w,h) return {setFilter=function()end,release=function()end} end
function g.setCanvas(target) assert(target.depth==true,"depth buffer required") end
function g.setDepthMode(mode,write) state.depth={mode,write} end
for _,name in ipairs({"origin","setScissor","clear","setMeshCullMode","setBlendMode","setColor","setShader","draw"}) do g[name]=function()end end
local V={}
function V.require(name)
 local v=assert(loadfile(root.."lib/"..name..".lua"))()
 if type(v)=="function" then return v(V) end
 return v
end
local R=V.require("Renderer")
local vertices={};R.box(vertices,10,0,20,16,32,16,{1,1,1})
assert(#vertices==30,"solid box needs top plus four side faces")
local minY,maxY=math.huge,-math.huge
for _,v in ipairs(vertices) do minY=math.min(minY,v[2]);maxY=math.max(maxY,v[2]) end
assert(minY==0 and maxY==32,"box must occupy real vertical space")
R.mesh(vertices)
R.begin(240,160,100,100)
assert(state.depth[1]=="less" and state.depth[2]==true,"depth testing/writing must be active")
local before={unpack(R.vp)};R.yaw=R.yaw+math.pi/2;R.begin(240,160,100,100)
assert(math.abs(before[1]-R.vp[1])>.1,"orbit must change the 3D view matrix")
R.finish();assert(state.depth[1]==nil,"depth mode must be cleared for UI")
print("PASS: XYZ geometry, solid faces, depth test, camera orbit and UI cleanup")
