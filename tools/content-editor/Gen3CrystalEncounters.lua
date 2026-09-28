-- Pokemon Crystal's wild grass (and cave) encounters in Kanto, by time of
-- day: a pre-configured mix for the real time clock (GAME PATCHES > Real
-- Time Clock > Encounter tables). From pret/pokecrystal
-- data/wild/kanto_grass.asm: per map, seven slots of { level, species } for
-- morning, day and night (Crystal's slot chances are 30, 30, 20, 10, 5, 4,
-- 1). Species use FireRed's names (FARFETCHD, MR_MIME). `kanto` lists the
-- FireRed tables each Crystal map stands for; Gen3DayNight spreads the seven
-- slots over FireRed's twelve with the same chances. Only FireRed's own
-- tables are used; maps added in a mod are never touched.
local M = {}

M.kanto = {
  DIGLETTS_CAVE = { "FR_DIGLETTS_CAVE_B1F" },
  MOUNT_MOON = { "FR_MT_MOON_1F", "FR_MT_MOON_B1F", "FR_MT_MOON_B2F" },
  ROCK_TUNNEL_1F = { "FR_ROCK_TUNNEL_1F" },
  ROCK_TUNNEL_B1F = { "FR_ROCK_TUNNEL_B1F" },
  ROUTE_1 = { "FR_ROUTE_1" },
  ROUTE_10_NORTH = { "FR_ROUTE_10" },
  ROUTE_11 = { "FR_ROUTE_11" },
  ROUTE_13 = { "FR_ROUTE_13" },
  ROUTE_14 = { "FR_ROUTE_14" },
  ROUTE_15 = { "FR_ROUTE_15" },
  ROUTE_16 = { "FR_ROUTE_16" },
  ROUTE_17 = { "FR_ROUTE_17" },
  ROUTE_18 = { "FR_ROUTE_18" },
  ROUTE_2 = { "FR_ROUTE_2" },
  ROUTE_21 = { "FR_ROUTE_21_NORTH", "FR_ROUTE_21_SOUTH" },
  ROUTE_22 = { "FR_ROUTE_22" },
  ROUTE_24 = { "FR_ROUTE_24" },
  ROUTE_25 = { "FR_ROUTE_25" },
  ROUTE_3 = { "FR_ROUTE_3" },
  ROUTE_4 = { "FR_ROUTE_4" },
  ROUTE_5 = { "FR_ROUTE_5" },
  ROUTE_6 = { "FR_ROUTE_6" },
  ROUTE_7 = { "FR_ROUTE_7" },
  ROUTE_8 = { "FR_ROUTE_8" },
  ROUTE_9 = { "FR_ROUTE_9" },
  VICTORY_ROAD = { "FR_VICTORY_ROAD_1F", "FR_VICTORY_ROAD_2F", "FR_VICTORY_ROAD_3F" },
}

