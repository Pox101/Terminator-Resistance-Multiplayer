// Fake Steam functions exercise lifecycle behavior without contacting Steam.
#include "../native/steam_lobby.cpp"
#include <cassert>
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
 puts("PASS: Steam private lobby creation, retry, metadata, overlay, leave and cancellation");
}
