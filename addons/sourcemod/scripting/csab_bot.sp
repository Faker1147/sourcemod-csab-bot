#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <cstrike>

#define PLUGIN_VERSION  "2.0.0"
#define MAX_PRIORITY    32
#define MAX_ROSTER      160
#define MAX_BEHAVIOR    16

#define FILE_BEHAVIOR   "configs/csab_bot/behavior.cfg"
#define FILE_ROSTER     "configs/csab_bot/roster.cfg"

public Plugin myinfo = {
    name        = "CSAB Bot Pack",
    author      = "CSAB Dev",
    description = "独立的CSAB BOT系统，兼容官方ZBot",
    version     = PLUGIN_VERSION,
    url         = ""
};

// ==================== ConVar ====================
ConVar g_cvEnabled;
ConVar g_cvAutoBuy;
ConVar g_cvAutoBuyArmor;
ConVar g_cvAimMult;

// ==================== 结构 ====================
enum struct RosterEntry {
    char name[64];
    char behavior[32];
    int  team;
    bool assigned;
    int  assignedTo;
}

enum struct BehaviorProfile {
    char  name[32];
    float aimSpeed;
    float aimFov;
    float reaction;
    float aimError;
    float aggression;
    int   weaponCount;
}

// ==================== 全局 ====================
RosterEntry     g_Roster[MAX_ROSTER];
int             g_RosterCount     = 0;
int             g_iBotRoster[MAXPLAYERS + 1];    // -1 = ZBot, >=0 = CSAB
int             g_PendingRoster   = -1;

BehaviorProfile g_Behavior[MAX_BEHAVIOR];
int             g_BehaviorCount   = 0;
int             g_iBotBehavior[MAXPLAYERS + 1];

// enum struct 字段不支持二维数组，武器列表单独用三维全局数组存放
char            g_BehaviorWeapons[MAX_BEHAVIOR][MAX_PRIORITY][32];

bool            g_bBoughtThisRound[MAXPLAYERS + 1];
float           g_fNextAimTime[MAXPLAYERS + 1];

StringMap       g_WeaponPrices;

int             g_iTargetBot[MAXPLAYERS + 1];
bool            g_bAiming[MAXPLAYERS + 1];
bool            g_bFollowing[MAXPLAYERS + 1];

// ==================== 初始化 ====================
public void OnPluginStart()
{
    LoadTranslations("common.phrases");

    g_cvEnabled      = CreateConVar("csab_enabled",      "1",  "启用CSAB",        FCVAR_NOTIFY, true, 0.0, true, 1.0);
    g_cvAutoBuy      = CreateConVar("csab_autobuy",      "1",  "CSAB自动购买",    FCVAR_NOTIFY, true, 0.0, true, 1.0);
    g_cvAutoBuyArmor = CreateConVar("csab_autobuy_armor","1",  "CSAB购买护甲",    FCVAR_NOTIFY, true, 0.0, true, 1.0);
    g_cvAimMult      = CreateConVar("csab_aim_mult",     "1.0","全局瞄准倍率",    FCVAR_NOTIFY, true, 0.1, true, 5.0);

    InitWeaponPrices();

    // ---- 只注册 csab_* 命令，绝不 Hook bot_* ----
    AddCommandListener(Listener_CsabAdd,   "csab_add");
    AddCommandListener(Listener_CsabAdd,   "csab_add_t");
    AddCommandListener(Listener_CsabAdd,   "csab_add_ct");
    AddCommandListener(Listener_CsabKick,  "csab_kick");
    AddCommandListener(Listener_CsabQuota, "csab_quota");
    AddCommandListener(Listener_CsabKill,  "csab_kill");
    AddCommandListener(Listener_CsabStop,  "csab_stop");

    // ---- 玩家侧命令 ----
    RegConsoleCmd("sm_csab",          Command_Menu,        "CSAB 控制菜单");
    RegConsoleCmd("sm_csabspawn",     Command_Spawn,       "生成 csab 类型BOT [数量]");
    RegConsoleCmd("sm_csabspawnname", Command_SpawnName,   "生成指定名单BOT");
    RegConsoleCmd("sm_csabkick",      Command_KickAll,     "踢出所有 CSAB BOT");
    RegConsoleCmd("sm_csabinfo",      Command_Info,        "查看当前控制的BOT");
    RegConsoleCmd("sm_csabroster",    Command_RosterList,  "查看 CSAB 名单");
    RegConsoleCmd("sm_csabreload",    Command_Reload,      "重载 CSAB 配置");
    RegConsoleCmd("sm_csabaim",       Command_AimToggle,   "切换BOT自动瞄准");
    RegConsoleCmd("sm_csabfollow",    Command_Follow,      "切换BOT跟随");
    RegConsoleCmd("sm_csabbuy",       Command_Buy,         "给BOT买枪 [武器]");
    RegConsoleCmd("sm_csabrelease",   Command_Release,     "释放BOT控制");

    RegConsoleCmd("+botaim",  Command_AimKey,    "快捷键：按住瞄准");
    RegConsoleCmd("-botaim",  Command_AimRelease,"快捷键：松开瞄准");
    RegConsoleCmd("+botmove", Command_MoveKey,   "快捷键：BOT前进");

    HookEvent("player_death", Event_PlayerDeath);
    HookEvent("round_start",  Event_RoundStart, EventHookMode_PostNoCopy);
    HookEvent("player_spawn", Event_PlayerSpawn, EventHookMode_Post);

    for (int i = 1; i <= MaxClients; i++)
    {
        g_iBotRoster[i]   = -1;   // 默认按 ZBot 处理
        g_iBotBehavior[i] = -1;
    }

    AutoExecConfig(true, "csab_bot");
}

