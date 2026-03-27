#import <Foundation/Foundation.h>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <dlfcn.h>
#include <mach-o/dyld.h>
#include <mach/mach.h>
#include <dispatch/dispatch.h>
#include <fcntl.h>
#include <unistd.h>
#include <chrono>
#include <vector>
#include <set>

#include <QApplication>
#include <QDialog>
#include <QVBoxLayout>
#include <QHBoxLayout>
#include <QLabel>
#include <QSpinBox>
#include <QPushButton>
#include <QCheckBox>
#include <QShortcut>
#include <QKeySequence>
#include <QKeyEvent>
#include <QWidget>
#include <QMenuBar>
#include <QMenu>
#include <QAction>

// =============================================================================
// Safe memory read
// =============================================================================
static bool safeRead(const void* addr, void* dest, size_t len) {
    vm_size_t outSize = 0;
    kern_return_t kr = vm_read_overwrite(
        mach_task_self(),
        (vm_address_t)addr,
        (vm_size_t)len,
        (vm_address_t)dest,
        &outSize);
    return kr == KERN_SUCCESS && outSize == len;
}

// =============================================================================
// Image slide resolution
// =============================================================================
static intptr_t g_slide = 0;
static const char* kMoveChannelLogPath = "/Users/sfx/Programavimas/dLive-patch/movechannel.log";

static void setupLogging() {
    int fd = open(kMoveChannelLogPath, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd < 0) return;

    if (dup2(fd, STDERR_FILENO) >= 0) {
        setvbuf(stderr, nullptr, _IONBF, 0);
        dprintf(STDERR_FILENO, "[MC] log file: %s\n", kMoveChannelLogPath);
    }
    close(fd);
}

static uint64_t monotonicMs() {
    using namespace std::chrono;
    return (uint64_t)duration_cast<milliseconds>(
        steady_clock::now().time_since_epoch()).count();
}

static void resolveSlide() {
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const char* name = _dyld_get_image_name(i);
        if (name && strstr(name, "dLive Director")) {
            g_slide = _dyld_get_image_vmaddr_slide(i);
            fprintf(stderr, "[MC] slide = 0x%lx\n", (unsigned long)g_slide);
            return;
        }
    }
    fprintf(stderr, "[MC] ERROR: dLive Director image not found!\n");
}

#define RESOLVE(addr) ((void*)((uintptr_t)(addr) + g_slide))
#define MAKE_KEY(type, ch) ((uint64_t)(type) | ((uint64_t)(ch) << 32))

// =============================================================================
// Function pointer types
// =============================================================================
typedef void* (*fn_void_void)();
typedef void  (*fn_method_void)(void* obj);
typedef void  (*fn_method_msg)(void* obj, void* msg);
typedef void  (*fn_MsgCtorCap)(void*, uint32_t);
typedef void  (*fn_MsgDtor)(void*);
typedef const char* (*fn_GetChannelName)(void* dm, uint32_t stripType, uint8_t ch);
typedef void  (*fn_SetChannelName)(void* dm, uint32_t stripType, uint8_t ch, const char* name);
typedef uint8_t (*fn_GetChannelColour)(void* dm, uint32_t stripType, uint8_t ch);
typedef void  (*fn_SetChannelColour)(void* dm, uint32_t stripType, uint8_t ch, uint8_t colour);
typedef void  (*fn_SetMainGain)(void* mixer, uint8_t chInGroup, int16_t gain, uint16_t xfade);
typedef void  (*fn_SyncMainGain)(void* inputMixer, uint8_t ch, int16_t gain);
typedef bool  (*fn_ChannelIsStereo)(void* helpers, uint64_t key);

// =============================================================================
// Processing object descriptors
// =============================================================================
// Type A: net objects with FillGetStatus / DirectlyRecallStatus / ReportData
struct ProcDescA {
    const char* name;
    int chOffset;
    uintptr_t fillGetStatusAddr;
    uintptr_t directlyRecallAddr;
    uintptr_t reportDataAddr;
};

// Type B: data objects — GetStatus hangs offline (tail-calls SyscallSendMessage).
// Instead, we read fields directly from object and call SetStatus to write.
// Data buffer is big-endian (SWORD/UWORD byte-swapped via rolw $8).
// Field access patterns:
// PTR_*:    obj+offset → read pointer → read value from pointer (cAudioObject subclasses)
// DIRECT_*: obj+offset → read value directly (cNetObject subclasses)
enum FieldType {
    FT_UBYTE, FT_UBYTE_BOOL, FT_SWORD, FT_UWORD,                    // pointer dereference
    FT_DIRECT_UBYTE, FT_DIRECT_UBYTE_BOOL, FT_DIRECT_SWORD, FT_DIRECT_UWORD  // direct access
};

struct FieldDesc {
    int objOffset;      // byte offset in object
    FieldType type;
    int msgDataOffset;  // offset in message data buffer
};

struct ProcDescB {
    const char* name;
    int chOffset;           // field index in InputChannel, or -1 for vtable scan
    uintptr_t vtableStatic; // vtable symbol address (for dynamic lookup when chOffset==-1)
    int msgLength;          // data length (for serialization/comparison)
    uint8_t versionByte;    // version byte written to buf[0]
    int subFieldIdx;        // if > 0: chOffset gives driver, subFieldIdx gives net obj within driver
    uintptr_t refreshAddr;  // optional Refresh/UpdateDriver method address (0 = none)
    int numFields;
    FieldDesc fields[4];
};

static ProcDescA g_procA[] = {
    {"DigiTube",  2,  0x1002d4170, 0x1002d42c0, 0x1002d53b0}, // cPreampModel = tube modeling, NOT analog gain
    {"HPF",       5,  0x10028d4d0, 0x10028d5c0, 0x10028d9c0},
    {"LPF",       6,  0x100b1e790, 0x100b1e8d0, 0x100b1efa0},
    {"Compressor",7,  0x1001f1040, 0x1001f1700, 0x1001f43a0},
    {"GateSCPEQ", 8,  0x1002d0d30, 0x1002d0ed0, 0x1002d1b30},
    {"Gate",      9,  0x100287a00, 0x100287b30, 0x100288f00},
    {"PEQ",       10, 0x100b1cdc0, 0x100b1cf00, 0x100b1d7f0},
};
static const int NUM_PROC_A = sizeof(g_procA) / sizeof(g_procA[0]);

// Field layouts derived from disassembling each class's GetStatus:
// subFieldIdx: 0 = object is directly at chOffset, >0 = driver at chOffset, net obj at driver[subFieldIdx]
static ProcDescB g_procB[] = {
    // cDigitalAttenuator (preamp digital trim): via driver at ch[4], net obj at driver[1]
    // ptr-deref: +0x98→gain(SWORD), +0xa0→mute(UBYTE_BOOL), +0xa8→polarity(UBYTE_BOOL)
    {"DigitalTrim", 4, 0x106c781f0, 7, 0x01, 1, 0, 3, {
        {0x98, FT_SWORD,      1},
        {0xa0, FT_UBYTE_BOOL, 3},
        {0xa8, FT_UBYTE_BOOL, 4},
    }},
    // cDelay (via cInputDelayDriver at ch[17], net obj at driver[1])
    // ptr-deref: +0x98→delay(UWORD), +0xa0→bypass(UBYTE_BOOL)
    {"Delay", 17, 0x106c78078, 4, 0x01, 1, 0, 2, {
        {0x98, FT_UWORD,      1},
        {0xa0, FT_UBYTE_BOOL, 3},
    }},
    // cDirectOutput: EXCLUDED — direct output stays tied to position
    // cProcessingOrderingSelect: len=2, version=0x01 — vtable scan (ptr-deref)
    {"ProcOrder", -1, 0x106c7a228, 2, 0x01, 0, 0, 1, {
        {0x88, FT_UBYTE_BOOL, 1},
    }},
    // cInsertNetObject (via InsertDriver1 at ch[12]→driver[1]): len=3, version=0x00
    {"Insert1", 12, 0, 3, 0x00, 1, 0, 2, {
        {0x98, FT_DIRECT_UBYTE_BOOL, 1},
        {0xA0, FT_DIRECT_UBYTE,     2},
    }},
    // cInsertNetObject (via InsertDriver2 at ch[13]→driver[1])
    {"Insert2", 13, 0, 3, 0x00, 1, 0, 2, {
        {0x98, FT_DIRECT_UBYTE_BOOL, 1},
        {0xA0, FT_DIRECT_UBYTE,     2},
    }},
    // cSideChainSelect (via SideChainSelectDriver at ch[14]→driver[1]): len=3, version=0x01
    // Source routing: 0x138→ptr to eChannelStripType (uint32, read low byte), 0x140→ptr to channel# (uint8)
    {"SideChain1", 14, 0, 3, 0x01, 1, 0, 2, {
        {0x138, FT_UBYTE, 1},
        {0x140, FT_UBYTE, 2},
    }},
    // cSideChainSelect (via SideChainSelectDriver at ch[15]→driver[1])
    {"SideChain2", 15, 0, 3, 0x01, 1, 0, 2, {
        {0x138, FT_UBYTE, 1},
        {0x140, FT_UBYTE, 2},
    }},
    // cStereoImage (via cStereoImageDriver at ch[3]→driver[1]): len=4, version=0x01
    // ptr-deref: +0xa0→width(UWORD), +0xa8→mode(UBYTE)
    {"StereoImage", 3, 0, 4, 0x01, 1, 0, 2, {
        {0xA0, FT_UWORD, 1},
        {0xA8, FT_UBYTE, 3},
    }},
};
static const int NUM_PROC_B = sizeof(g_procB) / sizeof(g_procB[0]);

static const size_t MSG_BUF_SIZE = 0x1000;

// =============================================================================
// Resolved globals
// =============================================================================
static fn_void_void     g_AppInstance;
static fn_void_void     g_CPRHelpersInstance;
static fn_MsgCtorCap    g_msgCtorCap;
static fn_MsgDtor       g_msgDtor;
static fn_GetChannelName  g_getChannelName;
static fn_SetChannelName  g_setChannelName;
static fn_GetChannelColour g_getChannelColour;
static fn_SetChannelColour g_setChannelColour;

static fn_ChannelIsStereo g_channelIsStereo;

static void* g_audioDM = nullptr;
static void** g_dmFields = nullptr;
static int g_firstInputChIdx = -1;
static void* g_inputMixerWrapper = nullptr;  // cInputMixerWrapper*
static void* g_channelMapper = nullptr;      // cChannelMapperBase* (for patching)
static void* g_registryRouter = nullptr;     // gRegistryRouter
static void* g_channelManager = nullptr;     // cChannelManager* (from cUIManagerHolder)
static void* g_audioSRPManager = nullptr;    // cAudioSendReceivePointManager* (from cUIManagerHolder)
static void* g_dynRack = nullptr;            // cDynamicsRack* (from UIManagerHolder+0x40)
static void* g_sceneClient = nullptr;       // cSceneManagerIntermediateClient* (from UIManagerHolder scan)
static void* g_libraryMgrClient = nullptr;  // cLibraryManagerClient* (from UIManagerHolder+0x98)
static int g_firstAnalogueInputIdx = -1;     // first cAnalogueInput index in router table
static int g_firstDynNetObjIdx = -1;         // first cDynamicsNetObject index in router table
static int g_dynNetObjIndices[256] = {};     // all found cDynamicsNetObject registry indices
static int g_dynNetObjCount = 0;             // total found

static const size_t SINPUTATTRS_SIZE = 0xAC8; // sizeof(sInputAttributes)

// sAudioSource: 8 bytes {uint32_t type, uint32_t number}
struct sAudioSource { uint32_t type; uint32_t number; };

// Patching data per channel
struct PatchData {
    uint32_t     sourceType;  // from activeInputChannelSourceType[ch]
    sAudioSource source;      // from the appropriate array
};

static void resolveSymbols() {
    g_AppInstance        = (fn_void_void)RESOLVE(0x100d5a120);
    g_CPRHelpersInstance = (fn_void_void)RESOLVE(0x100403270);
    g_msgCtorCap         = (fn_MsgCtorCap)RESOLVE(0x1000ed490);
    g_msgDtor            = (fn_MsgDtor)RESOLVE(0x1000e9810);
    g_getChannelName     = (fn_GetChannelName)RESOLVE(0x1001a3750);
    g_setChannelName     = (fn_SetChannelName)RESOLVE(0x1001a3670);
    g_getChannelColour   = (fn_GetChannelColour)RESOLVE(0x1001a34a0);
    g_setChannelColour   = (fn_SetChannelColour)RESOLVE(0x1001a3580);
    g_channelIsStereo    = (fn_ChannelIsStereo)RESOLVE(0x100405740);
}

// =============================================================================
// Find AudioCoreDM and InputChannels
// =============================================================================
static bool findAudioCoreDM() {
    void* app = g_AppInstance();
    if (!app) { fprintf(stderr, "[MC] App instance is null!\n"); return false; }

    void* expectedDMVtable = (void*)((uintptr_t)RESOLVE(0x106c77998) + 16);
    void** appFields = (void**)app;

    for (int i = 0; i < 200; i++) {
        void* field;
        if (!safeRead(&appFields[i], &field, sizeof(field))) continue;
        if (!field || (uintptr_t)field < 0x100000000ULL || (uintptr_t)field > 0x800000000000ULL) continue;

        void** subFields = (void**)field;
        for (int j = 0; j < 50; j++) {
            void* subField;
            if (!safeRead(&subFields[j], &subField, sizeof(subField))) continue;
            if (!subField || (uintptr_t)subField < 0x100000000ULL || (uintptr_t)subField > 0x800000000000ULL) continue;
            void* vt;
            if (!safeRead(subField, &vt, sizeof(vt))) continue;
            if (vt == expectedDMVtable) {
                g_audioDM = subField;
                g_dmFields = (void**)subField;
                fprintf(stderr, "[MC] AudioCoreDM at app[%d][%d] = %p\n", i, j, subField);
                break;
            }
        }
        if (g_audioDM) break;
    }

    if (!g_audioDM) { fprintf(stderr, "[MC] AudioCoreDM not found!\n"); return false; }

    void* inputChVtable = (void*)((uintptr_t)RESOLVE(0x106c79978) + 16);
    int count = 0;
    for (int i = 0; i < 300; i++) {
        void* field;
        if (!safeRead(&g_dmFields[i], &field, sizeof(field))) continue;
        if (!field || (uintptr_t)field < 0x100000000ULL || (uintptr_t)field > 0x800000000000ULL) continue;
        void* vt;
        if (!safeRead(field, &vt, sizeof(vt))) continue;
        if (vt == inputChVtable) {
            if (g_firstInputChIdx < 0) g_firstInputChIdx = i;
            count++;
        }
    }
    fprintf(stderr, "[MC] Found %d InputChannels, first at dm[%d]\n", count, g_firstInputChIdx);

    // Log stereo status of first 8 channels for validation
    {
        void* helpers = g_CPRHelpersInstance();
        if (helpers) {
            fprintf(stderr, "[MC] Stereo status ch 1-8: ");
            for (int i = 0; i < 8; i++) {
                uint64_t key = MAKE_KEY(1, (uint8_t)i);
                bool stereo = g_channelIsStereo(helpers, key);
                fprintf(stderr, "%d=%s ", i+1, stereo ? "ST" : "M");
            }
            fprintf(stderr, "\n");
        }
    }

    // Find InputMixerWrapper: AudioCoreDM+0x7A8 → driver → driver+0x8 → wrapper
    uint8_t* dmBytes = (uint8_t*)g_audioDM;
    void* mixerDriver = nullptr;
    if (safeRead(dmBytes + 0x7A8, &mixerDriver, sizeof(mixerDriver)) && mixerDriver) {
        void* wrapper = nullptr;
        safeRead((uint8_t*)mixerDriver + 0x8, &wrapper, sizeof(wrapper));
        if (wrapper) {
            // Verify by checking if wrapper+0x90 points to valid mixer objects
            void* firstMixer = nullptr;
            safeRead((uint8_t*)wrapper + 0x90, &firstMixer, sizeof(firstMixer));
            if (firstMixer && (uintptr_t)firstMixer > 0x100000000ULL) {
                g_inputMixerWrapper = wrapper;
                fprintf(stderr, "[MC] InputMixerWrapper at %p\n", wrapper);
            }
        }
    }
    if (!g_inputMixerWrapper)
        fprintf(stderr, "[MC] WARNING: InputMixerWrapper not found — mix sends won't transfer\n");

    // Find cChannelMapper via cChannelMapperUSBDriver in DM fields
    // cChannelMapperUSBDriver vtable+16 = 0x106c77c38, cChannelMapper at driver+0x20
    // cChannelMapper is 0xe108 bytes, vtable+16 = 0x106c77bc8
    {
        void* usbDrvVt = (void*)((uintptr_t)RESOLVE(0x106c77c28) + 16);
        void* cmVt = (void*)((uintptr_t)RESOLVE(0x106c77bb8) + 16);

        // Scan DM fields for cChannelMapperUSBDriver
        if (g_dmFields) {
            for (int i = 0; i < 300; i++) {
                void* field = nullptr;
                if (!safeRead(&g_dmFields[i], &field, sizeof(field))) continue;
                if (!field || (uintptr_t)field < 0x100000000ULL || (uintptr_t)field > 0x800000000000ULL) continue;
                void* vt = nullptr;
                if (!safeRead(field, &vt, sizeof(vt))) continue;
                if (vt == usbDrvVt) {
                    // Found USB driver, cChannelMapper is at driver+0x20
                    void* mapper = nullptr;
                    if (safeRead((uint8_t*)field + 0x20, &mapper, sizeof(mapper)) && mapper) {
                        void* mvt = nullptr;
                        safeRead(mapper, &mvt, sizeof(mvt));
                        fprintf(stderr, "[MC] ChannelMapperUSBDriver at dm[%d] = %p\n", i, field);
                        fprintf(stderr, "[MC] ChannelMapper at driver+0x20 = %p (vt=%p, expected=%p)\n",
                                mapper, mvt, cmVt);
                        g_channelMapper = mapper;
                    }
                    break;
                }
                // Also check direct cChannelMapper vtable match
                if (vt == cmVt) {
                    g_channelMapper = field;
                    fprintf(stderr, "[MC] ChannelMapper found directly at dm[%d] = %p\n", i, field);
                    break;
                }
            }
        }
    }
    if (!g_channelMapper)
        fprintf(stderr, "[MC] WARNING: ChannelMapper not found — patching won't transfer\n");

    // =========================================================================
    // Find cAnalogueInput objects in RegistryRouter local table
    // 512 objects at router+0x3a9820, starting at index 85
    // First 64 = Surface inputs, then 7×64 = StageBox inputs
    // Layout: +0x98→gain_ptr(int16), +0xa0→pad_ptr(bool), +0xa8→phantom_ptr(bool)
    // =========================================================================
    {
        void** rrPtr = (void**)RESOLVE(0x106fb6670);
        void* rr = nullptr;
        safeRead(rrPtr, &rr, sizeof(rr));
        g_registryRouter = rr;

        if (rr) {
            void* aiVtExpected = (void*)((uintptr_t)RESOLVE(0x106ce7930) + 16);
            uint8_t* base = (uint8_t*)rr + 0x3a9820;

            // Find first cAnalogueInput index
            for (int i = 0; i < 1000; i++) {
                void* entry = nullptr;
                if (!safeRead(base + i * 8, &entry, sizeof(entry))) continue;
                if (!entry || (uintptr_t)entry < 0x100000000ULL) continue;
                void* vt = nullptr;
                if (!safeRead(entry, &vt, sizeof(vt))) continue;
                if (vt == aiVtExpected) {
                    g_firstAnalogueInputIdx = i;
                    break;
                }
            }
            fprintf(stderr, "[MC] AnalogueInput: first at router idx %d\n", g_firstAnalogueInputIdx);
        }
    }

    // =========================================================================
    // Find cDigitalAttenuator objects in RegistryRouter (for message-based set)
    // Also scan ch0 for StereoImage and Delay correct offsets
    // =========================================================================
    {
        void* daVt = (void*)((uintptr_t)RESOLVE(0x106c78198));
        if (g_registryRouter) {
            uint8_t* base = (uint8_t*)g_registryRouter + 0x3a9820;
            int daCount = 0, firstDA = -1;
            for (int i = 0; i < 2000 && daCount < 5; i++) {
                void* entry = nullptr;
                if (!safeRead(base + i * 8, &entry, sizeof(entry))) continue;
                if (!entry || (uintptr_t)entry < 0x100000000ULL) continue;
                void* vt = nullptr;
                if (!safeRead(entry, &vt, sizeof(vt))) continue;
                if (vt == daVt) {
                    if (firstDA < 0) firstDA = i;
                    // Read objectId and handle from the object's embedded msg
                    uint16_t objId = 0; uint32_t handle = 0;
                    safeRead((uint8_t*)entry + 0x70, &objId, 2);
                    safeRead((uint8_t*)entry + 0x74, &handle, 4);
                    // Read gain value
                    void* gainPtr = nullptr; int16_t gain = 0;
                    safeRead((uint8_t*)entry + 0x98, &gainPtr, sizeof(gainPtr));
                    if (gainPtr && (uintptr_t)gainPtr > 0x100000000ULL)
                        safeRead(gainPtr, &gain, 2);
                    fprintf(stderr, "[MC] DigAtten router[%d]: objId=0x%x handle=0x%x gain=%d obj=%p\n",
                            i, objId, handle, gain, entry);
                    daCount++;
                }
            }
            fprintf(stderr, "[MC] DigitalAttenuator: first at router idx %d, found %d\n", firstDA, daCount);
        }

        // Also scan ch0 for StereoImage and Delay
        void* inputCh = nullptr;
        safeRead(&g_dmFields[g_firstInputChIdx], &inputCh, sizeof(inputCh));
        if (inputCh) {
            void** chF = (void**)inputCh;
            void* siDrvVt = (void*)((uintptr_t)RESOLVE(0x106c7a860));
            void* delDrvVt = (void*)((uintptr_t)RESOLVE(0x106c780d0));    // cDelayDriver base
            void* idelDrvVt = (void*)((uintptr_t)RESOLVE(0x106c799a8));   // cInputDelayDriver (vtable+16)
            for (int fi = 0; fi < 120; fi++) {
                void* field = nullptr;
                safeRead(&chF[fi], &field, sizeof(field));
                if (!field || (uintptr_t)field < 0x1000ULL || (uintptr_t)field > 0x800000000000ULL) continue;
                void* vt = nullptr;
                if (!safeRead(field, &vt, sizeof(vt))) continue;
                if (vt == siDrvVt) fprintf(stderr, "[MC]   ch0[%d] = cStereoImageDriver\n", fi);
                if (vt == delDrvVt) fprintf(stderr, "[MC]   ch0[%d] = cDelayDriver\n", fi);
                if (vt == idelDrvVt) fprintf(stderr, "[MC]   ch0[%d] = cInputDelayDriver\n", fi);
            }
        }

        // (diagnostic insert dump removed — insert routing now handled in snapshotChannel/moveChannel)
    }

    // =========================================================================
    // Find cDynamicsNetObject in RegistryRouter (for Dyn8 pool settings transfer)
    // vtable for cDynamicsNetObject = 0x106c78e28
    // 64 objects (one per Dyn8 pool unit), Type A: FillGetStatus/DirectlyRecallStatus/ReportData
    // =========================================================================
    {
        if (g_registryRouter) {
            void* dnoVt = (void*)((uintptr_t)RESOLVE(0x106c78e28) + 16);
            uint8_t* base = (uint8_t*)g_registryRouter + 0x3a9820;
            g_dynNetObjCount = 0;
            for (int i = 0; i < 5000 && g_dynNetObjCount < 256; i++) {
                void* entry = nullptr;
                if (!safeRead(base + i * 8, &entry, sizeof(entry))) continue;
                if (!entry || (uintptr_t)entry < 0x100000000ULL) continue;
                void* vt = nullptr;
                if (!safeRead(entry, &vt, sizeof(vt))) continue;
                if (vt == dnoVt) {
                    if (g_firstDynNetObjIdx < 0) g_firstDynNetObjIdx = i;
                    g_dynNetObjIndices[g_dynNetObjCount] = i;
                    g_dynNetObjCount++;
                }
            }
            fprintf(stderr, "[MC] DynamicsNetObject: first at router idx %d, found %d total\n",
                    g_firstDynNetObjIdx, g_dynNetObjCount);
            // Dump key58 for first 8 objects to understand pairing
            for (int n = 0; n < g_dynNetObjCount && n < 8; n++) {
                void* entry = nullptr;
                safeRead(base + g_dynNetObjIndices[n] * 8, &entry, sizeof(entry));
                if (!entry) continue;
                uint32_t key58 = 0;
                safeRead((uint8_t*)entry + 0x58, &key58, 4);
                fprintf(stderr, "[MC]   #%d registryIdx=%d obj=%p key58=0x%08x\n",
                        n, g_dynNetObjIndices[n], entry, key58);
            }
            // Show gap between first 64 and next entries
            if (g_dynNetObjCount > 64) {
                fprintf(stderr, "[MC]   ... gap: #63 registryIdx=%d, #64 registryIdx=%d (delta=%d)\n",
                        g_dynNetObjIndices[63], g_dynNetObjIndices[64],
                        g_dynNetObjIndices[64] - g_dynNetObjIndices[63]);
                for (int n = 64; n < g_dynNetObjCount && n < 68; n++) {
                    void* entry = nullptr;
                    safeRead(base + g_dynNetObjIndices[n] * 8, &entry, sizeof(entry));
                    if (!entry) continue;
                    uint32_t key58 = 0;
                    safeRead((uint8_t*)entry + 0x58, &key58, 4);
                    fprintf(stderr, "[MC]   #%d registryIdx=%d obj=%p key58=0x%08x\n",
                            n, g_dynNetObjIndices[n], entry, key58);
                }
            }
        }
    }

    // =========================================================================
    // Get cChannelManager and cAudioSendReceivePointManager from cUIManagerHolder
    // Used for proper patching via SetInputChannelSource (CSV import path)
    // =========================================================================
    {
        typedef void* (*fn_Instance)();
        auto getInstance = (fn_Instance)RESOLVE(0x10076d170);
        void* uiHolder = getInstance();
        if (uiHolder) {
            safeRead((uint8_t*)uiHolder + 0x78, &g_channelManager, sizeof(g_channelManager));
            safeRead((uint8_t*)uiHolder + 0x20, &g_audioSRPManager, sizeof(g_audioSRPManager));
            fprintf(stderr, "[MC] UIManagerHolder: channelMgr=%p audioSRPMgr=%p\n",
                    g_channelManager, g_audioSRPManager);

            // Store cDynamicsRack (at UIManagerHolder+0x40, confirmed by vtable scan)
            safeRead((uint8_t*)uiHolder + 0x40, &g_dynRack, sizeof(g_dynRack));
            fprintf(stderr, "[MC] DynamicsRack=%p\n", g_dynRack);

            // Find cSceneManagerIntermediateClient by vtable scan
            uintptr_t sceneClientVt = (uintptr_t)RESOLVE(0x106c9de30) + 0x10; // vtable symbol + 0x10
            for (int off = 0; off < 0x300; off += 8) {
                void* ptr = nullptr;
                safeRead((uint8_t*)uiHolder + off, &ptr, sizeof(ptr));
                if (!ptr || (uintptr_t)ptr < 0x100000000ULL) continue;
                void* vt = nullptr;
                safeRead(ptr, &vt, sizeof(vt));
                if ((uintptr_t)vt == sceneClientVt) {
                    g_sceneClient = ptr;
                    fprintf(stderr, "[MC] SceneManagerIntermediateClient at UIManagerHolder+0x%x = %p\n", off, ptr);
                    break;
                }
            }
            if (!g_sceneClient) fprintf(stderr, "[MC] SceneManagerIntermediateClient not found in UIManagerHolder\n");

            // cLibraryManagerClient at UIManagerHolder+0x98 (confirmed from PerformRecall disasm)
            safeRead((uint8_t*)uiHolder + 0x98, &g_libraryMgrClient, sizeof(g_libraryMgrClient));
            fprintf(stderr, "[MC] LibraryManagerClient=%p\n", g_libraryMgrClient);
        } else {
            fprintf(stderr, "[MC] UIManagerHolder::Instance() returned null\n");
        }
    }

    return count == 128;
}

