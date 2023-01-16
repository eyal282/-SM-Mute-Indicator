
#include <sourcemod>
#include <basecomm>
#include <sdktools>
#include <autoexecconfig>

#define PLUGIN_VERSION "1.0"
#pragma newdecls required

#pragma semicolon 1

#define DEFAULT_MUTE_MESSAGE "You are muted."

bool g_bSpeaking[MAXPLAYERS+1];
bool g_bLastState[MAXPLAYERS+1];

Handle hcv_Enabled;

GlobalForward g_fwIndicate;
GlobalForward g_fwIndicatePost;

enum struct g_message
{
    char message[512];
    // In seconds. If you have a float use RoundToCeil so you don't indicate 0 for a permanent mute.
    int timeleft;
}



public void OnPluginStart()
{
    // return Plugin_Handled to prevent indication, but fire post forward.
    // return Plugin_Stop to prevent indication, and don't fire post forward.
    // variable realtime is true if client was muted while talking, false if they started talking while already muted.
    // Edit the message at normal priority unless you're trying to be faster than another plugin ( lower priority ) or be slower than another plugin ( higher priority )
    // public Action OnMuteIndicate(int client, bool realtime, ArrayList messages)
    g_fwIndicate = CreateGlobalForward("OnMuteIndicate", ET_Event, Param_Cell, Param_Cell, Param_Cell);

    // messageSent decides if a message was sent by MutedIndicator.
    // public void OnMuteIndicate_Post(int client, bool realtime, bool messageSent, const char[] message)
    g_fwIndicatePost = CreateGlobalForward("OnMuteIndicate_Post", ET_Ignore, Param_Cell, Param_Cell, Param_Cell, Param_String);

    AutoExecConfig_SetFile("MutedIndicator");
    
    hcv_Enabled = UC_CreateConVar("mute_indicator_enabled", "1", "Enable mute indicator plugin?");

    AutoExecConfig_ExecuteFile();

    AutoExecConfig_CleanFile();
}

public void OnMapStart()
{
    for(int i=0;i < sizeof(g_bSpeaking);i++)
    {
        g_bSpeaking[i] = false;
        g_bLastState[i] = false;
    }
}

public void OnClientConnected(int client)
{
    g_bSpeaking[client] = false;
    g_bLastState[client] = false;
}

public void OnClientDisconnect(int client)
{
    g_bSpeaking[client] = false;
    g_bLastState[client] = false;
}

public void OnClientSpeakingEnd(int client)
{
    if(g_bSpeaking[client])
    {
        g_bSpeaking[client] = false;
    }
}

public void OnClientSpeaking(int client)
{
    bool lastState = g_bLastState[client];

    g_bLastState[client] = BaseComm_IsClientMuted(client) || GetClientListeningFlags(client) & VOICE_MUTED;

    // Player is speaking while he just got muted.
    if(g_bLastState[client] != lastState && !lastState)
    {
        g_bSpeaking[client] = true;
        MakeIndication(client, true);
    }
    else if(!g_bSpeaking[client])
    {
        g_bSpeaking[client] = true;

        if((BaseComm_IsClientMuted(client) || GetClientListeningFlags(client) & VOICE_MUTED) && GetConVarBool(hcv_Enabled))
        {
        MakeIndication(client, false);
        }
    }
}

stock void MakeIndication(int client, bool realtime)
{
    Call_StartForward(g_fwIndicate);

    ArrayList messages = new ArrayList(sizeof(g_message));
    g_message msg;

    msg.timeleft = -5;
    msg.message = DEFAULT_MUTE_MESSAGE;
    messages.PushArray(msg);

    Call_PushCell(client);
    Call_PushCell(realtime);

    ArrayList CLmessages = view_as<ArrayList>(CloneArray(messages));

    Call_PushCell(CLmessages);

    Action rtn;
    Call_Finish(rtn);

    if(rtn == Plugin_Stop)
        return;

    // Did our priority request get deleted?
    else if(CLmessages.Length == 0)
        return;

    bool messageSent = false;

    if(rtn != Plugin_Handled)
        messageSent = true;

    SortADTArrayCustom(CLmessages, sortADT_MuteTime);

    g_message winnerMsg;
    CLmessages.GetArray(0, winnerMsg); 

    if(messageSent)
    {
        PrintCenterText(client, winnerMsg.message);
    }

    Call_StartForward(g_fwIndicatePost);

    Call_PushCell(client);
    Call_PushCell(realtime);
    Call_PushCell(messageSent);
    Call_PushString(winnerMsg.message);
    
    Call_Finish();

    delete messages;
    delete CLmessages;
}

// 0 is better than everything
// 1 is better than 2, 2 is better than 3, ...
// -1 is WORSE than -2, -2 is WORSE than -3 ( even if -2 is smaller than -1, it's still better by my priority system )

public int sortADT_MuteTime(int index1, int index2, Handle array, Handle hndl)
{
    g_message msg1;
    g_message msg2;

    GetArrayArray(array, index1, msg1);
    GetArrayArray(array, index2, msg2);

    if(msg1.timeleft == msg2.timeleft)
        return 0;

    else if(msg1.timeleft == 0)
        return -1;

    else if(msg2.timeleft == 0)
        return 1;

    else if(msg1.timeleft > msg2.timeleft)
    {
        return -1;
    }

    else
    {
        return 1;
    }
}
stock ConVar UC_CreateConVar(const char[] name, const char[] defaultValue, const char[] description = "", int flags = 0, bool hasMin = false, float min = 0.0, bool hasMax = false, float max = 0.0)
{
    ConVar hndl = AutoExecConfig_CreateConVar(name, defaultValue, description, flags, hasMin, min, hasMax, max);

    if (flags & FCVAR_PROTECTED)
        ServerCommand("sm_cvar protect %s", name);

    return hndl;
}