public void OnMapStart()       { LoadAllConfigs(); }
public void OnConfigsExecuted() { if (g_RosterCount == 0) LoadAllConfigs(); }

// ==================== 类型判定 ====================
bool IsCsabBot(int client)
{
    return (IsValidClient(client) && IsFakeClient(client) && g_iBotRoster[client] >= 0);
}

bool IsZBot(int client)
{
    return (IsValidClient(client) && IsFakeClient(client) && g_iBotRoster[client] < 0);
}

// ==================== 加载配置 ====================
void LoadAllConfigs()
{
    LoadBehavior();
    LoadRoster();
}

void LoadBehavior()
{
    char path[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, path, sizeof(path), FILE_BEHAVIOR);
    if (!FileExists(path)) { PrintToServer("[CSAB] 缺少 %s", FILE_BEHAVIOR); return; }

    KeyValues kv = new KeyValues("BotBehavior");
    if (!kv.ImportFromFile(path)) { delete kv; return; }

    g_BehaviorCount = 0;
    if (kv.GotoFirstSubKey())
    {
        do
        {
            if (g_BehaviorCount >= MAX_BEHAVIOR) break;

            kv.GetSectionName(g_Behavior[g_BehaviorCount].name, 32);
            g_Behavior[g_BehaviorCount].aimSpeed   = kv.GetFloat("aim_speed",  8.0);
            g_Behavior[g_BehaviorCount].aimFov     = kv.GetFloat("aim_fov",    60.0);
            g_Behavior[g_BehaviorCount].reaction   = kv.GetFloat("reaction",   0.20);
            g_Behavior[g_BehaviorCount].aimError   = kv.GetFloat("aim_error",  2.0);
            g_Behavior[g_BehaviorCount].aggression = kv.GetFloat("aggression", 0.5);

            char buf[512];
            kv.GetString("weapons", buf, sizeof(buf), "");
            g_Behavior[g_BehaviorCount].weaponCount = 0;
            if (buf[0] != '\0')
            {
                char parts[MAX_PRIORITY][32];
                int cnt = ExplodeString(buf, ",", parts, MAX_PRIORITY, 32);
                for (int i = 0; i < cnt && i < MAX_PRIORITY; i++)
                {
                    TrimString(parts[i]);
                    strcopy(g_BehaviorWeapons[g_BehaviorCount][i], 32, parts[i]);
                    g_Behavior[g_BehaviorCount].weaponCount++;
                }
            }
            g_BehaviorCount++;
        } while (kv.GotoNextKey());
    }
    delete kv;
    PrintToServer("[CSAB] 已加载 %d 个行为档", g_BehaviorCount);
}

void LoadRoster()
{
    for (int i = 1; i <= MaxClients; i++) g_iBotRoster[i] = -1;
    for (int i = 0; i < MAX_ROSTER; i++)
    {
        g_Roster[i].assigned   = false;
        g_Roster[i].assignedTo = 0;
    }
    g_RosterCount = 0;

    char path[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, path, sizeof(path), FILE_ROSTER);
    if (!FileExists(path)) { PrintToServer("[CSAB] 缺少 %s", FILE_ROSTER); return; }

    KeyValues kv = new KeyValues("BotRoster");
    if (!kv.ImportFromFile(path)) { delete kv; return; }

    if (kv.GotoFirstSubKey())
    {
        do
        {
            if (g_RosterCount >= MAX_ROSTER) break;
            kv.GetSectionName(g_Roster[g_RosterCount].name, 64);
            kv.GetString("behavior", g_Roster[g_RosterCount].behavior, 32, "csab");

            char t[8];
            kv.GetString("team", t, sizeof(t), "any");
            if (StrEqual(t, "t", false))       g_Roster[g_RosterCount].team = 2;
            else if (StrEqual(t, "ct", false)) g_Roster[g_RosterCount].team = 3;
            else                                g_Roster[g_RosterCount].team = 0;

            g_Roster[g_RosterCount].assigned = false;
            g_RosterCount++;
        } while (kv.GotoNextKey());
    }
    delete kv;
    PrintToServer("[CSAB] 已加载 %d 个BOT名单", g_RosterCount);
}

