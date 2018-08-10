--[[
%% properties
55 value
%% events
66 CentralSceneEvent
%% globals
counter
--]]

--[[
-- EventRunnerLight. Single scene instance framework
-- Copyright 2018 Jan Gabrielsson. All Rights Reserved.
-- Email: jan@gabrielsson.com
--]]

_version = "1.0" 
osTime = os.time
osDate = os.date
if dofile then dofile("EventRunnerDebug.lua") end -- Support for running off-line on PC/Mac

---- Single scene instance, all fibaro triggers call main(sourceTrigger) ------------

local currentKey = nil -- Hey, this lua variable keeps its value between scene triggers
local time = osTime() -- Hey, this lua variable keeps its value between scene triggers
local function printf(...) fibaro:debug(string.format(...)) end

function main(sourceTrigger)
  local event = sourceTrigger

-- Example scene triggering on Fibaro remote keys 1-2-3 within 2x3seconds
  if event.type == 'CentralSceneEvent' then
    local keyPressed = event.event.data.keyId
    if keyPressed == '1' then 
      currentKey=1
      time=osTime()
      printf("1 pressed %s at",osDate("%X"))
    elseif keyPressed == '2' and currentKey==1 and osTime()-time < 3 then
      currentKey = 2
      time=osTime()
      printf("2 pressed %s at ",osDate("%X"))
    elseif keyPressed == '3' and currentKey==2 and osTime()-time < 3 then
      printf("Key 1-2-3 pressed within 2x3sec at %s",osDate("%X"))
    end
  end

  -- Test logic by posting events in 3,5, and 7 seconds
  if event.type=='autostart' or event.type=='other' then
    setTimeout(function() main({type='CentralSceneEvent',event={data={keyId='1'}}}) end,3000,"A")
    setTimeout(function() main({type='CentralSceneEvent',event={data={keyId='2'}}}) end,5000,"B")
    setTimeout(function() main({type='CentralSceneEvent',event={data={keyId='3'}}}) end,7000,"C")
  end

end -- main()

------------------------ Framework, do not change ---------------------------  
-- Spawned scene instances post triggers back to starting scene instance ----
local _trigger = fibaro:getSourceTrigger()
local _type, _source = _trigger.type, _trigger
local _MAILBOX = "MAILBOX"..__fibaroSceneId 

if _type == 'other' and fibaro:args() then
  _trigger,_type = fibaro:args()[1],'remote'
end

---------- Producer(s) - Handing over incoming triggers to consumer --------------------
if ({property=true,global=true,event=true,remote=true})[_type] then
  local event = type(_trigger) ~= 'string' and json.encode(_trigger) or _trigger
  local ticket = string.format('<@>%s%s',tostring(_source),event)
  repeat 
    while(fibaro:getGlobal(_MAILBOX) ~= "") do fibaro:sleep(100) end -- try again in 100ms
    fibaro:setGlobal(_MAILBOX,ticket) -- try to acquire lock
  until fibaro:getGlobal(_MAILBOX) == ticket -- got lock
  fibaro:setGlobal(_MAILBOX,event) -- write msg
  fibaro:abort() -- and exit
end

local function _poll()
  local l = fibaro:getGlobal(_MAILBOX)
  if l and l ~= "" and l:sub(1,3) ~= '<@>' then -- Something in the mailbox
    fibaro:setGlobal(_MAILBOX,"") -- clear mailbox
    setTimeout(function() main(json.decode(l)) end, 0) -- and "post" it to our "main()" in new "thread"
  end
  setTimeout(_poll,250) -- check every 250ms
end

if _type == 'autostart' or _type == 'other' then
  if not _OFFLINE and fibaro:getGlobalModificationTime(_MAILBOX) == nil then
    api.post("/globalVariables/",{name=_MAILBOX})
  end 
  if not _OFFLINE then 
    fibaro:setGlobal(_MAILBOX,"") 
    _poll()  -- start polling mailbox
    main(_trigger)
  else
    collectgarbage("collect") GC=collectgarbage("count")
    _System.runOffline(function() main(_trigger) end) 
  end
end