M.maps = {
  DIGLETTS_CAVE = {
    morning = { { 3, "DIGLETT" }, { 6, "DIGLETT" }, { 12, "DIGLETT" }, { 24, "DIGLETT" }, { 24, "DUGTRIO" }, { 24, "DUGTRIO" }, { 24, "DUGTRIO" } },
    day = { { 2, "DIGLETT" }, { 4, "DIGLETT" }, { 8, "DIGLETT" }, { 16, "DIGLETT" }, { 16, "DUGTRIO" }, { 16, "DUGTRIO" }, { 16, "DUGTRIO" } },
    night = { { 4, "DIGLETT" }, { 8, "DIGLETT" }, { 16, "DIGLETT" }, { 32, "DIGLETT" }, { 32, "DUGTRIO" }, { 32, "DUGTRIO" }, { 32, "DUGTRIO" } },
  },
  MOUNT_MOON = {
    morning = { { 6, "ZUBAT" }, { 8, "GEODUDE" }, { 8, "SANDSHREW" }, { 12, "PARAS" }, { 10, "GEODUDE" }, { 8, "CLEFAIRY" }, { 8, "CLEFAIRY" } },
    day = { { 6, "ZUBAT" }, { 8, "GEODUDE" }, { 8, "SANDSHREW" }, { 12, "PARAS" }, { 10, "GEODUDE" }, { 8, "CLEFAIRY" }, { 8, "CLEFAIRY" } },
    night = { { 6, "ZUBAT" }, { 8, "GEODUDE" }, { 8, "CLEFAIRY" }, { 12, "PARAS" }, { 10, "GEODUDE" }, { 12, "CLEFAIRY" }, { 12, "CLEFAIRY" } },
  },
  ROCK_TUNNEL_1F = {
    morning = { { 10, "CUBONE" }, { 11, "GEODUDE" }, { 12, "MACHOP" }, { 12, "ZUBAT" }, { 15, "MACHOKE" }, { 12, "MAROWAK" }, { 12, "MAROWAK" } },
    day = { { 10, "CUBONE" }, { 11, "GEODUDE" }, { 12, "MACHOP" }, { 12, "ZUBAT" }, { 15, "MACHOKE" }, { 12, "MAROWAK" }, { 12, "MAROWAK" } },
    night = { { 12, "ZUBAT" }, { 11, "GEODUDE" }, { 12, "GEODUDE" }, { 17, "HAUNTER" }, { 15, "ZUBAT" }, { 15, "ZUBAT" }, { 15, "ZUBAT" } },
  },
  ROCK_TUNNEL_B1F = {
    morning = { { 12, "CUBONE" }, { 14, "GEODUDE" }, { 16, "ONIX" }, { 12, "ZUBAT" }, { 15, "MAROWAK" }, { 15, "KANGASKHAN" }, { 15, "KANGASKHAN" } },
    day = { { 12, "CUBONE" }, { 14, "GEODUDE" }, { 16, "ONIX" }, { 12, "ZUBAT" }, { 15, "MAROWAK" }, { 15, "KANGASKHAN" }, { 15, "KANGASKHAN" } },
    night = { { 12, "ZUBAT" }, { 14, "GEODUDE" }, { 16, "ONIX" }, { 15, "ZUBAT" }, { 15, "HAUNTER" }, { 15, "GOLBAT" }, { 15, "GOLBAT" } },
  },
  ROUTE_1 = {
    morning = { { 2, "PIDGEY" }, { 2, "RATTATA" }, { 3, "SENTRET" }, { 3, "PIDGEY" }, { 6, "FURRET" }, { 4, "PIDGEY" }, { 4, "PIDGEY" } },
    day = { { 2, "PIDGEY" }, { 2, "RATTATA" }, { 3, "SENTRET" }, { 3, "PIDGEY" }, { 6, "FURRET" }, { 4, "PIDGEY" }, { 4, "PIDGEY" } },
    night = { { 2, "HOOTHOOT" }, { 2, "RATTATA" }, { 3, "RATTATA" }, { 3, "HOOTHOOT" }, { 6, "RATICATE" }, { 4, "HOOTHOOT" }, { 4, "HOOTHOOT" } },
  },
  ROUTE_10_NORTH = {
    morning = { { 15, "SPEAROW" }, { 17, "VOLTORB" }, { 15, "RATICATE" }, { 15, "FEAROW" }, { 15, "MAROWAK" }, { 16, "ELECTABUZZ" }, { 16, "ELECTABUZZ" } },
    day = { { 15, "SPEAROW" }, { 17, "VOLTORB" }, { 15, "RATICATE" }, { 15, "FEAROW" }, { 15, "MAROWAK" }, { 18, "ELECTABUZZ" }, { 18, "ELECTABUZZ" } },
    night = { { 15, "VENONAT" }, { 17, "VOLTORB" }, { 15, "RATICATE" }, { 15, "VENOMOTH" }, { 15, "ZUBAT" }, { 16, "ELECTABUZZ" }, { 16, "ELECTABUZZ" } },
  },
  ROUTE_11 = {
    morning = { { 14, "HOPPIP" }, { 13, "RATICATE" }, { 15, "MAGNEMITE" }, { 16, "PIDGEOTTO" }, { 16, "RATTATA" }, { 16, "HOPPIP" }, { 16, "HOPPIP" } },
    day = { { 14, "HOPPIP" }, { 13, "RATICATE" }, { 15, "MAGNEMITE" }, { 16, "PIDGEOTTO" }, { 16, "RATTATA" }, { 16, "HOPPIP" }, { 16, "HOPPIP" } },
    night = { { 14, "DROWZEE" }, { 13, "MEOWTH" }, { 15, "MAGNEMITE" }, { 16, "NOCTOWL" }, { 16, "RATICATE" }, { 16, "HYPNO" }, { 16, "HYPNO" } },
  },
  ROUTE_13 = {
    morning = { { 23, "NIDORINO" }, { 23, "NIDORINA" }, { 25, "PIDGEOTTO" }, { 25, "HOPPIP" }, { 27, "HOPPIP" }, { 27, "HOPPIP" }, { 25, "CHANSEY" } },
    day = { { 23, "NIDORINO" }, { 23, "NIDORINA" }, { 25, "PIDGEOTTO" }, { 25, "HOPPIP" }, { 27, "HOPPIP" }, { 27, "HOPPIP" }, { 25, "CHANSEY" } },
    night = { { 23, "VENONAT" }, { 23, "QUAGSIRE" }, { 25, "NOCTOWL" }, { 25, "VENOMOTH" }, { 25, "QUAGSIRE" }, { 25, "QUAGSIRE" }, { 25, "CHANSEY" } },
  },
  ROUTE_14 = {
    morning = { { 26, "NIDORINO" }, { 26, "NIDORINA" }, { 28, "PIDGEOTTO" }, { 28, "HOPPIP" }, { 30, "SKIPLOOM" }, { 30, "SKIPLOOM" }, { 28, "CHANSEY" } },
    day = { { 26, "NIDORINO" }, { 26, "NIDORINA" }, { 28, "PIDGEOTTO" }, { 28, "HOPPIP" }, { 30, "SKIPLOOM" }, { 30, "SKIPLOOM" }, { 28, "CHANSEY" } },
    night = { { 26, "VENONAT" }, { 26, "QUAGSIRE" }, { 28, "NOCTOWL" }, { 28, "VENOMOTH" }, { 28, "QUAGSIRE" }, { 28, "QUAGSIRE" }, { 28, "CHANSEY" } },
  },
  ROUTE_15 = {
    morning = { { 23, "NIDORINO" }, { 23, "NIDORINA" }, { 25, "PIDGEOTTO" }, { 25, "HOPPIP" }, { 27, "HOPPIP" }, { 27, "HOPPIP" }, { 25, "CHANSEY" } },
    day = { { 23, "NIDORINO" }, { 23, "NIDORINA" }, { 25, "PIDGEOTTO" }, { 25, "HOPPIP" }, { 27, "HOPPIP" }, { 27, "HOPPIP" }, { 25, "CHANSEY" } },
    night = { { 23, "VENONAT" }, { 23, "QUAGSIRE" }, { 25, "NOCTOWL" }, { 25, "VENOMOTH" }, { 25, "QUAGSIRE" }, { 25, "QUAGSIRE" }, { 25, "CHANSEY" } },
  },
  ROUTE_16 = {
    morning = { { 26, "GRIMER" }, { 27, "FEAROW" }, { 28, "GRIMER" }, { 29, "FEAROW" }, { 29, "FEAROW" }, { 30, "MUK" }, { 30, "MUK" } },
    day = { { 26, "GRIMER" }, { 27, "FEAROW" }, { 28, "GRIMER" }, { 29, "FEAROW" }, { 29, "SLUGMA" }, { 30, "MUK" }, { 30, "MUK" } },
    night = { { 26, "GRIMER" }, { 27, "GRIMER" }, { 28, "GRIMER" }, { 29, "MURKROW" }, { 29, "MURKROW" }, { 30, "MUK" }, { 30, "MUK" } },
  },
  ROUTE_17 = {
    morning = { { 30, "FEAROW" }, { 29, "GRIMER" }, { 31, "GRIMER" }, { 32, "FEAROW" }, { 33, "GRIMER" }, { 33, "MUK" }, { 33, "MUK" } },
    day = { { 30, "FEAROW" }, { 29, "SLUGMA" }, { 29, "GRIMER" }, { 32, "FEAROW" }, { 32, "SLUGMA" }, { 33, "MUK" }, { 33, "MUK" } },
    night = { { 30, "GRIMER" }, { 29, "GRIMER" }, { 31, "GRIMER" }, { 32, "GRIMER" }, { 33, "GRIMER" }, { 33, "MUK" }, { 33, "MUK" } },
  },
  ROUTE_18 = {
    morning = { { 26, "GRIMER" }, { 27, "FEAROW" }, { 28, "GRIMER" }, { 29, "FEAROW" }, { 29, "FEAROW" }, { 30, "MUK" }, { 30, "MUK" } },
    day = { { 26, "GRIMER" }, { 27, "FEAROW" }, { 28, "GRIMER" }, { 29, "FEAROW" }, { 29, "SLUGMA" }, { 30, "MUK" }, { 30, "MUK" } },
    night = { { 26, "GRIMER" }, { 27, "GRIMER" }, { 28, "GRIMER" }, { 29, "GRIMER" }, { 29, "GRIMER" }, { 30, "MUK" }, { 30, "MUK" } },
  },
  ROUTE_2 = {
    morning = { { 3, "CATERPIE" }, { 3, "LEDYBA" }, { 5, "PIDGEY" }, { 7, "BUTTERFREE" }, { 7, "LEDIAN" }, { 4, "PIKACHU" }, { 4, "PIKACHU" } },
    day = { { 3, "CATERPIE" }, { 3, "PIDGEY" }, { 5, "PIDGEY" }, { 7, "BUTTERFREE" }, { 7, "PIDGEOTTO" }, { 4, "PIKACHU" }, { 4, "PIKACHU" } },
    night = { { 3, "HOOTHOOT" }, { 3, "SPINARAK" }, { 5, "HOOTHOOT" }, { 7, "NOCTOWL" }, { 7, "ARIADOS" }, { 4, "NOCTOWL" }, { 4, "NOCTOWL" } },
  },
  ROUTE_21 = {
    morning = { { 30, "TANGELA" }, { 25, "RATTATA" }, { 35, "TANGELA" }, { 20, "RATICATE" }, { 30, "MR_MIME" }, { 28, "MR_MIME" }, { 28, "MR_MIME" } },
    day = { { 30, "TANGELA" }, { 25, "RATTATA" }, { 35, "TANGELA" }, { 20, "RATICATE" }, { 28, "MR_MIME" }, { 30, "MR_MIME" }, { 30, "MR_MIME" } },
    night = { { 30, "TANGELA" }, { 25, "RATTATA" }, { 35, "TANGELA" }, { 20, "RATICATE" }, { 30, "TANGELA" }, { 28, "TANGELA" }, { 28, "TANGELA" } },
  },
  ROUTE_22 = {
    morning = { { 3, "RATTATA" }, { 3, "SPEAROW" }, { 5, "SPEAROW" }, { 4, "DODUO" }, { 6, "PONYTA" }, { 7, "FEAROW" }, { 7, "FEAROW" } },
    day = { { 3, "RATTATA" }, { 3, "SPEAROW" }, { 5, "SPEAROW" }, { 4, "DODUO" }, { 6, "PONYTA" }, { 7, "FEAROW" }, { 7, "FEAROW" } },
    night = { { 3, "RATTATA" }, { 3, "POLIWAG" }, { 5, "RATTATA" }, { 4, "POLIWAG" }, { 6, "RATTATA" }, { 7, "RATTATA" }, { 7, "RATTATA" } },
  },
  ROUTE_24 = {
    morning = { { 8, "CATERPIE" }, { 10, "CATERPIE" }, { 12, "METAPOD" }, { 12, "ABRA" }, { 10, "BELLSPROUT" }, { 14, "BUTTERFREE" }, { 14, "BUTTERFREE" } },
    day = { { 8, "CATERPIE" }, { 12, "SUNKERN" }, { 10, "CATERPIE" }, { 12, "ABRA" }, { 10, "BELLSPROUT" }, { 14, "BUTTERFREE" }, { 14, "BUTTERFREE" } },
    night = { { 10, "VENONAT" }, { 10, "ODDISH" }, { 12, "ODDISH" }, { 12, "ABRA" }, { 10, "BELLSPROUT" }, { 14, "GLOOM" }, { 14, "GLOOM" } },
  },
  ROUTE_25 = {
    morning = { { 10, "CATERPIE" }, { 10, "PIDGEY" }, { 12, "PIDGEOTTO" }, { 12, "METAPOD" }, { 10, "BELLSPROUT" }, { 14, "BUTTERFREE" }, { 14, "BUTTERFREE" } },
    day = { { 10, "CATERPIE" }, { 10, "PIDGEY" }, { 12, "PIDGEOTTO" }, { 12, "METAPOD" }, { 10, "BELLSPROUT" }, { 14, "BUTTERFREE" }, { 14, "BUTTERFREE" } },
    night = { { 10, "ODDISH" }, { 10, "HOOTHOOT" }, { 10, "VENONAT" }, { 12, "NOCTOWL" }, { 10, "BELLSPROUT" }, { 14, "NOCTOWL" }, { 14, "NOCTOWL" } },
  },
  ROUTE_3 = {
    morning = { { 5, "SPEAROW" }, { 5, "RATTATA" }, { 8, "EKANS" }, { 10, "RATICATE" }, { 10, "ARBOK" }, { 10, "SANDSHREW" }, { 10, "SANDSHREW" } },
    day = { { 5, "SPEAROW" }, { 5, "RATTATA" }, { 8, "EKANS" }, { 10, "RATICATE" }, { 10, "ARBOK" }, { 10, "SANDSHREW" }, { 10, "SANDSHREW" } },
    night = { { 5, "RATTATA" }, { 10, "RATTATA" }, { 10, "RATICATE" }, { 6, "ZUBAT" }, { 5, "RATTATA" }, { 6, "CLEFAIRY" }, { 6, "CLEFAIRY" } },
  },
  ROUTE_4 = {
    morning = { { 5, "SPEAROW" }, { 5, "RATTATA" }, { 8, "EKANS" }, { 10, "RATICATE" }, { 10, "ARBOK" }, { 10, "SANDSHREW" }, { 10, "SANDSHREW" } },
    day = { { 5, "SPEAROW" }, { 5, "RATTATA" }, { 8, "EKANS" }, { 10, "RATICATE" }, { 10, "ARBOK" }, { 10, "SANDSHREW" }, { 10, "SANDSHREW" } },
    night = { { 5, "RATTATA" }, { 10, "RATTATA" }, { 10, "RATICATE" }, { 6, "ZUBAT" }, { 5, "RATTATA" }, { 6, "CLEFAIRY" }, { 6, "CLEFAIRY" } },
  },
  ROUTE_5 = {
    morning = { { 13, "PIDGEY" }, { 13, "SNUBBULL" }, { 15, "PIDGEOTTO" }, { 12, "ABRA" }, { 14, "JIGGLYPUFF" }, { 14, "ABRA" }, { 14, "ABRA" } },
    day = { { 13, "PIDGEY" }, { 13, "SNUBBULL" }, { 15, "PIDGEOTTO" }, { 12, "ABRA" }, { 14, "JIGGLYPUFF" }, { 14, "ABRA" }, { 14, "ABRA" } },
    night = { { 13, "HOOTHOOT" }, { 13, "MEOWTH" }, { 15, "NOCTOWL" }, { 12, "ABRA" }, { 14, "JIGGLYPUFF" }, { 14, "ABRA" }, { 14, "ABRA" } },
  },
  ROUTE_6 = {
    morning = { { 13, "RATTATA" }, { 13, "SNUBBULL" }, { 14, "MAGNEMITE" }, { 15, "RATICATE" }, { 12, "JIGGLYPUFF" }, { 15, "GRANBULL" }, { 15, "GRANBULL" } },
    day = { { 13, "RATTATA" }, { 13, "SNUBBULL" }, { 14, "MAGNEMITE" }, { 15, "RATICATE" }, { 12, "JIGGLYPUFF" }, { 15, "GRANBULL" }, { 15, "GRANBULL" } },
    night = { { 13, "MEOWTH" }, { 13, "DROWZEE" }, { 14, "MAGNEMITE" }, { 15, "PSYDUCK" }, { 12, "JIGGLYPUFF" }, { 15, "RATICATE" }, { 15, "RATICATE" } },
  },
  ROUTE_7 = {
    morning = { { 17, "RATTATA" }, { 17, "SPEAROW" }, { 18, "SNUBBULL" }, { 18, "RATICATE" }, { 18, "JIGGLYPUFF" }, { 16, "ABRA" }, { 16, "ABRA" } },
    day = { { 17, "RATTATA" }, { 17, "SPEAROW" }, { 18, "SNUBBULL" }, { 18, "RATICATE" }, { 18, "JIGGLYPUFF" }, { 16, "ABRA" }, { 16, "ABRA" } },
    night = { { 17, "MEOWTH" }, { 17, "MURKROW" }, { 18, "HOUNDOUR" }, { 18, "PERSIAN" }, { 18, "JIGGLYPUFF" }, { 16, "ABRA" }, { 16, "ABRA" } },
  },
  ROUTE_8 = {
    morning = { { 17, "SNUBBULL" }, { 19, "PIDGEOTTO" }, { 16, "ABRA" }, { 17, "GROWLITHE" }, { 16, "JIGGLYPUFF" }, { 18, "KADABRA" }, { 18, "KADABRA" } },
    day = { { 17, "SNUBBULL" }, { 19, "PIDGEOTTO" }, { 16, "ABRA" }, { 17, "GROWLITHE" }, { 16, "JIGGLYPUFF" }, { 18, "KADABRA" }, { 18, "KADABRA" } },
    night = { { 17, "MEOWTH" }, { 20, "NOCTOWL" }, { 16, "ABRA" }, { 17, "HAUNTER" }, { 16, "JIGGLYPUFF" }, { 18, "KADABRA" }, { 18, "KADABRA" } },
  },
  ROUTE_9 = {
    morning = { { 15, "RATTATA" }, { 15, "SPEAROW" }, { 15, "RATICATE" }, { 15, "FEAROW" }, { 15, "FEAROW" }, { 18, "MAROWAK" }, { 18, "MAROWAK" } },
    day = { { 15, "RATTATA" }, { 15, "SPEAROW" }, { 15, "RATICATE" }, { 15, "FEAROW" }, { 15, "FEAROW" }, { 18, "MAROWAK" }, { 18, "MAROWAK" } },
    night = { { 15, "RATTATA" }, { 15, "VENONAT" }, { 15, "RATICATE" }, { 15, "VENOMOTH" }, { 15, "ZUBAT" }, { 18, "RATICATE" }, { 18, "RATICATE" } },
  },
  VICTORY_ROAD = {
    morning = { { 34, "GRAVELER" }, { 32, "RHYHORN" }, { 33, "ONIX" }, { 34, "GOLBAT" }, { 35, "SANDSLASH" }, { 35, "RHYDON" }, { 35, "RHYDON" } },
    day = { { 34, "GRAVELER" }, { 32, "RHYHORN" }, { 33, "ONIX" }, { 34, "GOLBAT" }, { 35, "SANDSLASH" }, { 35, "RHYDON" }, { 35, "RHYDON" } },
    night = { { 34, "GOLBAT" }, { 34, "GRAVELER" }, { 32, "ONIX" }, { 36, "GRAVELER" }, { 38, "GRAVELER" }, { 40, "GRAVELER" }, { 40, "GRAVELER" } },
  },
}

return M