void InitWeaponPrices()
{
    g_WeaponPrices = new StringMap();
    g_WeaponPrices.SetValue("ak47",     2500);
    g_WeaponPrices.SetValue("m4a1",     3100);
    g_WeaponPrices.SetValue("sg552",    3500);
    g_WeaponPrices.SetValue("aug",      3500);
    g_WeaponPrices.SetValue("famas",    2250);
    g_WeaponPrices.SetValue("galil",    2000);
    g_WeaponPrices.SetValue("awp",      4750);
    g_WeaponPrices.SetValue("scout",    2750);
    g_WeaponPrices.SetValue("sg550",    4200);
    g_WeaponPrices.SetValue("g3sg1",    5000);
    g_WeaponPrices.SetValue("mp5navy",  1500);
    g_WeaponPrices.SetValue("tmp",      1250);
    g_WeaponPrices.SetValue("p90",      2350);
    g_WeaponPrices.SetValue("mac10",    1400);
    g_WeaponPrices.SetValue("ump45",    1700);
    g_WeaponPrices.SetValue("m3",       1700);
    g_WeaponPrices.SetValue("xm1014",   3000);
    g_WeaponPrices.SetValue("nova",     1200);
    g_WeaponPrices.SetValue("m249",     5750);
    g_WeaponPrices.SetValue("glock18",  0);
    g_WeaponPrices.SetValue("usp",      0);
    g_WeaponPrices.SetValue("p228",     600);
    g_WeaponPrices.SetValue("deagle",   650);
    g_WeaponPrices.SetValue("elite",    800);
    g_WeaponPrices.SetValue("fiveseven",750);
}

// ==================== CSAB 命令拦截 ====================
public Action Listener_CsabAdd(int client, const char[] cmd, int argc)
{
    if (!g_cvEnabled.BoolValue) return Plugin_Continue;

    int team = 0;
    if (StrEqual(cmd, "csab_add_t",  false)) team = 2;
    if (StrEqual(cmd, "csab_add_ct", false)) team = 3;

    int idx = FindFreeSlot(team);
    if (idx < 0)
    {
        if (client > 0) PrintToChat(client, "[CSAB] 名单已满");
        return Plugin_Handled;
    }

    g_PendingRoster = idx;
    g_Roster[idx].assigned = true;

    char c[32];
    if (team == 2)      strcopy(c, sizeof(c), "bot_add_t");
    else if (team == 3) strcopy(c, sizeof(c), "bot_add_ct");
    else                strcopy(c, sizeof(c), "bot_add");
    ServerCommand(c);   // 借壳生成，随后被标记为 CSAB
    return Plugin_Handled;
}

public Action Listener_CsabKick(int client, const char[] cmd, int argc)
{
    if (!g_cvEnabled.BoolValue) return Plugin_Continue;

    if (argc == 0)
    {
        int n = KickAllCsab();
        if (client > 0) PrintToChat(client, "[CSAB] 已踢出 %d 个 CSAB BOT", n);
        return Plugin_Handled;
    }

    char name[64]; GetCmdArg(1, name, sizeof(name));
    int bot = FindCsabBotByName(name);
    if (bot > 0) KickClient(bot, "CSAB: 管理员踢出");
    return Plugin_Handled;
}

public Action Listener_CsabQuota(int client, const char[] cmd, int argc)
{
    if (!g_cvEnabled.BoolValue) return Plugin_Continue;
    if (argc < 1) return Plugin_Handled;

    char a[8]; GetCmdArg(1, a, sizeof(a));
    int quota = StringToInt(a);
    int cur   = CountCsabBots();

    if (cur < quota)
    {
        for (int i = 0; i < quota - cur; i++)
        {
            int idx = FindFreeSlot(0);
            if (idx < 0) break;
            g_PendingRoster = idx;
            g_Roster[idx].assigned = true;
            ServerCommand("bot_add");
        }
    }
    else if (cur > quota)
    {
        int need = cur - quota, kicked = 0;
        for (int i = 1; i <= MaxClients && kicked < need; i++)
            if (IsCsabBot(i)) { KickClient(i, "CSAB: 配额调整"); kicked++; }
    }
    return Plugin_Handled;
}

