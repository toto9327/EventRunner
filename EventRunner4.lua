--[[
%% autostart
--]]

E_VERSION,E_FIX = "Beta 1.0","fix2"

if dofile and not _EMULATED then _EMULATED={name="EventRunner",id=199,maxtime=44} dofile("HC2.lua") end
if loadfile then local cr = loadfile("credentials.lua") if cr then cr() end end
if dofile then dofile("HC3_support.lua") end

if _EMULATED then
  _System.speed(true)                 -- run emulator faster than real-time
  --_System.setRemote("devices",{5})  -- make device 5 remote (call HC3 with api)
end

_debugFlags = { post=true, netSync = false  } 

DEVICE_VERS = "0.1"

function QuickApp:turnOn()
  self:updateProperty("value", true)
end

function QuickApp:turnOff()
  self:updateProperty("value", false)    
end

function QuickApp:main() 

  function test1(a,b) return a+b end  
  function test2(x) return x+1 end 

  dofile("example_rules3.lua")
  
  Util.checkVersion()
  Event.event({type='Event_version'},
    function(env)
      Log(LOG.LOG,"New version %s %s",env.event.version,env.event.fix)
      Util.patchEventRunner() 
    end)

  fibaro.call(69,"setValue",true) 
  Log(LOG.LOG,"Breached:%s",fibaro.getValue(69,"value"))
  setTimeout(function()fibaro.call(69,"setValue",false) Log(LOG.LOG,"Breached:%s",fibaro.getValue(69,"value")) end, 2000)

  exportFunctions{
    {name='test1', doc="Adds 2 numbers"},
    {name='test2', doc="Adds 1"}
  }
  local eh = Event.event({type='property',deviceID=755}, -- Triggering on an 'fake' event we post later
    function(env) self:debug("755") end)

  self:debug(eh) -- Printing out event handler

  self:debug("Hello") -- Just logging a message

  Event.event({type='customevent'}, -- Triggering on all custom event
    function(env) self:debug('Got %s',json.encode(env.event)) end)

  Event.event({type='property', deviceID=49, propertyName='value'}, -- Triggering on a device value change
    function(env) self:debug('Got %s',json.encode(env.event)) end)

  Event.post({type='property',deviceID=755},"+/00:00:02") -- Posting fakse event 2s into the future to trigger our handler

  -- Send an custom event to ourselves in 5 seconds (we can also send to other devices/scenes)
  Event.publishEvent(Event.deviceID,{type='Greeting', msg='Hello'},"+/00:00:05")

  -- Send an custom event to ourselves in 5 seconds (we can also send to other devices/scenes)
  Event.publishEvent(Event.deviceID,{type='Greeting', msg='God morning!'},"n/sunrise+00:10")

  -- Pickup custom event sent earlier
  Event.event({type='Greeting'},function(env)
      self:debug("Greeting '%s' from deviceID:%s",env.event.msg,env.event._from)
    end)

  -- Homemade loop, loop 10 times and flick a light
  Event.event({type='loop', index='$i'},
    function(env)
      if env.p.i < 10 then
        if fibaro.getValue(56,"value") then fibaro.call(56,'turnOff') else fibaro.call(56,'turnOn') end
        Event.post({type='loop', index=env.p.i+1},"+/00:00:02")
      end
    end)
  --QuickApp:post({type='loop', index=0},"+/00:00:02")

  local i = 0 -- Loop 10 times with :schedule construct
--   QuickApp:loop("+/00:00:02",
--     function(env)
--       self:debug("Loop %s",i)
--       i=i+1
--     end
--     ,true
--   )

end --main

function QuickApp:main2()

  local s = Event.loop("00:00:03",function(r) Log(LOG.LOG,"X:%s",r.count) end).disable() -- loop every minute. start disabled
  Event.post(s.enable,"+/00:00:01")  -- enable loop after 2min
  Event.post(s.disable,"+/00:00:20") -- disable loop after 10min
  Log(LOG.LOG,s) -- print rule

  Event.cron("0/15 8-12 * *",function(r) Log(LOG.LOG,"Y:%s",r.count) end) -- cron style loop

  Event.event({type='property', deviceID=88, propertyName='value'},  -- trigger on device property changing
    function(env) Log(LOG.LOG,"Device %s value is %s",env.event.deviceID,env.event.value) end)

  Event.event({type='global', name='myVar'},                         -- trigger on global changing value
    function(env) Log(LOG.LOG,"Global '%s' value is %s",env.event.name,env.event.value) end)

  Event.event({type='customevent', name='myEvent'},        -- trigger on custom event being emitted
    function(env) 
      local name = env.event.name
      Log(LOG.LOG,"Custom event '%s' description is %s",name,Event.getCustomEventDescription(name))
    end)

  Event.event({type='quickvar', name='myQuickvar'}, -- trigger on quickVar changing value
    function(env) Log(LOG.LOG,"QuickVar '%s' description is %s",env.event.name,env.event.value) end)

end

------------------- EventSupport - Don't change! -------------------- 