// Get cDynamicsNetObject for Dyn8 pool unit by index
// module=0: first group (0-63), module=1: second group (64-127) in g_dynNetObjIndices
static void* getDynNetObj(int unitIdx, int module = 0) {
    int arrayIdx = module * 64 + unitIdx;
    if (arrayIdx < 0 || arrayIdx >= g_dynNetObjCount) return nullptr;
    uint8_t* base = (uint8_t*)g_registryRouter + 0x3a9820;
    void* entry = nullptr;
    safeRead(base + g_dynNetObjIndices[arrayIdx] * 8, &entry, sizeof(entry));
    return entry;
}

// Read first element from a QList-like structure at a given offset in an object
// QList d-ptr layout: +0x0 = refcount/flags, +0x8 = begin(int), +0xc = end(int), +0x10 = array data
static void* readQListFirst(void* obj, int objOffset) {
    void* listDPtr = nullptr;
    if (!safeRead((uint8_t*)obj + objOffset, &listDPtr, sizeof(listDPtr))) return nullptr;
    if (!listDPtr || (uintptr_t)listDPtr < 0x100000000ULL) return nullptr;
    int32_t begin = 0, end = 0;
    safeRead((uint8_t*)listDPtr + 0x8, &begin, 4);
    safeRead((uint8_t*)listDPtr + 0xc, &end, 4);
    if (begin == end) return nullptr;  // empty list
    void* elem = nullptr;
    safeRead((uint8_t*)listDPtr + 0x10 + begin * 8, &elem, sizeof(elem));
    return elem;
}

// Get DynamicsUnitClient for a given pool index (0-63)
static void* getDynUnitClient(int idx) {
    if (!g_dynRack || idx < 0 || idx >= 64) return nullptr;
    typedef void* (*fn_GetDUC)(void* rack, uint8_t idx);
    auto getDUC = (fn_GetDUC)RESOLVE(0x1005ce200);
    return getDUC(g_dynRack, (uint8_t)idx);
}

// Get Dyn8 audio send point for pool unit (its output)
// duc+0xb8 = QList<cAudioSendPoint*>
static void* getDyn8SendPoint(int unitIdx) {
    void* duc = getDynUnitClient(unitIdx);
    if (!duc) return nullptr;
    return readQListFirst(duc, 0xb8);
}

// Get Dyn8 audio receive point for pool unit (its input)
// duc+0xa0 = QList<cAudioReceivePoint*>
static void* getDyn8RecvPoint(int unitIdx) {
    void* duc = getDynUnitClient(unitIdx);
    if (!duc) return nullptr;
    return readQListFirst(duc, 0xa0);
}

static void* getDyn8SendPointFromManager(int unitIdx) {
    if (!g_audioSRPManager || unitIdx < 0 || unitIdx >= 64) return nullptr;
    typedef void* (*fn_GetSendPoint)(void* mgr, uint32_t sourceType, uint16_t sourceNum);
    auto getSendPoint = (fn_GetSendPoint)RESOLVE(0x1006ce8e0);
    return getSendPoint(g_audioSRPManager, 0x27, (uint16_t)unitIdx);
}

static void* getDyn8RecvPointFromManager(int unitIdx) {
    if (!g_audioSRPManager || unitIdx < 0 || unitIdx >= 64) return nullptr;
    typedef void* (*fn_GetReceivePoint)(void* mgr, uint32_t targetType, uint16_t targetNum);
    auto getReceivePoint = (fn_GetReceivePoint)RESOLVE(0x1006c8a30);
    return getReceivePoint(g_audioSRPManager, 0x25, (uint16_t)unitIdx);
}

static void* getDefaultInsertSendPoint() {
    if (!g_audioSRPManager) return nullptr;
    void* pt = nullptr;
    safeRead((uint8_t*)g_audioSRPManager + 0x350, &pt, sizeof(pt));
    return pt;
}

static void* getDefaultInsertReceivePoint() {
    if (!g_audioSRPManager) return nullptr;
    void* pt = nullptr;
    safeRead((uint8_t*)g_audioSRPManager + 0x358, &pt, sizeof(pt));
    return pt;
}

// Recall scene by number (1-based). Blocks briefly for the recall to take effect.
static void recallScene(int sceneNum) {
    if (!g_sceneClient) {
        fprintf(stderr, "[MC] recallScene(%d): no scene client!\n", sceneNum);
        return;
    }
    uint16_t idx = (uint16_t)(sceneNum - 1); // 0-indexed
    typedef void (*fn_SetGoSceneIndex)(void* client, uint16_t idx);
    auto setGoSceneIndex = (fn_SetGoSceneIndex)RESOLVE(0x10071e2c0);
    typedef void (*fn_RecallCurrentSettings)(void* client);
    auto recallSettings = (fn_RecallCurrentSettings)RESOLVE(0x10071e5b0);

    setGoSceneIndex(g_sceneClient, idx);
    typedef void (*fn_PerformGo)(void* client);
    auto performGo = (fn_PerformGo)RESOLVE(0x10071e350);
    performGo(g_sceneClient);
    fprintf(stderr, "[MC] recallScene(%d): SetGoSceneIndex(%d) + PerformGo called\n", sceneNum, idx);
}

static bool isChannelStereo(int ch);
static void waitForStereoConfigReset();
static bool readStereoConfig(uint8_t config[64]);
static bool writeStereoConfig(const uint8_t config[64]);
static bool isInsertStatusProc(int procIdx);

static void waitForSceneRecall() {
    QApplication::processEvents();
    usleep(1500 * 1000);
    QApplication::processEvents();
    usleep(1500 * 1000);
    QApplication::processEvents();
}

static bool waitForStereoConfigMatch(const uint8_t want[64], int timeoutMs, const char* tag) {
    const int stepMs = 100;
    int waited = 0;
    uint8_t live[64];
    while (waited <= timeoutMs) {
        QApplication::processEvents();
        if (readStereoConfig(live) && memcmp(live, want, 64) == 0) {
            fprintf(stderr, "[MC] %s: stereo config observed after %d ms\n", tag, waited);
            return true;
        }
        usleep(stepMs * 1000);
        waited += stepMs;
    }
    fprintf(stderr, "[MC] %s: timed out waiting for stereo config match\n", tag);
    return false;
}

static bool sendStereoConfigViaDiscovery(const uint8_t config[64], const char* tag) {
    typedef void* (*fn_DiscoveryInstance)();
    auto discoveryInstance = (fn_DiscoveryInstance)RESOLVE(0x10059c610);
    typedef void* (*fn_GetSBDiscovery)(void*);
    auto getStageBox = (fn_GetSBDiscovery)RESOLVE(0x10059c9a0);
    typedef void (*fn_SendInputConfigSetMessage)(void* sbObj, const void* cfg, bool flag);
    auto sendInputConfigSetMessage = (fn_SendInputConfigSetMessage)RESOLVE(0x1005b0db0);

    void* disc = discoveryInstance ? discoveryInstance() : nullptr;
    if (!disc || !getStageBox || !sendInputConfigSetMessage) {
        fprintf(stderr, "[MC] %s: discovery send path unavailable\n", tag);
        return false;
    }

    void* sbObj = getStageBox(disc);
    if (!sbObj) {
        fprintf(stderr, "[MC] %s: stagebox discovery object unavailable\n", tag);
        return false;
    }

    sendInputConfigSetMessage(sbObj, config, false);
    fprintf(stderr, "[MC] %s: SendInputConfigurationSetMessage dispatched\n", tag);
    return true;
}

static bool applyStereoConfigAndRefresh(const uint8_t config[64], const char* tag) {
    if (!sendStereoConfigViaDiscovery(config, tag)) {
        fprintf(stderr, "[MC] %s: discovery stereo apply failed\n", tag);
        return false;
    }
    waitForStereoConfigMatch(config, 5000, tag);
    waitForStereoConfigReset();
    fprintf(stderr, "[MC] %s: stereo config applied via discovery path\n", tag);
    return true;
}

static bool prepareScene21MoveTest() {
    uint8_t config[64];
    if (!readStereoConfig(config)) {
        fprintf(stderr, "[MC][AUTOTEST] prepareScene21MoveTest: failed to read stereo config\n");
        return false;
    }

    bool changed = false;
    auto setPair = [&](int pair, bool stereo) {
        uint8_t want = stereo ? 1 : 0;
        if (config[pair] != want) {
            fprintf(stderr, "[MC][AUTOTEST] prep layout: pair %d (ch %d+%d) %s -> %s\n",
                    pair, pair * 2 + 1, pair * 2 + 2,
                    config[pair] ? "STEREO" : "MONO",
                    stereo ? "STEREO" : "MONO");
            config[pair] = want;
            changed = true;
        }
    };

    setPair(0, false); // ch 1+2 mono
    setPair(1, true);  // ch 3+4 stereo
    setPair(2, false); // ch 5+6 mono

    if (changed && !applyStereoConfigAndRefresh(config, "[MC][AUTOTEST] prepareScene21MoveTest"))
        return false;

    fprintf(stderr, "[MC][AUTOTEST] recalling scene 21 after layout prep\n");
    recallScene(21);
    waitForSceneRecall();

    for (int ch = 0; ch < 6; ch++) {
        const char* name = g_getChannelName(g_audioDM, 1, (uint8_t)ch);
        fprintf(stderr, "[MC][AUTOTEST] scene21 ready ch %d: '%s' stereo=%d\n",
                ch + 1, name ? name : "", isChannelStereo(ch) ? 1 : 0);
    }
    return true;
}

static void setInputChannelInsertFlags(int ch, int ip, bool assigned, bool dynamics, const char* phaseTag);

// Find Dyn8 unit index by matching the insert's connected send point
// with DynamicsRack unit send points (parentType==5)
static int findDyn8UnitIdx(void* insertSendPt) {
    if (!g_dynRack || !insertSendPt) return -1;
    for (int i = 0; i < 64; i++) {
        void* sp = getDyn8SendPoint(i);
        if (sp == insertSendPt) return i;
    }
    return -1;
}

// =============================================================================
// Library helpers for Dyn8 settings transfer
// =============================================================================

// Get the prefix for dynamics unit names from the StageBox discovery object.
// In the UI, the full name is: prefix + sprintf("Dynamics Unit %02d", unitIdx+1)
static char g_dynNamePrefix[128] = {0};
static bool g_dynNamePrefixResolved = false;

static void resolveDynNamePrefix() {
    if (g_dynNamePrefixResolved) return;
    g_dynNamePrefixResolved = true;
    g_dynNamePrefix[0] = '\0';

    typedef void* (*fn_DiscoveryInstance)();
    auto discoveryInstance = (fn_DiscoveryInstance)RESOLVE(0x10059c610);
    typedef void* (*fn_GetSBDiscovery)(void*);
    auto getStageBox = (fn_GetSBDiscovery)RESOLVE(0x10059c9a0);

    void* disc = discoveryInstance();
    if (!disc) { fprintf(stderr, "[MC] Discovery::Instance() returned null\n"); return; }
    void* sbObj = getStageBox(disc);
    if (!sbObj) { fprintf(stderr, "[MC] GetStageBoxDiscoveryObject() returned null\n"); return; }

    // Read C string at sbObj+0x99
    char buf[128] = {0};
    safeRead((uint8_t*)sbObj + 0x99, buf, sizeof(buf) - 1);
    strncpy(g_dynNamePrefix, buf, sizeof(g_dynNamePrefix) - 1);
    fprintf(stderr, "[MC] Dynamics name prefix: '%s'\n", g_dynNamePrefix);
}

// Get the full dynamics unit name for a pool unit index (0-based)
// e.g., for unit 1 → "Dynamics Unit 02" (or "PREFIXDynamics Unit 02" if prefix exists)
static void getDynUnitName(int unitIdx, char* out, size_t outLen) {
    resolveDynNamePrefix();
    snprintf(out, outLen, "%sDynamics Unit %02d", g_dynNamePrefix, unitIdx + 1);
}

// QListData::Data layout for manually constructed lists
struct QListDataHeader {
    int ref;     // atomic ref count
    int alloc;   // allocated slots
    int begin;   // first used slot index
    int end;     // one past last used slot index
    // void* array[] follows immediately
};

// Create a QString from a C string. Returns QStringData* (which IS the QString value).
// Uses Qt5's fromLatin1_helper. Caller must eventually release (or just leak for temp use).
static void* makeQString(const char* str) {
    typedef void* (*fn_fromLatin1)(const char*, int);
    static fn_fromLatin1 fromLatin1 = nullptr;
    if (!fromLatin1) {
        fromLatin1 = (fn_fromLatin1)dlsym(RTLD_DEFAULT, "_ZN7QString17fromLatin1_helperEPKci");
        if (!fromLatin1) {
            fprintf(stderr, "[MC] FATAL: QString::fromLatin1_helper not found!\n");
            return nullptr;
        }
    }
    return fromLatin1(str, (int)strlen(str));
}

// Release a QString (decrement refcount, free if zero).
static void releaseQString(void* qstrData) {
    if (!qstrData) return;
    int* refPtr = (int*)qstrData;
    int ref = *refPtr;
    if (ref == -1) return; // static, never freed
    if (__sync_sub_and_fetch(refPtr, 1) == 0) {
        // refcount reached 0, free it
        free(qstrData);
    }
}

// Build a QList<bool> with one entry on the heap. Returns pointer to the QList (8 bytes).
// The QList is a single pointer to QListDataHeader + array.
static void* makeQListBool(bool val) {
    // QList<bool> stores bool values as void* in the array slots
    uint8_t* buf = (uint8_t*)malloc(sizeof(QListDataHeader) + sizeof(void*));
    auto* hdr = (QListDataHeader*)buf;
    hdr->ref = 1;
    hdr->alloc = 1;
    hdr->begin = 0;
    hdr->end = 1;
    void** arr = (void**)(buf + sizeof(QListDataHeader));
    arr[0] = val ? (void*)1 : (void*)0;
    // The QList itself is just a pointer to this data
    void** qlist = (void**)malloc(sizeof(void*));
    *qlist = buf;
    return qlist;
}

// Build a QList<QString> with one entry on the heap.
static void* makeQListQString(void* qstrData) {
    uint8_t* buf = (uint8_t*)malloc(sizeof(QListDataHeader) + sizeof(void*));
    auto* hdr = (QListDataHeader*)buf;
    hdr->ref = 1;
    hdr->alloc = 1;
    hdr->begin = 0;
    hdr->end = 1;
    void** arr = (void**)(buf + sizeof(QListDataHeader));
    arr[0] = qstrData; // QStringData* stored inline
    void** qlist = (void**)malloc(sizeof(void*));
    *qlist = buf;
    return qlist;
}

// Build sLibraryKey on the heap. 16 bytes: {QString(8), eLibraryLocation(4), eLibraryType(4)}
static void* makeLibraryKey(void* qstrName, uint32_t location, uint32_t type) {
    uint8_t* key = (uint8_t*)calloc(1, 16);
    *(void**)&key[0] = qstrName;        // QString name
    *(uint32_t*)&key[8] = location;     // eLibraryLocation (0=local)
    *(uint32_t*)&key[12] = type;        // eLibraryType (0xb=dynamics)
    return key;
}

// Get QListData::shared_null (empty QList internal pointer)
static void* getQListSharedNull() {
    static void* sharedNull = nullptr;
    if (!sharedNull) {
        sharedNull = dlsym(RTLD_DEFAULT, "_ZN9QListData11shared_nullE");
        if (!sharedNull) fprintf(stderr, "[MC] WARN: QListData::shared_null not found!\n");
    }
    return sharedNull;
}

// Make an empty QList (8 bytes on heap, pointing to shared_null)
static void* makeEmptyQList() {
    void** qlist = (void**)malloc(sizeof(void*));
    *qlist = getQListSharedNull();
    return qlist;
}

// Store current Dyn8 settings from a channel to a library preset.
// unitIdx is the Dyn8 pool unit index (0-based), presetName is the library name.
static bool libraryStoreDyn8(int unitIdx, const char* presetName) {
    if (!g_libraryMgrClient) {
        fprintf(stderr, "[MC] libraryStoreDyn8: no library manager client!\n");
        return false;
    }

    // Construct the dynamics unit target name (same format as DynamicsLibraryForm uses)
    char dynUnitName[128];
    getDynUnitName(unitIdx, dynUnitName, sizeof(dynUnitName));

    void* nameQStr = makeQString(presetName);
    if (!nameQStr) return false;

    void* libKey = makeLibraryKey(nameQStr, 1, 0xb); // location=1 (local), type=dynamics
    void* objNameQStr = makeQString(dynUnitName);
    void* qlistStr = makeQListQString(objNameQStr);
    void* qlistBool = makeEmptyQList(); // empty QList<bool> (same as UI code)
    uint64_t stripKey = 0; // zero-initialized (same as UI ActionAdd code)

    typedef void (*fn_CreateLibrary)(void* client, void* libKey, void* qlistStr, void* qlistBool, uint64_t stripKey);
    auto createLibrary = (fn_CreateLibrary)RESOLVE(0x1006f2020);

    fprintf(stderr, "[MC] libraryStoreDyn8: storing unit %d ('%s') as '%s'...\n",
            unitIdx, dynUnitName, presetName);
    createLibrary(g_libraryMgrClient, libKey, qlistStr, qlistBool, stripKey);
    fprintf(stderr, "[MC] libraryStoreDyn8: CreateLibrary returned OK\n");

    free(*(void**)qlistStr); free(qlistStr);
    free(qlistBool); // shared_null is not freed
    free(libKey);
    return true;
}

// Recall a library preset onto a target channel's Dyn8.
// tgtCh is 0-based channel index. storedObjName is the source unit name used during store.
static bool libraryRecallDyn8(int tgtCh, const char* presetName, const char* storedObjName) {
    if (!g_libraryMgrClient) {
        fprintf(stderr, "[MC] libraryRecallDyn8: no library manager client!\n");
        return false;
    }

    void* nameQStr = makeQString(presetName);
    if (!nameQStr) return false;

    void* libKey = makeLibraryKey(nameQStr, 1, 0xb); // location=1, type=dynamics
    // objectName must match the name stored in the library (source unit name)
    void* objNameQStr = makeQString(storedObjName);
    void* qlistBool = makeEmptyQList();
    uint64_t stripKey = (uint64_t)1 | ((uint64_t)(uint8_t)tgtCh << 32); // input channel

    // RecallObjectFromLibrary(this, &sLibraryKey, eLibraryObject, &QString, &QList<bool>, sChannelStripKey, bool)
    typedef void (*fn_RecallFromLib)(void* client, void* libKey, uint32_t libObj,
                                      void* qstr, void* qlistBool, uint64_t stripKey, bool flag);
    auto recallFromLib = (fn_RecallFromLib)RESOLVE(0x1006f3f80);

    fprintf(stderr, "[MC] libraryRecallDyn8: recalling '%s' (obj='%s') onto ch %d...\n",
            presetName, storedObjName, tgtCh+1);
    recallFromLib(g_libraryMgrClient, libKey, 0x0f, &objNameQStr, qlistBool, stripKey, false);
    fprintf(stderr, "[MC] libraryRecallDyn8: RecallObjectFromLibrary returned OK\n");

    free(qlistBool);
    free(libKey);
    return true;
}

// Delete a library preset.
static bool libraryDeleteDyn8(const char* presetName) {
    if (!g_libraryMgrClient) return false;
    void* nameQStr = makeQString(presetName);
    if (!nameQStr) return false;

    void* libKey = makeLibraryKey(nameQStr, 1, 0xb); // location=1

    typedef void (*fn_DeleteLibrary)(void* client, void* libKey);
    auto deleteLibrary = (fn_DeleteLibrary)RESOLVE(0x1006f1cb0);

    fprintf(stderr, "[MC] libraryDeleteDyn8: deleting '%s'...\n", presetName);
    deleteLibrary(g_libraryMgrClient, libKey);
    fprintf(stderr, "[MC] libraryDeleteDyn8: done\n");

    free(libKey);
    return true;
}

static void probeLibraryTypesForChannel(int ch) {
    typedef uint8_t (*fn_GetLibraryObjectIndex)(uint32_t type, uint32_t object);
    auto getLibraryObjectIndex = (fn_GetLibraryObjectIndex)RESOLVE(0x1005a1c70);
    if (!getLibraryObjectIndex) return;

    struct ProbeObj { uint32_t obj; const char* name; };
    static const ProbeObj objs[] = {
        {0, "Trim"},
        {1, "HPF"},
        {2, "LPF"},
        {3, "Gate"},
        {4, "GateSC"},
        {5, "PEQ"},
        {6, "Comp"},
        {7, "Delay"},
        {8, "Preamp"},
        {12, "StereoImage"},
        {13, "PreampModel"},
        {15, "Dyn8"},
        {16, "Patching"},
    };

    fprintf(stderr, "[MC] Library type probe for ch %d...\n", ch + 1);
    for (uint32_t type = 0; type < 24; type++) {
        bool any = false;
        fprintf(stderr, "[MC]   type %u:", type);
        for (const auto& obj : objs) {
            uint8_t idx = getLibraryObjectIndex(type, obj.obj);
            if (idx == 0xff) continue;
            any = true;
            fprintf(stderr, " %s=%u", obj.name, idx);
        }
        if (!any)
            fprintf(stderr, " (no input-ish objects)");
        fprintf(stderr, "\n");
    }
}

static void* makeQListBoolN(size_t count, bool val) {
    uint8_t* buf = (uint8_t*)malloc(sizeof(QListDataHeader) + sizeof(void*) * count);
    auto* hdr = (QListDataHeader*)buf;
    hdr->ref = 1;
    hdr->alloc = (int)count;
    hdr->begin = 0;
    hdr->end = (int)count;
    void** arr = (void**)(buf + sizeof(QListDataHeader));
    for (size_t i = 0; i < count; i++)
        arr[i] = val ? (void*)1 : (void*)0;
    void** qlist = (void**)malloc(sizeof(void*));
    *qlist = buf;
    return qlist;
}

static void* makeQListQStringN(const std::vector<void*>& qstrs) {
    uint8_t* buf = (uint8_t*)malloc(sizeof(QListDataHeader) + sizeof(void*) * qstrs.size());
    auto* hdr = (QListDataHeader*)buf;
    hdr->ref = 1;
    hdr->alloc = (int)qstrs.size();
    hdr->begin = 0;
    hdr->end = (int)qstrs.size();
    void** arr = (void**)(buf + sizeof(QListDataHeader));
    for (size_t i = 0; i < qstrs.size(); i++)
        arr[i] = qstrs[i];
    void** qlist = (void**)malloc(sizeof(void*));
    *qlist = buf;
    return qlist;
}

static void* getChannelLibraryTargetQString(uint32_t libType, uint32_t libObj, uint64_t stripKey) {
    typedef void (*fn_GetTargetName)(void* retQStr, uint32_t libType, uint32_t libObj, uint64_t stripKey);
    auto getTargetName = (fn_GetTargetName)RESOLVE(0x1000d88f0);
    if (!getTargetName) return nullptr;
    void* qstr = nullptr;
    getTargetName(&qstr, libType, libObj, stripKey);
    return qstr;
}