public Action Listener_CsabKill(int client, const char[] cmd, int argc)
{
    if (!g_cvEnabled.BoolValue) return Plugin_Continue;
    for (int i = 1; i <= MaxClients; i++)
        if (IsCsabBot(i) && IsPlayerAlive(i)) ForcePlayerSuicide(i);
    return Plugin_Handled;
}

public Action Listener_CsabStop(int client, const char[] cmd, int argc)
{
    if (!g_cvEnabled.BoolValue) return Plugin_Continue;
    return Plugin_Handled;
}

// ==================== 生成 & 分配 ====================
void SpawnCsabBot(int team, int byClient)
{
    if (g_RosterCount == 0)
    {
        if (byClient > 0) PrintToChat(byClient, "[CSAB] 名单为空");
        return;
    }
    int idx = FindFreeSlot(team);
    if (idx < 0)
    {
        if (byClient > 0) PrintToChat(byClient, "[CSAB] 名单已用尽");
        return;
    }
    g_PendingRoster = idx;
    g_Roster[idx].assigned = true;

    char c[32];
    if (team == 2)      strcopy(c, sizeof(c), "bot_add_t");
    else if (team == 3) strcopy(c, sizeof(c), "bot_add_ct");
    else                strcopy(c, sizeof(c), "bot_add");
    ServerCommand(c);
}

public void OnClientPutInServer(int client)
{
    g_iBotRoster[client]   = -1;   // 默认 ZBot
    g_iBotBehavior[client] = -1;

    if (!IsFakeClient(client)) return;
    if (!g_cvEnabled.BoolValue) return;
    if (g_PendingRoster < 0) return;   // 关键：无预留槽位 → 是 ZBot，不分配

    CreateTimer(0.5, Timer_Assign, GetClientUserId(client));
}

public void OnClientDisconnect(int client)
{
    int idx = g_iBotRoster[client];
    if (idx >= 0 && idx < MAX_ROSTER)
    {
        g_Roster[idx].assigned   = false;
        g_Roster[idx].assignedTo = 0;
    }
    g_iBotRoster[client]   = -1;
    g_iBotBehavior[client] = -1;
}

public Action Timer_Assign(Handle timer, int userid)
{
    int client = GetClientOfUserId(userid);
    if (client <= 0 || !IsClientInGame(client) || !IsFakeClient(client)) return Plugin_Stop;
    if (g_iBotRoster[client] >= 0) return Plugin_Stop;
    if (g_PendingRoster < 0) return Plugin_Stop;   // 双保险

    int idx = g_PendingRoster;
    g_PendingRoster = -1;
    if (idx < 0 || idx >= g_RosterCount) return Plugin_Stop;

    g_iBotRoster[client]     = idx;
    g_Roster[idx].assigned   = true;
    g_Roster[idx].assignedTo = client;

    int bIdx = FindBehavior(g_Roster[idx].behavior);
    g_iBotBehavior[client] = bIdx;

    SetClientName(client, g_Roster[idx].name);
    ApplyEngineDifficulty(client, bIdx);

    PrintToChatAll("[CSAB] \x04%s\x01 加入 [%s]",
        g_Roster[idx].name, bIdx >= 0 ? g_Behavior[bIdx].name : "csab");
    return Plugin_Stop;
}

void ApplyEngineDifficulty(int bot, int bIdx)
{
    if (bIdx < 0) return;
    int diff = 1;
    char n[32];
    strcopy(n, sizeof(n), g_Behavior[bIdx].name);
    if (StrEqual(n, "csab") || StrEqual(n, "expert")) diff = 3;
    else if (StrEqual(n, "hard"))   diff = 2;
    else if (StrEqual(n, "normal")) diff = 1;
    else                            diff = 0;
    SetEntProp(bot, Prop_Send, "m_iDifficulty", diff);
}

int FindBehavior(const char[] name)
{
    for (int i = 0; i < g_BehaviorCount; i++)
        if (StrEqual(g_Behavior[i].name, name, false)) return i;
    return -1;
}

int FindFreeSlot(int team)
{
    for (int i = 0; i < g_RosterCount; i++)
    {
        if (g_Roster[i].assigned) continue;
        if (team == 0 || g_Roster[i].team == 0 || g_Roster[i].team == team) return i;
    }
    for (int i = 0; i < g_RosterCount; i++)
        if (!g_Roster[i].assigned) return i;
    return -1;
}

int FindRosterByName(const char[] name)
{
    for (int i = 0; i < g_RosterCount; i++)
        if (StrEqual(g_Roster[i].name, name, false)) return i;
    return -1;
}

int FindCsabBotByName(const char[] name)
{
    for (int i = 1; i <= MaxClients; i++)
        if (IsCsabBot(i))
        {
            char b[64]; GetClientName(i, b, sizeof(b));
            if (StrEqual(b, name, false)) return i;
        }
    return -1;
}

