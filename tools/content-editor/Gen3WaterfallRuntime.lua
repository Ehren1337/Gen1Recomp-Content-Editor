-- Keep native move/badge prompts, but repair passage and pace the ride.
return [=[
  mod.events:on("game.ready",function()
    local Field=require("src.core.game3.field")
    local Player=require("src.core.game3.player")
    local Collision=require("src.core.game3.collision")
    local Audio=require("src.core.game3.audio")
    local Runtime=require("src.mods.Runtime")
    local sound="SE_M_WATERFALL"
    local sounding=false
    local function bridge(object,name,key)
      if object[key] then return end
      object[key]=true
      local original=object[name]
      object[name]=function(...) return Runtime.call(key,original,...) end
    end
    local function waterfall(x,y) return Collision.behavior(x,y)==0x13 end
    bridge(Collision,"isWater","editor.gen3.waterfall.water")
    bridge(Collision,"canEnter","editor.gen3.waterfall.enter")
    bridge(Field,"updateWaterfall","editor.gen3.waterfall.tick")
    mod.hooks:wrap("editor.gen3.waterfall.water",function(proceed,x,y,...)
      if waterfall(x,y) then return true end
      return proceed(x,y,...)
    end)
    mod.hooks:wrap("editor.gen3.waterfall.enter",function(proceed,game,x,y,opts,...)
      if waterfall(x,y) then
        opts=opts or {}
        local surfing=opts.surfing
        if surfing==nil then surfing=Player.surfing end
        if not surfing or opts.dir~="down" then return false,"tile" end
        -- Falls connect upper/lower pools. Native water entry rejects an
        -- elevation change before the ride can begin. Match this one target
        -- for that check; retain bounds, obstacles, entities and direction.
        local entry={}
        for k,v in pairs(opts) do entry[k]=v end
        entry.elevation=Collision.elevationAt(x,y)
        opts=entry
      end
      return proceed(game,x,y,opts,...)
    end)
    mod.hooks:wrap("editor.gen3.waterfall.tick",function(proceed,game,...)
      local Space=package.loaded["src.core.game3.scripting.space"]
      local UI=package.loaded["src.core.game3.runtime"]
      local busy=(Space and Space.vm and Space.vm:isRunning()) or (UI and UI.uiBusy and UI.uiBusy())
      local entering=Player.moving and Player.facing=="down"
        and waterfall(Player.targetX,Player.targetY)
      if not Field._waterfall and not Field.locked
          and Player.surfing and (entering or (not Player.moving and waterfall(Player.cellX,Player.cellY))) and not busy then
        -- Walking onto the top starts descent; no move or badge is required.
        Field.rideWaterfall("down")
      end
      if not Field._waterfall and waterfall(Player.cellX,Player.cellY) then return end
      local result=proceed(game,...)
      if Field._waterfall then
        if Player.moving then Player.stepFrames=32 end
        if not Audio.isSePlaying(sound) then Audio.playSe(sound) end
        sounding=true
      elseif sounding then
        Audio.stopSe(sound)
        sounding=false
      end
      return result
    end)
  end,-200)
]=]