static const uint32_t kInputChannelLibraryType = 7;
static const uint32_t kInputChannelLibraryObjects[] = {
    0, 1, 2, 3, 4, 5, 6, 7, 8, 12, 13,
};

static bool libraryStoreInputChannel(int srcCh, const char* presetName) {
    if (!g_libraryMgrClient) return false;

    uint64_t stripKey = MAKE_KEY(1, (uint8_t)srcCh);
    std::vector<void*> targets;
    for (uint32_t obj : kInputChannelLibraryObjects) {
        void* qstr = getChannelLibraryTargetQString(kInputChannelLibraryType, obj, stripKey);
        if (qstr) targets.push_back(qstr);
    }
    if (targets.empty()) return false;

    void* nameQStr = makeQString(presetName);
    void* libKey = makeLibraryKey(nameQStr, 1, kInputChannelLibraryType);
    void* qlistStr = makeQListQStringN(targets);
    void* qlistBool = makeQListBoolN(targets.size(), true);

    typedef void (*fn_CreateLibrary)(void* client, void* libKey, void* qlistStr, void* qlistBool, uint64_t stripKey);
    auto createLibrary = (fn_CreateLibrary)RESOLVE(0x1006f2020);
    fprintf(stderr, "[MC] libraryStoreInputChannel: storing ch %d as '%s' (%zu objs)\n",
            srcCh + 1, presetName, targets.size());
    createLibrary(g_libraryMgrClient, libKey, qlistStr, qlistBool, stripKey);

    free(*(void**)qlistStr); free(qlistStr);
    free(*(void**)qlistBool); free(qlistBool);
    free(libKey);
    return true;
}

static bool libraryRecallInputChannel(int tgtCh, const char* presetName) {
    if (!g_libraryMgrClient) return false;

    uint64_t stripKey = MAKE_KEY(1, (uint8_t)tgtCh);
    void* nameQStr = makeQString(presetName);
    void* libKey = makeLibraryKey(nameQStr, 1, kInputChannelLibraryType);
    typedef void (*fn_RecallFromLib)(void* client, void* libKey, uint32_t libObj,
                                     void* objNameQStrPtr, void* qlistBool, uint64_t stripKey, bool);
    auto recallFromLib = (fn_RecallFromLib)RESOLVE(0x1006f3f80);

    fprintf(stderr, "[MC] libraryRecallInputChannel: recalling '%s' onto ch %d\n",
            presetName, tgtCh + 1);
    for (uint32_t obj : kInputChannelLibraryObjects) {
        void* objNameQStr = getChannelLibraryTargetQString(kInputChannelLibraryType, obj, stripKey);
        if (!objNameQStr) continue;
        void* qlistBool = makeEmptyQList();
        recallFromLib(g_libraryMgrClient, libKey, obj, &objNameQStr, qlistBool, stripKey, false);
        free(qlistBool);
    }

    free(libKey);
    return true;
}

static bool libraryDeleteInputChannel(const char* presetName) {
    if (!g_libraryMgrClient) return false;
    void* nameQStr = makeQString(presetName);
    if (!nameQStr) return false;
    void* libKey = makeLibraryKey(nameQStr, 1, kInputChannelLibraryType);
    typedef void (*fn_DeleteLibrary)(void* client, void* libKey);
    auto deleteLibrary = (fn_DeleteLibrary)RESOLVE(0x1006f1cb0);
    fprintf(stderr, "[MC] libraryDeleteInputChannel: deleting '%s'\n", presetName);
    deleteLibrary(g_libraryMgrClient, libKey);
    free(libKey);
    return true;
}

static void* getInputChannel(int ch) {
    void* ptr = nullptr;
    safeRead(&g_dmFields[g_firstInputChIdx + ch], &ptr, sizeof(ptr));
    return ptr;
}

static bool isChannelStereo(int ch) {
    void* helpers = g_CPRHelpersInstance();
    if (!helpers) return false;
    uint64_t key = MAKE_KEY(1, (uint8_t)ch);
    return g_channelIsStereo(helpers, key);
}

// Forward declaration for safeWrite (defined later)
static bool safeWrite(void* addr, const void* src, size_t len);
static void waitForStereoConfigReset();

// =============================================================================
// Stereo Configuration helpers
// =============================================================================
// Stereo config: 64-byte array at sbObj+0x21e (one byte per channel pair)
// Pair index = ch / 2. Non-zero = stereo, zero = mono pair.
// gDRIdentification+0xa8 → sIPStereoConfigurationData (same memory)

// Read the current stereo config (64 bytes) from the StageBox discovery object.
static bool readStereoConfig(uint8_t config[64]) {
    typedef void* (*fn_DiscoveryInstance)();
    auto discoveryInstance = (fn_DiscoveryInstance)RESOLVE(0x10059c610);
    typedef void* (*fn_GetSBDiscovery)(void*);
    auto getStageBox = (fn_GetSBDiscovery)RESOLVE(0x10059c9a0);

    void* disc = discoveryInstance();
    if (!disc) { fprintf(stderr, "[MC] readStereoConfig: Discovery null\n"); return false; }
    void* sbObj = getStageBox(disc);
    if (!sbObj) { fprintf(stderr, "[MC] readStereoConfig: sbObj null\n"); return false; }

    return safeRead((uint8_t*)sbObj + 0x21e, config, 64);
}

// Write stereo config (64 bytes) to the StageBox discovery object.
static bool writeStereoConfig(const uint8_t config[64]) {
    typedef void* (*fn_DiscoveryInstance)();
    auto discoveryInstance = (fn_DiscoveryInstance)RESOLVE(0x10059c610);
    typedef void* (*fn_GetSBDiscovery)(void*);
    auto getStageBox = (fn_GetSBDiscovery)RESOLVE(0x10059c9a0);

    void* disc = discoveryInstance();
    if (!disc) return false;
    void* sbObj = getStageBox(disc);
    if (!sbObj) return false;

    return safeWrite((uint8_t*)sbObj + 0x21e, config, 64);
}

// Change a channel pair's stereo status and apply.
// This calls NewInputStereoConfiguration which resets ALL settings on changed channels!
// Caller should snapshot settings BEFORE calling this.
// ch: 0-based channel number (pair index = ch/2)
// makeStereo: true = make stereo, false = make mono
static bool changeStereoConfig(int ch, bool makeStereo) {
    int pair = ch / 2;
    if (pair < 0 || pair >= 64) return false;

    uint8_t config[64];
    if (!readStereoConfig(config)) {
        fprintf(stderr, "[MC] changeStereoConfig: failed to read current config\n");
        return false;
    }

    bool currentStereo = config[pair] != 0;
    if (currentStereo == makeStereo) {
        fprintf(stderr, "[MC] changeStereoConfig: ch %d pair %d already %s\n",
                ch+1, pair, makeStereo ? "stereo" : "mono");
        return true;  // nothing to do
    }

    fprintf(stderr, "[MC] changeStereoConfig: ch %d pair %d: %s → %s\n",
            ch+1, pair, currentStereo ? "stereo" : "mono",
            makeStereo ? "stereo" : "mono");

    // Modify the config byte
    config[pair] = makeStereo ? 1 : 0;

    if (!sendStereoConfigViaDiscovery(config, "[MC] changeStereoConfig")) {
        fprintf(stderr, "[MC] changeStereoConfig: failed to send config via discovery\n");
        return false;
    }
    waitForStereoConfigMatch(config, 5000, "[MC] changeStereoConfig");
    waitForStereoConfigReset();
    return true;
}

// Stereo-aware move: change stereo config at destination to match source,
// preserving Type A settings via snapshot/recall.
// srcCh, dstCh: 0-based channel numbers
// Returns true if config was changed (and settings need to be re-recalled)
static bool alignStereoConfig(int srcCh, int dstCh) {
    bool srcStereo = isChannelStereo(srcCh);
    bool dstStereo = isChannelStereo(dstCh);

    if (srcStereo == dstStereo) return false;  // already aligned

    fprintf(stderr, "[MC] alignStereoConfig: src ch %d (%s) → dst ch %d (%s)\n",
            srcCh+1, srcStereo ? "ST" : "M",
            dstCh+1, dstStereo ? "ST" : "M");

    // Change destination pair to match source
    return changeStereoConfig(dstCh, srcStereo);
}

// Get the cInsertNetObject for a channel's InsertA (ip=0) or InsertB (ip=1)
// Located at inputCh[12+ip]→driver[1]
static void* getInsertNetObj(int ch, int ip) {
    void* inputCh = getInputChannel(ch);
    if (!inputCh) return nullptr;
    int chIdx = 12 + ip;
    void** drvArr = nullptr;
    safeRead((uint8_t*)inputCh + 0x28 + chIdx * 8, &drvArr, sizeof(drvArr));
    if (!drvArr) return nullptr;
    void* insertNetObj = nullptr;
    safeRead(&drvArr[1], &insertNetObj, sizeof(insertNetObj));
    return insertNetObj;
}

// Get pointer to sInputAttributes for channel ch (0-127)
// Path: wrapper+0x90+group*8 → mixer+0x200 → attrs + ch_in_grp*0xAC8
static uint8_t* getInputAttrsPtr(int ch) {
    if (!g_inputMixerWrapper) return nullptr;
    int group = ch >> 3;       // ch / 8
    int chInGrp = ch & 7;     // ch % 8

    void* mixer = nullptr;
    safeRead((uint8_t*)g_inputMixerWrapper + 0x90 + group * 8, &mixer, sizeof(mixer));
    if (!mixer) return nullptr;

    void* attrs = nullptr;
    safeRead((uint8_t*)mixer + 0x200, &attrs, sizeof(attrs));
    if (!attrs) return nullptr;

    return (uint8_t*)attrs + chInGrp * SINPUTATTRS_SIZE;
}

static void* getProcessingObj(void* inputCh, int offset) {
    void** fields = (void**)inputCh;
    void* obj = nullptr;
    safeRead(&fields[offset], &obj, sizeof(obj));
    return obj;
}

// Find processing object by vtable scan (for objects at variable offsets)
static void* findProcessingObjByVtable(void* inputCh, uintptr_t vtableStatic, int* foundIdx = nullptr) {
    void* expectedVt = (void*)((uintptr_t)RESOLVE(vtableStatic) + 16);
    void** fields = (void**)inputCh;
    // Scan typical processing object offsets (skip 0-1 which are vtable/base, and very high offsets)
    for (int i = 2; i < 800; i++) {
        void* field = nullptr;
        if (!safeRead(&fields[i], &field, sizeof(field))) continue;
        if (!field || (uintptr_t)field < 0x100000000ULL || (uintptr_t)field > 0x800000000000ULL) continue;
        void* vt = nullptr;
        if (!safeRead(field, &vt, sizeof(vt))) continue;
        if (vt == expectedVt) {
            if (foundIdx) *foundIdx = i;
            return field;
        }
    }
    return nullptr;
}

// Get Type B processing object (fixed offset or vtable scan, with optional driver indirection)
static void* getTypeBObj(void* inputCh, const ProcDescB& desc) {
    void* obj = nullptr;
    if (desc.chOffset >= 0) {
        obj = getProcessingObj(inputCh, desc.chOffset);
    } else {
        obj = findProcessingObjByVtable(inputCh, desc.vtableStatic);
    }
    // If subFieldIdx > 0, obj is a driver — deref to get the actual net object
    if (obj && desc.subFieldIdx > 0) {
        void** driverFields = (void**)obj;
        void* netObj = nullptr;
        safeRead(&driverFields[desc.subFieldIdx], &netObj, sizeof(netObj));
        return netObj;
    }
    return obj;
}

// Forward declaration
static bool safeWrite(void* addr, const void* src, size_t len);

// =============================================================================
// Patching helpers (cChannelMapperBase)
// =============================================================================
// Layout: mapper+0x80 → uint32_t[128] activeInputChannelSourceType
//         mapper+0x88 → sAudioSource[128] (type 0: local analogue)
//         mapper+0x90 → sAudioSource[128] (type 1)
//         mapper+0x98 → sAudioSource[128] (type 2)
//         mapper+0xa0 → sAudioSource[128] (type 3)
static bool readPatchData(int ch, PatchData& pd) {
    if (!g_channelMapper || ch < 0 || ch > 127) return false;
    uint8_t* base = (uint8_t*)g_channelMapper;

    void* sourceTypeArr = nullptr;
    if (!safeRead(base + 0x80, &sourceTypeArr, sizeof(sourceTypeArr)) || !sourceTypeArr) {
        fprintf(stderr, "[MC]   readPatch ch %d: sourceTypeArr failed\n", ch);
        return false;
    }
    if (!safeRead((uint8_t*)sourceTypeArr + ch * 4, &pd.sourceType, 4)) {
        fprintf(stderr, "[MC]   readPatch ch %d: sourceType read failed\n", ch);
        return false;
    }

    if (pd.sourceType > 4) {
        fprintf(stderr, "[MC]   readPatch ch %d: sourceType=%d out of range\n", ch, pd.sourceType);
        return false;
    }

    void* sourceArr = nullptr;
    int arrOffset = 0x88 + pd.sourceType * 8;
    if (!safeRead(base + arrOffset, &sourceArr, sizeof(sourceArr)) || !sourceArr) {
        fprintf(stderr, "[MC]   readPatch ch %d: sourceArr failed (offset=0x%x)\n", ch, arrOffset);
        return false;
    }
    if (!safeRead((uint8_t*)sourceArr + ch * sizeof(sAudioSource), &pd.source, sizeof(sAudioSource))) {
        fprintf(stderr, "[MC]   readPatch ch %d: source read failed\n", ch);
        return false;
    }

    return true;
}

static bool writePatchData(int ch, const PatchData& pd) {
    if (!g_channelMapper || ch < 0 || ch > 127) return false;
    uint8_t* base = (uint8_t*)g_channelMapper;

    void* sourceTypeArr = nullptr;
    if (!safeRead(base + 0x80, &sourceTypeArr, sizeof(sourceTypeArr)) || !sourceTypeArr) return false;
    if (!safeWrite((uint8_t*)sourceTypeArr + ch * 4, &pd.sourceType, 4)) return false;

    if (pd.sourceType > 4) return false;

    void* sourceArr = nullptr;
    int arrOffset = 0x88 + pd.sourceType * 8;
    if (!safeRead(base + arrOffset, &sourceArr, sizeof(sourceArr)) || !sourceArr) return false;
    if (!safeWrite((uint8_t*)sourceArr + ch * sizeof(sAudioSource), &pd.source, sizeof(sAudioSource))) return false;

    return true;
}

// =============================================================================
// Preamp helpers (cAnalogueInput in RegistryRouter local table)
// =============================================================================
// cAnalogueInput layout: +0x98→gain_ptr(int16), +0xa0→pad_ptr(bool), +0xa8→phantom_ptr(bool)
// Found at router+0x3a9820[g_firstAnalogueInputIdx + channel]
// MIDISetGain/MIDISetPad/MIDISetPhantomPower work offline via InformOtherObjects

struct PreampData {
    int16_t gain;
    uint8_t pad;
    uint8_t phantom;
};

static bool samePreampData(const PreampData& a, const PreampData& b) {
    return a.gain == b.gain && a.pad == b.pad && a.phantom == b.phantom;
}

static bool isLocalAnaloguePatch(const PatchData& pd) {
    return pd.sourceType == 0 && pd.source.type == 0;
}

static void* getAnalogueInput(int socketNum) {
    if (!g_registryRouter || g_firstAnalogueInputIdx < 0 || socketNum < 0 || socketNum > 127) return nullptr;
    uint8_t* base = (uint8_t*)g_registryRouter + 0x3a9820;
    void* entry = nullptr;
    safeRead(base + (g_firstAnalogueInputIdx + socketNum) * 8, &entry, sizeof(entry));
    return entry;
}

static bool readPreampDataForSocket(int socketNum, PreampData& pd) {
    void* ai = getAnalogueInput(socketNum);
    if (!ai) return false;

    void* gainPtr = nullptr;
    safeRead((uint8_t*)ai + 0x98, &gainPtr, sizeof(gainPtr));
    if (!gainPtr) return false;
    safeRead(gainPtr, &pd.gain, sizeof(pd.gain));

    void* padPtr = nullptr;
    safeRead((uint8_t*)ai + 0xa0, &padPtr, sizeof(padPtr));
    if (padPtr) safeRead(padPtr, &pd.pad, sizeof(pd.pad));
    else pd.pad = 0;

    void* phantomPtr = nullptr;
    safeRead((uint8_t*)ai + 0xa8, &phantomPtr, sizeof(phantomPtr));
    if (phantomPtr) safeRead(phantomPtr, &pd.phantom, sizeof(pd.phantom));
    else pd.phantom = 0;

    return true;
}

static bool readPreampDataForPatch(const PatchData& pd, PreampData& preamp) {
    if (!isLocalAnaloguePatch(pd)) return false;
    return readPreampDataForSocket((int)pd.source.number, preamp);
}

static bool writePreampDataForSocket(int socketNum, const PreampData& pd) {
    void* ai = getAnalogueInput(socketNum);
    if (!ai) return false;

    // Use MIDISetGain / MIDISetPad / MIDISetPhantomPower for proper notification
    typedef void (*fn_MIDISetGain)(void*, int16_t);
    typedef void (*fn_MIDISetPad)(void*, bool);
    typedef void (*fn_MIDISetPhantom)(void*, bool);

    auto midiSetGain = (fn_MIDISetGain)RESOLVE(0x1004ecf80);
    auto midiSetPad = (fn_MIDISetPad)RESOLVE(0x1004ed020);
    auto midiSetPhantom = (fn_MIDISetPhantom)RESOLVE(0x1004ed0a0);

    midiSetGain(ai, pd.gain);
    midiSetPad(ai, pd.pad != 0);
    midiSetPhantom(ai, pd.phantom != 0);

    return true;
}

static bool writePreampDataForPatch(const PatchData& pd, const PreampData& preamp) {
    if (!isLocalAnaloguePatch(pd)) return false;
    return writePreampDataForSocket((int)pd.source.number, preamp);
}

// =============================================================================
// Channel Snapshot
// =============================================================================
// Type B field data stored as raw bytes in big-endian message format
struct TypeBData {
    uint8_t buf[16];  // max message data (largest is 7 bytes)
    int     len;
};

struct ChannelSnapshot {
    // Type A: full cAHNetMessage objects (for FillGetStatus/DirectlyRecallStatus)
    uint8_t* msgA[NUM_PROC_A];
    bool     validA[NUM_PROC_A];

    // Type B: serialized message data ready for SetStatus
    TypeBData dataB[NUM_PROC_B];
    bool      validB[NUM_PROC_B];

    // Mixer data: sInputAttributes (sends, mutes, pan, DCA assigns, etc.)
    uint8_t* mixerData;  // SINPUTATTRS_SIZE bytes, heap-allocated
    bool     validMixer;

    // Patching data (for Scenario B)
    PatchData patchData;
    bool      validPatch;

    // Preamp data (gain, pad, phantom)
    PreampData preampData;
    bool       validPreamp;

    // Insert routing: specific audio send/receive points for each insert
    // [0] = Insert A, [1] = Insert B
    struct InsertInfo {
        void*   fxUnit;       // cFXUnit* (null if no FX insert)
        void*   fxSendPt;     // FX output send point (connected to channel's return)
        void*   fxReceivePt;  // FX input receive point (target of channel's send)
        int     parentType;   // GetParentType() result: 2=FXUnit, 6=AHFXUnit, -1=external/none
        bool    hasInsert;    // channel->HasInserts(insertPoint)
    } insertInfo[2];

    // Dyn8 pool dynamics settings — single cDynamicsNetObject per unit (64 total)
    // sDynamicsData = raw memory at obj+0x98..+0x12b (0x94 = 148 bytes)
    int      dyn8UnitIdx;   // Dyn8 pool unit index (0-63), or -1 if no Dyn8
    bool     validDyn8;
    uint8_t  dyn8Data[0x94]; // sDynamicsData snapshot from obj+0x98

    char     name[256];
    uint8_t  colour;
    bool     isStereo;    // stereo status at snapshot time

    ChannelSnapshot() {
        memset(this, 0, sizeof(*this));
        dyn8UnitIdx = -1;
    }
};

// Read a Type B field from an object.
// PTR types: obj+offset → read pointer → read value from pointer
// DIRECT types: obj+offset → read value directly from object
// Writes to buf at msgDataOffset in big-endian format
static bool readTypeBField(void* obj, const FieldDesc& f, uint8_t* buf) {
    uint8_t* base = (uint8_t*)obj;

    switch (f.type) {
        // --- Pointer-dereference types (cAudioObject subclasses) ---
        case FT_UBYTE: {
            void* ptr = nullptr;
            if (!safeRead(base + f.objOffset, &ptr, sizeof(ptr))) return false;
            if (!ptr) return false;
            uint8_t val = 0;
            safeRead(ptr, &val, 1);
            buf[f.msgDataOffset] = val;
            break;
        }
        case FT_UBYTE_BOOL: {
            void* ptr = nullptr;
            if (!safeRead(base + f.objOffset, &ptr, sizeof(ptr))) return false;
            if (!ptr) return false;
            uint8_t val = 0;
            safeRead(ptr, &val, 1);
            buf[f.msgDataOffset] = val ? 1 : 0;
            break;
        }
        case FT_SWORD:
        case FT_UWORD: {
            void* ptr = nullptr;
            if (!safeRead(base + f.objOffset, &ptr, sizeof(ptr))) return false;
            if (!ptr) return false;
            uint16_t val = 0;
            safeRead(ptr, &val, 2);
            buf[f.msgDataOffset]     = (uint8_t)(val >> 8);
            buf[f.msgDataOffset + 1] = (uint8_t)(val & 0xFF);
            break;
        }
        // --- Direct access types (cNetObject subclasses) ---
        case FT_DIRECT_UBYTE: {
            uint8_t val = 0;
            if (!safeRead(base + f.objOffset, &val, 1)) return false;
            buf[f.msgDataOffset] = val;
            break;
        }
        case FT_DIRECT_UBYTE_BOOL: {
            uint8_t val = 0;
            if (!safeRead(base + f.objOffset, &val, 1)) return false;
            buf[f.msgDataOffset] = val ? 1 : 0;
            break;
        }
        case FT_DIRECT_SWORD:
        case FT_DIRECT_UWORD: {
            uint16_t val = 0;
            if (!safeRead(base + f.objOffset, &val, 2)) return false;
            buf[f.msgDataOffset]     = (uint8_t)(val >> 8);
            buf[f.msgDataOffset + 1] = (uint8_t)(val & 0xFF);
            break;
        }
    }
    return true;
}

// Write Type B field values directly to object (bypasses SetStatus which hangs)
// Uses vm_write for safety — if the write would segfault, it fails gracefully instead.
static bool safeWrite(void* addr, const void* src, size_t len) {
    kern_return_t kr = vm_write(
        mach_task_self(),
        (vm_address_t)addr,
        (vm_address_t)src,
        (mach_msg_type_number_t)len);
    return kr == KERN_SUCCESS;
}

static void waitForStereoConfigReset() {
    // Stereo reconfiguration rebuilds parts of the input-channel object graph
    // asynchronously. A short settle window avoids recalling into half-reset
    // objects, which can leave the right-hand channel of a former stereo pair
    // mirroring stale state from its neighbor.
    QApplication::processEvents();
    usleep(500 * 1000);
    QApplication::processEvents();
}

static void writeTypeBFields(void* obj, const ProcDescB& desc, const uint8_t* buf) {
    uint8_t* base = (uint8_t*)obj;
    for (int f = 0; f < desc.numFields; f++) {
        const FieldDesc& fd = desc.fields[f];

        switch (fd.type) {
            // --- Pointer-dereference types ---
            case FT_UBYTE: {
                void* ptr = nullptr;
                if (!safeRead(base + fd.objOffset, &ptr, sizeof(ptr))) continue;
                if (!ptr || (uintptr_t)ptr < 0x100000000ULL || (uintptr_t)ptr > 0x800000000000ULL) continue;
                uint8_t val = buf[fd.msgDataOffset];
                if (!safeWrite(ptr, &val, 1))
                    fprintf(stderr, "[MC]     WARN: write failed %s field %d ptr=%p\n", desc.name, f, ptr);
                break;
            }
            case FT_UBYTE_BOOL: {
                void* ptr = nullptr;
                if (!safeRead(base + fd.objOffset, &ptr, sizeof(ptr))) continue;
                if (!ptr || (uintptr_t)ptr < 0x100000000ULL || (uintptr_t)ptr > 0x800000000000ULL) continue;
                uint8_t val = buf[fd.msgDataOffset] ? 1 : 0;
                if (!safeWrite(ptr, &val, 1))
                    fprintf(stderr, "[MC]     WARN: write failed %s field %d ptr=%p\n", desc.name, f, ptr);
                break;
            }
            case FT_SWORD:
            case FT_UWORD: {
                void* ptr = nullptr;
                if (!safeRead(base + fd.objOffset, &ptr, sizeof(ptr))) continue;
                if (!ptr || (uintptr_t)ptr < 0x100000000ULL || (uintptr_t)ptr > 0x800000000000ULL) continue;
                uint16_t val = ((uint16_t)buf[fd.msgDataOffset] << 8) |
                               (uint16_t)buf[fd.msgDataOffset + 1];
                if (!safeWrite(ptr, &val, 2))
                    fprintf(stderr, "[MC]     WARN: write failed %s field %d ptr=%p\n", desc.name, f, ptr);
                break;
            }
            // --- Direct access types ---
            case FT_DIRECT_UBYTE: {
                uint8_t old = 0;
                if (!safeRead(base + fd.objOffset, &old, 1)) continue;
                uint8_t val = buf[fd.msgDataOffset];
                if (!safeWrite(base + fd.objOffset, &val, 1))
                    fprintf(stderr, "[MC]     WARN: direct write failed %s field %d\n", desc.name, f);
                break;
            }
            case FT_DIRECT_UBYTE_BOOL: {
                uint8_t old = 0;
                if (!safeRead(base + fd.objOffset, &old, 1)) continue;
                uint8_t val = buf[fd.msgDataOffset] ? 1 : 0;
                if (!safeWrite(base + fd.objOffset, &val, 1))
                    fprintf(stderr, "[MC]     WARN: direct write failed %s field %d\n", desc.name, f);
                break;
            }
            case FT_DIRECT_SWORD:
            case FT_DIRECT_UWORD: {
                uint16_t old = 0;
                if (!safeRead(base + fd.objOffset, &old, 2)) continue;
                uint16_t val = ((uint16_t)buf[fd.msgDataOffset] << 8) |
                               (uint16_t)buf[fd.msgDataOffset + 1];
                if (!safeWrite(base + fd.objOffset, &val, 2))
                    fprintf(stderr, "[MC]     WARN: direct write failed %s field %d\n", desc.name, f);
                break;
            }
        }
    }
}