int CountCsabBots()
{
    int n = 0;
    for (int i = 1; i <= MaxClients; i++)
        if (IsCsabBot(i)) n++;
    return n;
}

int KickAllCsab()
{
    int n = 0;
    for (int i = 1; i <= MaxClients; i++)
        if (IsCsabBot(i)) { KickClient(i, "CSAB: 全部踢出"); n++; }
    return n;
}

// ==================== 每帧 AI ====================
public Action OnPlayerRunCmd(int client, int &buttons, int &impulse,
    float vel[3], float angles[3], int &weapon)
{
    // 玩家控制
    if (IsValidClient(client) && !IsFakeClient(client))
    {
        int bot = g_iTargetBot[client];
        if (bot > 0 && IsValidClient(bot) && IsPlayerAlive(bot))
        {
            if (g_bAiming[client])    AutoAimByBehavior(bot, FindBehavior("csab"));
            if (g_bFollowing[client]) FollowMove(bot, client, vel);
            if (buttons & IN_FORWARD) vel[0] = 250.0;
        }
        return Plugin_Continue;
    }

    // BOT 自身
    if (!IsValidClient(client) || !IsFakeClient(client)) return Plugin_Continue;
    if (!g_cvEnabled.BoolValue) return Plugin_Continue;

    // ⚠️ 只对 CSAB BOT 应用自研 AI；ZBot 完全走引擎
    if (!IsCsabBot(client)) return Plugin_Continue;

    int bIdx = g_iBotBehavior[client];
    if (bIdx < 0 || !IsPlayerAlive(client)) return Plugin_Continue;

    AutoAimByBehavior(client, bIdx);
    return Plugin_Continue;
}

void AutoAimByBehavior(int bot, int bIdx)
{
    if (bIdx < 0) return;
    float now = GetGameTime();
    if (now < g_fNextAimTime[bot]) return;

    int enemy = FindClosestEnemy(bot, g_Behavior[bIdx].aimFov);
    if (enemy <= 0) return;

    g_fNextAimTime[bot] = now + g_Behavior[bIdx].reaction;

    float bp[3], ep[3], v[3], a[3];
    GetClientEyePosition(bot, bp);
    GetClientEyePosition(enemy, ep);
    MakeVectorFromPoints(bp, ep, v);
    NormalizeVector(v, v);
    GetVectorAngles(v, a);
    a[0] *= -1.0;

    float err = g_Behavior[bIdx].aimError;
    if (err > 0.0)
    {
        a[0] += GetRandomFloat(-err, err);
        a[1] += GetRandomFloat(-err, err);
    }

    float cur[3]; GetClientEyeAngles(bot, cur);
    float spd = g_Behavior[bIdx].aimSpeed * g_cvAimMult.FloatValue;
    for (int i = 0; i < 3; i++)
    {
        float d = a[i] - cur[i];
        while (d >  180.0) d -= 360.0;
        while (d < -180.0) d += 360.0;
        cur[i] += d * (spd * GetTickInterval());
    }
    cur[0] = ClampFloat(cur[0], -89.0, 89.0);
    SetEntPropVector(bot, Prop_Send, "m_angEyeAngles[0]", cur);
}

void FollowMove(int bot, int target, float vel[3])
{
    float bp[3], tp[3];
    GetClientAbsOrigin(bot, bp);
    GetClientAbsOrigin(target, tp);
    if (GetVectorDistance(bp, tp) <= 100.0) return;

    float dir[3]; MakeVectorFromPoints(bp, tp, dir); NormalizeVector(dir, dir);
    float a[3], fwd[3];
    GetClientEyeAngles(bot, a);
    GetAngleVectors(a, fwd, NULL_VECTOR, NULL_VECTOR);
    NormalizeVector(fwd, fwd);
    vel[0] = 250.0 * GetVectorDotProduct(dir, fwd);
    vel[1] = 0.0;
    vel[2] = 0.0;
}

// ==================== 购买 ====================
public void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
    for (int i = 1; i <= MaxClients; i++) g_bBoughtThisRound[i] = false;
}

