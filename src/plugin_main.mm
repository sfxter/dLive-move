#import <Foundation/Foundation.h>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <dlfcn.h>
#include <mach-o/dyld.h>
#include <mach/mach.h>
#include <dispatch/dispatch.h>
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
    // cStereoImage: DISABLED — ch[19] is a small int, not a pointer. Need to find correct offset.
    // vtable+16 = 0x106c7a818, driver vtable+16 = 0x106c7a860
    // {"StereoImage", ??, 0x106c7a818, 4, 0x01, ?, 0, 2, { ... }},
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

    // Write back to discovery object
    if (!writeStereoConfig(config)) {
        fprintf(stderr, "[MC] changeStereoConfig: failed to write config\n");
        return false;
    }

    // Call cAudioCoreDM::NewInputStereoConfiguration(sIPStereoConfigurationData*)
    // this=rdi (g_audioDM), config=rsi
    typedef void (*fn_NewStereoConfig)(void* dm, const uint8_t* config);
    auto newStereoConfig = (fn_NewStereoConfig)RESOLVE(0x1001a0f10);
    newStereoConfig(g_audioDM, config);
    fprintf(stderr, "[MC] changeStereoConfig: NewInputStereoConfiguration called\n");

    // Call cApplication::NewInputConfiguration(bool)
    // this=rdi (app instance), bool=rsi
    void* app = g_AppInstance();
    if (app) {
        typedef void (*fn_NewInputConfig)(void* app, bool flag);
        auto newInputConfig = (fn_NewInputConfig)RESOLVE(0x100d6e0c0);
        newInputConfig(app, true);
        fprintf(stderr, "[MC] changeStereoConfig: NewInputConfiguration called\n");
    }

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
    for (int i = 2; i < 120; i++) {
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

static void* getAnalogueInput(int ch) {
    if (!g_registryRouter || g_firstAnalogueInputIdx < 0 || ch < 0 || ch > 127) return nullptr;
    uint8_t* base = (uint8_t*)g_registryRouter + 0x3a9820;
    void* entry = nullptr;
    safeRead(base + (g_firstAnalogueInputIdx + ch) * 8, &entry, sizeof(entry));
    return entry;
}

static bool readPreampData(int ch, PreampData& pd) {
    void* ai = getAnalogueInput(ch);
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

static bool writePreampData(int ch, const PreampData& pd) {
    void* ai = getAnalogueInput(ch);
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
        if (!obj) continue;

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
        snap.validB[p] = ok;
        if (ok && strstr(g_procB[p].name, "SideChain")) {
            fprintf(stderr, "[MC]   Snapshot %s ch %d: stripType=%d channel=%d\n",
                    g_procB[p].name, ch+1, snap.dataB[p].buf[1], snap.dataB[p].buf[2]);
        }
        if (ok && strstr(g_procB[p].name, "DigitalTrim")) {
            uint16_t gain = ((uint16_t)snap.dataB[p].buf[1] << 8) | snap.dataB[p].buf[2];
            fprintf(stderr, "[MC]   Snapshot %s ch %d: gain=%d (0x%04x)\n",
                    g_procB[p].name, ch+1, (int16_t)gain, gain);
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

    // Preamp (gain, pad, phantom)
    snap.validPreamp = readPreampData(ch, snap.preampData);

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

static bool recallChannel(int ch, const ChannelSnapshot& snap, bool skipPreamp = false) {
    void* inputCh = getInputChannel(ch);
    if (!inputCh) { fprintf(stderr, "[MC] Ch %d: InputChannel is null!\n", ch); return false; }

    // Type A: DirectlyRecallStatus + ReportData
    for (int p = 0; p < NUM_PROC_A; p++) {
        if (!snap.validA[p]) continue;
        void* obj = getProcessingObj(inputCh, g_procA[p].chOffset);
        if (!obj) { fprintf(stderr, "[MC]   %s: obj null, skip\n", g_procA[p].name); continue; }

        fprintf(stderr, "[MC]   Recall %s on ch %d (obj=%p)\n", g_procA[p].name, ch+1, obj);
        auto recall = (fn_method_msg)RESOLVE(g_procA[p].directlyRecallAddr);
        recall(obj, snap.msgA[p]);

        auto report = (fn_method_void)RESOLVE(g_procA[p].reportDataAddr);
        report(obj);
    }

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

        // Sidechain: write raw fields then use the EMBEDDED message at obj+0x60
        // exactly like SetStatus does, but skip RefreshSource which resets values
        if (p == 6 || p == 7) {
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

    // Preamp: write gain/pad/phantom via MIDISet* (works offline, notifies UI)
    // Skip in Scenario B — SetInputChannelSource moves preamp with the socket
    if (!skipPreamp && snap.validPreamp) {
        if (writePreampData(ch, snap.preampData))
            fprintf(stderr, "[MC]   Write preamp on ch %d: gain=%d pad=%d phantom=%d\n",
                    ch+1, snap.preampData.gain, snap.preampData.pad, snap.preampData.phantom);
        else
            fprintf(stderr, "[MC]   WARN: preamp write failed on ch %d\n", ch+1);
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

// =============================================================================
// Move Channel
// =============================================================================
static bool moveChannel(int src, int dst, bool keepPatching = true) {
    if (src == dst) { fprintf(stderr, "[MC] Same position, nothing to do.\n"); return true; }
    if (src < 0 || src > 127 || dst < 0 || dst > 127) {
        fprintf(stderr, "[MC] Invalid channel numbers.\n"); return false;
    }

    int lo = src < dst ? src : dst;
    int hi = src < dst ? dst : src;
    int rangeSize = hi - lo + 1;

    fprintf(stderr, "[MC] === MOVE ch %d → pos %d (range %d-%d) [patching: %s] ===\n",
            src+1, dst+1, lo+1, hi+1, keepPatching ? "keep at position" : "shift with channel");

    // Snapshot all channels in range
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
    auto remapCh = [&](uint8_t oldRef) -> uint8_t {
        if (oldRef == (uint8_t)src) return (uint8_t)dst;
        if (src < dst) {
            // Channels (src,dst] shift up by 1 position (i.e., their index decreases by 1)
            if (oldRef > (uint8_t)src && oldRef <= (uint8_t)dst)
                return oldRef - 1;
        } else {
            // Channels [dst,src) shift down by 1 position (i.e., their index increases by 1)
            if (oldRef >= (uint8_t)dst && oldRef < (uint8_t)src)
                return oldRef + 1;
        }
        return oldRef;
    };
    for (int i = 0; i < rangeSize; i++) {
        for (int p = 6; p <= 7; p++) { // SideChain1 (p=6), SideChain2 (p=7)
            if (!snaps[i].validB[p]) continue;
            uint8_t oldCh = snaps[i].dataB[p].buf[2];
            uint8_t newCh = remapCh(oldCh);
            if (oldCh != newCh) {
                fprintf(stderr, "[MC]   Remap %s snap[%d] channel %d → %d\n",
                        g_procB[p].name, lo+i+1, oldCh, newCh);
                snaps[i].dataB[p].buf[2] = newCh;
            }
        }
    }

    // Build Dyn8 transfer map: which snapshot's Dyn8 message goes to which target unit
    struct Dyn8Transfer { int tgtUnitIdx; int snapIdx; };
    std::vector<Dyn8Transfer> dyn8Transfers;
    {
        std::vector<std::pair<int,int>> dyn8Map; // (tgtCh, snapIdx)
        if (src < dst) {
            for (int i = 0; i < rangeSize - 1; i++)
                dyn8Map.push_back({lo + i, 1 + i});
            dyn8Map.push_back({hi, 0});
        } else {
            dyn8Map.push_back({lo, rangeSize - 1});
            for (int i = 0; i < rangeSize - 1; i++)
                dyn8Map.push_back({lo + 1 + i, i});
        }
        for (auto& [tgtCh, si] : dyn8Map) {
            if (!snaps[si].validDyn8) continue;
            for (int ip = 0; ip < 2; ip++) {
                if (snaps[si].insertInfo[ip].hasInsert && snaps[si].insertInfo[ip].parentType == 5) {
                    Dyn8Transfer xfer;
                    xfer.tgtUnitIdx = tgtCh; // target's OWN Dyn8 unit (unit index == channel index)
                    xfer.snapIdx = si;
                    // dyn8Data is in the snapshot, no need to copy
                    dyn8Transfers.push_back(xfer);
                    fprintf(stderr, "[MC] Dyn8 transfer: snap[%d] (unit %d) → target unit %d (ch %d)\n",
                            si, snaps[si].dyn8UnitIdx, tgtCh, tgtCh+1);
                    break;
                }
            }
        }
    }

    // =========================================================================
    // Stereo alignment: change stereo config at destination pairs if needed
    // Must happen AFTER snapshot (which preserves settings) but BEFORE recall.
    // The stereo config change calls Reset() on affected channels.
    // Channels IN the move range are already snapshotted and will be recalled.
    // Channels OUTSIDE the move range but in affected pairs must be separately
    // snapshotted and restored here.
    // =========================================================================
    {
        // Build target mapping: targetCh[i] gets snapshot snapIdx
        std::vector<std::pair<int,int>> targetMap; // (targetCh, snapIdx)
        if (src < dst) {
            for (int i = 0; i < rangeSize - 1; i++)
                targetMap.push_back({lo + i, 1 + i});
            targetMap.push_back({hi, 0});
        } else {
            targetMap.push_back({lo, rangeSize - 1});
            for (int i = 0; i < rangeSize - 1; i++)
                targetMap.push_back({lo + 1 + i, i});
        }

        // Read current stereo config
        uint8_t config[64];
        bool configRead = readStereoConfig(config);
        bool configChanged = false;

        if (configRead) {
            // For each target channel, check if source's stereo status matches target's pair
            // A pair's state is determined by the snapshot that lands on its even channel.
            std::set<int> pairsToChange;
            for (auto& [tgtCh, si] : targetMap) {
                int tgtPair = tgtCh / 2;
                bool snapStereo = snaps[si].isStereo;
                bool tgtCurrentStereo = (config[tgtPair] != 0);

                if (snapStereo != tgtCurrentStereo) {
                    if (tgtCh == tgtPair * 2) {
                        config[tgtPair] = snapStereo ? 1 : 0;
                        pairsToChange.insert(tgtPair);
                        fprintf(stderr, "[MC] Stereo align: pair %d (ch %d+%d) → %s (from snap '%s')\n",
                                tgtPair, tgtPair*2+1, tgtPair*2+2,
                                snapStereo ? "STEREO" : "MONO", snaps[si].name);
                        configChanged = true;
                    }
                }
            }

            if (configChanged) {
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
                if (!writeStereoConfig(config)) {
                    fprintf(stderr, "[MC] WARNING: failed to write stereo config!\n");
                } else {
                    typedef void (*fn_NewStereoConfig)(void* dm, const uint8_t* config);
                    auto newStereoConfig = (fn_NewStereoConfig)RESOLVE(0x1001a0f10);
                    newStereoConfig(g_audioDM, config);

                    void* app = g_AppInstance();
                    if (app) {
                        typedef void (*fn_NewInputConfig)(void* app, bool flag);
                        auto newInputConfig = (fn_NewInputConfig)RESOLVE(0x100d6e0c0);
                        newInputConfig(app, true);
                    }
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

    // Write in new order
    // In Scenario B (!keepPatching), skip preamp — SetInputChannelSource moves it with socket
    bool skipPreamp = !keepPatching;
    if (src < dst) {
        // Move DOWN: src→dst, others shift up
        for (int i = 0; i < rangeSize - 1; i++) {
            fprintf(stderr, "[MC] Recall '%s' → pos %d\n", snaps[1+i].name, lo+i+1);
            recallChannel(lo + i, snaps[1 + i], skipPreamp);
        }
        fprintf(stderr, "[MC] Recall '%s' → pos %d\n", snaps[0].name, hi+1);
        recallChannel(hi, snaps[0], skipPreamp);
    } else {
        // Move UP: src→dst, others shift down
        fprintf(stderr, "[MC] Recall '%s' → pos %d\n", snaps[rangeSize-1].name, lo+1);
        recallChannel(lo, snaps[rangeSize - 1], skipPreamp);
        for (int i = 0; i < rangeSize - 1; i++) {
            fprintf(stderr, "[MC] Recall '%s' → pos %d\n", snaps[i].name, lo+1+i+1);
            recallChannel(lo + 1 + i, snaps[i], skipPreamp);
        }
    }

    // Patching: Scenario B — shift socket assignments with channels
    if (!keepPatching) {
        fprintf(stderr, "[MC] Writing patching (Scenario B)...\n");
        // Build array mapping: targetCh[i] gets the patchData from snapIdx
        std::vector<std::pair<int,int>> patchOrder; // (targetCh, snapIdx)
        if (src < dst) {
            for (int i = 0; i < rangeSize - 1; i++)
                patchOrder.push_back({lo + i, 1 + i});
            patchOrder.push_back({hi, 0});
        } else {
            patchOrder.push_back({lo, rangeSize - 1});
            for (int i = 0; i < rangeSize - 1; i++)
                patchOrder.push_back({lo + 1 + i, i});
        }
        // Use CSV import path: cChannel::SetInputChannelSource via task system
        // This is what Import CSV uses — full update + UI refresh
        typedef void* (*fn_GetChannel)(void* mgr, uint32_t stripType, uint8_t chNum);
        auto getChannel = (fn_GetChannel)RESOLVE(0x1006e3f90);

        typedef void* (*fn_GetSendPoint)(void* mgr, uint32_t sourceType, uint16_t sourceNum);
        auto getSendPoint = (fn_GetSendPoint)RESOLVE(0x1006ce8e0);

        typedef void (*fn_SetInputChannelSource)(void* channel, int activeInputSource,
                                                  void* sendPt, void* sendPt2);
        auto setInputSource = (fn_SetInputChannelSource)RESOLVE(0x1006d8410);

        for (auto& [tgtCh, si] : patchOrder) {
            if (!snaps[si].validPatch) continue;
            sAudioSource& src = snaps[si].patchData.source;
            fprintf(stderr, "[MC]   Patch ch %d: srcType=%d src={type=%d, num=%d}\n",
                    tgtCh+1, snaps[si].patchData.sourceType,
                    src.type, src.number);

            if (!g_channelManager || !g_audioSRPManager) {
                fprintf(stderr, "[MC]   WARN: channelMgr or audioSRPMgr not available, falling back to writePatchData\n");
                writePatchData(tgtCh, snaps[si].patchData);
                continue;
            }

            // Get cChannel* for target
            void* ch = getChannel(g_channelManager, 1/*Input*/, (uint8_t)tgtCh);
            if (!ch) {
                fprintf(stderr, "[MC]   WARN: GetChannel(%d) returned null\n", tgtCh);
                writePatchData(tgtCh, snaps[si].patchData);
                continue;
            }

            // Get cAudioSendPoint* for desired source
            void* sendPt = getSendPoint(g_audioSRPManager, src.type, (uint16_t)src.number);
            fprintf(stderr, "[MC]   ch=%p sendPt=%p\n", ch, sendPt);

            // SetInputChannelSource: eActiveInputSource=1 (primary input)
            setInputSource(ch, 1, sendPt, nullptr);
        }
        fprintf(stderr, "[MC]   Patching applied via SetInputChannelSource.\n");
    }

    // Insert routing: reassign FX units to new channel positions
    // Strategy: first unassign ALL unique FX units, then reassign to new channels.
    // This avoids the "FX unit is already assigned" conflict when moving shared FX units.
    // Hidden struct return ABI: rdi=&retList, rsi=this, rdx/ecx=params
    {
        fprintf(stderr, "[MC] Reassigning insert FX units...\n");
        typedef void* (*fn_GetChannel)(void* mgr, uint32_t stripType, uint8_t chNum);
        auto getChannel = (fn_GetChannel)RESOLVE(0x1006e3f90);

        // Build snap→target mapping
        std::vector<std::pair<int,int>> insertOrder;
        if (src < dst) {
            for (int i = 0; i < rangeSize - 1; i++)
                insertOrder.push_back({lo + i, 1 + i});
            insertOrder.push_back({hi, 0});
        } else {
            insertOrder.push_back({lo, rangeSize - 1});
            for (int i = 0; i < rangeSize - 1; i++)
                insertOrder.push_back({lo + 1 + i, i});
        }

        // All insert types use audio routing + SetAssigned on InsertNetObject:
        // - Dyn8 (parentType==5): SetAssigned(true) + route to TARGET's Dyn8 unit
        // - Rack FX / External (parentType==2,6): route to same FX unit
        // - Unassigned (parentType==0): SetAssigned(false) + route to default points
        typedef void (*fn_PerformTasks)(void* audioSRPMgr, void* taskList);
        auto performTasks = (fn_PerformTasks)RESOLVE(0x1006d19c0);
        typedef void* (*fn_CreateSendTargetTask)(void* ret, void* channel, void* fxRecvPt, int ip, int enable);
        auto createSendTargetTask = (fn_CreateSendTargetTask)RESOLVE(0x1006da210);
        typedef void* (*fn_CreateReturnSourceTask)(void* ret, void* channel, void* fxSendPt, int ip);
        auto createReturnSourceTask = (fn_CreateReturnSourceTask)RESOLVE(0x1006da450);
        typedef void (*fn_SetAssigned)(void* insertNetObj, bool assigned, bool param2);
        auto setAssigned = (fn_SetAssigned)RESOLVE(0x1002a3c50);

        for (auto& [tgtCh, si] : insertOrder) {
            void* tgtChannel = getChannel(g_channelManager, 1, (uint8_t)tgtCh);
            if (!tgtChannel) continue;

            for (int ip = 0; ip < 2; ip++) {
                auto& ins = snaps[si].insertInfo[ip];
                if (!ins.hasInsert) continue;

                void* routeSendPt = ins.fxSendPt;
                void* routeRecvPt = ins.fxReceivePt;
                int enable = 1;

                // cChannel::SetInserts handles both assign and unassign
                struct sInsertPts { void* t1; void* t2; void* s1; void* s2; };
                typedef void (*fn_SetInserts)(void* channel, sInsertPts pts, int insertPoint);
                auto setInserts = (fn_SetInserts)RESOLVE(0x1006d9920);

                if (ins.parentType == 5 && tgtCh >= 0 && tgtCh < 64) {
                    // Dyn8: call SetInserts with correct struct.
                    // OLD BUG: {recv,recv,send,send} duplicated the Dyn8 point for
                    // both t1 and t2. SetInserts checks BOTH pts[0]+0x28 and pts[1]+0x28
                    // for parentType==5 (dynamics), causing double-unassign on the same
                    // DUC which corrupts dormant units.
                    // FIX: Use the channel's own insert return/send points for pts[1]/pts[3].
                    // These have a non-dynamics parent, so the pts[1] check is skipped.
                    typedef void* (*fn_GetInsertReturnPoint)(void* channel, int insertPoint);
                    typedef void* (*fn_GetInsertSendPoint)(void* channel, int insertPoint);
                    auto getRetPt = (fn_GetInsertReturnPoint)RESOLVE(0x1006d9850);
                    auto getSndPt = (fn_GetInsertSendPoint)RESOLVE(0x1006d9780);

                    void* dyn8Send = getDyn8SendPoint(tgtCh);
                    void* dyn8Recv = getDyn8RecvPoint(tgtCh);
                    void* chReturnPt = getRetPt(tgtChannel, ip);  // channel's own recv (non-dynamics parent)
                    void* chSendPt = getSndPt(tgtChannel, ip);    // channel's own send (non-dynamics parent)
                    sInsertPts pts = { dyn8Recv, chReturnPt, dyn8Send, chSendPt };
                    setInserts(tgtChannel, pts, ip);
                    fprintf(stderr, "[MC]   Insert%c: ch %d — SetInserts Dyn8[%d] recv=%p chRet=%p send=%p chSnd=%p\n",
                            'A'+ip, tgtCh+1, tgtCh, dyn8Recv, chReturnPt, dyn8Send, chSendPt);
                    continue;
                } else if (ins.parentType == 0) {
                    // Unassigned: call SetInserts with default unassigned points
                    sInsertPts pts = { routeRecvPt, routeRecvPt, routeSendPt, routeSendPt };
                    setInserts(tgtChannel, pts, ip);
                    fprintf(stderr, "[MC]   Insert%c: ch %d — SetInserts DISCONNECT (default pts)\n",
                            'A'+ip, tgtCh+1);
                    continue;
                } else {
                    // Rack FX / External: use audio routing tasks (proven to work)
                    fprintf(stderr, "[MC]   Insert%c: ch %d ← fxSend=%p fxRecv=%p (type=%d)\n",
                            'A'+ip, tgtCh+1, routeSendPt, routeRecvPt, ins.parentType);
                }

                if (routeRecvPt) {
                    uint8_t buf[64]; memset(buf, 0, sizeof(buf));
                    createSendTargetTask(buf, tgtChannel, routeRecvPt, ip, enable);
                    performTasks(g_audioSRPManager, buf);
                }
                if (routeSendPt) {
                    uint8_t buf[64]; memset(buf, 0, sizeof(buf));
                    createReturnSourceTask(buf, tgtChannel, routeSendPt, ip);
                    performTasks(g_audioSRPManager, buf);
                }
            }
        }
        fprintf(stderr, "[MC]   Insert reassignment done.\n");

        // Dyn8 settings transfer via cDynamicsSystem::SetDynamicsData + FullDriverUpdate
        // SetDynamicsData writes to system's internal data array + sets dirty flags
        // FullDriverUpdate pushes dirty data to drivers/curve widgets
        // Net object also updated via SetAllDataAndUpdateUI for control widgets
        if (!dyn8Transfers.empty()) {
            fprintf(stderr, "[MC] Dyn8 system-level transfer phase (%zu entries)...\n", dyn8Transfers.size());
            typedef void (*fn_setAllDataUI)(void* obj, void* sDynData);
            auto setAllDataUI = (fn_setAllDataUI)RESOLVE(0x100239970);
            typedef void (*fn_setDynData)(void* system, void* key, void* data);
            auto setDynData = (fn_setDynData)RESOLVE(0x100239240); // cDynamicsSystem::SetDynamicsData
            typedef void (*fn_fullDriverUpdate)(void* system);
            auto fullDriverUpdate = (fn_fullDriverUpdate)RESOLVE(0x10023c6c0); // cDynamicsSystem::FullDriverUpdate()

            for (auto& xfer : dyn8Transfers) {
                void* tgtDynObj = getDynNetObj(xfer.tgtUnitIdx);
                if (!tgtDynObj) {
                    fprintf(stderr, "[MC]   Dyn8 unit %d: getDynNetObj returned null!\n", xfer.tgtUnitIdx);
                    continue;
                }
                if (!snaps[xfer.snapIdx].validDyn8) {
                    fprintf(stderr, "[MC]   Dyn8 snap[%d]: no valid data!\n", xfer.snapIdx);
                    continue;
                }

                // Read cDynamicsSystem* and sDynamicsKey from target net object
                void* dynSystem = nullptr;
                safeRead((uint8_t*)tgtDynObj + 0x90, &dynSystem, sizeof(dynSystem));
                uint8_t dynKey[8] = {};
                safeRead((uint8_t*)tgtDynObj + 0x88, dynKey, 8);

                fprintf(stderr, "[MC]   Dyn8 unit %d: obj=%p system=%p key={%u,%u} type=%u\n",
                        xfer.tgtUnitIdx, tgtDynObj, dynSystem,
                        *(uint32_t*)dynKey, (uint32_t)dynKey[4],
                        *(uint32_t*)snaps[xfer.snapIdx].dyn8Data);

                // 1. Write to net object (for control widgets)
                setAllDataUI(tgtDynObj, snaps[xfer.snapIdx].dyn8Data);

                // 2. Write to cDynamicsSystem data array + set dirty flags (for curve/driver)
                if (dynSystem) {
                    setDynData(dynSystem, dynKey, snaps[xfer.snapIdx].dyn8Data);
                    // SetDynamicsData sets +0xca8 (selective dirty), but FullDriverUpdate
                    // checks +0xca9 (full update flag). Set it manually.
                    uint8_t one = 1;
                    safeWrite((uint8_t*)dynSystem + 0xca9, &one, 1);
                    // 3. Push dirty data to drivers/curve widgets immediately
                    fullDriverUpdate(dynSystem);
                    fprintf(stderr, "[MC]   SetDynamicsData + FullDriverUpdate done\n");
                } else {
                    fprintf(stderr, "[MC]   WARNING: cDynamicsSystem is null!\n");
                }

                // 3. Send messages through DUC's EntrypointMessage to refresh curve
                // The cDynamicsNetObject and DUC are separate objects. InformOtherObjects
                // on the net object does NOT reach the DUC's CC intermediates. The CC
                // intermediates (which drive the crossover curve) are dependents of the
                // DUC's embedded cNetObject at DUC+0x10. EntrypointMessage processes
                // the message type, emits Qt signals, AND calls InformOtherObjects on
                // DUC+0x10 — the exact path used when data arrives from the network.
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
                    auto packSC      = (fn_PackSideChain)RESOLVE(0x1000cdfd0); // PackSideChainMessage
                    auto entrypoint  = (fn_EntrypointMessage)RESOLVE(0x1005e9140);

                    uint32_t ducKey = 0;
                    safeRead((uint8_t*)duc + 0x68, &ducKey, 4);

                    // Helper: stack-allocated cAHNetMessage (0x28 bytes from disassembly)
                    uint8_t msgBuf[64];

                    // --- Send 0x1001 (type) message ---
                    memset(msgBuf, 0, sizeof(msgBuf));
                    msgCtor(msgBuf);
                    *(uint16_t*)(msgBuf + 0x10) = 0;      // flags
                    *(uint32_t*)(msgBuf + 0x14) = ducKey;  // src key
                    *(uint32_t*)(msgBuf + 0x18) = ducKey;  // dst key
                    *(uint32_t*)(msgBuf + 0x1c) = 0x1001;  // msg type
                    setLen(msgBuf, 1);
                    setUBYTE(msgBuf, snaps[xfer.snapIdx].dyn8Data[0], 0); // type byte
                    entrypoint(duc, msgBuf);
                    msgDtor(msgBuf);

                    // --- Send 0x1002 (bands wide) message ---
                    memset(msgBuf, 0, sizeof(msgBuf));
                    msgCtor(msgBuf);
                    *(uint16_t*)(msgBuf + 0x10) = 0;
                    *(uint32_t*)(msgBuf + 0x14) = ducKey;
                    *(uint32_t*)(msgBuf + 0x18) = ducKey;
                    *(uint32_t*)(msgBuf + 0x1c) = 0x1002;
                    setLen(msgBuf, 8);
                    packBands(msgBuf, snaps[xfer.snapIdx].dyn8Data, 0);
                    entrypoint(duc, msgBuf);
                    msgDtor(msgBuf);

                    // --- Send 0x1003 (sidechain) message ---
                    memset(msgBuf, 0, sizeof(msgBuf));
                    msgCtor(msgBuf);
                    *(uint16_t*)(msgBuf + 0x10) = 0;
                    *(uint32_t*)(msgBuf + 0x14) = ducKey;
                    *(uint32_t*)(msgBuf + 0x18) = ducKey;
                    *(uint32_t*)(msgBuf + 0x1c) = 0x1003;
                    setLen(msgBuf, 0xa);
                    packSC(msgBuf, snaps[xfer.snapIdx].dyn8Data, 0);
                    entrypoint(duc, msgBuf);
                    msgDtor(msgBuf);

                    fprintf(stderr, "[MC]   DUC %p: sent 0x1001+0x1002+0x1003 via EntrypointMessage\n", duc);
                } else {
                    fprintf(stderr, "[MC]   WARNING: getDynUnitClient(%d) returned null!\n", xfer.tgtUnitIdx);
                }

                // Verify net object
                uint8_t afterRecall[0x94] = {0};
                safeRead((uint8_t*)tgtDynObj + 0x98, afterRecall, 0x94);
                int match = 0;
                for (int b = 0; b < 0x94; b++) {
                    if (afterRecall[b] == snaps[xfer.snapIdx].dyn8Data[b]) match++;
                }
                fprintf(stderr, "[MC]   Unit %d: %d/148 bytes match source\n",
                        xfer.tgtUnitIdx, match);
            }
        }
    }

    for (int i = 0; i < rangeSize; i++) destroySnapshot(snaps[i]);

    // Verify
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
        srcStereoLabel->setText(srcSt ? QString("[Stereo %1+%2]").arg(srcCh+1).arg(srcCh+2) : "[Mono]");
        dstStereoLabel->setText(dstSt ? QString("[Stereo %1+%2]").arg(dstCh+1).arg(dstCh+2) : "[Mono]");
    };
    QObject::connect(srcSpin, QOverload<int>::of(&QSpinBox::valueChanged), [=](int) { updateStereoLabels(); });
    QObject::connect(dstSpin, QOverload<int>::of(&QSpinBox::valueChanged), [=](int) { updateStereoLabels(); });
    updateStereoLabels();  // initial state

    auto* patchCheck = new QCheckBox("Move source patching with channel (Scenario B)");
    patchCheck->setChecked(false);  // Default: Scenario A (patching stays at position)
    layout->addWidget(patchCheck);

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

    QObject::connect(closeBtn, &QPushButton::clicked, g_dialog, &QDialog::hide);

    QObject::connect(moveBtn, &QPushButton::clicked, [=]() {
        int src = srcSpin->value() - 1;
        int dst = dstSpin->value() - 1;
        bool keepPatching = !patchCheck->isChecked();  // checkbox = move patching = !keep
        statusLabel->setText("Moving...");
        moveBtn->setEnabled(false);
        QApplication::processEvents();

        bool ok = moveChannel(src, dst, keepPatching);
        statusLabel->setText(ok ? "Done!" : "Failed — check log.");
        moveBtn->setEnabled(true);
        updateStereoLabels();
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
        updateStereoLabels();
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

    // Preamp
    PreampData pd;
    if (readPreampData(ch, pd))
        fprintf(stderr, "[MC]      preamp: gain=%d pad=%d phantom=%d\n", pd.gain, pd.pad, pd.phantom);

    // Patching
    PatchData patch;
    if (readPatchData(ch, patch))
        fprintf(stderr, "[MC]      patch: srcType=%d src={type=%d, num=%d}\n",
                patch.sourceType, patch.source.type, patch.source.number);
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
