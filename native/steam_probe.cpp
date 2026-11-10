#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <cstdio>
#include <cstring>
#include "../third_party/gamenetworkingsockets/include/steam/isteamnetworkingsockets.h"
#include "../third_party/gamenetworkingsockets/include/steam/isteamnetworkingutils.h"

// Availability/local socket-pair diagnostic only. It never opens a public
// listener, creates a lobby, sends invitations, reads auth tickets, or changes
// the game's net driver. Local payload delivery does not prove Internet play.
static HMODULE selfModule;
static HSteamNetConnection pairSockets[2]={};
static ISteamNetworkingSockets* sockets=nullptr;
static bool pairStarted=false,payloadReceived=false;
static ULONGLONG pairStart=0;
template<class T> static T proc(HMODULE module,const char* name) {
    return reinterpret_cast<T>(GetProcAddress(module,name));
}
extern "C" __declspec(dllexport) int probe_steam(void*) {
    char directory[MAX_PATH];GetModuleFileNameA(selfModule,directory,MAX_PATH);
    char* slash=strrchr(directory,'\\');if(!slash)return 0;slash[1]=0;
    char output[MAX_PATH];sprintf_s(output,"%ssteam-feasibility.json",directory);
    FILE* file=nullptr;fopen_s(&file,output,"w");if(!file)return 0;
    HMODULE api=GetModuleHandleW(L"steam_api64.dll");
    if(!api) {
        char library[MAX_PATH];sprintf_s(library,"%sEngine\\Binaries\\ThirdParty\\Steamworks\\Steamv147\\Win64\\steam_api64.dll",directory);
        api=LoadLibraryExA(library,nullptr,LOAD_WITH_ALTERED_SEARCH_PATH);
    }
    bool initialized=false,loggedOn=false;unsigned appId=0;int user=0,pipe=0;
    const char* socketsVersion="";bool legacy=false;
    int relayStatus=0;bool relayAvailable=false;
    if(api) {
        auto getUser=proc<int(*)()>(api,"SteamAPI_GetHSteamUser");
        auto getPipe=proc<int(*)()>(api,"SteamAPI_GetHSteamPipe");
        auto init=proc<bool(*)()>(api,"SteamAPI_Init");
        user=getUser?getUser():0;
        initialized=user!=0;
        if(!initialized && init) initialized=init();
        user=getUser?getUser():0;pipe=getPipe?getPipe():0;
        auto find=proc<void*(*)(int,const char*)>(api,"SteamInternal_FindOrCreateUserInterface");
        if(find && user) {
            void* steamUser=find(user,"SteamUser020");
            auto logged=proc<bool(*)(void*)>(api,"SteamAPI_ISteamUser_BLoggedOn");
            if(steamUser && logged) loggedOn=logged(steamUser);
            legacy=find(user,"SteamNetworking005")!=nullptr;
            const char* versions[]={"SteamNetworkingSockets012","SteamNetworkingSockets011","SteamNetworkingSockets010","SteamNetworkingSockets009","SteamNetworkingSockets008","SteamNetworkingSockets006","SteamNetworkingSockets004"};
            for(auto version:versions) if(find(user,version)) {socketsVersion=version;break;}
            if(strcmp(socketsVersion,STEAMNETWORKINGSOCKETS_INTERFACE_VERSION)==0) {
                sockets=static_cast<ISteamNetworkingSockets*>(find(user,STEAMNETWORKINGSOCKETS_INTERFACE_VERSION));
                if(!pairStarted) {
                    pairStarted=true;pairStart=GetTickCount64();
                    if(sockets->CreateSocketPair(&pairSockets[0],&pairSockets[1],true,nullptr,nullptr)) {
                        static const char payload[]="TRMP/Steam/local-transport-probe/1";
                        sockets->SendMessageToConnection(pairSockets[0],payload,sizeof(payload),k_nSteamNetworkingSend_Reliable,nullptr);
                    }
                }
                if(pairSockets[1]) {
                    SteamNetworkingMessage_t* message=nullptr;
                    if(sockets->ReceiveMessagesOnConnection(pairSockets[1],&message,1)>0 && message) {
                        static const char expected[]="TRMP/Steam/local-transport-probe/1";
                        payloadReceived=message->m_cbSize==sizeof(expected) && memcmp(message->m_pData,expected,sizeof(expected))==0;
                        message->Release();
                    }
                    if(payloadReceived || GetTickCount64()-pairStart>10000) {
                        sockets->CloseConnection(pairSockets[0],0,"Probe complete",false);
                        sockets->CloseConnection(pairSockets[1],0,"Probe complete",false);
                        pairSockets[0]=pairSockets[1]=0;
                    }
                }
            }
            auto networkUtils=static_cast<ISteamNetworkingUtils*>(find(0,STEAMNETWORKINGUTILS_INTERFACE_VERSION));
            if(networkUtils) {
                networkUtils->InitRelayNetworkAccess();
                SteamRelayNetworkStatus_t status={};
                relayStatus=networkUtils->GetRelayNetworkStatus(&status);
                relayAvailable=relayStatus==k_ESteamNetworkingAvailability_Current;
            }
        }
        auto client=proc<void*(*)()>(api,"SteamClient");
        auto utils=proc<void*(*)(void*,int,const char*)>(api,"SteamAPI_ISteamClient_GetISteamUtils");
        auto getAppId=proc<unsigned(*)(void*)>(api,"SteamAPI_ISteamUtils_GetAppID");
        if(client && utils && getAppId && pipe) {
            void* u=utils(client(),pipe,"SteamUtils009");
            if(u) appId=getAppId(u);
        }
    }
    fprintf(file,"{\"apiLoaded\":%s,\"initialized\":%s,\"loggedOn\":%s,\"appId\":%u,\"legacyNetworkingAvailable\":%s,\"socketsInterface\":\"%s\",\"localTransportPayloadReceived\":%s,\"relayAvailability\":%d,\"relayAvailable\":%s,\"internetConnectionTested\":false,\"relayPrivacyVerified\":false}\n",
        api?"true":"false",initialized?"true":"false",loggedOn?"true":"false",appId,legacy?"true":"false",socketsVersion,payloadReceived?"true":"false",relayStatus,relayAvailable?"true":"false");
    fclose(file);return 0;
}
BOOL WINAPI DllMain(HINSTANCE instance,DWORD reason,LPVOID) {
    if(reason==DLL_PROCESS_ATTACH) {selfModule=instance;DisableThreadLibraryCalls(instance);}return TRUE;
}
