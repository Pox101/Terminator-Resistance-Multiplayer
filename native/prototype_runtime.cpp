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
BOOL WINAPI DllMain(HINSTANCE instance,DWORD reason,LPVOID) {
    if(reason==DLL_PROCESS_ATTACH) { selfModule=instance; DisableThreadLibraryCalls(instance); }
    return TRUE;
}