static bool snapshotChannel(int ch, ChannelSnapshot& snap) {
    void* inputCh = getInputChannel(ch);
    if (!inputCh) { fprintf(stderr, "[MC] Ch %d: InputChannel is null!\n", ch); return false; }

    // Type A: FillGetStatus → set version → store message
    for (int p = 0; p < NUM_PROC_A; p++) {
        snap.validA[p] = false;
        void* obj = getProcessingObj(inputCh, g_procA[p].chOffset);
        if (!obj) continue;

        snap.msgA[p] = new uint8_t[MSG_BUF_SIZE];
        memset(snap.msgA[p], 0, MSG_BUF_SIZE);
        g_msgCtorCap(snap.msgA[p], 512);

        auto fillGS = (fn_method_msg)RESOLVE(g_procA[p].fillGetStatusAddr);
        fillGS(obj, snap.msgA[p]);

        // Set version=10 so DirectlyRecallStatus accepts the data
        uint32_t version = 0x0a;
        memcpy(snap.msgA[p] + 0x1c, &version, 4);

        snap.validA[p] = true;
    }

    // Type B: read fields directly from object (GetStatus hangs — calls SyscallSendMessage)
    for (int p = 0; p < NUM_PROC_B; p++) {
        snap.validB[p] = false;
        void* obj = getTypeBObj(inputCh, g_procB[p]);
        if (!obj) {
            if (p == 2) { // ProcOrder behaves like a default-false flag when absent
                memset(snap.dataB[p].buf, 0, sizeof(snap.dataB[p].buf));
                snap.dataB[p].buf[0] = g_procB[p].versionByte;
                snap.dataB[p].len = g_procB[p].msgLength;
                snap.dataB[p].buf[1] = 0;
                snap.validB[p] = true;
            }
            continue;
        }

        memset(snap.dataB[p].buf, 0, sizeof(snap.dataB[p].buf));
        snap.dataB[p].buf[0] = g_procB[p].versionByte;
        snap.dataB[p].len = g_procB[p].msgLength;

        bool ok = true;
        for (int f = 0; f < g_procB[p].numFields; f++) {
            if (!readTypeBField(obj, g_procB[p].fields[f], snap.dataB[p].buf)) {
                ok = false;
                break;
            }
        }
        if (!ok && p == 2) {
            snap.dataB[p].buf[1] = 0;
            snap.validB[p] = true;
        } else {
            snap.validB[p] = ok;
        }
        if (ok && strstr(g_procB[p].name, "SideChain")) {
            fprintf(stderr, "[MC]   Snapshot %s ch %d: stripType=%d channel=%d\n",
                    g_procB[p].name, ch+1, snap.dataB[p].buf[1], snap.dataB[p].buf[2]);
        }
        if (ok && strstr(g_procB[p].name, "DigitalTrim")) {
            uint16_t gain = ((uint16_t)snap.dataB[p].buf[1] << 8) | snap.dataB[p].buf[2];
            fprintf(stderr, "[MC]   Snapshot %s ch %d: gain=%d (0x%04x)\n",
                    g_procB[p].name, ch+1, (int16_t)gain, gain);
        }
        if (ok && strcmp(g_procB[p].name, "StereoImage") == 0) {
            uint16_t width = ((uint16_t)snap.dataB[p].buf[1] << 8) | snap.dataB[p].buf[2];
            uint8_t mode = snap.dataB[p].buf[3];
            fprintf(stderr, "[MC]   Snapshot %s ch %d: width=%u mode=%u\n",
                    g_procB[p].name, ch+1, width, mode);
        }
        if (!ok) {
            fprintf(stderr, "[MC]   Snapshot %s ch %d: FAILED (obj=%p)\n", g_procB[p].name, ch+1, obj);
        }
    }

    // Mixer data: copy sInputAttributes (sends, fader, mute, DCA, matrix, etc.)
    snap.validMixer = false;
    snap.mixerData = nullptr;
    uint8_t* attrsPtr = getInputAttrsPtr(ch);
    if (attrsPtr) {
        snap.mixerData = new uint8_t[SINPUTATTRS_SIZE];
        if (safeRead(attrsPtr, snap.mixerData, SINPUTATTRS_SIZE)) {
            snap.validMixer = true;
        } else {
            delete[] snap.mixerData;
            snap.mixerData = nullptr;
        }
    }
    // Patching
    snap.validPatch = readPatchData(ch, snap.patchData);
    if (snap.validPatch)
        fprintf(stderr, "[MC]   Snapshot patch ch %d: srcType=%d src={type=%d, num=%d}\n",
                ch+1, snap.patchData.sourceType, snap.patchData.source.type, snap.patchData.source.number);

    // Preamp lives on the patched socket, not on the destination channel index.
    snap.validPreamp = snap.validPatch && readPreampDataForPatch(snap.patchData, snap.preampData);

    // Insert routing: find FX unit assigned to each insert point
    // Chain: cChannel::GetInsertReturnPoint(insertPt) → returnPt+0x20 → sendPt
    //        → sendPt->GetParentType() → if 2 or 6: sendPt+0x30 - 0xa8 = cFXUnit*
    if (g_channelManager) {
        typedef void* (*fn_GetChannel)(void* mgr, uint32_t stripType, uint8_t chNum);
        auto getChannel = (fn_GetChannel)RESOLVE(0x1006e3f90);
        typedef bool (*fn_HasInserts)(void* channel, int insertPoint);
        auto hasInserts = (fn_HasInserts)RESOLVE(0x1006df5e0);
        typedef void* (*fn_GetInsertReturnPoint)(void* channel, int insertPoint);
        auto getReturnPoint = (fn_GetInsertReturnPoint)RESOLVE(0x1006d9850);
        typedef int (*fn_GetParentType)(void* sendPoint);
        auto getParentType = (fn_GetParentType)RESOLVE(0x1006cd690);
        typedef void* (*fn_GetSendPoint)(void* channel, int insertPoint);
        auto getSendPoint = (fn_GetSendPoint)RESOLVE(0x1006d9780);
        typedef void* (*fn_GetFirstRecvPt)(void* sendPoint);
        auto getFirstRecvPt = (fn_GetFirstRecvPt)RESOLVE(0x1006cd7b0);

        void* cChannel = getChannel(g_channelManager, 1, (uint8_t)ch);
        for (int ip = 0; ip < 2; ip++) {
            snap.insertInfo[ip] = {nullptr, nullptr, nullptr, -1, false};
            if (!cChannel) continue;
            if (!hasInserts(cChannel, ip)) continue;
            snap.insertInfo[ip].hasInsert = true;

            // Get FX output → channel return connection (return source)
            void* returnPt = getReturnPoint(cChannel, ip);
            if (!returnPt) continue;
            void* connSendPt = nullptr;  // FX output send point
            safeRead((uint8_t*)returnPt + 0x20, &connSendPt, sizeof(connSendPt));
            if (!connSendPt) continue;

            int pType = getParentType(connSendPt);
            snap.insertInfo[ip].parentType = pType;
            snap.insertInfo[ip].fxSendPt = connSendPt;  // FX output

            // Get channel send → FX input connection (send target)
            void* chSendPt = getSendPoint(cChannel, ip);
            if (chSendPt) {
                void* fxRecvPt = getFirstRecvPt(chSendPt);  // FX input receive point
                snap.insertInfo[ip].fxReceivePt = fxRecvPt;
            }

            if (pType == 2 || pType == 6) {
                void* parent = nullptr;
                safeRead((uint8_t*)connSendPt + 0x30, &parent, sizeof(parent));
                if (parent)
                    snap.insertInfo[ip].fxUnit = (void*)((uintptr_t)parent - 0xa8);
                fprintf(stderr, "[MC]   Insert%c ch %d: parentType=%d fxUnit=%p fxSend=%p fxRecv=%p\n",
                        'A'+ip, ch+1, pType, snap.insertInfo[ip].fxUnit,
                        snap.insertInfo[ip].fxSendPt, snap.insertInfo[ip].fxReceivePt);
            } else if (pType == 5) {
                // Dyn8 pool insert — find unit index by matching send point
                int dynIdx = findDyn8UnitIdx(connSendPt);
                fprintf(stderr, "[MC]   Insert%c ch %d: parentType=5 (Dyn8 pool) unitIdx=%d fxSend=%p fxRecv=%p\n",
                        'A'+ip, ch+1, dynIdx,
                        snap.insertInfo[ip].fxSendPt, snap.insertInfo[ip].fxReceivePt);
                // Verify getDyn8RecvPoint matches captured fxReceivePt
                if (dynIdx >= 0) {
                    void* ducRecv = getDyn8RecvPoint(dynIdx);
                    void* ducSend = getDyn8SendPoint(dynIdx);
                    fprintf(stderr, "[MC]   Dyn8[%d] verify: ducSend=%p vs captured=%p (%s), ducRecv=%p vs captured=%p (%s)\n",
                            dynIdx, ducSend, snap.insertInfo[ip].fxSendPt,
                            ducSend == snap.insertInfo[ip].fxSendPt ? "MATCH" : "MISMATCH",
                            ducRecv, snap.insertInfo[ip].fxReceivePt,
                            ducRecv == snap.insertInfo[ip].fxReceivePt ? "MATCH" : "MISMATCH");
                    // If recv doesn't match, scan DUC for the correct offset
                    if (ducRecv != snap.insertInfo[ip].fxReceivePt && snap.insertInfo[ip].fxReceivePt) {
                        void* duc = getDynUnitClient(dynIdx);
                        if (duc) {
                            fprintf(stderr, "[MC]   Scanning DUC %p for recv point %p...\n", duc, snap.insertInfo[ip].fxReceivePt);
                            for (int off = 0x80; off <= 0x120; off += 8) {
                                void* candidate = readQListFirst(duc, off);
                                if (candidate == snap.insertInfo[ip].fxReceivePt) {
                                    fprintf(stderr, "[MC]   FOUND recv at DUC+0x%x!\n", off);
                                }
                            }
                        }
                    }
                }
                // Snapshot Dyn8 settings (only once per channel, first insert with Dyn8 wins)
                // Each Dyn8 unit has 2 sub-modules: [0]=DynEQ4, [1]=MultiBD4
                if (dynIdx >= 0 && !snap.validDyn8) {
                    snap.dyn8UnitIdx = dynIdx;
                    void* dynNetObj = getDynNetObj(dynIdx);
                    if (dynNetObj) {
                        // Snapshot sDynamicsData (0x94 bytes at obj+0x98)
                        memset(snap.dyn8Data, 0, sizeof(snap.dyn8Data));
                        safeRead((uint8_t*)dynNetObj + 0x98, snap.dyn8Data, 0x94);
                        snap.validDyn8 = true;
                        fprintf(stderr, "[MC]   Snapshot Dyn8[%d] sDynamicsData for ch %d: type=%u first16=",
                                dynIdx, ch+1, *(uint32_t*)snap.dyn8Data);
                        for (int b = 0; b < 16; b++) fprintf(stderr, "%02x ", snap.dyn8Data[b]);
                        fprintf(stderr, "...\n");
                    }
                }
            } else if (snap.insertInfo[ip].fxSendPt || snap.insertInfo[ip].fxReceivePt) {
                fprintf(stderr, "[MC]   Insert%c ch %d: parentType=%d fxSend=%p fxRecv=%p\n",
                        'A'+ip, ch+1, pType,
                        snap.insertInfo[ip].fxSendPt, snap.insertInfo[ip].fxReceivePt);
            }
        }
    }

    const char* n = g_getChannelName(g_audioDM, 1, (uint8_t)ch);
    strncpy(snap.name, n ? n : "", sizeof(snap.name) - 1);
    snap.name[sizeof(snap.name) - 1] = '\0';
    snap.colour = g_getChannelColour(g_audioDM, 1, (uint8_t)ch);
    snap.isStereo = isChannelStereo(ch);

    return true;
}

static void recallTypeAForChannel(int ch, const ChannelSnapshot& snap, bool reportData = true) {
    void* inputCh = getInputChannel(ch);
    if (!inputCh) return;

    for (int p = 0; p < NUM_PROC_A; p++) {
        if (!snap.validA[p]) continue;
        void* obj = getProcessingObj(inputCh, g_procA[p].chOffset);
        if (!obj) {
            fprintf(stderr, "[MC]   %s: obj null, skip\n", g_procA[p].name);
            continue;
        }

        fprintf(stderr, "[MC]   Recall %s on ch %d (obj=%p)\n", g_procA[p].name, ch+1, obj);
        auto recall = (fn_method_msg)RESOLVE(g_procA[p].directlyRecallAddr);
        recall(obj, snap.msgA[p]);

        if (reportData) {
            auto report = (fn_method_void)RESOLVE(g_procA[p].reportDataAddr);
            report(obj);
        }
    }
}

static bool recallChannel(int ch, const ChannelSnapshot& snap, bool skipPreamp = false) {
    void* inputCh = getInputChannel(ch);
    if (!inputCh) { fprintf(stderr, "[MC] Ch %d: InputChannel is null!\n", ch); return false; }

    // Type A: DirectlyRecallStatus + ReportData
    recallTypeAForChannel(ch, snap);

    // Type B: write directly to object fields + call Refresh if available
    // For sidechain objects (p==6,7), bypass SetStatus (which calls RefreshSource that
    // validates via ChannelMapper and resets values). Instead: write raw fields, update
    // old-value cache (0x168/0x16c), and call InformOtherObjects for UI notification.
    typedef void (*fn_InformOtherObjects)(void* obj, const void* msg);
    auto informOthers = (fn_InformOtherObjects)RESOLVE(0x1000eb020);

    for (int p = 0; p < NUM_PROC_B; p++) {
        if (!snap.validB[p]) continue;
        void* obj = getTypeBObj(inputCh, g_procB[p]);
        if (!obj) { fprintf(stderr, "[MC]   %s: obj null, skip\n", g_procB[p].name); continue; }
        if (isInsertStatusProc(p)) {
            fprintf(stderr, "[MC]   Skip raw %s on ch %d; live routing will be restored separately\n",
                    g_procB[p].name, ch+1);
            continue;
        }

        // Sidechain: write raw fields then use the EMBEDDED message at obj+0x60
        // exactly like SetStatus does, but skip RefreshSource which resets values.
        // SideChain1/2 are g_procB[5] and g_procB[6].
        if (p == 5 || p == 6) {
            uint8_t wantStripType = snap.dataB[p].buf[1];
            uint8_t wantChannel   = snap.dataB[p].buf[2];

            // Write via pointer deref: *(obj+0x138) = stripType, *(obj+0x140) = channel
            void* pStripType = nullptr;
            void* pChannel   = nullptr;
            safeRead((uint8_t*)obj + 0x138, &pStripType, sizeof(pStripType));
            safeRead((uint8_t*)obj + 0x140, &pChannel,   sizeof(pChannel));
            if (pStripType && pChannel) {
                uint32_t st32 = wantStripType;
                safeWrite((uint8_t*)pStripType, &st32, sizeof(st32));
                safeWrite((uint8_t*)pChannel,   &wantChannel, sizeof(wantChannel));
                // Update "old value" cache so RefreshSource won't see a diff and reset
                safeWrite((uint8_t*)obj + 0x168, &st32, sizeof(st32));
                safeWrite((uint8_t*)obj + 0x16c, &wantChannel, sizeof(wantChannel));
            }

            // Use the EMBEDDED cAHNetMessage at obj+0x60 (same as SetStatus does)
            void* embMsg = (uint8_t*)obj + 0x60;

            // Set header fields exactly like SetStatus at 0x1002e5700-0x1002e570f:
            //   obj+0x70 = 0xFFFF  (embMsg+0x10)
            //   obj+0x74 = 0xFFFFFFFF (embMsg+0x14)
            //   obj+0x7c = 0x1000 (embMsg+0x1c = objectId for change notification)
            uint16_t hdr10 = 0xFFFF;
            uint32_t hdr14 = 0xFFFFFFFF;
            uint32_t hdr1c = 0x1000;
            safeWrite((uint8_t*)obj + 0x70, &hdr10, 2);
            safeWrite((uint8_t*)obj + 0x74, &hdr14, 4);
            safeWrite((uint8_t*)obj + 0x7c, &hdr1c, 4);

            // SetLength(embMsg, 2) — 2 data bytes
            typedef void (*fn_SetLength)(void*, uint32_t);
            auto setLen = (fn_SetLength)RESOLVE(0x1000e9ee0);
            setLen(embMsg, 2);

            // Set data: [0]=stripType, [1]=channel
            typedef void (*fn_SetUBYTE)(void*, uint8_t, uint32_t);
            auto setUByte = (fn_SetUBYTE)RESOLVE(0x1000ebde0);
            setUByte(embMsg, wantStripType, 0);
            setUByte(embMsg, wantChannel, 1);

            // Set dirty flag
            uint8_t one = 1;
            safeWrite((uint8_t*)obj + 0x174, &one, 1);

            fprintf(stderr, "[MC]   SC-Write %s on ch %d: stripType=%d channel=%d\n",
                    g_procB[p].name, ch+1, wantStripType, wantChannel);
            informOthers(obj, embMsg);
            continue;
        }

        // DigitalTrim: write raw fields + InformObjectsOfNewSettings for UI refresh
        if (p == 0) {
            uint16_t wantGain = ((uint16_t)snap.dataB[p].buf[1] << 8) | snap.dataB[p].buf[2];
            writeTypeBFields(obj, g_procB[p], snap.dataB[p].buf);
            // cDigitalAttenuator::InformObjectsOfNewSettings() — reads current state, notifies UI
            typedef void (*fn_method_void)(void* obj);
            auto informNewSettings = (fn_method_void)RESOLVE(0x1002046d0);
            informNewSettings(obj);
            fprintf(stderr, "[MC]   Recall DigitalTrim on ch %d: gain=%d mute=%d pol=%d\n",
                    ch+1, (int16_t)wantGain,
                    snap.dataB[p].buf[3], snap.dataB[p].buf[4]);
            continue;
        }

        // Delay: use SetDelayAndInformOthers + SetBypassAndInformOthers for UI refresh
        if (p == 1) {
            uint16_t wantDelay = ((uint16_t)snap.dataB[p].buf[1] << 8) | snap.dataB[p].buf[2];
            uint8_t wantBypass = snap.dataB[p].buf[3];
            // cDelay::SetDelayAndInformOthers(unsigned short)
            typedef void (*fn_setDelay)(void*, uint16_t);
            auto setDelayInform = (fn_setDelay)RESOLVE(0x100202590);
            setDelayInform(obj, wantDelay);
            // cDelay::SetBypassAndInformOthers(bool)
            typedef void (*fn_setBypass)(void*, bool);
            auto setBypassInform = (fn_setBypass)RESOLVE(0x100202660);
            setBypassInform(obj, wantBypass != 0);
            fprintf(stderr, "[MC]   Recall Delay on ch %d: delay=%u bypass=%d\n",
                    ch+1, wantDelay, wantBypass);
            continue;
        }

        // StereoImage: write raw fields + InformObjectsOfNewSettings for UI/runtime refresh
        if (strcmp(g_procB[p].name, "StereoImage") == 0) {
            uint16_t wantWidth = ((uint16_t)snap.dataB[p].buf[1] << 8) | snap.dataB[p].buf[2];
            uint8_t wantMode = snap.dataB[p].buf[3];
            writeTypeBFields(obj, g_procB[p], snap.dataB[p].buf);
            typedef void (*fn_method_void)(void* obj);
            auto informNewSettings = (fn_method_void)RESOLVE(0x1002f5850);
            if (informNewSettings)
                informNewSettings(obj);
            fprintf(stderr, "[MC]   Recall StereoImage on ch %d: width=%u mode=%u\n",
                    ch+1, wantWidth, wantMode);
            continue;
        }

        fprintf(stderr, "[MC]   Write %s on ch %d (obj=%p) data=[%02x %02x %02x %02x %02x %02x %02x]\n",
                g_procB[p].name, ch+1, obj,
                snap.dataB[p].buf[0], snap.dataB[p].buf[1], snap.dataB[p].buf[2],
                snap.dataB[p].buf[3], snap.dataB[p].buf[4], snap.dataB[p].buf[5],
                snap.dataB[p].buf[6]);
        writeTypeBFields(obj, g_procB[p], snap.dataB[p].buf);
    }

    // Mixer data: write sInputAttributes (sends, fader, mute, DCA, matrix, etc.)
    if (snap.validMixer && snap.mixerData) {
        uint8_t* attrsPtr = getInputAttrsPtr(ch);
        if (attrsPtr) {
            if (safeWrite(attrsPtr, snap.mixerData, SINPUTATTRS_SIZE)) {
                fprintf(stderr, "[MC]   Write mixer data on ch %d\n", ch+1);
                // Call RefreshMixer on the mixer object to push fader/gains to UI
                int group = ch >> 3;
                void* mixer = nullptr;
                safeRead((uint8_t*)g_inputMixerWrapper + 0x90 + group * 8, &mixer, sizeof(mixer));
                if (mixer) {
                    // Call SyncMainGain to push fader value through proper notification + UI path
                    // SyncMainGain calls SetMainGain internally AND InformOtherObjects to notify QML
                    int chInGrp = ch & 7;
                    int16_t mainGain = 0;
                    memcpy(&mainGain, snap.mixerData + 0xA88, sizeof(int16_t));
                    auto syncMainGain = (fn_SyncMainGain)RESOLVE(0x1002927e0);
                    syncMainGain(mixer, (uint8_t)chInGrp, mainGain);
                    fprintf(stderr, "[MC]   SyncMainGain ch %d (group %d, chInGrp %d) gain=%d\n",
                            ch+1, group, chInGrp, (int)mainGain);
                }
            } else {
                fprintf(stderr, "[MC]   WARN: mixer data write failed on ch %d\n", ch+1);
            }
        }
    }

    g_setChannelName(g_audioDM, 1, (uint8_t)ch, snap.name);
    g_setChannelColour(g_audioDM, 1, (uint8_t)ch, snap.colour);

    return true;
}

static void destroySnapshot(ChannelSnapshot& snap) {
    for (int p = 0; p < NUM_PROC_A; p++) {
        if (snap.validA[p] && snap.msgA[p]) {
            g_msgDtor(snap.msgA[p]);
            delete[] snap.msgA[p];
            snap.msgA[p] = nullptr;
            snap.validA[p] = false;
        }
    }
    for (int p = 0; p < NUM_PROC_B; p++) {
        snap.validB[p] = false;
    }
    if (snap.mixerData) {
        delete[] snap.mixerData;
        snap.mixerData = nullptr;
    }
    snap.validMixer = false;
    snap.validDyn8 = false;
}

struct MovePlan {
    int rawSrc;
    int rawDst;
    int srcStart;
    int dstStart;
    int blockSize;
    int lo;
    int hi;
    bool srcStereo;
    bool srcMonoBlock;
    std::vector<std::pair<int, int>> targetMap;  // (target channel, snapshot index)

    MovePlan()
        : rawSrc(-1), rawDst(-1), srcStart(-1), dstStart(-1),
          blockSize(1), lo(-1), hi(-1), srcStereo(false), srcMonoBlock(false) {}
};

static void* getMsgDataPtr(uint8_t* msg);
static uint32_t getMsgLength(uint8_t* msg);
static void dumpChannelData(int ch, const char* label);
static bool buildMovePlan(int src, int dst, bool moveAdjacentMonoPair,
                          MovePlan& plan, char* errBuf, size_t errBufLen);
static uint8_t remapMovedChannelRef(uint8_t oldRef, const MovePlan& plan);
static PatchData remapPatchDataForMove(const PatchData& pd, int srcCh, int tgtCh);
static PatchData getTargetPatchDataForMove(const PatchData& pd, int srcCh, int tgtCh,
                                           bool movePatchWithChannel);
static bool moveChannel(int src, int dst, bool movePatchWithChannel, bool moveAdjacentMonoPair);
static bool isInsertStatusProc(int procIdx) {
    return procIdx == 3 || procIdx == 4;
}
static bool assignDyn8InsertWithSetInserts(int ch, int unitIdx, int ip, int variant, const char* phaseTag);
static void refreshDyn8InsertAssignment(int unitIdx, int tgtCh, const char* phaseTag);

static void* getSystemController() {
    if (!g_audioDM) return nullptr;
    void* controller = nullptr;
    safeRead((uint8_t*)g_audioDM + 0xb0, &controller, sizeof(controller));
    return controller;
}

static void* getCompressorSystem() {
    void* controller = getSystemController();
    if (!controller) return nullptr;
    void* system = nullptr;
    safeRead((uint8_t*)controller + 0x60, &system, sizeof(system));
    return system;
}

