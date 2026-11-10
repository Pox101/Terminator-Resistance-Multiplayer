// Fake Steam functions exercise lifecycle behavior without contacting Steam.
#include "../native/steam_lobby.cpp"
#include <cassert>
#include <map>
namespace {
int creates=0,invites=0,leaves=0,tags=0;
bool complete=false,enabled=true,tagged=true,ioFailure=false;
uint64_t fakeCreate(void*,int type,int count){assert(type==0 && count==2);++creates;return 42;}
bool fakeComplete(void*,uint64_t call,bool* failed){assert(call==42);*failed=ioFailure;return complete;}
bool fakeResult(void*,uint64_t,void* out,int size,int callback,bool* failed){
 assert(size==16 && callback==513);struct Response{int result;uint32_t padding;uint64_t id;} r{1,0,123};
 memcpy(out,&r,sizeof(r));*failed=ioFailure;return !ioFailure;
}
void fakeLeave(void*,uint64_t id){assert(id==123);++leaves;}
bool fakeTag(void*,uint64_t,const char* key,const char* value){++tags;if(strcmp(key,"trmp_transport")==0)assert(strcmp(value,"unavailable")==0);return tagged;}
int fakeMembers(void*,uint64_t){return 1;}
void fakeOverlay(void*,uint64_t id){assert(id==123);++invites;}
bool fakeEnabled(void*){return enabled;}
std::map<std::string,std::string> metadata;
const char* fakeData(void*,uint64_t,const char* key){return metadata[key].c_str();}
int twoMembers(void*,uint64_t){return 2;}
uint64_t memberAt(void*,uint64_t,int i){return i?22:11;}
void reset(){
 matchmaking=friends=utils=(void*)1;createLobby=fakeCreate;completed=fakeComplete;result=fakeResult;
 leaveLobby=fakeLeave;setData=fakeTag;getMembers=fakeMembers;overlay=fakeOverlay;overlayEnabled=fakeEnabled;
 lobby=creation=0;invitePending=cancelPending=false;members=0;error=0;state="idle";
 creates=invites=leaves=tags=0;complete=false;enabled=tagged=true;ioFailure=false;
}
}
int main(){
 reset();lobby_create(nullptr);lobby_create(nullptr);assert(creates==1 && invites==0);
 lobby_poll(nullptr);assert(lobby==0 && invites==0);
 complete=true;lobby_poll(nullptr);assert(lobby==123 && tags==4 && invites==1);
 lobby_poll(nullptr);assert(invites==1);lobby_invite(nullptr);assert(invites==2 && creates==1);
 lobby_leave(nullptr);assert(leaves==1 && lobby==0 && members==0);
 reset();lobby_create(nullptr);lobby_leave(nullptr);complete=true;lobby_poll(nullptr);
 assert(leaves==1 && lobby==0 && invites==0 && strcmp(state,"idle")==0);
 reset();lobby_create(nullptr);enabled=false;complete=true;lobby_poll(nullptr);
 assert(lobby==123 && invites==0 && strcmp(state,"overlay_unavailable")==0);
 enabled=true;lobby_poll(nullptr);assert(invites==1 && strcmp(state,"lobby_ready")==0);
 reset();lobby_create(nullptr);tagged=false;complete=true;lobby_poll(nullptr);assert(leaves==1 && lobby==0 && invites==0);
 reset();lobby_create(nullptr);complete=ioFailure=true;lobby_poll(nullptr);assert(lobby==0 && creation==0 && invites==0);
 reset();lobby_create_quiet(nullptr);complete=true;lobby_poll(nullptr);assert(lobby==123&&invites==0);
 online::getData=fakeData;online::content=std::string(64,'a');
 metadata={{"trmp_mod","resistance-multiplayer"},{"trmp_protocol","TRMP1"},{"trmp_mode","infiltrator-versus"},
 {"trmp_transport","steam-sdr-udp1"},{"trmp_build",trmp::NetworkBuild},{"trmp_content",online::content}};
 assert(online::compatible());metadata["trmp_content"]=std::string(64,'b');assert(!online::compatible());metadata["trmp_content"]=online::content;
 metadata["trmp_build"]="old-build";assert(!online::compatible());metadata["trmp_build"]=trmp::NetworkBuild;
 metadata["trmp_transport"]="direct-ip";assert(!online::compatible());
 online::selfId=11;online::getMember=memberAt;getMembers=twoMembers;
 assert(online::memberAllowed(22)&&!online::memberAllowed(11)&&!online::memberAllowed(33));
 uint64_t room=(1ULL<<56)|(8ULL<<52)|(0x40000ULL<<32)|123;
 assert(online::validRoom(room)&&!online::validRoom(123));
 struct Invite{uint64_t room,friendId;} invite{room,22};online::inviteCallback.Run(&invite);
 assert(online::invited==room&&!strcmp(state,"invitation_pending"));
 auto marker=std::string("TRMP_SESSION1|123:123|4|ready|")+std::to_string(time(nullptr));uint32_t generation=0;bool ready=false;
 assert(online::sessionValue(marker,generation,ready)&&generation==4&&ready);
 assert(!online::sessionValue("TRMP_SESSION1|bad|4|ready|123",generation,ready));
 assert(!online::sessionValue("TRMP_SESSION1|1:1|2147483648|ready|123",generation,ready));
 puts("PASS: Steam private lobby creation, retry, metadata, overlay, leave and cancellation");
 puts("PASS: Steam invitation callback ABI, lobby identity, peer membership, build/content gates and generation metadata");
}