public void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client <= 0 || !IsFakeClient(client)) return;
    if (!g_cvEnabled.BoolValue) return;
    if (!IsCsabBot(client)) return;   // ⚠️ ZBot 走引擎购买

    CreateTimer(0.3, Timer_Buy, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_Buy(Handle timer, int userid)
{
    int bot = GetClientOfUserId(userid);
    if (bot > 0 && IsPlayerAlive(bot) && g_iBotBehavior[bot] >= 0)
        ApplyBuy(bot, g_iBotBehavior[bot]);
    return Plugin_Stop;
}

void ApplyBuy(int bot, int bIdx)
{
    if (!g_cvAutoBuy.BoolValue || g_bBoughtThisRound[bot]) return;

    int money = GetEntProp(bot, Prop_Send, "m_iAccount");
    int cur   = GetPlayerWeaponSlot(bot, CS_SLOT_PRIMARY);

    if (cur > 0 && HasPriorityWeapon(bot, bIdx))
    {
        g_bBoughtThisRound[bot] = true;
        TryArmor(bot);
        return;
    }

    for (int i = 0; i < g_Behavior[bIdx].weaponCount; i++)
    {
        int price;
        if (!g_WeaponPrices.GetValue(g_BehaviorWeapons[bIdx][i], price)) continue;
        if (money < price) continue;
        if (cur > 0) RemovePlayerItem(bot, cur);

        char ent[64];
        Format(ent, sizeof(ent), "weapon_%s", g_BehaviorWeapons[bIdx][i]);
        if (GivePlayerItem(bot, ent) > 0)
        {
            SetEntProp(bot, Prop_Send, "m_iAccount", money - price);
            g_bBoughtThisRound[bot] = true;
        }
        break;
    }
    TryArmor(bot);
}

bool HasPriorityWeapon(int bot, int bIdx)
{
    int w = GetPlayerWeaponSlot(bot, CS_SLOT_PRIMARY);
    if (w <= 0) return false;
    char cls[64]; GetEntityClassname(w, cls, sizeof(cls));
    char expected[64];
    for (int i = 0; i < g_Behavior[bIdx].weaponCount; i++)
    {
        Format(expected, sizeof(expected), "weapon_%s", g_BehaviorWeapons[bIdx][i]);
        if (StrEqual(cls, expected, false)) return true;
    }
    return false;
}

void TryArmor(int bot)
{
    if (!g_cvAutoBuyArmor.BoolValue) return;
    if (GetEntProp(bot, Prop_Send, "m_ArmorValue") > 0) return;
    int money = GetEntProp(bot, Prop_Send, "m_iAccount");
    if (money >= 1000)
    {
        GivePlayerItem(bot, "item_assaultsuit");
        SetEntProp(bot, Prop_Send, "m_iAccount", money - 1000);
    }
    else if (money >= 650)
    {
        GivePlayerItem(bot, "item_kevlar");
        SetEntProp(bot, Prop_Send, "m_iAccount", money - 650);
    }
}

// ==================== 事件 ====================
public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
    int v = GetClientOfUserId(event.GetInt("userid"));
    if (v <= 0) return;
    for (int i = 1; i <= MaxClients; i++)
        if (g_iTargetBot[i] == v)
        {
            g_bAiming[i]    = false;
            g_bFollowing[i] = false;
            PrintToChat(i, "[CSAB] 控制的BOT死亡，已释放");
        }
}

// ==================== 指令回调 ====================
public Action Command_Menu(int client, int args)
{
    if (client == 0) return Plugin_Handled;
    Menu m = new Menu(MenuH);
    m.SetTitle("=== CSAB 控制菜单 ===");
    m.AddItem("spawn",   "生成 CSAB BOT");
    m.AddItem("roster",  "查看名单");
    m.AddItem("aim",     "切换BOT瞄准");
    m.AddItem("follow",  "切换BOT跟随");
    m.AddItem("info",    "查看当前BOT");
    m.AddItem("kick",    "踢出所有CSAB BOT");
    m.AddItem("release", "释放控制");
    m.Display(client, 30);
    return Plugin_Handled;
}

public int MenuH(Menu menu, MenuAction action, int client, int item)
{
    if (action == MenuAction_Select)
    {
        char info[32]; menu.GetItem(item, info, sizeof(info));
        if (StrEqual(info, "spawn"))   FakeClientCommand(client, "sm_csabspawn 1");
        if (StrEqual(info, "roster"))  FakeClientCommand(client, "sm_csabroster");
        if (StrEqual(info, "aim"))     FakeClientCommand(client, "sm_csabaim");
        if (StrEqual(info, "follow"))  FakeClientCommand(client, "sm_csabfollow");
        if (StrEqual(info, "info"))    FakeClientCommand(client, "sm_csabinfo");
        if (StrEqual(info, "kick"))    FakeClientCommand(client, "sm_csabkick");
        if (StrEqual(info, "release")) FakeClientCommand(client, "sm_csabrelease");
    }
    else if (action == MenuAction_End) delete menu;
    return 0;
}

public Action Command_Spawn(int client, int args)
{
    int count = 1;
    if (args >= 1)
    {
        char a[8]; GetCmdArg(1, a, sizeof(a));
        count = StringToInt(a);
        if (count < 1)  count = 1;
        if (count > 10) count = 10;
    }
    for (int i = 0; i < count; i++) SpawnCsabBot(0, client);
    if (client > 0) PrintToChat(client, "[CSAB] 已请求生成 %d 个BOT", count);
    return Plugin_Handled;
}