static void* getGateSystem() {
    void* controller = getSystemController();
    if (!controller) return nullptr;
    void* system = nullptr;
    safeRead((uint8_t*)controller + 0x68, &system, sizeof(system));
    return system;
}

static void* getBiquadSystem() {
    void* controller = getSystemController();
    if (!controller) return nullptr;
    void* system = nullptr;
    safeRead((uint8_t*)controller + 0x70, &system, sizeof(system));
    return system;
}

static void resetInputProcessingGangMaster(int ch, const char* phaseTag) {
    typedef void (*fn_ResetGangMaster)(void*, uint8_t);
    typedef void (*fn_CompSyncAllInputStereoGangData)(void*);
    typedef void (*fn_GateSyncAllInputStereoGangData)(void*);
    typedef void (*fn_BiquadSyncAllInputFilterStereoGangData)(void*);
    typedef void (*fn_BiquadSyncAllInputPEQStereoGangData)(void*);

    auto resetComp = (fn_ResetGangMaster)RESOLVE(0x100e62ee0);
    auto resetGate = (fn_ResetGangMaster)RESOLVE(0x100304900);
    auto resetBiquad = (fn_ResetGangMaster)RESOLVE(0x100b15f70);
    auto syncComp = (fn_CompSyncAllInputStereoGangData)RESOLVE(0x100e62e40);
    auto syncGate = (fn_GateSyncAllInputStereoGangData)RESOLVE(0x1003048b0);
    auto syncBiquadFilter = (fn_BiquadSyncAllInputFilterStereoGangData)RESOLVE(0x100b15ed0);
    auto syncBiquadPEQ = (fn_BiquadSyncAllInputPEQStereoGangData)RESOLVE(0x100b15f30);

    void* comp = getCompressorSystem();
    void* gate = getGateSystem();
    void* biquad = getBiquadSystem();

    fprintf(stderr,
            "[MC]   [%s] ResetInputChannelGangMaster ch %d comp=%p gate=%p biquad=%p\n",
            phaseTag, ch + 1, comp, gate, biquad);

    if (comp && resetComp) resetComp(comp, (uint8_t)ch);
    if (gate && resetGate) resetGate(gate, (uint8_t)ch);
    if (biquad && resetBiquad) resetBiquad(biquad, (uint8_t)ch);

    if (comp && syncComp) syncComp(comp);
    if (gate && syncGate) syncGate(gate);
    if (biquad && syncBiquadFilter) syncBiquadFilter(biquad);
    if (biquad && syncBiquadPEQ) syncBiquadPEQ(biquad);
}

static void refreshSideChainStateForChannel(int ch, const char* phaseTag) {
    void* inputCh = getInputChannel(ch);
    if (!inputCh) return;

    typedef void (*fn_method_void)(void*);
    auto informCompSideChain = (fn_method_void)RESOLVE(0x1001f39d0);
    auto informGateSideChain = (fn_method_void)RESOLVE(0x1002d1970);
    auto identifyAndRefreshSideChain = (fn_method_void)RESOLVE(0x1002e4e80);

    void* compObj = getProcessingObj(inputCh, g_procA[3].chOffset);
    if (compObj && informCompSideChain) {
        fprintf(stderr, "[MC]   [%s] Refresh compressor sidechain on ch %d (obj=%p)\n",
                phaseTag, ch + 1, compObj);
        informCompSideChain(compObj);
    }

    void* gateSCObj = getProcessingObj(inputCh, g_procA[4].chOffset);
    if (gateSCObj && informGateSideChain) {
        fprintf(stderr, "[MC]   [%s] Refresh gate sidechain on ch %d (obj=%p)\n",
                phaseTag, ch + 1, gateSCObj);
        informGateSideChain(gateSCObj);
    }

    for (int p = 5; p <= 6; p++) {
        void* scObj = getTypeBObj(inputCh, g_procB[p]);
        if (!scObj || !identifyAndRefreshSideChain) continue;
        fprintf(stderr, "[MC]   [%s] Refresh %s on ch %d (obj=%p)\n",
                phaseTag, g_procB[p].name, ch + 1, scObj);
        identifyAndRefreshSideChain(scObj);
    }
}

static void setDelayForChannel(int ch, uint16_t delay, bool bypass) {
    void* inputCh = getInputChannel(ch);
    if (!inputCh) return;
    void* obj = getTypeBObj(inputCh, g_procB[1]); // Delay
    if (!obj) return;

    typedef void (*fn_setDelay)(void*, uint16_t);
    auto setDelayInform = (fn_setDelay)RESOLVE(0x100202590);
    typedef void (*fn_setBypass)(void*, bool);
    auto setBypassInform = (fn_setBypass)RESOLVE(0x100202660);

    setDelayInform(obj, delay);
    setBypassInform(obj, bypass);
}

static void replayMixerAssignmentsForChannel(int ch,
                                             const ChannelSnapshot& snap,
                                             const char* phaseTag) {
    if (!g_inputMixerWrapper || !snap.validMixer || !snap.mixerData) return;

    int group = ch >> 3;
    int chInGrp = ch & 7;
    void* mixer = nullptr;
    safeRead((uint8_t*)g_inputMixerWrapper + 0x90 + group * 8, &mixer, sizeof(mixer));
    if (!mixer) return;

    typedef void (*fn_SetMainOnSwitch)(void* mixer, uint8_t chInGrp, bool on);
    typedef void (*fn_SetMainMonoOnSwitch)(void* mixer, uint8_t chInGrp, bool on);
    typedef void (*fn_InformObjectsOfNewMainOnSetting)(void* mixer, uint8_t chInGrp, bool on);
    typedef void (*fn_InformObjectsOfNewMainMonoOnSetting)(void* mixer, uint8_t chInGrp, bool on);
    typedef void (*fn_SetDCAGroupAssign)(void* mixer, uint8_t dca, uint8_t chInGrp, bool assign);
    typedef void (*fn_InformObjectsOfNewInDCAGroupSetting)(void* mixer, uint8_t dca, uint8_t chInGrp, bool assign);

    auto setMainOnSwitch = (fn_SetMainOnSwitch)RESOLVE(0x100037e10);
    auto setMainMonoOnSwitch = (fn_SetMainMonoOnSwitch)RESOLVE(0x100037e70);
    auto informMainOnSetting = (fn_InformObjectsOfNewMainOnSetting)RESOLVE(0x10003faf0);
    auto informMainMonoOnSetting = (fn_InformObjectsOfNewMainMonoOnSetting)RESOLVE(0x10003fb60);
    auto setDCAGroupAssign = (fn_SetDCAGroupAssign)RESOLVE(0x100039c40);
    auto informInDCAGroupSetting = (fn_InformObjectsOfNewInDCAGroupSetting)RESOLVE(0x10003fee0);

    bool wantMainOn = snap.mixerData[0xA86] != 0;
    bool wantMainMonoOn = snap.mixerData[0xA87] != 0;

    fprintf(stderr,
            "[MC]   [%s] Replay mixer assigns ch %d: mainOn=%d mainMonoOn=%d\n",
            phaseTag, ch + 1, wantMainOn ? 1 : 0, wantMainMonoOn ? 1 : 0);

    if (setMainOnSwitch) setMainOnSwitch(mixer, (uint8_t)chInGrp, wantMainOn);
    if (informMainOnSetting) informMainOnSetting(mixer, (uint8_t)chInGrp, wantMainOn);

    if (setMainMonoOnSwitch) setMainMonoOnSwitch(mixer, (uint8_t)chInGrp, wantMainMonoOn);
    if (informMainMonoOnSetting) informMainMonoOnSetting(mixer, (uint8_t)chInGrp, wantMainMonoOn);

    if (setDCAGroupAssign) {
        for (int dca = 0; dca < 32; dca++) {
            bool wantAssign = snap.mixerData[0x001 + dca] != 0;
            setDCAGroupAssign(mixer, (uint8_t)dca, (uint8_t)chInGrp, wantAssign);
            if (informInDCAGroupSetting)
                informInDCAGroupSetting(mixer, (uint8_t)dca, (uint8_t)chInGrp, wantAssign);
        }
    }
}

static void replayInsertRouting(const MovePlan& plan,
                                const std::vector<ChannelSnapshot>& snaps,
                                const char* phaseTag) {
    if (!g_channelManager || !g_audioSRPManager) return;

    typedef void* (*fn_GetChannel)(void* mgr, uint32_t stripType, uint8_t chNum);
    auto getChannel = (fn_GetChannel)RESOLVE(0x1006e3f90);
    typedef void (*fn_PerformTasks)(void* audioSRPMgr, void* taskList);
    auto performTasks = (fn_PerformTasks)RESOLVE(0x1006d19c0);
    typedef void* (*fn_CreateSendTargetTask)(void* ret, void* channel, void* fxRecvPt, int ip, int enable);
    auto createSendTargetTask = (fn_CreateSendTargetTask)RESOLVE(0x1006da210);
    typedef void* (*fn_CreateReturnSourceTask)(void* ret, void* channel, void* fxSendPt, int ip);
    auto createReturnSourceTask = (fn_CreateReturnSourceTask)RESOLVE(0x1006da450);
    typedef void (*fn_MergeTaskLists)(void* dst, void* src);
    auto mergeTaskLists = (fn_MergeTaskLists)RESOLVE(0x10069cd60);
    bool traceDyn8Route = false;
    if (const char* traceEnv = getenv("MC_TRACE_DYN8_ROUTE")) {
        traceDyn8Route = (atoi(traceEnv) != 0);
    }
    bool useAssignFlags = true;
    if (const char* assignEnv = getenv("MC_DYN8_ASSIGN_FLAGS")) {
        useAssignFlags = (atoi(assignEnv) != 0);
    }
    bool useDyn8SetInserts = false;
    if (const char* setInsertsEnv = getenv("MC_DYN8_USE_SETINSERTS")) {
        useDyn8SetInserts = (atoi(setInsertsEnv) != 0);
    }
    bool useStereoDyn8SetInserts = false;
    if (const char* stereoSetInsertsEnv = getenv("MC_DYN8_STEREO_SETINSERTS")) {
        useStereoDyn8SetInserts = (atoi(stereoSetInsertsEnv) != 0);
    }

    auto routeInsert = [&](int tgtCh, const ChannelSnapshot::InsertInfo& ins, int ip, bool clearPass) {
        if (!ins.hasInsert) return;
        if (!clearPass) {
            if (ins.parentType == 0) return;
        }

        void* tgtChannel = getChannel(g_channelManager, 1, (uint8_t)tgtCh);
        if (!tgtChannel) return;

        void* routeSendPt = ins.fxSendPt;
        void* routeRecvPt = ins.fxReceivePt;
        int enable = clearPass ? 0 : 1;

        if (!clearPass && ins.parentType == 5) {
            int dynIdx = findDyn8UnitIdx(ins.fxSendPt);
            void* mgrSend = getDyn8SendPointFromManager(dynIdx);
            void* mgrRecv = getDyn8RecvPointFromManager(dynIdx);
            fprintf(stderr,
                    "[MC]   [%s] Dyn8 manager points for ch %d unit %d: send=%p recv=%p (snapshot send=%p recv=%p)\n",
                    phaseTag, tgtCh + 1, dynIdx, mgrSend, mgrRecv, ins.fxSendPt, ins.fxReceivePt);
            if (mgrSend) routeSendPt = mgrSend;
            if (mgrRecv) routeRecvPt = mgrRecv;

            if (useStereoDyn8SetInserts && isChannelStereo(tgtCh) && ((tgtCh & 1) == 0) && ip == 0 && dynIdx >= 0) {
                if (assignDyn8InsertWithSetInserts(tgtCh, dynIdx, ip, 0, phaseTag)) {
                    if (traceDyn8Route) {
                        usleep(100 * 1000);
                        ChannelSnapshot live;
                        if (snapshotChannel(tgtCh, live)) {
                            fprintf(stderr,
                                    "[MC]   [%s] Dyn8 stereo trace after SetInserts ch %d: validDyn8=%d Insert%c type=%d send=%p recv=%p\n",
                                    phaseTag, tgtCh + 1, live.validDyn8, 'A' + ip,
                                    live.insertInfo[ip].parentType,
                                    live.insertInfo[ip].fxSendPt,
                                    live.insertInfo[ip].fxReceivePt);
                            destroySnapshot(live);
                        }
                    }
                    return;
                }
            }

            if (useDyn8SetInserts && !isChannelStereo(tgtCh) && dynIdx >= 0) {
                if (assignDyn8InsertWithSetInserts(tgtCh, dynIdx, ip, 0, phaseTag)) {
                    if (traceDyn8Route) {
                        usleep(100 * 1000);
                        ChannelSnapshot live;
                        if (snapshotChannel(tgtCh, live)) {
                            fprintf(stderr,
                                    "[MC]   [%s] Dyn8 trace after SetInserts ch %d: validDyn8=%d Insert%c type=%d send=%p recv=%p\n",
                                    phaseTag, tgtCh + 1, live.validDyn8, 'A' + ip,
                                    live.insertInfo[ip].parentType,
                                    live.insertInfo[ip].fxSendPt,
                                    live.insertInfo[ip].fxReceivePt);
                            destroySnapshot(live);
                        }
                    }
                    return;
                }
            }
        }

        if (clearPass) {
            routeSendPt = getDefaultInsertSendPoint();
            routeRecvPt = getDefaultInsertReceivePoint();
        }

        if (clearPass) {
            fprintf(stderr, "[MC]   [%s] Insert%c final clear on ch %d ← fxSend=%p fxRecv=%p\n",
                    phaseTag, 'A'+ip, tgtCh+1, routeSendPt, routeRecvPt);
        } else {
            fprintf(stderr, "[MC]   [%s] Insert%c: ch %d ← fxSend=%p fxRecv=%p (type=%d)\n",
                    phaseTag, 'A'+ip, tgtCh+1, routeSendPt, routeRecvPt, ins.parentType);
        }

        if (useAssignFlags) {
            if (clearPass) {
                setInputChannelInsertFlags(tgtCh, ip, false, false, phaseTag);
            } else if (useStereoDyn8SetInserts && ins.parentType == 5 && isChannelStereo(tgtCh) && ((tgtCh & 1) == 1) && ip == 0) {
                // Stereo Dyn8 pair is assigned through the even channel's SetInserts call.
                setInputChannelInsertFlags(tgtCh, ip, true, true, phaseTag);
            } else if (ins.parentType == 5) {
                setInputChannelInsertFlags(tgtCh, ip, true, true, phaseTag);
            } else if (ins.parentType != 0) {
                setInputChannelInsertFlags(tgtCh, ip, true, false, phaseTag);
            }
        }

        if (!clearPass && useStereoDyn8SetInserts && ins.parentType == 5 &&
            isChannelStereo(tgtCh) && ((tgtCh & 1) == 1) && ip == 0) {
            fprintf(stderr,
                    "[MC]   [%s] Stereo Dyn8 route on odd ch %d handled by even pair mate\n",
                    phaseTag, tgtCh + 1);
            return;
        }

        if (!clearPass && ins.parentType == 5 && routeRecvPt && routeSendPt) {
            uint8_t sendTasks[64];
            uint8_t returnTasks[64];
            memset(sendTasks, 0, sizeof(sendTasks));
            memset(returnTasks, 0, sizeof(returnTasks));
            createSendTargetTask(sendTasks, tgtChannel, routeRecvPt, ip, enable);
            createReturnSourceTask(returnTasks, tgtChannel, routeSendPt, ip);
            mergeTaskLists(sendTasks, returnTasks);
            performTasks(g_audioSRPManager, sendTasks);
        } else {
            if (routeRecvPt) {
                uint8_t buf[64];
                memset(buf, 0, sizeof(buf));
                createSendTargetTask(buf, tgtChannel, routeRecvPt, ip, enable);
                performTasks(g_audioSRPManager, buf);
            }
            if (routeSendPt) {
                uint8_t buf[64];
                memset(buf, 0, sizeof(buf));
                createReturnSourceTask(buf, tgtChannel, routeSendPt, ip);
                performTasks(g_audioSRPManager, buf);
            }
        }

        if (traceDyn8Route && !clearPass && ins.parentType == 5) {
            usleep(100 * 1000);
            ChannelSnapshot live;
            if (snapshotChannel(tgtCh, live)) {
                fprintf(stderr,
                        "[MC]   [%s] Dyn8 trace after route ch %d: validDyn8=%d Insert%c type=%d send=%p recv=%p\n",
                        phaseTag, tgtCh + 1, live.validDyn8, 'A' + ip,
                        live.insertInfo[ip].parentType,
                        live.insertInfo[ip].fxSendPt,
                        live.insertInfo[ip].fxReceivePt);
                destroySnapshot(live);
            }
        }
    };

    for (auto& [tgtCh, si] : plan.targetMap) {
        int liveIdx = tgtCh - plan.lo;
        for (int ip = 0; ip < 2; ip++)
            routeInsert(tgtCh, snaps[liveIdx].insertInfo[ip], ip, true);
    }
    if (plan.srcStart > plan.dstStart) {
        for (auto it = plan.targetMap.rbegin(); it != plan.targetMap.rend(); ++it) {
            for (int ip = 0; ip < 2; ip++)
                routeInsert(it->first, snaps[it->second].insertInfo[ip], ip, false);
        }
    } else {
        for (auto& [tgtCh, si] : plan.targetMap) {
            for (int ip = 0; ip < 2; ip++)
                routeInsert(tgtCh, snaps[si].insertInfo[ip], ip, false);
        }
    }
}

static bool assignDyn8InsertWithSetInserts(int ch, int unitIdx, int ip, int variant, const char* phaseTag) {
    if (!g_channelManager) return false;

    typedef void* (*fn_GetChannel)(void* mgr, uint32_t stripType, uint8_t chNum);
    auto getChannel = (fn_GetChannel)RESOLVE(0x1006e3f90);
    struct InsertPts {
        void* recvA;
        void* recvB;
        void* sendA;
        void* sendB;
    };
    typedef void (*fn_SetInserts)(void* channel, InsertPts insertPts, int insertPoint);
    auto setInserts = (fn_SetInserts)RESOLVE(0x1006d9920);

    void* cChannel = getChannel(g_channelManager, 1, (uint8_t)ch);
    void* recvPt = getDyn8RecvPointFromManager(unitIdx);
    void* sendPt = getDyn8SendPointFromManager(unitIdx);
    if (!cChannel || !recvPt || !sendPt) {
        fprintf(stderr,
                "[MC]   [%s] SetInserts Dyn8 attach skipped on ch %d unit %d (ch=%p recv=%p send=%p)\n",
                phaseTag, ch + 1, unitIdx, cChannel, recvPt, sendPt);
        return false;
    }

    bool stereo = isChannelStereo(ch);
    void* defaultRecv = getDefaultInsertReceivePoint();
    void* defaultSend = getDefaultInsertSendPoint();

    InsertPts pts = {};
    switch (variant) {
        case 1:
            pts = {sendPt, sendPt, recvPt, recvPt};
            break;
        default:
            pts.recvA = recvPt;
            pts.sendA = sendPt;
            if (stereo) {
                pts.recvB = getDyn8RecvPointFromManager(unitIdx + 1);
                pts.sendB = getDyn8SendPointFromManager(unitIdx + 1);
            } else {
                pts.recvB = defaultRecv;
                pts.sendB = defaultSend;
            }
            break;
    }
    fprintf(stderr,
            "[MC]   [%s] SetInserts Dyn8 attach variant=%d on ch %d ip=%d unit=%d recvA=%p recvB=%p sendA=%p sendB=%p stereo=%d\n",
            phaseTag, variant, ch + 1, ip, unitIdx,
            pts.recvA, pts.recvB, pts.sendA, pts.sendB,
            stereo ? 1 : 0);
    setInserts(cChannel, pts, ip);
    return true;
}

static void setInputChannelInsertFlags(int ch, int ip, bool assigned, bool dynamics, const char* phaseTag) {
    void* inputCh = getInputChannel(ch);
    if (!inputCh) {
        fprintf(stderr, "[MC]   [%s] AssignInsert skipped on ch %d ip=%d (no input channel)\n",
                phaseTag, ch + 1, ip);
        return;
    }

    typedef void (*fn_AssignInsert)(void* inputCh, bool assigned, bool dynamics);
    auto assignInsert1 = (fn_AssignInsert)RESOLVE(0x100290490);
    auto assignInsert2 = (fn_AssignInsert)RESOLVE(0x1002905b0);
    auto fn = ip == 0 ? assignInsert1 : assignInsert2;
    fprintf(stderr,
            "[MC]   [%s] AssignInsert%c on ch %d assigned=%d dynamics=%d\n",
            phaseTag, 'A' + ip, ch + 1, assigned ? 1 : 0, dynamics ? 1 : 0);
    fn(inputCh, assigned, dynamics);
}

static void refreshDyn8InsertAssignment(int unitIdx, int tgtCh, const char* phaseTag) {
    void* duc = getDynUnitClient(unitIdx);
    if (!duc) {
        fprintf(stderr,
                "[MC]   [%s] Dyn8 refresh skipped for unit %d / ch %d (no DUC)\n",
                phaseTag, unitIdx, tgtCh + 1);
        return;
    }

    typedef void (*fn_InputConfigurationChanged)(void* duc);
    typedef void (*fn_ReceivePointUpdated)(void* duc);
    auto inputConfigurationChanged = (fn_InputConfigurationChanged)RESOLVE(0x1005e8a00);
    auto receivePointUpdated = (fn_ReceivePointUpdated)RESOLVE(0x1005e81b0);

    fprintf(stderr,
            "[MC]   [%s] Dyn8 refresh unit %d / ch %d via InputConfigurationChanged + ReceivePointUpdated (duc=%p)\n",
            phaseTag, unitIdx, tgtCh + 1, duc);
    inputConfigurationChanged(duc);
    receivePointUpdated(duc);
}

static bool writeProcOrderForChannel(int ch, const ChannelSnapshot& snap) {
    if (!snap.validB[2]) return true;

    uint8_t wantVal = snap.dataB[2].buf[1];
    int attempts = wantVal ? 50 : 1;
    for (int attempt = 0; attempt < attempts; attempt++) {
        void* inputCh = getInputChannel(ch);
        if (inputCh) {
            void* procOrderObj = getTypeBObj(inputCh, g_procB[2]);
            if (procOrderObj) {
                uint8_t procBuf[16] = {};
                procBuf[0] = g_procB[2].versionByte;
                procBuf[1] = wantVal;
                writeTypeBFields(procOrderObj, g_procB[2], procBuf);
                fprintf(stderr, "[MC]   ProcOrder settle write on ch %d: value=%u (attempt %d)\n",
                        ch+1, wantVal, attempt + 1);
                return true;
            }
        }

        if (attempt + 1 < attempts) {
            QApplication::processEvents();
            usleep(100 * 1000);
        }
    }

    if (wantVal) {
        fprintf(stderr, "[MC]   WARN: ProcOrder object unavailable on ch %d while restoring value=%u\n",
                ch+1, wantVal);
        return false;
    }
    return true;
}

