# Imported FireRed cutscene preview audit

Three sampled input policies (0, 1, 127), at most 300 commands each. This checks preview execution, not every branch or game-effect fidelity. Dialogue references use the imported text table; direct map-event and map-hook contexts are included. Static checks traverse every reachable branch for missing scripts, movement routes and text. The on-disk firered_hgss_voxel mod contains no event overrides or editor_project.lua; unsaved editor changes are not available to this audit.

scripts: 4057
runs: 20916
complete: 20720
bounded: 196
errors: 0
crashes: 0

Map-event attachments: 2915; runs: 8745; completed: 8719; stops: 0; bounded: 26

Completion includes omitted effects and automatically answered prompts; it does not establish game fidelity.


## Remaining execution stops


## Effects omitted or approximated

- addcoins: 7 runs
- adddecoration: 6 runs
- additem: 157 runs
- braillemessage: 144 runs
- bufferboxname: 67 runs
- bufferdecorationname: 9 runs
- bufferitemname: 175 runs
- bufferitemnameplural: 15 runs
- buffermovename: 465 runs
- buffernumberstring: 166 runs
- bufferpartymonnick: 451 runs
- bufferspeciesname: 249 runs
- bufferstdstring: 267 runs
- callstd: 2483 runs
- checkcoins: 60 runs
- checkitem: 38 runs
- checkitemspace: 148 runs
- checkitemtype: 21 runs
- checkmoney: 64 runs
- checkpartymove: 444 runs
- checkplayergender: 44 runs
- checktrainerflag: 115 runs
- cleartrainerflag: 12 runs
- closedoor: 77 runs
- copyobjectxytoperm: 48 runs
- dofieldeffect: 453 runs
- doweather: 6 runs
- dowildbattle: 26 runs
- erasebox: 414 runs
- fadedefaultbgm: 268 runs
- fadeinbgm: 3 runs
- fadenewbgm: 6 runs
- fadeoutbgm: 9 runs
- fadescreen: 477 runs
- fadescreenspeed: 6 runs
- getbraillestringwidth: 12 runs
- getpartysize: 46 runs
- getplayerxy: 77 runs
- giveegg: 9 runs
- givemon: 51 runs
- hidecoinsbox: 152 runs
- hidemoneybox: 209 runs
- hidemonpic: 88 runs
- hideobjectat: 35 runs
- incrementgamestat: 44 runs
- messageautoscroll: 34 runs
- multichoice: 543 runs
- multichoicedefault: 44 runs
- multichoicegrid: 27 runs
- normalmsg: 42 runs
- opendoor: 77 runs
- playbgm: 403 runs
- playfanfare: 460 runs
- playmoncry: 239 runs
- playse: 1250 runs
- playslotmachine: 78 runs
- pokemart: 145 runs
- preview_approximation: 11706 runs
- random: 21 runs
- removecoins: 26 runs
- removeitem: 145 runs
- removemoney: 60 runs
- savebgm: 32 runs
- setdynamicwarp: 99 runs
- setescapewarp: 18 runs
- setfieldeffectargument: 525 runs
- setmaplayoutindex: 20 runs
- setmetatile: 1063 runs
- setobjectmovementtype: 178 runs
- setrespawn: 131 runs
- setstepcallback: 6 runs
- settrainerflag: 52 runs
- setwarp: 3 runs
- setweather: 6 runs
- setwildbattle: 59 runs
- setworldmapflag: 306 runs
- showcoinsbox: 24 runs
- showmoneybox: 74 runs
- showmonpic: 74 runs
- signmsg: 42 runs
- special: 4696 runs
- specialvar: 2426 runs
- textcolor: 2004 runs
- trainerbattle: 3716 runs
- trywondercardscript: 60 runs
- updatecoinsbox: 36 runs
- updatemoneybox: 65 runs
- waitdooranim: 77 runs
- waitfanfare: 457 runs
- waitfieldeffect: 140 runs
- waitmoncry: 239 runs
- waitse: 604 runs
- waitstate: 1344 runs
- warp: 126 runs
- warphole: 6 runs
- warpspinenter: 1 runs
- yesnobox: 6 runs

Per-event results: cutscene-event-results.json (6972 records).
