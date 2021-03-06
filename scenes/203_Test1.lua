--[[
%% properties
55 value
66 value
77 value
%% events
88 CentralSceneEvent
99 sceneActivation
100 AccessControlEvent
%% globals
%% autostart
--]] 

if dofile and not _EMULATED then _EMBEDDED={name="Test1",id=203} dofile("HC2.lua") end

function printf(...) fibaro:debug(string.format(...)) end

local trigger = fibaro:getSourceTrigger()
printf("Hello from Test1(%s):%s",__fibaroSceneId,json.encode(trigger))
if fibaro:args() then printf("Got arguments:%s",json.encode(fibaro:args())) end

printf("Looping 5 times, every 5min")

for i=1,5 do
  fibaro:debug("PING")
  fibaro:sleep(5*60*1000)
end