static bool compareSnapshotsForMove(const ChannelSnapshot& expected, const ChannelSnapshot& actual,
                                    int ch, bool comparePatch) {
    bool ok = true;

    if (strcmp(expected.name, actual.name) != 0) {
        fprintf(stderr, "[MC][VERIFY] ch %d name mismatch: expected '%s' got '%s'\n",
                ch+1, expected.name, actual.name);
        ok = false;
    }
    if (expected.colour != actual.colour) {
        fprintf(stderr, "[MC][VERIFY] ch %d colour mismatch: expected %u got %u\n",
                ch+1, expected.colour, actual.colour);
        ok = false;
    }
    if (expected.isStereo != actual.isStereo) {
        fprintf(stderr, "[MC][VERIFY] ch %d stereo mismatch: expected %d got %d\n",
                ch+1, expected.isStereo, actual.isStereo);
        ok = false;
    }

    for (int p = 0; p < NUM_PROC_A; p++) {
        if (expected.validA[p] != actual.validA[p]) {
            fprintf(stderr, "[MC][VERIFY] ch %d %s presence mismatch\n", ch+1, g_procA[p].name);
            ok = false;
            continue;
        }
        if (!expected.validA[p]) continue;

        uint32_t expLen = getMsgLength(expected.msgA[p]);
        uint32_t actLen = getMsgLength(actual.msgA[p]);
        if (expLen != actLen) {
            fprintf(stderr, "[MC][VERIFY] ch %d %s len mismatch: expected %u got %u\n",
                    ch+1, g_procA[p].name, expLen, actLen);
            ok = false;
            continue;
        }

        void* expData = getMsgDataPtr(expected.msgA[p]);
        void* actData = getMsgDataPtr(actual.msgA[p]);
        if ((expLen > 0) && (!expData || !actData || memcmp(expData, actData, expLen) != 0)) {
            fprintf(stderr, "[MC][VERIFY] ch %d %s payload mismatch\n", ch+1, g_procA[p].name);
            ok = false;
        }
    }

    for (int p = 0; p < NUM_PROC_B; p++) {
        if (isInsertStatusProc(p)) continue;
        if (p == 2) {
            uint8_t expVal = expected.validB[p] ? expected.dataB[p].buf[1] : 0;
            uint8_t actVal = actual.validB[p] ? actual.dataB[p].buf[1] : 0;
            if (expVal != actVal) {
                fprintf(stderr, "[MC][VERIFY] ch %d %s mismatch: expected %u got %u\n",
                        ch+1, g_procB[p].name, expVal, actVal);
                ok = false;
            }
            continue;
        }
        if (expected.validB[p] != actual.validB[p]) {
            fprintf(stderr, "[MC][VERIFY] ch %d %s presence mismatch\n", ch+1, g_procB[p].name);
            ok = false;
            continue;
        }
        if (!expected.validB[p]) continue;
        if ((expected.dataB[p].len != actual.dataB[p].len) ||
            memcmp(expected.dataB[p].buf, actual.dataB[p].buf, expected.dataB[p].len) != 0) {
            fprintf(stderr, "[MC][VERIFY] ch %d %s payload mismatch exp=[", ch+1, g_procB[p].name);
            for (int i = 0; i < expected.dataB[p].len; i++) fprintf(stderr, "%s%02x", i ? " " : "", expected.dataB[p].buf[i]);
            fprintf(stderr, "] got=[");
            for (int i = 0; i < actual.dataB[p].len; i++) fprintf(stderr, "%s%02x", i ? " " : "", actual.dataB[p].buf[i]);
            fprintf(stderr, "]\n");
            ok = false;
        }
    }

    if (expected.validMixer != actual.validMixer) {
        fprintf(stderr, "[MC][VERIFY] ch %d mixer presence mismatch\n", ch+1);
        ok = false;
    } else if (expected.validMixer && expected.mixerData && actual.mixerData &&
               memcmp(expected.mixerData, actual.mixerData, SINPUTATTRS_SIZE) != 0) {
        fprintf(stderr, "[MC][VERIFY] ch %d mixer payload mismatch\n", ch+1);
        ok = false;
    }

    if (expected.validPreamp != actual.validPreamp) {
        fprintf(stderr, "[MC][VERIFY] ch %d preamp presence mismatch\n", ch+1);
        ok = false;
    } else if (expected.validPreamp) {
        if (expected.preampData.gain != actual.preampData.gain ||
            expected.preampData.pad != actual.preampData.pad ||
            expected.preampData.phantom != actual.preampData.phantom) {
            fprintf(stderr, "[MC][VERIFY] ch %d preamp mismatch\n", ch+1);
            ok = false;
        }
    }

    if (comparePatch) {
        if (expected.validPatch != actual.validPatch) {
            fprintf(stderr, "[MC][VERIFY] ch %d patch presence mismatch\n", ch+1);
            ok = false;
        } else if (expected.validPatch &&
                   memcmp(&expected.patchData, &actual.patchData, sizeof(PatchData)) != 0) {
            fprintf(stderr, "[MC][VERIFY] ch %d patch mismatch\n", ch+1);
            ok = false;
        }
    }

    for (int ip = 0; ip < 2; ip++) {
        if (expected.insertInfo[ip].hasInsert != actual.insertInfo[ip].hasInsert ||
            expected.insertInfo[ip].parentType != actual.insertInfo[ip].parentType) {
            fprintf(stderr,
                    "[MC][VERIFY] ch %d Insert%c routing mismatch exp={has=%d type=%d send=%p recv=%p} got={has=%d type=%d send=%p recv=%p}\n",
                    ch+1, 'A'+ip,
                    expected.insertInfo[ip].hasInsert, expected.insertInfo[ip].parentType,
                    expected.insertInfo[ip].fxSendPt, expected.insertInfo[ip].fxReceivePt,
                    actual.insertInfo[ip].hasInsert, actual.insertInfo[ip].parentType,
                    actual.insertInfo[ip].fxSendPt, actual.insertInfo[ip].fxReceivePt);
            ok = false;
        }
    }

    if (expected.validDyn8 != actual.validDyn8) {
        fprintf(stderr, "[MC][VERIFY] ch %d Dyn8 presence mismatch\n", ch+1);
        ok = false;
    } else if (expected.validDyn8 &&
               memcmp(expected.dyn8Data, actual.dyn8Data, sizeof(expected.dyn8Data)) != 0) {
        fprintf(stderr, "[MC][VERIFY] ch %d Dyn8 data mismatch\n", ch+1);
        ok = false;
    }

    return ok;
}

static bool runAutomatedMoveTest() {
    const char* srcEnv = getenv("MC_AUTOTEST_SRC");
    const char* dstEnv = getenv("MC_AUTOTEST_DST");
    if (!srcEnv || !dstEnv) return false;

    int src = atoi(srcEnv) - 1;  // user-facing 1-based
    int dst = atoi(dstEnv) - 1;
    bool movePatchWithChannel = false;
    if (const char* patchEnv = getenv("MC_AUTOTEST_MOVE_PATCH")) {
        movePatchWithChannel = (atoi(patchEnv) != 0);
    }

    bool forceStereo = false;
    bool moveMonoBlock = false;
    bool prepareRange = true;
    if (const char* modeEnv = getenv("MC_AUTOTEST_MODE")) {
        if (strcmp(modeEnv, "stereo") == 0)
            forceStereo = true;
        if (strcmp(modeEnv, "mono2") == 0 || strcmp(modeEnv, "mono_pair") == 0)
            moveMonoBlock = true;
    }
    if (const char* noPrepEnv = getenv("MC_AUTOTEST_NO_PREP")) {
        if (atoi(noPrepEnv) != 0)
            prepareRange = false;
    }
    bool prepScene21 = false;
    if (const char* sceneEnv = getenv("MC_AUTOTEST_PREP_SCENE21")) {
        prepScene21 = (atoi(sceneEnv) != 0);
    }

    if (prepScene21 && !prepareScene21MoveTest()) {
        fprintf(stderr, "[MC][AUTOTEST] failed to prepare scene 21 test layout\n");
        return false;
    }

    if (const char* probeLibEnv = getenv("MC_PROBE_LIBRARY_TYPES")) {
        if (atoi(probeLibEnv) != 0)
            probeLibraryTypesForChannel(src);
    }

    if (forceStereo && !isChannelStereo(src)) {
        fprintf(stderr, "[MC][AUTOTEST] forcing source pair %d+%d to stereo before move\n", (src & ~1) + 1, (src & ~1) + 2);
        if (!changeStereoConfig(src, true)) {
            fprintf(stderr, "[MC][AUTOTEST] failed to force stereo config on source pair\n");
            return false;
        }
    }

    MovePlan plan;
    char err[256];
    if (!buildMovePlan(src, dst, moveMonoBlock, plan, err, sizeof(err))) {
        fprintf(stderr, "[MC][AUTOTEST] invalid test plan: %s\n", err[0] ? err : "unknown");
        return false;
    }

    if (prepareRange) {
        fprintf(stderr, "[MC][AUTOTEST] preparing range %d-%d for move test\n", plan.lo+1, plan.hi+1);
        for (int ch = plan.lo; ch <= plan.hi; ch++) {
            char nameBuf[64];
            snprintf(nameBuf, sizeof(nameBuf), "MC-%02d", ch + 1);
            g_setChannelName(g_audioDM, 1, (uint8_t)ch, nameBuf);
            g_setChannelColour(g_audioDM, 1, (uint8_t)ch, (uint8_t)((ch % 16) + 1));
            setDelayForChannel(ch, (uint16_t)(50 + (ch - plan.lo) * 37), false);
        }
    } else {
        fprintf(stderr, "[MC][AUTOTEST] using existing live range %d-%d without preparation\n", plan.lo+1, plan.hi+1);
    }

    std::vector<ChannelSnapshot> expected(plan.hi - plan.lo + 1);
    for (int i = 0; i < (int)expected.size(); i++) {
        if (!snapshotChannel(plan.lo + i, expected[i])) {
            fprintf(stderr, "[MC][AUTOTEST] failed to snapshot prepared channel %d\n", plan.lo + i + 1);
            for (int j = 0; j <= i; j++) destroySnapshot(expected[j]);
            return false;
        }
        dumpChannelData(plan.lo + i, "Autotest-Before");
    }

    for (int i = 0; i < (int)expected.size(); i++) {
        for (int p = 5; p <= 6; p++) {
            if (!expected[i].validB[p]) continue;
            expected[i].dataB[p].buf[2] = remapMovedChannelRef(expected[i].dataB[p].buf[2], plan);
        }
    }
    for (auto& [tgtCh, snapIdx] : plan.targetMap) {
        int srcCh = plan.lo + snapIdx;
        if (!expected[snapIdx].validPatch) continue;
        expected[snapIdx].patchData =
            getTargetPatchDataForMove(expected[snapIdx].patchData, srcCh, tgtCh, movePatchWithChannel);
    }
    bool moved = moveChannel(src, dst, movePatchWithChannel, moveMonoBlock);
    bool ok = moved;
    if (moved) {
        for (auto& [tgtCh, snapIdx] : plan.targetMap) {
            ChannelSnapshot live;
            if (!snapshotChannel(tgtCh, live)) {
                fprintf(stderr, "[MC][AUTOTEST] failed to snapshot target %d after move\n", tgtCh + 1);
                ok = false;
                continue;
            }
            dumpChannelData(tgtCh, "Autotest-After");
            if (!compareSnapshotsForMove(expected[snapIdx], live, tgtCh, true))
                ok = false;
            destroySnapshot(live);
        }
    }

    for (auto& snap : expected) destroySnapshot(snap);

    fprintf(stderr, "[MC][AUTOTEST] RESULT: %s\n", ok ? "PASS" : "FAIL");
    return ok;
}

static bool buildMovePlan(int src, int dst, bool moveAdjacentMonoPair,
                          MovePlan& plan, char* errBuf = nullptr, size_t errBufLen = 0) {
    plan = MovePlan();
    plan.rawSrc = src;
    plan.rawDst = dst;

    if (errBuf && errBufLen) errBuf[0] = '\0';
    auto setErr = [&](const char* fmt, int a = 0, int b = 0) {
        if (errBuf && errBufLen) snprintf(errBuf, errBufLen, fmt, a, b);
    };

    if (src < 0 || src > 127 || dst < 0 || dst > 127) {
        setErr("invalid channel number");
        return false;
    }

    plan.srcStereo = isChannelStereo(src);
    if (plan.srcStereo) {
        plan.blockSize = 2;
        plan.srcStart = src & ~1;
        plan.dstStart = dst & ~1;
    } else if (moveAdjacentMonoPair) {
        if (src >= 127) {
            setErr("two-channel mono move needs a following channel");
            return false;
        }
        if (isChannelStereo(src + 1)) {
            setErr("source channels %d+%d are not two independent mono channels", src + 1, src + 2);
            return false;
        }
        plan.blockSize = 2;
        plan.srcStart = src;
        plan.dstStart = dst;
        plan.srcMonoBlock = true;
    } else {
        plan.blockSize = 1;
        plan.srcStart = src;
        plan.dstStart = dst;
    }

    if (plan.dstStart < 0 || plan.dstStart + plan.blockSize - 1 > 127) {
        setErr("destination would exceed channel 128");
        return false;
    }

    if (plan.srcStart == plan.dstStart) {
        plan.lo = plan.srcStart;
        plan.hi = plan.srcStart + plan.blockSize - 1;
        return true;
    }

    if (plan.srcStart < plan.dstStart) {
        plan.lo = plan.srcStart;
        plan.hi = plan.dstStart + plan.blockSize - 1;
    } else {
        plan.lo = plan.dstStart;
        plan.hi = plan.srcStart + plan.blockSize - 1;
    }

    if (plan.blockSize == 1) {
        for (int pairStart = (plan.lo & ~1); pairStart <= plan.hi; pairStart += 2) {
            if (pairStart < 0 || pairStart + 1 > 127) continue;
            if (!isChannelStereo(pairStart)) continue;
            setErr("mono move crosses stereo pair %d+%d", pairStart + 1, pairStart + 2);
            return false;
        }
    } else if (plan.srcMonoBlock) {
        if ((plan.dstStart & 1) != 0 && isChannelStereo(plan.dstStart - 1)) {
            if (errBuf && errBufLen) {
                snprintf(errBuf, errBufLen,
                         "destination %d+%d would split stereo pair %d+%d",
                         plan.dstStart + 1, plan.dstStart + 2,
                         plan.dstStart, plan.dstStart + 1);
            }
            return false;
        }
    }

    if (plan.srcStart < plan.dstStart) {
        for (int tgt = plan.lo; tgt < plan.dstStart; tgt++) {
            int srcCh = tgt + plan.blockSize;
            plan.targetMap.push_back({tgt, srcCh - plan.lo});
        }
        for (int i = 0; i < plan.blockSize; i++) {
            plan.targetMap.push_back({plan.dstStart + i, plan.srcStart + i - plan.lo});
        }
    } else {
        for (int i = 0; i < plan.blockSize; i++) {
            plan.targetMap.push_back({plan.dstStart + i, plan.srcStart + i - plan.lo});
        }
        for (int tgt = plan.dstStart + plan.blockSize; tgt <= plan.hi; tgt++) {
            int srcCh = tgt - plan.blockSize;
            plan.targetMap.push_back({tgt, srcCh - plan.lo});
        }
    }

    return true;
}

static uint8_t remapMovedChannelRef(uint8_t oldRef, const MovePlan& plan) {
    int srcLo = plan.srcStart;
    int srcHi = plan.srcStart + plan.blockSize - 1;
    int dstLo = plan.dstStart;
    int dstHi = plan.dstStart + plan.blockSize - 1;

    if (oldRef >= srcLo && oldRef <= srcHi)
        return (uint8_t)(dstLo + (oldRef - srcLo));

    if (srcLo < dstLo) {
        if (oldRef > srcHi && oldRef <= dstHi)
            return (uint8_t)(oldRef - plan.blockSize);
    } else {
        if (oldRef >= dstLo && oldRef < srcLo)
            return (uint8_t)(oldRef + plan.blockSize);
    }

    return oldRef;
}

static PatchData remapPatchDataForMove(const PatchData& pd, int srcCh, int tgtCh) {
    PatchData out = pd;
    if (!isLocalAnaloguePatch(pd))
        return out;

    int delta = tgtCh - srcCh;
    int newNumber = (int)pd.source.number + delta;
    if (newNumber < 0 || newNumber > 127) {
        fprintf(stderr,
                "[MC]   WARN: patch remap src socket %u + delta %d is out of range for ch %d; keeping original\n",
                pd.source.number, delta, tgtCh + 1);
        return out;
    }

    out.source.number = (uint32_t)newNumber;
    fprintf(stderr,
            "[MC]   Patch remap srcCh %d -> tgtCh %d: local socket %u -> %u\n",
            srcCh + 1, tgtCh + 1, pd.source.number, out.source.number);
    return out;
}

static PatchData getTargetPatchDataForMove(const PatchData& pd, int srcCh, int tgtCh,
                                           bool movePatchWithChannel) {
    return movePatchWithChannel ? pd : remapPatchDataForMove(pd, srcCh, tgtCh);
}

