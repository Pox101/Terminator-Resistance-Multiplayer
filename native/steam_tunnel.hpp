#pragma once
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <winsock2.h>
#include <ws2tcpip.h>
#include <cstdint>
#include <cstring>
#include <string>
#include <vector>
#include <algorithm>
#include "../third_party/gamenetworkingsockets/include/steam/isteamnetworkingsockets.h"

// UDP stays on loopback. This layer never parses or executes a game RPC.
// Internet callers must authenticate/authorize the Steam connection separately.
namespace trmp {
constexpr size_t DatagramLimit=4096, HeaderSize=16;
constexpr const char* NetworkBuild="0.6.0-alpha.1";
inline uint32_t read32(const uint8_t* p){return uint32_t(p[0])<<24|uint32_t(p[1])<<16|uint32_t(p[2])<<8|p[3];}
inline void write32(uint8_t* p,uint32_t v){p[0]=uint8_t(v>>24);p[1]=uint8_t(v>>16);p[2]=uint8_t(v>>8);p[3]=uint8_t(v);}
struct Frame {uint8_t kind=0,role=0;uint32_t epoch=0;const uint8_t* payload=nullptr;size_t length=0;};
inline bool decode(const uint8_t* p,size_t n,Frame& f){
 if(n<HeaderSize||n>HeaderSize+DatagramLimit||memcmp(p,"TRN1",4)||p[6]||p[7])return false;
 if((p[4]!=1&&p[4]!=2)||(p[5]!=1&&p[5]!=2)||read32(p+12)!=n-HeaderSize)return false;
 f={p[4],p[5],read32(p+8),p+HeaderSize,n-HeaderSize};
 return f.kind==1?(f.length>0&&f.length<=256):(f.epoch>0&&f.length>0);
}
inline std::vector<uint8_t> encode(uint8_t kind,bool host,uint32_t epoch,const void* payload,size_t n){
 if(!n||n>DatagramLimit)return {};
 std::vector<uint8_t> out(HeaderSize+n);memcpy(out.data(),"TRN1",4);out[4]=kind;out[5]=host?1:2;
 write32(out.data()+8,epoch);write32(out.data()+12,uint32_t(n));memcpy(out.data()+HeaderSize,payload,n);return out;
}
inline bool fingerprint(const std::string& value){return value.size()==64&&std::all_of(value.begin(),value.end(),[](char c){return c>='0'&&c<='9'||c>='a'&&c<='f';});}
inline bool relaySafe(const SteamNetConnectionInfo_t& info){
 return info.m_identityRemote.GetSteamID64()!=0 &&
   (info.m_nFlags&k_nSteamNetworkConnectionInfoFlags_Relayed)!=0 &&
   (info.m_nFlags&(k_nSteamNetworkConnectionInfoFlags_Unauthenticated|k_nSteamNetworkConnectionInfoFlags_Unencrypted))==0;
}
struct Wire {
 virtual bool send(const void*,size_t,bool reliable)=0;
 // Returns 0 for no message, -1 for discarded oversized data.
 virtual int receive(uint8_t*,size_t)=0;
 virtual ~Wire()=default;
};
struct SteamWire:Wire {
 ISteamNetworkingSockets* api;HSteamNetConnection connection;
 SteamWire(ISteamNetworkingSockets* a,HSteamNetConnection c):api(a),connection(c){}
 bool send(const void* p,size_t n,bool reliable)override{
  return api->SendMessageToConnection(connection,p,uint32_t(n),reliable?k_nSteamNetworkingSend_Reliable:k_nSteamNetworkingSend_UnreliableNoNagle,nullptr)==k_EResultOK;
 }
 int receive(uint8_t* out,size_t capacity)override{
  SteamNetworkingMessage_t* message=nullptr;
  if(api->ReceiveMessagesOnConnection(connection,&message,1)<=0||!message)return 0;
  int length=message->m_cbSize;
  if(length>0&&size_t(length)<=capacity)memcpy(out,message->m_pData,length);else length=-1;
  message->Release();return length;
 }
};
// One peer only. poll() runs on the game thread; no Lua/Unreal calls or worker
// callbacks occur here. Work/size/rate limits bound a hostile invited peer.
class Tunnel {
 Wire& wire;bool host;SOCKET udp=INVALID_SOCKET;sockaddr_in client{};
 bool pinned=false,helloSent=false,helloReceived=false,ready=false;
 uint32_t epoch=0;std::string greeting;
 uint64_t rateAt=0;unsigned ratePackets=0;size_t rateBytes=0;
 bool openUdp(){
  if(udp!=INVALID_SOCKET)closesocket(udp);pinned=false;client={};
  udp=socket(AF_INET,SOCK_DGRAM,IPPROTO_UDP);if(udp==INVALID_SOCKET)return false;
  BOOL exclusive=TRUE;setsockopt(udp,SOL_SOCKET,SO_EXCLUSIVEADDRUSE,(const char*)&exclusive,sizeof(exclusive));
  sockaddr_in address{};address.sin_family=AF_INET;address.sin_addr.s_addr=htonl(INADDR_LOOPBACK);address.sin_port=htons(host?0:7778);
  if(bind(udp,(sockaddr*)&address,sizeof(address))==SOCKET_ERROR)return false;
  u_long nonblocking=1;if(ioctlsocket(udp,FIONBIO,&nonblocking))return false;
  if(host){address.sin_port=htons(7777);if(connect(udp,(sockaddr*)&address,sizeof(address))==SOCKET_ERROR)return false;}
  return true;
 }
 bool rate(size_t n){
  auto now=GetTickCount64();if(now-rateAt>=1000){rateAt=now;ratePackets=0;rateBytes=0;}
  if(++ratePackets>2048||(rateBytes+=n)>2*1024*1024){++dropped;return false;}return true;
 }
public:
 bool failed=false;uint64_t sent=0,received=0,dropped=0;
 Tunnel(Wire& w,bool server,const std::string& content,uint64_t lobby):wire(w),host(server){
  if(!fingerprint(content)){failed=true;return;}
  greeting=std::string("TRMP_NET1|")+NetworkBuild+"|"+content+"|"+std::to_string(lobby);
  failed=!openUdp();
 }
 ~Tunnel(){if(udp!=INVALID_SOCKET)closesocket(udp);}
 Tunnel(const Tunnel&)=delete;Tunnel& operator=(const Tunnel&)=delete;
 bool handshaken()const{return helloSent&&helloReceived&&!failed;}
 void session(uint32_t generation,bool running){
  // A fresh socket drops old queued UDP and the previous engine endpoint.
  if(generation!=epoch){epoch=generation;if(!openUdp())failed=true;}
  ready=running&&generation>0;
 }
 void poll(){
  if(failed)return;
  if(!helloSent){auto h=encode(1,host,0,greeting.data(),greeting.size());helloSent=wire.send(h.data(),h.size(),true);}
  uint8_t bytes[HeaderSize+DatagramLimit];
  for(unsigned count=0;count<128;++count){
   int n=wire.receive(bytes,sizeof(bytes));if(!n)break;
   if(n<0||!rate(size_t(n))){++dropped;continue;}
   Frame f;if(!decode(bytes,size_t(n),f)||f.role==(host?1:2)){++dropped;continue;}
   if(f.kind==1){
    if(f.length!=greeting.size()||memcmp(f.payload,greeting.data(),f.length)){failed=true;return;}
    helloReceived=true;continue;
   }
   if(!handshaken()||!ready||f.epoch!=epoch||(!host&&!pinned)){++dropped;continue;}
   int result=host?::send(udp,(const char*)f.payload,int(f.length),0):sendto(udp,(const char*)f.payload,int(f.length),0,(sockaddr*)&client,sizeof(client));
   if(result==int(f.length))++received;else ++dropped;
  }
  // Drain even while loading so old world datagrams cannot enter a new epoch.
  for(unsigned count=0;count<128;++count){
   sockaddr_in source{};int length=sizeof(source);
   int n=recvfrom(udp,(char*)bytes,DatagramLimit+1,0,(sockaddr*)&source,&length);
   if(n==SOCKET_ERROR){if(WSAGetLastError()==WSAEMSGSIZE){++dropped;continue;}break;}
   if(n<=0||size_t(n)>DatagramLimit||!handshaken()||!ready){++dropped;continue;}
   if(!host){
    if(source.sin_addr.s_addr!=htonl(INADDR_LOOPBACK)){++dropped;continue;}
    if(pinned&&(source.sin_port!=client.sin_port||source.sin_addr.s_addr!=client.sin_addr.s_addr)){++dropped;continue;}
    if(!pinned){client=source;pinned=true;}
   }
   auto packet=encode(2,host,epoch,bytes,size_t(n));
   if(wire.send(packet.data(),packet.size(),false))++sent;else ++dropped;
  }
 }
};
}
