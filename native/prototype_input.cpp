#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <cstdio>
#include <cstring>

// File bridge: no dependency on UE4SS's private Lua ABI.
// Only keyboard/mouse-button state for this process's foreground window is exposed.
static HMODULE selfModule;
static DWORD lastPid = ~DWORD(0);
static unsigned lastMask = ~0u;
extern "C" __declspec(dllexport) int sample_input(void*) {
    DWORD foregroundPid = 0;
    GetWindowThreadProcessId(GetForegroundWindow(), &foregroundPid);
    unsigned mask = 0;
    const int keys[] = {'W','A','S','D',VK_RBUTTON,VK_LBUTTON,'R'};
    if(foregroundPid == GetCurrentProcessId()) {
        for(unsigned i=0;i<sizeof(keys)/sizeof(keys[0]);++i)
            if(GetAsyncKeyState(keys[i]) & 0x8000) mask |= 1u<<i;
    }
    if(foregroundPid == lastPid && mask == lastMask) return 0;
    char path[MAX_PATH]; GetModuleFileNameA(selfModule,path,MAX_PATH);
    char* slash = strrchr(path,'\\'); if(!slash) return 0;
    strcpy_s(slash+1,MAX_PATH-(slash+1-path),"input-state.txt");
    FILE* file=nullptr; fopen_s(&file,path,"w");
    if(file) {
        fprintf(file,"%lu %u\n",foregroundPid,mask); fclose(file);
        lastPid=foregroundPid; lastMask=mask;
    }
    return 0;
}
BOOL WINAPI DllMain(HINSTANCE instance,DWORD reason,LPVOID) {
    if(reason==DLL_PROCESS_ATTACH) { selfModule=instance; DisableThreadLibraryCalls(instance); }
    return TRUE;
}