function createEventEngine(quickSelf) -- Event extension
  Log(LOG.SYS,"Setting up event engine..")
  local self,_handlers = {},{}
  self._sections,self.SECTION = {},nil
  self.BREAK, self.TIMER, self.RULE ='%%BREAK%%', '%%TIMER%%', '%%RULE%%'
  local equal,format,map,mapF,copy,toTime =  Util.equal, string.format, Util.map, Util.mapF, Util.copy, Util.toTime

  local function isTimer(t) return type(t) == 'table' and t[Event.TIMER] end
  local function isRule(r) return type(r) == 'table' and r[Event.RULE] end
  local function isEvent(e) return type(e) == 'table' and e.type end
  self.deviceID = plugin.mainDeviceId
  local smNR,maMatch=0,"^CE"..self.deviceID
  function self.makeAddress(id) smNR=smNR+1; return "CE"..id.."F"..self.deviceID.."N"..smNR end
  function self.isMyAddress(address) return address:match(maMatch)  end
  function self.isBroadcastAddress(address) return address:match("^CE000") end
  self.tickEvent = "TICK"

  local function timer2str(t) 
    return format("<timer:%s, start:%s, stop:%s>",
      t[Event.TIMER],os.date("%c",t.start),os.date("%c",math.floor(t.start+t.len/1000+0.5))) 
  end
  local function mkTimer(f,t) t=t or 0;
    return {[Event.TIMER]=setTimeout(f,t), start=os.time(), len=t, __tostring=timer2str} 
  end

  local function str2event(str)
    local t = str:match("#([%w_]+)")
    _assert(t,"Bad event:"..str)
    local e = str:sub(#t+2)
    e = e:sub(1,1)=='{' and json.decode(e) or {}
    e.type = t
    return e
  end

  local function coerce(x,y) local x1 = tonumber(x) if x1 then return x1,tonumber(y) else return x,y end end
  local constraints = {}
  constraints['=='] = function(val) return function(x) x,val=coerce(x,val) return x == val end end
  constraints['>='] = function(val) return function(x) x,val=coerce(x,val) return x >= val end end
  constraints['<='] = function(val) return function(x) x,val=coerce(x,val) return x <= val end end
  constraints['>'] = function(val) return function(x) x,val=coerce(x,val) return x > val end end
  constraints['<'] = function(val) return function(x) x,val=coerce(x,val) return x < val end end
  constraints['~='] = function(val) return function(x) x,val=coerce(x,val) return x ~= val end end
  constraints[''] = function(_) return function(x) return x ~= nil end end

  self.isTimer, self.isRule, self.isEvent, self.mkTimer, self.coerce = isTimer, isRule, isEvent, mkTimer, coerce

  local function compilePattern2(pattern)
    if type(pattern) == 'table' then
      if pattern._var_ then return end
      for k,v in pairs(pattern) do
        if type(v) == 'string' and v:sub(1,1) == '$' then
          local var,op,val = v:match("$([%w_]*)([<>=~]*)([+-]?%d*%.?%d*)")
          var = var =="" and "_" or var
          local c = constraints[op](tonumber(val))
          pattern[k] = {_var_=var, _constr=c, _str=v}
        else compilePattern2(v) end
      end
    end
  end

  local function compilePattern(pattern)
    compilePattern2(pattern)
    if pattern.type and type(pattern.deviceID)=='table' and not pattern.deviceID._constr then
      local m = {}; for _,id in ipairs(pattern.deviceID) do m[id]=true end
      pattern.deviceID = {_var_='_', _constr=function(val) return m[val] end, _str=pattern.deviceID}
    end
  end
  self._compilePattern = compilePattern

  function self._match(pattern, expr)
    local matches = {}
    local function _unify(pattern,expr)
      if pattern == expr then return true
      elseif type(pattern) == 'table' then
        if pattern._var_ then
          local var, constr = pattern._var_, pattern._constr
          if var == '_' then return constr(expr)
          elseif matches[var] then return constr(expr) and _unify(matches[var],expr) -- Hmm, equal?
          else matches[var] = expr return constr(expr) end
        end
        if type(expr) ~= "table" then return false end
        for k,v in pairs(pattern) do if not _unify(v,expr[k]) then return false end end
        return true
      else return false end
    end
    return _unify(pattern,expr) and matches or false
  end

  local toHash,fromHash={},{}
  fromHash['property'] = function(e) return {e.type..e.deviceID,e.type} end
  fromHash['global'] = function(e) return {e.type..e.name,e.type} end
  toHash['property'] = function(e) return e.deviceID and 'property'..e.deviceID or 'property' end
  toHash['global'] = function(e) return e.name and 'global'..e.name or 'global' end

  local function ruleToStr(r) return r.src end
  local function comboToStr(r)
    local res = { r.src }
    for _,s in ipairs(r.subs) do res[#res+1]="   "..tostring(s) end
    return table.concat(res,"\n")
  end

  function self.comboEvent(e,action,rl,src)
    local rm = {[self.RULE]=e, action=action, src=src, subs=rl}
    rm.enable = function() mapF(function(e) e.enable() end,rl) return rm end
    rm.disable = function() mapF(function(e) e.disable() end,rl) return rm end
    rm.start = function(event) self._invokeRule({rule=rm,event=event}) return rm end
    rm.print = function() map(function(e) e.print() end,rl) end
    rm.__tostring = comboToStr
    return rm
  end

  function self.event(e,action,src) 
    e = type(e)=='string' and str2event(e) or e
    src = src or (type(e)=='table' and format("Event(%s) => ..",e) or tostring(e))
    if type(e) == 'table' and e[1] then 
      return self.comboEvent(e,action,map(function(es) return self.event(es,action) end,e),src) 
    end
    if isEvent(e) then
      if e.type=='property' and e.deviceID and type(e.deviceID)=='table' then
        return self.event(map(function(id) local e1 = copy(e); e1.deviceID=id return e1 end,e.deviceID),action,src)
      end
    end
    compilePattern(e)
    local hashKey = toHash[e.type] and toHash[e.type](e) or e.type
    _handlers[hashKey] = _handlers[hashKey] or {}
    local rules = _handlers[hashKey]
    local rule,fn = {[self.RULE]=e, action=action, src=src}, true
    for _,rs in ipairs(rules) do -- Collect handlers with identical patterns. {{e1,e2,e3},{e1,e2,e3}}
      if equal(e,rs[1][self.RULE]) then 
        if front then table.insert(rs,1,rule) else rs[#rs+1] = rule end 
        fn = false break 
      end
    end
    if fn then if front then table.insert(rules,1,{rule}) else rules[#rules+1] = {rule} end end
    rule.enable = function() rule._disabled = nil return rule end
    rule.disable = function() rule._disabled = true return rule end
    rule.start = function(event) self._invokeRule({rule=rule,event=event}) return rule end
    rule.print = function() Log(LOG.LOG,src) end
    rule.__tostring = ruleToStr
    if self.SECTION then
      local s = self._sections[self.SECTION] or {}
      s[#s+1] = rule
      self._sections[self.SECTION] = s
    end
    return rule
  end

  function self._callTimerFun(tf,src)
    local status,res = pcall(tf) 
    if not status then 
      Log(LOG.ERROR,"in '%s': %s",src or tostring(tf),res)  
    end
  end

  function self.post(e,time,src) -- time in 'toTime' format, see below.
    _assert(isEvent(e) or type(e) == 'function', "Bad2 event format %s",tojson(e))
    time = toTime(time or os.time())
    if time < os.time() then return nil end
    if type(e) == 'function' then 
      src = src or "timer "..tostring(e)
      if _debugFlags.postTimers then Debug(true,"Posting timer %s at %s",src,os.date("%a %b %d %X",time)) end
      return mkTimer(function() self._callTimerFun(e,src) end, 1000*(time-os.time()))
    end
    if _debugFlags.post and not e._sh then Debug(true,"Posting %s at %s",e,os.date("%a %b %d %X",time)) end
    return mkTimer(function() self._handleEvent(e) end,1000*(time-os.time()))
  end

  function self.cancel(t)
    _assert(isTimer(t) or t == nil,"Bad timer")
    if t then clearTimeout(t[self.TIMER]) end 
    return nil 
  end
  
  function self.loop(time,fun,sync)
    local nextTime,interval,tp = os.time(),toTime(time),nil
    local res = {[self.RULE] = {}, count = 0}
    if type(fun)=='table' then local e = fun; fun = function() self.post(e) end end
    local function _loop()
      nextTime = nextTime + toTime(time); res.count=res.count+1
      if fun(res) == self.BREAK then tp = nil
      else tp = setTimeout(_loop,1000*(nextTime-os.time())) end
    end
    res.enable = function() 
      if tp then res.disable() end
      nextTime, count = os.time(),0
      if sync then nextTime = math.floor(nextTime/interval)*interval+interval end
      tp = setTimeout(_loop,1000*(nextTime-os.time()))
      return res
    end
    res.disable = function() if tp then clearTimeout(tp); tp=nil end return res end
    res.print = function() Log(LOG.LOG,res) end
    res.__tostring = function(e) return string.format("{loop interval:'%s', count:%s}",time,res.count) end
    res.enable()
    return res
  end

  function self.cron(pattern,fun)
    local test,c = Util.dateTest(pattern),0
    local r = self.loop("00:01",function(r) if test() then c=c+1; r.count=c return fun(r) end end,true)
    r.__tostring = function(e) return string.format("{cron:'%s', count:%s}",pattern,r.count) end
    return r
  end

  function self._compileAction(a)
    if type(a) == 'function' then return a                    -- Lua function
    elseif isEvent(a) then 
      return function(e) return self.post(a,nil,e.rule) end  -- Event -> post(event)
    end
  end

  function self._compileAction(a,src,log)
    if type(a) == 'function' then return a                   -- Lua function
    elseif isEvent(a) then 
      return function(e) return self.post(a,nil,tostring(a)) end  -- Event -> post(event)
    elseif self._compileActionHook then
      local r = self._compileActionHook(a,src,log)
      if r then return r end
    end
    error("Unable to compile action:"..json.encode(a))
  end

  local _getProp = {}
  _getProp['property'] = function(e,v)
    e.propertyName = e.propertyName or 'value'
    e.value = v or (fibaro.getValue(e.deviceID,e.propertyName))
    --self.trackManual(e.deviceID,e.value)
  end
  _getProp['global'] = function(e,v2) e.value = v2 or fibaro.getGlobalVariable(e.name) end

  function self._invokeRule(env,event)
    local t = os.time()
    env.last,env.rule.time = t-(env.rule.time or 0),t
    env.event = env.event or event
    local status, res = pcall(env.rule.action,env) -- call the associated action
    if not status then
      Log(LOG.ERROR,"in '%s': %s",res and res.src or "rule",res)
      env.rule._disabled = true -- disable rule to not generate more errors
    else return res end
  end

-- {{e1,e2,e3},{e4,e5,e6}} env={event=_,p=_,locals=_,rule.src=_,last=_}
  function self._handleEvent(e) -- running a posted event
    -- Log("E:%s",tojson(e))
    if _getProp[e.type] then _getProp[e.type](e,e.value) end  -- patch events
    local _match,hasKeys = self._match,fromHash[e.type] and fromHash[e.type](e) or {e.type}
    for _,hashKey in ipairs(hasKeys) do
      for _,rules in ipairs(_handlers[hashKey] or {}) do -- Check all rules of 'type'
        local match,m = _match(rules[1][self.RULE],e),nil
        if match then
          for _,rule in ipairs(rules) do 
            if not rule._disabled then 
              m={}; if next(match) then for k,v in pairs(match) do m[k]={v} end end
              local env = {event = e, p=match, rule=rule, locals= m}
              if self._invokeRule(env) == self.BREAK then break end
            end
          end
        end
      end
    end
  end

  function self.pollEvents()
    local lastRefresh = 0
    local function pollRefresh()
      local states = api.get("/refreshStates?last=" .. lastRefresh)
      if states then
        lastRefresh=states.last
        --if states.changes and #states.changes>0 then self.checkChanges(states.changes) end
        if states.events and #states.events>0 then self.checkEvents(states.events) end
      end
      setTimeout(pollRefresh,1000)
      self.postCustomEvent(self.tickEvent)  -- hack because refreshState hang if no events...
    end
    setTimeout(pollRefresh,1000)
  end

  function self.checkChanges(changes)
    for _,c in ipairs(changes) do
      Log(LOG.SYS,"Change:"..json.encode(c))
    end
  end

  EventTypes = {
    WeatherChangedEvent = function(self,d) Log(LOG.LOG,"%s, %s -> %s",d.change,d.oldValue,d.newValue) end,
    GlobalVariableChangedEvent = function(self,d)
      --Log(LOG.LOG,"Global %s, %s -> %s",d.variableName,d.oldValue,d.newValue)
      self.post({type='global', name=d.variableName, value=d.newValue, old=d.oldValue, _sh=true})
    end,
    DevicePropertyUpdatedEvent = function(self,d)
      if d.property=='quickAppVariables' then 
        local old={}; for _,v in ipairs(d.oldValue) do old[v.name] = v.value end -- Todo: optimize
        for _,v in ipairs(d.newValue) do
          if v.value ~= old[v.name] then
            --Log(LOG.LOG,"QuickVar:%s,  %s -> %s",v.name,old[v.name],v.value )
            self.post({type='quickvar', name=v.name, value=v.value, old=old[v.name], _sh=true})
          end
        end
      else
        if d.property:match("^ui%.") then return end
        --Log(LOG.LOG,"Device:%s:%s, %s -> %s",d.id,d.property,d.oldValue,d.newValue) 
        self.post({type='property', deviceID=d.id, propertyName=d.property, value=d.newValue, old=d.oldValue, _sh=true})
      end
    end,
    CustomEvent = function(self,d) 
      if d.name == self.tickEvent then return end
      --Log(LOG.LOG,"CustomEvent:%s",d.name)
      self.post({type='customevent', name=d.name, _sh=true})
    end,
    PluginChangedViewEvent = function(self,d) end,
    WizardStepStateChangedEvent = function(self,d) end,
    UpdateReadyEvent = function(self,d) end,
    SceneRunningInstancesEvent = function(self,d) end,
    DeviceRemovedEvent = function(self,d) Log(LOG.LOG,"Device %s removed",d.id) end,
    DeviceCreatedEvent = function(self,d) Log(LOG.LOG,"Device %s created",d.id) end,
    DeviceModifiedEvent = function(self,d) Log(LOG.LOG,"Device %s modified",d.id) end,
    SceneStartedEvent = function(self,d) Log(LOG.LOG,"Scene %s started",d.id) end,
    SceneFinishedEvent = function(self,d) Log(LOG.LOG,"Scene %s finished",d.id) end,
    SceneRemovedEvent = function(self,d) Log(LOG.LOG,"Scene %s removed (%s)",d.id,d.name) end,
    PluginProcessCrashedEvent = function(self,d) Log(LOG.LOG,"Device %s crashed",d.deviceId) end,
    onUIEvent = function(self,d) 
      --Log(LOG.LOG,"Device %s %s (UI)",d.deviceId,d.elementName) 
      self.post({type='uievent', deviceID=d.deviceId, name=d.elementName})
    end,
  }

  function self.checkEvents(events)
    for _,e in ipairs(events) do
      if EventTypes[e.type] then EventTypes[e.type](self,e.data)
      else Log(LOG.SYS,"Unhandled event:%s -- please report",json.encode(e)) end
    end
  end

  function self.getCustomEvent(name) return api.get("/customEvents/"..name) end
  function self.getCustomEventDescription(name) 
    local ce = self.getCustomEvent(name) 
    return ce and ce.userDescription or nil
  end
  function self.createCustomEvent(name,descr) api.post("/customEvents",{name=name,userDescription=descr}) end
  function self.deleteCustomEvent(name) api.delete("/customEvents/"..name) end
  function self.postCustomEvent(name) api.post("/customEvents/"..name) end
  return self
end -- eventEngine

function createDeviceSupport(quickSelf)
  Log(LOG.SYS,"Setting up device support..")
  local self = { deviceID = plugin.mainDeviceId }
  function self.updateProperty(prop,value) return quickSelf:updateProperty(prop,value)  end
  function self.updateView(componentID, property, value) return quickSelf:updateView(componentID, property, value)  end
  function self.setVariable(name,value) return quickSelf:setVariable(name,value) end
  function self.getVariable(name) return quickSelf:getVariable(name) end
  return self
end

if (_VERSION or ""):match("5%.3") then
  function table.maxn(tbl)
    local c=0
    for k in pairs(tbl) do c=c+1 end
    return c
  end
end

function createUtils(quickSelf)
  local self,format = {},string.format
  function self.map(f,l,s) s = s or 1; local r={} for i=s,table.maxn(l) do r[#r+1] = f(l[i]) end return r end
  function self.mapAnd(f,l,s) s = s or 1; local e=true for i=s,table.maxn(l) do e = f(l[i]) if not e then return false end end return e end 
  function self.mapOr(f,l,s) s = s or 1; for i=s,table.maxn(l) do local e = f(l[i]) if e then return e end end return false end
  function self.mapF(f,l,s) s = s or 1; local e=true for i=s,table.maxn(l) do e = f(l[i]) end return e end
  local function transform(obj,tf)
    if type(obj) == 'table' then
      local res = {} for l,v in pairs(obj) do res[l] = transform(v,tf) end 
      return res
    else return tf(obj) end
  end
  local function copy(obj) return transform(obj, function(o) return o end) end
  local function equal(e1,e2)
    local t1,t2 = type(e1),type(e2)
    if t1 ~= t2 then return false end
    if t1 ~= 'table' and t2 ~= 'table' then return e1 == e2 end 
    for k1,v1 in pairs(e1) do if e2[k1] == nil or not equal(v1,e2[k1]) then return false end end
    for k2,v2 in pairs(e2) do if e1[k2] == nil or not equal(e1[k2],v2) then return false end end
    return true
  end
  self.equal,self.copy,self.transform = equal,copy,transform

  function split(s, sep)
    local fields = {}
    sep = sep or " "
    local pattern = string.format("([^%s]+)", sep)
    string.gsub(s, pattern, function(c) fields[#fields + 1] = c end)
    return fields
  end

  local oldtostring,oldformat = tostring,string.format
  tostring = function(o)
    if type(o)=='table' then
      if o.__tostring then return o.__tostring(o)
      else return tojson(o) end
    else return oldtostring(o) end
  end
  string.format = function(...)
    local args = {...}
    for i=1,#args do if type(args[i])=='table' then args[i]=tostring(args[i]) end end
    return #args > 1 and oldformat(table.unpack(args)) or args[1]
  end
  format = string.format 

  local function logHeader(len,str)
    if #str % 2 == 1 then str=str.." " end
    local n = #str+2
    return string.rep("-",len/2-n/2).." "..str.." "..string.rep("-",len/2-n/2)
  end

  local orgDebug = quickSelf.debug
  LOG = { LOG="[L] ", ULOG="[U] ", SYS="[Sys] ", DEBUG="[D] ", ERROR='[ERROR] ', HEADER='HEADER'}
  function Debug(flag,...) if flag then Log(LOG.DEBUG,...) end end
  function Log(flag,...)
    local str = format(...)
    if flag == LOG.HEADER then str = logHeader(100,str) else str=flag..str end
    for _,s in ipairs(split(str,"\n")) do orgDebug(quickSelf,s) end
    return str
  end

  function _assert(test,msg,...) if not test then error(string.format(msg,...),3) end end
  function _assertf(test,msg,fun) if not test then error(string.format(msg,fun and fun() or ""),3) end end
  local function time2str(t) return format("%02d:%02d:%02d",math.floor(t/3600),math.floor((t%3600)/60),t%60) end
  local function midnight() local t = os.date("*t"); t.hour,t.min,t.sec = 0,0,0; return os.time(t) end
  local function hm2sec(hmstr)
    local offs,sun
    sun,offs = hmstr:match("^(%a+)([+-]?%d*)")
    if sun and (sun == 'sunset' or sun == 'sunrise') then
      hmstr,offs = fibaro.getValue(1,sun.."Hour"), tonumber(offs) or 0
    end
    local sg,h,m,s = hmstr:match("^(%-?)(%d+):(%d+):?(%d*)")
    _assert(h and m,"Bad hm2sec string %s",hmstr)
    return (sg == '-' and -1 or 1)*(h*3600+m*60+(tonumber(s) or 0)+(offs or 0)*60)
  end
  local function between(t11,t22)
    local t1,t2,tn = midnight()+hm2sec(t11),midnight()+hm2sec(t22),os.time()
    if t1 <= t2 then return t1 <= tn and tn <= t2 else return tn <= t1 or tn >= t2 end 
  end
  local function toDate(str)
    local y,m,d = str:match("(%d%d%d%d)/(%d%d)/(%d%d)")
    return os.time{year=tonumber(y),month=tonumber(m),day=tonumber(d),hour=0,min=0,sec=0}
  end
-- toTime("10:00")     -> 10*3600+0*60 secs   
-- toTime("10:00:05")  -> 10*3600+0*60+5*1 secs
-- toTime("t/10:00")    -> (t)oday at 10:00. midnight+10*3600+0*60 secs
-- toTime("n/10:00")    -> (n)ext time. today at 10.00AM if called before (or at) 10.00AM else 10:00AM next day
-- toTime("+/10:00")    -> Plus time. os.time() + 10 hours
-- toTime("+/00:01:22") -> Plus time. os.time() + 1min and 22sec
-- toTime("sunset")     -> todays sunset in relative secs since midnight, E.g. sunset="05:10", =>toTime("05:10")
-- toTime("sunrise")    -> todays sunrise
-- toTime("sunset+10")  -> todays sunset + 10min. E.g. sunset="05:10", =>toTime("05:10")+10*60
-- toTime("sunrise-5")  -> todays sunrise - 5min
-- toTime("t/sunset+10")-> (t)oday at sunset in 'absolute' time. E.g. midnight+toTime("sunset+10")
  function toTime(time)
    if type(time) == 'number' then return time end
    local p = time:sub(1,2)
    if p == '+/' then return hm2sec(time:sub(3))+os.time()
    elseif p == 'n/' then
      local t1,t2 = midnight()+hm2sec(time:sub(3)),os.time()
      return t1 > t2 and t1 or t1+24*60*60
    elseif p == 't/' then return  hm2sec(time:sub(3))+midnight()
    else return hm2sec(time) end
  end

  local gKeys = {type=1,deviceID=2,value=3,val=4,key=5,arg=6,event=7,events=8,msg=9,res=10}
  local gKeysNext = 10
  local function keyCompare(a,b)
    local av,bv = gKeys[a], gKeys[b]
    if av == nil then gKeysNext = gKeysNext+1 gKeys[a] = gKeysNext av = gKeysNext end
    if bv == nil then gKeysNext = gKeysNext+1 gKeys[b] = gKeysNext bv = gKeysNext end
    return av < bv
  end
  function self.prettyJson(e) -- our own json encode, as we don't have 'pure' json structs, and sorts keys in order
    local res,seen = {},{}
    local function pretty(e)
      local t = type(e)
      if t == 'string' then res[#res+1] = '"' res[#res+1] = e res[#res+1] = '"' 
      elseif t == 'number' then res[#res+1] = e
      elseif t == 'boolean' or t == 'function' or t=='thread' then res[#res+1] = tostring(e)
      elseif t == 'table' then
        if next(e)==nil then res[#res+1]='{}'
        elseif seen[e] then res[#res+1]="..rec.."
        elseif e[1] or #e>0 then
          seen[e]=true
          res[#res+1] = "[" pretty(e[1])
          for i=2,#e do res[#res+1] = "," pretty(e[i]) end
          res[#res+1] = "]"
        else
          seen[e]=true
          if e._var_  then res[#res+1] = format('"%s"',e._str) return end
          local k = {} for key,_ in pairs(e) do k[#k+1] = key end 
          table.sort(k,keyCompare)
          if #k == 0 then res[#res+1] = "[]" return end
          res[#res+1] = '{'; res[#res+1] = '"' res[#res+1] = k[1]; res[#res+1] = '":' t = k[1] pretty(e[t])
          for i=2,#k do 
            res[#res+1] = ',"' res[#res+1] = k[i]; res[#res+1] = '":' t = k[i] pretty(e[t]) 
          end
          res[#res+1] = '}'
        end
      elseif e == nil then res[#res+1]='null'
      else error("bad json expr:"..tostring(e)) end
    end
    pretty(e)
    return table.concat(res)
  end

  self.netSync = { HTTPClient = function (log)   
      local self,queue,HTTP,key = {},{},net.HTTPClient(),0
      local _request
      local function dequeue()
        table.remove(queue,1)
        local v = queue[1]
        if v then 
          Debug(_debugFlags.netSync,"netSync:Pop %s (%s)",v[3],#queue)
          --setTimeout(function() _request(table.unpack(v)) end,1) 
          _request(table.unpack(v))
        end
      end
      _request = function(url,params,key)
        params = copy(params)
        local uerr,usucc = params.error,params.success
        params.error = function(status)
          Debug(_debugFlags.netSync,"netSync:Error %s %s",key,status)
          dequeue()
          if params._logErr then Log(LOG.ERROR," %s:%s",log or "netSync:",tojson(status)) end
          if uerr then uerr(status) end
        end
        params.success = function(status)
          Debug(_debugFlags.netSync,"netSync:Success %s",key)
          dequeue()
          if usucc then usucc(status) end
        end
        Debug(_debugFlags.netSync,"netSync:Calling %s",key)
        HTTP:request(url,params)
      end
      function self:request(url,parameters)
        key = key+1
        if next(queue) == nil then
          queue[1]='RUN'
          _request(url,parameters,key)
        else 
          Debug(_debugFlags.netSync,"netSync:Push %s",key)
          queue[#queue+1]={url,parameters,key} 
        end
      end
      return self
    end}

  if _EMULATED then self.getWeekNumber = _System.getWeekNumber
  else self.getWeekNumber = function(tm) return tonumber(os.date("%V",tm)) end end

  function self.dateTest(dateStr)
    local days = {sun=1,mon=2,tue=3,wed=4,thu=5,fri=6,sat=7}
    local months = {jan=1,feb=2,mar=3,apr=4,may=5,jun=6,jul=7,aug=8,sep=9,oct=10,nov=11,dec=12}
    local last,month = {31,28,31,30,31,30,31,31,30,31,30,31},nil

    local function seq2map(seq) local s = {} for _,v in ipairs(seq) do s[v] = true end return s; end

    local function flatten(seq,res) -- flattens a table of tables
      res = res or {}
      if type(seq) == 'table' then for _,v1 in ipairs(seq) do flatten(v1,res) end else res[#res+1] = seq end
      return res
    end

    local function expandDate(w1,md)
      local function resolve(id)
        local res
        if id == 'last' then month = md res=last[md] 
        elseif id == 'lastw' then month = md res=last[md]-6 
        else res= type(id) == 'number' and id or days[id] or months[id] or tonumber(id) end
        _assert(res,"Bad date specifier '%s'",id) return res
      end
      local w,m,step= w1[1],w1[2],1
      local start,stop = w:match("(%w+)%p(%w+)")
      if (start == nil) then return resolve(w) end
      start,stop = resolve(start), resolve(stop)
      local res,res2 = {},{}
      if w:find("/") then
        if not w:find("-") then -- 10/2
          step=stop; stop = m.max
        else step=w:match("/(%d+)") end
      end
      step = tonumber(step)
      _assert(start>=m.min and start<=m.max and stop>=m.min and stop<=m.max,"illegal date intervall")
      while (start ~= stop) do -- 10-2
        res[#res+1] = start
        start = start+1; if start>m.max then start=m.min end  
      end
      res[#res+1] = stop
      if step > 1 then for i=1,#res,step do res2[#res2+1]=res[i] end; res=res2 end
      return res
    end

    local function parseDateStr(dateStr,last)
      local map = Util.map
      local seq = split(dateStr," ")   -- min,hour,day,month,wday
      local lim = {{min=0,max=59},{min=0,max=23},{min=1,max=31},{min=1,max=12},{min=1,max=7}}
      for i=1,5 do if seq[i]=='*' or seq[i]==nil then seq[i]=tostring(lim[i].min).."-"..lim[i].max end end
      seq = map(function(w) return split(w,",") end, seq)   -- split sequences "3,4"
      local month = os.date("*t",os.time()).month
      seq = map(function(t) local m = table.remove(lim,1);
          return flatten(map(function (g) return expandDate({g,m},month) end, t))
        end, seq) -- expand intervalls "3-5"
      return map(seq2map,seq)
    end
    local sun,offs,day,sunPatch = dateStr:match("^(sun%a+) ([%+%-]?%d+)")
    if sun then
      sun = sun.."Hour"
      dateStr=dateStr:gsub("sun%a+ [%+%-]?%d+","0 0")
      sunPatch=function(dateSeq)
        local h,m = (fibaro:getValue(1,sun)):match("(%d%d):(%d%d)")
        dateSeq[1]={[(h*60+m+offs)%60]=true}
        dateSeq[2]={[math.floor((h*60+m+offs)/60)]=true}
      end
    end
    local dateSeq = parseDateStr(dateStr)
    return function() -- Pretty efficient way of testing dates...
      local t = os.date("*t",os.time())
      if month and month~=t.month then parseDateStr(dateStr) end -- Recalculate 'last' every month
      if sunPatch and (month and month~=t.month or day~=t.day) then sunPatch(dateSeq) day=t.day end -- Recalculate 'last' every month
      return
      dateSeq[1][t.min] and    -- min     0-59
      dateSeq[2][t.hour] and   -- hour    0-23
      dateSeq[3][t.day] and    -- day     1-31
      dateSeq[4][t.month] and  -- month   1-12
      dateSeq[5][t.wday] or false      -- weekday 1-7, 1=sun, 7=sat
    end
  end

---- SunCalc -----
  do
    local function sunturnTime(date, rising, latitude, longitude, zenith, local_offset)
      local rad,deg,floor = math.rad,math.deg,math.floor
      local frac = function(n) return n - floor(n) end
      local cos = function(d) return math.cos(rad(d)) end
      local acos = function(d) return deg(math.acos(d)) end
      local sin = function(d) return math.sin(rad(d)) end
      local asin = function(d) return deg(math.asin(d)) end
      local tan = function(d) return math.tan(rad(d)) end
      local atan = function(d) return deg(math.atan(d)) end

      local function day_of_year(date)
        local n1 = floor(275 * date.month / 9)
        local n2 = floor((date.month + 9) / 12)
        local n3 = (1 + floor((date.year - 4 * floor(date.year / 4) + 2) / 3))
        return n1 - (n2 * n3) + date.day - 30
      end

      local function fit_into_range(val, min, max)
        local range,count = max - min
        if val < min then count = floor((min - val) / range) + 1; return val + count * range
        elseif val >= max then count = floor((val - max) / range) + 1; return val - count * range
        else return val end
      end

      -- Convert the longitude to hour value and calculate an approximate time
      local n,lng_hour,t =  day_of_year(date), longitude / 15, nil
      if rising then t = n + ((6 - lng_hour) / 24) -- Rising time is desired
      else t = n + ((18 - lng_hour) / 24) end -- Setting time is desired
      local M = (0.9856 * t) - 3.289 -- Calculate the Sun^s mean anomaly
      -- Calculate the Sun^s true longitude
      local L = fit_into_range(M + (1.916 * sin(M)) + (0.020 * sin(2 * M)) + 282.634, 0, 360)
      -- Calculate the Sun^s right ascension
      local RA = fit_into_range(atan(0.91764 * tan(L)), 0, 360)
      -- Right ascension value needs to be in the same quadrant as L
      local Lquadrant = floor(L / 90) * 90
      local RAquadrant = floor(RA / 90) * 90
      RA = RA + Lquadrant - RAquadrant; RA = RA / 15 -- Right ascension value needs to be converted into hours
      local sinDec = 0.39782 * sin(L) -- Calculate the Sun's declination
      local cosDec = cos(asin(sinDec))
      local cosH = (cos(zenith) - (sinDec * sin(latitude))) / (cosDec * cos(latitude)) -- Calculate the Sun^s local hour angle
      if rising and cosH > 1 then return "N/R" -- The sun never rises on this location on the specified date
      elseif cosH < -1 then return "N/S" end -- The sun never sets on this location on the specified date

      local H -- Finish calculating H and convert into hours
      if rising then H = 360 - acos(cosH)
      else H = acos(cosH) end
      H = H / 15
      local T = H + RA - (0.06571 * t) - 6.622 -- Calculate local mean time of rising/setting
      local UT = fit_into_range(T - lng_hour, 0, 24) -- Adjust back to UTC
      local LT = UT + local_offset -- Convert UT value to local time zone of latitude/longitude
      return os.time({day = date.day,month = date.month,year = date.year,hour = floor(LT),min = math.modf(frac(LT) * 60)})
    end

    local function getTimezone() local now = os.time() return os.difftime(now, os.time(os.date("!*t", now))) end

    function self.sunCalc(time)
      local hc2Info = api.get("/settings/location") or {}
      local lat = hc2Info.latitude
      local lon = hc2Info.longitude
      local utc = getTimezone() / 3600
      local zenith,zenith_twilight = 90.83, 96.0 -- sunset/sunrise 90°50′, civil twilight 96°0′

      local date = os.date("*t",time or os.time())
      if date.isdst then utc = utc + 1 end
      local rise_time = os.date("*t", sunturnTime(date, true, lat, lon, zenith, utc))
      local set_time = os.date("*t", sunturnTime(date, false, lat, lon, zenith, utc))
      local rise_time_t = os.date("*t", sunturnTime(date, true, lat, lon, zenith_twilight, utc))
      local set_time_t = os.date("*t", sunturnTime(date, false, lat, lon, zenith_twilight, utc))
      local sunrise = format("%.2d:%.2d", rise_time.hour, rise_time.min)
      local sunset = format("%.2d:%.2d", set_time.hour, set_time.min)
      local sunrise_t = format("%.2d:%.2d", rise_time_t.hour, rise_time_t.min)
      local sunset_t = format("%.2d:%.2d", set_time_t.hour, set_time_t.min)
      return sunrise, sunset, sunrise_t, sunset_t
    end
  end

  tojson = self.prettyJson
  self.toTime = toTime
  self.midnight = midnight
  self.hm2sec = hm2sec
  return self
end -- Utils

function createRemoteEventSupport()
  Log(LOG.SYS,"Setting up remote event support..")
  local function printSendEvent(e) return string.format("to %d %s",e.to,e.event) end

  Event.event({type='%sendEvent%'},function(env)
      local event = env.event.event
      event._from = Event.deviceID
      if env.event.stype == 'device' then
        fibaro.call(env.event.to,'recieveEvent',event)
      elseif env.event.stype == 'custom' then
        local address = Event.makeAddress(env.event.to)
        Event.createCustomEvent(address,json.encode(event))
        Event.postCustomEvent(address)
        setTimeout(function() Event.deleteCustomEvent(address) end,4*1000) -- Remove after 4s
      end
    end)

  function Event.postEvent2Device(toid,event,time) 
    Event.post({type='%sendEvent%',to=toid,event=event, stype='device', __tostring=printSendEvent},time) 
  end  
  function Event.postEvent2Scene(toid,event,time) 
    Event.post({type='%sendEvent%',to=toid, event=event, stype='scene', __tostring=printSendEvent},time) 
  end 
  function Event.publishEvent(toid,event,time) 
    Event.post({type='%sendEvent%',to=toid,event=event, stype='custom',  __tostring=printSendEvent},time) 
  end
  function Event.broadcastEvent(event,time) 
    Event.post({type='%sendEvent%',to="000", event=event, stype='custom', __tostring=printSendEvent},time) 
  end

  function QuickApp:recieveEvent(e)
    local stat,res = pcall(function() return (json.decode(e)) end)
    if stat and Event.isEvent(res) then Event.post(res)
    else LogErr("Bad arg to 'recieveEvent' "..tostring(e)) end
  end

  Event.event({type='customevent'}, -- Triggering on a custom event
    function(env) 
      local address = env.event.name
      if Event.isMyAddress(address) or Event.isBroadcastAddress(address) then
        local ce = Event.getCustomEvent(address)
        Event.post(json.decode(ce.userDescription))
        Event.deleteCustomEvent(address)
        return Event.BREAK
      end
    end)
end

function createRemoteFunctionSupport(quickSelf)
  Log(LOG.SYS,"Setting up remote function support..")
  local TIMEOUT = 3

  function defineRemoteFun(name,deviceID,tab) (tab or _G or _ENV)[name] = function(...) return funCall(deviceID,name,{...}) end end

  function exportFunctions(funList) quickSelf:setVariable("ExportedFuns",json.encode(funList)) end
  function importFunctions(deviceID,tab,log)
    log = log==nil and true or log
    for _,v in ipairs((api.get("/devices/"..deviceID) or {}).properties.quickAppVariables or {}) do
      if v.name == "ExportedFuns" then
        for _,ef in ipairs(json.decode(v.value) or {}) do
          ef = type(ef)=='string' and {name=ef} or ef
          if log then Log(LOG.SYS,"importing fun %s:%s%s",deviceID,ef.name,ef.doc and (" - "..ef.doc) or "") end
          defineRemoteFun(ef.name,deviceID,tab)
        end
        return
      end
    end
    quickSelf:debug("No exported functions from deviceID:"..deviceID)
  end

  local FUNRES = "FUNRES"..Event.deviceID
  local ASYNC = {"ASYNC"}
  api.post("/globalVariables/",{name=FUNRES})
  function funCall(deviceID,fun,args)
    if args[1]==ASYNC then return deviceID,fun end
    local timeout,res = os.time()+TIMEOUT,nil
    fibaro.setGlobalVariable(FUNRES,"")
    fibaro.call(deviceID,"funCall",json.encode({name=fun,args=args,from=FUNRES}))
    repeat res=fibaro.getGlobalVariable(FUNRES) until res~="" or timeout < os.time()
    if res~="" then
      res = json.decode(res)
      if res[1] then return table.unpack(res[2])
      else 
        error(string.format("Remote function error %s:%s - %s",deviceID,fun,res[2]),3)
      end
    end 
    error(string.format("Remote function %s:%s timed out",deviceID,fun),3)
  end

-- Receieve function call and return reponse
  function QuickApp:funCall(call)
    local stat,res = pcall(function() return {_G[call.name](table.unpack(call.args))} end)
    --Log(LOG.LOG,"RES:%s - %s",res,call.from)
    fibaro.setGlobalVariable(call.from,json.encode({stat,res}))
  end

end -- createRemoteFunctionSupport 

function createAutoPatchSupport(quickSelf)
  Log(LOG.SYS,"Setting up autopatch support..")
  local _EVENTSSRCPATH = "EventRunner4.lua"

  function Util.checkVersion(vers)
    local req = net.HTTPClient()
    req:request("https://raw.githubusercontent.com/jangabrielsson/EventRunner/master/VERSION.json",
      {options = {method = 'GET', checkCertificate = false, timeout=20000},
        success=function(data)
          if data.status == 200 then
            local v = json.decode(data.data)
            v = v[_EVENTSSRCPATH]
            if vers then v = v.scenes[vers] end
            if v.version ~= E_VERSION or v.fix ~= E_FIX then
              Event.post({type='Event_version',version=v.version,fix=v.fix or "", _sh=true})
            end
          end
        end})
  end

  local _EVENTSDELIMETER = "%-%-%-%-%-%-%-%-%-%-%-%-%-%-%-%-%-%-%- EventSupport %- Don't change! "

  function Util.patchEventRunner(newSrc)
    if newSrc == nil then
      local req = net.HTTPClient()
      req:request("https://raw.githubusercontent.com/jangabrielsson/EventRunner/master/".._EVENTSSRCPATH,
        {options = {method = 'GET', checkCertificate = false, timeout=20000},
          success=function(data)
            if data.status == 200 then
              local src = data.data
              Util.patchEventRunner(src)
            end
          end,
          error=function(status) Log(LOG.ERROR,"Get src code from Github: %s",status) end
        })
    else
      local oldSrc=""
      if __fullFileName then
        --local f = io.open(__fullFileName)
        --if not f then return end
        --oldSrc = f:read("*all")
      else oldSrc = api.get("/devices/"..Device.deviceID).properties.mainFunction end
      local obp = oldSrc:find(_EVENTSDELIMETER)
      oldSrc = oldSrc:sub(1,obp-1)
      local nbp = newSrc:find(_EVENTSDELIMETER)
      local nbody = newSrc:sub(nbp)
      oldSrc = oldSrc:gsub("(E_VERSION,E_FIX = .-\n)",newSrc:match("(E_VERSION,E_FIX = .-\n)"))
      Log(LOG.SYS,"Patching scene to latest version")
      if __fullFileName then
        --local f = io.open(__fullFileName, "w")
        --io.output(f)
        --io.write(oldSrc..nbody)
        --io.close(f)
      else quickSelf:updateProperty("mainFunction",oldSrc..nbody) end
    end
  end
end

function extraSetup()
  -- Sunset/sunrise patch -- first time in the day someone asks for sunsethours we calculate and cahche
  local _SUNTIMEDAY = nil
  local _SUNTIMEVALUES = {sunsetHour="00:00",sunriseHour="00:00",dawnHour="00:00",duskHour="00:00"}
  do
    oldGet = fibaro.getValue
    function fibaro.getValue(id,prop)
      if id ~= 1 or not _SUNTIMEVALUES[prop] then return oldGet(id,prop) end
      local s = _SUNTIMEVALUES
      local day = os.date("*t").day
      if day ~= _SUNTIMEDAY then
        _SUNTIMEDAY = day
        s.sunriseHour,s.sunsetHour,s.dawnHour,s.duskHour=Util.sunCalc()
      end
      return _SUNTIMEVALUES[prop]
    end
  end
end

function add100(x) return x+100 end   -- test
function add1000(x) return x+1000 end -- test

local function setUpEventScript()
  if dofile then dofile("ERinclude.lua") end
  if makeEventScriptParser then ScriptParser = makeEventScriptParser() end
  if makeEventScriptCompiler then ScriptCompiler = makeEventScriptCompiler(ScriptParser) end
  if makeEventScriptRuntime then ScriptEngine = makeEventScriptRuntime() end
  if makeEventScriptRuleCompiler then Rule = makeEventScriptRuleCompiler() end
end

function QuickApp:initEventExtension(s)
  Util = createUtils(s) 
  local deviceID = plugin.mainDeviceId
  local appName = api.get("/devices/"..deviceID).name
  Log(LOG.HEADER,"%s, %s (ID:%s)",appName or "NoName",DEVICE_VERS or "",deviceID)
  Log(LOG.SYS,"Events %s, %s",E_VERSION,E_FIX)
  s.debug = function(s,...) Log(LOG.LOG,...) end
  Device = createDeviceSupport(s)
  Event = createEventEngine(s)
  createRemoteEventSupport(s)
  createRemoteFunctionSupport(s)
  createAutoPatchSupport(s)
  extraSetup()
  setUpEventScript()

  Log(LOG.SYS,"Sunrise:%s,  Sunset:%s",(fibaro.get(1,"sunriseHour")),(fibaro.get(1,"sunsetHour")))
  Log(LOG.HEADER,"Setting up rules (main)")
  s:main() -- call main
  Event.createCustomEvent(Event.tickEvent,"Tock!") -- hack because refreshState hang if no events available... 
  Log(LOG.HEADER,"Running")
  Event.pollEvents() 
  Event.post({type='startup'})
end 

function QuickApp:onInit()
  QuickApp:initEventExtension(self)
end

if dofile then QuickApp:onInit() end