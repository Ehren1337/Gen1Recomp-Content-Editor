local M={}
function M.install(mod)
  mod.events:on("game.ready",function()
    local Natives=require("src.core.game3.scripting.natives")
    -- Binding again later would drop the replacement.
    Natives.ensureBound()
    local id=require("src.core.game3.constants.emerald.specials").byName.StartWallClock
    Natives.ALLOW["special:"..id]=function()
      local Rtc=require("src.core.game3.rtc")
      local session=require("src.core.game3.runtime").getSession()
      local now=Rtc.getInfo(session)
      Rtc.calcLocalTimeOffset(session,0,now.hour,now.minute,now.second)
      require("src.core.game3.time_events").init(session)
      -- The script faded to black for the clock screen.
      local Fade=require("src.ui.game3.fade")
      Fade.clear();Fade.begin(Fade.MODE.FROM_BLACK,1)
      return false
    end
  end)
end
return M
