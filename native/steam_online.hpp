// Implementation included by steam_lobby.cpp after its flat-API declarations.
// No UE4SS/Lua ABI or Unreal object is used by Steam callbacks.
#pragma once
#include <memory>
#include <cstdlib>
#include <ctime>
#include "../third_party/gamenetworkingsockets/include/steam/isteamnetworkingutils.h"
namespace online {
bool enabled=false,configured=false,wsaReady=false,localTest=false;
void* steamUser=nullptr;
ISteamNetworkingSockets* network=nullptr;
ISteamNetworkingUtils* networkUtils=nullptr;
uint64_t selfId=0,ownerId=0,expectedPeer=0,invited=0,joiningRoom=0,joinCall=0;
ULONGLONG joinStarted=0;bool cancelJoin=false;
HSteamListenSocket listener=0;HSteamNetConnection connection=0,secondConnection=0;
std::unique_ptr<trmp::SteamWire> wire,secondWire;
std::unique_ptr<trmp::Tunnel> tunnel,secondTunnel;
std::string content,lastSession;
bool ready(){return enabled&&!localTest&&tunnel&&tunnel->handshaken();}
using Join=uint64_t(*)(void*,uint64_t);
using GetData=const char*(*)(void*,uint64_t,const char*);
using Owner=uint64_t(*)(void*,uint64_t);
using Member=uint64_t(*)(void*,uint64_t,int);
Join joinLobby=nullptr;GetData getData=nullptr;Owner getOwner=nullptr;Member getMember=nullptr;
void(*runCallbacks)()=nullptr;
void writeFile(const char* name,const std::string& text){
 char path[MAX_PATH],temp[MAX_PATH];sprintf_s(path,"%s%s",directory,name);sprintf_s(temp,"%s%s.tmp",directory,name);
 FILE* f=nullptr;fopen_s(&f,temp,"wb");if(!f)return;fwrite(text.data(),1,text.size(),f);fclose(f);MoveFileExA(temp,path,MOVEFILE_REPLACE_EXISTING);
}
std::string readFile(const char* name,size_t limit=160){
 char path[MAX_PATH];sprintf_s(path,"%s%s",directory,name);FILE* f=nullptr;fopen_s(&f,path,"rb");if(!f)return {};
 std::string text(limit+1,'\0');size_t n=fread(text.data(),1,text.size(),f);fclose(f);if(n>limit)return {};text.resize(n);
 while(!text.empty()&&(text.back()=='\r'||text.back()=='\n'))text.pop_back();return text;
}
bool validRoom(uint64_t id){return (id>>56)==1&&((id>>52)&15)==8&&((id>>32)&0x40000)!=0&&uint32_t(id)!=0;}
bool memberAllowed(uint64_t id){
 if(!id||id==selfId||!lobby||!getMember)return false;
 int n=getMembers(matchmaking,lobby);if(n<1||n>2)return false;
 for(int i=0;i<n;++i)if(getMember(matchmaking,lobby,i)==id)return true;return false;
}
void clearTransport(){
 tunnel.reset();secondTunnel.reset();wire.reset();secondWire.reset();
 if(network&&connection)network->CloseConnection(connection,1000,"Party closed",false);connection=0;
 if(network&&secondConnection)network->CloseConnection(secondConnection,1000,"Local test closed",false);secondConnection=0;
 if(network&&listener)network->CloseListenSocket(listener);listener=0;
 expectedPeer=0;lastSession.clear();localTest=false;
}
void failure(const char* value,int code){clearTransport();state=value;error=code;}
void connectionChanged(SteamNetConnectionStatusChangedCallback_t* change){
 if(!enabled||!network)return;
 const auto& info=change->m_info;auto id=info.m_identityRemote.GetSteamID64();
 if(info.m_eState==k_ESteamNetworkingConnectionState_Connecting&&info.m_hListenSocket==listener){
  if(!listener||connection||ownerId!=selfId||!memberAllowed(id)){network->CloseConnection(change->m_hConn,1001,"Not an invited party member",false);return;}
  // Steam may update membership while dispatching callbacks, after poll's
  // snapshot. Authorize against the current lobby, then pin that identity.
  expectedPeer=id;connection=change->m_hConn;
  if(network->AcceptConnection(connection)!=k_EResultOK)failure("transport_failed",30);
 }else if(change->m_hConn==connection&&(info.m_eState==k_ESteamNetworkingConnectionState_ClosedByPeer||info.m_eState==k_ESteamNetworkingConnectionState_ProblemDetectedLocally)){
  failure("peer_disconnected",31);
 }
}
// Public Steam callback ABI, x64: three virtual slots, flags byte, callback ID.
// Steam owns no memory here; callbacks remain registered for process lifetime.
class InviteCallback {
public:
 virtual void Run(void* data){uint64_t id=0;memcpy(&id,data,8);if(validRoom(id)){invited=id;state="invitation_pending";error=0;}}
 virtual void Run(void* data,bool failed,uint64_t){if(!failed)Run(data);}
 virtual int GetCallbackSizeBytes(){return 16;}
 uint8_t flags=0;int callback=333;
};
static_assert(sizeof(InviteCallback)==16,"Steam callback ABI");
InviteCallback inviteCallback;
void configure(){
 if(configured)return;
 auto mode=readFile("network-mode.txt",32);if(mode!="steam"&&mode!="tunnel_test")return;
 configured=true;enabled=true;content=readFile("content-fingerprint.txt",80);
 if(!trmp::fingerprint(content)){state="incompatible";error=20;return;}
 auto user=symbol<GetUser>("SteamAPI_GetHSteamUser");auto find=symbol<FindInterface>("SteamInternal_FindOrCreateUserInterface");
 auto getSelf=symbol<uint64_t(*)(void*)>("SteamAPI_ISteamUser_GetSteamID");
 auto loggedOn=symbol<bool(*)(void*)>("SteamAPI_ISteamUser_BLoggedOn");
 joinLobby=symbol<Join>("SteamAPI_ISteamMatchmaking_JoinLobby");getData=symbol<GetData>("SteamAPI_ISteamMatchmaking_GetLobbyData");
 getOwner=symbol<Owner>("SteamAPI_ISteamMatchmaking_GetLobbyOwner");getMember=symbol<Member>("SteamAPI_ISteamMatchmaking_GetLobbyMemberByIndex");
 auto registerCallback=symbol<void(*)(void*,int)>("SteamAPI_RegisterCallback");runCallbacks=symbol<void(*)()>("SteamAPI_RunCallbacks");
 if(!user||!find||!getSelf||!loggedOn||!joinLobby||!getData||!getOwner||!getMember||!registerCallback||!runCallbacks){state="unsupported_api";error=21;return;}
 steamUser=find(user(),"SteamUser020");
 network=(ISteamNetworkingSockets*)find(user(),STEAMNETWORKINGSOCKETS_INTERFACE_VERSION);
 networkUtils=(ISteamNetworkingUtils*)find(0,STEAMNETWORKINGUTILS_INTERFACE_VERSION);
 if(!steamUser||!loggedOn(steamUser)||!network||!networkUtils){state="steam_unavailable";error=22;return;}
 selfId=getSelf(steamUser);WSADATA ws{};wsaReady=WSAStartup(MAKEWORD(2,2),&ws)==0;
 if(!selfId||!wsaReady){state="transport_failed";error=23;network=nullptr;return;}
 registerCallback(&inviteCallback,333);network->InitAuthentication();networkUtils->InitRelayNetworkAccess();
 auto requested=readFile("steam-invite.txt",24);
 if(!requested.empty()&&requested.find_first_not_of("0123456789")==std::string::npos){char* end=nullptr;auto id=_strtoui64(requested.c_str(),&end,10);if(end&&!*end&&validRoom(id)){invited=id;state="invitation_pending";}}
}
int options(SteamNetworkingConfigValue_t* out){
 out[0].SetInt32(k_ESteamNetworkingConfig_P2P_Transport_ICE_Enable,0);
 out[1].SetInt32(k_ESteamNetworkingConfig_Unencrypted,0);
 out[2].SetPtr(k_ESteamNetworkingConfig_Callback_ConnectionStatusChanged,(void*)connectionChanged);return 3;
}
bool created(){
 if(!network||!trmp::fingerprint(content))return false;
 ownerId=selfId;SteamNetworkingConfigValue_t opts[3];
 writeFile("steam-role.txt","host\n");
 listener=network->CreateListenSocketP2P(17,options(opts),opts);
 if(!listener){state="transport_failed";error=24;return false;}
 return setData(matchmaking,lobby,"trmp_build",trmp::NetworkBuild)&&setData(matchmaking,lobby,"trmp_content",content.c_str());
}
void accept(){
 if(!enabled||!network||!invited||joinCall)return;
 if(creation){cancelPending=true;invitePending=false;return;}
 clearTransport();if(lobby)leaveLobby(matchmaking,lobby);lobby=0;members=0;
 joiningRoom=invited;invited=0;cancelJoin=false;joinStarted=GetTickCount64();joinCall=joinLobby(matchmaking,joiningRoom);
 state=joinCall?"joining":"join_failed";error=joinCall?0:25;
}
void cancel(){invited=0;cancelJoin=joinCall!=0;clearTransport();ownerId=0;}
bool compatible(){
 return !strcmp(getData(matchmaking,lobby,"trmp_mod"),"resistance-multiplayer")&&
 !strcmp(getData(matchmaking,lobby,"trmp_protocol"),"TRMP1")&&
 !strcmp(getData(matchmaking,lobby,"trmp_mode"),"infiltrator-versus")&&
 !strcmp(getData(matchmaking,lobby,"trmp_transport"),"steam-sdr-udp1")&&
 !strcmp(getData(matchmaking,lobby,"trmp_build"),trmp::NetworkBuild)&&
 content==getData(matchmaking,lobby,"trmp_content");
}
bool sessionValue(const std::string& text,uint32_t& epoch,bool& ready){
 // The full phase/run/timestamp grammar is checked again by the Lua provider.
 if(text.size()>160||text.rfind("TRMP_SESSION1|",0))return false;
 size_t start=text.find('|',14);if(start==std::string::npos)return false;
 auto run=text.substr(14,start-14);auto colon=run.find(':');
 if(run.size()>32||colon==std::string::npos||!colon||colon==run.size()-1||run.find(':',colon+1)!=std::string::npos)return false;
 auto first=run.substr(0,colon),second=run.substr(colon+1);
 if(first.find_first_not_of("0123456789")!=std::string::npos||second.find_first_not_of("0123456789")!=std::string::npos)return false;
 size_t stop=text.find('|',start+1);if(stop==std::string::npos||stop==start+1)return false;
 auto number=text.substr(start+1,stop-start-1);if(number.size()>10||number.find_first_not_of("0123456789")!=std::string::npos)return false;
 auto n=strtoull(number.c_str(),nullptr,10);if(n>2147483647)return false;epoch=uint32_t(n);
 start=stop+1;stop=text.find('|',start);if(stop==std::string::npos)return false;
 auto phase=text.substr(start,stop-start);if(phase!="ready"&&phase!="menu"&&phase!="starting"&&phase!="loading"&&phase!="restarting")return false;
 auto stamp=text.substr(stop+1);if(stamp.empty()||stamp.size()>10||stamp.find_first_not_of("0123456789")!=std::string::npos)return false;
 auto now=uint64_t(time(nullptr)),then=strtoull(stamp.c_str(),nullptr,10);
 if(then>now+10||now>then+300)return false;ready=phase=="ready"&&now<=then+30;return true;
}
void applySession(const std::string& text){uint32_t epoch=0;bool ready=false;if(!sessionValue(text,epoch,ready))ready=false;if(tunnel)tunnel->session(epoch,ready);if(secondTunnel)secondTunnel->session(epoch,ready);}
void publish(){
 if(!enabled||!lobby||ownerId!=selfId)return;
 auto text=readFile("steam-session-out.txt");uint32_t epoch=0;bool ready=false;
 if(sessionValue(text,epoch,ready)){setData(matchmaking,lobby,"trmp_session",text.c_str());applySession(text);}
}
void frame(){
 if(tunnel&&!localTest){
  SteamNetConnectionInfo_t info{};
  if(!network||!network->GetConnectionInfo(connection,&info)||!trmp::relaySafe(info)){
   tunnel->failed=true;state="transport_failed";error=34;return;
  }
 }
 if(tunnel)tunnel->poll();if(secondTunnel)secondTunnel->poll();
}
void poll(){
 if(!enabled||!network)return;
 // Refresh membership before dispatching connection acceptance callbacks.
 if(lobby&&ownerId==selfId){expectedPeer=0;int count=getMembers(matchmaking,lobby);if(count==2)for(int i=0;i<2;++i){auto id=getMember(matchmaking,lobby,i);if(id!=selfId)expectedPeer=id;}}
 if(runCallbacks)runCallbacks();network->RunCallbacks();
 {
  SteamNetConnectionInfo_t info{};bool connected=connection&&network->GetConnectionInfo(connection,&info);
  char diagnostic[160];sprintf_s(diagnostic,"TRMP_STEAM1|%d|%d|%d|%d|%d|%d\n",
   int(network->GetAuthenticationStatus(nullptr)),int(networkUtils->GetRelayNetworkStatus(nullptr)),listener?1:0,
   connected?int(info.m_eState):0,connected&&trmp::relaySafe(info)?1:0,ready()?1:0);
  // Numeric availability/connection flags only: no identities or addresses.
  writeFile("steam-network-state.txt",diagnostic);
 }
 if(joinCall){
  bool failed=false;
  if(completed(utils,joinCall,&failed)){
   struct Enter{uint64_t id;uint32_t permissions;bool locked;uint8_t padding[3];uint32_t response;uint32_t tail;} entered{};
   static_assert(sizeof(Enter)==24,"LobbyEnter ABI");
   bool got=!failed&&result(utils,joinCall,&entered,sizeof(entered),504,&failed);joinCall=0;
   if(got&&!failed&&entered.response==1&&entered.id==joiningRoom){
    if(cancelJoin){leaveLobby(matchmaking,entered.id);state="idle";}
    else{
     lobby=entered.id;members=getMembers(matchmaking,lobby);ownerId=getOwner(matchmaking,lobby);
     if(ownerId==selfId||!ownerId||members>2||!compatible()){leaveLobby(matchmaking,lobby);lobby=0;state="incompatible";error=26;}
     else{
      expectedPeer=ownerId;SteamNetworkingIdentity identity{};identity.SetSteamID64(ownerId);SteamNetworkingConfigValue_t opts[3];
      connection=network->ConnectP2P(identity,17,options(opts),opts);
      state=connection?"transport_connecting":"transport_failed";error=connection?0:27;
      writeFile("steam-role.txt","client\n");
     }
    }
   }else{state="join_failed";error=got?int(entered.response):28;}
  }else if(GetTickCount64()-joinStarted>45000){cancelJoin=true;state="join_failed";error=29;}
 }
 if(localTest){
  applySession(readFile("../trmp-session.txt"));
  char stats[160];sprintf_s(stats,"TRMP_TUNNEL1|%d|%llu|%llu|%llu|%llu\n",tunnel&&secondTunnel&&tunnel->handshaken()&&secondTunnel->handshaken()?1:0,
   (unsigned long long)(tunnel?tunnel->sent:0),(unsigned long long)(tunnel?tunnel->received:0),
   (unsigned long long)(secondTunnel?secondTunnel->sent:0),(unsigned long long)(secondTunnel?secondTunnel->received:0));
  writeFile("steam-tunnel-state.txt",stats);return;
 }
 if(!lobby)return;
 if(getOwner(matchmaking,lobby)!=ownerId){failure("owner_left",32);leaveLobby(matchmaking,lobby);lobby=0;return;}
 if(connection){
  if(!memberAllowed(expectedPeer)){failure("peer_disconnected",33);return;}
  SteamNetConnectionInfo_t info{};
  if(network->GetConnectionInfo(connection,&info)&&info.m_eState==k_ESteamNetworkingConnectionState_Connected){
   if(!trmp::relaySafe(info)||info.m_identityRemote.GetSteamID64()!=expectedPeer){failure("transport_failed",34);return;}
   if(!tunnel){wire=std::make_unique<trmp::SteamWire>(network,connection);tunnel=std::make_unique<trmp::Tunnel>(*wire,ownerId==selfId,content,lobby);}
   frame();if(tunnel->failed){failure(error==34?"transport_failed":"incompatible",error==34?34:35);return;}
   state=tunnel->handshaken()?"transport_ready":"transport_connecting";error=0;
  }
 }
 std::string session=ownerId==selfId?readFile("steam-session-out.txt"):getData(matchmaking,lobby,"trmp_session");
 if(session!=lastSession){lastSession=session;writeFile("steam-session-state.txt",session+"\n");}
 applySession(session);
 if(invited)state="invitation_pending";
}
void testTunnel(){
 configure();if(!network||!wsaReady||tunnel||connection||listener||lobby)return;
 HSteamNetConnection pair[2]{};if(!network->CreateSocketPair(pair,pair+1,true,nullptr,nullptr)){state="transport_failed";error=36;return;}
 // Developer-only local transport check: real Steam socket-pair framing and
 // loopback game UDP, deliberately not represented as an Internet/SDR test.
 localTest=true;connection=pair[0];secondConnection=pair[1];wire=std::make_unique<trmp::SteamWire>(network,pair[0]);secondWire=std::make_unique<trmp::SteamWire>(network,pair[1]);
 tunnel=std::make_unique<trmp::Tunnel>(*wire,true,content,1);secondTunnel=std::make_unique<trmp::Tunnel>(*secondWire,false,content,1);
 tunnel->session(1,true);secondTunnel->session(1,true);state="local_transport_test";
}
}
