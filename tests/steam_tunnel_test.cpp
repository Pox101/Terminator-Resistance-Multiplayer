#include "../native/steam_tunnel.hpp"
#include <deque>
#include <cassert>
#include <cstdio>
struct FakeWire:trmp::Wire{
 std::deque<std::vector<uint8_t>> input;FakeWire* peer=nullptr;
 bool send(const void* p,size_t n,bool)override{peer->input.emplace_back((const uint8_t*)p,(const uint8_t*)p+n);return true;}
 int receive(uint8_t* p,size_t capacity)override{if(input.empty())return 0;auto b=std::move(input.front());input.pop_front();if(b.size()>capacity)return -1;memcpy(p,b.data(),b.size());return int(b.size());}
};
static sockaddr_in loopback(unsigned port){sockaddr_in a{};a.sin_family=AF_INET;a.sin_addr.s_addr=htonl(INADDR_LOOPBACK);a.sin_port=htons((u_short)port);return a;}
static SOCKET endpoint(unsigned port){SOCKET s=socket(AF_INET,SOCK_DGRAM,IPPROTO_UDP);assert(s!=INVALID_SOCKET);auto a=loopback(port);assert(!bind(s,(sockaddr*)&a,sizeof(a)));u_long nonblocking=1;ioctlsocket(s,FIONBIO,&nonblocking);return s;}
int main(){
 WSADATA ws{};assert(WSAStartup(MAKEWORD(2,2),&ws)==0);
 trmp::Frame frame{};const char data[]="UE packet";auto good=trmp::encode(2,true,1,data,sizeof(data));
 assert(trmp::decode(good.data(),good.size(),frame)&&frame.epoch==1);
 for(auto kind:{0,3,255}){auto b=good;b[4]=(uint8_t)kind;assert(!trmp::decode(b.data(),b.size(),frame));}
 auto bad=good;bad[6]=1;assert(!trmp::decode(bad.data(),bad.size(),frame));
 bad=good;bad[12]=1;assert(!trmp::decode(bad.data(),bad.size(),frame));
 assert(!trmp::decode(good.data(),15,frame));assert(!trmp::fingerprint("not-a-hash"));
 SteamNetConnectionInfo_t info{};info.m_identityRemote.SetSteamID64(76561198000000001ULL);info.m_nFlags=k_nSteamNetworkConnectionInfoFlags_Relayed;
 assert(trmp::relaySafe(info));info.m_nFlags|=k_nSteamNetworkConnectionInfoFlags_Unencrypted;assert(!trmp::relaySafe(info));
 info.m_nFlags=k_nSteamNetworkConnectionInfoFlags_Relayed|k_nSteamNetworkConnectionInfoFlags_Unauthenticated;assert(!trmp::relaySafe(info));
 info.m_nFlags=0;assert(!trmp::relaySafe(info));
 {
  FakeWire a,b;a.peer=&b;b.peer=&a;
  SOCKET server=endpoint(7777),client=endpoint(0);auto proxy=loopback(7778);
  trmp::Tunnel host(a,true,std::string(64,'a'),123),guest(b,false,std::string(64,'a'),123);
  assert(!host.failed&&!guest.failed);host.session(1,true);guest.session(1,true);
  host.poll();guest.poll();host.poll();assert(host.handshaken()&&guest.handshaken());
  assert(sendto(client,data,sizeof(data),0,(sockaddr*)&proxy,sizeof(proxy))==sizeof(data));guest.poll();host.poll();
  char bytes[128]{};sockaddr_in from{};int length=sizeof(from);
  assert(recvfrom(server,bytes,sizeof(bytes),0,(sockaddr*)&from,&length)==sizeof(data));assert(!memcmp(bytes,data,sizeof(data)));
  assert(sendto(server,data,sizeof(data),0,(sockaddr*)&from,sizeof(from))==sizeof(data));host.poll();guest.poll();
  assert(recv(client,bytes,sizeof(bytes),0)==sizeof(data));assert(!memcmp(bytes,data,sizeof(data)));
  auto stale=trmp::encode(2,false,1,data,sizeof(data));host.session(2,true);guest.session(2,true);a.input.push_back(stale);host.poll();
  assert(recv(server,bytes,sizeof(bytes),0)==SOCKET_ERROR);assert(host.dropped>0);
  SOCKET second=endpoint(0);sendto(second,data,sizeof(data),0,(sockaddr*)&proxy,sizeof(proxy));guest.poll();host.poll();
  length=sizeof(from);assert(recvfrom(server,bytes,sizeof(bytes),0,(sockaddr*)&from,&length)==sizeof(data));
  sendto(server,data,sizeof(data),0,(sockaddr*)&from,sizeof(from));host.poll();guest.poll();assert(recv(second,bytes,sizeof(bytes),0)==sizeof(data));
  // The previous game socket cannot replace the pinned new game endpoint.
  sendto(client,data,sizeof(data),0,(sockaddr*)&proxy,sizeof(proxy));guest.poll();host.poll();assert(recv(server,bytes,sizeof(bytes),0)==SOCKET_ERROR);
  closesocket(second);closesocket(client);closesocket(server);
 }
 {
  FakeWire a,b;a.peer=&b;b.peer=&a;
  trmp::Tunnel host(a,true,std::string(64,'a'),123),guest(b,false,std::string(64,'b'),123);
  host.poll();guest.poll();assert(guest.failed);
 }
 WSACleanup();puts("PASS: bounded tunnel codec, authenticated relay flags, bidirectional loopback UDP, version/content handshake, stale generations and endpoint pinning");
}
