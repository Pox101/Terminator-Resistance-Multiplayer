#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <cstdint>
#include <cstdio>
#include <cstring>

// Uses the installed game's Steam API. Opening the invite dialog does not
// send invitations. The user chooses recipients in Steam's own overlay.
// Lobby membership is not a game transport; the current game driver remains
// loopback-only until a separately validated Steam transport is implemented.
namespace {
HMODULE selfModule,api;
char directory[MAX_PATH];
void *friends=nullptr,*matchmaking=nullptr,*utils=nullptr;
uint64_t lobby=0,creation=0;
bool invitePending=false,cancelPending=false;
unsigned members=0;
const char* state="idle";
int error=0;
template<class T>T symbol(const char* name){return reinterpret_cast<T>(GetProcAddress(api,name));}
using Init=bool(*)();
using GetUser=int(*)();
using FindInterface=void*(*)(int,const char*);
using Create=uint64_t(*)(void*,int,int);
using Completed=bool(*)(void*,uint64_t,bool*);
using Result=bool(*)(void*,uint64_t,void*,int,int,bool*);
using Leave=void(*)(void*,uint64_t);
using SetData=bool(*)(void*,uint64_t,const char*,const char*);
using GetMembers=int(*)(void*,uint64_t);
using Overlay=void(*)(void*,uint64_t);
using Enabled=bool(*)(void*);
Create createLobby;
Completed completed;
Result result;
Leave leaveLobby;
SetData setData;
GetMembers getMembers;
Overlay overlay;
Enabled overlayEnabled;

void writeState(){
 char path[MAX_PATH];sprintf_s(path,"%ssteam-lobby-state.txt",directory);
 FILE* f=nullptr;fopen_s(&f,path,"w");
 if(f){fprintf(f,"TRMP_LOBBY1|%s|%d|%u|%llu|0\n",state,error,members,(unsigned long long)lobby);fclose(f);}
}
bool initialize(){
 if(matchmaking)return true;
 GetModuleFileNameA(selfModule,directory,MAX_PATH);
 char* slash=strrchr(directory,'\\');if(!slash)return false;slash[1]=0;
 api=GetModuleHandleW(L"steam_api64.dll");
 if(!api){
  char path[MAX_PATH];sprintf_s(path,"%sEngine\\Binaries\\ThirdParty\\Steamworks\\Steamv147\\Win64\\steam_api64.dll",directory);
  api=LoadLibraryExA(path,nullptr,LOAD_WITH_ALTERED_SEARCH_PATH);
 }
 if(!api){state="steam_unavailable";error=1;writeState();return false;}
 auto user=symbol<GetUser>("SteamAPI_GetHSteamUser");auto init=symbol<Init>("SteamAPI_Init");
 if(!user || (!user() && (!init || !init()))){state="steam_unavailable";error=2;writeState();return false;}
 auto find=symbol<FindInterface>("SteamInternal_FindOrCreateUserInterface");
 if(!find){state="unsupported_api";error=3;writeState();return false;}
 friends=find(user(),"SteamFriends017");utils=find(0,"SteamUtils009");
 void* candidate=find(user(),"SteamMatchMaking009");
 createLobby=symbol<Create>("SteamAPI_ISteamMatchmaking_CreateLobby");
 completed=symbol<Completed>("SteamAPI_ISteamUtils_IsAPICallCompleted");
 result=symbol<Result>("SteamAPI_ISteamUtils_GetAPICallResult");
 leaveLobby=symbol<Leave>("SteamAPI_ISteamMatchmaking_LeaveLobby");
 setData=symbol<SetData>("SteamAPI_ISteamMatchmaking_SetLobbyData");
 getMembers=symbol<GetMembers>("SteamAPI_ISteamMatchmaking_GetNumLobbyMembers");
 overlay=symbol<Overlay>("SteamAPI_ISteamFriends_ActivateGameOverlayInviteDialog");
 overlayEnabled=symbol<Enabled>("SteamAPI_ISteamUtils_IsOverlayEnabled");
 if(!friends || !utils || !candidate || !createLobby || !completed || !result || !leaveLobby || !setData || !getMembers || !overlay || !overlayEnabled){
  state="unsupported_api";error=4;writeState();return false;
 }
 auto appId=symbol<unsigned(*)(void*)>("SteamAPI_ISteamUtils_GetAppID");
 if(!appId || appId(utils)!=954740){state="unsupported_api";error=9;writeState();return false;}
 matchmaking=candidate;return true;
}
void openInvite(){
 if(!lobby)return;
 if(!overlayEnabled(utils)){state="overlay_unavailable";error=5;writeState();return;}
 overlay(friends,lobby);state="lobby_ready";error=0;invitePending=false;writeState();
}
}
extern "C" __declspec(dllexport) int lobby_create(void*){
 if(!initialize())return 0;
 invitePending=true;
 cancelPending=false;
 if(lobby){openInvite();return 0;}
 if(creation)return 0;
 // k_ELobbyTypePrivate=0; two total members for the current 1v1 prototype.
 creation=createLobby(matchmaking,0,2);state=creation?"creating":"create_failed";error=creation?0:6;
 writeState();return 0;
}
extern "C" __declspec(dllexport) int lobby_poll(void*){
 if(!matchmaking)return 0;
 if(creation){
  bool failed=false;
  if(completed(utils,creation,&failed)){
   struct LobbyCreated {int result;uint32_t padding;uint64_t id;} response{};
   static_assert(sizeof(response)==16,"LobbyCreated ABI");
   // LobbyCreated_t callback ID=513 in the Steamworks matchmaking ABI.
   bool received=!failed && result(utils,creation,&response,sizeof(response),513,&failed);creation=0;
   if(received && !failed && response.result==1 && response.id && cancelPending){
    leaveLobby(matchmaking,response.id);state="idle";error=0;cancelPending=false;
   }else if(received && !failed && response.result==1 && response.id){
    lobby=response.id;members=1;
    bool tagged=setData(matchmaking,lobby,"trmp_mod","resistance-multiplayer") &&
       setData(matchmaking,lobby,"trmp_protocol","TRMP1") &&
       setData(matchmaking,lobby,"trmp_mode","infiltrator-versus") &&
       setData(matchmaking,lobby,"trmp_transport","unavailable");
    if(tagged){state="lobby_ready";error=0;}
    else {leaveLobby(matchmaking,lobby);lobby=0;state="create_failed";error=7;invitePending=false;}
   }else {state="create_failed";error=received?response.result:8;invitePending=false;}
  }
 }
 if(lobby){members=(unsigned)getMembers(matchmaking,lobby);if(invitePending)openInvite();}
 writeState();return 0;
}
extern "C" __declspec(dllexport) int lobby_invite(void*){if(initialize()){invitePending=true;if(lobby)openInvite();}return 0;}
extern "C" __declspec(dllexport) int lobby_leave(void*){
 if(lobby && matchmaking)leaveLobby(matchmaking,lobby);
 lobby=0;members=0;invitePending=false;state="idle";error=0;
 cancelPending=creation!=0;
 // A pending CreateLobby must still be collected, then left, before starting
 // another request. Keep the handle; cancel intent is recorded separately.
 writeState();return 0;
}
BOOL WINAPI DllMain(HINSTANCE instance,DWORD reason,LPVOID){
 if(reason==DLL_PROCESS_ATTACH){selfModule=instance;DisableThreadLibraryCalls(instance);}return TRUE;
}
