#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <cstdio>
#include <cstdint>
#include <cstring>

// UE 4.25Plus shipping build, SHA256:
// 5A01BBEE102990B1B1108C8656994ED19D46A9B2735C3B3A11EB9C7921CAFDB4
// Calls AActor::DispatchBeginPlay for the validated base engine test actors.
// No executable bytes, global world flags, or save data are changed.
static HMODULE selfModule;
static char directory[MAX_PATH];
static void writeLog(const char* message,uintptr_t actor=0,unsigned before=0,unsigned after=0) {
    char path[MAX_PATH]; sprintf_s(path,"%sprototype-runtime.log",directory);
    FILE* file=nullptr; fopen_s(&file,path,"a");
    if(file) { fprintf(file,"pid=%lu %s actor=%p before=%02x after=%02x\n",GetCurrentProcessId(),message,(void*)actor,before,after); fclose(file); }
}
static bool readable(uintptr_t address,size_t bytes) {
    MEMORY_BASIC_INFORMATION info={};
    return VirtualQuery((void*)address,&info,sizeof(info)) && info.State==MEM_COMMIT
        && !(info.Protect&(PAGE_NOACCESS|PAGE_GUARD))
        && address+bytes <= (uintptr_t)info.BaseAddress+info.RegionSize;
}
static LONG CALLBACK logCppException(PEXCEPTION_POINTERS exception) {
    const auto record=exception->ExceptionRecord;
    if(record->ExceptionCode!=0xe06d7363 || record->NumberParameters<3)return EXCEPTION_CONTINUE_SEARCH;
    auto object=(uintptr_t)record->ExceptionInformation[1];
    if(!readable(object,16))return EXCEPTION_CONTINUE_SEARCH;
    auto message=*(uintptr_t*)(object+8);
    char text[1024]={};size_t length=0;
    for(;length<sizeof(text)-1 && readable(message+length,1);++length) {
        char c=*(char*)(message+length);if(!c)break;
        if((unsigned char)c<0x20 && c!='\n' && c!='\t')break;
        text[length]=c;
    }
    if(length)writeLog(text);
    return EXCEPTION_CONTINUE_SEARCH;
}
extern "C" __declspec(dllexport) int log_exceptions(void*) {
    static bool installed=false;if(installed)return 0;
    GetModuleFileNameA(selfModule,directory,MAX_PATH);char* slash=strrchr(directory,'\\');if(!slash)return 0;slash[1]=0;
    installed=AddVectoredExceptionHandler(0,&logCppException)!=nullptr;
    writeLog("first-chance C++ diagnostic enabled");return 0;
}
extern "C" __declspec(dllexport) int initialize_local(void*) {
    GetModuleFileNameA(selfModule,directory,MAX_PATH);
    char* slash=strrchr(directory,'\\'); if(!slash) return 0; slash[1]=0;
    char path[MAX_PATH]; sprintf_s(path,"%sprototype-actors.txt",directory);
    FILE* file=nullptr; fopen_s(&file,path,"r"); if(!file) { writeLog("missing actor descriptor"); return 0; }
    unsigned long pid=0; unsigned long long controller=0,controllerClass=0,pawn=0,pawnClass=0;
    int fields=fscanf_s(file,"%lu %llx %llx %llx %llx",&pid,&controller,&controllerClass,&pawn,&pawnClass); fclose(file);
    if(fields!=5 || pid!=GetCurrentProcessId()) { writeLog("invalid or stale actor descriptor"); return 0; }
    auto base=(unsigned char*)GetModuleHandleW(nullptr);
    const unsigned char expected[]={0x48,0x89,0x7c,0x24,0x20,0x41,0x56,0x48,0x83,0xec,0x20,0x0f,0xb6,0x41,0x5c};
    if(memcmp(base+0x2089ed0,expected,sizeof(expected))!=0) { writeLog("unsupported DispatchBeginPlay signature"); return 0; }
    uintptr_t addresses[]={(uintptr_t)controller,(uintptr_t)pawn};
    uintptr_t classes[]={(uintptr_t)controllerClass,(uintptr_t)pawnClass};
    const auto dos=(IMAGE_DOS_HEADER*)base;
    const auto nt=(IMAGE_NT_HEADERS64*)(base+dos->e_lfanew);
    for(int i=0;i<2;++i) {
        auto object=addresses[i];
        if(!readable(object,0x60) || *(uintptr_t*)(object+0x10)!=classes[i]) { writeLog("invalid actor class",object); return 0; }
        auto vtable=*(uintptr_t*)object;
        if(vtable<(uintptr_t)base || vtable+0x330>(uintptr_t)base+nt->OptionalHeader.SizeOfImage) { writeLog("invalid actor vtable",object); return 0; }
    }
    auto dispatch=(void(*)(void*,bool))(base+0x2089ed0);
    for(auto object:addresses) {
        unsigned before=*(unsigned char*)(object+0x5c)&0x60;
        if(before==0) dispatch((void*)object,false);
        unsigned after=*(unsigned char*)(object+0x5c)&0x60;
        writeLog("selective BeginPlay",object,before,after);
    }
    return 0;
}
// Start listening in the already initialized world. Reopening the Infiltrator
// level would discard its randomized mission state. No code bytes are patched.
extern "C" __declspec(dllexport) int listen_local(void*) {
    GetModuleFileNameA(selfModule,directory,MAX_PATH);
    char* slash=strrchr(directory,'\\');if(!slash)return 0;slash[1]=0;
    char path[MAX_PATH];sprintf_s(path,"%slisten-world.txt",directory);
    FILE* file=nullptr;fopen_s(&file,path,"r");if(!file)return 0;
    unsigned long pid=0;unsigned long long world=0,worldClass=0;
    int fields=fscanf_s(file,"%lu %llx %llx",&pid,&world,&worldClass);fclose(file);
    if(fields!=3 || pid!=GetCurrentProcessId() || !readable((uintptr_t)world,0x60)
        || *(uintptr_t*)(world+0x10)!=(uintptr_t)worldClass) {writeLog("invalid listen descriptor");return 0;}
    auto base=(unsigned char*)GetModuleHandleW(nullptr);
    const unsigned char signature[]={0x48,0x89,0x5c,0x24,0x10,0x48,0x89,0x74,0x24,0x20,0x57,0x48,0x83,0xec,0x50};
    if(memcmp(base+0x272b5b0,signature,sizeof(signature))!=0) {writeLog("unsupported Listen signature");return 0;}
    if(*(uintptr_t*)(world+0x38)) {writeLog("world already has net driver");return 0;}
    // Use the engine's own FURL constructor/destructor and allocator.
    alignas(8) unsigned char url[0x68]={};
    auto construct=(void(*)(void*,const void*,const wchar_t*,unsigned char))(base+0x26eb6b0);
    auto destruct=(void(*)(void*))(base+0x62c870);
    auto listen=(bool(*)(void*,void*))(base+0x272b5b0);
    construct(url,nullptr,L"unreal://127.0.0.1:7777?listen",0);
    bool success=listen((void*)world,url);
    destruct(url);
    writeLog(success?"in-place listener started":"in-place listener failed",(uintptr_t)world);
    return 0;
}
BOOL WINAPI DllMain(HINSTANCE instance,DWORD reason,LPVOID) {
    if(reason==DLL_PROCESS_ATTACH) { selfModule=instance; DisableThreadLibraryCalls(instance); }
    return TRUE;
}