public Action Command_SpawnName(int client, int args)
{
    if (args < 1)
    {
        if (client > 0) PrintToChat(client, "[CSAB] 用法: sm_csabspawnname <名字|索引>");
        return Plugin_Handled;
    }

    char a[64]; GetCmdArg(1, a, sizeof(a));
    int idx = -1;
    if (a[0] >= '0' && a[0] <= '9')
    {
        int n = StringToInt(a);
        if (n >= 1 && n <= g_RosterCount) idx = n - 1;
    }
    else idx = FindRosterByName(a);

    if (idx < 0) { if (client > 0) PrintToChat(client, "[CSAB] 找不到: %s", a); return Plugin_Handled; }
    if (g_Roster[idx].assigned) { if (client > 0) PrintToChat(client, "[CSAB] %s 已在使用", g_Roster[idx].name); return Plugin_Handled; }

    g_PendingRoster = idx;
    g_Roster[idx].assigned = true;
    ServerCommand("bot_add");
    if (client > 0) PrintToChat(client, "[CSAB] 正在生成: %s", g_Roster[idx].name);
    return Plugin_Handled;
}

public Action Command_KickAll(int client, int args)
{
    int n = KickAllCsab();
    if (client > 0) PrintToChat(client, "[CSAB] 已踢出 %d 个BOT", n);
    return Plugin_Handled;
}

public Action Command_RosterList(int client, int args)
{
    if (client == 0) return Plugin_Handled;

    PrintToChat(client, "[CSAB] 共 %d 个条目 (仅列出来源为 CSAB 名单的BOT):", g_RosterCount);

    for (int i = 0; i < g_RosterCount; i++)
    {
        PrintToChat(client, "  %d. \x04%s\x01 [%s] %s",
            i + 1,
            g_Roster[i].name,
            g_Roster[i].behavior,
            g_Roster[i].assigned ? "● 使用中" : "○ 空闲");
    }
    return Plugin_Handled;
}

public Action Command_Info(int client, int args)
{
    if (client == 0) return Plugin_Handled;

    int bot = g_iTargetBot[client];
    if (bot <= 0 || !IsValidClient(bot) || !IsFakeClient(bot))
    {
        PrintToChat(client, "[CSAB] 当前未绑定BOT，可用 sm_csabaim / sm_csabfollow 自动绑定");
        return Plugin_Handled;
    }

    int bIdx = g_iBotBehavior[bot];

    char behaviorName[32];
    if (bIdx >= 0) strcopy(behaviorName, sizeof(behaviorName), g_Behavior[bIdx].name);
    else           strcopy(behaviorName, sizeof(behaviorName), "无");

    PrintToChat(client, "[CSAB] 当前BOT: %N", bot);
    PrintToChat(client, "[CSAB] 类型: %s | 行为: %s",
        IsCsabBot(bot) ? "CSAB" : "ZBot", behaviorName);
    PrintToChat(client, "[CSAB] 瞄准: %s | 跟随: %s",
        g_bAiming[client] ? "开" : "关",
        g_bFollowing[client] ? "开" : "关");
    return Plugin_Handled;
}

public Action Command_Reload(int client, int args)
{
    LoadAllConfigs();
    if (client > 0) PrintToChat(client, "[CSAB] 配置已重载");
    return Plugin_Handled;
}

public Action Command_AimToggle(int client, int args)
{
    int bot = GetTargetBot(client);
    if (bot <= 0) return Plugin_Handled;

    g_bAiming[client] = !g_bAiming[client];
    PrintToChat(client, "[CSAB] 对 %N 的自动瞄准 %s",
        bot, g_bAiming[client] ? "开启" : "关闭");
    return Plugin_Handled;
}

public Action Command_Follow(int client, int args)
{
    int bot = GetTargetBot(client);
    if (bot <= 0) return Plugin_Handled;

    g_bFollowing[client] = !g_bFollowing[client];
    PrintToChat(client, "[CSAB] 对 %N 的跟随 %s",
        bot, g_bFollowing[client] ? "开启" : "关闭");
    return Plugin_Handled;
}