// =============================================================================
// Move Channel
// =============================================================================
static bool moveChannel(int src, int dst, bool movePatchWithChannel = false, bool moveAdjacentMonoPair = false) {
    MovePlan plan;
    char planErr[256];
    if (!buildMovePlan(src, dst, moveAdjacentMonoPair, plan, planErr, sizeof(planErr))) {
        fprintf(stderr, "[MC] Unsupported move: %s\n", planErr[0] ? planErr : "unknown error");
        return false;
    }

    if (plan.srcStart == plan.dstStart) {
        fprintf(stderr, "[MC] Same position after normalization, nothing to do.\n");
        return true;
    }

    int lo = plan.lo;
    int hi = plan.hi;
    int rangeSize = hi - lo + 1;
    bool hadStereoConfigChange = false;
    std::vector<int> monoizedPairs;
    std::vector<int> stereoizedPairs;

    if (plan.srcStereo) {
        fprintf(stderr, "[MC] === MOVE ch %d → pos %d (normalized %d+%d → %d+%d, range %d-%d) [patching: %s] ===\n",
                src+1, dst+1,
                plan.srcStart+1, plan.srcStart+2,
                plan.dstStart+1, plan.dstStart+2,
                lo+1, hi+1,
                movePatchWithChannel ? "move with channel" : "shift by move amount");
    } else if (plan.srcMonoBlock) {
        fprintf(stderr, "[MC] === MOVE mono block %d+%d → %d+%d (range %d-%d) [patching: %s] ===\n",
                plan.srcStart+1, plan.srcStart+2,
                plan.dstStart+1, plan.dstStart+2,
                lo+1, hi+1,
                movePatchWithChannel ? "move with channel" : "shift by move amount");
    } else {
        fprintf(stderr, "[MC] === MOVE ch %d → pos %d (range %d-%d) [patching: %s] ===\n",
                src+1, dst+1, lo+1, hi+1,
                movePatchWithChannel ? "move with channel" : "shift by move amount");
    }
    if (plan.srcStereo) {
        fprintf(stderr, "[MC] Stereo source pair: %d+%d → %d+%d\n",
                plan.srcStart+1, plan.srcStart+2, plan.dstStart+1, plan.dstStart+2);
    }

    uint64_t moveStartMs = monotonicMs();
    auto phase = [&](const char* label) {
        fprintf(stderr, "[MC][%6llums] %s\n",
                (unsigned long long)(monotonicMs() - moveStartMs), label);
    };

    // Snapshot all channels in range
    phase("Phase: snapshot move range");
    std::vector<ChannelSnapshot> snaps(rangeSize);
    for (int i = 0; i < rangeSize; i++) {
        int ch = lo + i;
        fprintf(stderr, "[MC] Snapshot ch %d '%s'\n", ch+1,
                g_getChannelName(g_audioDM, 1, (uint8_t)ch));
        if (!snapshotChannel(ch, snaps[i])) {
            for (int j = 0; j < i; j++) destroySnapshot(snaps[j]);
            return false;
        }
    }

    // Remap sidechain channel references to account for position shifts.
    // After the move: src goes to dst, and channels in between shift by 1.
    // Any sidechain reference pointing to a channel in [lo..hi] needs remapping.
    phase("Phase: remap sidechain references");
    for (int i = 0; i < rangeSize; i++) {
        for (int p = 5; p <= 6; p++) { // SideChain1 (p=5), SideChain2 (p=6)
            if (!snaps[i].validB[p]) continue;
            uint8_t oldCh = snaps[i].dataB[p].buf[2];
            uint8_t newCh = remapMovedChannelRef(oldCh, plan);
            if (oldCh != newCh) {
                fprintf(stderr, "[MC]   Remap %s snap[%d] channel %d → %d\n",
                        g_procB[p].name, lo+i+1, oldCh, newCh);
                snaps[i].dataB[p].buf[2] = newCh;
            }
        }
    }

    if (!movePatchWithChannel) {
        struct PlannedPreampWrite {
            uint32_t socketNum;
            int srcCh;
            int tgtCh;
            PreampData data;
        };
        std::vector<PlannedPreampWrite> plannedWrites;
        for (auto& [tgtCh, si] : plan.targetMap) {
            if (!snaps[si].validPatch || !snaps[si].validPreamp) continue;
            int srcCh = lo + si;
            PatchData tgtPatch = getTargetPatchDataForMove(snaps[si].patchData, srcCh, tgtCh, movePatchWithChannel);
            if (!isLocalAnaloguePatch(tgtPatch)) continue;

            for (const auto& planned : plannedWrites) {
                if (planned.socketNum != tgtPatch.source.number) continue;
                if (!samePreampData(planned.data, snaps[si].preampData)) {
                    fprintf(stderr,
                            "[MC] ERROR: Scenario A preamp conflict on target socket %u:"
                            " ch %d -> %d wants gain=%d pad=%d phantom=%d,"
                            " but ch %d -> %d wants gain=%d pad=%d phantom=%d\n",
                            tgtPatch.source.number,
                            planned.srcCh + 1, planned.tgtCh + 1,
                            planned.data.gain, planned.data.pad, planned.data.phantom,
                            srcCh + 1, tgtCh + 1,
                            snaps[si].preampData.gain, snaps[si].preampData.pad, snaps[si].preampData.phantom);
                    for (int i = 0; i < rangeSize; i++) destroySnapshot(snaps[i]);
                    return false;
                }
            }

            plannedWrites.push_back({tgtPatch.source.number, srcCh, tgtCh, snaps[si].preampData});
        }
    }

    bool useDyn8LibraryExperiment = false;
    if (const char* libEnv = getenv("MC_AUTOTEST_DYN8_LIBRARY")) {
        useDyn8LibraryExperiment = (atoi(libEnv) != 0);
    }
    bool useInputLibraryExperiment = false;
    if (const char* libEnv = getenv("MC_AUTOTEST_INPUT_LIBRARY")) {
        useInputLibraryExperiment = (atoi(libEnv) != 0);
    }

    // Dyn8 is an external insert pool. Keep each channel bound to its original
    // pool unit when it moves instead of rebinding the insert to the target slot.
    struct Dyn8Transfer {
        int tgtUnitIdx;
        int tgtCh;
        int snapIdx;
        int ip;
        bool validData;
        uint8_t dyn8Data[0x94];
    };
    struct Dyn8LibraryRecall {
        int tgtCh;
        int tgtUnitIdx;
        int snapIdx;
        char presetName[128];
        char storedObjName[128];
    };
    struct InputLibraryRecall {
        int tgtCh;
        int snapIdx;
        char presetName[128];
    };
    std::vector<Dyn8Transfer> dyn8Transfers;
    std::vector<Dyn8LibraryRecall> dyn8LibraryRecalls;
    std::vector<InputLibraryRecall> inputLibraryRecalls;
    phase("Phase: preserve Dyn8 state");
    {
        for (auto& [tgtCh, si] : plan.targetMap) {
            for (int ip = 0; ip < 2; ip++) {
                if (snaps[si].insertInfo[ip].hasInsert && snaps[si].insertInfo[ip].parentType == 5) {
                    int dynIdx = findDyn8UnitIdx(snaps[si].insertInfo[ip].fxSendPt);
                    if (dynIdx < 0) {
                        fprintf(stderr,
                                "[MC] Dyn8 preserve: snap[%d] Insert%c on ch %d could not resolve unit index\n",
                                si, 'A' + ip, tgtCh + 1);
                        continue;
                    }
                    Dyn8Transfer xfer = {};
                    xfer.tgtUnitIdx = dynIdx;
                    xfer.tgtCh = tgtCh;
                    xfer.snapIdx = si;
                    xfer.ip = ip;
                    xfer.validData = false;
                    void* dynNetObj = getDynNetObj(dynIdx);
                    if (dynNetObj) {
                        safeRead((uint8_t*)dynNetObj + 0x98, xfer.dyn8Data, sizeof(xfer.dyn8Data));
                        xfer.validData = true;
                    }
                    fprintf(stderr,
                            "[MC] Dyn8 preserve: snap[%d] keeps Insert%c unit %d while moving to ch %d (data=%d)\n",
                            si, 'A' + ip, dynIdx, tgtCh + 1, xfer.validData ? 1 : 0);
                    dyn8Transfers.push_back(xfer);
                    if (useDyn8LibraryExperiment) {
                        Dyn8LibraryRecall recall = {};
                        recall.tgtCh = tgtCh;
                        recall.tgtUnitIdx = dynIdx;
                        recall.snapIdx = si;
                        snprintf(recall.presetName, sizeof(recall.presetName),
                                 "MC-DYN8-%d-%d-%d-%d",
                                 (int)getpid(), plan.srcStart + 1, plan.dstStart + 1, tgtCh + 1);
                        getDynUnitName(dynIdx, recall.storedObjName, sizeof(recall.storedObjName));
                        if (libraryStoreDyn8(dynIdx, recall.presetName)) {
                            fprintf(stderr,
                                    "[MC] Dyn8 library experiment: stored Insert%c unit %d for target ch %d as '%s'\n",
                                    'A' + ip, dynIdx, tgtCh + 1, recall.presetName);
                            dyn8LibraryRecalls.push_back(recall);
                        } else {
                            fprintf(stderr,
                                    "[MC] Dyn8 library experiment: failed to store Insert%c unit %d for target ch %d\n",
                                    'A' + ip, dynIdx, tgtCh + 1);
                        }
                    }
                }
            }
        }
    }
    auto refreshStereoDyn8Assignments = [&](const char* phaseTag) {
        if (g_dynRack) {
            typedef void (*fn_InputConfigurationChanged)(void* rack);
            auto inputConfigurationChanged = (fn_InputConfigurationChanged)RESOLVE(0x1005ce2f0);
            fprintf(stderr,
                    "[MC]   [%s] DynamicsRack InputConfigurationChanged (rack=%p)\n",
                    phaseTag, g_dynRack);
            inputConfigurationChanged(g_dynRack);
        }
        std::set<std::pair<int, int>> refreshedSlots;
        for (auto& xfer : dyn8Transfers) {
            if (!snaps[xfer.snapIdx].isStereo) continue;
            if ((xfer.tgtCh & 1) != 0) continue;
            if (!refreshedSlots.insert({xfer.tgtCh / 2, xfer.ip}).second) continue;
            assignDyn8InsertWithSetInserts(xfer.tgtCh, xfer.tgtUnitIdx, xfer.ip, 0, phaseTag);
            refreshDyn8InsertAssignment(xfer.tgtUnitIdx, xfer.tgtCh, phaseTag);
            refreshDyn8InsertAssignment(xfer.tgtUnitIdx + 1, xfer.tgtCh + 1, phaseTag);
        }
        QApplication::processEvents();
    };
    // =========================================================================
    // Stereo alignment: change stereo config at destination pairs if needed
    // Must happen AFTER snapshot (which preserves settings) but BEFORE recall.
    // The stereo config change calls Reset() on affected channels.
    // Channels IN the move range are already snapshotted and will be recalled.
    // Channels OUTSIDE the move range but in affected pairs must be separately
    // snapshotted and restored here.
    // =========================================================================
    phase("Phase: stereo alignment");
    {
        // Read current stereo config
        uint8_t config[64];
        bool configRead = readStereoConfig(config);
        bool configChanged = false;

        if (configRead) {
            std::set<int> pairsToChange;
            for (int tgtPair = lo / 2; tgtPair <= hi / 2; tgtPair++) {
                int evenCh = tgtPair * 2;
                int si = -1;
                for (auto& [tgtCh, snapIdx] : plan.targetMap) {
                    if (tgtCh == evenCh) {
                        si = snapIdx;
                        break;
                    }
                }
                if (si < 0) continue;

                bool snapStereo = snaps[si].isStereo;
                bool tgtCurrentStereo = (config[tgtPair] != 0);

                if (snapStereo != tgtCurrentStereo) {
                    config[tgtPair] = snapStereo ? 1 : 0;
                    pairsToChange.insert(tgtPair);
                    if (!snapStereo)
                        monoizedPairs.push_back(tgtPair);
                    else
                        stereoizedPairs.push_back(tgtPair);
                    fprintf(stderr, "[MC] Stereo align: pair %d (ch %d+%d) → %s (from snap '%s')\n",
                            tgtPair, tgtPair*2+1, tgtPair*2+2,
                            snapStereo ? "STEREO" : "MONO", snaps[si].name);
                    configChanged = true;
                }
            }

            if (configChanged) {
                hadStereoConfigChange = true;
                if (useInputLibraryExperiment) {
                    for (int pair : monoizedPairs) {
                        for (int ch = pair * 2; ch <= pair * 2 + 1; ch++) {
                            for (auto& [tgtCh, si] : plan.targetMap) {
                                if (tgtCh != ch) continue;
                                int srcCh = lo + si;
                                InputLibraryRecall recall = {};
                                recall.tgtCh = tgtCh;
                                recall.snapIdx = si;
                                snprintf(recall.presetName, sizeof(recall.presetName),
                                         "MC-ICH-%d-%d-%d-%d",
                                         (int)getpid(), plan.srcStart + 1, plan.dstStart + 1, tgtCh + 1);
                                if (libraryStoreInputChannel(srcCh, recall.presetName)) {
                                    inputLibraryRecalls.push_back(recall);
                                } else {
                                    fprintf(stderr,
                                            "[MC] input library experiment: failed to store ch %d for target %d\n",
                                            srcCh + 1, tgtCh + 1);
                                }
                                break;
                            }
                        }
                    }
                }
                // Find channels OUTSIDE the move range [lo..hi] that are in affected pairs
                // and snapshot them so we can restore after the stereo config change.
                std::vector<std::pair<int, ChannelSnapshot>> extraSnaps;
                for (int pair : pairsToChange) {
                    int ch_even = pair * 2;
                    int ch_odd  = pair * 2 + 1;
                    // Check if even channel is outside move range
                    if (ch_even < lo || ch_even > hi) {
                        ChannelSnapshot es;
                        if (snapshotChannel(ch_even, es)) {
                            extraSnaps.push_back({ch_even, std::move(es)});
                            fprintf(stderr, "[MC] Extra snapshot: ch %d '%s' (outside move range, in affected pair %d)\n",
                                    ch_even+1, es.name, pair);
                        }
                    }
                    // Check if odd channel is outside move range
                    if (ch_odd < lo || ch_odd > hi) {
                        ChannelSnapshot es;
                        if (snapshotChannel(ch_odd, es)) {
                            extraSnaps.push_back({ch_odd, std::move(es)});
                            fprintf(stderr, "[MC] Extra snapshot: ch %d '%s' (outside move range, in affected pair %d)\n",
                                    ch_odd+1, es.name, pair);
                        }
                    }
                }

                fprintf(stderr, "[MC] Applying stereo config changes (%zu pairs, %zu extra snapshots)...\n",
                        pairsToChange.size(), extraSnaps.size());
                if (!applyStereoConfigAndRefresh(config, "[MC] moveChannel stereo align")) {
                    fprintf(stderr, "[MC] WARNING: failed to apply stereo config via discovery path!\n");
                } else {
                    fprintf(stderr, "[MC] Stereo config applied.\n");

                    // Restore extra snapshots (channels outside move range)
                    for (auto& [eCh, eSnap] : extraSnaps) {
                        fprintf(stderr, "[MC] Restoring extra snapshot: ch %d '%s'\n", eCh+1, eSnap.name);
                        recallChannel(eCh, eSnap);
                    }
                }

                // Cleanup extra snapshots
                for (auto& [eCh, eSnap] : extraSnaps) {
                    destroySnapshot(eSnap);
                }
            } else {
                fprintf(stderr, "[MC] No stereo config changes needed.\n");
            }
        }
    }

    // Write in new order. Preamp state is restored separately after patching,
    // because gain/pad/phantom live on the assigned socket, not on the strip.
    bool skipPreamp = true;
    phase("Phase: recall channels to target positions");
    for (auto& [tgtCh, si] : plan.targetMap) {
        fprintf(stderr, "[MC] Recall '%s' → pos %d\n", snaps[si].name, tgtCh+1);
        recallChannel(tgtCh, snaps[si], skipPreamp);
    }

    phase("Phase: rewrite patching");
    fprintf(stderr, "[MC] Writing patching (%s)...\n",
            movePatchWithChannel ? "move sockets with channel" : "shift sockets by move amount");
        // Use CSV import path: cChannel::SetInputChannelSource via task system
        // This is what Import CSV uses — full update + UI refresh
        typedef void* (*fn_GetChannel)(void* mgr, uint32_t stripType, uint8_t chNum);
        auto getChannel = (fn_GetChannel)RESOLVE(0x1006e3f90);

        typedef void* (*fn_GetSendPoint)(void* mgr, uint32_t sourceType, uint16_t sourceNum);
        auto getSendPoint = (fn_GetSendPoint)RESOLVE(0x1006ce8e0);

        typedef void (*fn_SetInputChannelSource)(void* channel, int activeInputSource,
                                                  void* sendPt, void* sendPt2);
        auto setInputSource = (fn_SetInputChannelSource)RESOLVE(0x1006d8410);

        for (auto& [tgtCh, si] : plan.targetMap) {
            if (!snaps[si].validPatch) continue;
            int srcCh = lo + si;
            PatchData tgtPatch = getTargetPatchDataForMove(snaps[si].patchData, srcCh, tgtCh, movePatchWithChannel);

            bool tgtStereo = isChannelStereo(tgtCh);
            if (tgtStereo && (tgtCh & 1)) {
                fprintf(stderr,
                        "[MC]   Patch ch %d skipped; stereo pair handled by ch %d\n",
                        tgtCh + 1, tgtCh);
                continue;
            }

            sAudioSource& src = tgtPatch.source;
            fprintf(stderr, "[MC]   Patch ch %d: srcType=%d src={type=%d, num=%d}\n",
                    tgtCh+1, tgtPatch.sourceType,
                    src.type, src.number);

            if (!g_channelManager || !g_audioSRPManager) {
                fprintf(stderr, "[MC]   WARN: channelMgr or audioSRPMgr not available, falling back to writePatchData\n");
                writePatchData(tgtCh, tgtPatch);
                continue;
            }

            void* ch = getChannel(g_channelManager, 1/*Input*/, (uint8_t)tgtCh);
            if (!ch) {
                fprintf(stderr, "[MC]   WARN: GetChannel(%d) returned null\n", tgtCh);
                writePatchData(tgtCh, tgtPatch);
                continue;
            }

            void* sendPtA = getSendPoint(g_audioSRPManager, src.type, (uint16_t)src.number);
            void* sendPtB = nullptr;

            if (tgtStereo) {
                int pairMateCh = tgtCh + 1;
                int mateSnapIdx = -1;
                for (auto& [mappedTgtCh, mappedSi] : plan.targetMap) {
                    if (mappedTgtCh == pairMateCh) {
                        mateSnapIdx = mappedSi;
                        break;
                    }
                }
                if (mateSnapIdx >= 0 && snaps[mateSnapIdx].validPatch) {
                    int mateSrcCh = lo + mateSnapIdx;
                    PatchData matePatch = getTargetPatchDataForMove(
                        snaps[mateSnapIdx].patchData, mateSrcCh, pairMateCh, movePatchWithChannel);
                    sAudioSource& mateSrc = matePatch.source;
                    sendPtB = getSendPoint(g_audioSRPManager, mateSrc.type, (uint16_t)mateSrc.number);
                    fprintf(stderr,
                            "[MC]   Stereo patch pair ch %d+%d: A={type=%d,num=%d}->%p B={type=%d,num=%d}->%p\n",
                            tgtCh + 1, pairMateCh + 1,
                            src.type, src.number, sendPtA,
                            mateSrc.type, mateSrc.number, sendPtB);
                } else {
                    fprintf(stderr,
                            "[MC]   WARN: stereo target ch %d missing pair mate patch snapshot; falling back to single source\n",
                            tgtCh + 1);
                }
            } else {
                fprintf(stderr, "[MC]   ch=%p sendPt=%p\n", ch, sendPtA);
            }

            setInputSource(ch, 1, sendPtA, sendPtB);
        }
        fprintf(stderr, "[MC]   Patching applied via SetInputChannelSource.\n");
    phase("Phase: restore preamp sockets");
    for (auto& [tgtCh, si] : plan.targetMap) {
        if (!snaps[si].validPreamp || !snaps[si].validPatch) continue;
        int srcCh = lo + si;
        PatchData tgtPatch = getTargetPatchDataForMove(snaps[si].patchData, srcCh, tgtCh, movePatchWithChannel);
        if (!isLocalAnaloguePatch(tgtPatch)) continue;
        if (writePreampDataForPatch(tgtPatch, snaps[si].preampData)) {
            fprintf(stderr,
                    "[MC]   Restore preamp for ch %d on socket %u: gain=%d pad=%d phantom=%d\n",
                    tgtCh + 1, tgtPatch.source.number,
                    snaps[si].preampData.gain, snaps[si].preampData.pad, snaps[si].preampData.phantom);
        } else {
            fprintf(stderr,
                    "[MC]   WARN: preamp restore failed for ch %d on socket %u\n",
                    tgtCh + 1, tgtPatch.source.number);
        }
    }

    auto replayDyn8Settings = [&](const char* phaseTag) {
        if (dyn8Transfers.empty()) return;

        fprintf(stderr, "[MC] Dyn8 system-level transfer phase '%s' (%zu entries)...\n",
                phaseTag, dyn8Transfers.size());
        typedef void (*fn_setAllDataUI)(void* obj, void* sDynData);
        auto setAllDataUI = (fn_setAllDataUI)RESOLVE(0x100239970);
        typedef void (*fn_setDynData)(void* system, void* key, void* data);
        auto setDynData = (fn_setDynData)RESOLVE(0x100239240);
        typedef void (*fn_fullDriverUpdate)(void* system);
        auto fullDriverUpdate = (fn_fullDriverUpdate)RESOLVE(0x10023c6c0);

        for (auto& xfer : dyn8Transfers) {
            void* tgtDynObj = getDynNetObj(xfer.tgtUnitIdx);
            if (!tgtDynObj) {
                fprintf(stderr, "[MC]   [%s] Dyn8 unit %d: getDynNetObj returned null!\n",
                        phaseTag, xfer.tgtUnitIdx);
                continue;
            }
            if (!xfer.validData) {
                fprintf(stderr, "[MC]   [%s] Dyn8 snap[%d] Insert%c unit %d: no valid data!\n",
                        phaseTag, xfer.snapIdx, 'A' + xfer.ip, xfer.tgtUnitIdx);
                continue;
            }

            void* dynSystem = nullptr;
            safeRead((uint8_t*)tgtDynObj + 0x90, &dynSystem, sizeof(dynSystem));
            uint8_t dynKey[8] = {};
            safeRead((uint8_t*)tgtDynObj + 0x88, dynKey, 8);

            fprintf(stderr, "[MC]   [%s] Dyn8 unit %d: obj=%p system=%p key={%u,%u} type=%u\n",
                    phaseTag, xfer.tgtUnitIdx, tgtDynObj, dynSystem,
                    *(uint32_t*)dynKey, (uint32_t)dynKey[4],
                    *(uint32_t*)xfer.dyn8Data);

            setAllDataUI(tgtDynObj, xfer.dyn8Data);

            if (dynSystem) {
                setDynData(dynSystem, dynKey, xfer.dyn8Data);
                uint8_t one = 1;
                safeWrite((uint8_t*)dynSystem + 0xca9, &one, 1);
                fullDriverUpdate(dynSystem);
                fprintf(stderr, "[MC]   [%s] SetDynamicsData + FullDriverUpdate done\n", phaseTag);
            } else {
                fprintf(stderr, "[MC]   [%s] WARNING: cDynamicsSystem is null!\n", phaseTag);
            }

            void* duc = getDynUnitClient(xfer.tgtUnitIdx);
            if (duc) {
                typedef void (*fn_cAHNetMessage_ctor)(void* msg);
                typedef void (*fn_cAHNetMessage_dtor)(void* msg);
                typedef void (*fn_SetLength)(void* msg, uint32_t len);
                typedef void (*fn_SetDataBufferUBYTE)(void* msg, uint8_t val, uint32_t offset);
                typedef void (*fn_PackBandsWide)(void* msg, void* data, int param);
                typedef void (*fn_PackSideChain)(void* msg, void* data, int param);
                typedef void (*fn_EntrypointMessage)(void* duc, void* msg);

                auto msgCtor     = (fn_cAHNetMessage_ctor)RESOLVE(0x1000e9790);
                auto msgDtor     = (fn_cAHNetMessage_dtor)RESOLVE(0x1000e9810);
                auto setLen      = (fn_SetLength)RESOLVE(0x1000e9ee0);
                auto setUBYTE    = (fn_SetDataBufferUBYTE)RESOLVE(0x1000ebde0);
                auto packBands   = (fn_PackBandsWide)RESOLVE(0x1000cded0);
                auto packSC      = (fn_PackSideChain)RESOLVE(0x1000cdfd0);
                auto entrypoint  = (fn_EntrypointMessage)RESOLVE(0x1005e9140);

                uint32_t ducKey = 0;
                safeRead((uint8_t*)duc + 0x68, &ducKey, 4);
                bool sendInsertIn = false;
                if (const char* env = getenv("MC_DYN8_INSERTIN")) {
                    sendInsertIn = (atoi(env) != 0);
                }
                bool callCreateInsertIn = false;
                if (const char* env = getenv("MC_DYN8_CREATE_INSERT_IN")) {
                    callCreateInsertIn = (atoi(env) != 0);
                }
                typedef void (*fn_CreateInsertInAssignment)(void* duc);
                auto createInsertInAssignment = (fn_CreateInsertInAssignment)RESOLVE(0x1005e8330);

                uint8_t msgBuf[64];

                memset(msgBuf, 0, sizeof(msgBuf));
                msgCtor(msgBuf);
                *(uint16_t*)(msgBuf + 0x10) = 0;
                *(uint32_t*)(msgBuf + 0x14) = ducKey;
                *(uint32_t*)(msgBuf + 0x18) = ducKey;
                *(uint32_t*)(msgBuf + 0x1c) = 0x1001;
                setLen(msgBuf, 1);
                setUBYTE(msgBuf, xfer.dyn8Data[0], 0);
                entrypoint(duc, msgBuf);
                msgDtor(msgBuf);

                memset(msgBuf, 0, sizeof(msgBuf));
                msgCtor(msgBuf);
                *(uint16_t*)(msgBuf + 0x10) = 0;
                *(uint32_t*)(msgBuf + 0x14) = ducKey;
                *(uint32_t*)(msgBuf + 0x18) = ducKey;
                *(uint32_t*)(msgBuf + 0x1c) = 0x1002;
                setLen(msgBuf, 8);
                packBands(msgBuf, xfer.dyn8Data, 0);
                entrypoint(duc, msgBuf);
                msgDtor(msgBuf);

                memset(msgBuf, 0, sizeof(msgBuf));
                msgCtor(msgBuf);
                *(uint16_t*)(msgBuf + 0x10) = 0;
                *(uint32_t*)(msgBuf + 0x14) = ducKey;
                *(uint32_t*)(msgBuf + 0x18) = ducKey;
                *(uint32_t*)(msgBuf + 0x1c) = 0x1003;
                setLen(msgBuf, 0xa);
                packSC(msgBuf, xfer.dyn8Data, 0);
                entrypoint(duc, msgBuf);
                msgDtor(msgBuf);

                if (sendInsertIn) {
                    memset(msgBuf, 0, sizeof(msgBuf));
                    msgCtor(msgBuf);
                    *(uint16_t*)(msgBuf + 0x10) = 0;
                    *(uint32_t*)(msgBuf + 0x14) = ducKey;
                    *(uint32_t*)(msgBuf + 0x18) = ducKey;
                    *(uint32_t*)(msgBuf + 0x1c) = 0x1004;
                    setLen(msgBuf, 1);
                    setUBYTE(msgBuf, 1, 0);
                    entrypoint(duc, msgBuf);
                    msgDtor(msgBuf);
                    fprintf(stderr, "[MC]   [%s] DUC %p: sent 0x1004 InsertIn(true)\n", phaseTag, duc);
                }

                if (callCreateInsertIn) {
                    fprintf(stderr, "[MC]   [%s] DUC %p: calling CreateInsertInAssignment()\n",
                            phaseTag, duc);
                    createInsertInAssignment(duc);
                }

                fprintf(stderr, "[MC]   [%s] DUC %p: sent 0x1001+0x1002+0x1003 via EntrypointMessage\n",
                        phaseTag, duc);
            } else {
                fprintf(stderr, "[MC]   [%s] WARNING: getDynUnitClient(%d) returned null!\n",
                        phaseTag, xfer.tgtUnitIdx);
            }

            uint8_t afterRecall[0x94] = {0};
            safeRead((uint8_t*)tgtDynObj + 0x98, afterRecall, 0x94);
            int match = 0;
            for (int b = 0; b < 0x94; b++) {
                if (afterRecall[b] == xfer.dyn8Data[b]) match++;
            }
            fprintf(stderr, "[MC]   [%s] Insert%c unit %d: %d/148 bytes match source\n",
                    phaseTag, 'A' + xfer.ip, xfer.tgtUnitIdx, match);
        }
    };

    // Insert routing: reassign FX units to new channel positions
    // Strategy: first unassign ALL unique FX units, then reassign to new channels.
    // This avoids the "FX unit is already assigned" conflict when moving shared FX units.
    // Hidden struct return ABI: rdi=&retList, rsi=this, rdx/ecx=params
    {
        phase("Phase: initial insert and Dyn8 routing");
        fprintf(stderr, "[MC] Reassigning insert FX units...\n");
        replayInsertRouting(plan, snaps, "initial");
        refreshStereoDyn8Assignments("post-initial-dyn8-refresh");
        fprintf(stderr, "[MC]   Insert reassignment done.\n");
        replayDyn8Settings("initial");
    }

    if (hadStereoConfigChange) {
        phase("Phase: post-stereo routing settle");
        waitForStereoConfigReset();
        replayInsertRouting(plan, snaps, "post-settle");
        refreshStereoDyn8Assignments("post-settle-dyn8-refresh");
        waitForStereoConfigReset();
        replayInsertRouting(plan, snaps, "final");
        refreshStereoDyn8Assignments("post-final-dyn8-refresh");
    }

    if (hadStereoConfigChange)
        waitForStereoConfigReset();

    if (hadStereoConfigChange) {
        phase("Phase: full settle recall");
        for (auto& [tgtCh, si] : plan.targetMap) {
            fprintf(stderr, "[MC] Full settle recall '%s' → pos %d\n", snaps[si].name, tgtCh+1);
            recallChannel(tgtCh, snaps[si], skipPreamp);
        }
        waitForStereoConfigReset();
    }

    phase("Phase: restore delay and proc order");
    for (auto& [tgtCh, si] : plan.targetMap) {
        if (snaps[si].validB[1]) {
            uint16_t wantDelay = ((uint16_t)snaps[si].dataB[1].buf[1] << 8) | snaps[si].dataB[1].buf[2];
            bool wantBypass = snaps[si].dataB[1].buf[3] != 0;
            setDelayForChannel(tgtCh, wantDelay, wantBypass);
        }
        writeProcOrderForChannel(tgtCh, snaps[si]);
    }

    if (hadStereoConfigChange) {
        phase("Phase: stereo split stabilization");
        waitForStereoConfigReset();
        waitForStereoConfigReset();
        replayInsertRouting(plan, snaps, "post-final-state");
        refreshStereoDyn8Assignments("post-final-state-dyn8-refresh");
        waitForStereoConfigReset();
        for (auto it = plan.targetMap.rbegin(); it != plan.targetMap.rend(); ++it) {
            int tgtCh = it->first;
            int si = it->second;
            fprintf(stderr, "[MC] Late Type A settle '%s' → pos %d\n", snaps[si].name, tgtCh+1);
            recallTypeAForChannel(tgtCh, snaps[si]);
            waitForStereoConfigReset();
        }
        for (int pair : monoizedPairs) {
            for (int ch = pair * 2 + 1; ch >= pair * 2; ch--) {
                for (auto& [tgtCh, si] : plan.targetMap) {
                    if (tgtCh != ch) continue;
                    fprintf(stderr, "[MC] Mono split settle '%s' → pos %d\n", snaps[si].name, tgtCh+1);
                    recallTypeAForChannel(tgtCh, snaps[si]);
                    waitForStereoConfigReset();
                    break;
                }
            }
        }
        replayInsertRouting(plan, snaps, "post-typea-settle");
        refreshStereoDyn8Assignments("post-typea-dyn8-refresh");
        waitForStereoConfigReset();
        for (auto& [tgtCh, si] : plan.targetMap)
            writeProcOrderForChannel(tgtCh, snaps[si]);
        waitForStereoConfigReset();
        for (int pair : monoizedPairs) {
            for (int ch = pair * 2; ch <= pair * 2 + 1; ch++) {
                for (auto& [tgtCh, si] : plan.targetMap) {
                    if (tgtCh != ch || !snaps[si].validB[1]) continue;
                    uint16_t wantDelay = ((uint16_t)snaps[si].dataB[1].buf[1] << 8) | snaps[si].dataB[1].buf[2];
                    bool wantBypass = snaps[si].dataB[1].buf[3] != 0;
                    fprintf(stderr, "[MC] Mono split delay settle '%s' → pos %d\n", snaps[si].name, tgtCh+1);
                    setDelayForChannel(tgtCh, wantDelay, wantBypass);
                    waitForStereoConfigReset();
                    break;
                }
            }
        }
        replayInsertRouting(plan, snaps, "post-delay-settle");
        refreshStereoDyn8Assignments("post-delay-dyn8-refresh");
        waitForStereoConfigReset();
        for (int pair : monoizedPairs) {
            for (int ch = pair * 2; ch <= pair * 2 + 1; ch++) {
                resetInputProcessingGangMaster(ch, "mono-split-ungang");
                waitForStereoConfigReset();
            }
        }
        for (int pair : monoizedPairs) {
            for (int ch = pair * 2; ch <= pair * 2 + 1; ch++) {
                for (auto& [tgtCh, si] : plan.targetMap) {
                    if (tgtCh != ch) continue;
                    fprintf(stderr, "[MC] Mono split final full settle '%s' → pos %d\n", snaps[si].name, tgtCh+1);
                    recallChannel(tgtCh, snaps[si], skipPreamp);
                    waitForStereoConfigReset();
                    break;
                }
            }
        }
        replayInsertRouting(plan, snaps, "post-mono-full-settle");
        refreshStereoDyn8Assignments("post-mono-full-dyn8-refresh");
        waitForStereoConfigReset();
    }

    if (useInputLibraryExperiment && !inputLibraryRecalls.empty()) {
        phase("Phase: input library experiment recall");
        fprintf(stderr, "[MC] Input channel library experiment recall phase (%zu entries)...\n",
                inputLibraryRecalls.size());
        for (auto& recall : inputLibraryRecalls) {
            libraryRecallInputChannel(recall.tgtCh, recall.presetName);
            waitForStereoConfigReset();
        }
        replayInsertRouting(plan, snaps, "post-input-lib");
        refreshStereoDyn8Assignments("post-input-lib-dyn8-refresh");
        waitForStereoConfigReset();
    }

    if (useDyn8LibraryExperiment && !dyn8LibraryRecalls.empty()) {
        phase("Phase: Dyn8 library experiment recall");
        fprintf(stderr, "[MC] Dyn8 library experiment recall phase (%zu entries)...\n",
                dyn8LibraryRecalls.size());
        replayInsertRouting(plan, snaps, "pre-lib-recall");
        refreshStereoDyn8Assignments("pre-lib-recall-dyn8-refresh");
        waitForStereoConfigReset();
        bool tryDyn8SetInserts = false;
        if (const char* setInsertsEnv = getenv("MC_AUTOTEST_DYN8_SETINSERTS")) {
            tryDyn8SetInserts = (atoi(setInsertsEnv) != 0);
        }
        for (auto& recall : dyn8LibraryRecalls) {
            ChannelSnapshot beforeCh;
            bool beforeOk = snapshotChannel(recall.tgtCh, beforeCh);

            if (tryDyn8SetInserts && beforeOk && !beforeCh.validDyn8) {
                for (int variant = 0; variant < 2 && !beforeCh.validDyn8; variant++) {
                    if (!assignDyn8InsertWithSetInserts(recall.tgtCh, recall.tgtUnitIdx, 0, variant, "pre-lib-recall"))
                        continue;
                    waitForStereoConfigReset();
                    destroySnapshot(beforeCh);
                    beforeOk = snapshotChannel(recall.tgtCh, beforeCh);
                    fprintf(stderr,
                            "[MC] Dyn8 library experiment: after SetInserts variant=%d ch %d validDyn8=%d InsertA type=%d\n",
                            variant, recall.tgtCh + 1, beforeCh.validDyn8, beforeCh.insertInfo[0].parentType);
                }
            }

            uint8_t before[0x94] = {};
            void* tgtDynObj = getDynNetObj(recall.tgtUnitIdx);
            if (tgtDynObj)
                safeRead((uint8_t*)tgtDynObj + 0x98, before, sizeof(before));

            fprintf(stderr,
                    "[MC] Dyn8 library experiment: recalling '%s' (obj '%s') onto ch %d / unit %d\n",
                    recall.presetName, recall.storedObjName, recall.tgtCh + 1, recall.tgtUnitIdx);
            libraryRecallDyn8(recall.tgtCh, recall.presetName, recall.storedObjName);
            waitForStereoConfigReset();

            uint8_t after[0x94] = {};
            int changed = 0;
            if (tgtDynObj)
                safeRead((uint8_t*)tgtDynObj + 0x98, after, sizeof(after));
            for (size_t i = 0; i < sizeof(after); i++) {
                if (before[i] != after[i]) changed++;
            }

            ChannelSnapshot afterCh;
            bool afterOk = snapshotChannel(recall.tgtCh, afterCh);
            fprintf(stderr,
                    "[MC] Dyn8 library experiment: recall changed %d/148 bytes on unit %d\n",
                    changed, recall.tgtUnitIdx);
            if (beforeOk && afterOk) {
                fprintf(stderr,
                        "[MC] Dyn8 library experiment: ch %d validDyn8 %d -> %d, InsertA type %d -> %d\n",
                        recall.tgtCh + 1,
                        beforeCh.validDyn8, afterCh.validDyn8,
                        beforeCh.insertInfo[0].parentType, afterCh.insertInfo[0].parentType);
            }
            if (beforeOk) destroySnapshot(beforeCh);
            if (afterOk) destroySnapshot(afterCh);
        }
    }

    if (hadStereoConfigChange) {
        phase("Phase: final stabilize and refresh");
        waitForStereoConfigReset();
        for (auto& [tgtCh, si] : plan.targetMap) {
            writeProcOrderForChannel(tgtCh, snaps[si]);
        }
        waitForStereoConfigReset();
        for (int pair : monoizedPairs) {
            for (int ch = pair * 2; ch <= pair * 2 + 1; ch++) {
                for (auto& [tgtCh, si] : plan.targetMap) {
                    if (tgtCh != ch) continue;
                    replayMixerAssignmentsForChannel(tgtCh, snaps[si], "post-final-mixer-assigns");
                    waitForStereoConfigReset();
                    break;
                }
            }
        }
        for (int pair : stereoizedPairs) {
            for (int ch = pair * 2; ch <= pair * 2 + 1; ch++) {
                for (auto& [tgtCh, si] : plan.targetMap) {
                    if (tgtCh != ch) continue;
                    replayMixerAssignmentsForChannel(tgtCh, snaps[si], "post-final-stereo-mixer-assigns");
                    waitForStereoConfigReset();
                    break;
                }
            }
        }
        waitForStereoConfigReset();
        waitForStereoConfigReset();
        replayInsertRouting(plan, snaps, "post-final-stabilize");
        refreshStereoDyn8Assignments("post-final-stabilize-dyn8-refresh");
        replayDyn8Settings("post-final-stabilize");
        for (int pair : monoizedPairs) {
            for (int ch = pair * 2; ch <= pair * 2 + 1; ch++) {
                refreshSideChainStateForChannel(ch, "post-final-sidechain-refresh");
                waitForStereoConfigReset();
            }
        }
        for (int pair : stereoizedPairs) {
            for (int ch = pair * 2; ch <= pair * 2 + 1; ch++) {
                refreshSideChainStateForChannel(ch, "post-final-stereo-sidechain-refresh");
                waitForStereoConfigReset();
            }
        }
        QApplication::processEvents();
        for (auto& [tgtCh, _] : plan.targetMap) {
            ChannelSnapshot live = {};
            if (!snapshotChannel(tgtCh, live)) continue;
            fprintf(stderr,
                    "[MC]   [post-final-stabilize] live ch %d: validDyn8=%d InsertA type=%d send=%p recv=%p InsertB type=%d send=%p recv=%p\n",
                    tgtCh + 1,
                    live.validDyn8 ? 1 : 0,
                    live.insertInfo[0].parentType,
                    live.insertInfo[0].fxSendPt,
                    live.insertInfo[0].fxReceivePt,
                    live.insertInfo[1].parentType,
                    live.insertInfo[1].fxSendPt,
                    live.insertInfo[1].fxReceivePt);
            destroySnapshot(live);
        }
    }

    for (int i = 0; i < rangeSize; i++) destroySnapshot(snaps[i]);

    if (!dyn8LibraryRecalls.empty()) {
        fprintf(stderr, "[MC] Dyn8 library experiment cleanup (%zu entries)...\n",
                dyn8LibraryRecalls.size());
        for (auto& recall : dyn8LibraryRecalls) {
            if (!libraryDeleteDyn8(recall.presetName)) {
                fprintf(stderr, "[MC] Dyn8 library experiment: failed to delete '%s'\n",
                        recall.presetName);
            }
        }
    }
    if (!inputLibraryRecalls.empty()) {
        fprintf(stderr, "[MC] Input channel library experiment cleanup (%zu entries)...\n",
                inputLibraryRecalls.size());
        for (auto& recall : inputLibraryRecalls) {
            if (!libraryDeleteInputChannel(recall.presetName)) {
                fprintf(stderr, "[MC] input library experiment: failed to delete '%s'\n",
                        recall.presetName);
            }
        }
    }

    // Verify
    phase("Phase: verify final state");
    fprintf(stderr, "[MC] === Verify after move ===\n");
    for (int i = lo; i <= hi; i++) {
        const char* name = g_getChannelName(g_audioDM, 1, (uint8_t)i);

        // Read back digital trim to check if write persisted
        void* ic = getInputChannel(i);
        void* dtObj = ic ? getTypeBObj(ic, g_procB[0]) : nullptr;
        int16_t trimVal = 0;
        if (dtObj) {
            void* gp = nullptr;
            safeRead((uint8_t*)dtObj + 0x98, &gp, sizeof(gp));
            if (gp && (uintptr_t)gp > 0x100000000ULL)
                safeRead(gp, &trimVal, 2);
        }
        float trimDb = (trimVal - 3) / 256.0f;

        fprintf(stderr, "[MC] Pos %d: '%s' trim=%.1f dB (%d)\n", i+1, name ? name : "", trimDb, trimVal);
    }

    phase("Phase: move complete");
    return true;
}

// Forward declarations for UI
static void dumpChannelData(int ch, const char* label);

// =============================================================================
// UI Dialog
// =============================================================================
static QDialog* g_dialog = nullptr;

static void showMoveDialog() {
    if (g_dialog) { g_dialog->show(); g_dialog->raise(); g_dialog->activateWindow(); return; }

    g_dialog = new QDialog(nullptr, Qt::WindowStaysOnTopHint);
    g_dialog->setWindowTitle("Move Channel");
    g_dialog->setMinimumWidth(300);
    // Dialog persists — never destroyed, just hidden/shown

    auto* layout = new QVBoxLayout(g_dialog);

    auto* srcLayout = new QHBoxLayout();
    srcLayout->addWidget(new QLabel("Source Channel:"));
    auto* srcSpin = new QSpinBox();
    srcSpin->setRange(1, 128);
    srcSpin->setValue(1);
    srcLayout->addWidget(srcSpin);
    auto* srcStereoLabel = new QLabel("[Mono]");
    srcLayout->addWidget(srcStereoLabel);
    layout->addLayout(srcLayout);

    auto* dstLayout = new QHBoxLayout();
    dstLayout->addWidget(new QLabel("Destination Position:"));
    auto* dstSpin = new QSpinBox();
    dstSpin->setRange(1, 128);
    dstSpin->setValue(1);
    dstLayout->addWidget(dstSpin);
    auto* dstStereoLabel = new QLabel("[Mono]");
    dstLayout->addWidget(dstStereoLabel);
    layout->addLayout(dstLayout);

    // Update stereo status labels when spinbox values change
    auto updateStereoLabels = [=]() {
        int srcCh = srcSpin->value() - 1;
        int dstCh = dstSpin->value() - 1;
        bool srcSt = isChannelStereo(srcCh);
        bool dstSt = isChannelStereo(dstCh);
        int srcPairStart = srcSt ? (srcCh & ~1) : srcCh;
        int dstPairStart = dstSt ? (dstCh & ~1) : dstCh;
        srcStereoLabel->setText(srcSt ? QString("[Stereo %1+%2]").arg(srcPairStart+1).arg(srcPairStart+2) : "[Mono]");
        dstStereoLabel->setText(dstSt ? QString("[Stereo %1+%2]").arg(dstPairStart+1).arg(dstPairStart+2) : "[Mono]");
    };

    auto* patchCheck = new QCheckBox("Move preamp socket with channel (Scenario B)");
    patchCheck->setChecked(false);
    layout->addWidget(patchCheck);

    auto* monoPairCheck = new QCheckBox("Move two adjacent mono channels as one block");
    monoPairCheck->setChecked(false);
    layout->addWidget(monoPairCheck);

    auto* moveHintLabel = new QLabel();
    moveHintLabel->setWordWrap(true);
    layout->addWidget(moveHintLabel);

    auto* statusLabel = new QLabel("Ready.");
    statusLabel->setWordWrap(true);
    layout->addWidget(statusLabel);

    auto* btnLayout = new QHBoxLayout();
    auto* moveBtn = new QPushButton("Move");
    auto* testStereoBtn = new QPushButton("Test Stereo");
    auto* closeBtn = new QPushButton("Close");
    btnLayout->addWidget(moveBtn);
    btnLayout->addWidget(testStereoBtn);
    btnLayout->addWidget(closeBtn);
    layout->addLayout(btnLayout);

    auto updateMoveUi = [=]() {
        updateStereoLabels();

        int srcCh = srcSpin->value() - 1;
        int dstCh = dstSpin->value() - 1;
        bool srcSt = isChannelStereo(srcCh);
        bool canUseMonoPair = false;
        if (!srcSt && srcCh < 127) {
            canUseMonoPair = !isChannelStereo(srcCh + 1);
        }
        monoPairCheck->setEnabled(canUseMonoPair);
        if (!canUseMonoPair) monoPairCheck->setChecked(false);

        MovePlan plan;
        char err[256];
        if (!buildMovePlan(srcCh, dstCh, monoPairCheck->isChecked(), plan, err, sizeof(err))) {
            moveHintLabel->setText(QString("Unsupported right now: %1.").arg(err));
            moveBtn->setEnabled(false);
            return;
        }

        if (plan.srcStereo) {
            QString text = QString("Stereo move: ch %1+%2 will move together to %3+%4.")
                .arg(plan.srcStart + 1).arg(plan.srcStart + 2)
                .arg(plan.dstStart + 1).arg(plan.dstStart + 2);
            if (plan.rawSrc != plan.srcStart || plan.rawDst != plan.dstStart)
                text += " Selection normalized to the stereo pair boundary.";
            text += patchCheck->isChecked()
                ? " Patching/preamp socket will move with the channel."
                : " Patching/preamp socket will shift by the move amount.";
            moveHintLabel->setText(text);
        } else if (plan.srcMonoBlock) {
            QString text = QString("Two-mono block move: ch %1+%2 will move together to %3+%4.")
                .arg(plan.srcStart + 1).arg(plan.srcStart + 2)
                .arg(plan.dstStart + 1).arg(plan.dstStart + 2);
            text += patchCheck->isChecked()
                ? " Patching/preamp socket will move with the channel."
                : " Patching/preamp socket will shift by the move amount.";
            moveHintLabel->setText(text);
        } else {
            moveHintLabel->setText(patchCheck->isChecked()
                ? "Mono move: affected range is all mono. Patching/preamp socket will move with the channel."
                : "Mono move: affected range is all mono. Patching/preamp socket will shift by the move amount.");
        }

        moveBtn->setEnabled(true);
    };

    QObject::connect(srcSpin, QOverload<int>::of(&QSpinBox::valueChanged), [=](int) { updateMoveUi(); });
    QObject::connect(dstSpin, QOverload<int>::of(&QSpinBox::valueChanged), [=](int) { updateMoveUi(); });
    QObject::connect(monoPairCheck, &QCheckBox::toggled, [=](bool) { updateMoveUi(); });
    QObject::connect(patchCheck, &QCheckBox::toggled, [=](bool) { updateMoveUi(); });
    updateMoveUi();

    QObject::connect(closeBtn, &QPushButton::clicked, g_dialog, &QDialog::hide);

    QObject::connect(moveBtn, &QPushButton::clicked, [=]() {
        int src = srcSpin->value() - 1;
        int dst = dstSpin->value() - 1;
        bool movePatchWithChannel = patchCheck->isChecked();
        bool moveMonoBlock = monoPairCheck->isChecked();
        MovePlan plan;
        char err[256];
        if (!buildMovePlan(src, dst, moveMonoBlock, plan, err, sizeof(err))) {
            statusLabel->setText(QString("Unsupported: %1.").arg(err));
            moveBtn->setEnabled(false);
            return;
        }
        statusLabel->setText("Moving...");
        moveBtn->setEnabled(false);
        QApplication::processEvents();

        bool ok = moveChannel(src, dst, movePatchWithChannel, moveMonoBlock);
        statusLabel->setText(ok ? "Done!" : "Failed — check log.");
        updateMoveUi();
    });

    // Test Stereo button: toggle stereo on source channel, with Type A settings preservation
    QObject::connect(testStereoBtn, &QPushButton::clicked, [=]() {
        int ch = srcSpin->value() - 1;
        int pair = ch / 2;
        int ch1 = pair * 2;      // first channel of pair (even)
        int ch2 = pair * 2 + 1;  // second channel of pair (odd)
        bool st = isChannelStereo(ch);
        QString beforeMsg = QString("Ch %1 pair (%2+%3): %4")
            .arg(ch+1).arg(ch1+1).arg(ch2+1).arg(st ? "STEREO" : "MONO");

        fprintf(stderr, "[MC] === Stereo toggle test: ch %d pair (%d+%d) currently %s ===\n",
                ch+1, ch1+1, ch2+1, st ? "STEREO" : "MONO");

        // 1. Dump current state before toggle
        dumpChannelData(ch1, "StereoTest-Before");
        dumpChannelData(ch2, "StereoTest-Before");

        // 2. Snapshot both channels in the pair (Type A settings)
        ChannelSnapshot snap1, snap2;
        bool snapOk1 = snapshotChannel(ch1, snap1);
        bool snapOk2 = snapshotChannel(ch2, snap2);
        fprintf(stderr, "[MC] Snapshot: ch %d=%s ch %d=%s\n",
                ch1+1, snapOk1 ? "OK" : "FAIL",
                ch2+1, snapOk2 ? "OK" : "FAIL");

        // 3. Toggle stereo config
        statusLabel->setText("Toggling stereo...");
        QApplication::processEvents();
        bool toggleOk = changeStereoConfig(ch, !st);
        fprintf(stderr, "[MC] changeStereoConfig returned %s\n", toggleOk ? "OK" : "FAIL");

        // 4. Verify channels were reset
        bool newSt = isChannelStereo(ch);
        fprintf(stderr, "[MC] After toggle: ch %d is now %s\n", ch+1, newSt ? "STEREO" : "MONO");
        dumpChannelData(ch1, "StereoTest-AfterToggle");
        dumpChannelData(ch2, "StereoTest-AfterToggle");

        // 5. Recall snapshots to restore Type A settings
        fprintf(stderr, "[MC] Recalling snapshots to restore settings...\n");
        if (snapOk1) recallChannel(ch1, snap1);
        if (snapOk2) recallChannel(ch2, snap2);

        // 6. Dump final state
        dumpChannelData(ch1, "StereoTest-AfterRecall");
        dumpChannelData(ch2, "StereoTest-AfterRecall");

        // Cleanup
        if (snapOk1) destroySnapshot(snap1);
        if (snapOk2) destroySnapshot(snap2);

        QString afterMsg = QString("Ch %1 pair: %2 → %3. Settings %4.")
            .arg(ch+1)
            .arg(st ? "STEREO" : "MONO")
            .arg(newSt ? "STEREO" : "MONO")
            .arg(toggleOk ? "restored — check log" : "FAILED");
        statusLabel->setText(afterMsg);
        updateMoveUi();
    });

    g_dialog->show();
}

// =============================================================================
// Global key event filter (more reliable than QShortcut for injected code)
// =============================================================================
class MCEventFilter : public QObject {
public:
    using QObject::QObject;
protected:
    bool eventFilter(QObject* obj, QEvent* event) override {
        if (event->type() == QEvent::KeyPress) {
            auto* ke = static_cast<QKeyEvent*>(event);
            if (ke->key() == Qt::Key_M &&
                (ke->modifiers() & (Qt::ControlModifier | Qt::ShiftModifier)) ==
                    (Qt::ControlModifier | Qt::ShiftModifier)) {
                showMoveDialog();
                return true;
            }
        }
        return QObject::eventFilter(obj, event);
    }
};

// =============================================================================
// Helpers for reading external data from messages
// =============================================================================
static void* getMsgDataPtr(uint8_t* msg) {
    void* ptr = nullptr;
    memcpy(&ptr, msg + 8, 8);
    return ptr;
}

static uint32_t getMsgLength(uint8_t* msg) {
    uint32_t len = 0;
    memcpy(&len, msg, 4);
    return len;
}

// Read type A processing external data for comparison
static void readExtDataA(int ch, int procIdx, uint8_t* outBuf, int maxLen) {
    void* inputCh = getInputChannel(ch);
    void* obj = getProcessingObj(inputCh, g_procA[procIdx].chOffset);
    uint8_t* msg = new uint8_t[MSG_BUF_SIZE];
    memset(msg, 0, MSG_BUF_SIZE);
    g_msgCtorCap(msg, 512);
    auto fillGS = (fn_method_msg)RESOLVE(g_procA[procIdx].fillGetStatusAddr);
    fillGS(obj, msg);
    uint32_t len = getMsgLength(msg);
    void* dataPtr = getMsgDataPtr(msg);
    if (dataPtr && len > 0) {
        int copyLen = (int)len < maxLen ? (int)len : maxLen;
        safeRead(dataPtr, outBuf, copyLen);
    }
    g_msgDtor(msg);
    delete[] msg;
}

// Read type B data by direct field access (same as snapshotChannel does)
static void readTypeBDirect(int ch, int procIdx, uint8_t* outBuf, int maxLen) {
    void* inputCh = getInputChannel(ch);
    void* obj = getTypeBObj(inputCh, g_procB[procIdx]);
    if (!obj) return;

    memset(outBuf, 0, maxLen);
    outBuf[0] = 0x01;  // version
    for (int f = 0; f < g_procB[procIdx].numFields; f++) {
        readTypeBField(obj, g_procB[procIdx].fields[f], outBuf);
    }
}

// =============================================================================
// Dump channel processing data (human-readable hex) for visual verification
// =============================================================================
static void dumpChannelData(int ch, const char* label) {
    fprintf(stderr, "[MC] --- %s: Ch %d '%s' ---\n", label, ch+1,
            g_getChannelName(g_audioDM, 1, (uint8_t)ch));

    // Type A: dump first 16 bytes of each processing object's data
    for (int p = 0; p < NUM_PROC_A; p++) {
        uint8_t buf[256];
        memset(buf, 0, sizeof(buf));
        readExtDataA(ch, p, buf, 256);
        uint8_t tmpMsg[MSG_BUF_SIZE];
        memset(tmpMsg, 0, MSG_BUF_SIZE);
        g_msgCtorCap(tmpMsg, 512);
        void* inputCh = getInputChannel(ch);
        void* obj = getProcessingObj(inputCh, g_procA[p].chOffset);
        if (obj) {
            auto fillGS = (fn_method_msg)RESOLVE(g_procA[p].fillGetStatusAddr);
            fillGS(obj, tmpMsg);
        }
        uint32_t len = getMsgLength(tmpMsg);
        g_msgDtor(tmpMsg);

        fprintf(stderr, "[MC]   %10s [len=%3u]: ", g_procA[p].name, len);
        int showLen = len < 24 ? (int)len : 24;
        for (int b = 0; b < showLen; b++) fprintf(stderr, "%02x ", buf[b]);
        if ((int)len > showLen) fprintf(stderr, "...");
        fprintf(stderr, "\n");
    }

    // Type B: dump field values
    for (int p = 0; p < NUM_PROC_B; p++) {
        void* inputCh = getInputChannel(ch);
        void* obj = getTypeBObj(inputCh, g_procB[p]);
        if (!obj) {
            fprintf(stderr, "[MC]   %10s: (not present)\n", g_procB[p].name);
            continue;
        }
        uint8_t buf[16];
        memset(buf, 0, sizeof(buf));
        buf[0] = g_procB[p].versionByte;
        for (int f = 0; f < g_procB[p].numFields; f++)
            readTypeBField(obj, g_procB[p].fields[f], buf);

        fprintf(stderr, "[MC]   %10s [len=%d]: ", g_procB[p].name, g_procB[p].msgLength);
        for (int b = 0; b < g_procB[p].msgLength; b++) fprintf(stderr, "%02x ", buf[b]);
        fprintf(stderr, "\n");
    }

    // Patching
    PatchData patch;
    if (readPatchData(ch, patch)) {
        fprintf(stderr, "[MC]      patch: srcType=%d src={type=%d, num=%d}\n",
                patch.sourceType, patch.source.type, patch.source.number);
        PreampData pd;
        if (readPreampDataForPatch(patch, pd))
            fprintf(stderr, "[MC]      preamp: socket=%u gain=%d pad=%d phantom=%d\n",
                    patch.source.number, pd.gain, pd.pad, pd.phantom);
    }
}

// =============================================================================
// Non-interactive self-test
// =============================================================================
// (self-test removed — use dialog for testing)

// =============================================================================
// Entry point
// =============================================================================
__attribute__((constructor))
static void onLoad() {
    setupLogging();
    fprintf(stderr, "[MC] ===== MoveChannel dylib loaded =====\n");
    resolveSlide();
    resolveSymbols();

    // Poll for app instance availability (user may need to click Offline first)
    __block int pollCount = 0;
    __block void (^pollBlock)(void) = ^{
        pollCount++;
        void* app = g_AppInstance();
        if (!app) {
            if (pollCount <= 60) {
                fprintf(stderr, "[MC] Waiting for app instance... (%d)\n", pollCount);
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC),
                               dispatch_get_main_queue(), pollBlock);
            } else {
                fprintf(stderr, "[MC] FATAL: App instance never became available after 120s.\n");
            }
            return;
        }

        fprintf(stderr, "[MC] Initializing (after %d polls)...\n", pollCount);

        if (!findAudioCoreDM()) {
            fprintf(stderr, "[MC] FATAL: Could not find AudioCoreDM!\n");
            return;
        }

        const char* ch0name = g_getChannelName(g_audioDM, 1, 0);
        fprintf(stderr, "[MC] Ch 1 name: '%s'\n", ch0name ? ch0name : "(null)");

        // Install global event filter for Ctrl+Shift+M
        auto* filter = new MCEventFilter(qApp);
        qApp->installEventFilter(filter);
        fprintf(stderr, "[MC] Global key filter installed (Ctrl+Shift+M).\n");

        showMoveDialog();

        if (getenv("MC_AUTOTEST_SRC") && getenv("MC_AUTOTEST_DST")) {
            fprintf(stderr, "[MC] Autotest requested via environment.\n");
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC),
                           dispatch_get_main_queue(), ^{
                bool ok = runAutomatedMoveTest();
                if (const char* exitEnv = getenv("MC_AUTOTEST_EXIT")) {
                    if (atoi(exitEnv) != 0) {
                        fprintf(stderr, "[MC] Autotest finished, quitting app (%s).\n", ok ? "PASS" : "FAIL");
                        qApp->quit();
                    }
                }
            });
        }

        // Auto-test disabled
#if 0
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC),
                       dispatch_get_main_queue(), ^{
            fprintf(stderr, "[MC] Recalling scene 21 (Test MOVE)...\n");
            recallScene(21);
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC),
                           dispatch_get_main_queue(), ^{
                // Dump Dyn8 settings for units 0-3 right after scene recall
                fprintf(stderr, "[MC] Dyn8 settings after scene recall:\n");
                for (int u = 0; u < 4; u++) {
                    void* dynObj = getDynNetObj(u);
                    if (!dynObj) { fprintf(stderr, "[MC]   Unit %d: NOT FOUND\n", u); continue; }
                    uint8_t raw[0x90];
                    safeRead((uint8_t*)dynObj + 0xa0, raw, 0x90);
                    fprintf(stderr, "[MC]   Unit %d (first 48): ", u);
                    for (int b = 0; b < 48; b++) fprintf(stderr, "%02x ", raw[b]);
                    fprintf(stderr, "\n");
                }

                fprintf(stderr, "[MC] Moving ch 1 → ch 4...\n");
                moveChannel(0, 3, true);
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC)),
                               dispatch_get_main_queue(), ^{
                    // Post-move Dyn8 verification
                    fprintf(stderr, "[MC] Dyn8 settings after move:\n");
                    for (int u = 0; u < 4; u++) {
                        void* dynObj = getDynNetObj(u);
                        if (!dynObj) { fprintf(stderr, "[MC]   Unit %d: NOT FOUND\n", u); continue; }
                        uint8_t raw[0x90];
                        safeRead((uint8_t*)dynObj + 0xa0, raw, 0x90);
                        fprintf(stderr, "[MC]   Unit %d (first 48): ", u);
                        for (int b = 0; b < 48; b++) fprintf(stderr, "%02x ", raw[b]);
                        fprintf(stderr, "\n");
                    }
                    fprintf(stderr, "[MC] Move complete — showing dialog for verification.\n");
                    showMoveDialog();
                });
            });
        });
#endif

        fprintf(stderr, "[MC] ===== MoveChannel ready =====\n");
    };
    // Start polling after initial 5s delay
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC),
                   dispatch_get_main_queue(), pollBlock);
}