public Action Command_Buy(int client, int args)
{
    int bot = GetTargetBot(client);
    if (bot <= 0) return Plugin_Handled;
    if (args < 1)
    {
        PrintToChat(client, "[CSAB] 用法: sm_csabbuy <武器名>");
        PrintToChat(client, "[CSAB] 常用: ak47 / m4a1 / awp / deagle / mp5navy");
        return Plugin_Handled;
    }

    char w[32]; GetCmdArg(1, w, sizeof(w));

    int price;
    if (!g_WeaponPrices.GetValue(w, price))
    {
        PrintToChat(client, "[CSAB] 未知武器: %s", w);
        return Plugin_Handled;
    }

    int money = GetEntProp(bot, Prop_Send, "m_iAccount");
    if (money < price)
    {
        PrintToChat(client, "[CSAB] 金钱不足 (需要 $%d，当前 $%d)", price, money);
        return Plugin_Handled;
    }

    int cur = GetPlayerWeaponSlot(bot, CS_SLOT_PRIMARY);
    if (cur > 0) RemovePlayerItem(bot, cur);

    char ent[64]; Format(ent, sizeof(ent), "weapon_%s", w);
    if (GivePlayerItem(bot, ent) > 0)
    {
        SetEntProp(bot, Prop_Send, "m_iAccount", money - price);
        PrintToChat(client, "[CSAB] 已为 %N 购买 %s ($%d)", bot, w, price);
    }
    return Plugin_Handled;
}

public Action Command_Release(int client, int args)
{
    int bot = g_iTargetBot[client];
    if (bot > 0) PrintToChat(client, "[CSAB] 已释放对 %N 的控制", bot);

    g_iTargetBot[client] = 0;
    g_bAiming[client]    = false;
    g_bFollowing[client] = false;
    return Plugin_Handled;
}

// ==================== 快捷键回调 ====================
public Action Command_AimKey(int client, int args)
{
    if (GetTargetBot(client) <= 0) return Plugin_Handled;
    g_bAiming[client] = true;
    PrintToChat(client, "[CSAB] 瞄准开启（按住模式）");
    return Plugin_Handled;
}

public Action Command_AimRelease(int client, int args)
{
    g_bAiming[client] = false;
    PrintToChat(client, "[CSAB] 瞄准关闭");
    return Plugin_Handled;
}

public Action Command_MoveKey(int client, int args)
{
    if (GetTargetBot(client) <= 0) return Plugin_Handled;
    g_bFollowing[client] = true;
    PrintToChat(client, "[CSAB] 跟随前进中...");
    return Plugin_Handled;
}

// ==================== 辅助函数 ====================
// 优先绑定 CSAB BOT；没有 CSAB 时回退到 ZBot
int GetTargetBot(int client)
{
    if (client <= 0) return -1;

    if (g_iTargetBot[client] > 0 && IsValidClient(g_iTargetBot[client])
        && IsFakeClient(g_iTargetBot[client]))
        return g_iTargetBot[client];

    float cp[3]; GetClientAbsOrigin(client, cp);
    int nearCsab = -1, nearAny = -1;
    float mdCsab = 99999.0, mdAny = 99999.0;

    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsValidClient(i) || !IsFakeClient(i) || !IsPlayerAlive(i)) continue;

        float bp[3]; GetClientAbsOrigin(i, bp);
        float d = GetVectorDistance(cp, bp);

        if (IsCsabBot(i))
        {
            if (d < mdCsab) { mdCsab = d; nearCsab = i; }
        }
        else
        {
            if (d < mdAny) { mdAny = d; nearAny = i; }
        }
    }

    int pick = (nearCsab > 0) ? nearCsab : nearAny;
    if (pick > 0)
    {
        g_iTargetBot[client] = pick;
        PrintToChat(client, "[CSAB] 已绑定: %N (%s)",
            pick, IsCsabBot(pick) ? "CSAB" : "ZBot");
    }
    else
    {
        PrintToChat(client, "[CSAB] 附近没有BOT");
    }
    return pick;
}

int FindClosestEnemy(int bot, float maxFov)
{
    float bp[3], ba[3], bf[3];
    GetClientEyePosition(bot, bp);
    GetClientEyeAngles(bot, ba);
    GetAngleVectors(ba, bf, NULL_VECTOR, NULL_VECTOR);
    NormalizeVector(bf, bf);

    int team = GetClientTeam(bot);
    int near = -1;
    float md = 99999.0;

    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsValidClient(i) || !IsPlayerAlive(i) || i == bot) continue;
        if (GetClientTeam(i) == team) continue;

        float ep[3]; GetClientEyePosition(i, ep);
        float d[3]; MakeVectorFromPoints(bp, ep, d); NormalizeVector(d, d);

        float ang = ArcCosine(GetVectorDotProduct(bf, d)) * (180.0 / FLOAT_PI);
        if (ang > maxFov) continue;

        float dist = GetVectorDistance(bp, ep);
        if (dist < md) { md = dist; near = i; }
    }
    return near;
}

bool IsValidClient(int c)
{
    return (c > 0 && c <= MaxClients
        && IsClientInGame(c)
        && !IsClientSourceTV(c)
        && !IsClientReplay(c));
}

float ClampFloat(float v, float mn, float mx)
{
    if (v < mn) return mn;
    if (v > mx) return mx;
    return v;
}