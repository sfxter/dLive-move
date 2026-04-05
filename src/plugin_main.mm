#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <dlfcn.h>
#include <mach-o/dyld.h>
#include <mach/mach.h>
#include <dispatch/dispatch.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <unistd.h>
#include <chrono>
#include <array>
#include <algorithm>
#include <functional>
#include <map>
#include <vector>
#include <set>
#include <memory>
#include <cerrno>
#include <cstdarg>
#include <climits>
#include <cmath>
#include <mutex>

#include <QApplication>
#include <QAbstractButton>
#include <QDialog>
#include <QVBoxLayout>
#include <QHBoxLayout>
#include <QLabel>
#include <QSpinBox>
#include <QPushButton>
#include <QCheckBox>
#include <QProgressDialog>
#include <QShortcut>
#include <QKeySequence>
#include <QKeyEvent>
#include <QDropEvent>
#include <QWidget>
#include <QMenuBar>
#include <QMenu>
#include <QAction>
#include <QInputDialog>
#include <QMessageBox>
#include <QComboBox>
#include <QFormLayout>
#include <QDialogButtonBox>
#include <QTableWidget>
#include <QHeaderView>
#include <QAbstractItemView>
#include <QScrollBar>
#include <QColor>
#include <QBrush>
#include <QStandardItemModel>
#include <QList>
#include <QPainter>
#include <QWidget>
#include <QWindow>
#include <QPoint>
#include <QTimer>
#include <QElapsedTimer>
#include <QEventLoop>
#include <QVariant>
#include <QMetaProperty>
#include <QMetaMethod>
#include <QPointer>
#include <QFile>
#include <QThread>

static bool selectInputChannelForUI(int ch, const char* phaseTag);
static bool createShowViaShowManagerClient(const QString& showName);

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

template <typename T>
static bool safeReadValue(const void* addr, T* out) {
    if (!out) return false;
    T tmp{};
    if (!safeRead(addr, &tmp, sizeof(tmp)))
        return false;
    *out = tmp;
    return true;
}

// =============================================================================
// Image slide resolution
// =============================================================================
static intptr_t g_slide = 0;
static const char* kMoveChannelLogPath = "/Users/sfx/Programavimas/dLive-patch/movechannel.log";
struct sAudioSource;
struct PreampData;

enum MCLogLevel {
    MC_LOG_QUIET = 0,
    MC_LOG_NORMAL = 1,
    MC_LOG_VERBOSE = 2,
};

static int g_mcLogLevel = -1;
static void refreshVisiblePreampUI(const char* phaseTag = nullptr);
static void dumpPreampUiRegions(const char* phaseTag = nullptr);
static void scanRootForVtableSlotCandidates(void* root,
                                            const char* rootLabel,
                                            const char* phaseTag,
                                            uintptr_t targetFn,
                                            const char* targetLabel,
                                            int directScanBytes = 0x4000,
                                            int childScanBytes = 0x1000,
                                            int slotCount = 256,
                                            intptr_t tolerance = 0x40);
static void dumpWestBindingForSelectedChannel(const char* phaseTag = nullptr);
static void runWestProcessingRefreshExperiment(const char* phaseTag = nullptr);
static void runWestUserControlDriverExperiment(const char* phaseTag = nullptr);
static void runSelectorLitePreampExperiment(const char* phaseTag = nullptr);
static void runSelectorSurfacePreampExperiment(int ch, const char* phaseTag = nullptr);
static void refreshWestProcessingForChannel(int ch, const char* phaseTag = nullptr);
static void relinkWestPreampControlWrappers(const char* phaseTag = nullptr);
static void pushWestPreampGainValue(int ch, const char* phaseTag = nullptr);
static void scheduleWestPreampGainPush(int ch, const char* phaseTag = nullptr);
static void scheduleWestPreampGainPushForCurrentSelection(const char* phaseTag = nullptr);
static void scheduleWestPreampGainPushAfterPointerSelection();
static void syncWestPreampUiToSelectedChannel(bool force = false, const char* phaseTag = nullptr);
static QList<QObject*> collectWestProcessingForms();
static bool writePreampDataViaCsvImport(const sAudioSource& source,
                                        const PreampData& preamp,
                                        const char* phaseTag = nullptr);
static void maybePatchDirectorSingletonKey();
static void* findSurfaceDiscoveryNamedObject(const char* name);
static void discoverSelectorObjectsFallback(const char* phaseTag = nullptr);
static void discoverSelectorManagerFromChannelMapper(const char* phaseTag = nullptr);
static int getSelectedInputChannel(bool verbose);
static void rememberSelectedInputChannel(int ch);
struct SelectedStripInfo {
    bool valid = false;
    uint32_t stripType = 0;
    int channel = -1;
    void* channelPtr = nullptr;
};
static SelectedStripInfo getSelectedStripInfo(bool verbose);
static int getSelectedInputChannel(bool verbose);
static void updateAutotestOverlay(const QString& title, const QString& detail = QString());

static void dumpSelectorLiteState(void* selectorLite, const char* phaseTag = nullptr) {
    if (!selectorLite) {
        fprintf(stderr,
                "[MC] %sselector-lite state: selectorLite=null\n",
                phaseTag ? phaseTag : "");
        return;
    }

    uint32_t u32_17c = 0;
    uint32_t u32_180 = 0;
    uint32_t u32_184 = 0;
    uint32_t u32_188 = 0;
    uint32_t u32_18c = 0;
    uint64_t ptr_a8 = 0;
    uint64_t ptr_150 = 0;
    uint64_t ptr_158 = 0;
    uint64_t ptr_160 = 0;
    uint64_t ptr_168 = 0;

    safeReadValue((uint8_t*)selectorLite + 0x17c, &u32_17c);
    safeReadValue((uint8_t*)selectorLite + 0x180, &u32_180);
    safeReadValue((uint8_t*)selectorLite + 0x184, &u32_184);
    safeReadValue((uint8_t*)selectorLite + 0x188, &u32_188);
    safeReadValue((uint8_t*)selectorLite + 0x18c, &u32_18c);
    safeReadValue((uint8_t*)selectorLite + 0xa8, &ptr_a8);
    safeReadValue((uint8_t*)selectorLite + 0x150, &ptr_150);
    safeReadValue((uint8_t*)selectorLite + 0x158, &ptr_158);
    safeReadValue((uint8_t*)selectorLite + 0x160, &ptr_160);
    safeReadValue((uint8_t*)selectorLite + 0x168, &ptr_168);

    SelectedStripInfo sel = getSelectedStripInfo(false);
    fprintf(stderr,
            "[MC] %sselector-lite state: self=%p sel.valid=%d sel.stripType=%u sel.channel=%d sel.channelPtr=%p "
            "off17c=%u off180=%u off184=%u off188=%u off18c=%u "
            "ptrA8=%p ptr150=%p ptr158=%p ptr160=%p ptr168=%p\n",
            phaseTag ? phaseTag : "",
            selectorLite,
            sel.valid ? 1 : 0,
            sel.stripType,
            sel.channel >= 0 ? sel.channel + 1 : -1,
            sel.channelPtr,
            u32_17c,
            u32_180,
            u32_184,
            u32_188,
            u32_18c,
            (void*)(uintptr_t)ptr_a8,
            (void*)(uintptr_t)ptr_150,
            (void*)(uintptr_t)ptr_158,
            (void*)(uintptr_t)ptr_160,
            (void*)(uintptr_t)ptr_168);
}

static void scanRootForKnownSelectorObjects(void* root,
                                            const char* rootLabel,
                                            const char* phaseTag,
                                            int directScanBytes = 0x1000,
                                            int childScanBytes = 0x800) {
    if (!root || (uintptr_t)root < 0x100000000ULL)
        return;

    const uintptr_t selectorMgrVt = (uintptr_t)0x106c77ca0 + g_slide + 0x10;
    const uintptr_t selectorVt = (uintptr_t)0x106c77c58 + g_slide + 0x10;
    const uintptr_t selectorLiteVt = (uintptr_t)0x106c7c098 + g_slide + 0x10;
    const uintptr_t surfaceChannelsVt = (uintptr_t)0x106ce5900 + g_slide + 0x10;

    struct TargetDesc {
        const char* name;
        uintptr_t vt;
    };
    const TargetDesc targets[] = {
        {"ChannelSelectorManager", selectorMgrVt},
        {"ChannelSelector", selectorVt},
        {"ChannelSelectorLite", selectorLiteVt},
        {"SurfaceChannels", surfaceChannelsVt},
    };
    bool nestedContainerScanTriggered = false;

    auto logHit = [&](const char* hitKind, int off, int subOff, void* container, void* obj, uintptr_t vt) {
        const char* typeName = "Unknown";
        for (const auto& target : targets) {
            if (target.vt == vt) {
                typeName = target.name;
                break;
            }
        }
        fprintf(stderr,
                "[MC] %sselector-root-scan: root=%s rootPtr=%p hit=%s type=%s off=0x%x subOff=0x%x container=%p obj=%p vt=%p\n",
                phaseTag ? phaseTag : "",
                rootLabel ? rootLabel : "(root)",
                root,
                hitKind,
                typeName,
                off,
                subOff,
                container,
                obj,
                (void*)vt);
    };

    for (int off = 0; off < directScanBytes; off += 8) {
        void* ptr = nullptr;
        if (!safeRead((uint8_t*)root + off, &ptr, sizeof(ptr)))
            continue;
        if (!ptr || (uintptr_t)ptr < 0x100000000ULL)
            continue;
        void* vtPtr = nullptr;
        if (safeRead(ptr, &vtPtr, sizeof(vtPtr))) {
            uintptr_t vt = (uintptr_t)vtPtr;
            for (const auto& target : targets) {
                if (vt == target.vt) {
                    logHit("direct", off, -1, root, ptr, vt);
                    break;
                }
            }
        }
        for (int subOff = 0; subOff < childScanBytes; subOff += 8) {
            void* child = nullptr;
            if (!safeRead((uint8_t*)ptr + subOff, &child, sizeof(child)))
                continue;
            if (!child || (uintptr_t)child < 0x100000000ULL)
                continue;
            void* childVtPtr = nullptr;
            if (!safeRead(child, &childVtPtr, sizeof(childVtPtr)))
                continue;
            uintptr_t childVt = (uintptr_t)childVtPtr;
            for (const auto& target : targets) {
                if (childVt == target.vt) {
                    logHit("child", off, subOff, ptr, child, childVt);
                    if (!nestedContainerScanTriggered &&
                        rootLabel &&
                        strcmp(rootLabel, "AppInstance") == 0 &&
                        target.vt == selectorLiteVt &&
                        ptr != root) {
                        nestedContainerScanTriggered = true;
                        scanRootForKnownSelectorObjects(ptr,
                                                        "AppInstanceSelectorContainer",
                                                        phaseTag,
                                                        0x8000,
                                                        0x2000);
                        if (const char* slotScanEnv = getenv("MC_EXPERIMENT_SELECTOR_SLOT_SCAN");
                            slotScanEnv && atoi(slotScanEnv) != 0) {
                            scanRootForVtableSlotCandidates(
                                ptr,
                                "AppInstanceSelectorContainer",
                                phaseTag,
                                (uintptr_t)0x1001e3360 + g_slide,
                                "DL5000PreampGainRotary",
                                0x12000,
                                0x3000,
                                256,
                                0x80);
                            scanRootForVtableSlotCandidates(
                                ptr,
                                "AppInstanceSelectorContainer",
                                phaseTag,
                                (uintptr_t)0x1001ddcd0 + g_slide,
                                "InformDL5000ControlSurfacePreAmpControls",
                                0x12000,
                                0x3000,
                                256,
                                0x80);
                        }
                    }
                    break;
                }
            }
        }
    }
}

static bool findChildContainerForTargetVtable(void* root,
                                              uintptr_t targetVtable,
                                              void** containerOut,
                                              void** objectOut,
                                              int directScanBytes = 0x1000,
                                              int childScanBytes = 0x800) {
    if (containerOut) *containerOut = nullptr;
    if (objectOut) *objectOut = nullptr;
    if (!root || targetVtable < 0x100000000ULL)
        return false;

    for (int off = 0; off < directScanBytes; off += 8) {
        void* ptr = nullptr;
        if (!safeRead((uint8_t*)root + off, &ptr, sizeof(ptr)))
            continue;
        if (!ptr || (uintptr_t)ptr < 0x100000000ULL)
            continue;

        void* vt = nullptr;
        if (safeRead(ptr, &vt, sizeof(vt)) && (uintptr_t)vt == targetVtable) {
            if (containerOut) *containerOut = root;
            if (objectOut) *objectOut = ptr;
            return true;
        }

        for (int subOff = 0; subOff < childScanBytes; subOff += 8) {
            void* child = nullptr;
            if (!safeRead((uint8_t*)ptr + subOff, &child, sizeof(child)))
                continue;
            if (!child || (uintptr_t)child < 0x100000000ULL)
                continue;
            void* childVt = nullptr;
            if (safeRead(child, &childVt, sizeof(childVt)) &&
                (uintptr_t)childVt == targetVtable) {
                if (containerOut) *containerOut = ptr;
                if (objectOut) *objectOut = child;
                return true;
            }
        }
    }
    return false;
}

static void initLogLevel() {
    if (g_mcLogLevel >= 0) return;
    g_mcLogLevel = MC_LOG_NORMAL;
    if (const char* env = getenv("MC_LOG_LEVEL")) {
        int parsed = atoi(env);
        if (parsed < MC_LOG_QUIET) parsed = MC_LOG_QUIET;
        if (parsed > MC_LOG_VERBOSE) parsed = MC_LOG_VERBOSE;
        g_mcLogLevel = parsed;
    }
}

static bool shouldEmitLogLine(const char* fmt) {
    initLogLevel();
    if (g_mcLogLevel >= MC_LOG_VERBOSE || !fmt) return true;

    bool severe =
        strstr(fmt, "ERROR") ||
        strstr(fmt, "FATAL") ||
        strstr(fmt, "WARNING") ||
        strstr(fmt, "WARN:") ||
        strstr(fmt, "FAIL");
    if (severe) return true;

    if (g_mcLogLevel <= MC_LOG_QUIET)
        return false;

    if (strstr(fmt, "[MC][AUTOTEST]") && !strstr(fmt, "RESULT"))
        return false;

    if (strstr(fmt, "[MC]   "))
        return false;

    return true;
}

static int mc_fprintf(FILE* stream, const char* fmt, ...) {
    if (stream == stderr && !shouldEmitLogLine(fmt))
        return 0;

    va_list ap;
    va_start(ap, fmt);
    int rc = vfprintf(stream, fmt, ap);
    va_end(ap);
    return rc;
}

#define fprintf mc_fprintf

static void setupLogging() {
    int fd = open(kMoveChannelLogPath, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd < 0) return;

    if (dup2(fd, STDERR_FILENO) >= 0) {
        setvbuf(stderr, nullptr, _IOLBF, 0);
        dprintf(STDERR_FILENO, "[MC] log file: %s\n", kMoveChannelLogPath);
    }
    close(fd);
}

static uint64_t monotonicMs() {
    using namespace std::chrono;
    return (uint64_t)duration_cast<milliseconds>(
        steady_clock::now().time_since_epoch()).count();
}

static void logAutotestTiming(const char* step, uint64_t elapsedMs, const char* detail = nullptr) {
    fprintf(stderr,
            "[MC][TIMING] step=%s ms=%llu%s%s\n",
            step ? step : "unknown",
            (unsigned long long)elapsedMs,
            detail && detail[0] ? " detail=" : "",
            detail && detail[0] ? detail : "");
}

static bool autotestEnvEnabled(const char* name) {
    const char* value = getenv(name);
    return value && atoi(value) != 0;
}

static bool envFlagEnabled(const char* name) {
    const char* value = getenv(name);
    return value && atoi(value) != 0;
}

static bool inputConfigSignalSettleEnabled() {
    if (const char* value = getenv("MC_EXPERIMENT_INPUTCFG_SIGNAL_SETTLE"))
        return atoi(value) != 0;
    return true;
}

static void* findChildObjectByVtable(void* root,
                                     uintptr_t expectedVtable,
                                     int directScanBytes = 0x400,
                                     int childScanBytes = 0x400) {
    if (!root || expectedVtable < 0x100000000ULL)
        return nullptr;

    for (int off = 0; off < directScanBytes; off += 8) {
        void* ptr = nullptr;
        if (!safeRead((uint8_t*)root + off, &ptr, sizeof(ptr)))
            continue;
        if (!ptr || (uintptr_t)ptr < 0x100000000ULL)
            continue;
        void* vt = nullptr;
        if (safeRead(ptr, &vt, sizeof(vt)) && (uintptr_t)vt == expectedVtable)
            return ptr;

        for (int subOff = 0; subOff < childScanBytes; subOff += 8) {
            void* child = nullptr;
            if (!safeRead((uint8_t*)ptr + subOff, &child, sizeof(child)))
                continue;
            if (!child || (uintptr_t)child < 0x100000000ULL)
                continue;
            void* childVt = nullptr;
            if (safeRead(child, &childVt, sizeof(childVt)) &&
                (uintptr_t)childVt == expectedVtable) {
                return child;
            }
        }
    }
    return nullptr;
}

static bool vtableHasNearbySlot(void* obj,
                                uintptr_t targetFn,
                                int slotCount,
                                intptr_t tolerance,
                                int* matchedSlot = nullptr) {
    if (!obj || (uintptr_t)obj < 0x100000000ULL || targetFn < 0x100000000ULL)
        return false;
    void* vt = nullptr;
    if (!safeRead(obj, &vt, sizeof(vt)) || !vt || (uintptr_t)vt < 0x100000000ULL)
        return false;
    for (int slot = 0; slot < slotCount; slot++) {
        uintptr_t fn = 0;
        if (!safeRead((uint8_t*)vt + slot * sizeof(void*), &fn, sizeof(fn)) ||
            fn < 0x100000000ULL)
            continue;
        if (llabs((long long)fn - (long long)targetFn) <= tolerance) {
            if (matchedSlot)
                *matchedSlot = slot;
            return true;
        }
    }
    return false;
}

static void scanRootForVtableSlotCandidates(void* root,
                                            const char* rootLabel,
                                            const char* phaseTag,
                                            uintptr_t targetFn,
                                            const char* targetLabel,
                                            int directScanBytes,
                                            int childScanBytes,
                                            int slotCount,
                                            intptr_t tolerance) {
    if (!root || (uintptr_t)root < 0x100000000ULL || targetFn < 0x100000000ULL)
        return;

    for (int off = 0; off < directScanBytes; off += 8) {
        void* ptr = nullptr;
        if (!safeRead((uint8_t*)root + off, &ptr, sizeof(ptr)))
            continue;
        if (!ptr || (uintptr_t)ptr < 0x100000000ULL)
            continue;

        int matchedSlot = -1;
        if (vtableHasNearbySlot(ptr, targetFn, slotCount, tolerance, &matchedSlot)) {
            fprintf(stderr,
                    "[MC] %svtable-slot-scan: root=%s rootPtr=%p target=%s hit=direct off=0x%x obj=%p matchedSlot=%d\n",
                    phaseTag ? phaseTag : "",
                    rootLabel ? rootLabel : "(root)",
                    root,
                    targetLabel ? targetLabel : "(target)",
                    off,
                    ptr,
                    matchedSlot);
        }

        for (int subOff = 0; subOff < childScanBytes; subOff += 8) {
            void* child = nullptr;
            if (!safeRead((uint8_t*)ptr + subOff, &child, sizeof(child)))
                continue;
            if (!child || (uintptr_t)child < 0x100000000ULL)
                continue;
            matchedSlot = -1;
            if (vtableHasNearbySlot(child, targetFn, slotCount, tolerance, &matchedSlot)) {
                fprintf(stderr,
                        "[MC] %svtable-slot-scan: root=%s rootPtr=%p target=%s hit=child off=0x%x subOff=0x%x container=%p obj=%p matchedSlot=%d\n",
                        phaseTag ? phaseTag : "",
                        rootLabel ? rootLabel : "(root)",
                        root,
                        targetLabel ? targetLabel : "(target)",
                        off,
                        subOff,
                        ptr,
                        child,
                        matchedSlot);
            }
        }
    }
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

static void maybePatchDirectorSingletonKey() {
    const char* flag = getenv("MC_PATCH_DIRECTOR_SINGLETON_KEY");
    if (!flag || flag[0] == '\0' || strcmp(flag, "0") == 0)
        return;
    if (!g_slide) {
        fprintf(stderr, "[MC] singleton patch: skipped, slide unresolved\n");
        return;
    }

    constexpr uintptr_t kDirectorSingletonKeyAddr = 0x10125bf15;
    char* keyPtr = (char*)((uintptr_t)kDirectorSingletonKeyAddr + g_slide);
    if (!keyPtr)
        return;

    char original[32] = {};
    memcpy(original, keyPtr, sizeof(original) - 1);
    if (strcmp(original, "dLiveDirectorRunning") != 0) {
        fprintf(stderr,
                "[MC] singleton patch: unexpected key at %p -> '%s'\n",
                keyPtr,
                original);
        return;
    }

    char patched[21] = {};
    snprintf(patched,
             sizeof(patched),
             "dLP%016llx",
             (unsigned long long)(uint32_t)getpid());

    long pageSize = sysconf(_SC_PAGESIZE);
    if (pageSize <= 0)
        pageSize = 4096;
    uintptr_t pageStart = (uintptr_t)keyPtr & ~((uintptr_t)pageSize - 1);
    bool madeWritable = false;
    if (mprotect((void*)pageStart, (size_t)pageSize, PROT_READ | PROT_WRITE) == 0) {
        madeWritable = true;
    } else {
        kern_return_t vmKr = vm_protect(mach_task_self(),
                                        (vm_address_t)pageStart,
                                        (vm_size_t)pageSize,
                                        false,
                                        VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY);
        if (vmKr == KERN_SUCCESS) {
            madeWritable = true;
        } else {
            fprintf(stderr,
                    "[MC] singleton patch: mprotect failed for %p errno=%d vm_protect=%d\n",
                    (void*)pageStart,
                    errno,
                    vmKr);
            return;
        }
    }
    memset(keyPtr, 0, strlen(original) + 1);
    memcpy(keyPtr, patched, strlen(patched));
    if (madeWritable)
        mprotect((void*)pageStart, (size_t)pageSize, PROT_READ);
    fprintf(stderr,
            "[MC] singleton patch: '%s' -> '%s'\n",
            original,
            keyPtr);
}

static void* findSurfaceDiscoveryNamedObject(const char* name) {
    if (!name || !name[0])
        return nullptr;
    typedef void* (*fn_SurfaceDiscoveryInstance)();
    typedef void* (*fn_GetSurfaceDiscoveryObject)(void*);
    typedef void* (*fn_DiscoveryObjectBaseFindObject)(void*, const char*);

    auto surfaceDiscoveryInstance =
        (fn_SurfaceDiscoveryInstance)((uintptr_t)0x1006ab790 + g_slide);
    auto getSurfaceDiscoveryObject =
        (fn_GetSurfaceDiscoveryObject)((uintptr_t)0x1006ab820 + g_slide);
    auto findObject =
        (fn_DiscoveryObjectBaseFindObject)((uintptr_t)0x10059caf0 + g_slide);
    if (!surfaceDiscoveryInstance || !getSurfaceDiscoveryObject || !findObject)
        return nullptr;

    void* discovery = surfaceDiscoveryInstance();
    if (!discovery)
        return nullptr;
    void* surfaceRoot = getSurfaceDiscoveryObject(discovery);
    if (!surfaceRoot)
        return nullptr;
    return findObject(surfaceRoot, name);
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
    // cProcessingOrderingSelect: via cProcessingOrderingSelectDriver at ch[16]→driver[1]
    {"ProcOrder", 16, 0x106c7a228, 2, 0x01, 1, 0, 1, {
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
static const int kProcStereoImageIdx = 7;
static const int kNumMuteGroups = 8;

static const size_t MSG_BUF_SIZE = 0x1000;
static const size_t kCsvImportPreampManagerSize = 0x200;

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
static void* g_uiManagerHolder = nullptr;    // cUIManagerHolder* (for current selected channel)
static void* g_channelSelectorManager = nullptr; // cChannelSelectorManager* (from UIManagerHolder scan)
static void* g_channelSelector = nullptr;   // cChannelSelector* (from ChannelSelectorManager scan)
static void* g_channelSelectorLite = nullptr; // cChannelSelectorLite* (from ChannelSelectorManager scan)
static void* g_processingSurfaceVisibilityManager = nullptr; // cProcessingSurfaceVisibilityManager*
static bool g_selectorFallbackDiscoveryAttempted = false;
static void* g_multifunctionChannelInterface = nullptr; // cMultifunctionChannelInterface* (from UIManagerHolder scan)
static void* g_uiCopyPasteResetManager = nullptr; // cUICopyPasteResetManager* (from UIManagerHolder scan)
static void* g_copyPasteResetSwitchInterpreter = nullptr; // cCopyPasteResetSwitchInterpreter*
static void* g_audioSRPManager = nullptr;    // cAudioSendReceivePointManager* (from cUIManagerHolder)
static void* g_dynRack = nullptr;            // cDynamicsRack* (from UIManagerHolder+0x40)
static void* g_sceneClient = nullptr;       // cSceneManagerIntermediateClient* (from UIManagerHolder scan)
static void* g_showManagerClientBase = nullptr; // cShowManagerClientBase* (from UIManagerHolder scan)
static void* g_showManagerClient = nullptr; // cShowManagerClient* (from UIManagerHolder scan)
static bool g_showManagerSignalsHooked = false;
static bool g_lastStereoInputConfigSignalObserved = false;
static uint64_t g_lastStereoInputConfigSignalMs = 0;
static void* g_virtualMixRackShowManagerClient = nullptr; // cVirtualMixRackShowManagerClient*
static void* g_sceneImportManagerClient = nullptr; // cSceneImportManagerClient*
static void* g_uiChannelSelectListener = nullptr; // cUIChannelSelectListener* (from UIManagerHolder scan)
static void* g_uiListenManager = nullptr; // cUIListenManager* (from UIManagerHolder scan)
static void* g_libraryMgrClient = nullptr;  // cLibraryManagerClient* (from UIManagerHolder+0x98)
static void* g_gangingManager = nullptr;    // cGangingManager* (from UIManagerHolder scan)
static void* g_surfaceChannels = nullptr;   // cSurfaceChannels* (from UIManagerHolder scan)
static int g_firstAnalogueInputIdx = -1;     // first cAnalogueInput index in router table
static int g_firstDynNetObjIdx = -1;         // first cDynamicsNetObject index in router table
static int g_dynNetObjIndices[256] = {};     // all found cDynamicsNetObject registry indices
static int g_dynNetObjCount = 0;             // total found

static const size_t SINPUTATTRS_SIZE = 0xAC8; // sizeof(sInputAttributes)
static const int kMaxAnalogueInputSocket = 511;
static const uint32_t kMixRackIOPortAudioSourceType = 5;
static const size_t kMixerMainMuteOffset = 0x000;
static const size_t kMixerDCAOffset = 0x001;
static const size_t kMixerGroupOnOffset = 0x025;
static const size_t kMixerAuxOnOffset = 0x065;
static const size_t kMixerAuxPreOffset = 0x0A5;
static const size_t kMixerAuxGainOffset = 0x0E6;
static const size_t kMixerMatrixOnOffset = 0x606;
static const size_t kMixerMatrixPreOffset = 0x646;
static const size_t kMixerMatrixGainOffset = 0x686;
static const size_t kMixerMainOnOffset = 0xA86;
static const size_t kMixerMainMonoOnOffset = 0xA87;
static const size_t kMixerMainGainOffset = 0xA88;
static const int kMixerNumDCAs = 32;
static const int kMixerNumGroups = 64;
static const int kMixerNumAuxes = 64;
static const int kMixerNumMatrices = 64;
static const size_t kMixerGainStride = 6;
static void* g_csvImportPreampManager = nullptr;
static dispatch_queue_t g_csvPreampQueue = nullptr;

static void discoverSelectorManagerFromChannelMapper(const char* phaseTag) {
    const uintptr_t selectorMgrVt = (uintptr_t)0x106c77ca0 + g_slide + 0x10;
    const uintptr_t selectorVt = (uintptr_t)0x106c77c58 + g_slide + 0x10;

    if (!g_channelMapper || (uintptr_t)g_channelMapper < 0x100000000ULL)
        return;

    if (!g_channelSelectorManager) {
        void* ptr = nullptr;
        if (safeRead((uint8_t*)g_channelMapper + 0xd360, &ptr, sizeof(ptr)) &&
            ptr && (uintptr_t)ptr >= 0x100000000ULL) {
            void* vt = nullptr;
            if (safeRead(ptr, &vt, sizeof(vt)) && (uintptr_t)vt == selectorMgrVt) {
                g_channelSelectorManager = ptr;
                fprintf(stderr,
                        "[MC] %sselector-manager discovery: from ChannelMapper+0xd360 = %p\n",
                        phaseTag ? phaseTag : "",
                        g_channelSelectorManager);
            } else {
                fprintf(stderr,
                        "[MC] %sselector-manager discovery: ChannelMapper+0xd360 candidate=%p vt=%p expected=%p\n",
                        phaseTag ? phaseTag : "",
                        ptr,
                        vt,
                        (void*)selectorMgrVt);
            }
        }
    }

    if (!g_channelSelector && g_channelSelectorManager) {
        for (int idx = 0; idx < 8; ++idx) {
            void* selector = nullptr;
            if (!safeRead((uint8_t*)g_channelSelectorManager + 0xa0 + idx * 8,
                          &selector,
                          sizeof(selector))) {
                continue;
            }
            if (!selector || (uintptr_t)selector < 0x100000000ULL)
                continue;
            void* vt = nullptr;
            if (!safeRead(selector, &vt, sizeof(vt)) || (uintptr_t)vt != selectorVt)
                continue;
            g_channelSelector = selector;
            fprintf(stderr,
                    "[MC] %sselector-manager discovery: selector[%d] = %p\n",
                    phaseTag ? phaseTag : "",
                    idx,
                    g_channelSelector);
            break;
        }
    }
}

static void discoverSelectorObjectsFallback(const char* phaseTag) {
    if (g_selectorFallbackDiscoveryAttempted &&
        (g_channelSelector || g_channelSelectorLite || g_processingSurfaceVisibilityManager))
        return;
    if (g_selectorFallbackDiscoveryAttempted &&
        !g_channelSelector && !g_channelSelectorLite && !g_processingSurfaceVisibilityManager)
        return;

    g_selectorFallbackDiscoveryAttempted = true;

    uintptr_t selectorVt = (uintptr_t)0x106c77c58 + g_slide + 0x10;
    uintptr_t selectorLiteVt = (uintptr_t)0x106c7c098 + g_slide + 0x10;
    uintptr_t visibilityVt = (uintptr_t)0x106ce2a68 + g_slide + 0x10;

    std::vector<std::pair<const char*, void*>> roots;
    auto addRoot = [&](const char* label, void* ptr) {
        if (!ptr)
            return;
        for (const auto& entry : roots) {
            if (entry.second == ptr)
                return;
        }
        roots.emplace_back(label, ptr);
    };

    addRoot("AppInstance", g_AppInstance ? g_AppInstance() : nullptr);
    addRoot("AudioDM", g_audioDM);
    addRoot("InputMixerWrapper", g_inputMixerWrapper);
    addRoot("ChannelMapper", g_channelMapper);
    addRoot("SurfaceChannels", g_surfaceChannels);
    addRoot("ShowManagerClient", g_showManagerClient);
    addRoot("ShowManagerClientBase", g_showManagerClientBase);
    addRoot("MultifunctionChannelInterface", g_multifunctionChannelInterface);
    addRoot("UIManagerHolder", g_uiManagerHolder);
    addRoot("qApp", qApp);

    typedef void* (*fn_SurfaceDiscoveryInstance)();
    typedef void* (*fn_GetSurfaceDiscoveryObject)(void*);
    auto surfaceDiscoveryInstance =
        (fn_SurfaceDiscoveryInstance)((uintptr_t)0x1006ab790 + g_slide);
    auto getSurfaceDiscoveryObject =
        (fn_GetSurfaceDiscoveryObject)((uintptr_t)0x1006ab820 + g_slide);
    if (surfaceDiscoveryInstance && getSurfaceDiscoveryObject) {
        void* discovery = surfaceDiscoveryInstance();
        addRoot("SurfaceDiscovery", discovery);
        addRoot("SurfaceDiscoveryRoot", discovery ? getSurfaceDiscoveryObject(discovery) : nullptr);
    }

    for (const auto& [label, root] : roots) {
        if (!g_channelSelector) {
            void* found = findChildObjectByVtable(root, selectorVt, 0x4000, 0x4000);
            if (found) {
                g_channelSelector = found;
                fprintf(stderr,
                        "[MC] %sselector fallback: ChannelSelector found from %s = %p\n",
                        phaseTag ? phaseTag : "",
                        label,
                        found);
            }
        }
        if (!g_channelSelectorLite) {
            void* found = findChildObjectByVtable(root, selectorLiteVt, 0x4000, 0x4000);
            if (found) {
                g_channelSelectorLite = found;
                fprintf(stderr,
                        "[MC] %sselector fallback: ChannelSelectorLite found from %s = %p\n",
                        phaseTag ? phaseTag : "",
                        label,
                        found);
            }
        }
        if (!g_processingSurfaceVisibilityManager) {
            void* found = findChildObjectByVtable(root, visibilityVt, 0x4000, 0x4000);
            if (found) {
                g_processingSurfaceVisibilityManager = found;
                fprintf(stderr,
                        "[MC] %sselector fallback: ProcessingSurfaceVisibilityManager found from %s = %p\n",
                        phaseTag ? phaseTag : "",
                        label,
                        found);
            }
        }
    }

    fprintf(stderr,
            "[MC] %sselector fallback summary: selector=%p selectorLite=%p visibilityMgr=%p roots=%zu\n",
            phaseTag ? phaseTag : "",
            g_channelSelector,
            g_channelSelectorLite,
            g_processingSurfaceVisibilityManager,
            roots.size());
}

static void rescanSelectionProvidersFromUIHolder(int desiredStripType = -1,
                                                 int desiredChannel = -1,
                                                 bool verbose = false) {
    (void)desiredStripType;
    (void)desiredChannel;
    if (verbose) {
        fprintf(stderr,
                "[MC] Selection provider rescan disabled; using startup discovery and cached/UIHolder selection only.\n");
    }
}

// sAudioSource: 8 bytes {uint32_t type, uint32_t number}
struct sAudioSource { uint32_t type; uint32_t number; };

// Patching data per channel
struct PatchData {
    uint32_t     sourceType;  // from activeInputChannelSourceType[ch]
    sAudioSource source;      // from the appropriate array
};

struct GangStripKey {
    uint32_t stripType = 0;
    uint8_t channel = 0xFF;
    uint8_t pad[3] = {0, 0, 0};
};

struct GangAttributesRaw {
    uint64_t lo = 0;
    uint64_t hi = 0;
};

struct GangSnapshot {
    uint8_t gangNum = 0;
    uint32_t stripType = 0;
    std::vector<uint8_t> memberChannels;
    GangAttributesRaw attrs = {};
    bool valid = false;
    bool affected = false;
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
            g_uiManagerHolder = uiHolder;
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

            uintptr_t showMgrBaseVt = (uintptr_t)RESOLVE(0x106c9e138) + 0x10;
            uintptr_t showMgrVt = (uintptr_t)RESOLVE(0x106d0da90) + 0x10;
            uintptr_t vmrShowMgrVt = (uintptr_t)RESOLVE(0x106cfb420) + 0x10;
            uintptr_t sceneImportMgrVt = (uintptr_t)RESOLVE(0x106c9dd10) + 0x10;
            uintptr_t uiChannelSelectListenerVt = (uintptr_t)RESOLVE(0x106d0f240) + 0x10;
            uintptr_t uiListenManagerVt = (uintptr_t)RESOLVE(0x106c9eea0) + 0x10;
            for (int off = 0; off < 0x400; off += 8) {
                void* ptr = nullptr;
                safeRead((uint8_t*)uiHolder + off, &ptr, sizeof(ptr));
                if (!ptr || (uintptr_t)ptr < 0x100000000ULL) continue;
                void* vt = nullptr;
                safeRead(ptr, &vt, sizeof(vt));
                uintptr_t vtp = (uintptr_t)vt;
                if (!g_showManagerClientBase && vtp == showMgrBaseVt) {
                    g_showManagerClientBase = ptr;
                    fprintf(stderr, "[MC] ShowManagerClientBase at UIManagerHolder+0x%x = %p\n", off, ptr);
                }
                if (!g_showManagerClient && vtp == showMgrVt) {
                    g_showManagerClient = ptr;
                    fprintf(stderr, "[MC] ShowManagerClient at UIManagerHolder+0x%x = %p\n", off, ptr);
                }
                if (!g_virtualMixRackShowManagerClient && vtp == vmrShowMgrVt) {
                    g_virtualMixRackShowManagerClient = ptr;
                    fprintf(stderr, "[MC] VirtualMixRackShowManagerClient at UIManagerHolder+0x%x = %p\n", off, ptr);
                }
                if (!g_sceneImportManagerClient && vtp == sceneImportMgrVt) {
                    g_sceneImportManagerClient = ptr;
                    fprintf(stderr, "[MC] SceneImportManagerClient at UIManagerHolder+0x%x = %p\n", off, ptr);
                }
                if (!g_uiChannelSelectListener && vtp == uiChannelSelectListenerVt) {
                    g_uiChannelSelectListener = ptr;
                    fprintf(stderr, "[MC] UIChannelSelectListener at UIManagerHolder+0x%x = %p\n", off, ptr);
                }
                if (!g_uiListenManager && vtp == uiListenManagerVt) {
                    g_uiListenManager = ptr;
                    fprintf(stderr, "[MC] UIListenManager at UIManagerHolder+0x%x = %p\n", off, ptr);
                }
            }
            if (!g_showManagerClientBase) fprintf(stderr, "[MC] ShowManagerClientBase not found in UIManagerHolder\n");
            if (!g_showManagerClient) fprintf(stderr, "[MC] ShowManagerClient not found in UIManagerHolder\n");
            if (!g_virtualMixRackShowManagerClient) fprintf(stderr, "[MC] VirtualMixRackShowManagerClient not found in UIManagerHolder\n");
            if (!g_sceneImportManagerClient) fprintf(stderr, "[MC] SceneImportManagerClient not found in UIManagerHolder\n");
            if (!g_uiChannelSelectListener) fprintf(stderr, "[MC] UIChannelSelectListener not found in UIManagerHolder\n");
            if (!g_uiListenManager) fprintf(stderr, "[MC] UIListenManager not found in UIManagerHolder\n");

            // cLibraryManagerClient at UIManagerHolder+0x98 (confirmed from PerformRecall disasm)
            safeRead((uint8_t*)uiHolder + 0x98, &g_libraryMgrClient, sizeof(g_libraryMgrClient));
            fprintf(stderr, "[MC] LibraryManagerClient=%p\n", g_libraryMgrClient);

            // Find cGangingManager by vtable scan
            uintptr_t gangingMgrVt = (uintptr_t)RESOLVE(0x106ced990) + 0x10; // vtable symbol + 0x10
            for (int off = 0; off < 0x300; off += 8) {
                void* ptr = nullptr;
                safeRead((uint8_t*)uiHolder + off, &ptr, sizeof(ptr));
                if (!ptr || (uintptr_t)ptr < 0x100000000ULL) continue;
                void* vt = nullptr;
                safeRead(ptr, &vt, sizeof(vt));
                if ((uintptr_t)vt == gangingMgrVt) {
                    g_gangingManager = ptr;
                    fprintf(stderr, "[MC] GangingManager at UIManagerHolder+0x%x = %p\n", off, ptr);
                    break;
                }
            }
            if (!g_gangingManager) fprintf(stderr, "[MC] GangingManager not found in UIManagerHolder\n");

            // Find cSurfaceChannels by vtable scan
            uintptr_t surfaceChannelsVt = (uintptr_t)RESOLVE(0x106ce5900) + 0x10; // vtable symbol + 0x10
            for (int off = 0; off < 0x400; off += 8) {
                void* ptr = nullptr;
                safeRead((uint8_t*)uiHolder + off, &ptr, sizeof(ptr));
                if (!ptr || (uintptr_t)ptr < 0x100000000ULL) continue;
                void* vt = nullptr;
                safeRead(ptr, &vt, sizeof(vt));
                if ((uintptr_t)vt == surfaceChannelsVt) {
                    g_surfaceChannels = ptr;
                    fprintf(stderr, "[MC] SurfaceChannels at UIManagerHolder+0x%x = %p\n", off, ptr);
                    break;
                }
            }
            if (!g_surfaceChannels) fprintf(stderr, "[MC] SurfaceChannels not found in UIManagerHolder\n");

            uintptr_t uiCprMgrVt = (uintptr_t)RESOLVE(0x106c9eba8) + 0x10;
            for (int off = 0; off < 0x400; off += 8) {
                void* ptr = nullptr;
                safeRead((uint8_t*)uiHolder + off, &ptr, sizeof(ptr));
                if (!ptr || (uintptr_t)ptr < 0x100000000ULL) continue;
                void* vt = nullptr;
                safeRead(ptr, &vt, sizeof(vt));
                if ((uintptr_t)vt == uiCprMgrVt) {
                    g_uiCopyPasteResetManager = ptr;
                    fprintf(stderr, "[MC] UICopyPasteResetManager at UIManagerHolder+0x%x = %p\n", off, ptr);
                    break;
                }
            }
            if (!g_uiCopyPasteResetManager)
                fprintf(stderr, "[MC] UICopyPasteResetManager not found in UIManagerHolder\n");

            uintptr_t cprSwitchInterpVt = (uintptr_t)RESOLVE(0x106ce1fe8) + 0x10;
            for (int off = 0; off < 0x400; off += 8) {
                void* ptr = nullptr;
                safeRead((uint8_t*)uiHolder + off, &ptr, sizeof(ptr));
                if (!ptr || (uintptr_t)ptr < 0x100000000ULL) continue;
                void* vt = nullptr;
                safeRead(ptr, &vt, sizeof(vt));
                if ((uintptr_t)vt == cprSwitchInterpVt) {
                    g_copyPasteResetSwitchInterpreter = ptr;
                    fprintf(stderr, "[MC] CopyPasteResetSwitchInterpreter at UIManagerHolder+0x%x = %p\n", off, ptr);
                    break;
                }
            }
            if (!g_copyPasteResetSwitchInterpreter)
                fprintf(stderr, "[MC] CopyPasteResetSwitchInterpreter not found in UIManagerHolder\n");

            uintptr_t selectorMgrVt = (uintptr_t)RESOLVE(0x106c77ca0) + 0x10;
            for (int off = 0; off < 0x400; off += 8) {
                void* ptr = nullptr;
                safeRead((uint8_t*)uiHolder + off, &ptr, sizeof(ptr));
                if (!ptr || (uintptr_t)ptr < 0x100000000ULL) continue;
                void* vt = nullptr;
                safeRead(ptr, &vt, sizeof(vt));
                if ((uintptr_t)vt == selectorMgrVt) {
                    g_channelSelectorManager = ptr;
                    fprintf(stderr, "[MC] ChannelSelectorManager at UIManagerHolder+0x%x = %p\n", off, ptr);
                    break;
                }
            }
            if (!g_channelSelectorManager)
                fprintf(stderr, "[MC] ChannelSelectorManager not found in UIManagerHolder\n");
            else {
                uintptr_t selectorVt = (uintptr_t)RESOLVE(0x106c77c58) + 0x10;
                uintptr_t selectorLiteVt = (uintptr_t)RESOLVE(0x106c7c098) + 0x10;
                g_channelSelector = findChildObjectByVtable(g_channelSelectorManager, selectorVt);
                g_channelSelectorLite = findChildObjectByVtable(g_channelSelectorManager, selectorLiteVt);
                if (g_channelSelector) {
                    fprintf(stderr, "[MC] ChannelSelector discovered from ChannelSelectorManager = %p\n",
                            g_channelSelector);
                }
                if (g_channelSelectorLite) {
                    fprintf(stderr, "[MC] ChannelSelectorLite discovered from ChannelSelectorManager = %p\n",
                            g_channelSelectorLite);
                }
                if (!g_channelSelector)
                    fprintf(stderr, "[MC] ChannelSelector not found in ChannelSelectorManager\n");
                if (!g_channelSelectorLite)
                    fprintf(stderr, "[MC] ChannelSelectorLite not found in ChannelSelectorManager\n");
            }
            if (!g_channelSelectorManager || !g_channelSelector)
                discoverSelectorManagerFromChannelMapper("[MC] ");

            uintptr_t multiFuncGetSelected = (uintptr_t)RESOLVE(0x1001098470);
            for (int off = 0; off < 0x400; off += 8) {
                void* ptr = nullptr;
                safeRead((uint8_t*)uiHolder + off, &ptr, sizeof(ptr));
                if (!ptr || (uintptr_t)ptr < 0x100000000ULL) continue;
                void* vt = nullptr;
                safeRead(ptr, &vt, sizeof(vt));
                if (!vt) continue;
                uintptr_t slot0 = 0;
                safeRead(vt, &slot0, sizeof(slot0));
                if (slot0 > 0x100000000ULL && llabs((long long)slot0 - (long long)multiFuncGetSelected) < 0x2000000LL) {
                    g_multifunctionChannelInterface = ptr;
                    fprintf(stderr, "[MC] MultifunctionChannelInterface candidate at UIManagerHolder+0x%x = %p (slot0=%p)\n",
                            off, ptr, (void*)slot0);
                    break;
                }
            }
            if (!g_multifunctionChannelInterface)
                fprintf(stderr, "[MC] MultifunctionChannelInterface candidate not found in UIManagerHolder\n");

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

struct MCShowKey {
    QString name;
    int location = 3;
    uint16_t slot = 0;
    uint16_t reserved = 0;
    QString aux;
};

static const char* showLocationName(int location) {
    switch (location) {
        case 0: return "Unknown0";
        case 1: return "MixRack";
        case 2: return "Surface";
        case 3: return "EditorLocal";
        case 4: return "USB";
        case 5: return "Unknown5";
        default: return "Unknown";
    }
}

static QString normalizeShowName(const QString& text) {
    return text.trimmed().toCaseFolded();
}

static void* getShowManagerClientForCalls() {
    if (g_showManagerClient)
        return g_showManagerClient;
    if (g_showManagerClientBase)
        return g_showManagerClientBase;
    return nullptr;
}

static void hookShowManagerSignalsForLogging() {
    if (g_showManagerSignalsHooked)
        return;
    QObject* sender = reinterpret_cast<QObject*>(getShowManagerClientForCalls());
    if (!sender)
        return;
    const QMetaObject* mo = sender->metaObject();
    if (!mo)
        return;

    auto logSignalPresence = [&](const char* signalName) {
        for (int i = mo->methodOffset(); i < mo->methodCount(); i++) {
            QMetaMethod method = mo->method(i);
            if (method.methodType() != QMetaMethod::Signal)
                continue;
            QByteArray name = method.name();
            if (name != signalName)
                continue;
            fprintf(stderr,
                    "[MC][SHOWSIG] found signal %s method='%s'\n",
                    signalName,
                    method.methodSignature().constData());
            return;
        }
        fprintf(stderr, "[MC][SHOWSIG] signal %s not found\n", signalName);
    };

    logSignalPresence("ShowsChanged");
    logSignalPresence("ShowRecallComplete");
    logSignalPresence("ShowRecalled");
    g_showManagerSignalsHooked = true;
}

static QList<MCShowKey> getShowsForLocation(int location) {
    QList<MCShowKey> out;
    void* client = getShowManagerClientForCalls();
    if (!client)
        return out;
    typedef void (*fn_GetShows)(void* client, QList<MCShowKey>& out, int location);
    auto getShows = (fn_GetShows)RESOLVE(0x100723bc0);
    getShows(client, out, location);
    return out;
}

static void dumpAvailableShows() {
    void* client = getShowManagerClientForCalls();
    if (!client) {
        fprintf(stderr, "[MC] dumpAvailableShows: no show manager client!\n");
        return;
    }
    fprintf(stderr, "[MC] ==== Available Shows ====\n");
    for (int location = 0; location <= 5; location++) {
        QList<MCShowKey> shows = getShowsForLocation(location);
        fprintf(stderr,
                "[MC] show location %d (%s): %d shows\n",
                location,
                showLocationName(location),
                shows.size());
        for (int i = 0; i < shows.size(); i++) {
            const MCShowKey& key = shows[i];
            QByteArray nameUtf8 = key.name.toUtf8();
            QByteArray auxUtf8 = key.aux.toUtf8();
            fprintf(stderr,
                    "[MC][SHOW] show[%d]: name='%s' loc=%d(%s) slot=%u aux='%s'\n",
                    i,
                    nameUtf8.constData(),
                    key.location,
                    showLocationName(key.location),
                    (unsigned)key.slot,
                    auxUtf8.constData());
        }
    }
}

static bool findShowKeyByName(const QString& wantedName, MCShowKey& outKey) {
    void* client = getShowManagerClientForCalls();
    if (!client)
        return false;

    QString wantedNorm = normalizeShowName(wantedName);
    for (int location = 0; location <= 5; location++) {
        QList<MCShowKey> shows = getShowsForLocation(location);
        for (const MCShowKey& key : shows) {
            if (normalizeShowName(key.name) == wantedNorm ||
                normalizeShowName(key.aux) == wantedNorm) {
                outKey = key;
                return true;
            }
        }
    }
    return false;
}

static bool getShowKeyFromExperimentEnv(const QString& fallbackName, MCShowKey& outKey) {
    const char* locEnv = getenv("MC_EXPERIMENT_COPY_SHOW_SOURCE_LOCATION");
    const char* slotEnv = getenv("MC_EXPERIMENT_COPY_SHOW_SOURCE_SLOT");
    if (!locEnv || !slotEnv || !*locEnv || !*slotEnv)
        return false;

    bool okLoc = false;
    bool okSlot = false;
    int location = QString::fromUtf8(locEnv).toInt(&okLoc);
    int slot = QString::fromUtf8(slotEnv).toInt(&okSlot);
    if (!okLoc || !okSlot || location < 0 || location > 5 || slot < 0 || slot > 0xffff)
        return false;

    outKey.name = fallbackName;
    outKey.location = location;
    outKey.slot = (uint16_t)slot;
    outKey.reserved = 0;
    if (const char* auxEnv = getenv("MC_EXPERIMENT_COPY_SHOW_SOURCE_AUX"))
        outKey.aux = QString::fromUtf8(auxEnv);
    if (const char* nameEnv = getenv("MC_EXPERIMENT_COPY_SHOW_SOURCE_KEY_NAME")) {
        QString overrideName = QString::fromUtf8(nameEnv).trimmed();
        if (!overrideName.isEmpty())
            outKey.name = overrideName;
    }
    fprintf(stderr,
            "[MC][SHOWEXP] using explicit source key from env: name='%s' loc=%d(%s) slot=%u aux='%s'\n",
            outKey.name.toUtf8().constData(),
            outKey.location,
            showLocationName(outKey.location),
            (unsigned)outKey.slot,
            outKey.aux.toUtf8().constData());
    return true;
}

static bool recallShowByName(const QString& wantedName) {
    void* client = getShowManagerClientForCalls();
    if (!client) {
        fprintf(stderr, "[MC] recallShowByName('%s'): no show manager client!\n",
                wantedName.toUtf8().constData());
        return false;
    }

    MCShowKey key;
    if (!findShowKeyByName(wantedName, key)) {
        fprintf(stderr, "[MC] recallShowByName('%s'): show not found\n",
                wantedName.toUtf8().constData());
        dumpAvailableShows();
        return false;
    }

    typedef void (*fn_RecallShow)(void* client, MCShowKey key, bool arg1, bool arg2);
    auto recallShow = (fn_RecallShow)RESOLVE(0x1007249e0);
    fprintf(stderr,
            "[MC] recallShowByName('%s'): recalling key name='%s' loc=%d(%s) slot=%u aux='%s'\n",
            wantedName.toUtf8().constData(),
            key.name.toUtf8().constData(),
            key.location,
            showLocationName(key.location),
            (unsigned)key.slot,
            key.aux.toUtf8().constData());
    recallShow(client, key, false, false);
    return true;
}

static void waitForSceneRecall();

static QString makeAutotestTempShowName(const QString& baseName) {
    QString cleaned = baseName.trimmed();
    if (cleaned.isEmpty())
        cleaned = "TESTING";
    QString suffix = QString("MC_%1")
                         .arg((qulonglong)(monotonicMs() % 100000000ULL));
    return QString("%1 %2").arg(cleaned, suffix);
}

static bool copyShowByNameToLocation(const QString& sourceName,
                                     const QString& destName,
                                     int destLocation,
                                     int copyAction) {
    void* client = getShowManagerClientForCalls();
    if (!client) {
        fprintf(stderr,
                "[MC] copyShowByNameToLocation('%s' -> '%s'): no show manager client!\n",
                sourceName.toUtf8().constData(),
                destName.toUtf8().constData());
        return false;
    }

    MCShowKey sourceKey;
    if (!getShowKeyFromExperimentEnv(sourceName, sourceKey) &&
        !findShowKeyByName(sourceName, sourceKey)) {
        fprintf(stderr,
                "[MC] copyShowByNameToLocation('%s' -> '%s'): source show not found\n",
                sourceName.toUtf8().constData(),
                destName.toUtf8().constData());
        dumpAvailableShows();
        return false;
    }

    if (!envFlagEnabled("MC_EXPERIMENT_COPY_SHOW_SKIP_DEST_LOOKUP")) {
        MCShowKey existingDest;
        if (findShowKeyByName(destName, existingDest)) {
            fprintf(stderr,
                    "[MC] copyShowByNameToLocation('%s' -> '%s'): destination already exists at loc=%d(%s) slot=%u\n",
                    sourceName.toUtf8().constData(),
                    destName.toUtf8().constData(),
                    existingDest.location,
                    showLocationName(existingDest.location),
                    (unsigned)existingDest.slot);
            return false;
        }
    } else {
        fprintf(stderr,
                "[MC][SHOWEXP] skipping destination lookup for '%s' due to MC_EXPERIMENT_COPY_SHOW_SKIP_DEST_LOOKUP\n",
                destName.toUtf8().constData());
    }

    typedef void (*fn_CopyShow)(void* client,
                                MCShowKey source,
                                int copyAction,
                                QString destName,
                                int destLocation);
    auto copyShow = (fn_CopyShow)RESOLVE(0x1007246f0);
    fprintf(stderr,
            "[MC] copyShowByNameToLocation('%s' -> '%s'): source loc=%d(%s) slot=%u, dest loc=%d(%s), action=%d\n",
            sourceName.toUtf8().constData(),
            destName.toUtf8().constData(),
            sourceKey.location,
            showLocationName(sourceKey.location),
            (unsigned)sourceKey.slot,
            destLocation,
            showLocationName(destLocation),
            copyAction);
    copyShow(client, sourceKey, copyAction, destName, destLocation);
    return true;
}

static bool runShowCopyRecallExperiment() {
    const char* srcEnv = getenv("MC_EXPERIMENT_COPY_SHOW_SRC");
    if (!srcEnv || !*srcEnv)
        return false;

    QString sourceName = QString::fromUtf8(srcEnv).trimmed();
    if (sourceName.isEmpty())
        return false;

    QString destName;
    if (const char* dstEnv = getenv("MC_EXPERIMENT_COPY_SHOW_DST")) {
        destName = QString::fromUtf8(dstEnv).trimmed();
    }
    if (destName.isEmpty())
        destName = makeAutotestTempShowName(sourceName);

    int destLocation = 3;
    if (const char* locEnv = getenv("MC_EXPERIMENT_COPY_SHOW_LOCATION")) {
        int parsed = atoi(locEnv);
        if (parsed >= 0 && parsed <= 5)
            destLocation = parsed;
    }

    int copyAction = 1;
    if (const char* actionEnv = getenv("MC_EXPERIMENT_COPY_SHOW_ACTION")) {
        int parsed = atoi(actionEnv);
        if (parsed >= 0)
            copyAction = parsed;
    }

    updateAutotestOverlay("dLive Self-Test",
                          QString("Copying SHOW %1 -> %2")
                              .arg(sourceName, destName));
    fprintf(stderr,
            "[MC][SHOWEXP] starting native show copy experiment: src='%s' dst='%s' loc=%d(%s) action=%d\n",
            sourceName.toUtf8().constData(),
            destName.toUtf8().constData(),
            destLocation,
            showLocationName(destLocation),
            copyAction);

    if (!envFlagEnabled("MC_EXPERIMENT_COPY_SHOW_NOWAIT")) {
        updateAutotestOverlay("dLive Self-Test",
                              QString("Waiting for show manager to settle"));
        fprintf(stderr, "[MC][SHOWEXP] waiting for show manager settle before copy\n");
        waitForSceneRecall();
    }

    if (!copyShowByNameToLocation(sourceName, destName, destLocation, copyAction)) {
        updateAutotestOverlay("dLive Self-Test",
                              QString("SHOW copy failed: %1").arg(destName));
        fprintf(stderr, "[MC][SHOWEXP] copy request failed to start\n");
        return false;
    }

    updateAutotestOverlay("dLive Self-Test",
                          QString("Waiting for SHOW %1 copy").arg(destName));
    waitForSceneRecall();

    if (envFlagEnabled("MC_EXPERIMENT_COPY_SHOW_SKIP_VERIFY")) {
        fprintf(stderr,
                "[MC][SHOWEXP] skipping copied-show lookup/recall verification for '%s'\n",
                destName.toUtf8().constData());
        updateAutotestOverlay("dLive Self-Test",
                              QString("SHOW copy request sent: %1").arg(destName));
        return true;
    }

    MCShowKey copiedKey;
    bool foundCopy = findShowKeyByName(destName, copiedKey);
    fprintf(stderr,
            "[MC][SHOWEXP] copied show lookup for '%s': %s\n",
            destName.toUtf8().constData(),
            foundCopy ? "FOUND" : "NOT FOUND");
    if (foundCopy) {
        fprintf(stderr,
                "[MC][SHOWEXP] copied key name='%s' loc=%d(%s) slot=%u aux='%s'\n",
                copiedKey.name.toUtf8().constData(),
                copiedKey.location,
                showLocationName(copiedKey.location),
                (unsigned)copiedKey.slot,
                copiedKey.aux.toUtf8().constData());
    } else {
        dumpAvailableShows();
        updateAutotestOverlay("dLive Self-Test",
                              QString("SHOW copy missing: %1").arg(destName));
        return false;
    }

    if (envFlagEnabled("MC_EXPERIMENT_COPY_SHOW_RECALL")) {
        updateAutotestOverlay("dLive Self-Test",
                              QString("Recalling copied SHOW %1").arg(destName));
        if (!recallShowByName(destName)) {
            fprintf(stderr,
                    "[MC][SHOWEXP] failed to recall copied show '%s'\n",
                    destName.toUtf8().constData());
            updateAutotestOverlay("dLive Self-Test",
                                  QString("Recall failed: %1").arg(destName));
            return false;
        }
        waitForSceneRecall();
        fprintf(stderr,
                "[MC][SHOWEXP] recall of copied show '%s' completed\n",
                destName.toUtf8().constData());
    }

    updateAutotestOverlay("dLive Self-Test",
                          QString("SHOW copy experiment OK: %1").arg(destName));
    fprintf(stderr,
            "[MC][SHOWEXP] native show copy experiment completed successfully for '%s'\n",
            destName.toUtf8().constData());
    return true;
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

// Ask Director to recall "current settings" via the scene manager client.
// This is a high-level scene-side refresh path, so keep it gated/explicit.
static void recallCurrentSettingsViaSceneClient() {
    if (!g_sceneClient) {
        fprintf(stderr, "[MC] recallCurrentSettingsViaSceneClient: no scene client!\n");
        return;
    }
    typedef void (*fn_RecallCurrentSettings)(void* client);
    auto recallCurrentSettings = (fn_RecallCurrentSettings)RESOLVE(0x10071e5b0);
    recallCurrentSettings(g_sceneClient);
    fprintf(stderr, "[MC] recallCurrentSettingsViaSceneClient: RecallCurrentSettings() called\n");
}

// Emit the client-side "current settings recalled" Qt signal without forcing
// another backend recall. This is intended as a UI refresh experiment only.
static void emitSceneCurrentSettingsRecalledSignal() {
    if (!g_sceneClient) {
        fprintf(stderr, "[MC] emitSceneCurrentSettingsRecalledSignal: no scene client!\n");
        return;
    }
    typedef void (*fn_SceneCurrentSettingsRecalled)(void* client);
    auto emitSignal = (fn_SceneCurrentSettingsRecalled)RESOLVE(0x100368070);
    emitSignal(g_sceneClient);
    fprintf(stderr, "[MC] emitSceneCurrentSettingsRecalledSignal: SceneCurrentSettingsRecalled() emitted\n");
}

static bool isChannelStereo(int ch);
static void waitForStereoConfigReset();
static bool readStereoConfig(uint8_t config[64]);
static bool writeStereoConfig(const uint8_t config[64]);
static bool isInsertStatusProc(int procIdx);

static void waitForSceneRecall() {
    int settleMs = 8000;
    if (const char* env = getenv("MC_AUTOTEST_SHOW_SETTLE_MS")) {
        int parsed = atoi(env);
        if (parsed > 0)
            settleMs = parsed;
    }
    fprintf(stderr, "[MC][AUTOTEST] waitForSceneRecall: settling for %d ms\n", settleMs);
    int waited = 0;
    while (waited < settleMs) {
        QApplication::processEvents();
        usleep(500 * 1000);
        waited += 500;
    }
    QApplication::processEvents();
}

static bool waitForShowRecallComplete() {
    int timeoutMs = 15000;
    uint64_t startMs = monotonicMs();
    if (const char* env = getenv("MC_AUTOTEST_SHOW_SETTLE_MS")) {
        int parsed = atoi(env);
        if (parsed > 0)
            timeoutMs = parsed;
    }
    int extraSettleMs = 1500;
    if (const char* env = getenv("MC_AUTOTEST_POST_SHOW_SETTLE_MS")) {
        int parsed = atoi(env);
        if (parsed >= 0)
            extraSettleMs = parsed;
    }

    QObject* sender = reinterpret_cast<QObject*>(getShowManagerClientForCalls());
    if (!sender) {
        fprintf(stderr,
                "[MC][AUTOTEST] waitForShowRecallComplete: no show manager client, "
                "falling back to timed settle\n");
        waitForSceneRecall();
        return false;
    }

    QEventLoop loop;
    QTimer timeoutTimer;
    timeoutTimer.setSingleShot(true);
    QObject::connect(&timeoutTimer, &QTimer::timeout, &loop, &QEventLoop::quit);

    bool hookedShowRecalled =
        QObject::connect(sender, SIGNAL(ShowRecalled(QString)), &loop, SLOT(quit()));
    bool hookedShowRecallComplete =
        QObject::connect(sender,
                         SIGNAL(ShowRecallComplete(eShowRecallCompleteResult)),
                         &loop,
                         SLOT(quit()));

    fprintf(stderr,
            "[MC][AUTOTEST] waitForShowRecallComplete: timeout=%dms "
            "hookedShowRecalled=%d hookedShowRecallComplete=%d\n",
            timeoutMs,
            hookedShowRecalled ? 1 : 0,
            hookedShowRecallComplete ? 1 : 0);

    if (!hookedShowRecalled && !hookedShowRecallComplete) {
        fprintf(stderr,
                "[MC][AUTOTEST] waitForShowRecallComplete: no usable show recall "
                "signals, falling back to timed settle\n");
        waitForSceneRecall();
        return false;
    }

    timeoutTimer.start(timeoutMs);
    loop.exec();
    bool signalObserved = timeoutTimer.isActive();
    if (signalObserved)
        timeoutTimer.stop();

    QObject::disconnect(sender, nullptr, &loop, nullptr);
    QApplication::processEvents();

    if (extraSettleMs > 0) {
        fprintf(stderr,
                "[MC][AUTOTEST] waitForShowRecallComplete: post-signal settle %d ms\n",
                extraSettleMs);
        int waited = 0;
        while (waited < extraSettleMs) {
            QApplication::processEvents();
            usleep(100 * 1000);
            waited += 100;
        }
        QApplication::processEvents();
    }

    fprintf(stderr,
            "[MC][AUTOTEST] waitForShowRecallComplete: %s\n",
            signalObserved ? "signal observed" : "timed out");
    logAutotestTiming("wait_show_recall_complete_ms",
                      monotonicMs() - startMs,
                      signalObserved ? "signal_observed" : "timed_out");
    return signalObserved;
}

static bool waitForCurrentSettingsStored() {
    int timeoutMs = 10000;
    uint64_t startMs = monotonicMs();
    QObject* sender = reinterpret_cast<QObject*>(g_sceneClient);
    if (!sender) {
        fprintf(stderr,
                "[MC][AUTOTEST] waitForCurrentSettingsStored: no scene client\n");
        return false;
    }

    QEventLoop loop;
    QTimer timeoutTimer;
    timeoutTimer.setSingleShot(true);
    QObject::connect(&timeoutTimer, &QTimer::timeout, &loop, &QEventLoop::quit);

    bool hooked =
        QObject::connect(sender, SIGNAL(CurrentSettingsStored()), &loop, SLOT(quit()));
    fprintf(stderr,
            "[MC][AUTOTEST] waitForCurrentSettingsStored: timeout=%dms hooked=%d\n",
            timeoutMs,
            hooked ? 1 : 0);
    if (!hooked)
        return false;

    timeoutTimer.start(timeoutMs);
    loop.exec();
    bool signalObserved = timeoutTimer.isActive();
    if (signalObserved)
        timeoutTimer.stop();
    QObject::disconnect(sender, nullptr, &loop, nullptr);
    QApplication::processEvents();
    fprintf(stderr,
            "[MC][AUTOTEST] waitForCurrentSettingsStored: %s\n",
            signalObserved ? "signal observed" : "timed out");
    logAutotestTiming("wait_current_settings_stored_ms",
                      monotonicMs() - startMs,
                      signalObserved ? "signal_observed" : "timed_out");
    return signalObserved;
}

static bool waitForShowArchived() {
    int timeoutMs = 20000;
    uint64_t startMs = monotonicMs();
    QObject* sender = reinterpret_cast<QObject*>(getShowManagerClientForCalls());
    if (!sender) {
        fprintf(stderr,
                "[MC][AUTOTEST] waitForShowArchived: no show manager client\n");
        return false;
    }

    QEventLoop loop;
    QTimer timeoutTimer;
    timeoutTimer.setSingleShot(true);
    QObject::connect(&timeoutTimer, &QTimer::timeout, &loop, &QEventLoop::quit);

    bool hooked =
        QObject::connect(sender, SIGNAL(ShowArchived(eShowArchiveCompleteResult)), &loop, SLOT(quit()));
    fprintf(stderr,
            "[MC][AUTOTEST] waitForShowArchived: timeout=%dms hooked=%d\n",
            timeoutMs,
            hooked ? 1 : 0);
    if (!hooked)
        return false;

    timeoutTimer.start(timeoutMs);
    loop.exec();
    bool signalObserved = timeoutTimer.isActive();
    if (signalObserved)
        timeoutTimer.stop();
    QObject::disconnect(sender, nullptr, &loop, nullptr);
    QApplication::processEvents();
    fprintf(stderr,
            "[MC][AUTOTEST] waitForShowArchived: %s\n",
            signalObserved ? "signal observed" : "timed out");
    logAutotestTiming("wait_show_archived_ms",
                      monotonicMs() - startMs,
                      signalObserved ? "signal_observed" : "timed_out");
    return signalObserved;
}

static bool storeCurrentSettingsViaSceneClient() {
    typedef void (*fn_StoreCurrentSettings)(void* client);
    auto storeCurrentSettings = (fn_StoreCurrentSettings)RESOLVE(0x10071e5a0);
    if (!g_sceneClient || !storeCurrentSettings) {
        fprintf(stderr,
                "[MC][SHOWSAVE] scene current-settings store path unavailable\n");
        return false;
    }
    storeCurrentSettings(g_sceneClient);
    fprintf(stderr, "[MC][SHOWSAVE] StoreCurrentSettings() called\n");
    return true;
}

static QString makeRoundtripShowName(const QString& rawName) {
    QString cleaned = rawName.trimmed();
    if (cleaned.isEmpty())
        cleaned = "MCAUTO";
    QString out;
    out.reserve(cleaned.size());
    for (QChar ch : cleaned) {
        if (ch.isLetterOrNumber() || ch == '_' || ch == '-')
            out.append(ch.toUpper());
    }
    if (out.isEmpty())
        out = "MCAUTO";
    if (out.size() > 16)
        out = out.left(16);
    return out;
}

static bool saveAndRecallAutotestShowRoundtrip(const QString& requestedName,
                                               int selectCh,
                                               const char* logPrefix) {
    uint64_t roundtripStartMs = monotonicMs();
    QString showName = makeRoundtripShowName(requestedName);
    if (showName != requestedName.trimmed()) {
        fprintf(stderr,
                "%sroundtrip show name normalized '%s' -> '%s'\n",
                logPrefix ? logPrefix : "",
                requestedName.toUtf8().constData(),
                showName.toUtf8().constData());
    }

    updateAutotestOverlay("dLive Self-Test",
                          QString("Storing current settings for %1").arg(showName));
    uint64_t storeStageMs = monotonicMs();
    if (!storeCurrentSettingsViaSceneClient())
        return false;
    if (!waitForCurrentSettingsStored()) {
        fprintf(stderr,
                "%swaitForCurrentSettingsStored failed during roundtrip\n",
                logPrefix ? logPrefix : "");
        return false;
    }
    logAutotestTiming("roundtrip_store_current_settings_ms",
                      monotonicMs() - storeStageMs,
                      showName.toUtf8().constData());

    updateAutotestOverlay("dLive Self-Test",
                          QString("Saving reordered SHOW %1").arg(showName));
    uint64_t saveStageMs = monotonicMs();
    if (!createShowViaShowManagerClient(showName)) {
        fprintf(stderr,
                "%screateShowViaShowManagerClient failed during roundtrip\n",
                logPrefix ? logPrefix : "");
        return false;
    }
    if (!waitForShowArchived()) {
        fprintf(stderr,
                "%swaitForShowArchived failed during roundtrip\n",
                logPrefix ? logPrefix : "");
        return false;
    }
    logAutotestTiming("roundtrip_archive_show_ms",
                      monotonicMs() - saveStageMs,
                      showName.toUtf8().constData());

    // Give Director a brief moment to register the new show in the user list.
    QElapsedTimer settle;
    settle.start();
    while (settle.elapsed() < 1200) {
        QApplication::processEvents();
        QThread::msleep(50);
    }

    updateAutotestOverlay("dLive Self-Test",
                          QString("Recalling reordered SHOW %1").arg(showName));
    uint64_t recallStageMs = monotonicMs();
    bool recalled = false;
    QElapsedTimer recallTimer;
    recallTimer.start();
    while (recallTimer.elapsed() < 12000) {
        if (recallShowByName(showName)) {
            recalled = true;
            break;
        }
        QApplication::processEvents();
        QThread::msleep(250);
    }
    if (!recalled) {
        fprintf(stderr,
                "%sfailed to recall roundtrip show '%s'\n",
                logPrefix ? logPrefix : "",
                showName.toUtf8().constData());
        return false;
    }
    if (!waitForShowRecallComplete()) {
        fprintf(stderr,
                "%swaitForShowRecallComplete failed during roundtrip\n",
                logPrefix ? logPrefix : "");
        return false;
    }
    logAutotestTiming("roundtrip_recall_saved_show_ms",
                      monotonicMs() - recallStageMs,
                      showName.toUtf8().constData());

    if (selectCh >= 0) {
        updateAutotestOverlay("dLive Self-Test",
                              QString("Selecting channel %1 after rerecall").arg(selectCh + 1));
        selectInputChannelForUI(selectCh, logPrefix ? logPrefix : "[MC][AUTOTEST] ");
    }
    logAutotestTiming("roundtrip_total_ms",
                      monotonicMs() - roundtripStartMs,
                      showName.toUtf8().constData());
    fprintf(stderr,
            "%sroundtrip save+recall complete for '%s'\n",
            logPrefix ? logPrefix : "",
            showName.toUtf8().constData());
    return true;
}

static bool maybeRecallAutotestShow() {
    const char* showEnv = getenv("MC_AUTOTEST_RECALL_SHOW");
    if (!showEnv || !*showEnv)
        return true;
    QString showName = QString::fromUtf8(showEnv).trimmed();
    if (showName.isEmpty())
        return true;
    updateAutotestOverlay("dLive Self-Test",
                          QString("Recalling SHOW %1").arg(showName));
    fprintf(stderr, "[MC][AUTOTEST] recalling SHOW '%s' before scenario\n",
            showName.toUtf8().constData());
    uint64_t startMs = monotonicMs();
    if (!recallShowByName(showName)) {
        updateAutotestOverlay("dLive Self-Test",
                              QString("Failed to recall SHOW %1").arg(showName));
        fprintf(stderr, "[MC][AUTOTEST] failed to recall SHOW '%s'\n",
                showName.toUtf8().constData());
        return false;
    }
    updateAutotestOverlay("dLive Self-Test",
                          QString("Waiting for SHOW %1 to settle").arg(showName));
    waitForShowRecallComplete();
    updateAutotestOverlay("dLive Self-Test",
                          QString("SHOW %1 recalled").arg(showName));
    logAutotestTiming("baseline_show_recall_ms",
                      monotonicMs() - startMs,
                      showName.toUtf8().constData());
    fprintf(stderr, "[MC][AUTOTEST] SHOW '%s' recall wait complete\n",
            showName.toUtf8().constData());
    return true;
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

static bool waitForInputConfigurationChangedSignal(QObject* sender,
                                                   int timeoutMs,
                                                   const char* tag) {
    if (!sender) {
        fprintf(stderr, "[MC] %s: no UIManagerHolder sender for InputConfigurationChanged(bool)\n", tag);
        return false;
    }

    uint64_t startMs = monotonicMs();
    QEventLoop loop;
    QTimer timeoutTimer;
    timeoutTimer.setSingleShot(true);
    QObject::connect(&timeoutTimer, &QTimer::timeout, &loop, &QEventLoop::quit);

    bool hooked =
        QObject::connect(sender, SIGNAL(InputConfigurationChanged(bool)), &loop, SLOT(quit()));
    fprintf(stderr,
            "[MC] %s: waitForInputConfigurationChangedSignal timeout=%dms hooked=%d\n",
            tag,
            timeoutMs,
            hooked ? 1 : 0);
    if (!hooked)
        return false;

    timeoutTimer.start(timeoutMs);
    loop.exec();
    bool signalObserved = timeoutTimer.isActive();
    if (signalObserved)
        timeoutTimer.stop();

    QObject::disconnect(sender, nullptr, &loop, nullptr);
    QApplication::processEvents();

    if (signalObserved) {
        g_lastStereoInputConfigSignalObserved = true;
        g_lastStereoInputConfigSignalMs = monotonicMs();
    }

    fprintf(stderr,
            "[MC] %s: InputConfigurationChanged(bool) %s after %llu ms\n",
            tag,
            signalObserved ? "observed" : "timed out",
            (unsigned long long)(monotonicMs() - startMs));
    return signalObserved;
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
    QObject* inputConfigSender = reinterpret_cast<QObject*>(g_uiManagerHolder);
    bool useSignalSettle = inputConfigSignalSettleEnabled() && inputConfigSender;
    g_lastStereoInputConfigSignalObserved = false;

    if (useSignalSettle) {
        uint64_t startMs = monotonicMs();
        QEventLoop loop;
        QTimer timeoutTimer;
        timeoutTimer.setSingleShot(true);
        QObject::connect(&timeoutTimer, &QTimer::timeout, &loop, &QEventLoop::quit);

        bool hooked =
            QObject::connect(inputConfigSender, SIGNAL(InputConfigurationChanged(bool)), &loop, SLOT(quit()));
        fprintf(stderr,
                "[MC] %s: event-settle enabled hooked=%d sender=%p\n",
                tag,
                hooked ? 1 : 0,
                inputConfigSender);
        if (hooked) {
            if (!sendStereoConfigViaDiscovery(config, tag)) {
                QObject::disconnect(inputConfigSender, nullptr, &loop, nullptr);
                fprintf(stderr, "[MC] %s: discovery stereo apply failed\n", tag);
                return false;
            }
            timeoutTimer.start(5000);
            loop.exec();
            bool signalObserved = timeoutTimer.isActive();
            if (signalObserved)
                timeoutTimer.stop();
            QObject::disconnect(inputConfigSender, nullptr, &loop, nullptr);
            QApplication::processEvents();
            if (signalObserved) {
                g_lastStereoInputConfigSignalObserved = true;
                g_lastStereoInputConfigSignalMs = monotonicMs();
                fprintf(stderr,
                        "[MC] %s: InputConfigurationChanged(bool) observed after %llu ms\n",
                        tag,
                        (unsigned long long)(g_lastStereoInputConfigSignalMs - startMs));
            } else {
                fprintf(stderr,
                        "[MC] %s: InputConfigurationChanged(bool) timed out after %llu ms\n",
                        tag,
                        (unsigned long long)(monotonicMs() - startMs));
            }
        } else {
            useSignalSettle = false;
        }
    }

    if (!useSignalSettle) {
        if (!sendStereoConfigViaDiscovery(config, tag)) {
            fprintf(stderr, "[MC] %s: discovery stereo apply failed\n", tag);
            return false;
        }
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

static void collectAssignedDyn8Units(std::set<int>& usedUnits) {
    usedUnits.clear();
    if (!g_channelManager) return;

    typedef void* (*fn_GetChannel)(void* mgr, uint32_t stripType, uint8_t chNum);
    auto getChannel = (fn_GetChannel)RESOLVE(0x1006e3f90);
    typedef bool (*fn_HasInserts)(void* channel, int insertPoint);
    auto hasInserts = (fn_HasInserts)RESOLVE(0x1006df5e0);
    typedef void* (*fn_GetInsertReturnPoint)(void* channel, int insertPoint);
    auto getReturnPoint = (fn_GetInsertReturnPoint)RESOLVE(0x1006d9850);
    typedef int (*fn_GetParentType)(void* sendPoint);
    auto getParentType = (fn_GetParentType)RESOLVE(0x1006cd690);
    if (!getChannel || !hasInserts || !getReturnPoint || !getParentType)
        return;

    for (int ch = 0; ch < 128; ch++) {
        void* cChannel = getChannel(g_channelManager, 1, (uint8_t)ch);
        if (!cChannel) continue;
        for (int ip = 0; ip < 2; ip++) {
            if (!hasInserts(cChannel, ip)) continue;
            void* returnPt = getReturnPoint(cChannel, ip);
            if (!returnPt) continue;
            void* connSendPt = nullptr;
            safeRead((uint8_t*)returnPt + 0x20, &connSendPt, sizeof(connSendPt));
            if (!connSendPt || getParentType(connSendPt) != 5) continue;
            int dynIdx = findDyn8UnitIdx(connSendPt);
            if (dynIdx >= 0)
                usedUnits.insert(dynIdx);
        }
    }
}

static int findFreeDyn8Unit(const std::set<int>& reservedUnits) {
    for (int unitIdx = 0; unitIdx < 64; unitIdx++) {
        if (reservedUnits.count(unitIdx))
            continue;
        if (!getDynNetObj(unitIdx))
            continue;
        if (!getDynUnitClient(unitIdx))
            continue;
        if (!getDyn8SendPointFromManager(unitIdx) || !getDyn8RecvPointFromManager(unitIdx))
            continue;
        return unitIdx;
    }
    return -1;
}

static int findFreeDyn8StereoPair(const std::set<int>& reservedUnits) {
    for (int unitIdx = 0; unitIdx < 63; unitIdx++) {
        if (reservedUnits.count(unitIdx) || reservedUnits.count(unitIdx + 1))
            continue;
        if (!getDynNetObj(unitIdx) || !getDynNetObj(unitIdx + 1))
            continue;
        if (!getDynUnitClient(unitIdx) || !getDynUnitClient(unitIdx + 1))
            continue;
        if (!getDyn8SendPointFromManager(unitIdx) || !getDyn8RecvPointFromManager(unitIdx))
            continue;
        if (!getDyn8SendPointFromManager(unitIdx + 1) || !getDyn8RecvPointFromManager(unitIdx + 1))
            continue;
        return unitIdx;
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

static bool isSelectedInputChannelMatch(const SelectedStripInfo& strip,
                                        int selectedInput,
                                        int targetCh) {
    if (selectedInput == targetCh)
        return true;
    if (strip.valid && strip.stripType == 1 && strip.channel == targetCh)
        return true;
    return false;
}

static bool selectInputChannelForUI(int ch, const char* phaseTag = nullptr) {
    if (ch < 0 || ch >= 128) {
        fprintf(stderr, "[MC] %sselectInputChannelForUI: invalid channel %d\n",
                phaseTag ? phaseTag : "", ch + 1);
        return false;
    }
    if (!g_uiManagerHolder) {
        fprintf(stderr, "[MC] %sselectInputChannelForUI: no UIManagerHolder\n",
                phaseTag ? phaseTag : "");
        return false;
    }
    void* inputCh = getInputChannel(ch);
    if (!inputCh) {
        fprintf(stderr, "[MC] %sselectInputChannelForUI: input channel %d not found\n",
                phaseTag ? phaseTag : "", ch + 1);
        return false;
    }
    typedef void (*fn_SetCurrentlySelectedChannel)(void* holder, void* channel);
    auto setCurrentlySelectedChannel = (fn_SetCurrentlySelectedChannel)RESOLVE(0x10076c070);
    typedef void (*fn_UIListenChangeChannel)(void* mgr, void* channel);
    auto uiListenChangeChannel = (fn_UIListenChangeChannel)RESOLVE(0x100370060);
    struct UIChannelStripKey {
        uint32_t stripType = 0;
        uint8_t channel = 0xFF;
        uint8_t pad[3] = {0, 0, 0};
    };
    typedef void (*fn_SelectChannelByKey)(void* listener, UIChannelStripKey key);
    auto selectChannelByKey = (fn_SelectChannelByKey)RESOLVE(0x10076bf50);
    if (!setCurrentlySelectedChannel) {
        fprintf(stderr, "[MC] %sselectInputChannelForUI: SetCurrentlySelectedChannel unavailable\n",
                phaseTag ? phaseTag : "");
        return false;
    }
    int keyStripType = 1;
    if (const char* stripEnv = getenv("MC_AUTOTEST_SELECT_KEY_STRIP"))
        keyStripType = atoi(stripEnv);
    int keyChannel = ch;
    if (const char* offsetEnv = getenv("MC_AUTOTEST_SELECT_KEY_CH_OFFSET"))
        keyChannel += atoi(offsetEnv);
    bool useSet = false;
    bool useListen = false;
    bool useListener = true;
    if (const char* setEnv = getenv("MC_AUTOTEST_SELECT_USE_SET"))
        useSet = (atoi(setEnv) != 0);
    if (const char* listenEnv = getenv("MC_AUTOTEST_SELECT_USE_LISTEN"))
        useListen = (atoi(listenEnv) != 0);
    if (const char* listenerEnv = getenv("MC_AUTOTEST_SELECT_USE_LISTENER"))
        useListener = (atoi(listenerEnv) != 0);
    fprintf(stderr,
            "[MC] %sselectInputChannelForUI: target=%d useSet=%d useListen=%d useListener=%d keyStripType=%d keyChannel=%d\n",
            phaseTag ? phaseTag : "",
            ch + 1, useSet ? 1 : 0, useListen ? 1 : 0, useListener ? 1 : 0,
            keyStripType, keyChannel + 1);
    UIChannelStripKey key;
    key.stripType = (uint32_t)std::max(0, keyStripType);
    key.channel = (uint8_t)std::max(0, std::min(255, keyChannel));

    auto issueSelection = [&]() {
        if (useSet) {
            fprintf(stderr, "[MC] %sselectInputChannelForUI: calling SetCurrentlySelectedChannel\n",
                    phaseTag ? phaseTag : "");
            setCurrentlySelectedChannel(g_uiManagerHolder, inputCh);
            fprintf(stderr, "[MC] %sselectInputChannelForUI: SetCurrentlySelectedChannel returned\n",
                    phaseTag ? phaseTag : "");
        }
        if (useListen && g_uiListenManager && uiListenChangeChannel) {
            fprintf(stderr, "[MC] %sselectInputChannelForUI: calling UIListenManager::ChangeChannel\n",
                    phaseTag ? phaseTag : "");
            uiListenChangeChannel(g_uiListenManager, inputCh);
            fprintf(stderr, "[MC] %sselectInputChannelForUI: UIListenManager::ChangeChannel returned\n",
                    phaseTag ? phaseTag : "");
        }
        if (useListener && g_uiChannelSelectListener && selectChannelByKey) {
            fprintf(stderr,
                    "[MC] %sselectInputChannelForUI: calling UIChannelSelectListener::SelectChannel(stripType=%u, channel=%u)\n",
                    phaseTag ? phaseTag : "",
                    key.stripType, (unsigned)key.channel);
            selectChannelByKey(g_uiChannelSelectListener, key);
            fprintf(stderr, "[MC] %sselectInputChannelForUI: UIChannelSelectListener::SelectChannel returned\n",
                    phaseTag ? phaseTag : "");
        }
        rememberSelectedInputChannel(ch);
    };

    issueSelection();

    SelectedStripInfo strip;
    int selectedInput = -1;
    bool matched = false;
    for (int attempt = 0; attempt < 10; attempt++) {
        QApplication::processEvents();
        usleep(350 * 1000);
        QApplication::processEvents();
        strip = getSelectedStripInfo(true);
        selectedInput = getSelectedInputChannel(true);
        matched = isSelectedInputChannelMatch(strip, selectedInput, ch);
        fprintf(stderr,
                "[MC] %sselectInputChannelForUI: poll attempt=%d stripValid=%d stripType=%u stripCh=%d selectedInput=%d matched=%d\n",
                phaseTag ? phaseTag : "",
                attempt,
                strip.valid ? 1 : 0,
                strip.valid ? strip.stripType : 0u,
                strip.valid ? strip.channel + 1 : -1,
                selectedInput >= 0 ? selectedInput + 1 : -1,
                matched ? 1 : 0);
        if (matched)
            break;
        if (attempt < 9)
            issueSelection();
    }

    fprintf(stderr,
            "[MC] %sselectInputChannelForUI: after select stripValid=%d stripType=%u stripCh=%d selectedInput=%d\n",
            phaseTag ? phaseTag : "",
            strip.valid ? 1 : 0,
            strip.valid ? strip.stripType : 0u,
            strip.valid ? strip.channel + 1 : -1,
            selectedInput >= 0 ? selectedInput + 1 : -1);
    fprintf(stderr, "[MC] %sselectInputChannelForUI: selected ch %d\n",
            phaseTag ? phaseTag : "", ch + 1);
    if (autotestEnvEnabled("MC_AUTOTEST_WEST_WRAPPER_RELINK")) {
        relinkWestPreampControlWrappers(phaseTag);
        QTimer::singleShot(150, qApp, []() {
            relinkWestPreampControlWrappers("[MC] (delayed 150ms) ");
        });
        QTimer::singleShot(600, qApp, []() {
            relinkWestPreampControlWrappers("[MC] (delayed 600ms) ");
        });
    }
    scheduleWestPreampGainPush(ch, phaseTag);
    if (autotestEnvEnabled("MC_AUTOTEST_WEST_REFRESH_AFTER_SELECT")) {
        refreshWestProcessingForChannel(ch, phaseTag);
        QTimer::singleShot(150, qApp, [ch]() { refreshWestProcessingForChannel(ch, "[MC] (delayed 150ms) "); });
        QTimer::singleShot(600, qApp, [ch]() { refreshWestProcessingForChannel(ch, "[MC] (delayed 600ms) "); });
    }
    return true;
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

    if (!applyStereoConfigAndRefresh(config, "[MC] changeStereoConfig")) {
        fprintf(stderr, "[MC] changeStereoConfig: failed to apply config via discovery\n");
        return false;
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

struct ActiveInputSourceData {
    sAudioSource source;
    bool         assigned;
    PreampData   preampData;
    bool         validPreamp;
};

static const char* preampSourceLabelText(char sourceLabel) {
    switch (sourceLabel) {
        case 'M': return "Main";
        case 'A': return "ABCD A";
        case 'B': return "ABCD B";
        case 'C': return "ABCD C";
        case 'D': return "ABCD D";
        default:  return "?";
    }
}

static void logPreampSocketClaim(const char* stage,
                                 uint32_t socketNum,
                                 char sourceLabel,
                                 int srcCh,
                                 int tgtCh,
                                 const sAudioSource& source,
                                 const PreampData& data,
                                 const char* extra = nullptr) {
    if (!stage)
        stage = "claim";
    if (srcCh == tgtCh) {
        fprintf(stderr,
                "[MC][PREAMP] %s socket %u: %s ch %d source={type=%u,num=%u} gain=%d pad=%d phantom=%d%s%s\n",
                stage,
                socketNum,
                preampSourceLabelText(sourceLabel),
                srcCh + 1,
                source.type, source.number,
                data.gain, data.pad, data.phantom,
                extra ? " " : "",
                extra ? extra : "");
    } else {
        fprintf(stderr,
                "[MC][PREAMP] %s socket %u: %s ch %d -> %d source={type=%u,num=%u} gain=%d pad=%d phantom=%d%s%s\n",
                stage,
                socketNum,
                preampSourceLabelText(sourceLabel),
                srcCh + 1, tgtCh + 1,
                source.type, source.number,
                data.gain, data.pad, data.phantom,
                extra ? " " : "",
                extra ? extra : "");
    }
}

static PreampData normalizedPreampDataForSource(const sAudioSource& source, PreampData pd);
static bool samePreampData(const PreampData& a, const PreampData& b) {
    return a.gain == b.gain && a.pad == b.pad && a.phantom == b.phantom;
}

static bool samePreampDataForSource(const sAudioSource& source,
                                    const PreampData& a,
                                    const PreampData& b) {
    return samePreampData(normalizedPreampDataForSource(source, a),
                          normalizedPreampDataForSource(source, b));
}

static bool isLocalAnaloguePatch(const PatchData& pd) {
    return pd.sourceType == 0 && pd.source.type == 0;
}

static bool patchDataUsesSocketBackedPreamp(const PatchData& pd);
static bool audioSourceIsMixRackIOPortPreamp(const sAudioSource& source);
static bool audioSourceHasMovablePreampState(const sAudioSource& source);
static bool audioSourceIsUnassigned(const sAudioSource& source);
static bool audioSourceSupportsPad(const sAudioSource& source);
static bool audioSourceSupportsPhantom(const sAudioSource& source);
static bool audioSourceNeedsDirectBoolPreampWrites(const sAudioSource& source);
static bool readPreampDataForAudioSource(const sAudioSource& source, PreampData& preamp);
static bool shouldShiftPatchedPreampForMove(const PatchData& pd,
                                            bool movePatchWithChannel,
                                            bool shiftMixRackIOPortWithMoveInScenarioA);
static bool shouldShiftSocketBackedPreampForMove(const sAudioSource& source,
                                                 bool movePatchWithChannel,
                                                 bool shiftMixRackIOPortWithMoveInScenarioA);
static bool getAnalogueSocketIndexForAudioSource(const sAudioSource& source, int& socketNum);

static void* getAnalogueInput(int socketNum) {
    if (!g_registryRouter || g_firstAnalogueInputIdx < 0 ||
        socketNum < 0 || socketNum > kMaxAnalogueInputSocket) return nullptr;
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
    if (padPtr) {
        uint8_t rawPad = 0;
        safeRead(padPtr, &rawPad, sizeof(rawPad));
        pd.pad = rawPad ? 1 : 0;
    }
    else pd.pad = 0;

    void* phantomPtr = nullptr;
    safeRead((uint8_t*)ai + 0xa8, &phantomPtr, sizeof(phantomPtr));
    if (phantomPtr) {
        uint8_t rawPhantom = 0;
        safeRead(phantomPtr, &rawPhantom, sizeof(rawPhantom));
        pd.phantom = rawPhantom ? 1 : 0;
    }
    else pd.phantom = 0;

    return true;
}

static bool readPreampDataForPatch(const PatchData& pd, PreampData& preamp) {
    int socketNum = -1;
    if (!patchDataUsesSocketBackedPreamp(pd) ||
        !getAnalogueSocketIndexForAudioSource(pd.source, socketNum))
        return false;
    return readPreampDataForSocket(socketNum, preamp);
}

static bool csvPreampExperimentEnabled() {
    return envFlagEnabled("MC_EXPERIMENT_CSV_PREAMP_GAIN");
}

static void* findLiveCsvImportPreampManager() {
    if (g_csvImportPreampManager)
        return g_csvImportPreampManager;
    if (!g_registryRouter)
        return nullptr;

    void* expectedVt = (void*)((uintptr_t)RESOLVE(0x106d248c0) + 16);
    uint8_t* base = (uint8_t*)g_registryRouter + 0x3a9820;
    for (int i = 0; i < 10000; ++i) {
        void* entry = nullptr;
        if (!safeRead(base + i * 8, &entry, sizeof(entry)))
            continue;
        if (!entry || (uintptr_t)entry < 0x100000000ULL)
            continue;
        void* vt = nullptr;
        if (!safeRead(entry, &vt, sizeof(vt)))
            continue;
        if (vt == expectedVt) {
            g_csvImportPreampManager = entry;
            fprintf(stderr,
                    "[MC][CSVPREAMP] found live manager at registry idx %d obj=%p\n",
                    i,
                    entry);
            return entry;
        }
    }

    fprintf(stderr, "[MC][CSVPREAMP] live manager not found in RegistryRouter\n");
    return nullptr;
}

static void* ensureCsvImportPreampManager() {
    return findLiveCsvImportPreampManager();
}

static bool writePreampDataViaCsvImport(const sAudioSource& source,
                                        const PreampData& preamp,
                                        const char* phaseTag) {
    typedef uint32_t (*fn_SourceTypeToSocketLocation)(uint32_t, uint32_t*);
    typedef uint16_t (*fn_GainToUWORD)(int16_t);
    typedef void (*fn_CsvImportPreampReset)(void*);
    typedef void* (*fn_CsvImportPreampInsert)(void*, uint32_t, uint16_t, uint16_t, uint32_t, uint32_t);
    typedef void (*fn_CsvImportPreampStartSeeking)(void*, bool);

    void* mgr = ensureCsvImportPreampManager();
    auto sourceTypeToSocketLocation =
        (fn_SourceTypeToSocketLocation)RESOLVE(0x100f5bc70);
    auto gainToUword = (fn_GainToUWORD)RESOLVE(0x100105fa0);
    auto reset = (fn_CsvImportPreampReset)RESOLVE(0x10108c040);
    auto insertPreamp = (fn_CsvImportPreampInsert)RESOLVE(0x10108c940);
    auto startSeeking = (fn_CsvImportPreampStartSeeking)RESOLVE(0x10108bf50);
    if (!mgr || !sourceTypeToSocketLocation || !gainToUword || !reset ||
        !insertPreamp || !startSeeking) {
        fprintf(stderr,
                "[MC][CSVPREAMP] %s unavailable mgr=%p map=%p gainToUword=%p reset=%p insert=%p start=%p\n",
                phaseTag ? phaseTag : "",
                mgr,
                (void*)sourceTypeToSocketLocation,
                (void*)gainToUword,
                (void*)reset,
                (void*)insertPreamp,
                (void*)startSeeking);
        return false;
    }

    uint32_t localSocket = source.number;
    uint32_t location = sourceTypeToSocketLocation(source.type, &localSocket);
    if (location == 0x0fU) {
        fprintf(stderr,
                "[MC][CSVPREAMP] %s invalid socket location for source {type=%u,num=%u}\n",
                phaseTag ? phaseTag : "",
                source.type, source.number);
        return false;
    }

    uint16_t gainWord = gainToUword((int16_t)preamp.gain);
    uint32_t padState = audioSourceSupportsPad(source) ? (preamp.pad ? 1U : 0U) : 2U;
    uint32_t phantomState = audioSourceSupportsPhantom(source) ? (preamp.phantom ? 1U : 0U) : 2U;

    fprintf(stderr,
            "[MC][CSVPREAMP] %s queue source={type=%u,num=%u} location=%u localSocket=%u gain=%d gainWord=%u pad=%u phantom=%u\n",
            phaseTag ? phaseTag : "",
            source.type, source.number,
            location, localSocket,
            preamp.gain, (unsigned)gainWord,
            padState, phantomState);

    reset(mgr);
    insertPreamp(mgr,
                 location,
                 (uint16_t)localSocket,
                 gainWord,
                 padState,
                 phantomState);
    if (!g_csvPreampQueue) {
        g_csvPreampQueue = dispatch_queue_create("mc.csv-preamp", DISPATCH_QUEUE_SERIAL);
    }

    __block bool workerFinished = false;
    __block uint64_t workerStartMs = monotonicMs();
    dispatch_async(g_csvPreampQueue, ^{
        fprintf(stderr,
                "[MC][CSVPREAMP] %s worker start source={type=%u,num=%u}\n",
                phaseTag ? phaseTag : "",
                source.type, source.number);
        startSeeking(mgr, true);
        workerFinished = true;
        fprintf(stderr,
                "[MC][CSVPREAMP] %s worker done source={type=%u,num=%u} duration=%llums\n",
                phaseTag ? phaseTag : "",
                source.type, source.number,
                (unsigned long long)(monotonicMs() - workerStartMs));
    });

    for (int attempt = 0; attempt < 60; ++attempt) {
        QApplication::processEvents();
        usleep(25 * 1000);
        QApplication::processEvents();

        PreampData readback = {};
        if (!readPreampDataForAudioSource(source, readback))
            continue;

        bool gainOk = readback.gain == preamp.gain;
        bool padOk = !audioSourceSupportsPad(source) || readback.pad == preamp.pad;
        bool phantomOk = !audioSourceSupportsPhantom(source) || readback.phantom == preamp.phantom;
        fprintf(stderr,
                "[MC][CSVPREAMP] %s readback attempt=%d source={type=%u,num=%u} gain=%d pad=%d phantom=%d match=%d/%d/%d\n",
                phaseTag ? phaseTag : "",
                attempt + 1,
                source.type, source.number,
                readback.gain, readback.pad, readback.phantom,
                gainOk ? 1 : 0,
                padOk ? 1 : 0,
                phantomOk ? 1 : 0);
        if (gainOk && padOk && phantomOk) {
            fprintf(stderr,
                    "[MC][CSVPREAMP] %s success workerFinished=%d attempts=%d\n",
                    phaseTag ? phaseTag : "",
                    workerFinished ? 1 : 0,
                    attempt + 1);
            return true;
        }
    }

    fprintf(stderr,
            "[MC][CSVPREAMP] %s timeout workerFinished=%d source={type=%u,num=%u}\n",
            phaseTag ? phaseTag : "",
            workerFinished ? 1 : 0,
            source.type, source.number);

    return false;
}

static bool writePreampDataForSocket(int socketNum, const PreampData& pd,
                                     bool directBoolWrites = false,
                                     bool writeBoolState = true) {
    void* ai = getAnalogueInput(socketNum);
    if (!ai) return false;

    // Use MIDISetGain / MIDISetPad / MIDISetPhantomPower for proper notification
    typedef void (*fn_MIDISetGain)(void*, int16_t);
    typedef void (*fn_MIDISetPad)(void*, bool);
    typedef void (*fn_MIDISetPhantom)(void*, bool);
    typedef int (*fn_SetStatus)(void*, int16_t*, bool*, bool*, void*, bool, int);
    typedef void (*fn_InformOtherObjects)(void*, const void*);
    typedef void (*fn_SetLength)(void*, uint32_t);
    typedef void (*fn_SetSWORD)(void*, int16_t, uint32_t);
    typedef void (*fn_SetUBYTE)(void*, uint8_t, uint32_t);

    auto midiSetGain = (fn_MIDISetGain)RESOLVE(0x1004ecf80);
    auto midiSetPad = (fn_MIDISetPad)RESOLVE(0x1004ed020);
    auto midiSetPhantom = (fn_MIDISetPhantom)RESOLVE(0x1004ed0a0);
    auto setStatus = (fn_SetStatus)RESOLVE(0x1004ed410);
    auto informOthers = (fn_InformOtherObjects)RESOLVE(0x1000eb020);
    auto setLen = (fn_SetLength)RESOLVE(0x1000e9ee0);
    auto setSWord = (fn_SetSWORD)RESOLVE(0x1000eb000);
    auto setUByte = (fn_SetUBYTE)RESOLVE(0x1000ebde0);

    fprintf(stderr,
            "[MC]     Preamp write begin socket %d ai=%p gain=%d pad=%d phantom=%d\n",
            socketNum, ai, pd.gain, pd.pad, pd.phantom);
    midiSetGain(ai, pd.gain);
    fprintf(stderr, "[MC]     Preamp write socket %d: gain applied\n", socketNum);
    if (!writeBoolState) {
        fprintf(stderr,
                "[MC]     Preamp write socket %d: skipping pad/phantom for unsupported source\n",
                socketNum);
        return true;
    }
    if (directBoolWrites) {
        void* embMsg = (uint8_t*)ai + 0x60;
        if (setStatus && setLen && setSWord && setUByte) {
            int16_t wantGain = pd.gain;
            bool wantPad = pd.pad != 0;
            bool wantPhantom = pd.phantom != 0;
            setLen(embMsg, 5);
            setUByte(embMsg, 1, 0);
            setSWord(embMsg, wantGain, 1);
            setUByte(embMsg, wantPad ? 1 : 0, 3);
            setUByte(embMsg, wantPhantom ? 1 : 0, 4);
            int rc = setStatus(ai, &wantGain, &wantPad, &wantPhantom, embMsg, false, 0);
            PreampData readback = {};
            if (rc != 0 &&
                readPreampDataForSocket(socketNum, readback) &&
                readback.gain == pd.gain &&
                readback.pad == pd.pad &&
                readback.phantom == pd.phantom) {
                fprintf(stderr,
                        "[MC]     Preamp write socket %d: gain/pad/phantom applied via SetStatus verified\n",
                        socketNum);
                return true;
            }
            fprintf(stderr,
                    "[MC]     Preamp write socket %d: SetStatus mismatch rc=%d want gain=%d pad=%d phantom=%d got gain=%d pad=%d phantom=%d, falling back to direct+inform\n",
                    socketNum, rc,
                    pd.gain, pd.pad, pd.phantom,
                    readback.gain, readback.pad, readback.phantom);
        }

        void* padPtr = nullptr;
        safeRead((uint8_t*)ai + 0xa0, &padPtr, sizeof(padPtr));
        if (padPtr) {
            uint8_t pad = pd.pad ? 1 : 0;
            safeWrite(padPtr, &pad, sizeof(pad));
        }

        void* phantomPtr = nullptr;
        safeRead((uint8_t*)ai + 0xa8, &phantomPtr, sizeof(phantomPtr));
        if (phantomPtr) {
            uint8_t phantom = pd.phantom ? 1 : 0;
            safeWrite(phantomPtr, &phantom, sizeof(phantom));
        }

        uint8_t type5 = 0x5;
        uint16_t hdr10 = 0xFFFF;
        uint32_t hdr14 = 0xFFFFFFFF;
        safeWrite((uint8_t*)ai + 0x84, &type5, sizeof(type5));
        safeWrite((uint8_t*)ai + 0x70, &hdr10, sizeof(hdr10));
        safeWrite((uint8_t*)ai + 0x74, &hdr14, sizeof(hdr14));

        auto sendBoolUpdate = [&](uint64_t opcode, uint8_t value) {
            if (!informOthers || !setLen || !setUByte)
                return;
            safeWrite((uint8_t*)ai + 0x7c, &opcode, sizeof(opcode));
            setLen(embMsg, 1);
            setUByte(embMsg, value ? 1 : 0, 0);
            informOthers(ai, embMsg);
        };

        sendBoolUpdate(0x100001004ULL, pd.pad ? 1 : 0);
        sendBoolUpdate(0x100001003ULL, pd.phantom ? 1 : 0);

        PreampData readback = {};
        if (readPreampDataForSocket(socketNum, readback) &&
            readback.pad == pd.pad &&
            readback.phantom == pd.phantom) {
            fprintf(stderr,
                    "[MC]     Preamp write socket %d: pad/phantom applied (direct+inform verified)\n",
                    socketNum);
        } else {
            fprintf(stderr,
                    "[MC]     Preamp write socket %d: direct+inform readback mismatch want pad=%d phantom=%d got pad=%d phantom=%d\n",
                    socketNum,
                    pd.pad, pd.phantom,
                    readback.pad, readback.phantom);
        }
    } else {
        midiSetPad(ai, pd.pad != 0);
        fprintf(stderr, "[MC]     Preamp write socket %d: pad applied\n", socketNum);
        midiSetPhantom(ai, pd.phantom != 0);
        fprintf(stderr, "[MC]     Preamp write socket %d: phantom applied\n", socketNum);
    }

    PreampData finalReadback = {};
    if (readPreampDataForSocket(socketNum, finalReadback)) {
        fprintf(stderr,
                "[MC][PREAMP] write socket %d readback: gain=%d pad=%d phantom=%d\n",
                socketNum,
                finalReadback.gain, finalReadback.pad, finalReadback.phantom);
    } else {
        fprintf(stderr,
                "[MC][PREAMP] write socket %d readback failed\n",
                socketNum);
    }

    return true;
}

static bool writePreampDataForPatch(const PatchData& pd, const PreampData& preamp) {
    int socketNum = -1;
    if (!patchDataUsesSocketBackedPreamp(pd) ||
        !getAnalogueSocketIndexForAudioSource(pd.source, socketNum))
        return false;
    if (csvPreampExperimentEnabled()) {
        if (writePreampDataViaCsvImport(pd.source, preamp, "[MC][CSVPREAMP] "))
            return true;
        fprintf(stderr,
                "[MC][CSVPREAMP] fallback to direct write for source {type=%u,num=%u} socket=%d\n",
                pd.source.type, pd.source.number, socketNum);
    }
    bool directBoolWrites = audioSourceNeedsDirectBoolPreampWrites(pd.source);
    bool writeBoolState = audioSourceSupportsPad(pd.source) || audioSourceSupportsPhantom(pd.source);
    return writePreampDataForSocket(socketNum, preamp, directBoolWrites, writeBoolState);
}

static bool isLocalAnalogueSource(const sAudioSource& source) {
    return source.type == 0;
}

static bool readNumSendPointsForType(uint32_t sourceType, uint16_t& count);
static bool getAnalogueSocketIndexForAudioSource(const sAudioSource& source, int& socketNum);

static bool getSendPointForAudioSource(const sAudioSource& source, void*& sendPt) {
    sendPt = nullptr;
    if (!g_audioSRPManager) return false;
    typedef void* (*fn_GetSendPoint)(void* mgr, uint32_t sourceType, uint16_t sourceNum);
    auto getSendPoint = (fn_GetSendPoint)RESOLVE(0x1006ce8e0);
    if (!getSendPoint) return false;
    sendPt = getSendPoint(g_audioSRPManager, source.type, (uint16_t)source.number);
    return sendPt != nullptr;
}

static void* getUnassignedInputSendPoint() {
    if (!g_audioSRPManager) return nullptr;
    void* sendPt = nullptr;
    safeRead((uint8_t*)g_audioSRPManager + 0x350, &sendPt, sizeof(sendPt));
    return sendPt;
}

static bool audioSourceIsSocketBackedPreamp(const sAudioSource& source) {
    void* sendPt = nullptr;
    if (!getSendPointForAudioSource(source, sendPt) || !sendPt)
        return false;
    typedef int (*fn_GetParentType)(void* sendPoint);
    auto getParentType = (fn_GetParentType)RESOLVE(0x1006cd690);
    return getParentType && getParentType(sendPt) == 3;
}

static bool patchDataUsesSocketBackedPreamp(const PatchData& pd) {
    return audioSourceHasMovablePreampState(pd.source);
}

static bool audioSourceIsMixRackIOPortPreamp(const sAudioSource& source) {
    // Observed live mappings:
    //   type 5 -> MixRack I/O Port preamp bank
    //   type 2 -> MixRack I/O Port preamp bank on the current live scenes
    // Keep both treated as "stick with channel" by default in Scenario A.
    return (source.type == kMixRackIOPortAudioSourceType || source.type == 2) &&
           audioSourceIsSocketBackedPreamp(source);
}

static bool audioSourceHasMovablePreampState(const sAudioSource& source) {
    return audioSourceIsSocketBackedPreamp(source) &&
           !audioSourceIsMixRackIOPortPreamp(source);
}

static bool audioSourceSupportsPhantom(const sAudioSource& source) {
    return audioSourceHasMovablePreampState(source);
}

static bool audioSourceSupportsPad(const sAudioSource& source) {
    return audioSourceHasMovablePreampState(source);
}

static PreampData normalizedPreampDataForSource(const sAudioSource& source, PreampData pd) {
    if (!audioSourceSupportsPad(source))
        pd.pad = 0;
    if (!audioSourceSupportsPhantom(source))
        pd.phantom = 0;
    return pd;
}

static bool audioSourceNeedsDirectBoolPreampWrites(const sAudioSource& source) {
    // Observed live issue: MixRack I/O Port preamp banks can hang in the
    // MIDISetPad / MIDISetPhantomPower path offline even when gain writes are fine.
    // Keep using the normal gain setter, but write pad/phantom directly.
    return audioSourceIsMixRackIOPortPreamp(source);
}

static bool shouldShiftPatchedPreampForMove(const PatchData& pd,
                                            bool movePatchWithChannel,
                                            bool shiftMixRackIOPortWithMoveInScenarioA) {
    if (movePatchWithChannel)
        return false;
    if (isLocalAnaloguePatch(pd))
        return true;
    if (audioSourceIsMixRackIOPortPreamp(pd.source))
        return shiftMixRackIOPortWithMoveInScenarioA;
    return false;
}

static bool shouldShiftSocketBackedPreampForMove(const sAudioSource& source,
                                                 bool movePatchWithChannel,
                                                 bool shiftMixRackIOPortWithMoveInScenarioA) {
    if (movePatchWithChannel || !audioSourceHasMovablePreampState(source))
        return false;
    if (audioSourceIsMixRackIOPortPreamp(source) &&
        !shiftMixRackIOPortWithMoveInScenarioA)
        return false;
    return true;
}

static bool shouldShiftAudioSourceForMove(const sAudioSource& source,
                                          bool movePatchWithChannel,
                                          bool shiftMixRackIOPortWithMoveInScenarioA) {
    if (movePatchWithChannel || !audioSourceIsSocketBackedPreamp(source))
        return false;
    if (audioSourceIsMixRackIOPortPreamp(source) &&
        !shiftMixRackIOPortWithMoveInScenarioA)
        return false;
    return true;
}

static bool shouldRestoreSocketBackedPreampForMove(const sAudioSource& source,
                                                   bool movePatchWithChannel,
                                                   bool shiftMixRackIOPortWithMoveInScenarioA) {
    if (!audioSourceHasMovablePreampState(source))
        return false;
    if (movePatchWithChannel)
        return true;
    return shouldShiftSocketBackedPreampForMove(source,
                                                movePatchWithChannel,
                                                shiftMixRackIOPortWithMoveInScenarioA);
}

static bool shouldRestorePatchedPreampForMove(const PatchData& pd,
                                              bool movePatchWithChannel,
                                              bool shiftMixRackIOPortWithMoveInScenarioA) {
    return shouldRestoreSocketBackedPreampForMove(pd.source,
                                                  movePatchWithChannel,
                                                  shiftMixRackIOPortWithMoveInScenarioA);
}

static bool getAnalogueSocketIndexForAudioSource(const sAudioSource& source, int& socketNum) {
    socketNum = -1;
    if (!audioSourceIsSocketBackedPreamp(source))
        return false;

    uint16_t count = 0;
    if (!readNumSendPointsForType(source.type, count) || source.number >= count)
        return false;

    // The nonlocal preamp banks are not laid out uniformly. The observed mapping so far is:
    //   type 0 -> zero-based
    //   odd nonzero types -> +1 offset
    //   even nonzero types -> zero-based
    socketNum = (int)source.type * 64 + (int)source.number;
    if ((source.type & 1U) != 0)
        socketNum += 1;
    if (socketNum < 0 || socketNum > kMaxAnalogueInputSocket) {
        socketNum = -1;
        return false;
    }
    return true;
}

static sAudioSource remapAudioSourceForMove(const sAudioSource& source, int srcCh, int tgtCh,
                                            bool movePatchWithChannel,
                                            bool shiftMixRackIOPortWithMoveInScenarioA) {
    if (!shouldShiftAudioSourceForMove(source, movePatchWithChannel,
                                       shiftMixRackIOPortWithMoveInScenarioA))
        return source;

    sAudioSource out = source;
    int delta = tgtCh - srcCh;
    int newNumber = (int)source.number + delta;
    uint16_t count = 0;
    if (!readNumSendPointsForType(source.type, count) || newNumber < 0 || newNumber >= count) {
        fprintf(stderr,
                "[MC]   WARN: active-input source remap {type=%u, num=%u} + delta %d is out of range for ch %d; keeping original\n",
                source.type,
                source.number, delta, tgtCh + 1);
        return out;
    }

    out.number = (uint32_t)newNumber;
    fprintf(stderr,
            "[MC]   Active-input remap srcCh %d -> tgtCh %d: source {type=%u, num=%u} -> {type=%u, num=%u}\n",
            srcCh + 1, tgtCh + 1,
            source.type, source.number,
            out.type, out.number);
    return out;
}

static bool readPreampDataForAudioSource(const sAudioSource& source, PreampData& preamp) {
    if (!audioSourceHasMovablePreampState(source))
        return false;
    int socketNum = -1;
    if (!getAnalogueSocketIndexForAudioSource(source, socketNum)) return false;
    return readPreampDataForSocket(socketNum, preamp);
}

static bool writePreampDataForAudioSource(const sAudioSource& source, const PreampData& preamp) {
    if (!audioSourceHasMovablePreampState(source))
        return false;
    int socketNum = -1;
    if (!getAnalogueSocketIndexForAudioSource(source, socketNum)) return false;
    bool directBoolWrites = audioSourceNeedsDirectBoolPreampWrites(source);
    bool writeBoolState = audioSourceSupportsPad(source) || audioSourceSupportsPhantom(source);
    return writePreampDataForSocket(socketNum, preamp, directBoolWrites, writeBoolState);
}

static void* getManagedInputChannel(int ch) {
    if (!g_channelManager || ch < 0 || ch > 127) return nullptr;
    typedef void* (*fn_GetChannel)(void* mgr, uint32_t stripType, uint8_t chNum);
    auto getChannel = (fn_GetChannel)RESOLVE(0x1006e3f90);
    return getChannel ? getChannel(g_channelManager, 1, (uint8_t)ch) : nullptr;
}

static void* getInputStripControl(int ch) {
    if (!g_surfaceChannels || ch < 0 || ch > 127) return nullptr;
    typedef void* (*fn_GetSurfaceChannel)(void* surfaceChannels, uint32_t stripType, uint8_t chNum);
    auto getSurfaceChannel = (fn_GetSurfaceChannel)RESOLVE(0x1048ea90);
    return getSurfaceChannel ? getSurfaceChannel(g_surfaceChannels, 1, (uint8_t)ch) : nullptr;
}

static bool readMuteGroupMaskForChannel(int ch, uint8_t& maskOut) {
    maskOut = 0;
    void* stripCtrl = getInputStripControl(ch);
    if (!stripCtrl) return false;

    typedef bool (*fn_GetMuteGroupAssign)(void* stripCtrl, uint8_t groupIdx);
    auto getMuteGroupAssign = (fn_GetMuteGroupAssign)RESOLVE(0x100331bd0);
    if (!getMuteGroupAssign) return false;

    for (int group = 0; group < kNumMuteGroups; group++) {
        if (getMuteGroupAssign(stripCtrl, (uint8_t)group))
            maskOut |= (uint8_t)(1u << group);
    }
    return true;
}

static void formatMuteGroupMaskSummary(uint8_t mask, char* out, size_t outSize) {
    if (!out || outSize == 0) return;
    out[0] = '\0';

    size_t len = 0;
    int count = 0;
    for (int group = 0; group < kNumMuteGroups; group++) {
        if ((mask & (uint8_t)(1u << group)) == 0) continue;
        int written = snprintf(out + len,
                               outSize - len,
                               "%s%d",
                               count ? "," : "",
                               group + 1);
        if (written <= 0) break;
        if ((size_t)written >= outSize - len) {
            len = outSize - 1;
            break;
        }
        len += (size_t)written;
        count++;
    }

    if (count == 0)
        snprintf(out, outSize, "-");
}

static std::map<void*, sAudioSource> g_sendPointSourceCache;
static bool g_sendPointSourceCacheBuilt = false;

static bool readNumSendPointsForType(uint32_t sourceType, uint16_t& count) {
    if (sourceType >= 0x2f) return false;
    const uint16_t* counts = (const uint16_t*)RESOLVE(0x1029851c0);
    return safeRead((const void*)(counts + sourceType), &count, sizeof(count));
}

static void buildSendPointSourceCache() {
    if (g_sendPointSourceCacheBuilt || !g_audioSRPManager) return;

    typedef void* (*fn_GetSendPoint)(void* mgr, uint32_t sourceType, uint16_t sourceNum);
    auto getSendPoint = (fn_GetSendPoint)RESOLVE(0x1006ce8e0);
    if (!getSendPoint) return;

    for (uint32_t sourceType = 0; sourceType < 0x2f; sourceType++) {
        uint16_t count = 0;
        if (!readNumSendPointsForType(sourceType, count))
            continue;
        for (uint16_t sourceNum = 0; sourceNum < count; sourceNum++) {
            void* sendPt = getSendPoint(g_audioSRPManager, sourceType, sourceNum);
            if (!sendPt) continue;
            g_sendPointSourceCache[sendPt] = {sourceType, sourceNum};
        }
    }

    g_sendPointSourceCacheBuilt = true;
    fprintf(stderr, "[MC] Built send-point source cache with %zu entries\n",
            g_sendPointSourceCache.size());
}

static bool resolveAudioSourceFromSendPoint(void* sendPt, sAudioSource& source) {
    if (!sendPt) return false;
    buildSendPointSourceCache();
    auto it = g_sendPointSourceCache.find(sendPt);
    if (it == g_sendPointSourceCache.end())
        return false;
    source = it->second;
    return true;
}

static bool resolveLocalAnalogueSourceFromSendPoint(void* sendPt, sAudioSource& source) {
    if (!sendPt || !g_audioSRPManager) return false;
    typedef void* (*fn_GetSendPoint)(void* mgr, uint32_t sourceType, uint16_t sourceNum);
    auto getSendPoint = (fn_GetSendPoint)RESOLVE(0x1006ce8e0);
    if (!getSendPoint) return false;

    uint16_t count = 0;
    if (!readNumSendPointsForType(0, count)) return false;
    for (uint16_t sourceNum = 0; sourceNum < count; sourceNum++) {
        void* localSendPt = getSendPoint(g_audioSRPManager, 0, sourceNum);
        if (localSendPt != sendPt) continue;
        source = {0, sourceNum};
        return true;
    }
    return false;
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

    // Mute-group membership (8 groups) via cChannelStripControl
    uint8_t    muteGroupMask;
    bool       validMuteGroups;

    // ABCD / redundant input-source setup
    uint8_t activeInputSource;
    bool    abcdEnabled;
    ActiveInputSourceData activeInputData[4];

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
    QApplication::processEvents();
    if (inputConfigSignalSettleEnabled() && g_lastStereoInputConfigSignalObserved) {
        uint64_t sinceSignalMs = monotonicMs() - g_lastStereoInputConfigSignalMs;
        fprintf(stderr,
                "[MC] waitForStereoConfigReset: using event-settle path (since signal %llu ms)\n",
                (unsigned long long)sinceSignalMs);
        for (int i = 0; i < 3; i++) {
            QCoreApplication::sendPostedEvents(nullptr, 0);
            QApplication::processEvents();
            usleep(10 * 1000);
        }
    } else {
        // Stereo reconfiguration rebuilds parts of the input-channel object graph
        // asynchronously. A short settle window avoids recalling into half-reset
        // objects, which can leave the right-hand channel of a former stereo pair
        // mirroring stale state from its neighbor.
        usleep(500 * 1000);
    }
    QApplication::processEvents();
}

static bool readSidechainRef(void* obj, uint8_t& stripType, uint8_t& channel) {
    if (!obj) return false;
    void* pStripType = nullptr;
    void* pChannel   = nullptr;
    safeRead((uint8_t*)obj + 0x138, &pStripType, sizeof(pStripType));
    safeRead((uint8_t*)obj + 0x140, &pChannel, sizeof(pChannel));
    if (!pStripType || !pChannel) return false;

    uint32_t st32 = 0;
    if (!safeRead((uint8_t*)pStripType, &st32, sizeof(st32))) return false;
    if (!safeRead((uint8_t*)pChannel, &channel, sizeof(channel))) return false;
    stripType = (uint8_t)st32;
    return true;
}

static bool readStereoImageState(void* obj, uint16_t& width, uint8_t& mode) {
    width = 0;
    mode = 0;
    if (!obj) return false;
    void* widthPtr = nullptr;
    void* modePtr = nullptr;
    safeRead((uint8_t*)obj + 0xA0, &widthPtr, sizeof(widthPtr));
    safeRead((uint8_t*)obj + 0xA8, &modePtr, sizeof(modePtr));
    if (!widthPtr || !modePtr) return false;
    if (!safeRead(widthPtr, &width, sizeof(width))) return false;
    if (!safeRead(modePtr, &mode, sizeof(mode))) return false;
    return true;
}

static void writeSidechainRef(void* obj, int procIdx, int ch,
                              uint8_t wantStripType, uint8_t wantChannel,
                              const char* phaseTag = nullptr) {
    if (!obj) return;

    typedef void (*fn_SetStatus)(void* obj, void* msg);
    typedef void (*fn_IdentifyAndRefresh)(void* obj);
    typedef void (*fn_InformOtherObjects)(void* obj, const void* msg);
    typedef void (*fn_SetLength)(void*, uint32_t);
    typedef void (*fn_SetUBYTE)(void*, uint8_t, uint32_t);

    auto setStatus = (fn_SetStatus)RESOLVE(0x1002e5690);
    auto identifyAndRefresh = (fn_IdentifyAndRefresh)RESOLVE(0x1002e4e80);
    auto informOthers = (fn_InformOtherObjects)RESOLVE(0x1000eb020);
    auto setLen = (fn_SetLength)RESOLVE(0x1000e9ee0);
    auto setUByte = (fn_SetUBYTE)RESOLVE(0x1000ebde0);

    void* embMsg = (uint8_t*)obj + 0x60;
    uint16_t hdr10 = 0xFFFF;
    uint32_t hdr14 = 0xFFFFFFFF;
    uint32_t hdr1c = 0x1000;
    safeWrite((uint8_t*)obj + 0x70, &hdr10, 2);
    safeWrite((uint8_t*)obj + 0x74, &hdr14, 4);
    safeWrite((uint8_t*)obj + 0x7c, &hdr1c, 4);

    if (setStatus && setLen && setUByte) {
        setLen(embMsg, 3);
        setUByte(embMsg, g_procB[procIdx].versionByte, 0);
        setUByte(embMsg, wantStripType, 1);
        setUByte(embMsg, wantChannel, 2);
        setStatus(obj, embMsg);
        if (identifyAndRefresh)
            identifyAndRefresh(obj);

        uint8_t gotStripType = 0;
        uint8_t gotChannel = 0;
        if (readSidechainRef(obj, gotStripType, gotChannel) &&
            gotStripType == wantStripType &&
            gotChannel == wantChannel) {
            fprintf(stderr, "[MC]   %s%s on ch %d: stripType=%d channel=%d via SetStatus verified\n",
                    phaseTag ? phaseTag : "",
                    g_procB[procIdx].name, ch + 1, wantStripType, wantChannel);
            return;
        }

        fprintf(stderr,
                "[MC]   %s%s on ch %d: SetStatus readback mismatch want={%d,%d} got={%d,%d}, falling back to raw path\n",
                phaseTag ? phaseTag : "",
                g_procB[procIdx].name, ch + 1,
                wantStripType, wantChannel,
                gotStripType, gotChannel);
    }

    if (setLen && setUByte) {
        setLen(embMsg, 2);
        setUByte(embMsg, wantStripType, 0);
        setUByte(embMsg, wantChannel, 1);
    }

    void* pStripType = nullptr;
    void* pChannel   = nullptr;
    safeRead((uint8_t*)obj + 0x138, &pStripType, sizeof(pStripType));
    safeRead((uint8_t*)obj + 0x140, &pChannel, sizeof(pChannel));
    if (pStripType && pChannel) {
        uint32_t st32 = wantStripType;
        safeWrite((uint8_t*)pStripType, &st32, sizeof(st32));
        safeWrite((uint8_t*)pChannel, &wantChannel, sizeof(wantChannel));
        safeWrite((uint8_t*)obj + 0x168, &st32, sizeof(st32));
        safeWrite((uint8_t*)obj + 0x16c, &wantChannel, sizeof(wantChannel));
        uint8_t one = 1;
        safeWrite((uint8_t*)obj + 0x174, &one, 1);
    }

    fprintf(stderr, "[MC]   %s%s on ch %d: stripType=%d channel=%d via raw path\n",
            phaseTag ? phaseTag : "",
            g_procB[procIdx].name, ch + 1, wantStripType, wantChannel);
    if (informOthers) informOthers(obj, embMsg);
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

static void formatMixerAssignmentSummary(const uint8_t* mixerData,
                                         bool& mainOn,
                                         bool& mainMonoOn,
                                         char* dcaList,
                                         size_t dcaListSize) {
    mainOn = false;
    mainMonoOn = false;
    if (!dcaList || dcaListSize == 0) return;

    dcaList[0] = '\0';
    if (!mixerData) {
        snprintf(dcaList, dcaListSize, "-");
        return;
    }

    mainOn = mixerData[0xA86] != 0;
    mainMonoOn = mixerData[0xA87] != 0;

    size_t dcaLen = 0;
    int dcaCount = 0;
    for (int dca = 0; dca < 32; dca++) {
        bool wantAssign = mixerData[0x001 + dca] != 0;
        if (!wantAssign) continue;
        int written = snprintf(dcaList + dcaLen,
                               dcaListSize - dcaLen,
                               "%s%d",
                               dcaCount ? "," : "",
                               dca + 1);
        if (written <= 0) break;
        if ((size_t)written >= dcaListSize - dcaLen) {
            dcaLen = dcaListSize - 1;
            break;
        }
        dcaLen += (size_t)written;
        dcaCount++;
    }
    if (dcaCount == 0)
        snprintf(dcaList, dcaListSize, "-");
}

static void formatMixerGroupSummary(const uint8_t* mixerData,
                                    char* groupList,
                                    size_t groupListSize) {
    if (!groupList || groupListSize == 0) return;
    groupList[0] = '\0';
    if (!mixerData) {
        snprintf(groupList, groupListSize, "-");
        return;
    }

    size_t groupLen = 0;
    int groupCount = 0;
    for (int group = 0; group < kMixerNumGroups; group++) {
        bool wantAssign = mixerData[kMixerGroupOnOffset + group] != 0;
        if (!wantAssign) continue;
        int written = snprintf(groupList + groupLen,
                               groupListSize - groupLen,
                               "%s%d",
                               groupCount ? "," : "",
                               group + 1);
        if (written <= 0) break;
        if ((size_t)written >= groupListSize - groupLen) {
            groupLen = groupListSize - 1;
            break;
        }
        groupLen += (size_t)written;
        groupCount++;
    }
    if (groupCount == 0)
        snprintf(groupList, groupListSize, "-");
}

static int16_t readMixerSWord(const uint8_t* mixerData, size_t offset) {
    int16_t value = 0;
    if (!mixerData) return 0;
    memcpy(&value, mixerData + offset, sizeof(value));
    return value;
}

static void logMixerAssignmentSummary(const char* phaseTag, int ch, const uint8_t* mixerData) {
    bool mainOn = false;
    bool mainMonoOn = false;
    char dcaList[160];
    char groupList[256];
    formatMixerAssignmentSummary(mixerData, mainOn, mainMonoOn, dcaList, sizeof(dcaList));
    formatMixerGroupSummary(mixerData, groupList, sizeof(groupList));
    fprintf(stderr,
            "[MC]   %s mixer assigns ch %d: mainOn=%d mainMonoOn=%d dcas=%s groups=%s\n",
            phaseTag ? phaseTag : "Mixer",
            ch + 1,
            mainOn ? 1 : 0,
            mainMonoOn ? 1 : 0,
            dcaList,
            groupList);
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
            logMixerAssignmentSummary("Snapshot", ch, snap.mixerData);
        } else {
            delete[] snap.mixerData;
            snap.mixerData = nullptr;
        }
    }
    snap.validMuteGroups = readMuteGroupMaskForChannel(ch, snap.muteGroupMask);
    if (snap.validMuteGroups) {
        char muteGroupList[64];
        formatMuteGroupMaskSummary(snap.muteGroupMask, muteGroupList, sizeof(muteGroupList));
        fprintf(stderr, "[MC]   Snapshot mute groups ch %d: %s\n", ch + 1, muteGroupList);
    }
    // Patching
    snap.validPatch = readPatchData(ch, snap.patchData);
    if (snap.validPatch)
        fprintf(stderr, "[MC]   Snapshot patch ch %d: srcType=%d src={type=%d, num=%d}\n",
                ch+1, snap.patchData.sourceType, snap.patchData.source.type, snap.patchData.source.number);

    // Preamp lives on the patched socket, not on the destination channel index.
    snap.validPreamp = snap.validPatch && readPreampDataForPatch(snap.patchData, snap.preampData);

    snap.activeInputSource = 0;
    snap.abcdEnabled = false;
    for (int i = 0; i < 4; i++) {
        snap.activeInputData[i].source = {0, 0};
        snap.activeInputData[i].assigned = false;
        snap.activeInputData[i].validPreamp = false;
        memset(&snap.activeInputData[i].preampData, 0, sizeof(PreampData));
    }

    if (void* cChannel = getManagedInputChannel(ch)) {
        typedef int (*fn_GetActiveInputSource)(void* channel);
        typedef bool (*fn_HasActiveInputSourceAssigned)(void* channel, int activeInputSource);
        typedef void* (*fn_GetInputChannelSource)(void* channel, int activeInputSource);

        auto getActiveInputSource = (fn_GetActiveInputSource)RESOLVE(0x1006d80d0);
        auto hasActiveInputSourceAssigned = (fn_HasActiveInputSourceAssigned)RESOLVE(0x1006df840);
        auto getInputChannelSource = (fn_GetInputChannelSource)RESOLVE(0x1006d81e0);

        if (getActiveInputSource)
            snap.activeInputSource = (uint8_t)getActiveInputSource(cChannel);
        snap.abcdEnabled = snap.activeInputSource != 0;

        for (int activeInputSource = 1; activeInputSource <= 4; activeInputSource++) {
            ActiveInputSourceData& aid = snap.activeInputData[activeInputSource - 1];
            if (!hasActiveInputSourceAssigned || !getInputChannelSource ||
                !hasActiveInputSourceAssigned(cChannel, activeInputSource)) {
                continue;
            }

            void* sendPt = getInputChannelSource(cChannel, activeInputSource);
            if (!sendPt) continue;
            bool resolved = resolveAudioSourceFromSendPoint(sendPt, aid.source);
            if (!resolved) {
                fprintf(stderr,
                        "[MC]   Snapshot ABCD ch %d source %d: unresolved send point %p\n",
                        ch + 1, activeInputSource, sendPt);
                continue;
            }

            aid.assigned = true;
            aid.validPreamp = readPreampDataForAudioSource(aid.source, aid.preampData);
            fprintf(stderr,
                    "[MC]   Snapshot ABCD ch %d source %d: type=%u num=%u preamp=%d\n",
                    ch + 1, activeInputSource,
                    aid.source.type, aid.source.number, aid.validPreamp ? 1 : 0);
        }
    }

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

static void replayStereoImageForChannel(int ch,
                                        const ChannelSnapshot& snap,
                                        const char* phaseTag);
static void replayMuteGroupsForChannel(int ch,
                                       const ChannelSnapshot& snap,
                                       const char* phaseTag);

static bool recallChannel(int ch, const ChannelSnapshot& snap, bool skipPreamp = false) {
    void* inputCh = getInputChannel(ch);
    if (!inputCh) { fprintf(stderr, "[MC] Ch %d: InputChannel is null!\n", ch); return false; }

    // Type A: DirectlyRecallStatus + ReportData
    recallTypeAForChannel(ch, snap);

    // Type B: write directly to object fields + call Refresh if available.

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
            writeSidechainRef(obj, p, ch, wantStripType, wantChannel, "SC-Write ");
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

        if (p == 2) {
            fprintf(stderr, "[MC]   Skip raw ProcOrder on ch %d; dedicated settle path will restore it\n",
                    ch + 1);
            continue;
        }

        // StereoImage: write raw fields + InformObjectsOfNewSettings for UI/runtime refresh
        if (strcmp(g_procB[p].name, "StereoImage") == 0) {
            replayStereoImageForChannel(ch, snap, "recall");
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
    replayMuteGroupsForChannel(ch, snap, "recall");

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
    bool customOrder;
    std::vector<std::pair<int, int>> targetMap;  // (target channel, snapshot index)
    std::array<int, 128> sourceToTarget;
    std::array<bool, 128> hasPatchOverride;
    std::array<PatchData, 128> patchOverride;

    MovePlan()
        : rawSrc(-1), rawDst(-1), srcStart(-1), dstStart(-1),
          blockSize(1), lo(-1), hi(-1), srcStereo(false), srcMonoBlock(false),
          customOrder(false) {
        for (int i = 0; i < 128; i++) {
            sourceToTarget[i] = i;
            hasPatchOverride[i] = false;
        }
    }
};

static void* getMsgDataPtr(uint8_t* msg);
static uint32_t getMsgLength(uint8_t* msg);
static void dumpChannelData(int ch, const char* label);
static std::function<void(const char*)> g_moveProgressCallback;
static bool buildMovePlan(int src, int dst, int requestedBlockSize,
                          MovePlan& plan, char* errBuf, size_t errBufLen);
static bool buildReorderPlan(const std::vector<int>& targetOrder,
                             MovePlan& plan, char* errBuf, size_t errBufLen);
static int remapChannelIndex(const MovePlan& plan, int ch);
static uint8_t remapMovedChannelRef(uint8_t oldRef, const MovePlan& plan);
static bool remapDyn8SideChainRef(uint8_t* dyn8Data, size_t dyn8Size,
                                  const MovePlan& plan,
                                  const char* phaseTag,
                                  int ownerCh,
                                  int unitIdx);
static GangStripKey makeGangStripKey(uint32_t stripType, uint8_t ch);
static bool readGangSnapshot(uint8_t gangNum, GangSnapshot& snap);
static bool gangSnapshotAffectsMove(const GangSnapshot& snap, const MovePlan& plan);
static QList<GangStripKey> buildGangMemberList(const GangSnapshot& snap, const MovePlan* plan);
static void applyGangMembershipHighLevel(void* driver,
                                         uint8_t gangNum,
                                         const QList<GangStripKey>& members,
                                         const char* phaseTag);
static void clearGangMembershipHighLevel(const GangSnapshot& snap, const char* phaseTag);
static void restoreGangMembershipHighLevel(const GangSnapshot& snap, const MovePlan* plan,
                                           const char* phaseTag);
static PatchData remapPatchDataForMove(const PatchData& pd, int srcCh, int tgtCh,
                                       bool shiftMixRackIOPortWithMoveInScenarioA);
static PatchData getTargetPatchDataForMove(const PatchData& pd, int srcCh, int tgtCh,
                                           bool movePatchWithChannel,
                                           bool shiftMixRackIOPortWithMoveInScenarioA);
static PatchData getEffectiveTargetPatchData(const MovePlan* plan,
                                             const PatchData& pd,
                                             int srcCh,
                                             int tgtCh,
                                             bool movePatchWithChannel,
                                             bool shiftMixRackIOPortWithMoveInScenarioA);
static bool moveChannel(int src, int dst, bool movePatchWithChannel,
                        bool shiftMixRackIOPortWithMoveInScenarioA,
                        int requestedBlockSize);
static bool captureCopiedInputSettings(int ch);
static bool pasteCopyBufferToInputStart(int dstStart);
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
        uint8_t stripType = 0;
        uint8_t channel = 0;
        if (readSidechainRef(scObj, stripType, channel)) {
            fprintf(stderr,
                    "[MC]   [%s] Readback %s on ch %d: stripType=%u channel=%u\n",
                    phaseTag, g_procB[p].name, ch + 1, stripType, channel);
        }
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

static void replayStereoImageForChannel(int ch,
                                        const ChannelSnapshot& snap,
                                        const char* phaseTag) {
    if (!snap.validB[kProcStereoImageIdx]) return;

    void* inputCh = getInputChannel(ch);
    if (!inputCh) return;
    void* obj = getTypeBObj(inputCh, g_procB[kProcStereoImageIdx]);
    if (!obj) return;

    uint16_t wantWidth = ((uint16_t)snap.dataB[kProcStereoImageIdx].buf[1] << 8) |
                         snap.dataB[kProcStereoImageIdx].buf[2];
    uint8_t wantMode = snap.dataB[kProcStereoImageIdx].buf[3];

    writeTypeBFields(obj, g_procB[kProcStereoImageIdx], snap.dataB[kProcStereoImageIdx].buf);

    typedef void (*fn_method_void)(void* obj);
    auto informNewSettings = (fn_method_void)RESOLVE(0x1002f5850);
    if (informNewSettings)
        informNewSettings(obj);

    uint16_t gotWidth = 0;
    uint8_t gotMode = 0;
    bool readbackOk = readStereoImageState(obj, gotWidth, gotMode);

    bool usingWrapperSync = false;
    if (g_inputMixerWrapper) {
        typedef void (*fn_WrapperSyncChannelCopy)(void* wrapper, uint8_t srcCh, uint8_t dstCh);
        auto wrapperSyncImageControl1 = (fn_WrapperSyncChannelCopy)RESOLVE(0x10029d600);
        auto wrapperSyncImageControl2 = (fn_WrapperSyncChannelCopy)RESOLVE(0x10029d6c0);
        if (wrapperSyncImageControl1 && wrapperSyncImageControl2) {
            wrapperSyncImageControl1(g_inputMixerWrapper, (uint8_t)ch, (uint8_t)ch);
            wrapperSyncImageControl2(g_inputMixerWrapper, (uint8_t)ch, (uint8_t)ch);
            usingWrapperSync = true;
        }
    }

    fprintf(stderr,
            "[MC]   [%s] Replay StereoImage on ch %d: width=%u mode=%u (syncPath=%s readback=%s width=%u mode=%u)\n",
            phaseTag ? phaseTag : "stereo-image",
            ch + 1, wantWidth, wantMode,
            usingWrapperSync ? "wrapper-sync" : "inform-only",
            readbackOk ? "ok" : "fail",
            gotWidth, gotMode);
}

static void replayMuteGroupsForChannel(int ch,
                                       const ChannelSnapshot& snap,
                                       const char* phaseTag) {
    if (!snap.validMuteGroups) return;

    void* stripCtrl = getInputStripControl(ch);
    if (!stripCtrl)
        return;

    typedef void (*fn_SetMuteGroupAssign)(void* stripCtrl, bool assign, uint8_t groupIdx);
    typedef bool (*fn_GetMuteGroupAssign)(void* stripCtrl, uint8_t groupIdx);
    auto setMuteGroupAssign = (fn_SetMuteGroupAssign)RESOLVE(0x100331be0);
    auto getMuteGroupAssign = (fn_GetMuteGroupAssign)RESOLVE(0x100331bd0);
    if (!setMuteGroupAssign || !getMuteGroupAssign) return;

    for (int group = 0; group < kNumMuteGroups; group++) {
        bool wantAssign = (snap.muteGroupMask & (uint8_t)(1u << group)) != 0;
        setMuteGroupAssign(stripCtrl, wantAssign, (uint8_t)group);
    }

    uint8_t gotMask = 0;
    for (int group = 0; group < kNumMuteGroups; group++) {
        if (getMuteGroupAssign(stripCtrl, (uint8_t)group))
            gotMask |= (uint8_t)(1u << group);
    }

    char wantList[64];
    char gotList[64];
    formatMuteGroupMaskSummary(snap.muteGroupMask, wantList, sizeof(wantList));
    formatMuteGroupMaskSummary(gotMask, gotList, sizeof(gotList));
    fprintf(stderr,
            "[MC]   [%s] Replay mute groups on ch %d: want=%s got=%s\n",
            phaseTag ? phaseTag : "mute-groups",
            ch + 1,
            wantList,
            gotList);
}

static void replayMixerStateForChannel(int ch,
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
    typedef void (*fn_WrapperMIDISetMainMute)(void* wrapper, uint8_t ch, bool mute, bool cacheMute);
    typedef void (*fn_WrapperMIDISetInputAuxOn)(void* wrapper,
                                                uint8_t ch,
                                                uint8_t aux,
                                                bool on,
                                                bool cacheOn);
    typedef void (*fn_WrapperMIDISetAuxGain)(void* wrapper,
                                             uint8_t ch,
                                             uint8_t aux,
                                             uint16_t gainWord,
                                             bool cacheGain);
    typedef void (*fn_SyncAuxPreSwitches)(void* mixer, uint8_t chInGrp, uint8_t aux, bool pre);
    typedef void (*fn_WrapperMIDISetInputMatrixOn)(void* wrapper,
                                                   uint8_t ch,
                                                   uint8_t matrix,
                                                   bool on,
                                                   bool cacheOn);
    typedef void (*fn_SyncMatrixPreSwitches)(void* mixer, uint8_t chInGrp, uint8_t matrix, bool pre);
    typedef void (*fn_SyncMatrixGains)(void* mixer, uint8_t chInGrp, uint8_t matrix, int16_t gain);
    typedef void (*fn_SetDCAGroupAssign)(void* mixer, uint8_t dca, uint8_t chInGrp, bool assign);
    typedef void (*fn_InformObjectsOfNewInDCAGroupSetting)(void* mixer, uint8_t dca, uint8_t chInGrp, bool assign);
    typedef void (*fn_WrapperSyncChannelCopy)(void* wrapper, uint8_t srcCh, uint8_t dstCh);
    typedef void (*fn_WrapperMIDISetDCAGroupAssign)(void* wrapper,
                                                    uint8_t dca,
                                                    uint8_t ch,
                                                    bool assign,
                                                    bool cacheAssign);

    auto setMainOnSwitch = (fn_SetMainOnSwitch)RESOLVE(0x100037e10);
    auto setMainMonoOnSwitch = (fn_SetMainMonoOnSwitch)RESOLVE(0x100037e70);
    auto informMainOnSetting = (fn_InformObjectsOfNewMainOnSetting)RESOLVE(0x10003faf0);
    auto informMainMonoOnSetting = (fn_InformObjectsOfNewMainMonoOnSetting)RESOLVE(0x10003fb60);
    auto wrapperSetMainMute = (fn_WrapperMIDISetMainMute)RESOLVE(0x10029cc20);
    auto wrapperSetInputAuxOn = (fn_WrapperMIDISetInputAuxOn)RESOLVE(0x10029c7f0);
    auto wrapperSetAuxGain = (fn_WrapperMIDISetAuxGain)RESOLVE(0x10029c8f0);
    auto syncAuxPreSwitches = (fn_SyncAuxPreSwitches)RESOLVE(0x100294d50);
    auto wrapperSetInputMatrixOn = (fn_WrapperMIDISetInputMatrixOn)RESOLVE(0x10029cd90);
    auto syncMatrixPreSwitches = (fn_SyncMatrixPreSwitches)RESOLVE(0x100294f40);
    auto syncMatrixGains = (fn_SyncMatrixGains)RESOLVE(0x100294f80);
    auto wrapperSyncImageControl1 = (fn_WrapperSyncChannelCopy)RESOLVE(0x10029d600);
    auto wrapperSyncImageControl2 = (fn_WrapperSyncChannelCopy)RESOLVE(0x10029d6c0);
    auto wrapperSyncAuxPans = (fn_WrapperSyncChannelCopy)RESOLVE(0x10029d840);
    auto wrapperSyncMatrixPans = (fn_WrapperSyncChannelCopy)RESOLVE(0x10029d960);
    auto setDCAGroupAssign = (fn_SetDCAGroupAssign)RESOLVE(0x100039c40);
    auto informInDCAGroupSetting = (fn_InformObjectsOfNewInDCAGroupSetting)RESOLVE(0x10003fee0);
    auto wrapperSetDCAGroupAssign = (fn_WrapperMIDISetDCAGroupAssign)RESOLVE(0x10029cc90);

    bool wantMainOn = false;
    bool wantMainMonoOn = false;
    char dcaList[160];
    formatMixerAssignmentSummary(snap.mixerData,
                                 wantMainOn,
                                 wantMainMonoOn,
                                 dcaList,
                                 sizeof(dcaList));
    bool wantMainMute = snap.mixerData[kMixerMainMuteOffset] != 0;
    bool usingWrapperMainMute = wrapperSetMainMute != nullptr;
    bool usingAuxOnSync = wrapperSetInputAuxOn != nullptr;
    bool usingAuxGainSync = wrapperSetAuxGain != nullptr;
    bool usingAuxPreSync = syncAuxPreSwitches != nullptr;
    bool usingAuxPanSync = wrapperSyncAuxPans != nullptr;
    bool usingImageSync = wrapperSyncImageControl1 && wrapperSyncImageControl2;
    bool usingMatrixSync = wrapperSetInputMatrixOn && syncMatrixPreSwitches &&
                           syncMatrixGains && wrapperSyncMatrixPans;
    bool usingWrapperDCA = wrapperSetDCAGroupAssign != nullptr;

    fprintf(stderr,
            "[MC]   [%s] Replay mixer state ch %d: mainOn=%d mainMonoOn=%d mainMute=%d dcas=%s "
            "(mainPath=%s mutePath=%s auxPath=%s matrixPath=%s dcaPath=%s)\n",
            phaseTag, ch + 1, wantMainOn ? 1 : 0, wantMainMonoOn ? 1 : 0, wantMainMute ? 1 : 0, dcaList,
            "mixer-module",
            usingWrapperMainMute ? "wrapper-midi" : "disabled",
            (usingAuxOnSync && usingAuxGainSync && usingAuxPreSync && usingAuxPanSync) ? "wrapper-midi-on+gain+pre+pan" :
            (usingAuxOnSync && usingAuxGainSync && usingAuxPreSync) ? "wrapper-midi-on+gain+pre" :
            (usingAuxOnSync && usingAuxGainSync) ? "wrapper-midi-on+gain" :
            (usingAuxOnSync ? "wrapper-midi-on" : "disabled"),
            usingMatrixSync ? "matrix-sync" : "disabled",
            usingWrapperDCA ? "wrapper-midi" : "mixer-module");

    if (setMainOnSwitch) setMainOnSwitch(mixer, (uint8_t)chInGrp, wantMainOn);
    if (informMainOnSetting) informMainOnSetting(mixer, (uint8_t)chInGrp, wantMainOn);

    if (setMainMonoOnSwitch) setMainMonoOnSwitch(mixer, (uint8_t)chInGrp, wantMainMonoOn);
    if (informMainMonoOnSetting) informMainMonoOnSetting(mixer, (uint8_t)chInGrp, wantMainMonoOn);

    if (usingWrapperMainMute)
        wrapperSetMainMute(g_inputMixerWrapper, (uint8_t)ch, wantMainMute, wantMainMute);

    int16_t mainGain = readMixerSWord(snap.mixerData, kMixerMainGainOffset);
    auto syncMainGain = (fn_SyncMainGain)RESOLVE(0x1002927e0);
    if (syncMainGain)
        syncMainGain(mixer, (uint8_t)chInGrp, mainGain);

    if (usingImageSync) {
        wrapperSyncImageControl1(g_inputMixerWrapper, (uint8_t)ch, (uint8_t)ch);
        wrapperSyncImageControl2(g_inputMixerWrapper, (uint8_t)ch, (uint8_t)ch);
    }

    if (usingAuxOnSync) {
        auto gainToUWORD = (uint16_t(*)(int16_t))RESOLVE(0x100105fa0);
        for (int aux = 0; aux < kMixerNumAuxes; aux++) {
            bool wantOn = snap.mixerData[kMixerAuxOnOffset + aux] != 0;
            wrapperSetInputAuxOn(g_inputMixerWrapper,
                                 (uint8_t)ch,
                                 (uint8_t)aux,
                                 wantOn,
                                 wantOn);
            if (usingAuxGainSync && gainToUWORD) {
                int16_t wantGain = readMixerSWord(snap.mixerData,
                                                  kMixerAuxGainOffset + aux * kMixerGainStride);
                uint16_t gainWord = gainToUWORD(wantGain);
                wrapperSetAuxGain(g_inputMixerWrapper,
                                  (uint8_t)ch,
                                  (uint8_t)aux,
                                  gainWord,
                                  true);
            }
            if (usingAuxPreSync) {
                bool wantPre = snap.mixerData[kMixerAuxPreOffset + aux] != 0;
                syncAuxPreSwitches(mixer, (uint8_t)chInGrp, (uint8_t)aux, wantPre);
            }
        }
        if (usingAuxPanSync)
            wrapperSyncAuxPans(g_inputMixerWrapper, (uint8_t)ch, (uint8_t)ch);
    }

    if (usingMatrixSync) {
        for (int matrix = 0; matrix < kMixerNumMatrices; matrix++) {
            bool wantOn = snap.mixerData[kMixerMatrixOnOffset + matrix] != 0;
            bool wantPre = snap.mixerData[kMixerMatrixPreOffset + matrix] != 0;
            int16_t wantGain = readMixerSWord(snap.mixerData,
                                              kMixerMatrixGainOffset + matrix * kMixerGainStride);
            wrapperSetInputMatrixOn(g_inputMixerWrapper,
                                    (uint8_t)ch,
                                    (uint8_t)matrix,
                                    wantOn,
                                    wantOn);
            syncMatrixPreSwitches(mixer, (uint8_t)chInGrp, (uint8_t)matrix, wantPre);
            syncMatrixGains(mixer, (uint8_t)chInGrp, (uint8_t)matrix, wantGain);
        }
        wrapperSyncMatrixPans(g_inputMixerWrapper, (uint8_t)ch, (uint8_t)ch);
    }

    for (int dca = 0; dca < kMixerNumDCAs; dca++) {
        bool wantAssign = snap.mixerData[kMixerDCAOffset + dca] != 0;
        if (usingWrapperDCA) {
            wrapperSetDCAGroupAssign(g_inputMixerWrapper,
                                     (uint8_t)dca,
                                     (uint8_t)ch,
                                     wantAssign,
                                     wantAssign);
            continue;
        }
        if (setDCAGroupAssign) {
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
        if (!clearPass) {
            if (!ins.hasInsert) return;
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

static bool routeDyn8InsertForChannelSlot(int ch,
                                          int ip,
                                          int unitIdx,
                                          bool clearSlot,
                                          const char* phaseTag) {
    if (!g_channelManager || !g_audioSRPManager)
        return false;

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
    if (!getChannel || !performTasks || !createSendTargetTask || !createReturnSourceTask || !mergeTaskLists)
        return false;

    void* cChannel = getChannel(g_channelManager, 1, (uint8_t)ch);
    if (!cChannel)
        return false;

    void* routeSendPt = clearSlot ? getDefaultInsertSendPoint() : getDyn8SendPointFromManager(unitIdx);
    void* routeRecvPt = clearSlot ? getDefaultInsertReceivePoint() : getDyn8RecvPointFromManager(unitIdx);
    if (!routeSendPt || !routeRecvPt)
        return false;

    if (clearSlot) {
        fprintf(stderr,
                "[MC]   [%s] Copy-paste clear Dyn8 Insert%c on ch %d\n",
                phaseTag, 'A' + ip, ch + 1);
        setInputChannelInsertFlags(ch, ip, false, false, phaseTag);
    } else {
        fprintf(stderr,
                "[MC]   [%s] Copy-paste assign Dyn8 Insert%c on ch %d unit=%d send=%p recv=%p\n",
                phaseTag, 'A' + ip, ch + 1, unitIdx, routeSendPt, routeRecvPt);
        setInputChannelInsertFlags(ch, ip, true, true, phaseTag);
    }

    uint8_t sendTasks[64];
    uint8_t returnTasks[64];
    memset(sendTasks, 0, sizeof(sendTasks));
    memset(returnTasks, 0, sizeof(returnTasks));
    createSendTargetTask(sendTasks, cChannel, routeRecvPt, ip, clearSlot ? 0 : 1);
    createReturnSourceTask(returnTasks, cChannel, routeSendPt, ip);
    mergeTaskLists(sendTasks, returnTasks);
    performTasks(g_audioSRPManager, sendTasks);
    return true;
}

static bool replayDyn8DataToUnit(int unitIdx,
                                 const uint8_t dyn8Data[0x94],
                                 int ch,
                                 int ip,
                                 const char* phaseTag) {
    if (!dyn8Data)
        return false;

    void* tgtDynObj = getDynNetObj(unitIdx);
    if (!tgtDynObj)
        return false;

    typedef void (*fn_setAllDataUI)(void* obj, void* sDynData);
    auto setAllDataUI = (fn_setAllDataUI)RESOLVE(0x100239970);
    typedef void (*fn_setDynData)(void* system, void* key, void* data);
    auto setDynData = (fn_setDynData)RESOLVE(0x100239240);
    typedef void (*fn_setFullSideChainData)(void* system, void* key, void* data);
    auto setFullSideChainData = (fn_setFullSideChainData)RESOLVE(0x10023a4e0);
    typedef void (*fn_setDynObjSideChainSource)(void* obj, void* msg);
    auto setDynObjSideChainSource = (fn_setDynObjSideChainSource)RESOLVE(0x10023a490);
    typedef void (*fn_fullDriverUpdate)(void* system);
    auto fullDriverUpdate = (fn_fullDriverUpdate)RESOLVE(0x10023c6c0);
    typedef void (*fn_cAHNetMessage_ctor)(void* msg);
    typedef void (*fn_cAHNetMessage_dtor)(void* msg);
    typedef void (*fn_SetLength)(void* msg, uint32_t len);
    typedef void (*fn_SetDataBufferUBYTE)(void* msg, uint8_t val, uint32_t offset);
    typedef void (*fn_PackBandsWide)(void* msg, void* data, int param);
    typedef void (*fn_PackSideChain)(void* msg, void* data, int param);
    typedef void (*fn_EntrypointMessage)(void* duc, void* msg);

    auto msgCtor = (fn_cAHNetMessage_ctor)RESOLVE(0x1000e9790);
    auto msgDtor = (fn_cAHNetMessage_dtor)RESOLVE(0x1000e9810);
    auto setLen = (fn_SetLength)RESOLVE(0x1000e9ee0);
    auto setUBYTE = (fn_SetDataBufferUBYTE)RESOLVE(0x1000ebde0);
    auto packBands = (fn_PackBandsWide)RESOLVE(0x1000cded0);
    auto packSC = (fn_PackSideChain)RESOLVE(0x1000cdfd0);
    auto entrypoint = (fn_EntrypointMessage)RESOLVE(0x1005e9140);
    if (!setAllDataUI || !setDynData || !fullDriverUpdate || !msgCtor || !msgDtor ||
        !setLen || !setUBYTE || !packBands || !packSC || !entrypoint)
        return false;

    void* dynSystem = nullptr;
    safeRead((uint8_t*)tgtDynObj + 0x90, &dynSystem, sizeof(dynSystem));
    uint8_t dynKey[8] = {};
    safeRead((uint8_t*)tgtDynObj + 0x88, dynKey, sizeof(dynKey));

    fprintf(stderr,
            "[MC]   [%s] Copy-paste Dyn8 data to ch %d Insert%c unit %d key={%u,%u}\n",
            phaseTag, ch + 1, 'A' + ip, unitIdx,
            *(uint32_t*)dynKey, (uint32_t)dynKey[4]);

    setAllDataUI(tgtDynObj, (void*)dyn8Data);
    if (dynSystem) {
        setDynData(dynSystem, dynKey, (void*)dyn8Data);
        if (setFullSideChainData)
            setFullSideChainData(dynSystem, dynKey, (void*)dyn8Data);
        uint8_t one = 1;
        safeWrite((uint8_t*)dynSystem + 0xca9, &one, 1);
        fullDriverUpdate(dynSystem);
    }

    if (setDynObjSideChainSource) {
        uint8_t scMsg[64];
        memset(scMsg, 0, sizeof(scMsg));
        msgCtor(scMsg);
        setLen(scMsg, 0xa);
        packSC(scMsg, (void*)dyn8Data, 0);
        setDynObjSideChainSource(tgtDynObj, scMsg);
        msgDtor(scMsg);
    }

    void* duc = getDynUnitClient(unitIdx);
    if (duc) {
        uint32_t ducKey = 0;
        safeRead((uint8_t*)duc + 0x68, &ducKey, 4);
        uint8_t msgBuf[64];

        memset(msgBuf, 0, sizeof(msgBuf));
        msgCtor(msgBuf);
        *(uint16_t*)(msgBuf + 0x10) = 0;
        *(uint32_t*)(msgBuf + 0x14) = ducKey;
        *(uint32_t*)(msgBuf + 0x18) = ducKey;
        *(uint32_t*)(msgBuf + 0x1c) = 0x1001;
        setLen(msgBuf, 1);
        setUBYTE(msgBuf, dyn8Data[0], 0);
        entrypoint(duc, msgBuf);
        msgDtor(msgBuf);

        memset(msgBuf, 0, sizeof(msgBuf));
        msgCtor(msgBuf);
        *(uint16_t*)(msgBuf + 0x10) = 0;
        *(uint32_t*)(msgBuf + 0x14) = ducKey;
        *(uint32_t*)(msgBuf + 0x18) = ducKey;
        *(uint32_t*)(msgBuf + 0x1c) = 0x1002;
        setLen(msgBuf, 8);
        packBands(msgBuf, (void*)dyn8Data, 0);
        entrypoint(duc, msgBuf);
        msgDtor(msgBuf);

        memset(msgBuf, 0, sizeof(msgBuf));
        msgCtor(msgBuf);
        *(uint16_t*)(msgBuf + 0x10) = 0;
        *(uint32_t*)(msgBuf + 0x14) = ducKey;
        *(uint32_t*)(msgBuf + 0x18) = ducKey;
        *(uint32_t*)(msgBuf + 0x1c) = 0x1003;
        setLen(msgBuf, 0xa);
        packSC(msgBuf, (void*)dyn8Data, 0);
        entrypoint(duc, msgBuf);
        msgDtor(msgBuf);
    }

    refreshDyn8InsertAssignment(unitIdx, ch, phaseTag);
    return true;
}

static bool readProcOrderValue(void* procOrderObj, uint8_t& outVal) {
    if (!procOrderObj) return false;
    uint8_t procBuf[16] = {};
    procBuf[0] = g_procB[2].versionByte;
    if (!readTypeBField(procOrderObj, g_procB[2].fields[0], procBuf))
        return false;
    outVal = procBuf[1];
    return true;
}

static bool writeProcOrderForChannel(int ch, const ChannelSnapshot& snap) {
    if (!snap.validB[2]) return true;

    uint8_t wantVal = snap.dataB[2].buf[1];
    int attempts = wantVal ? 50 : 1;
    typedef void (*fn_SetPEQComp)(void* obj, bool enabled);
    typedef void (*fn_SetStatus)(void* obj, void* msg);
    typedef void (*fn_SetLength)(void*, uint32_t);
    typedef void (*fn_SetUBYTE)(void*, uint8_t, uint32_t);
    auto setPEQComp = (fn_SetPEQComp)RESOLVE(0x1002d8730);
    auto setStatus = (fn_SetStatus)RESOLVE(0x1002d87e0);
    auto setLen = (fn_SetLength)RESOLVE(0x1000e9ee0);
    auto setUByte = (fn_SetUBYTE)RESOLVE(0x1000ebde0);

    for (int attempt = 0; attempt < attempts; attempt++) {
        void* inputCh = getInputChannel(ch);
        if (inputCh) {
            void* procOrderObj = getTypeBObj(inputCh, g_procB[2]);
            if (procOrderObj) {
                bool applied = false;

                if (setStatus && setLen && setUByte) {
                    uint8_t msg[MSG_BUF_SIZE];
                    memset(msg, 0, sizeof(msg));
                    g_msgCtorCap(msg, 512);
                    setLen(msg, 2);
                    setUByte(msg, g_procB[2].versionByte, 0);
                    setUByte(msg, wantVal, 1);
                    setStatus(procOrderObj, msg);
                    g_msgDtor(msg);

                    uint8_t gotVal = 0;
                    bool readbackOk = readProcOrderValue(procOrderObj, gotVal);
                    fprintf(stderr,
                            "[MC]   ProcOrder settle set on ch %d: value=%u via SetStatus (attempt %d readback=%s value=%u)\n",
                            ch + 1, wantVal, attempt + 1,
                            readbackOk ? "ok" : "fail",
                            gotVal);
                    if (readbackOk && gotVal == wantVal)
                        applied = true;
                }

                if (!applied && setPEQComp) {
                    setPEQComp(procOrderObj, wantVal != 0);
                    uint8_t gotVal = 0;
                    bool readbackOk = readProcOrderValue(procOrderObj, gotVal);
                    fprintf(stderr,
                            "[MC]   ProcOrder settle set on ch %d: value=%u via SetPEQComp fallback (attempt %d readback=%s value=%u)\n",
                            ch + 1, wantVal, attempt + 1,
                            readbackOk ? "ok" : "fail",
                            gotVal);
                    if (readbackOk && gotVal == wantVal)
                        applied = true;
                }

                if (!applied) {
                    uint8_t procBuf[16] = {};
                    procBuf[0] = g_procB[2].versionByte;
                    procBuf[1] = wantVal;
                    writeTypeBFields(procOrderObj, g_procB[2], procBuf);
                    uint8_t gotVal = 0;
                    bool readbackOk = readProcOrderValue(procOrderObj, gotVal);
                    fprintf(stderr,
                            "[MC]   ProcOrder settle write on ch %d: value=%u via raw fallback (attempt %d readback=%s value=%u)\n",
                            ch + 1, wantVal, attempt + 1,
                            readbackOk ? "ok" : "fail",
                            gotVal);
                }
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
    bool skipMixerVerify = autotestEnvEnabled("MC_AUTOTEST_SKIP_MIXER_VERIFY");

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

    if (!skipMixerVerify) {
        if (expected.validMixer != actual.validMixer) {
            fprintf(stderr, "[MC][VERIFY] ch %d mixer presence mismatch\n", ch+1);
            ok = false;
        } else if (expected.validMixer && expected.mixerData && actual.mixerData &&
                   memcmp(expected.mixerData, actual.mixerData, SINPUTATTRS_SIZE) != 0) {
            fprintf(stderr, "[MC][VERIFY] ch %d mixer payload mismatch\n", ch+1);
            ok = false;
        }
    }

    if (expected.validMuteGroups != actual.validMuteGroups) {
        fprintf(stderr, "[MC][VERIFY] ch %d mute-group presence mismatch\n", ch + 1);
        ok = false;
    } else if (expected.validMuteGroups && expected.muteGroupMask != actual.muteGroupMask) {
        char expList[64];
        char actList[64];
        formatMuteGroupMaskSummary(expected.muteGroupMask, expList, sizeof(expList));
        formatMuteGroupMaskSummary(actual.muteGroupMask, actList, sizeof(actList));
        fprintf(stderr,
                "[MC][VERIFY] ch %d mute-group mismatch: expected %s got %s\n",
                ch + 1, expList, actList);
        ok = false;
    }

    if (expected.validPreamp != actual.validPreamp) {
        fprintf(stderr, "[MC][VERIFY] ch %d preamp presence mismatch\n", ch+1);
        ok = false;
    } else if (expected.validPreamp) {
        PreampData expPreamp = expected.preampData;
        PreampData actPreamp = actual.preampData;
        if (expected.validPatch)
            expPreamp = normalizedPreampDataForSource(expected.patchData.source, expPreamp);
        if (actual.validPatch)
            actPreamp = normalizedPreampDataForSource(actual.patchData.source, actPreamp);
        if (!samePreampData(expPreamp, actPreamp)) {
            fprintf(stderr,
                    "[MC][VERIFY] ch %d preamp mismatch exp={gain=%d pad=%d phantom=%d} got={gain=%d pad=%d phantom=%d}\n",
                    ch + 1,
                    expPreamp.gain, expPreamp.pad, expPreamp.phantom,
                    actPreamp.gain, actPreamp.pad, actPreamp.phantom);
            ok = false;
        }
    }

    if (comparePatch) {
        if (expected.validPatch != actual.validPatch) {
            fprintf(stderr, "[MC][VERIFY] ch %d patch presence mismatch\n", ch+1);
            ok = false;
        } else if (expected.validPatch) {
            if (expected.patchData.sourceType != actual.patchData.sourceType ||
                expected.patchData.source.type != actual.patchData.source.type ||
                expected.patchData.source.number != actual.patchData.source.number) {
                fprintf(stderr,
                        "[MC][VERIFY] ch %d patch mismatch exp={srcType=%u type=%u num=%u} got={srcType=%u type=%u num=%u}\n",
                        ch + 1,
                        expected.patchData.sourceType,
                        expected.patchData.source.type,
                        expected.patchData.source.number,
                        actual.patchData.sourceType,
                        actual.patchData.source.type,
                        actual.patchData.source.number);
                ok = false;
            }
        }
    }

    if (expected.activeInputSource != actual.activeInputSource ||
        expected.abcdEnabled != actual.abcdEnabled) {
        fprintf(stderr,
                "[MC][VERIFY] ch %d ABCD state mismatch exp={enabled=%d active=%u} got={enabled=%d active=%u}\n",
                ch + 1,
                expected.abcdEnabled ? 1 : 0, expected.activeInputSource,
                actual.abcdEnabled ? 1 : 0, actual.activeInputSource);
        ok = false;
    }
    for (int i = 0; i < 4; i++) {
        const auto& exp = expected.activeInputData[i];
        const auto& act = actual.activeInputData[i];
        if (exp.assigned != act.assigned) {
            fprintf(stderr,
                    "[MC][VERIFY] ch %d ABCD source %c assigned mismatch exp=%d got=%d\n",
                    ch + 1, 'A' + i, exp.assigned ? 1 : 0, act.assigned ? 1 : 0);
            ok = false;
            continue;
        }
        if (!exp.assigned) continue;
        if (memcmp(&exp.source, &act.source, sizeof(sAudioSource)) != 0) {
            fprintf(stderr,
                    "[MC][VERIFY] ch %d ABCD source %c mismatch exp={type=%u num=%u} got={type=%u num=%u}\n",
                    ch + 1, 'A' + i,
                    exp.source.type, exp.source.number,
                    act.source.type, act.source.number);
            ok = false;
        }
        if (exp.validPreamp != act.validPreamp) {
            fprintf(stderr,
                    "[MC][VERIFY] ch %d ABCD source %c preamp presence mismatch\n",
                    ch + 1, 'A' + i);
            ok = false;
            continue;
        }
        if (exp.validPreamp && !samePreampDataForSource(exp.source, exp.preampData, act.preampData)) {
            fprintf(stderr,
                    "[MC][VERIFY] ch %d ABCD source %c preamp mismatch exp={gain=%d pad=%d phantom=%d} got={gain=%d pad=%d phantom=%d}\n",
                    ch + 1, 'A' + i,
                    normalizedPreampDataForSource(exp.source, exp.preampData).gain,
                    normalizedPreampDataForSource(exp.source, exp.preampData).pad,
                    normalizedPreampDataForSource(exp.source, exp.preampData).phantom,
                    normalizedPreampDataForSource(exp.source, act.preampData).gain,
                    normalizedPreampDataForSource(exp.source, act.preampData).pad,
                    normalizedPreampDataForSource(exp.source, act.preampData).phantom);
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

static bool compareSnapshotsForCopyPaste(const ChannelSnapshot& expected,
                                         const ChannelSnapshot& actual,
                                         int ch) {
    bool ok = true;
    bool skipMixerVerify = autotestEnvEnabled("MC_AUTOTEST_SKIP_MIXER_VERIFY");

    if (strcmp(expected.name, actual.name) != 0) {
        fprintf(stderr, "[MC][COPY-VERIFY] ch %d name mismatch: expected '%s' got '%s'\n",
                ch + 1, expected.name, actual.name);
        ok = false;
    }
    if (expected.colour != actual.colour) {
        fprintf(stderr, "[MC][COPY-VERIFY] ch %d colour mismatch: expected %u got %u\n",
                ch + 1, expected.colour, actual.colour);
        ok = false;
    }
    if (expected.isStereo != actual.isStereo) {
        fprintf(stderr, "[MC][COPY-VERIFY] ch %d stereo mismatch: expected %d got %d\n",
                ch + 1, expected.isStereo, actual.isStereo);
        ok = false;
    }

    for (int p = 0; p < NUM_PROC_A; p++) {
        if (expected.validA[p] != actual.validA[p]) {
            fprintf(stderr, "[MC][COPY-VERIFY] ch %d %s presence mismatch\n", ch + 1, g_procA[p].name);
            ok = false;
            continue;
        }
        if (!expected.validA[p]) continue;

        uint32_t expLen = getMsgLength(expected.msgA[p]);
        uint32_t actLen = getMsgLength(actual.msgA[p]);
        if (expLen != actLen) {
            fprintf(stderr, "[MC][COPY-VERIFY] ch %d %s len mismatch: expected %u got %u\n",
                    ch + 1, g_procA[p].name, expLen, actLen);
            ok = false;
            continue;
        }

        void* expData = getMsgDataPtr(expected.msgA[p]);
        void* actData = getMsgDataPtr(actual.msgA[p]);
        if ((expLen > 0) && (!expData || !actData || memcmp(expData, actData, expLen) != 0)) {
            fprintf(stderr, "[MC][COPY-VERIFY] ch %d %s payload mismatch\n", ch + 1, g_procA[p].name);
            ok = false;
        }
    }

    for (int p = 0; p < NUM_PROC_B; p++) {
        if (isInsertStatusProc(p)) continue;
        if (p == 2) {
            uint8_t expVal = expected.validB[p] ? expected.dataB[p].buf[1] : 0;
            uint8_t actVal = actual.validB[p] ? actual.dataB[p].buf[1] : 0;
            if (expVal != actVal) {
                fprintf(stderr, "[MC][COPY-VERIFY] ch %d %s mismatch: expected %u got %u\n",
                        ch + 1, g_procB[p].name, expVal, actVal);
                ok = false;
            }
            continue;
        }
        if (expected.validB[p] != actual.validB[p]) {
            fprintf(stderr, "[MC][COPY-VERIFY] ch %d %s presence mismatch\n", ch + 1, g_procB[p].name);
            ok = false;
            continue;
        }
        if (!expected.validB[p]) continue;
        if ((expected.dataB[p].len != actual.dataB[p].len) ||
            memcmp(expected.dataB[p].buf, actual.dataB[p].buf, expected.dataB[p].len) != 0) {
            fprintf(stderr, "[MC][COPY-VERIFY] ch %d %s payload mismatch\n", ch + 1, g_procB[p].name);
            ok = false;
        }
    }

    if (!skipMixerVerify) {
        if (expected.validMixer != actual.validMixer) {
            fprintf(stderr, "[MC][COPY-VERIFY] ch %d mixer presence mismatch\n", ch + 1);
            ok = false;
        } else if (expected.validMixer && expected.mixerData && actual.mixerData &&
                   memcmp(expected.mixerData, actual.mixerData, SINPUTATTRS_SIZE) != 0) {
            fprintf(stderr, "[MC][COPY-VERIFY] ch %d mixer payload mismatch\n", ch + 1);
            ok = false;
        }
    }

    if (expected.validMuteGroups != actual.validMuteGroups) {
        fprintf(stderr, "[MC][COPY-VERIFY] ch %d mute-group presence mismatch\n", ch + 1);
        ok = false;
    } else if (expected.validMuteGroups && expected.muteGroupMask != actual.muteGroupMask) {
        char expList[64];
        char actList[64];
        formatMuteGroupMaskSummary(expected.muteGroupMask, expList, sizeof(expList));
        formatMuteGroupMaskSummary(actual.muteGroupMask, actList, sizeof(actList));
        fprintf(stderr,
                "[MC][COPY-VERIFY] ch %d mute-group mismatch: expected %s got %s\n",
                ch + 1, expList, actList);
        ok = false;
    }

    if (expected.validPreamp && actual.validPatch &&
        patchDataUsesSocketBackedPreamp(actual.patchData) &&
        audioSourceHasMovablePreampState(actual.patchData.source)) {
        PreampData expPreamp = normalizedPreampDataForSource(actual.patchData.source, expected.preampData);
        PreampData actPreamp = normalizedPreampDataForSource(actual.patchData.source, actual.preampData);
        if (!samePreampData(expPreamp, actPreamp)) {
            fprintf(stderr,
                    "[MC][COPY-VERIFY] ch %d preamp mismatch exp={gain=%d pad=%d phantom=%d} got={gain=%d pad=%d phantom=%d}\n",
                    ch + 1,
                    expPreamp.gain, expPreamp.pad, expPreamp.phantom,
                    actPreamp.gain, actPreamp.pad, actPreamp.phantom);
            ok = false;
        }
    }

    bool expectedHasDyn8 = expected.validDyn8;
    bool actualHasDyn8 = actual.validDyn8;
    if (expectedHasDyn8 != actualHasDyn8) {
        fprintf(stderr, "[MC][COPY-VERIFY] ch %d Dyn8 presence mismatch exp=%d got=%d\n",
                ch + 1, expectedHasDyn8 ? 1 : 0, actualHasDyn8 ? 1 : 0);
        ok = false;
    } else if (expectedHasDyn8 &&
               memcmp(expected.dyn8Data, actual.dyn8Data, sizeof(expected.dyn8Data)) != 0) {
        fprintf(stderr, "[MC][COPY-VERIFY] ch %d Dyn8 data mismatch\n", ch + 1);
        ok = false;
    }

    for (int ip = 0; ip < 2; ip++) {
        bool expDyn8 = expected.validDyn8 &&
                       expected.insertInfo[ip].hasInsert &&
                       expected.insertInfo[ip].parentType == 5;
        bool actDyn8 = actual.insertInfo[ip].hasInsert &&
                       actual.insertInfo[ip].parentType == 5;
        if (expDyn8 != actDyn8) {
            fprintf(stderr,
                    "[MC][COPY-VERIFY] ch %d Insert%c Dyn8 mismatch exp=%d got=%d\n",
                    ch + 1, 'A' + ip, expDyn8 ? 1 : 0, actDyn8 ? 1 : 0);
            ok = false;
        }
    }

    return ok;
}

static void logFinalPreampStateForChannel(int ch, const char* phaseTag = "final-verify") {
    PatchData livePatch = {};
    if (!readPatchData(ch, livePatch))
        return;

    int socketNum = -1;
    if (!patchDataUsesSocketBackedPreamp(livePatch) ||
        !getAnalogueSocketIndexForAudioSource(livePatch.source, socketNum)) {
        fprintf(stderr,
                "[MC][PREAMP] %s ch %d: no socket-backed preamp source (srcType=%u src={type=%u,num=%u})\n",
                phaseTag,
                ch + 1,
                livePatch.sourceType,
                livePatch.source.type,
                livePatch.source.number);
        return;
    }

    PreampData pd = {};
    if (!readPreampDataForPatch(livePatch, pd)) {
        fprintf(stderr,
                "[MC][PREAMP] %s ch %d: source={type=%u,num=%u} socket=%d readback failed\n",
                phaseTag,
                ch + 1,
                livePatch.source.type,
                livePatch.source.number,
                socketNum);
        return;
    }

    fprintf(stderr,
            "[MC][PREAMP] %s ch %d: source={type=%u,num=%u} socket=%d gain=%d pad=%d phantom=%d\n",
            phaseTag,
            ch + 1,
            livePatch.source.type,
            livePatch.source.number,
            socketNum,
            pd.gain, pd.pad, pd.phantom);
}

static bool compareGangSnapshotsForMove(const GangSnapshot& expected,
                                        const GangSnapshot& actual,
                                        const MovePlan& plan) {
    if (expected.valid != actual.valid) {
        fprintf(stderr, "[MC][VERIFY] input gang %d validity mismatch\n", expected.gangNum + 1);
        return false;
    }
    if (!expected.valid)
        return true;

    bool ok = true;
    if (expected.stripType != actual.stripType) {
        fprintf(stderr,
                "[MC][VERIFY] input gang %d stripType mismatch exp=%u got=%u\n",
                expected.gangNum + 1, expected.stripType, actual.stripType);
        ok = false;
    }
    if (memcmp(&expected.attrs, &actual.attrs, sizeof(expected.attrs)) != 0) {
        fprintf(stderr, "[MC][VERIFY] input gang %d attrs mismatch\n", expected.gangNum + 1);
        ok = false;
    }

    QList<GangStripKey> expMembers = buildGangMemberList(expected, &plan);
    QList<GangStripKey> actMembers = buildGangMemberList(actual, nullptr);
    if (expMembers.size() != actMembers.size()) {
        fprintf(stderr,
                "[MC][VERIFY] input gang %d member count mismatch exp=%d got=%d\n",
                expected.gangNum + 1, expMembers.size(), actMembers.size());
        ok = false;
    } else {
        for (int i = 0; i < expMembers.size(); i++) {
            if (expMembers[i].stripType != actMembers[i].stripType ||
                expMembers[i].channel != actMembers[i].channel) {
                fprintf(stderr,
                        "[MC][VERIFY] input gang %d member %d mismatch exp={type=%u ch=%u} got={type=%u ch=%u}\n",
                        expected.gangNum + 1, i,
                        expMembers[i].stripType, expMembers[i].channel,
                        actMembers[i].stripType, actMembers[i].channel);
                ok = false;
            }
        }
    }

    return ok;
}

static void logGangSnapshotSummary(const char* phaseTag, const GangSnapshot& snap, const MovePlan* plan = nullptr) {
    if (!snap.valid) {
        fprintf(stderr, "[MC]   [%s] input gang %d: invalid\n",
                phaseTag ? phaseTag : "gang", snap.gangNum + 1);
        return;
    }
    QList<GangStripKey> members = buildGangMemberList(snap, plan);
    std::string memberList;
    for (int i = 0; i < members.size(); i++) {
        char buf[32];
        snprintf(buf, sizeof(buf), "%s%u", i ? "," : "", (unsigned)members[i].channel + 1);
        memberList += buf;
    }
    if (memberList.empty())
        memberList = "-";
    fprintf(stderr,
            "[MC]   [%s] input gang %d: stripType=%u members=%s attrs={lo=0x%016llx hi=0x%016llx}\n",
            phaseTag ? phaseTag : "gang",
            snap.gangNum + 1,
            snap.stripType,
            memberList.c_str(),
            (unsigned long long)snap.attrs.lo,
            (unsigned long long)snap.attrs.hi);
}

static bool prepareAutotestGang(const MovePlan& plan, GangSnapshot& snap) {
    snap = {};
    if (!g_gangingManager) {
        fprintf(stderr, "[MC][AUTOTEST] ganging manager unavailable; skipping gang prep\n");
        return false;
    }

    typedef void* (*fn_GetGangDriver)(void* mgr, uint8_t gangNum);
    auto getGangDriver = (fn_GetGangDriver)RESOLVE(0x100e95a30);
    if (!getGangDriver) return false;

    uint8_t gangNum = 0;
    void* driver = getGangDriver(g_gangingManager, gangNum);
    if (!driver) return false;

    QList<GangStripKey> members;
    for (int ch = plan.lo; ch <= plan.hi && members.size() < 3; ch++)
        members.append(makeGangStripKey(1, (uint8_t)ch));
    if (members.size() < 2) {
        fprintf(stderr, "[MC][AUTOTEST] not enough channels to prepare gang test\n");
        return false;
    }

    fprintf(stderr,
            "[MC][AUTOTEST] preparing input gang %d with %d members\n",
            gangNum + 1, members.size());
    applyGangMembershipHighLevel(driver, gangNum, members, "[MC][AUTOTEST] prep gang");
    if (!readGangSnapshot(gangNum, snap)) {
        fprintf(stderr, "[MC][AUTOTEST] failed to snapshot prepared gang %d\n", gangNum + 1);
        return false;
    }
    snap.affected = gangSnapshotAffectsMove(snap, plan);
    fprintf(stderr,
            "[MC][AUTOTEST] prepared input gang %d: affected=%d members=%zu\n",
            gangNum + 1, snap.affected ? 1 : 0, snap.memberChannels.size());
    logGangSnapshotSummary("[MC][AUTOTEST] prep gang summary", snap, nullptr);
    return snap.valid;
}

static void prepareAutotestPreampPattern(const MovePlan& plan,
                                         bool movePatchWithChannel,
                                         bool shiftMixRackIOPortWithMoveInScenarioA) {
    for (int ch = plan.lo; ch <= plan.hi; ch++) {
        ChannelSnapshot snap;
        if (!snapshotChannel(ch, snap))
            continue;

        if (snap.validPatch && snap.validPreamp &&
            shouldRestorePatchedPreampForMove(snap.patchData,
                                              movePatchWithChannel,
                                              shiftMixRackIOPortWithMoveInScenarioA)) {
            int idx = ch - plan.lo;
            PreampData want = snap.preampData;
            want.gain = (int16_t)(-1200 + idx * 111);
            if (audioSourceSupportsPad(snap.patchData.source))
                want.pad = (idx & 1) ? 1 : 0;
            if (audioSourceSupportsPhantom(snap.patchData.source))
                want.phantom = ((idx / 2) & 1) ? 1 : 0;
            fprintf(stderr,
                    "[MC][AUTOTEST] prep preamp ch %d: gain=%d pad=%d phantom=%d\n",
                    ch + 1, want.gain, want.pad, want.phantom);
            writePreampDataForPatch(snap.patchData, want);
        }

        destroySnapshot(snap);
    }
    QApplication::processEvents();
}

static void prepareAutotestStereoImagePattern(const MovePlan& plan) {
    for (int ch = plan.lo; ch <= plan.hi; ch++) {
        ChannelSnapshot snap;
        if (!snapshotChannel(ch, snap))
            continue;
        if (!snap.validB[kProcStereoImageIdx]) {
            destroySnapshot(snap);
            continue;
        }

        uint16_t wantWidth = (uint16_t)std::min(1000, 120 + (ch - plan.lo) * 95);
        uint8_t wantMode = (uint8_t)((ch - plan.lo) & 1);
        snap.dataB[kProcStereoImageIdx].buf[1] = (uint8_t)(wantWidth >> 8);
        snap.dataB[kProcStereoImageIdx].buf[2] = (uint8_t)(wantWidth & 0xFF);
        snap.dataB[kProcStereoImageIdx].buf[3] = wantMode;
        fprintf(stderr,
                "[MC][AUTOTEST] prep stereo image ch %d: width=%u mode=%u\n",
                ch + 1, wantWidth, wantMode);
        replayStereoImageForChannel(ch, snap, "[MC][AUTOTEST] prep stereo image");
        destroySnapshot(snap);
    }
    QApplication::processEvents();
}

static bool runAutomatedCopyPasteTest() {
    const char* srcEnv = getenv("MC_AUTOTEST_COPY_SRC");
    const char* dstEnv = getenv("MC_AUTOTEST_COPY_DST");
    if (!srcEnv || !dstEnv)
        return false;
    updateAutotestOverlay("dLive Self-Test", "Running copy/paste scenario...");

    int src = atoi(srcEnv) - 1;
    int dst = atoi(dstEnv) - 1;
    if (src < 0 || src >= 128 || dst < 0 || dst >= 128) {
        fprintf(stderr, "[MC][COPYTEST] invalid source/destination env: src=%s dst=%s\n",
                srcEnv, dstEnv);
        return false;
    }

    if (autotestEnvEnabled("MC_AUTOTEST_PREP_SCENE21")) {
        if (!prepareScene21MoveTest())
            return false;
    }

    bool srcStereo = isChannelStereo(src);
    int srcStart = srcStereo ? (src & ~1) : src;
    int blockSize = srcStereo ? 2 : 1;
    int dstStart = srcStereo ? (dst & ~1) : dst;
    bool dstStereo = isChannelStereo(dst);
    if (srcStereo != dstStereo) {
        fprintf(stderr,
                "[MC][COPYTEST] stereo mismatch: src ch %d is %s but dst ch %d is %s\n",
                src + 1, srcStereo ? "stereo" : "mono",
                dst + 1, dstStereo ? "stereo" : "mono");
        return false;
    }

    MovePlan prepPlan;
    prepPlan.lo = srcStart;
    prepPlan.hi = srcStart + blockSize - 1;
    if (autotestEnvEnabled("MC_AUTOTEST_PREP_PREAMP"))
        prepareAutotestPreampPattern(prepPlan, false, false);
    if (autotestEnvEnabled("MC_AUTOTEST_PREP_STEREO_IMAGE"))
        prepareAutotestStereoImagePattern(prepPlan);

    ChannelSnapshot expected[2];
    for (int i = 0; i < blockSize; i++) {
        if (!snapshotChannel(srcStart + i, expected[i])) {
            fprintf(stderr, "[MC][COPYTEST] failed to snapshot source ch %d\n", srcStart + i + 1);
            for (int j = 0; j < i; j++)
                destroySnapshot(expected[j]);
            return false;
        }
    }

    if (!captureCopiedInputSettings(srcStart))
        return false;
    if (!pasteCopyBufferToInputStart(dstStart))
        return false;

    QApplication::processEvents();
    usleep(200 * 1000);
    QApplication::processEvents();

    if (const char* selectEnv = getenv("MC_AUTOTEST_SELECT_CH")) {
        int selectCh = atoi(selectEnv) - 1;
        selectInputChannelForUI(selectCh, "[MC][COPYTEST] ");
    } else {
        selectInputChannelForUI(dstStart, "[MC][COPYTEST] ");
    }

    bool ok = true;
    for (int i = 0; i < blockSize; i++) {
        ChannelSnapshot actual = {};
        if (!snapshotChannel(dstStart + i, actual)) {
            fprintf(stderr, "[MC][COPYTEST] failed to snapshot target ch %d\n", dstStart + i + 1);
            ok = false;
            continue;
        }
        if (!compareSnapshotsForCopyPaste(expected[i], actual, dstStart + i))
            ok = false;
        destroySnapshot(actual);
    }
    for (int i = 0; i < blockSize; i++)
        destroySnapshot(expected[i]);

    updateAutotestOverlay("dLive Self-Test",
                          QString("Copy/paste result: %1").arg(ok ? "PASS" : "FAIL"));
    fprintf(stderr, "[MC][COPYTEST] RESULT: %s\n", ok ? "PASS" : "FAIL");
    return ok;
}

static bool runAutomatedSelectTest() {
    const char* selectEnv = getenv("MC_AUTOTEST_SELECT_CH");
    if (!selectEnv) {
        fprintf(stderr, "[MC][SELECTTEST] missing MC_AUTOTEST_SELECT_CH\n");
        return false;
    }
    int selectCh = atoi(selectEnv) - 1;
    if (selectCh < 0 || selectCh >= 128) {
        fprintf(stderr, "[MC][SELECTTEST] invalid channel env '%s'\n", selectEnv);
        return false;
    }

    updateAutotestOverlay("dLive Self-Test",
                          QString("Selecting channel %1").arg(selectCh + 1));
    fprintf(stderr, "[MC][SELECTTEST] selecting channel %d\n", selectCh + 1);
    bool ok = selectInputChannelForUI(selectCh, "[MC][SELECTTEST] ");
    QApplication::processEvents();
    usleep(700 * 1000);
    QApplication::processEvents();

    SelectedStripInfo strip = getSelectedStripInfo(true);
    int selectedInput = getSelectedInputChannel(true);
    const char* selectedName = nullptr;
    if (g_audioDM)
        selectedName = g_getChannelName(g_audioDM, 1, selectCh);
    fprintf(stderr,
            "[MC][SELECTTEST] final selection: stripValid=%d stripType=%u stripCh=%d selectedInput=%d name='%s'\n",
            strip.valid ? 1 : 0,
            strip.valid ? strip.stripType : 0u,
            strip.valid ? strip.channel + 1 : -1,
            selectedInput >= 0 ? selectedInput + 1 : -1,
            selectedName ? selectedName : "(null)");

    if (!isSelectedInputChannelMatch(strip, selectedInput, selectCh))
        ok = false;

    updateAutotestOverlay("dLive Self-Test",
                          QString("Selection result: %1").arg(ok ? "PASS" : "FAIL"));
    fprintf(stderr, "[MC][SELECTTEST] RESULT: %s\n", ok ? "PASS" : "FAIL");
    return ok;
}

static bool runAutomatedMoveTest() {
    uint64_t autotestStartMs = monotonicMs();
    const char* srcEnv = getenv("MC_AUTOTEST_SRC");
    const char* dstEnv = getenv("MC_AUTOTEST_DST");
    if (!srcEnv || !dstEnv) return false;
    updateAutotestOverlay("dLive Self-Test",
                          QString("Preparing move %1 -> %2").arg(srcEnv).arg(dstEnv));

    int src = atoi(srcEnv) - 1;  // user-facing 1-based
    int dst = atoi(dstEnv) - 1;
    bool skipChannelVerify = autotestEnvEnabled("MC_AUTOTEST_SKIP_CHANNEL_VERIFY");
    QString roundtripShowName;
    if (const char* roundtripEnv = getenv("MC_AUTOTEST_SAVE_RECALL_SHOW")) {
        if (roundtripEnv[0] != '\0')
            roundtripShowName = QString::fromUtf8(roundtripEnv).trimmed();
    }
    bool movePatchWithChannel = false;
    if (const char* patchEnv = getenv("MC_AUTOTEST_MOVE_PATCH")) {
        movePatchWithChannel = (atoi(patchEnv) != 0);
    }
    bool shiftMixRackIOPortWithMoveInScenarioA = false;
    if (const char* ioEnv = getenv("MC_AUTOTEST_SHIFT_MIXRACK_IO")) {
        shiftMixRackIOPortWithMoveInScenarioA = (atoi(ioEnv) != 0);
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
    int requestedBlockSize = moveMonoBlock ? 2 : 1;
    if (const char* blockEnv = getenv("MC_AUTOTEST_BLOCK_SIZE")) {
        int parsed = atoi(blockEnv);
        if (parsed > 0) requestedBlockSize = parsed;
    }
    if (!buildMovePlan(src, dst, requestedBlockSize, plan, err, sizeof(err))) {
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

    if (autotestEnvEnabled("MC_AUTOTEST_PREP_PREAMP")) {
        prepareAutotestPreampPattern(plan,
                                     movePatchWithChannel,
                                     shiftMixRackIOPortWithMoveInScenarioA);
    }

    if (autotestEnvEnabled("MC_AUTOTEST_PREP_STEREO_IMAGE")) {
        prepareAutotestStereoImagePattern(plan);
    }

    GangSnapshot expectedGang;
    bool verifyGang = false;
    if (autotestEnvEnabled("MC_AUTOTEST_PREP_GANG")) {
        verifyGang = prepareAutotestGang(plan, expectedGang) && expectedGang.affected;
        if (!verifyGang)
            fprintf(stderr, "[MC][AUTOTEST] gang verification disabled for this run\n");
    }

    std::vector<ChannelSnapshot> expected;
    if (!skipChannelVerify) {
        expected.resize(plan.hi - plan.lo + 1);
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
            if (expected[i].validDyn8) {
                remapDyn8SideChainRef(expected[i].dyn8Data,
                                      sizeof(expected[i].dyn8Data),
                                      plan,
                                      "[MC][AUTOTEST] expected ",
                                      plan.lo + i,
                                      expected[i].dyn8UnitIdx);
            }
        }
        for (auto& [tgtCh, snapIdx] : plan.targetMap) {
            int srcCh = plan.lo + snapIdx;
            if (expected[snapIdx].validPatch) {
                expected[snapIdx].patchData =
                    getTargetPatchDataForMove(expected[snapIdx].patchData, srcCh, tgtCh,
                                             movePatchWithChannel,
                                             shiftMixRackIOPortWithMoveInScenarioA);
            }
            for (int i = 0; i < 4; i++) {
                auto& aid = expected[snapIdx].activeInputData[i];
                if (!aid.assigned) continue;
                aid.source = remapAudioSourceForMove(aid.source, srcCh, tgtCh,
                                                    movePatchWithChannel,
                                                    shiftMixRackIOPortWithMoveInScenarioA);
            }
        }
    }
    bool moved = moveChannel(src, dst, movePatchWithChannel,
                             shiftMixRackIOPortWithMoveInScenarioA,
                             requestedBlockSize);
    logAutotestTiming("move_channel_call_ms",
                      monotonicMs() - autotestStartMs,
                      moved ? "move_returned_true" : "move_returned_false");
    bool ok = moved;
    if (moved) {
        int selectedTargetCh = plan.dstStart;
        if (const char* selectEnv = getenv("MC_AUTOTEST_SELECT_CH")) {
            selectedTargetCh = atoi(selectEnv) - 1;
        }
        selectInputChannelForUI(selectedTargetCh, "[MC][AUTOTEST] ");
        fprintf(stderr,
                "[MC][AUTOTEST] MC_AUTOTEST_DUMP_PREAMP_UI=%s\n",
                getenv("MC_AUTOTEST_DUMP_PREAMP_UI") ? getenv("MC_AUTOTEST_DUMP_PREAMP_UI") : "(null)");
        if (autotestEnvEnabled("MC_AUTOTEST_DUMP_PREAMP_UI")) {
            QTimer::singleShot(0, qApp, []() {
                dumpPreampUiRegions("[MC][AUTOTEST] ");
            });
            QTimer::singleShot(1500, qApp, []() {
                dumpPreampUiRegions("[MC][AUTOTEST] (delayed) ");
            });
        }
        if (autotestEnvEnabled("MC_AUTOTEST_WEST_RELINK_EXPERIMENT")) {
            QTimer::singleShot(0, qApp, []() {
                relinkWestPreampControlWrappers("[MC][AUTOTEST] ");
            });
            QTimer::singleShot(250, qApp, []() {
                relinkWestPreampControlWrappers("[MC][AUTOTEST] (delayed 250ms) ");
            });
            QTimer::singleShot(1000, qApp, []() {
                relinkWestPreampControlWrappers("[MC][AUTOTEST] (delayed 1000ms) ");
            });
        }
        if (autotestEnvEnabled("MC_AUTOTEST_SELECTOR_LITE_PREAMP_EXPERIMENT")) {
            QTimer::singleShot(0, qApp, []() {
                runSelectorLitePreampExperiment("[MC][AUTOTEST] ");
            });
            QTimer::singleShot(250, qApp, []() {
                runSelectorLitePreampExperiment("[MC][AUTOTEST] (delayed 250ms) ");
            });
            QTimer::singleShot(1000, qApp, []() {
                runSelectorLitePreampExperiment("[MC][AUTOTEST] (delayed 1000ms) ");
            });
        }
        if (autotestEnvEnabled("MC_EXPERIMENT_SELECTOR_SURFACE_PREAMP")) {
            fprintf(stderr,
                    "[MC][AUTOTEST] selector-surface experiment scheduling for ch %d\n",
                    selectedTargetCh + 1);
            QTimer::singleShot(0, qApp, [selectedTargetCh]() {
                runSelectorSurfacePreampExperiment(selectedTargetCh, "[MC][AUTOTEST] ");
            });
            QTimer::singleShot(250, qApp, [selectedTargetCh]() {
                runSelectorSurfacePreampExperiment(selectedTargetCh, "[MC][AUTOTEST] (delayed 250ms) ");
            });
            QTimer::singleShot(1000, qApp, [selectedTargetCh]() {
                runSelectorSurfacePreampExperiment(selectedTargetCh, "[MC][AUTOTEST] (delayed 1000ms) ");
            });
        }
        if (autotestEnvEnabled("MC_AUTOTEST_WEST_REFRESH_EXPERIMENT")) {
            QTimer::singleShot(0, qApp, []() {
                runWestProcessingRefreshExperiment("[MC][AUTOTEST] ");
            });
            QTimer::singleShot(250, qApp, []() {
                runWestProcessingRefreshExperiment("[MC][AUTOTEST] (delayed 250ms) ");
            });
            QTimer::singleShot(1000, qApp, []() {
                runWestProcessingRefreshExperiment("[MC][AUTOTEST] (delayed 1000ms) ");
            });
        }
        if (autotestEnvEnabled("MC_AUTOTEST_WEST_DRIVER_POST_USER") ||
            autotestEnvEnabled("MC_AUTOTEST_WEST_DRIVER_WRITE_VALUE")) {
            QTimer::singleShot(0, qApp, []() {
                runWestUserControlDriverExperiment("[MC][AUTOTEST] ");
            });
            QTimer::singleShot(250, qApp, []() {
                runWestUserControlDriverExperiment("[MC][AUTOTEST] (delayed 250ms) ");
            });
            QTimer::singleShot(1000, qApp, []() {
                runWestUserControlDriverExperiment("[MC][AUTOTEST] (delayed 1000ms) ");
            });
        }
        if (!skipChannelVerify) {
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
        if (verifyGang) {
            GangSnapshot liveGang;
            if (!readGangSnapshot(expectedGang.gangNum, liveGang)) {
                fprintf(stderr,
                        "[MC][AUTOTEST] failed to snapshot input gang %d after move\n",
                        expectedGang.gangNum + 1);
                ok = false;
            } else if (!compareGangSnapshotsForMove(expectedGang, liveGang, plan)) {
                logGangSnapshotSummary("[MC][AUTOTEST] expected gang", expectedGang, &plan);
                logGangSnapshotSummary("[MC][AUTOTEST] live gang", liveGang, nullptr);
                ok = false;
            } else {
                logGangSnapshotSummary("[MC][AUTOTEST] live gang", liveGang, nullptr);
            }
        }

        if (ok && !roundtripShowName.isEmpty()) {
            updateAutotestOverlay("dLive Self-Test",
                                  QString("Saving reordered show %1").arg(roundtripShowName));
            fprintf(stderr,
                    "[MC][AUTOTEST] roundtrip requested via MC_AUTOTEST_SAVE_RECALL_SHOW='%s'\n",
                    roundtripShowName.toUtf8().constData());
            if (!saveAndRecallAutotestShowRoundtrip(roundtripShowName,
                                                    selectedTargetCh,
                                                    "[MC][AUTOTEST] ")) {
                ok = false;
            } else {
                if (autotestEnvEnabled("MC_AUTOTEST_DUMP_PREAMP_UI")) {
                    QTimer::singleShot(0, qApp, []() {
                        dumpPreampUiRegions("[MC][AUTOTEST] (post-rerecall) ");
                    });
                    QTimer::singleShot(1500, qApp, []() {
                        dumpPreampUiRegions("[MC][AUTOTEST] (post-rerecall delayed) ");
                    });
                }
                if (!skipChannelVerify) {
                    for (auto& [tgtCh, snapIdx] : plan.targetMap) {
                        ChannelSnapshot live;
                        if (!snapshotChannel(tgtCh, live)) {
                            fprintf(stderr,
                                    "[MC][AUTOTEST] failed to snapshot target %d after rerecall\n",
                                    tgtCh + 1);
                            ok = false;
                            continue;
                        }
                        dumpChannelData(tgtCh, "Autotest-After-Recall");
                        if (!compareSnapshotsForMove(expected[snapIdx], live, tgtCh, true))
                            ok = false;
                        destroySnapshot(live);
                    }
                }
                if (verifyGang) {
                    GangSnapshot liveGang;
                    if (!readGangSnapshot(expectedGang.gangNum, liveGang)) {
                        fprintf(stderr,
                                "[MC][AUTOTEST] failed to snapshot input gang %d after rerecall\n",
                                expectedGang.gangNum + 1);
                        ok = false;
                    } else if (!compareGangSnapshotsForMove(expectedGang, liveGang, plan)) {
                        logGangSnapshotSummary("[MC][AUTOTEST] expected gang", expectedGang, &plan);
                        logGangSnapshotSummary("[MC][AUTOTEST] live gang after rerecall", liveGang, nullptr);
                        ok = false;
                    } else {
                        logGangSnapshotSummary("[MC][AUTOTEST] live gang after rerecall", liveGang, nullptr);
                    }
                }
            }
        }
    }

    for (auto& snap : expected) destroySnapshot(snap);

    updateAutotestOverlay("dLive Self-Test",
                          QString("Move result: %1").arg(ok ? "PASS" : "FAIL"));
    logAutotestTiming("autotest_move_total_ms",
                      monotonicMs() - autotestStartMs,
                      ok ? "pass" : "fail");
    fprintf(stderr, "[MC][AUTOTEST] RESULT: %s\n", ok ? "PASS" : "FAIL");
    fprintf(stderr,
            "[MC][AUTOTEST] MC_AUTOTEST_DUMP_WEST_BINDING=%s\n",
            getenv("MC_AUTOTEST_DUMP_WEST_BINDING") ? getenv("MC_AUTOTEST_DUMP_WEST_BINDING") : "(null)");
    if (autotestEnvEnabled("MC_AUTOTEST_DUMP_WEST_BINDING")) {
        fprintf(stderr, "[MC][AUTOTEST] dumping west binding now\n");
        dumpWestBindingForSelectedChannel("[MC][AUTOTEST] ");
        QTimer::singleShot(1500, qApp, []() {
            dumpWestBindingForSelectedChannel("[MC][AUTOTEST] (delayed) ");
        });
    }
    return ok;
}

static bool buildMovePlan(int src, int dst, int requestedBlockSize,
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
    if (requestedBlockSize < 1 || requestedBlockSize > 128) {
        setErr("invalid block size");
        return false;
    }

    plan.srcStereo = isChannelStereo(src);
    if (requestedBlockSize == 1 && plan.srcStereo) {
        plan.blockSize = 2;
        plan.srcStart = src & ~1;
        plan.dstStart = dst & ~1;
    } else {
        plan.srcStereo = false;
        plan.blockSize = requestedBlockSize;
        plan.srcStart = src;
        plan.dstStart = dst;
        if (requestedBlockSize == 2 && src < 127 &&
            !isChannelStereo(src) && !isChannelStereo(src + 1)) {
            plan.srcMonoBlock = true;
        }
    }

    if (plan.srcStart + plan.blockSize - 1 > 127) {
        setErr("source block would exceed channel 128");
        return false;
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

    for (auto& [tgtCh, snapIdx] : plan.targetMap) {
        int srcCh = plan.lo + snapIdx;
        if (srcCh >= 0 && srcCh < 128)
            plan.sourceToTarget[srcCh] = tgtCh;
    }

    for (int pairStart = 0; pairStart < 128; pairStart += 2) {
        if (!isChannelStereo(pairStart)) continue;
        int leftDst = remapChannelIndex(plan, pairStart);
        int rightDst = remapChannelIndex(plan, pairStart + 1);
        if (leftDst < 0 || rightDst < 0 || rightDst != leftDst + 1 || (leftDst & 1) != 0) {
            setErr("move would split stereo pair %d+%d", pairStart + 1, pairStart + 2);
            return false;
        }
    }

    return true;
}

static bool buildReorderPlan(const std::vector<int>& targetOrder,
                             MovePlan& plan, char* errBuf = nullptr, size_t errBufLen = 0) {
    plan = MovePlan();
    plan.customOrder = true;
    if (errBuf && errBufLen) errBuf[0] = '\0';
    auto setErr = [&](const char* fmt, int a = 0, int b = 0) {
        if (errBuf && errBufLen) snprintf(errBuf, errBufLen, fmt, a, b);
    };

    if ((int)targetOrder.size() != 128) {
        setErr("invalid channel list size");
        return false;
    }

    std::array<bool, 128> seen{};
    std::vector<int> changed;
    for (int tgt = 0; tgt < 128; tgt++) {
        int srcCh = targetOrder[tgt];
        if (srcCh < 0 || srcCh > 127) {
            setErr("invalid source channel %d", srcCh + 1);
            return false;
        }
        if (seen[srcCh]) {
            setErr("duplicate channel %d in target list", srcCh + 1);
            return false;
        }
        seen[srcCh] = true;
        plan.sourceToTarget[srcCh] = tgt;
        if (srcCh != tgt) {
            changed.push_back(tgt);
            changed.push_back(srcCh);
        }
    }

    if (changed.empty()) {
        plan.lo = 0;
        plan.hi = -1;
        return true;
    }

    plan.lo = *std::min_element(changed.begin(), changed.end());
    plan.hi = *std::max_element(changed.begin(), changed.end());

    for (int tgt = plan.lo; tgt <= plan.hi; tgt++) {
        int srcCh = targetOrder[tgt];
        if (srcCh < plan.lo || srcCh > plan.hi) {
            setErr("reorder range closure failed");
            return false;
        }
        plan.targetMap.push_back({tgt, srcCh - plan.lo});
    }

    for (int pairStart = 0; pairStart < 128; pairStart += 2) {
        if (!isChannelStereo(pairStart)) continue;
        int leftDst = remapChannelIndex(plan, pairStart);
        int rightDst = remapChannelIndex(plan, pairStart + 1);
        if (leftDst < 0 || rightDst < 0 || rightDst != leftDst + 1 || (leftDst & 1) != 0) {
            setErr("reorder would split stereo pair %d+%d", pairStart + 1, pairStart + 2);
            return false;
        }
    }

    return true;
}

static int remapChannelIndex(const MovePlan& plan, int ch) {
    if (ch < 0 || ch > 127) return -1;
    return plan.sourceToTarget[ch];
}

static uint8_t remapMovedChannelRef(uint8_t oldRef, const MovePlan& plan) {
    int remapped = remapChannelIndex(plan, (int)oldRef);
    return remapped >= 0 ? (uint8_t)remapped : oldRef;
}

static bool remapDyn8SideChainRef(uint8_t* dyn8Data, size_t dyn8Size,
                                  const MovePlan& plan,
                                  const char* phaseTag,
                                  int ownerCh,
                                  int unitIdx) {
    if (!dyn8Data || dyn8Size < 12) return false;

    // sDynamicsData begins with sidechain selector metadata:
    // +0x04 = source type, +0x08 = zero-based source channel.
    uint32_t srcType = 0;
    uint32_t srcChannel = 0;
    memcpy(&srcType, dyn8Data + 4, sizeof(srcType));
    memcpy(&srcChannel, dyn8Data + 8, sizeof(srcChannel));
    if (srcType == 0)
        return false;

    int remapped = remapChannelIndex(plan, (int)srcChannel);
    if (remapped < 0 || remapped == (int)srcChannel)
        return false;

    uint32_t newChannel = (uint32_t)remapped;
    memcpy(dyn8Data + 8, &newChannel, sizeof(newChannel));
    fprintf(stderr,
            "[MC]   %sDyn8 sidechain remap on ch %d unit %d: type=%u channel %u -> %u\n",
            phaseTag ? phaseTag : "",
            ownerCh + 1, unitIdx, srcType, srcChannel, newChannel);
    return true;
}

static GangStripKey makeGangStripKey(uint32_t stripType, uint8_t ch) {
    GangStripKey key;
    key.stripType = stripType;
    key.channel = ch;
    return key;
}

static bool readGangSnapshot(uint8_t gangNum, GangSnapshot& snap) {
    snap = {};
    snap.gangNum = gangNum;
    if (!g_gangingManager) return false;

    typedef void* (*fn_GetGangDriver)(void* mgr, uint8_t gangNum);
    auto getGangDriver = (fn_GetGangDriver)RESOLVE(0x100e95a30);
    if (!getGangDriver) return false;

    void* driver = getGangDriver(g_gangingManager, gangNum);
    if (!driver) return false;

    snap.valid = true;
    safeRead((uint8_t*)driver + 0x94, &snap.stripType, sizeof(snap.stripType));
    safeRead((uint8_t*)driver + 0xA8, &snap.attrs, sizeof(snap.attrs));

    uint8_t members[16];
    memset(members, 0xFF, sizeof(members));
    safeRead((uint8_t*)driver + 0x98, members, sizeof(members));
    for (uint8_t member : members) {
        if (member == 0xFF) continue;
        snap.memberChannels.push_back(member);
    }
    return true;
}

static bool gangSnapshotAffectsMove(const GangSnapshot& snap, const MovePlan& plan) {
    if (!snap.valid || snap.stripType != 1) return false;
    for (uint8_t ch : snap.memberChannels) {
        if (ch >= plan.lo && ch <= plan.hi)
            return true;
    }
    return false;
}

static QList<GangStripKey> buildGangMemberList(const GangSnapshot& snap, const MovePlan* plan) {
    QList<GangStripKey> out;
    std::set<uint8_t> seen;
    for (uint8_t memberCh : snap.memberChannels) {
        uint8_t mappedCh = plan ? remapMovedChannelRef(memberCh, *plan) : memberCh;
        if (!seen.insert(mappedCh).second)
            continue;
        out.append(makeGangStripKey(snap.stripType, mappedCh));
    }
    return out;
}

static void syncGangStateToLive(const char* phaseTag, uint8_t gangNum) {
    typedef void (*fn_SyncGangs)(void* wrapper);
    auto syncGangs = (fn_SyncGangs)RESOLVE(0x10029f220);
    if (!g_inputMixerWrapper || !syncGangs) return;
    syncGangs(g_inputMixerWrapper);
    fprintf(stderr,
            "[MC]   [%s] SyncGangs for input gang %d\n",
            phaseTag, gangNum + 1);
}

static void applyGangMembershipHighLevel(void* driver,
                                         uint8_t gangNum,
                                         const QList<GangStripKey>& members,
                                         const char* phaseTag) {
    if (!driver) return;

    typedef void (*fn_SetGangMembersAndInform)(void* driver, const QList<GangStripKey>& members);
    typedef void (*fn_FlushSettingsToNetwork)(void* driver);

    auto setGangMembersAndInform = (fn_SetGangMembersAndInform)RESOLVE(0x1008f97f0);
    auto flushSettingsToNetwork = (fn_FlushSettingsToNetwork)RESOLVE(0x1008f9aa0);

    if (!setGangMembersAndInform) {
        fprintf(stderr,
                "[MC]   [%s] Gang %d apply skipped; no gang setter path available\n",
                phaseTag, gangNum + 1);
        return;
    }
    setGangMembersAndInform(driver, members);

    if (flushSettingsToNetwork) {
        flushSettingsToNetwork(driver);
        fprintf(stderr,
                "[MC]   [%s] FlushSettingsToNetwork for input gang %d\n",
                phaseTag, gangNum + 1);
    }
    syncGangStateToLive(phaseTag, gangNum);
    QApplication::processEvents();
    fprintf(stderr,
            "[MC]   [%s] Gang %d applied via %s (%d members)\n",
            phaseTag, gangNum + 1, "SetGangMembersAndInform", members.size());
}

static void clearGangMembershipHighLevel(const GangSnapshot& snap, const char* phaseTag) {
    if (!snap.valid || snap.memberChannels.empty() || !g_gangingManager) return;

    typedef void* (*fn_GetGangDriver)(void* mgr, uint8_t gangNum);
    auto getGangDriver = (fn_GetGangDriver)RESOLVE(0x100e95a30);
    if (!getGangDriver) return;

    void* driver = getGangDriver(g_gangingManager, snap.gangNum);
    if (!driver) return;

    QList<GangStripKey> emptyMembers;
    fprintf(stderr,
            "[MC]   [%s] Clear input gang %d (%zu members)\n",
            phaseTag, snap.gangNum + 1, snap.memberChannels.size());
    applyGangMembershipHighLevel(driver, snap.gangNum, emptyMembers, phaseTag);
}

static void restoreGangMembershipHighLevel(const GangSnapshot& snap, const MovePlan* plan,
                                           const char* phaseTag) {
    if (!snap.valid || !g_gangingManager) return;

    typedef void* (*fn_GetGangDriver)(void* mgr, uint8_t gangNum);
    auto getGangDriver = (fn_GetGangDriver)RESOLVE(0x100e95a30);
    if (!getGangDriver) return;

    void* driver = getGangDriver(g_gangingManager, snap.gangNum);
    if (!driver) return;

    QList<GangStripKey> remappedMembers = buildGangMemberList(snap, plan);
    fprintf(stderr,
            "[MC]   [%s] Restore input gang %d (%d members)\n",
            phaseTag, snap.gangNum + 1, remappedMembers.size());
    for (const auto& key : remappedMembers) {
        fprintf(stderr, "[MC]     gang %d member ch %d\n",
                snap.gangNum + 1, (int)key.channel + 1);
    }
    applyGangMembershipHighLevel(driver, snap.gangNum, remappedMembers, phaseTag);
}

static PatchData remapPatchDataForMove(const PatchData& pd, int srcCh, int tgtCh,
                                       bool shiftMixRackIOPortWithMoveInScenarioA) {
    PatchData out = pd;
    if (!shouldShiftPatchedPreampForMove(pd, false,
                                         shiftMixRackIOPortWithMoveInScenarioA))
        return out;

    int delta = tgtCh - srcCh;
    int newNumber = (int)pd.source.number + delta;
    uint16_t count = 0;
    if (!readNumSendPointsForType(pd.source.type, count) ||
        newNumber < 0 || newNumber >= count) {
        fprintf(stderr,
                "[MC]   WARN: patch remap src={type=%u, num=%u} + delta %d is out of range for ch %d; keeping original\n",
                pd.source.type,
                pd.source.number, delta, tgtCh + 1);
        return out;
    }

    out.source.number = (uint32_t)newNumber;
    fprintf(stderr,
            "[MC]   Patch remap srcCh %d -> tgtCh %d: source {type=%u, num=%u} -> {type=%u, num=%u}\n",
            srcCh + 1, tgtCh + 1,
            pd.source.type, pd.source.number,
            out.source.type, out.source.number);
    return out;
}

static PatchData getTargetPatchDataForMove(const PatchData& pd, int srcCh, int tgtCh,
                                           bool movePatchWithChannel,
                                           bool shiftMixRackIOPortWithMoveInScenarioA) {
    return movePatchWithChannel ? pd :
        remapPatchDataForMove(pd, srcCh, tgtCh, shiftMixRackIOPortWithMoveInScenarioA);
}

static PatchData getEffectiveTargetPatchData(const MovePlan* plan,
                                             const PatchData& pd,
                                             int srcCh,
                                             int tgtCh,
                                             bool movePatchWithChannel,
                                             bool shiftMixRackIOPortWithMoveInScenarioA) {
    if (plan && tgtCh >= 0 && tgtCh < 128 && plan->hasPatchOverride[tgtCh])
        return plan->patchOverride[tgtCh];
    return getTargetPatchDataForMove(pd, srcCh, tgtCh,
                                     movePatchWithChannel,
                                     shiftMixRackIOPortWithMoveInScenarioA);
}

// =============================================================================
// Move Channel
// =============================================================================
struct MoveConflictInfo;
static void clearLastMoveConflict();
static void setScenarioAPreampConflict(uint32_t socketNum,
                                       char existingSourceLabel, int existingSrcCh, int existingTgtCh,
                                       const PreampData& existingData,
                                       char newSourceLabel, int newSrcCh, int newTgtCh,
                                       const PreampData& newData);
static bool takeLastMoveConflict(MoveConflictInfo& out);

static bool applyMovePlan(const MovePlan& inputPlan,
                          bool movePatchWithChannel = false,
                          bool shiftMixRackIOPortWithMoveInScenarioA = false,
                          const char* logLabel = nullptr) {
    clearLastMoveConflict();
    MovePlan plan = inputPlan;

    if (plan.targetMap.empty()) {
        fprintf(stderr, "[MC] %s: nothing to do.\n", logLabel ? logLabel : "Move");
        return true;
    }

    int lo = plan.lo;
    int hi = plan.hi;
    int rangeSize = hi - lo + 1;
    bool hadStereoConfigChange = false;
    std::vector<int> monoizedPairs;
    std::vector<int> stereoizedPairs;
    struct ExternalSidechainRemap {
        int ch;
        int procIdx;
        uint8_t stripType;
        uint8_t oldChannel;
        uint8_t newChannel;
    };
    std::vector<ExternalSidechainRemap> externalSidechainRemaps;
    const char* patchPolicy = movePatchWithChannel ? "move with channel" : "shift by move amount";
    const char* ioPortPolicy = movePatchWithChannel
        ? "move with channel"
        : (shiftMixRackIOPortWithMoveInScenarioA ? "shift by move amount" : "stay with channel");

    if (plan.customOrder) {
        fprintf(stderr, "[MC] === APPLY %s (range %d-%d) [patching: %s, MixRack I/O Port: %s] ===\n",
                logLabel ? logLabel : "custom reorder",
                lo + 1, hi + 1,
                patchPolicy, ioPortPolicy);
    } else if (plan.srcStereo) {
        fprintf(stderr, "[MC] === MOVE ch %d → pos %d (normalized %d+%d → %d+%d, range %d-%d) [patching: %s, MixRack I/O Port: %s] ===\n",
                plan.rawSrc+1, plan.rawDst+1,
                plan.srcStart+1, plan.srcStart+2,
                plan.dstStart+1, plan.dstStart+2,
                lo+1, hi+1,
                patchPolicy, ioPortPolicy);
    } else if (plan.srcMonoBlock) {
        fprintf(stderr, "[MC] === MOVE mono block %d+%d → %d+%d (range %d-%d) [patching: %s, MixRack I/O Port: %s] ===\n",
                plan.srcStart+1, plan.srcStart+2,
                plan.dstStart+1, plan.dstStart+2,
                lo+1, hi+1,
                patchPolicy, ioPortPolicy);
    } else if (plan.blockSize > 1) {
        fprintf(stderr, "[MC] === MOVE block %d-%d → %d-%d (range %d-%d) [patching: %s, MixRack I/O Port: %s] ===\n",
                plan.srcStart+1, plan.srcStart+plan.blockSize,
                plan.dstStart+1, plan.dstStart+plan.blockSize,
                lo+1, hi+1,
                patchPolicy, ioPortPolicy);
    } else {
        fprintf(stderr, "[MC] === MOVE ch %d → pos %d (range %d-%d) [patching: %s, MixRack I/O Port: %s] ===\n",
                plan.rawSrc+1, plan.rawDst+1, lo+1, hi+1,
                patchPolicy, ioPortPolicy);
    }
    if (plan.srcStereo) {
        fprintf(stderr, "[MC] Stereo source pair: %d+%d → %d+%d\n",
                plan.srcStart+1, plan.srcStart+2, plan.dstStart+1, plan.dstStart+2);
    }

    uint64_t moveStartMs = monotonicMs();
    auto phase = [&](const char* label) {
        fprintf(stderr, "[MC][%6llums] %s\n",
                (unsigned long long)(monotonicMs() - moveStartMs), label);
        updateAutotestOverlay("dLive Self-Test", QString::fromUtf8(label));
        if (g_moveProgressCallback)
            g_moveProgressCallback(label);
    };

    std::vector<GangSnapshot> affectedGangSnaps;
    if (g_gangingManager) {
        phase("Phase: snapshot input ganging");
        for (uint8_t gangNum = 0; gangNum < 16; gangNum++) {
            GangSnapshot gangSnap;
            if (!readGangSnapshot(gangNum, gangSnap))
                continue;
            gangSnap.affected = gangSnapshotAffectsMove(gangSnap, plan);
            if (!gangSnap.affected)
                continue;
            fprintf(stderr,
                    "[MC]   Input gang %d snapshot: stripType=%u members=%zu\n",
                    gangNum + 1, gangSnap.stripType, gangSnap.memberChannels.size());
            affectedGangSnaps.push_back(gangSnap);
        }
    } else {
        fprintf(stderr, "[MC] GangingManager unavailable; skipping gang snapshot/restore.\n");
    }
    auto restoreAffectedGangs = [&](const char* phaseTag, bool remapToMovedChannels) {
        if (affectedGangSnaps.empty()) return;
        phase(phaseTag);
        for (const auto& gangSnap : affectedGangSnaps)
            restoreGangMembershipHighLevel(gangSnap, remapToMovedChannels ? &plan : nullptr, phaseTag);
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
            restoreAffectedGangs("Phase: restore input ganging after abort", false);
            return false;
        }
    }

    phase("Phase: plan external sidechain updates");
    for (int ch = 0; ch < 128; ch++) {
        if (ch >= lo && ch <= hi) continue;
        void* inputCh = getInputChannel(ch);
        if (!inputCh) continue;
        for (int p = 5; p <= 6; p++) {
            void* obj = getTypeBObj(inputCh, g_procB[p]);
            if (!obj) continue;
            uint8_t stripType = 0;
            uint8_t oldChannel = 0;
            if (!readSidechainRef(obj, stripType, oldChannel)) continue;
            if (stripType != 1) continue;
            uint8_t newChannel = remapMovedChannelRef(oldChannel, plan);
            if (newChannel == oldChannel) continue;
            fprintf(stderr,
                    "[MC]   Plan external %s on ch %d: channel %d -> %d\n",
                    g_procB[p].name, ch + 1, oldChannel, newChannel);
            externalSidechainRemaps.push_back({ch, p, stripType, oldChannel, newChannel});
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
            char sourceLabel;
            PreampData data;
        };
        std::vector<PlannedPreampWrite> plannedWrites;
        auto checkPlannedWrite = [&](uint32_t socketNum, int srcCh, int tgtCh,
                                     char sourceLabel, const sAudioSource& source,
                                     const PreampData& data) -> bool {
            for (const auto& planned : plannedWrites) {
                if (planned.socketNum != socketNum) continue;
                if (!samePreampDataForSource(source, planned.data, data)) {
                    PreampData plannedNorm = normalizedPreampDataForSource(source, planned.data);
                    PreampData dataNorm = normalizedPreampDataForSource(source, data);
                    setScenarioAPreampConflict(socketNum,
                                               planned.sourceLabel, planned.srcCh, planned.tgtCh, plannedNorm,
                                               sourceLabel, srcCh, tgtCh, dataNorm);
                    fprintf(stderr,
                            "[MC] ERROR: Scenario A preamp conflict on target socket %u:"
                            " %c ch %d -> %d wants gain=%d pad=%d phantom=%d,"
                            " but %c ch %d -> %d wants gain=%d pad=%d phantom=%d\n",
                            socketNum,
                            planned.sourceLabel, planned.srcCh + 1, planned.tgtCh + 1,
                            plannedNorm.gain, plannedNorm.pad, plannedNorm.phantom,
                            sourceLabel, srcCh + 1, tgtCh + 1,
                            dataNorm.gain, dataNorm.pad, dataNorm.phantom);
                    for (int i = 0; i < rangeSize; i++) destroySnapshot(snaps[i]);
                    restoreAffectedGangs("Phase: restore input ganging after abort", false);
                    return false;
                }
            }

            plannedWrites.push_back({socketNum, srcCh, tgtCh, sourceLabel, data});
            return true;
        };

        auto appendUntouchedSocketClaims = [&](int ch) {
            PatchData livePatch = {};
            PreampData livePreamp = {};
            if (readPatchData(ch, livePatch) &&
                readPreampDataForPatch(livePatch, livePreamp)) {
                int socketNum = -1;
                if (patchDataUsesSocketBackedPreamp(livePatch) &&
                    getAnalogueSocketIndexForAudioSource(livePatch.source, socketNum)) {
                    plannedWrites.push_back({(uint32_t)socketNum, ch, ch, 'M', livePreamp});
                    logPreampSocketClaim("untouched claim",
                                         (uint32_t)socketNum,
                                         'M',
                                         ch, ch,
                                         livePatch.source,
                                         livePreamp);
                }
            }

            void* cChannel = getManagedInputChannel(ch);
            if (!cChannel)
                return;

            typedef bool (*fn_HasActiveInputSourceAssigned)(void* channel, int activeInputSource);
            typedef void* (*fn_GetInputChannelSource)(void* channel, int activeInputSource);
            auto hasActiveInputSourceAssigned = (fn_HasActiveInputSourceAssigned)RESOLVE(0x1006df840);
            auto getInputChannelSource = (fn_GetInputChannelSource)RESOLVE(0x1006d81e0);
            if (!hasActiveInputSourceAssigned || !getInputChannelSource)
                return;

            for (int activeInputSource = 1; activeInputSource <= 4; activeInputSource++) {
                if (!hasActiveInputSourceAssigned(cChannel, activeInputSource))
                    continue;
                void* sendPt = getInputChannelSource(cChannel, activeInputSource);
                if (!sendPt)
                    continue;
                sAudioSource source = {0, 0};
                if (!resolveAudioSourceFromSendPoint(sendPt, source))
                    continue;
                if (!shouldRestoreSocketBackedPreampForMove(source,
                                                            movePatchWithChannel,
                                                            shiftMixRackIOPortWithMoveInScenarioA))
                    continue;
                PreampData liveAidPreamp = {};
                if (!readPreampDataForAudioSource(source, liveAidPreamp))
                    continue;
                int socketNum = -1;
                if (!getAnalogueSocketIndexForAudioSource(source, socketNum))
                    continue;
                plannedWrites.push_back({(uint32_t)socketNum, ch, ch,
                                         (char)('A' + activeInputSource - 1), liveAidPreamp});
                logPreampSocketClaim("untouched claim",
                                     (uint32_t)socketNum,
                                     (char)('A' + activeInputSource - 1),
                                     ch, ch,
                                     source,
                                     liveAidPreamp);
            }
        };

        for (int ch = 0; ch < 128; ch++) {
            if (ch >= lo && ch <= hi)
                continue;
            appendUntouchedSocketClaims(ch);
        }

        for (auto& [tgtCh, si] : plan.targetMap) {
            if (!snaps[si].validPatch || !snaps[si].validPreamp) continue;
            int srcCh = lo + si;
            PatchData tgtPatch = getEffectiveTargetPatchData(&plan, snaps[si].patchData, srcCh, tgtCh,
                                                             movePatchWithChannel,
                                                             shiftMixRackIOPortWithMoveInScenarioA);
            if (!shouldRestorePatchedPreampForMove(tgtPatch,
                                                   movePatchWithChannel,
                                                   shiftMixRackIOPortWithMoveInScenarioA))
                continue;
            int socketNum = -1;
            if (!patchDataUsesSocketBackedPreamp(tgtPatch) ||
                !getAnalogueSocketIndexForAudioSource(tgtPatch.source, socketNum))
                continue;
            logPreampSocketClaim("planned moved",
                                 (uint32_t)socketNum,
                                 'M',
                                 srcCh, tgtCh,
                                 tgtPatch.source,
                                 snaps[si].preampData);
            if (!checkPlannedWrite((uint32_t)socketNum, srcCh, tgtCh,
                                   'M', tgtPatch.source, snaps[si].preampData)) {
                restoreAffectedGangs("Phase: restore input ganging after abort", false);
                return false;
            }
        }

        for (auto& [tgtCh, si] : plan.targetMap) {
            int srcCh = lo + si;
            if (!snaps[si].abcdEnabled) continue;
            for (int activeInputSource = 1; activeInputSource <= 4; activeInputSource++) {
                const auto& aid = snaps[si].activeInputData[activeInputSource - 1];
                if (!aid.assigned || !aid.validPreamp) continue;
                sAudioSource tgtSource =
                    remapAudioSourceForMove(aid.source, srcCh, tgtCh,
                                            movePatchWithChannel,
                                            shiftMixRackIOPortWithMoveInScenarioA);
                if (!shouldRestoreSocketBackedPreampForMove(tgtSource,
                                                            movePatchWithChannel,
                                                            shiftMixRackIOPortWithMoveInScenarioA))
                    continue;
                int socketNum = -1;
                if (!getAnalogueSocketIndexForAudioSource(tgtSource, socketNum)) continue;
                logPreampSocketClaim("planned moved",
                                     (uint32_t)socketNum,
                                     (char)('A' + activeInputSource - 1),
                                     srcCh, tgtCh,
                                     tgtSource,
                                     aid.preampData);
                if (!checkPlannedWrite((uint32_t)socketNum, srcCh, tgtCh,
                                       (char)('A' + activeInputSource - 1),
                                       tgtSource, aid.preampData)) {
                    restoreAffectedGangs("Phase: restore input ganging after abort", false);
                    return false;
                }
            }
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
                        remapDyn8SideChainRef(xfer.dyn8Data,
                                              sizeof(xfer.dyn8Data),
                                              plan,
                                              "[MC] preserve ",
                                              tgtCh,
                                              dynIdx);
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
    fprintf(stderr, "[MC] Writing patching (%s; MixRack I/O Port: %s)...\n",
            patchPolicy, ioPortPolicy);
        bool disablePatchMetadataSync = envFlagEnabled("MC_DISABLE_PATCH_METADATA_SYNC");
        fprintf(stderr,
                "[MC]   Patch metadata sync after SetInputChannelSource: %s\n",
                disablePatchMetadataSync ? "DISABLED by MC_DISABLE_PATCH_METADATA_SYNC" : "enabled");
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
            PatchData tgtPatch = getEffectiveTargetPatchData(&plan, snaps[si].patchData, srcCh, tgtCh,
                                                             movePatchWithChannel,
                                                             shiftMixRackIOPortWithMoveInScenarioA);
            PatchData matePatch = {};
            bool haveMatePatch = false;

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

            void* sendPtA = audioSourceIsUnassigned(src)
                ? getUnassignedInputSendPoint()
                : getSendPoint(g_audioSRPManager, src.type, (uint16_t)src.number);
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
                    matePatch = getEffectiveTargetPatchData(
                        &plan, snaps[mateSnapIdx].patchData, mateSrcCh, pairMateCh,
                        movePatchWithChannel, shiftMixRackIOPortWithMoveInScenarioA);
                    haveMatePatch = true;
                    sAudioSource& mateSrc = matePatch.source;
                    sendPtB = audioSourceIsUnassigned(mateSrc)
                        ? getUnassignedInputSendPoint()
                        : getSendPoint(g_audioSRPManager, mateSrc.type, (uint16_t)mateSrc.number);
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

            fprintf(stderr, "[MC]   Apply patch on ch %d via SetInputChannelSource\n", tgtCh + 1);
            setInputSource(ch, 1, sendPtA, sendPtB);
            // Keep channel-mapper metadata aligned with the applied send points so
            // Director and the reorder panel show the correct source family.
            if (disablePatchMetadataSync) {
                fprintf(stderr,
                        "[MC]   Metadata patch sync skipped on ch %d after SetInputChannelSource\n",
                        tgtCh + 1);
                if (tgtStereo && haveMatePatch) {
                    int pairMateCh = tgtCh + 1;
                    fprintf(stderr,
                            "[MC]   Metadata patch sync skipped on stereo mate ch %d after SetInputChannelSource\n",
                            pairMateCh + 1);
                }
            } else {
                if (!writePatchData(tgtCh, tgtPatch)) {
                    fprintf(stderr,
                            "[MC]   WARN: metadata patch sync failed on ch %d after SetInputChannelSource\n",
                            tgtCh + 1);
                } else {
                    fprintf(stderr,
                            "[MC]   Metadata patch sync applied on ch %d after SetInputChannelSource\n",
                            tgtCh + 1);
                }
                if (tgtStereo && haveMatePatch) {
                    int pairMateCh = tgtCh + 1;
                    if (!writePatchData(pairMateCh, matePatch)) {
                        fprintf(stderr,
                                "[MC]   WARN: metadata patch sync failed on stereo mate ch %d after SetInputChannelSource\n",
                                pairMateCh + 1);
                    } else {
                        fprintf(stderr,
                                "[MC]   Metadata patch sync applied on stereo mate ch %d after SetInputChannelSource\n",
                                pairMateCh + 1);
                    }
                }
            }
            fprintf(stderr, "[MC]   Patch applied on ch %d\n", tgtCh + 1);
            QApplication::processEvents();
            usleep(25 * 1000);
            QApplication::processEvents();
        }
        fprintf(stderr, "[MC]   Patching applied via SetInputChannelSource.\n");
    phase("Phase: restore preamp sockets");
    for (auto& [tgtCh, si] : plan.targetMap) {
        if (!snaps[si].validPreamp || !snaps[si].validPatch) continue;
        int srcCh = lo + si;
        PatchData tgtPatch = getEffectiveTargetPatchData(&plan, snaps[si].patchData, srcCh, tgtCh,
                                                         movePatchWithChannel,
                                                         shiftMixRackIOPortWithMoveInScenarioA);
        if (!shouldRestorePatchedPreampForMove(tgtPatch,
                                               movePatchWithChannel,
                                               shiftMixRackIOPortWithMoveInScenarioA)) {
            fprintf(stderr,
                    "[MC]   Skip preamp restore on ch %d; socket-backed preamp stays with channel for source {type=%u,num=%u}\n",
                    tgtCh + 1, tgtPatch.source.type, tgtPatch.source.number);
            continue;
        }
        int socketNum = -1;
        if (!patchDataUsesSocketBackedPreamp(tgtPatch) ||
            !getAnalogueSocketIndexForAudioSource(tgtPatch.source, socketNum))
            continue;
        logPreampSocketClaim("restore main",
                             (uint32_t)socketNum,
                             'M',
                             srcCh, tgtCh,
                             tgtPatch.source,
                             snaps[si].preampData);
        if (writePreampDataForPatch(tgtPatch, snaps[si].preampData)) {
            fprintf(stderr,
                    "[MC]   Restore preamp for ch %d on socket %u: gain=%d pad=%d phantom=%d\n",
                    tgtCh + 1, (unsigned)socketNum,
                    snaps[si].preampData.gain, snaps[si].preampData.pad, snaps[si].preampData.phantom);
            PreampData readback = {};
            if (readPreampDataForPatch(tgtPatch, readback)) {
                fprintf(stderr,
                        "[MC][PREAMP] restore main readback ch %d socket %u: gain=%d pad=%d phantom=%d\n",
                        tgtCh + 1, (unsigned)socketNum,
                        readback.gain, readback.pad, readback.phantom);
            }
        } else {
            fprintf(stderr,
                    "[MC]   WARN: preamp restore failed for ch %d on socket %u\n",
                    tgtCh + 1, (unsigned)socketNum);
        }
    }
    refreshVisiblePreampUI("[MC] post-main-preamp: ");

    phase("Phase: restore ABCD source setup");
    typedef void (*fn_SetActiveInputChannel)(void* channel, uint8_t activeInputSource);
    auto setActiveInputChannel = (fn_SetActiveInputChannel)RESOLVE(0x1006d7fe0);
    for (auto& [tgtCh, si] : plan.targetMap) {
        if (!snaps[si].abcdEnabled) {
            fprintf(stderr,
                    "[MC]   Skip ABCD source restore on ch %d; ABCD disabled in snapshot\n",
                    tgtCh + 1);
            continue;
        }
        bool tgtStereo = isChannelStereo(tgtCh);
        if (tgtStereo && (tgtCh & 1)) {
            fprintf(stderr,
                    "[MC]   ABCD ch %d skipped; stereo pair handled by ch %d\n",
                    tgtCh + 1, tgtCh);
            continue;
        }

        void* ch = getChannel ? getChannel(g_channelManager, 1/*Input*/, (uint8_t)tgtCh) : nullptr;
        if (!ch || !getSendPoint || !setInputSource) {
            fprintf(stderr, "[MC]   WARN: ABCD restore unavailable for ch %d\n", tgtCh + 1);
            continue;
        }

        int srcCh = lo + si;
        int pairMateCh = tgtCh + 1;
        int mateSnapIdx = -1;
        if (tgtStereo) {
            for (auto& [mappedTgtCh, mappedSi] : plan.targetMap) {
                if (mappedTgtCh == pairMateCh) {
                    mateSnapIdx = mappedSi;
                    break;
                }
            }
        }

        for (int activeInputSource = 1; activeInputSource <= 4; activeInputSource++) {
            const auto& aid = snaps[si].activeInputData[activeInputSource - 1];
            void* sendPtA = nullptr;
            void* sendPtB = nullptr;
            const char slotName = (char)('A' + activeInputSource - 1);

            if (aid.assigned) {
                sAudioSource tgtSource =
                    remapAudioSourceForMove(aid.source, srcCh, tgtCh,
                                            movePatchWithChannel,
                                            shiftMixRackIOPortWithMoveInScenarioA);
                sendPtA = audioSourceIsUnassigned(tgtSource)
                    ? getUnassignedInputSendPoint()
                    : getSendPoint(g_audioSRPManager, tgtSource.type, (uint16_t)tgtSource.number);
                fprintf(stderr,
                        "[MC]   Restore ABCD-%c ch %d: A={type=%u,num=%u}->%p\n",
                        slotName, tgtCh + 1,
                        tgtSource.type, tgtSource.number, sendPtA);
            } else {
                sendPtA = getUnassignedInputSendPoint();
                fprintf(stderr,
                        "[MC]   Restore ABCD-%c ch %d: A=Unassigned->%p\n",
                        slotName, tgtCh + 1, sendPtA);
            }

            if (tgtStereo && mateSnapIdx >= 0) {
                int mateSrcCh = lo + mateSnapIdx;
                const auto& mateAid = snaps[mateSnapIdx].activeInputData[activeInputSource - 1];
                if (mateAid.assigned) {
                    sAudioSource mateSource =
                        remapAudioSourceForMove(mateAid.source, mateSrcCh, pairMateCh,
                                                movePatchWithChannel,
                                                shiftMixRackIOPortWithMoveInScenarioA);
                    sendPtB = audioSourceIsUnassigned(mateSource)
                        ? getUnassignedInputSendPoint()
                        : getSendPoint(g_audioSRPManager, mateSource.type, (uint16_t)mateSource.number);
                    fprintf(stderr,
                            "[MC]   Restore ABCD-%c ch %d+%d: B={type=%u,num=%u}->%p\n",
                            slotName, tgtCh + 1, pairMateCh + 1,
                            mateSource.type, mateSource.number, sendPtB);
                } else {
                    sendPtB = getUnassignedInputSendPoint();
                    fprintf(stderr,
                            "[MC]   Restore ABCD-%c ch %d+%d: B=Unassigned->%p\n",
                            slotName, tgtCh + 1, pairMateCh + 1, sendPtB);
                }
            }

            if (!sendPtA || (tgtStereo && mateSnapIdx >= 0 && !sendPtB)) {
                fprintf(stderr,
                        "[MC]   WARN: ABCD-%c unresolved send point on ch %d%s; skipping apply\n",
                        slotName, tgtCh + 1,
                        (tgtStereo && mateSnapIdx >= 0) ? " stereo pair" : "");
                continue;
            }

            fprintf(stderr, "[MC]   Apply ABCD-%c on ch %d via SetInputChannelSource\n",
                    slotName, tgtCh + 1);
            setInputSource(ch, activeInputSource, sendPtA, sendPtB);
            fprintf(stderr, "[MC]   ABCD-%c applied on ch %d\n",
                    slotName, tgtCh + 1);
            QApplication::processEvents();
        }
    }

    phase("Phase: restore ABCD preamp sockets");
    for (auto& [tgtCh, si] : plan.targetMap) {
        int srcCh = lo + si;
        if (!snaps[si].abcdEnabled) {
            fprintf(stderr,
                    "[MC]   Skip ABCD preamp restore on ch %d; ABCD disabled in snapshot\n",
                    tgtCh + 1);
            continue;
        }
        for (int activeInputSource = 1; activeInputSource <= 4; activeInputSource++) {
            const auto& aid = snaps[si].activeInputData[activeInputSource - 1];
            if (!aid.assigned || !aid.validPreamp) continue;
            sAudioSource tgtSource =
                remapAudioSourceForMove(aid.source, srcCh, tgtCh,
                                        movePatchWithChannel,
                                        shiftMixRackIOPortWithMoveInScenarioA);
            if (!shouldRestoreSocketBackedPreampForMove(tgtSource,
                                                        movePatchWithChannel,
                                                        shiftMixRackIOPortWithMoveInScenarioA)) {
                fprintf(stderr,
                        "[MC]   Skip ABCD-%c preamp restore on ch %d; socket-backed preamp stays with channel for source {type=%u,num=%u}\n",
                        'A' + activeInputSource - 1, tgtCh + 1, tgtSource.type, tgtSource.number);
                continue;
            }
            PreampData tgtPreamp = aid.preampData;
            int socketNum = -1;
            if (!getAnalogueSocketIndexForAudioSource(tgtSource, socketNum)) continue;
            logPreampSocketClaim("restore abcd",
                                 (uint32_t)socketNum,
                                 (char)('A' + activeInputSource - 1),
                                 srcCh, tgtCh,
                                 tgtSource,
                                 tgtPreamp);
            fprintf(stderr,
                    "[MC]   ABCD-%c preamp begin ch %d: source={type=%u,num=%u} socket=%u\n",
                    'A' + activeInputSource - 1, tgtCh + 1,
                    tgtSource.type, tgtSource.number, (unsigned)socketNum);
            if (writePreampDataForAudioSource(tgtSource, tgtPreamp)) {
                fprintf(stderr,
                        "[MC]   Restore ABCD-%c preamp for ch %d on socket %u: gain=%d pad=%d phantom=%d\n",
                        'A' + activeInputSource - 1, tgtCh + 1, (unsigned)socketNum,
                        tgtPreamp.gain, tgtPreamp.pad, tgtPreamp.phantom);
                PreampData readback = {};
                if (readPreampDataForAudioSource(tgtSource, readback)) {
                    fprintf(stderr,
                            "[MC][PREAMP] restore abcd readback ch %d socket %u: gain=%d pad=%d phantom=%d\n",
                            tgtCh + 1, (unsigned)socketNum,
                            readback.gain, readback.pad, readback.phantom);
                }
            } else {
                fprintf(stderr,
                    "[MC]   WARN: ABCD-%c preamp restore failed for ch %d on socket %u\n",
                        'A' + activeInputSource - 1, tgtCh + 1, (unsigned)socketNum);
            }
        }
    }
    refreshVisiblePreampUI("[MC] post-abcd-preamp: ");

    phase("Phase: restore ABCD selection");
    for (auto& [tgtCh, si] : plan.targetMap) {
        void* ch = getChannel ? getChannel(g_channelManager, 1/*Input*/, (uint8_t)tgtCh) : nullptr;
        if (!ch || !setActiveInputChannel) continue;
        uint8_t selectedSource = snaps[si].activeInputSource;
        setActiveInputChannel(ch, selectedSource);
        fprintf(stderr,
                "[MC]   Restore ABCD selection ch %d: enabled=%d active=%u\n",
                tgtCh + 1, snaps[si].abcdEnabled ? 1 : 0, selectedSource);
    }

    auto replayDyn8Settings = [&](const char* phaseTag) {
        if (dyn8Transfers.empty()) return;

        fprintf(stderr, "[MC] Dyn8 system-level transfer phase '%s' (%zu entries)...\n",
                phaseTag, dyn8Transfers.size());
        typedef void (*fn_setAllDataUI)(void* obj, void* sDynData);
        auto setAllDataUI = (fn_setAllDataUI)RESOLVE(0x100239970);
        typedef void (*fn_setDynData)(void* system, void* key, void* data);
        auto setDynData = (fn_setDynData)RESOLVE(0x100239240);
        typedef void (*fn_setFullSideChainData)(void* system, void* key, void* data);
        auto setFullSideChainData = (fn_setFullSideChainData)RESOLVE(0x10023a4e0);
        typedef void (*fn_setDynObjSideChainSource)(void* obj, void* msg);
        auto setDynObjSideChainSource = (fn_setDynObjSideChainSource)RESOLVE(0x10023a490);
        typedef void (*fn_fullDriverUpdate)(void* system);
        auto fullDriverUpdate = (fn_fullDriverUpdate)RESOLVE(0x10023c6c0);
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
                if (setFullSideChainData) {
                    setFullSideChainData(dynSystem, dynKey, xfer.dyn8Data);
                    fprintf(stderr, "[MC]   [%s] SetFullSideChainData done\n", phaseTag);
                }
                uint8_t one = 1;
                safeWrite((uint8_t*)dynSystem + 0xca9, &one, 1);
                fullDriverUpdate(dynSystem);
                fprintf(stderr, "[MC]   [%s] SetDynamicsData + FullDriverUpdate done\n", phaseTag);
            } else {
                fprintf(stderr, "[MC]   [%s] WARNING: cDynamicsSystem is null!\n", phaseTag);
            }

            if (setDynObjSideChainSource && msgCtor && msgDtor && setLen && packSC) {
                uint8_t scMsg[64];
                memset(scMsg, 0, sizeof(scMsg));
                msgCtor(scMsg);
                setLen(scMsg, 0xa);
                packSC(scMsg, xfer.dyn8Data, 0);
                setDynObjSideChainSource(tgtDynObj, scMsg);
                msgDtor(scMsg);
                fprintf(stderr, "[MC]   [%s] Dyn8 unit %d: SetSideChainSource applied on net object\n",
                        phaseTag, xfer.tgtUnitIdx);
            }

            void* duc = getDynUnitClient(xfer.tgtUnitIdx);
            if (duc) {
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
        for (auto& [tgtCh, si] : plan.targetMap) {
            fprintf(stderr, "[MC] Final stabilize recall '%s' → pos %d\n", snaps[si].name, tgtCh + 1);
            recallChannel(tgtCh, snaps[si], skipPreamp);
        }
        waitForStereoConfigReset();
        waitForStereoConfigReset();
        for (auto& [tgtCh, si] : plan.targetMap) {
            writeProcOrderForChannel(tgtCh, snaps[si]);
        }
        waitForStereoConfigReset();
        for (auto& [tgtCh, si] : plan.targetMap) {
            replayMixerStateForChannel(tgtCh, snaps[si], "post-final-mixer-assigns");
            replayMuteGroupsForChannel(tgtCh, snaps[si], "post-final-mute-groups");
            replayStereoImageForChannel(tgtCh, snaps[si], "post-final-stereo-image");
            waitForStereoConfigReset();
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
            logMixerAssignmentSummary("[post-final-stabilize] live", tgtCh, live.mixerData);
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

    if (!externalSidechainRemaps.empty()) {
        phase("Phase: update external sidechain references");
        std::vector<int> refreshedChannels;
        for (const auto& fix : externalSidechainRemaps) {
            void* inputCh = getInputChannel(fix.ch);
            if (!inputCh) continue;
            void* obj = getTypeBObj(inputCh, g_procB[fix.procIdx]);
            if (!obj) continue;
            writeSidechainRef(obj, fix.procIdx, fix.ch, fix.stripType, fix.newChannel,
                              "External SC-Write ");
            if (std::find(refreshedChannels.begin(), refreshedChannels.end(), fix.ch) == refreshedChannels.end())
                refreshedChannels.push_back(fix.ch);
        }
        for (int ch : refreshedChannels) {
            refreshSideChainStateForChannel(ch, "post-external-sidechain-refresh");
            QApplication::processEvents();
        }
    }

    restoreAffectedGangs("Phase: restore input ganging", true);

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
        logFinalPreampStateForChannel(i);
    }
    refreshVisiblePreampUI("[MC] final-preamp: ");
    scheduleWestPreampGainPushForCurrentSelection("[MC] final-preamp: ");

    if (autotestEnvEnabled("MC_EXPERIMENT_RECALL_CURRENT_SETTINGS")) {
        phase("Phase: scene refresh experiment");
        fprintf(stderr,
                "[MC] scene refresh experiment: invoking RecallCurrentSettings via scene client\n");
        recallCurrentSettingsViaSceneClient();
        waitForSceneRecall();
        fprintf(stderr, "[MC] === Verify after scene refresh experiment ===\n");
        for (int i = lo; i <= hi; i++) {
            logFinalPreampStateForChannel(i);
        }
        refreshVisiblePreampUI("[MC] post-scene-refresh: ");
    }

    if (autotestEnvEnabled("MC_EXPERIMENT_SCENE_UI_SIGNAL")) {
        phase("Phase: scene UI signal experiment");
        fprintf(stderr,
                "[MC] scene UI signal experiment: emitting SceneCurrentSettingsRecalled on scene client\n");
        emitSceneCurrentSettingsRecalledSignal();
        QApplication::processEvents();
        usleep(500 * 1000);
        QApplication::processEvents();
        fprintf(stderr, "[MC] === Verify after scene UI signal experiment ===\n");
        for (int i = lo; i <= hi; i++) {
            logFinalPreampStateForChannel(i);
        }
        refreshVisiblePreampUI("[MC] post-scene-ui-signal: ");
    }

    phase("Phase: move complete");
    return true;
}

static bool moveChannel(int src, int dst, bool movePatchWithChannel = false,
                        bool shiftMixRackIOPortWithMoveInScenarioA = false,
                        int requestedBlockSize = 1) {
    MovePlan plan;
    char planErr[256];
    if (!buildMovePlan(src, dst, requestedBlockSize, plan, planErr, sizeof(planErr))) {
        fprintf(stderr, "[MC] Unsupported move: %s\n", planErr[0] ? planErr : "unknown error");
        return false;
    }

    if (plan.srcStart == plan.dstStart) {
        fprintf(stderr, "[MC] Same position after normalization, nothing to do.\n");
        return true;
    }

    return applyMovePlan(plan, movePatchWithChannel,
                         shiftMixRackIOPortWithMoveInScenarioA,
                         "block move");
}

// Forward declarations for UI
static void dumpChannelData(int ch, const char* label);
struct MoveConflictInfo;
static void clearLastMoveConflict();
static void setScenarioAPreampConflict(uint32_t socketNum,
                                       char existingSourceLabel, int existingSrcCh, int existingTgtCh,
                                       const PreampData& existingData,
                                       char newSourceLabel, int newSrcCh, int newTgtCh,
                                       const PreampData& newData);
static bool takeLastMoveConflict(MoveConflictInfo& out);

// =============================================================================
// UI Dialog
// =============================================================================
static QDialog* g_dialog = nullptr;
static QDialog* g_reorderDialog = nullptr;
static id g_moveShortcutMonitor = nil;
static QPushButton* g_toolbarReorderButton = nullptr;
static QTimer* g_toolbarButtonRefreshTimer = nullptr;
static QTimer* g_autotestOverlayStatusTimer = nullptr;
static QTimer* g_westPreampSyncTimer = nullptr;
static QPointer<QFrame> g_autotestOverlayFrame = nullptr;
static QPointer<QLabel> g_autotestOverlayTitle = nullptr;
static QPointer<QLabel> g_autotestOverlayDetail = nullptr;
static QString g_autotestOverlayStatusPath;
static QString g_lastAutotestOverlayStatusText;
static int g_westPreampSyncLastChannel = -2;
static int g_westPreampSyncLastSocket = -2;
static int g_westPreampSyncLastGain = INT32_MIN;
static int g_westPreampSyncLastPad = -1;
static int g_westPreampSyncLastPhantom = -1;
static int g_westPreampSyncLastForms = -1;

static bool shouldShowAutotestOverlay() {
    return getenv("MC_AUTOTEST_SELECT_ONLY") ||
           (getenv("MC_AUTOTEST_SRC") && getenv("MC_AUTOTEST_DST")) ||
           (getenv("MC_AUTOTEST_COPY_SRC") && getenv("MC_AUTOTEST_COPY_DST"));
}

static bool westPreampSyncEnabled() {
    const char* env = getenv("MC_ENABLE_WEST_PREAMP_SYNC");
    return env && atoi(env) != 0;
}

static bool westPreampGainPushEnabled() {
    const char* env = getenv("MC_DISABLE_WEST_GAIN_PUSH");
    return !(env && atoi(env) != 0);
}

static QWidget* getLargestVisibleAutotestWindow() {
    QWidget* best = nullptr;
    int bestArea = -1;
    const auto topLevels = QApplication::topLevelWidgets();
    for (QWidget* widget : topLevels) {
        if (!widget || !widget->isVisible())
            continue;
        if (qobject_cast<QDialog*>(widget))
            continue;
        if (widget->width() < 400 || widget->height() < 250)
            continue;
        int area = widget->width() * widget->height();
        if (widget->findChild<QObject*>("mainQmlWidget", Qt::FindChildrenRecursively))
            area += 100000000;
        if (area > bestArea) {
            best = widget;
            bestArea = area;
        }
    }
    return best;
}

static QWidget* getAutotestOverlayHost() {
    QWidget* host = QApplication::activeWindow();
    if (host && host->isVisible() && !qobject_cast<QDialog*>(host))
        return host;
    return getLargestVisibleAutotestWindow();
}

static void ensureAutotestOverlay(QWidget* host) {
    if (!host)
        return;
    if (!g_autotestOverlayFrame || g_autotestOverlayFrame->parentWidget() != host) {
        if (g_autotestOverlayFrame)
            g_autotestOverlayFrame->deleteLater();
        auto* frame = new QFrame(host);
        frame->setObjectName("mcAutotestOverlay");
        frame->setAttribute(Qt::WA_ShowWithoutActivating, true);
        frame->setFrameShape(QFrame::StyledPanel);
        frame->setStyleSheet(
            "#mcAutotestOverlay {"
            "background: rgba(12, 16, 22, 220);"
            "border: 2px solid rgba(0, 196, 255, 180);"
            "border-radius: 10px;"
            "}"
        );
        auto* layout = new QVBoxLayout(frame);
        layout->setContentsMargins(12, 10, 12, 10);
        layout->setSpacing(4);
        auto* title = new QLabel(frame);
        title->setStyleSheet("color: white; font-size: 16px; font-weight: 700;");
        auto* detail = new QLabel(frame);
        detail->setStyleSheet("color: rgba(255,255,255,210); font-size: 12px;");
        detail->setWordWrap(true);
        layout->addWidget(title);
        layout->addWidget(detail);
        g_autotestOverlayFrame = frame;
        g_autotestOverlayTitle = title;
        g_autotestOverlayDetail = detail;
    }
}

static void positionAutotestOverlay() {
    if (!g_autotestOverlayFrame)
        return;
    QWidget* host = g_autotestOverlayFrame->parentWidget();
    if (!host)
        return;
    const int overlayWidth = std::min(420, std::max(300, host->width() / 3));
    g_autotestOverlayFrame->resize(overlayWidth, g_autotestOverlayFrame->sizeHint().height());
    const int x = std::max(12, host->width() - g_autotestOverlayFrame->width() - 18);
    const int y = std::max(56, host->height() - g_autotestOverlayFrame->height() - 18);
    g_autotestOverlayFrame->move(x, y);
}

static void updateAutotestOverlay(const QString& title, const QString& detail) {
    if (!shouldShowAutotestOverlay())
        return;
    QWidget* host = getAutotestOverlayHost();
    if (!host) {
        fprintf(stderr, "[MC][AUTOTEST] overlay host unavailable for title='%s'\n",
                title.toUtf8().constData());
        return;
    }
    ensureAutotestOverlay(host);
    if (!g_autotestOverlayFrame)
        return;
    g_autotestOverlayTitle->setText(title);
    g_autotestOverlayDetail->setText(detail);
    g_autotestOverlayDetail->setVisible(!detail.isEmpty());
    g_autotestOverlayFrame->adjustSize();
    positionAutotestOverlay();
    g_autotestOverlayFrame->show();
    g_autotestOverlayFrame->raise();
    fprintf(stderr,
            "[MC][AUTOTEST] overlay shown on host='%s' size=%dx%d title='%s' detail='%s'\n",
            host->objectName().toUtf8().constData(),
            host->width(),
            host->height(),
            title.toUtf8().constData(),
            detail.toUtf8().constData());
    QApplication::processEvents();
}

static void hideAutotestOverlay() {
    if (g_autotestOverlayFrame)
        g_autotestOverlayFrame->hide();
}

static void pollAutotestOverlayStatusFile() {
    if (g_autotestOverlayStatusPath.isEmpty())
        return;
    QFile file(g_autotestOverlayStatusPath);
    if (!file.exists())
        return;
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text))
        return;
    QString text = QString::fromUtf8(file.readAll());
    file.close();
    if (text == g_lastAutotestOverlayStatusText)
        return;
    g_lastAutotestOverlayStatusText = text;
    QString trimmed = text.trimmed();
    if (trimmed.isEmpty()) {
        hideAutotestOverlay();
        return;
    }
    QStringList lines = trimmed.split('\n');
    QString title = lines.isEmpty() ? QString("dLive Self-Test") : lines.takeFirst().trimmed();
    QString detail = lines.join("\n").trimmed();
    updateAutotestOverlay(title.isEmpty() ? QString("dLive Self-Test") : title, detail);
}

struct MoveConflictInfo {
    bool active = false;
    QString title;
    QString summary;
    QString details;
};

static MoveConflictInfo g_lastMoveConflict;

static void clearLastMoveConflict() {
    g_lastMoveConflict = MoveConflictInfo();
}

static QString sourceLabelForConflict(char sourceLabel) {
    if (sourceLabel == 'M')
        return "Main patch";
    if (sourceLabel >= 'A' && sourceLabel <= 'D')
        return QString("ABCD %1").arg(QChar(sourceLabel));
    return QString("Source %1").arg(QChar(sourceLabel));
}

static QString boolLabelForConflict(int value, const char* falseText = "Off", const char* trueText = "On") {
    return value ? QString::fromUtf8(trueText) : QString::fromUtf8(falseText);
}

static QString channelNameForConflict(int ch) {
    if (!g_audioDM || !g_getChannelName || ch < 0 || ch >= 128)
        return QString();
    const char* raw = g_getChannelName(g_audioDM, 1, (uint8_t)ch);
    if (!raw || !*raw)
        return QString();
    return QString::fromUtf8(raw);
}

static void setScenarioAPreampConflict(uint32_t socketNum,
                                       char existingSourceLabel, int existingSrcCh, int existingTgtCh,
                                       const PreampData& existingData,
                                       char newSourceLabel, int newSrcCh, int newTgtCh,
                                       const PreampData& newData) {
    QString existingName = channelNameForConflict(existingSrcCh);
    QString newName = channelNameForConflict(newSrcCh);

    auto formatChannelRef = [](int srcCh, int tgtCh, const QString& name) {
        QString ref = (srcCh == tgtCh)
            ? QString("ch %1").arg(srcCh + 1)
            : QString("ch %1 -> %2").arg(srcCh + 1).arg(tgtCh + 1);
        if (!name.isEmpty())
            ref += QString(" (\"%1\")").arg(name);
        return ref;
    };

    QString summary =
        QString("Scenario A would make multiple input paths share analogue socket %1, "
                "but they request different preamp values.")
            .arg(socketNum);

    QString details =
        QString(
            "<p><b>Conflicting socket:</b> %1</p>"
            "<table cellspacing='0' cellpadding='5' border='1' style='border-collapse:collapse;'>"
            "<tr>"
            "<th align='left'>Path</th>"
            "<th align='left'>Channel</th>"
            "<th align='left'>Socket</th>"
            "<th align='left'>Gain</th>"
            "<th align='left'>Pad</th>"
            "<th align='left'>Phantom</th>"
            "</tr>"
            "<tr>"
            "<td>%2</td>"
            "<td>%3</td>"
            "<td>%4</td>"
            "<td>%5</td>"
            "<td>%6</td>"
            "<td>%7</td>"
            "</tr>"
            "<tr>"
            "<td>%8</td>"
            "<td>%9</td>"
            "<td>%10</td>"
            "<td>%11</td>"
            "<td>%12</td>"
            "<td>%13</td>"
            "</tr>"
            "</table>"
            "<p><b>How to fix it:</b></p>"
            "<p>1. Try <b>Scenario B</b> (move preamp socket with channel) instead of Scenario A.<br/>"
            "2. Or change the channel's main / ABCD input setup so these paths do not land on the same socket.<br/>"
            "3. Or make both paths use the same preamp values, then try again.</p>")
            .arg(socketNum)
            .arg(sourceLabelForConflict(existingSourceLabel).toHtmlEscaped())
            .arg(formatChannelRef(existingSrcCh, existingTgtCh, existingName).toHtmlEscaped())
            .arg(socketNum)
            .arg(existingData.gain)
            .arg(boolLabelForConflict(existingData.pad, "Off", "On").toHtmlEscaped())
            .arg(boolLabelForConflict(existingData.phantom, "Off", "On").toHtmlEscaped())
            .arg(sourceLabelForConflict(newSourceLabel).toHtmlEscaped())
            .arg(formatChannelRef(newSrcCh, newTgtCh, newName).toHtmlEscaped())
            .arg(socketNum)
            .arg(newData.gain)
            .arg(boolLabelForConflict(newData.pad, "Off", "On").toHtmlEscaped())
            .arg(boolLabelForConflict(newData.phantom, "Off", "On").toHtmlEscaped());

    g_lastMoveConflict.active = true;
    g_lastMoveConflict.title = "Scenario A Socket Conflict";
    g_lastMoveConflict.summary = summary;
    g_lastMoveConflict.details = details;
}

static bool takeLastMoveConflict(MoveConflictInfo& out) {
    if (!g_lastMoveConflict.active)
        return false;
    out = g_lastMoveConflict;
    clearLastMoveConflict();
    return true;
}

static QString widgetTextProperty(QWidget* widget);
static double objectNumericProperty(QObject* obj, const char* name, double fallback);
static constexpr uint64_t kShortcutSelectionFallbackWindowMs = 1000;
static constexpr uint64_t kCopyPasteShortcutDebounceMs = 250;
static constexpr uint64_t kPointerSelectionSettleWindowMs = 350;
static constexpr int kPointerSelectionSettleDelayMs = 60;
static constexpr int kPointerSelectionSettlePollAttempts = 5;
struct CopyPasteBuffer {
    bool valid = false;
    bool stereo = false;
    int blockSize = 0;
    int srcStart = -1;
    ChannelSnapshot snaps[2];
};
static CopyPasteBuffer g_copyBuffer;
static bool shouldCaptureCopyPasteShortcut();
static void showReorderDialog();

static QString formatMoveProgressLabel(const char* phase) {
    QString text = phase ? QString::fromUtf8(phase) : QString("Working...");
    if (text.startsWith("Phase: "))
        text = text.mid(7);
    return QString("Moving channels...\n%1").arg(text);
}

template <typename Fn>
static bool runMoveWithProgressDialog(QWidget* parent, const QString& initialLabel, Fn&& fn) {
    QProgressDialog progress(parent);
    progress.setWindowTitle("Moving Channels");
    progress.setLabelText(initialLabel);
    progress.setCancelButton(nullptr);
    progress.setMinimumDuration(0);
    progress.setRange(0, 0);
    progress.setWindowModality(Qt::ApplicationModal);
    progress.show();
    QApplication::processEvents();

    auto previousCallback = g_moveProgressCallback;
    g_moveProgressCallback = [&](const char* phase) {
        progress.setLabelText(formatMoveProgressLabel(phase));
        QApplication::processEvents();
    };

    bool ok = fn();

    g_moveProgressCallback = previousCallback;
    progress.close();
    QApplication::processEvents();
    return ok;
}

struct ReorderBlockEntry {
    int blockId = -1;
    int srcStart = -1;
    int width = 1;
    QString name;
    uint8_t colour = 0;
    bool stereo = false;
    bool validPatchA = false;
    PatchData patchDataA = {};
    bool validPatchB = false;
    PatchData patchDataB = {};
    bool hasPatchOverrideA = false;
    PatchData patchOverrideA = {};
    bool hasPatchOverrideB = false;
    PatchData patchOverrideB = {};
};

struct IllegalStereoPlacement {
    int row = -1;
    int targetStart = -1;
    int blockId = -1;
};

static QColor colorForChannelColourIndex(uint8_t colour) {
    QColor base;
    switch (colour & 0x7) {
        case 0: base = QColor(48, 48, 48);    break; // Black
        case 1: base = QColor(220, 35, 60);   break; // Red
        case 2: base = QColor(8, 170, 72);    break; // Green
        case 3: base = QColor(255, 236, 56);  break; // Yellow
        case 4: base = QColor(20, 86, 185);   break; // Blue
        case 5: base = QColor(186, 34, 176);  break; // Magenta
        case 6: base = QColor(25, 196, 207);  break; // Cyan
        case 7: base = QColor(242, 242, 242); break; // White
        default: base = QColor(242, 242, 242); break;
    }
    const int mix = 230; // about 90% original color, 10% white
    int r = (base.red()   * mix + 255 * (255 - mix)) / 255;
    int g = (base.green() * mix + 255 * (255 - mix)) / 255;
    int b = (base.blue()  * mix + 255 * (255 - mix)) / 255;
    return QColor(r, g, b);
}

static QColor textColorForChannelColourIndex(uint8_t colour) {
    switch (colour & 0x7) {
        case 0: // Black
        case 1: // Red
        case 4: // Blue
        case 5: // Magenta
            return QColor(255, 255, 255);
        default:
            return QColor(44, 44, 48);
    }
}

struct ChannelColorOption {
    uint8_t index;
    const char* name;
};

static const ChannelColorOption kChannelColorOptions[] = {
    {7, "White"},
    {1, "Red"},
    {2, "Green"},
    {3, "Yellow"},
    {4, "Blue"},
    {5, "Magenta"},
    {6, "Cyan"},
    {0, "Black"},
};

static QString formatAudioSourceLabel(const sAudioSource& source) {
    switch (source.type) {
        case 0: return "MixRack Sockets";
        case 1: return "MixRack DX1/2";
        case 2: return "MixRack I/O Port";
        case 3: return "MixRack DX3/4";
        case 5: return "MixRack I/O Port";
        default: return QString("Type %1").arg(source.type);
    }
}

static bool audioSourceIsUnassigned(const sAudioSource& source) {
    return source.type == 20 && source.number == 0;
}

static QString buildAudioSourceBankLabel(uint32_t sourceType);

static std::mutex g_audioSourceDescBuildMutex;

static QString buildAudioSourceDescriptionRaw(const sAudioSource& source) {
    if (audioSourceIsUnassigned(source))
        return "Unassigned";

    typedef QString (*fn_BuildAudioSourceDesc)(sAudioSource);
    auto buildDesc = (fn_BuildAudioSourceDesc)RESOLVE(0x100eb1840);
    if (buildDesc) {
        QString desc;
        {
            // Director logs "Unhandled Socket Type" on some probe calls; keep the
            // richer binary-backed names, but silence that specific stderr noise
            // while we are only asking it for display text.
            std::lock_guard<std::mutex> lock(g_audioSourceDescBuildMutex);
            int savedStderr = dup(STDERR_FILENO);
            int nullFd = open("/dev/null", O_WRONLY);
            if (savedStderr >= 0 && nullFd >= 0) {
                fflush(stderr);
                dup2(nullFd, STDERR_FILENO);
                desc = buildDesc(source);
                fflush(stderr);
                dup2(savedStderr, STDERR_FILENO);
                setvbuf(stderr, nullptr, _IOLBF, 0);
            } else {
                desc = buildDesc(source);
            }
            if (nullFd >= 0)
                close(nullFd);
            if (savedStderr >= 0)
                close(savedStderr);
        }
        if (!desc.isEmpty())
            return desc;
    }

    return QString();
}

static QString trimAudioSourceBankSuffix(QString desc) {
    struct Pattern {
        const char* marker;
    };
    static const Pattern patterns[] = {
        {": "},
        {", Input "},
        {", Output "},
        {" Number "},
    };

    for (const auto& pattern : patterns) {
        int pos = desc.lastIndexOf(pattern.marker);
        if (pos <= 0)
            continue;
        QString suffix = desc.mid(pos + (int)strlen(pattern.marker)).trimmed();
        bool ok = false;
        suffix.toInt(&ok);
        if (ok)
            return desc.left(pos).trimmed();
    }

    int spacePos = desc.lastIndexOf(' ');
    if (spacePos > 0) {
        QString suffix = desc.mid(spacePos + 1).trimmed();
        bool ok = false;
        suffix.toInt(&ok);
        if (ok)
            return desc.left(spacePos).trimmed();
    }

    return desc.trimmed();
}

static bool classNameContains(QObject* obj, const char* needle) {
    if (!obj || !needle || !*needle)
        return false;
    const QMetaObject* mo = obj->metaObject();
    if (!mo || !mo->className())
        return false;
    return QString::fromLatin1(mo->className()).contains(QString::fromLatin1(needle),
                                                         Qt::CaseInsensitive);
}

static QList<QObject*> collectShowManagerForms() {
    QList<QObject*> targets;
    auto addTarget = [&](QObject* obj) {
        if (!obj || targets.contains(obj))
            return;
        if (classNameContains(obj, "ShowManagerForm"))
            targets.push_back(obj);
    };

    if (qApp) {
        addTarget(qApp);
        for (QObject* obj : qApp->findChildren<QObject*>())
            addTarget(obj);
    }
    for (QWidget* widget : QApplication::allWidgets()) {
        addTarget(widget);
        for (QObject* obj : widget->findChildren<QObject*>())
            addTarget(obj);
    }
    return targets;
}

static bool createShowViaShowManagerClient(const QString& showName) {
    void* client = getShowManagerClientForCalls();
    if (!client) {
        fprintf(stderr,
                "[MC][SHOWSAVE] createShowViaShowManagerClient('%s'): no show manager client\n",
                showName.toUtf8().constData());
        return false;
    }

    typedef void (*fn_CreateShow)(void*, const MCShowKey*);
    auto createShow = (fn_CreateShow)RESOLVE(0x1007240f0);
    if (!createShow) {
        fprintf(stderr,
                "[MC][SHOWSAVE] cShowManagerClientBase::CreateShow not available\n");
        return false;
    }

    MCShowKey key;
    key.name = showName;
    key.location = 1; // user show location
    key.slot = 0;
    key.reserved = 0;
    key.aux = QString();
    fprintf(stderr,
            "[MC][SHOWSAVE] createShowViaShowManagerClient('%s'): loc=%d(%s) slot=%u aux='%s'\n",
            showName.toUtf8().constData(),
            key.location,
            showLocationName(key.location),
            (unsigned)key.slot,
            key.aux.toUtf8().constData());
    createShow(client, &key);
    QApplication::processEvents();
    return true;
}

static bool runArchiveCurrentShowExperiment() {
    const char* showEnv = getenv("MC_EXPERIMENT_ARCHIVE_SHOW_NAME");
    if (!showEnv || !*showEnv)
        return false;
    QString showName = QString::fromUtf8(showEnv).trimmed();
    if (showName.isEmpty())
        return false;

    updateAutotestOverlay("dLive Self-Test",
                          QString("Storing current settings for %1").arg(showName));
    fprintf(stderr,
            "[MC][SHOWSAVE] starting archive experiment for '%s'\n",
            showName.toUtf8().constData());

    if (!storeCurrentSettingsViaSceneClient())
        return false;
    waitForCurrentSettingsStored();

    updateAutotestOverlay("dLive Self-Test",
                          QString("Saving SHOW %1").arg(showName));
    if (!createShowViaShowManagerClient(showName)) {
        fprintf(stderr,
                "[MC][SHOWSAVE] createShowViaShowManagerClient failed\n");
        return false;
    }
    waitForShowArchived();
    updateAutotestOverlay("dLive Self-Test",
                          QString("SHOW saved %1").arg(showName));
    fprintf(stderr,
            "[MC][SHOWSAVE] archive experiment complete for '%s'\n",
            showName.toUtf8().constData());
    return true;
}

static bool objectLooksLikePreampUI(QObject* obj) {
    if (!obj)
        return false;
    if (classNameContains(obj, "Preamp"))
        return true;
    const QString name = obj->objectName();
    if (name.contains("Preamp", Qt::CaseInsensitive))
        return true;
    return false;
}

static QList<QWidget*> candidatePreampRefreshWindows() {
    QList<QWidget*> windows;
    auto addWindow = [&](QWidget* w) {
        if (!w || !w->isVisible())
            return;
        if (!windows.contains(w))
            windows.push_back(w);
    };

    addWindow(QApplication::activeWindow());
    if (QWidget* focus = QApplication::focusWidget())
        addWindow(focus->window());

    const QList<QWidget*> topLevels = QApplication::topLevelWidgets();
    for (QWidget* top : topLevels)
        addWindow(top);
    return windows;
}

static QList<QObject*> collectPreampRefreshTargets() {
    QList<QObject*> targets;
    auto addTarget = [&](QObject* obj) {
        if (!obj || targets.contains(obj))
            return;
        targets.push_back(obj);
    };

    auto maybeAdd = [&](QObject* obj) {
        if (!obj)
            return;
        if (classNameContains(obj, "InputChannelPreampForm") ||
            classNameContains(obj, "PreampOverviewForm") ||
            classNameContains(obj, "InputSourceAssignPanel")) {
            addTarget(obj);
        }
    };

    if (qApp) {
        maybeAdd(qApp);
        const QList<QObject*> appObjects = qApp->findChildren<QObject*>();
        for (QObject* obj : appObjects)
            maybeAdd(obj);
    }

    const QList<QWidget*> allWidgets = QApplication::allWidgets();
    for (QWidget* widget : allWidgets) {
        maybeAdd(widget);
        const QList<QObject*> children = widget->findChildren<QObject*>();
        for (QObject* obj : children)
            maybeAdd(obj);
    }

    return targets;
}

static void refreshVisiblePreampUIOnTargets(const QList<QObject*>& targets,
                                            const char* phaseTag) {
    if (!qApp)
        return;

    typedef void (*fn_PreampFormChangeChannel)(void*, void*);
    typedef void (*fn_PreampFormReceivePointUpdated)(void*, void*);
    typedef void (*fn_PreampFormInputChannelStartReceivePointUpdated)(void*, int, void*);
    typedef void (*fn_PreampFormUpdateToReceivePoint)(void*);
    typedef void (*fn_PreampFormUpdatePreampPanel)(void*);
    typedef void (*fn_SourceAssignPanelChangeChannel)(void*, void*);
    typedef void (*fn_SourceAssignPanelUpdateToReceivePoint)(void*);
    typedef void (*fn_PreampOverviewReceivePointUpdated)(void*, void*);
    typedef void (*fn_PreampOverviewUpdatePreamp)(void*);

    auto preampChangeChannel =
        (fn_PreampFormChangeChannel)RESOLVE(0x100a0c080);
    auto preampReceivePointUpdated =
        (fn_PreampFormReceivePointUpdated)RESOLVE(0x100a0f1e0);
    auto preampInputChannelStartReceivePointUpdated =
        (fn_PreampFormInputChannelStartReceivePointUpdated)RESOLVE(0x100a0d460);
    auto preampUpdateToReceivePoint =
        (fn_PreampFormUpdateToReceivePoint)RESOLVE(0x100a0fde0);
    auto preampUpdatePreampPanel =
        (fn_PreampFormUpdatePreampPanel)RESOLVE(0x100a10440);
    auto sourceAssignChangeChannel =
        (fn_SourceAssignPanelChangeChannel)RESOLVE(0x100a167a0);
    auto sourceAssignUpdateToReceivePoint =
        (fn_SourceAssignPanelUpdateToReceivePoint)RESOLVE(0x100a175a0);
    auto preampOverviewReceivePointUpdated =
        (fn_PreampOverviewReceivePointUpdated)RESOLVE(0x100a79170);
    auto preampOverviewUpdatePreamp =
        (fn_PreampOverviewUpdatePreamp)RESOLVE(0x100a79300);

    int selectedInputCh = getSelectedInputChannel(false);
    void* selectedChannelObj =
        (selectedInputCh >= 0) ? getInputChannel(selectedInputCh) : nullptr;
    int preampForms = 0;
    int sourceAssignPanels = 0;
    int overviewForms = 0;
    int actions = 0;
    for (QObject* obj : targets) {
        if (!obj)
            continue;

        if (classNameContains(obj, "InputChannelPreampForm")) {
            preampForms++;
            void* raw = obj;
            if (selectedChannelObj && preampChangeChannel) {
                preampChangeChannel(raw, selectedChannelObj);
                actions++;
            }
            if (selectedChannelObj && preampReceivePointUpdated) {
                preampReceivePointUpdated(raw, selectedChannelObj);
                actions++;
            }
            if (selectedChannelObj && preampInputChannelStartReceivePointUpdated) {
                for (int activeInput = 1; activeInput <= 4; ++activeInput) {
                    preampInputChannelStartReceivePointUpdated(raw, activeInput,
                                                               selectedChannelObj);
                    actions++;
                }
            }
            if (preampUpdateToReceivePoint) {
                preampUpdateToReceivePoint(raw);
                actions++;
            }
            if (preampUpdatePreampPanel) {
                preampUpdatePreampPanel(raw);
                actions++;
            }
            continue;
        }

        if (classNameContains(obj, "InputSourceAssignPanel")) {
            sourceAssignPanels++;
            void* raw = obj;
            if (selectedChannelObj && sourceAssignChangeChannel) {
                sourceAssignChangeChannel(raw, selectedChannelObj);
                actions++;
            }
            if (sourceAssignUpdateToReceivePoint) {
                sourceAssignUpdateToReceivePoint(raw);
                actions++;
            }
            continue;
        }

        if (classNameContains(obj, "PreampOverviewForm")) {
            overviewForms++;
            void* raw = obj;
            if (selectedChannelObj && preampOverviewReceivePointUpdated) {
                preampOverviewReceivePointUpdated(raw, selectedChannelObj);
                actions++;
            }
            if (preampOverviewUpdatePreamp) {
                preampOverviewUpdatePreamp(raw);
                actions++;
            }
        }
    }

    fprintf(stderr,
            "[MC] %srefresh preamp via forms: selectedCh=%d channelObj=%p candidates=%d preampForms=%d sourcePanels=%d overviewForms=%d actions=%d\n",
            phaseTag ? phaseTag : "",
            selectedInputCh >= 0 ? selectedInputCh + 1 : -1,
            selectedChannelObj,
            targets.size(), preampForms, sourceAssignPanels, overviewForms,
            actions);
    QApplication::processEvents();
}

static void refreshVisiblePreampUI(const char* phaseTag) {
    QList<QObject*> targets = collectPreampRefreshTargets();
    refreshVisiblePreampUIOnTargets(targets, phaseTag);

    const QString delayedTag = QString::fromUtf8(phaseTag ? phaseTag : "");
    const int delaysMs[] = {250, 1000, 2500};
    for (int delayMs : delaysMs) {
        QTimer::singleShot(delayMs, qApp, [delayedTag, delayMs]() {
            QList<QObject*> delayedTargets = collectPreampRefreshTargets();
            QByteArray tagUtf8 =
                QString("%1(delayed %2ms) ")
                    .arg(delayedTag)
                    .arg(delayMs)
                    .toUtf8();
            refreshVisiblePreampUIOnTargets(delayedTargets, tagUtf8.constData());
        });
    }
}

static bool isMeaningfulAudioSourceDesc(const QString& desc) {
    QString t = desc.trimmed();
    if (t.isEmpty() || t == "-" || t == "--")
        return false;
    return true;
}

static bool isGenericPatchSourceLabel(const QString& label) {
    QString t = label.trimmed();
    return t.isEmpty() || t == "Input" || t.startsWith("Type ");
}

static bool shouldSplitPatchSourceTypeByRange(uint32_t sourceType) {
    // These low-numbered input banks contain multiple visible sub-banks
    // (Surface sockets, Surface I/O 4/5, MixRack sockets, DX, I/O ports).
    return sourceType <= 5;
}

static QString buildAudioSourceDescription(const sAudioSource& source) {
    QString desc = buildAudioSourceDescriptionRaw(source).trimmed();
    if (!desc.isEmpty() && desc != "-" && desc != "--")
        return desc;

    if (audioSourceIsUnassigned(source))
        return "Unassigned";

    return QString("%1 %2")
        .arg(buildAudioSourceBankLabel(source.type))
        .arg(source.number + 1);
}

static QString buildAudioSourceBankLabel(uint32_t sourceType) {
    if (sourceType == 20)
        return "Unassigned";

    uint16_t count = 0;
    if (readNumSendPointsForType(sourceType, count) && count > 0) {
        uint16_t probeLimit = shouldSplitPatchSourceTypeByRange(sourceType)
            ? std::min<uint16_t>(count, 32)
            : std::min<uint16_t>(count, 8);
        for (uint16_t sourceNumber = 0; sourceNumber < probeLimit; sourceNumber++) {
            QString desc = buildAudioSourceDescriptionRaw({sourceType, sourceNumber}).trimmed();
            if (!isMeaningfulAudioSourceDesc(desc))
                continue;
            desc = trimAudioSourceBankSuffix(desc);
            if (!desc.isEmpty() && !isGenericPatchSourceLabel(desc))
                return desc;
        }
    }

    typedef QString (*fn_AudioSourceToSourceString)(uint32_t sourceType, uint32_t& sourceNumber);
    auto audioSourceToSourceString = (fn_AudioSourceToSourceString)RESOLVE(0x100f59db0);
    if (audioSourceToSourceString) {
        uint32_t sourceNumber = 0;
        QString label = audioSourceToSourceString(sourceType, sourceNumber).trimmed();
        if (!label.isEmpty())
            return label;
    }

    return formatAudioSourceLabel({sourceType, 0});
}

static QString buildPatchMenuBankLabel(uint32_t sourceType, uint32_t sourceNumber) {
    if (sourceType == 20)
        return "Unassigned";

    QString desc = buildAudioSourceDescriptionRaw({sourceType, sourceNumber}).trimmed();
    if (isMeaningfulAudioSourceDesc(desc)) {
        QString label = trimAudioSourceBankSuffix(desc);
        if (!label.isEmpty() && !isGenericPatchSourceLabel(label))
            return label;
    }

    typedef QString (*fn_AudioSourceToSourceString)(uint32_t sourceType, uint32_t& sourceNumber);
    auto audioSourceToSourceString = (fn_AudioSourceToSourceString)RESOLVE(0x100f59db0);
    if (audioSourceToSourceString) {
        uint32_t probeNumber = sourceNumber;
        QString label = audioSourceToSourceString(sourceType, probeNumber).trimmed();
        if (!label.isEmpty()) {
            label = trimAudioSourceBankSuffix(label);
            if (!label.isEmpty())
                return label;
        }
    }

    return buildAudioSourceBankLabel(sourceType);
}

static QString formatAudioSourceDisplay(const sAudioSource& source) {
    return buildAudioSourceDescription(source);
}

struct PatchSourceChoiceEntry {
    QString label;
    uint32_t type;
    uint32_t startNumber;
    uint32_t count;
    bool available;
};

static std::vector<PatchSourceChoiceEntry> buildPatchSourceChoices(const PatchData* preferredPatch = nullptr) {
    std::vector<PatchSourceChoiceEntry> out;
    out.push_back({QString("Unassigned"), 20, 0, 0, true});

    for (uint32_t sourceType = 0; sourceType < 0x2f; sourceType++) {
        uint16_t count = 0;
        bool hasCount = readNumSendPointsForType(sourceType, count);
        if (!hasCount || count == 0)
            continue;

        if (!shouldSplitPatchSourceTypeByRange(sourceType)) {
            QString label = buildPatchMenuBankLabel(sourceType, 0).trimmed();
            if (isGenericPatchSourceLabel(label) || label == "Unassigned")
                continue;
            out.push_back({label, sourceType, 0, count, true});
            continue;
        }

        QString runLabel;
        uint32_t runStart = 0;
        uint32_t runCount = 0;

        auto flushRun = [&]() {
            if (runLabel.isEmpty() || runLabel == "Unassigned" || runCount == 0 ||
                isGenericPatchSourceLabel(runLabel))
                return;
            out.push_back({runLabel, sourceType, runStart, runCount, true});
        };

        for (uint32_t sourceNumber = 0; sourceNumber < count; sourceNumber++) {
            QString label = buildPatchMenuBankLabel(sourceType, sourceNumber).trimmed();
            if (label.isEmpty() || label == "Unassigned" || isGenericPatchSourceLabel(label))
                continue;

            if (runLabel.isEmpty()) {
                runLabel = label;
                runStart = sourceNumber;
                runCount = 1;
                continue;
            }
            if (label == runLabel) {
                runCount++;
                continue;
            }

            flushRun();
            runLabel = label;
            runStart = sourceNumber;
            runCount = 1;
        }
        flushRun();
    }

    return out;
}

static uint32_t patchDataSourceIndexForAudioSourceType(uint32_t audioSourceType,
                                                       uint32_t fallbackSourceIndex = 0) {
    switch (audioSourceType) {
        case 0: return 0;
        case 1: return 1;
        case 2: return 2;
        case 3: return 3;
        case 5: return 4;
        default: return std::min<uint32_t>(fallbackSourceIndex, 4);
    }
}

static uint32_t preferredMixRackIOPortAudioSourceType(const PatchData* preferredPatch = nullptr) {
    if (preferredPatch && (preferredPatch->source.type == 2 || preferredPatch->source.type == 5))
        return preferredPatch->source.type;
    uint16_t count = 0;
    if (readNumSendPointsForType(kMixRackIOPortAudioSourceType, count) && count > 0)
        return kMixRackIOPortAudioSourceType;
    if (readNumSendPointsForType(2, count) && count > 0)
        return 2;
    return kMixRackIOPortAudioSourceType;
}

static PatchData makePatchDataForAudioSource(const sAudioSource& source,
                                             const PatchData* preferredPatch = nullptr) {
    PatchData out = preferredPatch ? *preferredPatch : PatchData{};
    out.source = source;
    out.sourceType = patchDataSourceIndexForAudioSourceType(
        source.type, preferredPatch ? preferredPatch->sourceType : 0);
    return out;
}

static PatchData getEffectiveBlockPatchData(const ReorderBlockEntry& entry,
                                            int side,
                                            int tgtCh,
                                            bool movePatchWithChannel,
                                            bool shiftMixRackIOPortWithMoveInScenarioA) {
    if (side == 0) {
        if (entry.hasPatchOverrideA)
            return entry.patchOverrideA;
        return getTargetPatchDataForMove(entry.patchDataA, entry.srcStart, tgtCh,
                                         movePatchWithChannel,
                                         shiftMixRackIOPortWithMoveInScenarioA);
    }
    if (entry.hasPatchOverrideB)
        return entry.patchOverrideB;
    return getTargetPatchDataForMove(entry.patchDataB, entry.srcStart + 1, tgtCh,
                                     movePatchWithChannel,
                                     shiftMixRackIOPortWithMoveInScenarioA);
}

static QString formatPatchPreviewForMove(const PatchData& patch,
                                         int srcCh,
                                         int tgtCh,
                                         bool movePatchWithChannel,
                                         bool shiftMixRackIOPortWithMoveInScenarioA) {
    PatchData previewPatch = getTargetPatchDataForMove(patch, srcCh, tgtCh,
                                                       movePatchWithChannel,
                                                       shiftMixRackIOPortWithMoveInScenarioA);
    return formatAudioSourceDisplay(previewPatch.source);
}

static QString formatPreampPreviewForTarget(const ReorderBlockEntry& entry,
                                            int tgtStart,
                                            bool movePatchWithChannel,
                                            bool shiftMixRackIOPortWithMoveInScenarioA) {
    if (!entry.stereo) {
        if (!entry.validPatchA)
            return "n/a";
        return formatAudioSourceDisplay(
            getEffectiveBlockPatchData(entry, 0, tgtStart,
                                       movePatchWithChannel,
                                       shiftMixRackIOPortWithMoveInScenarioA).source);
    }

    QString left = entry.validPatchA
        ? formatAudioSourceDisplay(
            getEffectiveBlockPatchData(entry, 0, tgtStart,
                                       movePatchWithChannel,
                                       shiftMixRackIOPortWithMoveInScenarioA).source)
        : QString("n/a");
    QString right = entry.validPatchB
        ? formatAudioSourceDisplay(
            getEffectiveBlockPatchData(entry, 1, tgtStart + 1,
                                       movePatchWithChannel,
                                       shiftMixRackIOPortWithMoveInScenarioA).source)
        : QString("n/a");

    int leftSocket = -1;
    int rightSocket = -1;
    if (entry.validPatchA && entry.validPatchB) {
        PatchData leftPatch = getEffectiveBlockPatchData(entry, 0, tgtStart,
                                                         movePatchWithChannel,
                                                         shiftMixRackIOPortWithMoveInScenarioA);
        PatchData rightPatch = getEffectiveBlockPatchData(entry, 1, tgtStart + 1,
                                                          movePatchWithChannel,
                                                          shiftMixRackIOPortWithMoveInScenarioA);
        if (leftPatch.source.type == rightPatch.source.type &&
            rightPatch.source.number == leftPatch.source.number + 1) {
            return QString("%1 %2/%3")
                .arg(buildAudioSourceBankLabel(leftPatch.source.type))
                .arg(leftPatch.source.number + 1)
                .arg(rightPatch.source.number + 1);
        }
        if (getAnalogueSocketIndexForAudioSource(leftPatch.source, leftSocket) &&
            getAnalogueSocketIndexForAudioSource(rightPatch.source, rightSocket)) {
            return QString("%1 %2/%3")
                .arg(buildAudioSourceBankLabel(leftPatch.source.type))
                .arg(leftPatch.source.number + 1)
                .arg(rightPatch.source.number + 1);
        }
    }
    if (left == right)
        return left;
    return left + " | " + right;
}

static QString formatReorderChannelNumberText(const ReorderBlockEntry& entry) {
    if (entry.stereo) {
        return QString("Ch %1+%2")
            .arg(entry.srcStart + 1, 3, 10, QChar('0'))
            .arg(entry.srcStart + 2, 3, 10, QChar('0'));
    }
    return QString("Ch %1").arg(entry.srcStart + 1, 3, 10, QChar('0'));
}

static QString formatReorderChannelNameText(const ReorderBlockEntry& entry) {
    return entry.name.isEmpty() ? QString("(empty)") : entry.name;
}

static QString formatReorderStereoText(const ReorderBlockEntry& entry) {
    return entry.stereo ? "Stereo" : "Mono";
}

static std::vector<IllegalStereoPlacement> findIllegalStereoPlacements(
    const std::vector<int>& blockOrder,
    const std::vector<ReorderBlockEntry>& blocks) {
    std::vector<IllegalStereoPlacement> out;
    int tgtStart = 0;
    for (int row = 0; row < (int)blockOrder.size(); row++) {
        int blockId = blockOrder[row];
        if (blockId < 0 || blockId >= (int)blocks.size())
            continue;
        const auto& block = blocks[blockId];
        if (block.stereo && (tgtStart & 1) != 0)
            out.push_back({row, tgtStart, blockId});
        tgtStart += block.width;
    }
    return out;
}

class ReorderTableWidget : public QTableWidget {
public:
    std::function<void(const std::vector<int>&, const std::vector<int>&)> onItemsReordered;

    explicit ReorderTableWidget(QWidget* parent = nullptr)
        : QTableWidget(parent) {
        QFont tableFont = font();
        tableFont.setPointSize(std::max(8, tableFont.pointSize() - 2));
        setFont(tableFont);
        setSelectionMode(QAbstractItemView::ExtendedSelection);
        setSelectionBehavior(QAbstractItemView::SelectRows);
        setDragEnabled(true);
        setAcceptDrops(true);
        setDropIndicatorShown(false);
        setDefaultDropAction(Qt::CopyAction);
        setDragDropMode(QAbstractItemView::DragDrop);
        setDragDropOverwriteMode(false);
        setAutoScroll(true);
        setAutoScrollMargin(48);
        setVerticalScrollMode(QAbstractItemView::ScrollPerPixel);
        setEditTriggers(QAbstractItemView::NoEditTriggers);
        setShowGrid(false);
        setAlternatingRowColors(false);
        setContextMenuPolicy(Qt::CustomContextMenu);
        verticalHeader()->setVisible(false);
        verticalHeader()->setDefaultSectionSize(22);
        horizontalHeader()->setStretchLastSection(true);
    }

protected:
    struct SavedItemBrushState {
        int row = -1;
        int col = -1;
        QBrush background;
        QBrush foreground;
    };

    std::vector<SavedItemBrushState> m_dragBrushState;
    bool m_dragVisualsActive = false;
    QString m_savedDragStyleSheet;
    int m_dropHoverRow = -1;

    int computeDropRowFromPosition(const QPoint& pos) const {
        QModelIndex dropIndex = indexAt(pos);
        int dropRow = rowCount();
        if (dropIndex.isValid()) {
            dropRow = dropIndex.row();
            QRect rect = visualRect(dropIndex);
            if (pos.y() > rect.center().y())
                dropRow++;
        }
        if (dropRow < 0)
            dropRow = 0;
        if (rowCount() <= 0)
            return -1;
        return std::min(dropRow, rowCount());
    }

    void updateDropHoverRow(const QPoint& pos) {
        int nextRow = computeDropRowFromPosition(pos);
        if (m_dropHoverRow == nextRow)
            return;
        m_dropHoverRow = nextRow;
        viewport()->update();
    }

    void clearDropHoverRow() {
        if (m_dropHoverRow < 0)
            return;
        m_dropHoverRow = -1;
        viewport()->update();
    }

    QList<int> selectedRowsSorted() const {
        QModelIndexList selection = selectedIndexes();
        QList<int> selectedRows;
        for (const QModelIndex& index : selection)
            selectedRows.push_back(index.row());
        std::sort(selectedRows.begin(), selectedRows.end());
        selectedRows.erase(std::unique(selectedRows.begin(), selectedRows.end()), selectedRows.end());
        return selectedRows;
    }

    void applyDragVisuals() {
        if (m_dragVisualsActive)
            return;
        QList<int> rows = selectedRowsSorted();
        if (rows.empty())
            return;
        m_dragBrushState.clear();
        m_dragBrushState.reserve(rows.size() * std::max(1, columnCount()));
        m_savedDragStyleSheet = styleSheet();
        setStyleSheet(m_savedDragStyleSheet +
                      QStringLiteral(
                          " QTableWidget::item:selected {"
                          " background-color: rgba(255,255,255,196);"
                          " color: rgba(255,255,255,250);"
                          " }"));
        const QColor fallbackBg = palette().base().color();
        const QColor fallbackFg = palette().text().color();
        for (int row : rows) {
            for (int col = 0; col < columnCount(); col++) {
                QTableWidgetItem* item = this->item(row, col);
                if (!item)
                    continue;
                m_dragBrushState.push_back({row, col, item->background(), item->foreground()});

                QBrush bgBrush = item->background();
                QColor bg = bgBrush.color().isValid() ? bgBrush.color() : fallbackBg;
                bg.setAlpha(196);
                item->setBackground(QBrush(bg));

                QBrush fgBrush = item->foreground();
                QColor fg = fgBrush.color().isValid() ? fgBrush.color() : fallbackFg;
                fg.setAlpha(250);
                item->setForeground(QBrush(fg));
            }
        }
        m_dragVisualsActive = true;
        viewport()->update();
    }

    void restoreDragVisuals() {
        if (!m_dragVisualsActive)
            return;
        for (const SavedItemBrushState& saved : m_dragBrushState) {
            QTableWidgetItem* item = this->item(saved.row, saved.col);
            if (!item)
                continue;
            item->setBackground(saved.background);
            item->setForeground(saved.foreground);
        }
        m_dragBrushState.clear();
        setStyleSheet(m_savedDragStyleSheet);
        m_savedDragStyleSheet.clear();
        m_dragVisualsActive = false;
        viewport()->update();
    }

    std::vector<int> currentOrder() const {
        std::vector<int> order;
        order.reserve(rowCount());
        for (int row = 0; row < rowCount(); row++) {
            QTableWidgetItem* it = item(row, 0);
            order.push_back(it ? it->data(Qt::UserRole).toInt() : row);
        }
        return order;
    }

    void startDrag(Qt::DropActions supportedActions) override {
        applyDragVisuals();
        QTableWidget::startDrag(supportedActions);
        restoreDragVisuals();
        clearDropHoverRow();
    }

    void paintEvent(QPaintEvent* event) override {
        QTableWidget::paintEvent(event);
        if (m_dropHoverRow < 0 || rowCount() <= 0)
            return;
        int lineY = 0;
        if (m_dropHoverRow >= rowCount()) {
            QModelIndex lastIndex = model()->index(rowCount() - 1, 0);
            QRect lastRect = visualRect(lastIndex);
            if (!lastRect.isValid())
                return;
            lineY = lastRect.bottom();
        } else {
            QModelIndex targetIndex = model()->index(m_dropHoverRow, 0);
            QRect targetRect = visualRect(targetIndex);
            if (!targetRect.isValid())
                return;
            lineY = targetRect.top();
        }
        QPainter painter(viewport());
        painter.setRenderHint(QPainter::Antialiasing, false);
        QColor accent(0, 0, 0, 255);
        QPen pen(accent);
        pen.setWidth(4);
        pen.setCapStyle(Qt::SquareCap);
        painter.setPen(pen);
        painter.setBrush(Qt::NoBrush);
        painter.drawLine(0, lineY, viewport()->width(), lineY);
    }

    void dragMoveEvent(QDragMoveEvent* event) override {
        const int margin = 48;
        const int step = std::max(4, verticalHeader()->defaultSectionSize() / 2);
        QScrollBar* bar = verticalScrollBar();
        if (bar) {
            if (event->pos().y() < margin) {
                bar->setValue(bar->value() - step);
            } else if (event->pos().y() > viewport()->height() - margin) {
                bar->setValue(bar->value() + step);
            }
        }
        updateDropHoverRow(event->pos());
        QTableWidget::dragMoveEvent(event);
    }

    void dragLeaveEvent(QDragLeaveEvent* event) override {
        clearDropHoverRow();
        QTableWidget::dragLeaveEvent(event);
    }

    void dropEvent(QDropEvent* event) override {
        std::vector<int> beforeOrder = currentOrder();
        QList<int> selectedRows = selectedRowsSorted();
        if (selectedRows.empty()) {
            clearDropHoverRow();
            event->ignore();
            return;
        }

        QModelIndex dropIndex = indexAt(event->pos());
        int dropRow = rowCount();
        if (dropIndex.isValid()) {
            dropRow = dropIndex.row();
            QRect rect = visualRect(dropIndex);
            if (event->pos().y() > rect.center().y())
                dropRow++;
        }
        int firstSelected = selectedRows.front();
        int lastSelected = selectedRows.back();
        if (dropRow >= firstSelected && dropRow <= lastSelected + 1) {
            clearDropHoverRow();
            event->setDropAction(Qt::CopyAction);
            event->accept();
            return;
        }
        int removedBeforeDrop = 0;
        for (int rowIdx : selectedRows) {
            if (rowIdx < dropRow)
                removedBeforeDrop++;
        }
        dropRow -= removedBeforeDrop;
        if (dropRow < 0)
            dropRow = 0;
        std::vector<int> movedChannels;
        movedChannels.reserve(selectedRows.size());
        for (int rowIdx : selectedRows)
            movedChannels.push_back(beforeOrder[rowIdx]);

        std::vector<int> afterOrder = beforeOrder;
        for (int i = (int)selectedRows.size() - 1; i >= 0; i--)
            afterOrder.erase(afterOrder.begin() + selectedRows[i]);
        afterOrder.insert(afterOrder.begin() + dropRow, movedChannels.begin(), movedChannels.end());
        clearDropHoverRow();
        event->setDropAction(Qt::CopyAction);
        event->accept();
        if (onItemsReordered && beforeOrder != afterOrder)
            onItemsReordered(beforeOrder, afterOrder);
    }
};

static std::vector<ReorderBlockEntry> snapshotReorderBlocks() {
    std::vector<ReorderBlockEntry> blocks;
    blocks.reserve(128);
    for (int ch = 0, blockId = 0; ch < 128; ) {
        ReorderBlockEntry entry;
        entry.blockId = blockId++;
        entry.srcStart = ch;
        entry.stereo = ((ch & 1) == 0) && isChannelStereo(ch);
        entry.width = entry.stereo ? 2 : 1;
        const char* rawName = g_getChannelName ? g_getChannelName(g_audioDM, 1, (uint8_t)ch) : "";
        entry.name = rawName ? QString::fromUtf8(rawName) : QString();
        entry.colour = g_getChannelColour ? g_getChannelColour(g_audioDM, 1, (uint8_t)ch) : 0;
        entry.validPatchA = readPatchData(ch, entry.patchDataA);
        if (entry.stereo && ch + 1 < 128)
            entry.validPatchB = readPatchData(ch + 1, entry.patchDataB);
        blocks.push_back(entry);
        ch += entry.width;
    }
    return blocks;
}

static std::vector<int> readCurrentReorderBlockOrder(const ReorderTableWidget* table) {
    std::vector<int> order;
    order.reserve(table->rowCount());
    for (int row = 0; row < table->rowCount(); row++) {
        QTableWidgetItem* item = table->item(row, 0);
        order.push_back(item ? item->data(Qt::UserRole).toInt() : row);
    }
    return order;
}

static std::vector<int> expandReorderBlockOrder(const std::vector<int>& blockOrder,
                                                const std::vector<ReorderBlockEntry>& blocks) {
    std::vector<int> channels;
    channels.reserve(128);
    for (int blockId : blockOrder) {
        if (blockId < 0 || blockId >= (int)blocks.size())
            continue;
        const auto& block = blocks[blockId];
        for (int i = 0; i < block.width; i++)
            channels.push_back(block.srcStart + i);
    }
    return channels;
}

static void populateReorderTable(ReorderTableWidget* table, const std::vector<int>& blockOrder) {
    table->setUpdatesEnabled(false);
    if (table->rowCount() != (int)blockOrder.size())
        table->setRowCount((int)blockOrder.size());
    for (int row = 0; row < (int)blockOrder.size(); row++) {
        int blockId = blockOrder[row];
        for (int col = 0; col < table->columnCount(); col++) {
            QTableWidgetItem* item = table->item(row, col);
            if (!item) {
                item = new QTableWidgetItem();
                item->setFlags((item->flags() | Qt::ItemIsDragEnabled | Qt::ItemIsDropEnabled |
                                Qt::ItemIsSelectable | Qt::ItemIsEnabled) & ~Qt::ItemIsEditable);
                table->setItem(row, col, item);
            }
            if (col == 0)
                item->setData(Qt::UserRole, blockId);
        }
    }
    table->setUpdatesEnabled(true);
}

static void selectReorderRowsForBlocks(ReorderTableWidget* table, const std::vector<int>& blockIds) {
    table->clearSelection();
    if (blockIds.empty())
        return;
    std::set<int> wanted(blockIds.begin(), blockIds.end());
    for (int row = 0; row < table->rowCount(); row++) {
        QTableWidgetItem* item = table->item(row, 0);
        if (item && wanted.count(item->data(Qt::UserRole).toInt()))
            table->selectRow(row);
    }
}

static void resizeReorderDialogToTable(QDialog* dialog, ReorderTableWidget* table) {
    if (!dialog || !table)
        return;
    auto* header = table->horizontalHeader();
    bool stretchLast = header->stretchLastSection();
    header->setStretchLastSection(false);
    table->resizeColumnsToContents();
    const int kColumnPadding = 18;
    for (int col = 0; col < table->columnCount(); col++) {
        int contentWidth = header->sectionSizeHint(col);
        table->setColumnWidth(col, std::max(table->columnWidth(col), contentWidth) + kColumnPadding);
    }
    int width = table->verticalHeader()->isVisible() ? table->verticalHeader()->width() : 0;
    for (int col = 0; col < table->columnCount(); col++)
        width += table->columnWidth(col);
    width += table->frameWidth() * 2;
    width += 24; // breathing room for scrollbars/margins
    int desired = std::max(500, width + 28);
    dialog->setMinimumWidth(desired);
    dialog->resize(desired, dialog->height());
    header->setStretchLastSection(stretchLast);
}

static bool applyChannelReorder(const std::vector<int>& blockOrder,
                                const std::vector<ReorderBlockEntry>& blocks,
                                bool movePatchWithChannel,
                                bool shiftMixRackIOPortWithMoveInScenarioA,
                                char* errBuf = nullptr,
                                size_t errBufLen = 0) {
    std::vector<int> targetOrder = expandReorderBlockOrder(blockOrder, blocks);
    MovePlan plan;
    if (!buildReorderPlan(targetOrder, plan, errBuf, errBufLen))
        return false;
    const bool hadOrderChanges = !plan.targetMap.empty();
    std::set<int> overrideTargets;
    int tgtStart = 0;
    for (int blockId : blockOrder) {
        if (blockId < 0 || blockId >= (int)blocks.size())
            continue;
        const auto& block = blocks[blockId];
        if (block.hasPatchOverrideA && tgtStart >= 0 && tgtStart < 128) {
            plan.hasPatchOverride[tgtStart] = true;
            plan.patchOverride[tgtStart] = block.patchOverrideA;
            overrideTargets.insert(tgtStart);
        }
        if (block.width > 1 && block.hasPatchOverrideB && tgtStart + 1 >= 0 && tgtStart + 1 < 128) {
            plan.hasPatchOverride[tgtStart + 1] = true;
            plan.patchOverride[tgtStart + 1] = block.patchOverrideB;
            overrideTargets.insert(tgtStart + 1);
        }
        tgtStart += block.width;
    }
    if (!overrideTargets.empty()) {
        int finalLo = overrideTargets.empty() ? plan.lo : *overrideTargets.begin();
        int finalHi = overrideTargets.empty() ? plan.hi : *overrideTargets.rbegin();
        if (!plan.targetMap.empty()) {
            finalLo = std::min(finalLo, plan.lo);
            finalHi = std::max(finalHi, plan.hi);
        }
        plan.lo = finalLo;
        plan.hi = finalHi;
        plan.targetMap.clear();
        for (int tgt = plan.lo; tgt <= plan.hi; tgt++) {
            int srcCh = targetOrder[tgt];
            if (hadOrderChanges || overrideTargets.count(tgt))
                plan.targetMap.push_back({tgt, srcCh - plan.lo});
        }
    }
    return applyMovePlan(plan,
                         movePatchWithChannel,
                         shiftMixRackIOPortWithMoveInScenarioA,
                         "custom reorder");
}

static QString normalizedToolbarText(const QString& text) {
    QString out = text;
    out.remove('&');
    return out.trimmed();
}

static bool isVisibleToolbarWidget(const QWidget* widget) {
    return widget && widget->isVisible() && widget->window() && widget->window()->isVisible();
}

static QRect widgetRectInAncestor(QWidget* widget, QWidget* ancestor) {
    if (!widget || !ancestor)
        return QRect();
    QPoint topLeft = ancestor->mapFromGlobal(widget->mapToGlobal(QPoint(0, 0)));
    return QRect(topLeft, widget->size());
}

static QRect visualTextRectInAncestor(QWidget* widget, QWidget* ancestor) {
    QRect rect = widgetRectInAncestor(widget, ancestor);
    if (!widget || !rect.isValid())
        return rect;
    QString text = normalizedToolbarText(widgetTextProperty(widget));
    if (text.isEmpty())
        return rect;
    int textWidth = widget->fontMetrics().horizontalAdvance(text);
    int desiredWidth = std::max(rect.width(), textWidth + 10);
    if (desiredWidth == rect.width())
        return rect;
    rect.setWidth(desiredWidth);
    return rect;
}

static QWidget* commonAncestorWidget(QWidget* a, QWidget* b) {
    if (!a || !b)
        return nullptr;
    std::set<QWidget*> ancestors;
    for (QWidget* cur = a; cur; cur = cur->parentWidget())
        ancestors.insert(cur);
    for (QWidget* cur = b; cur; cur = cur->parentWidget()) {
        if (ancestors.count(cur))
            return cur;
    }
    return nullptr;
}

static QString widgetTextProperty(QWidget* widget) {
    if (!widget)
        return QString();
    QVariant textProp = widget->property("text");
    if (textProp.isValid() && textProp.canConvert<QString>())
        return textProp.toString();
    const QMetaObject* mo = widget->metaObject();
    if (mo) {
        int textIdx = mo->indexOfProperty("text");
        if (textIdx >= 0) {
            QMetaProperty prop = mo->property(textIdx);
            QVariant value = prop.read(widget);
            if (value.isValid() && value.canConvert<QString>())
                return value.toString();
        }
        int titleIdx = mo->indexOfProperty("title");
        if (titleIdx >= 0) {
            QMetaProperty prop = mo->property(titleIdx);
            QVariant value = prop.read(widget);
            if (value.isValid() && value.canConvert<QString>())
                return value.toString();
        }
    }
    return QString();
}

struct ToolbarReorderTargets {
    QWidget* host = nullptr;
    QWidget* mainWidget = nullptr;
    QWidget* systemWidget = nullptr;
    QWidget* homeWidget = nullptr;
    QWidget* previewWidget = nullptr;
    QWidget* selWidget = nullptr;
    QWidget* rightBoundaryWidget = nullptr;
};

static ToolbarReorderTargets findToolbarReorderTargets() {
    ToolbarReorderTargets best;
    int bestScore = INT_MAX;

    const QList<QWidget*> topLevels = QApplication::topLevelWidgets();
    for (QWidget* window : topLevels) {
        if (!window || !window->isVisible())
            continue;

        QList<QWidget*> widgets = window->findChildren<QWidget*>();
        QWidget* mainWidget = nullptr;
        QWidget* systemWidget = nullptr;
        QWidget* homeWidget = nullptr;
        QWidget* previewWidget = nullptr;
        QWidget* selWidget = nullptr;
        for (QWidget* widget : widgets) {
            if (!isVisibleToolbarWidget(widget))
                continue;
            QString text = normalizedToolbarText(widgetTextProperty(widget));
            if (text.isEmpty())
                continue;
            if (text == "Main") {
                if (!mainWidget || widget->mapToGlobal(QPoint()).y() < mainWidget->mapToGlobal(QPoint()).y())
                    mainWidget = widget;
            } else if (text.startsWith("System", Qt::CaseInsensitive)) {
                if (!systemWidget || widget->mapToGlobal(QPoint()).y() < systemWidget->mapToGlobal(QPoint()).y())
                    systemWidget = widget;
            } else if (text == "Home") {
                if (!homeWidget || widget->mapToGlobal(QPoint()).y() < homeWidget->mapToGlobal(QPoint()).y())
                    homeWidget = widget;
            } else if (text == "Preview") {
                if (!previewWidget || widget->mapToGlobal(QPoint()).y() < previewWidget->mapToGlobal(QPoint()).y())
                    previewWidget = widget;
            } else if (text.startsWith("Sel:", Qt::CaseInsensitive)) {
                if (!selWidget || widget->mapToGlobal(QPoint()).y() < selWidget->mapToGlobal(QPoint()).y())
                    selWidget = widget;
            }
        }

        QWidget* leftAnchor = systemWidget ? systemWidget : mainWidget;
        if (!leftAnchor)
            continue;
        QWidget* rightBoundary = nullptr;
        int boundaryX = INT_MAX;
        int anchorGlobalY = leftAnchor->mapToGlobal(QPoint()).y();
        int anchorGlobalRight = leftAnchor->mapToGlobal(QPoint(leftAnchor->width(), 0)).x();
        for (QWidget* widget : widgets) {
            if (widget == leftAnchor || !isVisibleToolbarWidget(widget))
                continue;
            QPoint gp = widget->mapToGlobal(QPoint(0, 0));
            if (std::abs(gp.y() - anchorGlobalY) > 20)
                continue;
            if (gp.x() <= anchorGlobalRight)
                continue;
            if (gp.x() < boundaryX) {
                boundaryX = gp.x();
                rightBoundary = widget;
            }
        }
        if (!rightBoundary)
            rightBoundary = previewWidget ? previewWidget : (homeWidget ? homeWidget : selWidget);
        if (!rightBoundary)
            continue;

        QWidget* host = commonAncestorWidget(leftAnchor, rightBoundary);
        if (!host)
            host = leftAnchor->parentWidget();
        if (!host)
            continue;

        QRect leftRect = visualTextRectInAncestor(leftAnchor, host);
        QRect rightRect = widgetRectInAncestor(rightBoundary, host);
        if (!leftRect.isValid() || !rightRect.isValid())
            continue;
        if (rightRect.x() <= leftRect.right())
            continue;

        int score = leftAnchor->mapToGlobal(QPoint()).y();
        if (score < bestScore) {
            bestScore = score;
            best.host = host;
            best.mainWidget = mainWidget;
            best.systemWidget = systemWidget;
            best.homeWidget = homeWidget;
            best.previewWidget = previewWidget;
            best.selWidget = selWidget;
            best.rightBoundaryWidget = rightBoundary;
        }
    }

    return best;
}

static QWidget* findLargestVisibleTopLevelWidget() {
    QWidget* best = nullptr;
    int64_t bestArea = -1;
    const QList<QWidget*> topLevels = QApplication::topLevelWidgets();
    for (QWidget* widget : topLevels) {
        if (!widget || !widget->isVisible())
            continue;
        QSize sz = widget->size();
        int64_t area = (int64_t)sz.width() * (int64_t)sz.height();
        if (area > bestArea) {
            bestArea = area;
            best = widget;
        }
    }
    return best;
}

struct QmlToolbarTargets {
    QWidget* host = nullptr;
    QWidget* quickWidget = nullptr;
    QObject* tabbar = nullptr;
    QObject* tabrow = nullptr;
    QObject* homeButton = nullptr;
};

static QmlToolbarTargets findQmlToolbarTargets() {
    QmlToolbarTargets out;
    QWidget* host = findLargestVisibleTopLevelWidget();
    if (!host)
        return out;
    QObject* quickObj = host->findChild<QObject*>("mainQmlWidget");
    QWidget* quickWidget = host->findChild<QWidget*>("mainQmlWidget");
    if (!quickObj || !quickWidget)
        return out;
    QObject* tabbar = quickObj->findChild<QObject*>("tabbar");
    QObject* tabrow = quickObj->findChild<QObject*>("tabrow");
    if (!tabbar || !tabrow)
        return out;
    out.host = host;
    out.quickWidget = quickWidget;
    out.tabbar = tabbar;
    out.tabrow = tabrow;
    out.homeButton = quickObj->findChild<QObject*>("homeButton");
    return out;
}

static QRect qmlObjectRectInHost(QObject* obj, QWidget* quickWidget, QWidget* host) {
    if (!obj || !quickWidget || !host)
        return QRect();
    QRect quickRect = widgetRectInAncestor(quickWidget, host);
    int x = quickRect.x() + (int)std::lround(objectNumericProperty(obj, "x", 0.0));
    int y = quickRect.y() + (int)std::lround(objectNumericProperty(obj, "y", 0.0));
    int w = (int)std::lround(objectNumericProperty(obj, "width", 0.0));
    int h = (int)std::lround(objectNumericProperty(obj, "height", 0.0));
    return QRect(x, y, w, h);
}

static QString describeWidgetForLog(QWidget* widget, QWidget* host = nullptr) {
    if (!widget)
        return QString("(null)");
    QRect rect = host ? widgetRectInAncestor(widget, host) : widget->geometry();
    QString text = normalizedToolbarText(widgetTextProperty(widget));
    if (text.isEmpty())
        text = "-";
    return QString("%1 name='%2' text='%3' rect=(%4,%5 %6x%7) visible=%8 enabled=%9")
        .arg(widget->metaObject() ? widget->metaObject()->className() : "(no-meta)")
        .arg(widget->objectName())
        .arg(text)
        .arg(rect.x()).arg(rect.y()).arg(rect.width()).arg(rect.height())
        .arg(widget->isVisible() ? 1 : 0)
        .arg(widget->isEnabled() ? 1 : 0);
}

static void dumpTopNavWidgets() {
    QWidget* host = findLargestVisibleTopLevelWidget();
    if (!host) {
        fprintf(stderr, "[MC] TopNavDump: no visible top-level widget found.\n");
        return;
    }

    fprintf(stderr, "[MC] TopNavDump host: %s\n",
            describeWidgetForLog(host).toUtf8().constData());

    QList<QWidget*> widgets = host->findChildren<QWidget*>();
    std::vector<QWidget*> interesting;
    interesting.reserve((size_t)widgets.size());
    for (QWidget* widget : widgets) {
        if (!widget || !widget->isVisible())
            continue;
        QRect rect = widgetRectInAncestor(widget, host);
        if (!rect.isValid())
            continue;
        if (rect.bottom() < 0 || rect.y() > 120)
            continue;
        if (rect.width() <= 0 || rect.height() <= 0)
            continue;
        interesting.push_back(widget);
    }

    std::sort(interesting.begin(), interesting.end(), [&](QWidget* a, QWidget* b) {
        QRect ra = widgetRectInAncestor(a, host);
        QRect rb = widgetRectInAncestor(b, host);
        if (ra.y() != rb.y()) return ra.y() < rb.y();
        if (ra.x() != rb.x()) return ra.x() < rb.x();
        return QString(a->metaObject() ? a->metaObject()->className() : "")
             < QString(b->metaObject() ? b->metaObject()->className() : "");
    });

    fprintf(stderr, "[MC] TopNavDump: %zu visible widgets in top band.\n", interesting.size());
    for (QWidget* widget : interesting) {
        QString line = describeWidgetForLog(widget, host);
        QWidget* parent = widget->parentWidget();
        if (parent) {
            line += QString(" parent=%1('%2')")
                .arg(parent->metaObject() ? parent->metaObject()->className() : "(no-meta)")
                .arg(parent->objectName());
        }
        fprintf(stderr, "[MC] TopNavDump: %s\n", line.toUtf8().constData());
    }
}

static double objectNumericProperty(QObject* obj, const char* name, double fallback = 0.0) {
    if (!obj || !name)
        return fallback;
    QVariant value = obj->property(name);
    bool ok = false;
    double out = value.toDouble(&ok);
    return ok ? out : fallback;
}

static bool objectBoolProperty(QObject* obj, const char* name, bool fallback = false) {
    if (!obj || !name)
        return fallback;
    QVariant value = obj->property(name);
    return value.isValid() ? value.toBool() : fallback;
}

static QString objectFontDescription(QObject* obj) {
    if (!obj)
        return QString();
    QVariant value = obj->property("font");
    if (!value.isValid() || !value.canConvert<QFont>())
        return QString();
    QFont font = qvariant_cast<QFont>(value);
    return QString("family='%1' pointSize=%2 pixelSize=%3 weight=%4 bold=%5 italic=%6")
        .arg(font.family())
        .arg(font.pointSizeF(), 0, 'f', 2)
        .arg(font.pixelSize())
        .arg(font.weight())
        .arg(font.bold() ? 1 : 0)
        .arg(font.italic() ? 1 : 0);
}

static void dumpQuickObjectTreeRecursive(QObject* obj, int depth, int maxDepth) {
    if (!obj || depth > maxDepth)
        return;

    QString text;
    const QMetaObject* mo = obj->metaObject();
    if (mo) {
        int textIdx = mo->indexOfProperty("text");
        if (textIdx >= 0) {
            QVariant value = mo->property(textIdx).read(obj);
            if (value.isValid() && value.canConvert<QString>())
                text = normalizedToolbarText(value.toString());
        }
    }
    QString indent(depth * 2, ' ');
    QString fontDesc = objectFontDescription(obj);
    if (!fontDesc.isEmpty()) {
        fprintf(stderr,
                "[MC] TopNavQML: %s%s name='%s' text='%s' pos=(%.1f,%.1f) size=(%.1f x %.1f) visible=%d enabled=%d %s\n",
                indent.toUtf8().constData(),
                obj->metaObject() ? obj->metaObject()->className() : "(no-meta)",
                obj->objectName().toUtf8().constData(),
                text.toUtf8().constData(),
                objectNumericProperty(obj, "x"),
                objectNumericProperty(obj, "y"),
                objectNumericProperty(obj, "width"),
                objectNumericProperty(obj, "height"),
                objectBoolProperty(obj, "visible", true) ? 1 : 0,
                objectBoolProperty(obj, "enabled", true) ? 1 : 0,
                fontDesc.toUtf8().constData());
    } else {
        fprintf(stderr,
                "[MC] TopNavQML: %s%s name='%s' text='%s' pos=(%.1f,%.1f) size=(%.1f x %.1f) visible=%d enabled=%d\n",
                indent.toUtf8().constData(),
                obj->metaObject() ? obj->metaObject()->className() : "(no-meta)",
                obj->objectName().toUtf8().constData(),
                text.toUtf8().constData(),
                objectNumericProperty(obj, "x"),
                objectNumericProperty(obj, "y"),
                objectNumericProperty(obj, "width"),
                objectNumericProperty(obj, "height"),
                objectBoolProperty(obj, "visible", true) ? 1 : 0,
                objectBoolProperty(obj, "enabled", true) ? 1 : 0);
    }

    const QObjectList children = obj->children();
    for (QObject* child : children) {
        if (!child)
            continue;
        if (!objectBoolProperty(child, "visible", true))
            continue;
        if (objectNumericProperty(child, "y") > 140.0 && depth >= 1)
            continue;
        dumpQuickObjectTreeRecursive(child, depth + 1, maxDepth);
    }
}

static void dumpTopNavQuickTree() {
    QWidget* host = findLargestVisibleTopLevelWidget();
    if (!host) {
        fprintf(stderr, "[MC] TopNavQML: no visible top-level widget found.\n");
        return;
    }
    QObject* quickObj = host->findChild<QObject*>("mainQmlWidget");
    QWidget* quickWidget = host->findChild<QWidget*>("mainQmlWidget");
    if (!quickObj || !quickWidget) {
        fprintf(stderr, "[MC] TopNavQML: mainQmlWidget not found.\n");
        return;
    }
    fprintf(stderr, "[MC] TopNavQML root widget: %s\n",
            describeWidgetForLog(quickWidget, host).toUtf8().constData());
    dumpQuickObjectTreeRecursive(quickObj, 0, 7);
}

static void dumpRegionWidgetsRecursive(QWidget* widget,
                                       QWidget* host,
                                       const QRect& region,
                                       int depth,
                                       int maxDepth) {
    if (!widget || !host || depth > maxDepth || !widget->isVisible())
        return;
    QRect rect = widgetRectInAncestor(widget, host);
    if (!rect.isValid() || !rect.intersects(region))
        return;

    QString indent(depth * 2, ' ');
    QString text = normalizedToolbarText(widgetTextProperty(widget));
    QString valueText;
    if (widget->metaObject() &&
        QString::fromLatin1(widget->metaObject()->className()).contains("ValueWidget",
                                                                        Qt::CaseInsensitive)) {
        typedef QString (*fn_ValueWidgetBaseGetText)(const void*);
        static auto valueWidgetGetText =
            (fn_ValueWidgetBaseGetText)RESOLVE(0x1001875e0);
        if (valueWidgetGetText) {
            valueText = normalizedToolbarText(valueWidgetGetText(widget));
        }
    }
    fprintf(stderr,
            "[MC][UIDUMP] %sWIDGET %s name='%s' rect=(%d,%d %dx%d) text='%s' valueText='%s' enabled=%d visible=%d\n",
            indent.toUtf8().constData(),
            widget->metaObject() ? widget->metaObject()->className() : "(no-meta)",
            widget->objectName().toUtf8().constData(),
            rect.x(), rect.y(), rect.width(), rect.height(),
            text.toUtf8().constData(),
            valueText.toUtf8().constData(),
            widget->isEnabled() ? 1 : 0,
            widget->isVisible() ? 1 : 0);

    const QObjectList children = widget->children();
    for (QObject* child : children) {
        QWidget* childWidget = qobject_cast<QWidget*>(child);
        if (!childWidget)
            continue;
        dumpRegionWidgetsRecursive(childWidget, host, region, depth + 1, maxDepth);
    }
}

static void dumpQuickObjectsInRegionRecursive(QObject* obj,
                                              QWidget* quickWidget,
                                              QWidget* host,
                                              const QRect& region,
                                              int depth,
                                              int maxDepth) {
    if (!obj || !quickWidget || !host || depth > maxDepth)
        return;
    QRect rect = qmlObjectRectInHost(obj, quickWidget, host);
    bool hasSize = rect.width() > 0 && rect.height() > 0;
    if (hasSize && !rect.intersects(region))
        return;
    if (!objectBoolProperty(obj, "visible", true))
        return;

    QString indent(depth * 2, ' ');
    QString text;
    const QMetaObject* mo = obj->metaObject();
    if (mo) {
        int textIdx = mo->indexOfProperty("text");
        if (textIdx >= 0) {
            QVariant value = mo->property(textIdx).read(obj);
            if (value.isValid() && value.canConvert<QString>())
                text = normalizedToolbarText(value.toString());
        }
    }

    fprintf(stderr,
            "[MC][UIDUMP] %sQML %s name='%s' rect=(%d,%d %dx%d) text='%s' enabled=%d visible=%d\n",
            indent.toUtf8().constData(),
            obj->metaObject() ? obj->metaObject()->className() : "(no-meta)",
            obj->objectName().toUtf8().constData(),
            rect.x(), rect.y(), rect.width(), rect.height(),
            text.toUtf8().constData(),
            objectBoolProperty(obj, "enabled", true) ? 1 : 0,
            objectBoolProperty(obj, "visible", true) ? 1 : 0);

    for (QObject* child : obj->children())
        dumpQuickObjectsInRegionRecursive(child, quickWidget, host, region, depth + 1, maxDepth);
}

static void dumpPreampUiRegions(const char* phaseTag) {
    QWidget* host = findLargestVisibleTopLevelWidget();
    if (!host) {
        fprintf(stderr, "[MC][UIDUMP] %sno visible host window\n", phaseTag ? phaseTag : "");
        return;
    }
    QRect leftRegion(120, 240, 140, 430);
    QRect rightRegion(610, 240, 150, 430);
    fprintf(stderr,
            "[MC][UIDUMP] %shost=%s size=%dx%d leftRegion=(%d,%d %dx%d) rightRegion=(%d,%d %dx%d)\n",
            phaseTag ? phaseTag : "",
            host->metaObject() ? host->metaObject()->className() : "(no-meta)",
            host->width(),
            host->height(),
            leftRegion.x(), leftRegion.y(), leftRegion.width(), leftRegion.height(),
            rightRegion.x(), rightRegion.y(), rightRegion.width(), rightRegion.height());

    fprintf(stderr, "[MC][UIDUMP] %sLEFT REGION\n", phaseTag ? phaseTag : "");
    dumpRegionWidgetsRecursive(host, host, leftRegion, 0, 7);
    fprintf(stderr, "[MC][UIDUMP] %sRIGHT REGION\n", phaseTag ? phaseTag : "");
    dumpRegionWidgetsRecursive(host, host, rightRegion, 0, 7);

    QObject* quickObj = host->findChild<QObject*>("mainQmlWidget");
    QWidget* quickWidget = host->findChild<QWidget*>("mainQmlWidget");
    if (quickObj && quickWidget) {
        fprintf(stderr, "[MC][UIDUMP] %sLEFT REGION QML\n", phaseTag ? phaseTag : "");
        dumpQuickObjectsInRegionRecursive(quickObj, quickWidget, host, leftRegion, 0, 8);
        fprintf(stderr, "[MC][UIDUMP] %sRIGHT REGION QML\n", phaseTag ? phaseTag : "");
        dumpQuickObjectsInRegionRecursive(quickObj, quickWidget, host, rightRegion, 0, 8);
    }
}

static void dumpWestBindingForSelectedChannel(const char* phaseTag) {
    auto readAsciiPreview = [](void* ptr, char* out, size_t outSize) {
        if (!out || outSize == 0)
            return;
        out[0] = '\0';
        if (!ptr || (uintptr_t)ptr < 0x100000000ULL)
            return;
        size_t maxChars = outSize - 1;
        for (size_t i = 0; i < maxChars; i++) {
            char ch = '\0';
            if (!safeRead((char*)ptr + i, &ch, sizeof(ch)))
                break;
            if (ch == '\0')
                break;
            if ((unsigned char)ch < 32 || (unsigned char)ch > 126)
                break;
            out[i] = ch;
            out[i + 1] = '\0';
        }
    };
    bool dumpDriverQtProps = autotestEnvEnabled("MC_AUTOTEST_WEST_DRIVER_QT_PROPS");

    int ch = getSelectedInputChannel(false);
    if (ch < 0 || ch >= 128) {
        fprintf(stderr,
                "[MC][WESTBIND] %sno selected input channel\n",
                phaseTag ? phaseTag : "");
        return;
    }

    PatchData patch = {};
    if (!readPatchData(ch, patch)) {
        fprintf(stderr,
                "[MC][WESTBIND] %sselected ch %d patch unavailable\n",
                phaseTag ? phaseTag : "",
                ch + 1);
        return;
    }

    fprintf(stderr,
            "[MC][WESTBIND] %sselected ch=%d source={type=%u,num=%u}",
            phaseTag ? phaseTag : "",
            ch + 1,
            patch.source.type,
            patch.source.number);
    void* selectedChannelObj = getInputChannel(ch);
    int selectedSocketNum = -1;
    if (getAnalogueSocketIndexForAudioSource(patch.source, selectedSocketNum)) {
        fprintf(stderr,
                " channelObj=%p socket=%d analogueObj=%p\n",
                selectedChannelObj,
                selectedSocketNum,
                getAnalogueInput(selectedSocketNum));
    } else {
        fprintf(stderr, " channelObj=%p socket=(n/a) analogueObj=%p\n", selectedChannelObj, nullptr);
    }

    for (int probeCh = std::max(0, ch - 2); probeCh <= std::min(127, ch + 2); ++probeCh) {
        PatchData probePatch = {};
        if (!readPatchData(probeCh, probePatch))
            continue;
        fprintf(stderr,
                "[MC][WESTBIND] %snearby ch=%d source={type=%u,num=%u}",
                phaseTag ? phaseTag : "",
                probeCh + 1,
                probePatch.source.type,
                probePatch.source.number);
        int probeSocketNum = -1;
        if (getAnalogueSocketIndexForAudioSource(probePatch.source, probeSocketNum)) {
            fprintf(stderr,
                    " socket=%d analogueObj=%p\n",
                    probeSocketNum,
                    getAnalogueInput(probeSocketNum));
        } else {
            fprintf(stderr, " socket=(n/a) analogueObj=%p\n", nullptr);
        }
    }

    QList<QObject*> forms = collectWestProcessingForms();
    int formsTouched = 0;
    for (QObject* obj : forms) {
        char* raw = (char*)obj;
        void* gainRotary = *(void**)(raw + 0xc8);
        void* gainText = *(void**)(raw + 0xd0);
        void* padExponent = *(void**)(raw + 0xe8);
        void* trimRotary = *(void**)(raw + 0xf8);
        void* trimText = *(void**)(raw + 0x100);
        void* dynamicAssign = *(void**)(raw + 0x128);
        void* preampModelWatcher = *(void**)(raw + 0x140);
        void* socketStatusWatcher = *(void**)(raw + 0x160);
        void* onSurfaceWatcher = *(void**)(raw + 0x190);
        void* currentChannelObj = *(void**)(raw + 0x200);
        formsTouched++;

        fprintf(stderr,
                "[MC][WESTBIND] %sform=%p currentChannel=%p gainRotary=%p gainText=%p padExponent=%p trimRotary=%p trimText=%p dynAssign=%p modelWatcher=%p socketWatcher=%p surfaceWatcher=%p\n",
                phaseTag ? phaseTag : "",
                obj,
                currentChannelObj,
                gainRotary,
                gainText,
                padExponent,
                trimRotary,
                trimText,
                dynamicAssign,
                preampModelWatcher,
                socketStatusWatcher,
                onSurfaceWatcher);

        auto dumpWrapper = [&](const char* label, void* wrapper) {
            if (!wrapper)
                return;
            void* wrapperVt = nullptr;
            uint32_t kind = 0;
            void* ptr18 = nullptr;
            void* ptr20 = nullptr;
            void* chosen = nullptr;
            void* linkedAudioObj = nullptr;
            void* linkedVt = nullptr;
            uint16_t lower = 0;
            uint16_t upper = 0;
            uint16_t controllerValue = 0;
            uint8_t controllerTouched = 0;
            void* controllerDriver = nullptr;
            void* controllerNamePtr = nullptr;
            char controllerName[96] = {};

            safeRead(wrapper, &wrapperVt, sizeof(wrapperVt));
            safeRead((char*)wrapper + 0x10, &kind, sizeof(kind));
            safeRead((char*)wrapper + 0x18, &ptr18, sizeof(ptr18));
            safeRead((char*)wrapper + 0x20, &ptr20, sizeof(ptr20));
            chosen = (kind == 2) ? ptr20 : ptr18;
            if (chosen && (uintptr_t)chosen >= 0x100000000ULL) {
                safeRead(chosen, &linkedVt, sizeof(linkedVt));
                safeRead((char*)chosen + 0x8, &linkedAudioObj, sizeof(linkedAudioObj));
                safeRead((char*)chosen + 0x10, &lower, sizeof(lower));
                safeRead((char*)chosen + 0x12, &upper, sizeof(upper));
                if (linkedAudioObj && (uintptr_t)linkedAudioObj >= 0x100000000ULL) {
                    safeRead((char*)linkedAudioObj + 0x80, &controllerValue, sizeof(controllerValue));
                    safeRead((char*)linkedAudioObj + 0x82, &controllerTouched, sizeof(controllerTouched));
                    safeRead((char*)linkedAudioObj + 0x88, &controllerDriver, sizeof(controllerDriver));
                    safeRead((char*)linkedAudioObj + 0x8, &controllerNamePtr, sizeof(controllerNamePtr));
                    readAsciiPreview(controllerNamePtr, controllerName, sizeof(controllerName));
                }
            }
            fprintf(stderr,
                    "[MC][WESTBIND] %sform=%p %s wrapper=%p vt=%p kind=%u ptr18=%p ptr20=%p chosen=%p linkedVt=%p linkedAudioObj=%p controllerName='%s' controllerDriver=%p cachedValue=%u cachedSigned=%d touched=%u rawRange=[%u,%u]\n",
                    phaseTag ? phaseTag : "",
                    obj,
                    label,
                    wrapper,
                    wrapperVt,
                    (unsigned)kind,
                    ptr18,
                    ptr20,
                    chosen,
                    linkedVt,
                    linkedAudioObj,
                    controllerName,
                    controllerDriver,
                    (unsigned)controllerValue,
                    (int16_t)controllerValue,
                    (unsigned)controllerTouched,
                    (unsigned)lower,
                    (unsigned)upper);

            if (dumpDriverQtProps && controllerDriver && (uintptr_t)controllerDriver >= 0x100000000ULL) {
                QObject* driverObj = reinterpret_cast<QObject*>(controllerDriver);
                const QMetaObject* mo = driverObj->metaObject();
                QString className = mo ? QString::fromLatin1(mo->className()) : QString();
                QString objectName = driverObj->objectName();
                QVariant netObjectName = driverObj->property("netObjectName");
                QVariant value = driverObj->property("value");
                QVariant rangeLower = driverObj->property("rangeLower");
                QVariant rangeUpper = driverObj->property("rangeUpper");
                QVariant zeroValue = driverObj->property("zeroValue");
                fprintf(stderr,
                        "[MC][WESTBIND] %sform=%p %s driverQt class='%s' objectName='%s' netObjectName='%s' value='%s' rangeLower='%s' rangeUpper='%s' zeroValue='%s'\n",
                        phaseTag ? phaseTag : "",
                        obj,
                        label,
                        className.toUtf8().constData(),
                        objectName.toUtf8().constData(),
                        netObjectName.toString().toUtf8().constData(),
                        value.toString().toUtf8().constData(),
                        rangeLower.toString().toUtf8().constData(),
                        rangeUpper.toString().toUtf8().constData(),
                        zeroValue.toString().toUtf8().constData());
            }
        };

        dumpWrapper("gainRotary", gainRotary);
        dumpWrapper("gainText", gainText);
        dumpWrapper("trimRotary", trimRotary);
        dumpWrapper("trimText", trimText);
    }

    fprintf(stderr,
            "[MC][WESTBIND] %sforms=%d\n",
            phaseTag ? phaseTag : "",
            formsTouched);
}

static QList<QObject*> collectWestProcessingForms() {
    QList<QObject*> targets;
    auto addTarget = [&](QObject* obj) {
        if (!obj || targets.contains(obj))
            return;
        if (classNameContains(obj, "WestProcessingForm"))
            targets.push_back(obj);
    };

    if (qApp) {
        addTarget(qApp);
        for (QObject* obj : qApp->findChildren<QObject*>())
            addTarget(obj);
    }
    for (QWidget* widget : QApplication::allWidgets()) {
        addTarget(widget);
        for (QObject* obj : widget->findChildren<QObject*>())
            addTarget(obj);
    }
    return targets;
}

static void relinkWestPreampControlWrappers(const char* phaseTag) {
    typedef void* (*fn_SurfaceDiscoveryInstance)();
    typedef void* (*fn_GetSurfaceDiscoveryObject)(void*);
    typedef void (*fn_UserControlDriverWrapperLink)(void*, const char*, unsigned int, unsigned char, bool);
    typedef void (*fn_AHCCExponentSwitcherLink)(void*, const char*, unsigned short, unsigned char);

    auto surfaceDiscoveryInstance = (fn_SurfaceDiscoveryInstance)RESOLVE(0x1006ab790);
    auto getSurfaceDiscoveryObject = (fn_GetSurfaceDiscoveryObject)RESOLVE(0x1006ab820);
    auto wrapperLink = (fn_UserControlDriverWrapperLink)RESOLVE(0x10013a3d0);
    auto exponentLink = (fn_AHCCExponentSwitcherLink)RESOLVE(0x100122400);

    if (!surfaceDiscoveryInstance || !getSurfaceDiscoveryObject || !wrapperLink)
        return;

    void* discovery = surfaceDiscoveryInstance();
    if (!discovery)
        return;
    char* surfaceObj = (char*)getSurfaceDiscoveryObject(discovery);
    if (!surfaceObj)
        return;

    char selectorLitePath[512] = {};
    snprintf(selectorLitePath,
             sizeof(selectorLitePath),
             "%s%s",
             surfaceObj + 0x99,
             "Control Surface Channel Selector Lite");

    QList<QObject*> forms = collectWestProcessingForms();
    int formsTouched = 0;
    int actions = 0;
    for (QObject* obj : forms) {
        char* raw = (char*)obj;
        formsTouched++;

        void* gainRotary = *(void**)(raw + 0xc8);
        void* gainText = *(void**)(raw + 0xd0);
        void* padExponent = *(void**)(raw + 0xe8);
        void* trimRotary = *(void**)(raw + 0xf8);
        void* trimText = *(void**)(raw + 0x100);

        if (gainRotary) {
            wrapperLink(gainRotary, selectorLitePath, 0x1008, 0, true);
            actions++;
        }
        if (gainText) {
            wrapperLink(gainText, selectorLitePath, 0x1008, 0, true);
            actions++;
        }
        if (padExponent && exponentLink) {
            exponentLink(padExponent, selectorLitePath, 0x100b, 0);
            actions++;
        }
        if (trimRotary) {
            wrapperLink(trimRotary, selectorLitePath, 0x1009, 0, true);
            actions++;
        }
        if (trimText) {
            wrapperLink(trimText, selectorLitePath, 0x1009, 0, true);
            actions++;
        }
    }

    fprintf(stderr,
            "[MC] %swest wrapper relink: forms=%d actions=%d path='%s'\n",
            phaseTag ? phaseTag : "",
            formsTouched,
            actions,
            selectorLitePath);
}

static void pushWestPreampGainValue(int ch, const char* phaseTag) {
    typedef uint16_t (*fn_UserControlDriverWrapperGetControllerRangeLower)(void*);
    typedef uint16_t (*fn_UserControlDriverWrapperGetControllerRangeUpper)(void*);
    typedef void (*fn_UserControlDriverWrapperPostContinuousControllerValue)(void*, uint16_t);
    typedef void (*fn_UserControlDriverWrapperPostContinuousControllerRangeAndValue)(void*, uint16_t, uint16_t, uint16_t);
    typedef void* (*fn_UserControlDriverWrapperGetAudioObject)(void*);

    if (ch < 0 || ch >= 128)
        return;

    auto getRangeLower = (fn_UserControlDriverWrapperGetControllerRangeLower)RESOLVE(0x10013a430);
    auto getRangeUpper = (fn_UserControlDriverWrapperGetControllerRangeUpper)RESOLVE(0x10013a470);
    auto postValue = (fn_UserControlDriverWrapperPostContinuousControllerValue)RESOLVE(0x10013a4b0);
    auto postRangeValue = (fn_UserControlDriverWrapperPostContinuousControllerRangeAndValue)RESOLVE(0x10013a4f0);
    auto getAudioObject = (fn_UserControlDriverWrapperGetAudioObject)RESOLVE(0x10013a530);
    if ((!postRangeValue && !postValue) || !getRangeLower || !getRangeUpper)
        return;

    PatchData livePatch = {};
    if (!readPatchData(ch, livePatch))
        return;

    PreampData pd = {};
    if (!readPreampDataForPatch(livePatch, pd))
        return;

    uint16_t rawValue = (uint16_t)pd.gain;
    QList<QObject*> forms = collectWestProcessingForms();
    int formsTouched = 0;
    int posts = 0;
    for (QObject* obj : forms) {
        char* raw = (char*)obj;
        void* gainRotary = *(void**)(raw + 0xc8);
        void* gainText = *(void**)(raw + 0xd0);
        formsTouched++;

        auto postWrapper = [&](const char* label, void* wrapper) {
            if (!wrapper)
                return;
            uint16_t lower = getRangeLower(wrapper);
            uint16_t upper = getRangeUpper(wrapper);
            void* audioObj = getAudioObject ? getAudioObject(wrapper) : nullptr;
            int controllerSigned = 0x8000 + (int)pd.gain;
            if (controllerSigned < (int)lower)
                controllerSigned = (int)lower;
            if (controllerSigned > (int)upper)
                controllerSigned = (int)upper;
            uint16_t controllerValue = (uint16_t)controllerSigned;
            fprintf(stderr,
                    "[MC] %swest gain push ch %d %s wrapper=%p audioObj=%p range=[%u,%u] raw=%u signed=%d controller=%u\n",
                    phaseTag ? phaseTag : "",
                    ch + 1,
                    label,
                    wrapper,
                    audioObj,
                    (unsigned)lower,
                    (unsigned)upper,
                    (unsigned)rawValue,
                    (int16_t)rawValue,
                    (unsigned)controllerValue);
            if (postRangeValue)
                postRangeValue(wrapper, lower, upper, controllerValue);
            else
                postValue(wrapper, controllerValue);
            posts++;
        };

        postWrapper("rotary", gainRotary);
        postWrapper("text", gainText);
    }

    fprintf(stderr,
            "[MC] %swest gain push summary: ch=%d forms=%d posts=%d raw=%u signed=%d\n",
            phaseTag ? phaseTag : "",
            ch + 1,
            formsTouched,
            posts,
            (unsigned)rawValue,
            (int16_t)rawValue);
}

static void scheduleWestPreampGainPush(int ch, const char* phaseTag) {
    if (!westPreampGainPushEnabled())
        return;
    if (ch < 0 || ch >= 128)
        return;
    pushWestPreampGainValue(ch, phaseTag);
    QTimer::singleShot(150, qApp, [ch]() {
        pushWestPreampGainValue(ch, "[MC] (delayed 150ms) ");
    });
    QTimer::singleShot(600, qApp, [ch]() {
        pushWestPreampGainValue(ch, "[MC] (delayed 600ms) ");
    });
}

static void scheduleWestPreampGainPushForCurrentSelection(const char* phaseTag) {
    if (!westPreampGainPushEnabled())
        return;

    auto tryPush = [phaseTag](const char* attemptTag) {
        int ch = getSelectedInputChannel(false);
        if (ch >= 0) {
            fprintf(stderr,
                    "[MC] %scurrent-selection west gain push: selected ch %d\n",
                    attemptTag ? attemptTag : (phaseTag ? phaseTag : ""),
                    ch + 1);
            scheduleWestPreampGainPush(ch, attemptTag ? attemptTag : phaseTag);
            return;
        }
        fprintf(stderr,
                "[MC] %scurrent-selection west gain push: no selected input channel yet\n",
                attemptTag ? attemptTag : (phaseTag ? phaseTag : ""));
    };

    tryPush(phaseTag);
    QTimer::singleShot(250, qApp, [phaseTag, tryPush]() {
        tryPush("[MC] final-preamp: (delayed 250ms) ");
    });
    QTimer::singleShot(1000, qApp, [phaseTag, tryPush]() {
        tryPush("[MC] final-preamp: (delayed 1000ms) ");
    });
    QTimer::singleShot(2500, qApp, [phaseTag, tryPush]() {
        tryPush("[MC] final-preamp: (delayed 2500ms) ");
    });
}

static void runWestUserControlDriverExperiment(const char* phaseTag) {
    typedef void (*fn_cUserControlCCDriverQObjectPostNewUserValue)(void*, uint16_t);
    typedef void (*fn_cUserControlCCDriverQObjectWriteControllerValue)(void*, uint16_t);

    auto postNewUserValue =
        (fn_cUserControlCCDriverQObjectPostNewUserValue)RESOLVE(0x100136f20);
    auto writeControllerValue =
        (fn_cUserControlCCDriverQObjectWriteControllerValue)RESOLVE(0x1001372b0);

    bool usePostUser = autotestEnvEnabled("MC_AUTOTEST_WEST_DRIVER_POST_USER");
    bool useWriteValue = autotestEnvEnabled("MC_AUTOTEST_WEST_DRIVER_WRITE_VALUE");
    if ((!usePostUser || !postNewUserValue) &&
        (!useWriteValue || !writeControllerValue))
        return;

    int ch = getSelectedInputChannel(false);
    if (ch < 0 || ch >= 128)
        return;

    PatchData livePatch = {};
    if (!readPatchData(ch, livePatch))
        return;

    PreampData pd = {};
    if (!readPreampDataForPatch(livePatch, pd))
        return;

    int controllerValue = 0x8000 + (int)pd.gain;
    QList<QObject*> forms = collectWestProcessingForms();
    int actions = 0;
    for (QObject* obj : forms) {
        char* raw = (char*)obj;
        void* gainRotary = *(void**)(raw + 0xc8);
        void* gainText = *(void**)(raw + 0xd0);
        auto updateWrapper = [&](const char* label, void* wrapper) {
            if (!wrapper)
                return;
            uint32_t kind = 0;
            void* ptr18 = nullptr;
            void* ptr20 = nullptr;
            safeRead((char*)wrapper + 0x10, &kind, sizeof(kind));
            safeRead((char*)wrapper + 0x18, &ptr18, sizeof(ptr18));
            safeRead((char*)wrapper + 0x20, &ptr20, sizeof(ptr20));
            void* driver = (kind == 2) ? ptr20 : ptr18;
            if (!driver || (uintptr_t)driver < 0x100000000ULL)
                return;
            fprintf(stderr,
                    "[MC] %swest user-control driver: ch=%d %s wrapper=%p driver=%p encoded=%d signedGain=%d post=%d write=%d\n",
                    phaseTag ? phaseTag : "",
                    ch + 1,
                    label,
                    wrapper,
                    driver,
                    controllerValue,
                    pd.gain,
                    usePostUser ? 1 : 0,
                    useWriteValue ? 1 : 0);
            if (usePostUser && postNewUserValue) {
                postNewUserValue(driver, (uint16_t)controllerValue);
                actions++;
            }
            if (useWriteValue && writeControllerValue) {
                writeControllerValue(driver, (uint16_t)controllerValue);
                actions++;
            }
        };
        updateWrapper("gainRotary", gainRotary);
        updateWrapper("gainText", gainText);
    }

    fprintf(stderr,
            "[MC] %swest user-control driver summary: ch=%d forms=%d actions=%d encoded=%d signedGain=%d post=%d write=%d\n",
            phaseTag ? phaseTag : "",
            ch + 1,
            forms.size(),
            actions,
            controllerValue,
            pd.gain,
            usePostUser ? 1 : 0,
            useWriteValue ? 1 : 0);
    QApplication::processEvents();
}

static void syncWestPreampUiToSelectedChannel(bool force, const char* phaseTag) {
    QList<QObject*> forms = collectWestProcessingForms();
    int formCount = forms.size();
    if (formCount <= 0) {
        g_westPreampSyncLastForms = 0;
        return;
    }

    int ch = getSelectedInputChannel(false);
    if (ch < 0 || ch >= 128)
        return;

    PatchData livePatch = {};
    if (!readPatchData(ch, livePatch))
        return;

    int socketNum = -1;
    if (!patchDataUsesSocketBackedPreamp(livePatch) ||
        !getAnalogueSocketIndexForAudioSource(livePatch.source, socketNum)) {
        return;
    }

    PreampData pd = {};
    if (!readPreampDataForPatch(livePatch, pd))
        return;

    if (!force &&
        ch == g_westPreampSyncLastChannel &&
        socketNum == g_westPreampSyncLastSocket &&
        pd.gain == g_westPreampSyncLastGain &&
        pd.pad == g_westPreampSyncLastPad &&
        pd.phantom == g_westPreampSyncLastPhantom &&
        formCount == g_westPreampSyncLastForms) {
        return;
    }

    pushWestPreampGainValue(ch, phaseTag ? phaseTag : "[MC] west sync ");
    g_westPreampSyncLastChannel = ch;
    g_westPreampSyncLastSocket = socketNum;
    g_westPreampSyncLastGain = pd.gain;
    g_westPreampSyncLastPad = pd.pad;
    g_westPreampSyncLastPhantom = pd.phantom;
    g_westPreampSyncLastForms = formCount;
}

static void refreshWestProcessingForChannel(int ch, const char* phaseTag) {
    typedef void (*fn_WestProcessingFormChangeChannel)(void*, void*);
    typedef void (*fn_WestProcessingFormReceivePointUpdated)(void*, void*);
    typedef void (*fn_WestProcessingFormSocketStatusUpdated)(void*);
    typedef void (*fn_WestProcessingFormLink)(void*);
    typedef void (*fn_WestProcessingFormPreampModelModeChanged)(void*);

    if (ch < 0 || ch >= 128)
        return;

    void* selectedChannelObj = getInputChannel(ch);
    if (!selectedChannelObj)
        return;

    auto changeChannel = (fn_WestProcessingFormChangeChannel)RESOLVE(0x100d69350);
    auto receivePointUpdated =
        (fn_WestProcessingFormReceivePointUpdated)RESOLVE(0x100d6a920);
    auto socketStatusUpdated =
        (fn_WestProcessingFormSocketStatusUpdated)RESOLVE(0x100d6a810);
    auto link = (fn_WestProcessingFormLink)RESOLVE(0x100d697c0);
    auto preampModelModeChanged = (fn_WestProcessingFormPreampModelModeChanged)RESOLVE(0x100d69b20);
    bool useDeepRelink = autotestEnvEnabled("MC_AUTOTEST_WEST_DEEP_RELINK");

    QList<QObject*> forms = collectWestProcessingForms();
    int actions = 0;
    for (QObject* obj : forms) {
        void* raw = obj;
        if (changeChannel) {
            changeChannel(raw, selectedChannelObj);
            actions++;
        }
        if (selectedChannelObj && receivePointUpdated) {
            receivePointUpdated(raw, selectedChannelObj);
            actions++;
        }
        if (socketStatusUpdated) {
            socketStatusUpdated(raw);
            actions++;
        }
        if (useDeepRelink && link) {
            link(raw);
            actions++;
        }
        if (useDeepRelink && preampModelModeChanged) {
            preampModelModeChanged(raw);
            actions++;
        }
    }

    fprintf(stderr,
            "[MC] %swest refresh after selection: ch=%d channelObj=%p forms=%d actions=%d deepRelink=%d\n",
            phaseTag ? phaseTag : "",
            ch + 1,
            selectedChannelObj,
            forms.size(),
            actions,
            useDeepRelink ? 1 : 0);
    QApplication::processEvents();
}

static void runWestProcessingRefreshExperiment(const char* phaseTag) {
    typedef void (*fn_WestProcessingFormChangeChannel)(void*, void*);
    typedef void (*fn_WestProcessingFormReceivePointUpdated)(void*, void*);
    typedef void (*fn_WestProcessingFormSocketStatusUpdated)(void*);
    typedef void (*fn_WestProcessingFormPreampOnSurfaceChanged)(void*, unsigned char);
    typedef void (*fn_WestProcessingFormSetActiveInputText)(void*, unsigned char);

    auto changeChannel =
        (fn_WestProcessingFormChangeChannel)RESOLVE(0x100d69350);
    auto receivePointUpdated =
        (fn_WestProcessingFormReceivePointUpdated)RESOLVE(0x100d6a920);
    auto socketStatusUpdated =
        (fn_WestProcessingFormSocketStatusUpdated)RESOLVE(0x100d6a810);
    auto preampOnSurfaceChanged =
        (fn_WestProcessingFormPreampOnSurfaceChanged)RESOLVE(0x100d6a940);
    auto setActiveInputText =
        (fn_WestProcessingFormSetActiveInputText)RESOLVE(0x100d69f80);

    int selectedInputCh = getSelectedInputChannel(false);
    void* selectedChannelObj =
        (selectedInputCh >= 0) ? getInputChannel(selectedInputCh) : nullptr;
    QList<QObject*> forms = collectWestProcessingForms();
    int actions = 0;
    bool doChange = !getenv("MC_AUTOTEST_WEST_ONLY_RECEIVE") &&
                    !getenv("MC_AUTOTEST_WEST_ONLY_SOCKET") &&
                    !getenv("MC_AUTOTEST_WEST_ONLY_SURFACE") &&
                    !getenv("MC_AUTOTEST_WEST_ONLY_ACTIVE_INPUT");
    bool doReceive = doChange;
    bool doSocket = doChange;
    bool doSurface = doChange;
    bool doActiveInput = doChange;
    if (getenv("MC_AUTOTEST_WEST_ONLY_RECEIVE")) {
        doChange = false; doReceive = true; doSocket = false; doSurface = false; doActiveInput = false;
    }
    if (getenv("MC_AUTOTEST_WEST_ONLY_SOCKET")) {
        doChange = false; doReceive = false; doSocket = true; doSurface = false; doActiveInput = false;
    }
    if (getenv("MC_AUTOTEST_WEST_ONLY_SURFACE")) {
        doChange = false; doReceive = false; doSocket = false; doSurface = true; doActiveInput = false;
    }
    if (getenv("MC_AUTOTEST_WEST_ONLY_ACTIVE_INPUT")) {
        doChange = false; doReceive = false; doSocket = false; doSurface = false; doActiveInput = true;
    }
    for (QObject* obj : forms) {
        void* raw = obj;
        if (selectedChannelObj && changeChannel && doChange) {
            fprintf(stderr, "[MC] %swest experiment: ChangeChannel begin form=%p ch=%d obj=%p\n",
                    phaseTag ? phaseTag : "", raw, selectedInputCh + 1, selectedChannelObj);
            changeChannel(raw, selectedChannelObj);
            fprintf(stderr, "[MC] %swest experiment: ChangeChannel end form=%p\n",
                    phaseTag ? phaseTag : "", raw);
            actions++;
        }
        if (selectedChannelObj && receivePointUpdated && doReceive) {
            fprintf(stderr, "[MC] %swest experiment: ReceivePointUpdated begin form=%p ch=%d obj=%p\n",
                    phaseTag ? phaseTag : "", raw, selectedInputCh + 1, selectedChannelObj);
            receivePointUpdated(raw, selectedChannelObj);
            fprintf(stderr, "[MC] %swest experiment: ReceivePointUpdated end form=%p\n",
                    phaseTag ? phaseTag : "", raw);
            actions++;
        }
        if (socketStatusUpdated && doSocket) {
            fprintf(stderr, "[MC] %swest experiment: SocketStatusUpdated begin form=%p\n",
                    phaseTag ? phaseTag : "", raw);
            socketStatusUpdated(raw);
            fprintf(stderr, "[MC] %swest experiment: SocketStatusUpdated end form=%p\n",
                    phaseTag ? phaseTag : "", raw);
            actions++;
        }
        if (preampOnSurfaceChanged && doSurface) {
            fprintf(stderr, "[MC] %swest experiment: PreampOnSurfaceChanged begin form=%p arg=0\n",
                    phaseTag ? phaseTag : "", raw);
            preampOnSurfaceChanged(raw, 0);
            fprintf(stderr, "[MC] %swest experiment: PreampOnSurfaceChanged end form=%p\n",
                    phaseTag ? phaseTag : "", raw);
            actions++;
        }
        if (setActiveInputText && doActiveInput) {
            fprintf(stderr, "[MC] %swest experiment: SetActiveInputText begin form=%p arg=0\n",
                    phaseTag ? phaseTag : "", raw);
            setActiveInputText(raw, 0);
            fprintf(stderr, "[MC] %swest experiment: SetActiveInputText end form=%p\n",
                    phaseTag ? phaseTag : "", raw);
            actions++;
        }
    }
    fprintf(stderr,
            "[MC] %swest refresh experiment: selectedCh=%d channelObj=%p forms=%d actions=%d\n",
            phaseTag ? phaseTag : "",
            selectedInputCh >= 0 ? selectedInputCh + 1 : -1,
            selectedChannelObj,
            forms.size(),
            actions);
    QApplication::processEvents();
}

static void runSelectorLitePreampExperiment(const char* phaseTag) {
    typedef void (*fn_ChannelSelectorLiteUpdateInputPreAmp)(void*);
    typedef void (*fn_ChannelSelectorLiteUpdateInputPreAmpSingle)(void*, unsigned char);
    typedef void (*fn_ChannelSelectorLiteUpdateDL5000ControlSurfaceControls)(void*);
    typedef void (*fn_ChannelSelectorInformDL5000ControlSurfacePreAmpControls)(void*, unsigned char, int);
    typedef void (*fn_ChannelSelectorLiteLinkSurfacePreAmp)(void*, unsigned char, int, unsigned int, const sAudioSource&, bool, bool, unsigned char, bool);
    typedef void (*fn_SurfaceChannelsUpdateInputPreAmp)(void*, unsigned char);
    typedef void (*fn_SurfaceChannelsUpdateInputPreAmps)(void*);

    auto updateInputPreAmp =
        (fn_ChannelSelectorLiteUpdateInputPreAmp)RESOLVE(0x10032e690);
    auto updateInputPreAmpSingle =
        (fn_ChannelSelectorLiteUpdateInputPreAmpSingle)RESOLVE(0x10032d390);
    auto updateSurfaceControls =
        (fn_ChannelSelectorLiteUpdateDL5000ControlSurfaceControls)RESOLVE(0x10032d260);
    auto informPreampControls =
        (fn_ChannelSelectorInformDL5000ControlSurfacePreAmpControls)RESOLVE(0x1001ddcd0);
    auto linkSurfacePreAmp =
        (fn_ChannelSelectorLiteLinkSurfacePreAmp)RESOLVE(0x10032d2f0);
    auto surfaceUpdateInputPreAmp =
        (fn_SurfaceChannelsUpdateInputPreAmp)RESOLVE(0x10040d7c0);
    auto surfaceUpdateInputPreAmps =
        (fn_SurfaceChannelsUpdateInputPreAmps)RESOLVE(0x10040d730);

    bool doInputPreamp = true;
    bool doSurfaceControls = true;
    bool doLink = autotestEnvEnabled("MC_AUTOTEST_SELECTOR_LITE_LINK_EXPERIMENT");
    if (getenv("MC_AUTOTEST_SELECTOR_LITE_ONLY_INPUT_PREAMP")) {
        doInputPreamp = true;
        doSurfaceControls = false;
    }
    if (getenv("MC_AUTOTEST_SELECTOR_LITE_ONLY_SURFACE_CONTROLS")) {
        doInputPreamp = false;
        doSurfaceControls = true;
    }

    int selectedInputCh = getSelectedInputChannel(false);
    int actions = 0;
    fprintf(stderr,
            "[MC] %sselector-lite experiment: begin selectedCh=%d selectorLite=%p doInputPreamp=%d doSurfaceControls=%d\n",
            phaseTag ? phaseTag : "",
            selectedInputCh >= 0 ? selectedInputCh + 1 : -1,
            g_channelSelectorLite,
            doInputPreamp ? 1 : 0,
            doSurfaceControls ? 1 : 0);

    discoverSelectorManagerFromChannelMapper(phaseTag);

    if (!g_channelSelectorLite) {
        g_channelSelectorLite = findSurfaceDiscoveryNamedObject("Control Surface Channel Selector Lite");
        if (g_channelSelectorLite) {
            fprintf(stderr,
                    "[MC] %sselector-lite experiment: discovered via SurfaceDiscovery = %p\n",
                    phaseTag ? phaseTag : "",
                    g_channelSelectorLite);
        }
    }
    if (!g_channelSelectorLite) {
        uintptr_t selectorLiteVt = (uintptr_t)0x106c7c098 + g_slide + 0x10;
        std::array<std::pair<const char*, void*>, 3> roots = {{
            {"AppInstance", g_AppInstance ? g_AppInstance() : nullptr},
            {"UIManagerHolder", g_uiManagerHolder},
            {"qApp", qApp},
        }};
        for (const auto& [label, root] : roots) {
            if (!root)
                continue;
            g_channelSelectorLite = findChildObjectByVtable(root, selectorLiteVt, 0x800, 0x800);
            if (g_channelSelectorLite) {
                fprintf(stderr,
                        "[MC] %sselector-lite experiment: discovered from %s = %p\n",
                        phaseTag ? phaseTag : "",
                        label,
                        g_channelSelectorLite);
                break;
            }
        }
    }
    if (!g_surfaceChannels) {
        const uintptr_t selectorLiteVt = (uintptr_t)0x106c7c098 + g_slide + 0x10;
        const uintptr_t surfaceChannelsVt = (uintptr_t)0x106ce5900 + g_slide + 0x10;
        void* app = g_AppInstance ? g_AppInstance() : nullptr;
        void* selectorContainer = nullptr;
        void* selectorObj = nullptr;
        if (findChildContainerForTargetVtable(app,
                                              selectorLiteVt,
                                              &selectorContainer,
                                              &selectorObj,
                                              0x2000,
                                              0x800)) {
            void* surfaceContainer = nullptr;
            void* surfaceObj = nullptr;
            if (findChildContainerForTargetVtable(selectorContainer,
                                                  surfaceChannelsVt,
                                                  &surfaceContainer,
                                                  &surfaceObj,
                                                  0x8000,
                                                  0x2000)) {
                g_surfaceChannels = surfaceObj;
                fprintf(stderr,
                        "[MC] %sselector-lite experiment: discovered surfaceChannels via selector container=%p object=%p\n",
                        phaseTag ? phaseTag : "",
                        surfaceContainer,
                        g_surfaceChannels);
            }
        }
    }
    if (autotestEnvEnabled("MC_EXPERIMENT_SELECTOR_ROOT_SCAN")) {
        scanRootForKnownSelectorObjects(g_AppInstance ? g_AppInstance() : nullptr,
                                        "AppInstance",
                                        phaseTag,
                                        0x2000,
                                        0x800);
        scanRootForKnownSelectorObjects(g_uiManagerHolder,
                                        "UIManagerHolder",
                                        phaseTag,
                                        0x2000,
                                        0x800);
        scanRootForKnownSelectorObjects(g_channelSelectorLite,
                                        "SelectorLite",
                                        phaseTag,
                                        0x2000,
                                        0x800);
    }

    if (!g_channelSelectorLite && !g_channelSelector) {
        fprintf(stderr,
                "[MC] %sselector-lite experiment: skipped, selector/selectorLite not discovered\n",
                phaseTag ? phaseTag : "");
        return;
    }


    if (doLink && g_channelSelectorLite && selectedInputCh >= 0 && linkSurfacePreAmp) {
        PatchData livePatch = {};
        if (readPatchData(selectedInputCh, livePatch)) {
            bool linkBool1 = autotestEnvEnabled("MC_AUTOTEST_SELECTOR_LITE_LINK_B1");
            bool linkBool2 = autotestEnvEnabled("MC_AUTOTEST_SELECTOR_LITE_LINK_B2");
            bool linkBool3 = autotestEnvEnabled("MC_AUTOTEST_SELECTOR_LITE_LINK_B3");
            unsigned char linkByte =
                (unsigned char)atoi(getenv("MC_AUTOTEST_SELECTOR_LITE_LINK_BYTE") ? getenv("MC_AUTOTEST_SELECTOR_LITE_LINK_BYTE") : "0");
            unsigned int linkWord =
                (unsigned int)atoi(getenv("MC_AUTOTEST_SELECTOR_LITE_LINK_WORD") ? getenv("MC_AUTOTEST_SELECTOR_LITE_LINK_WORD") : "0");
            fprintf(stderr,
                    "[MC] %sselector-lite experiment: LinkSurfacePreAmp begin selectorLite=%p ch=%d audioType=0 word=%u src={type=%u,num=%u} b1=%d b2=%d byte=%u b3=%d\n",
                    phaseTag ? phaseTag : "",
                    g_channelSelectorLite,
                    selectedInputCh + 1,
                    linkWord,
                    livePatch.source.type,
                    livePatch.source.number,
                    linkBool1 ? 1 : 0,
                    linkBool2 ? 1 : 0,
                    (unsigned)linkByte,
                    linkBool3 ? 1 : 0);
            linkSurfacePreAmp(g_channelSelectorLite,
                              (unsigned char)selectedInputCh,
                              0,
                              linkWord,
                              livePatch.source,
                              linkBool1,
                              linkBool2,
                              linkByte,
                              linkBool3);
            fprintf(stderr,
                    "[MC] %sselector-lite experiment: LinkSurfacePreAmp end selectorLite=%p\n",
                    phaseTag ? phaseTag : "",
                    g_channelSelectorLite);
            actions++;
        } else {
            fprintf(stderr,
                    "[MC] %sselector-lite experiment: LinkSurfacePreAmp skipped, failed to read patch for ch=%d\n",
                    phaseTag ? phaseTag : "",
                    selectedInputCh + 1);
        }
    }

    if (doSurfaceControls && updateSurfaceControls) {
        fprintf(stderr,
                "[MC] %sselector-lite experiment: UpdateDL5000ControlSurfaceControls begin selectorLite=%p\n",
                phaseTag ? phaseTag : "",
                g_channelSelectorLite);
        updateSurfaceControls(g_channelSelectorLite);
        fprintf(stderr,
                "[MC] %sselector-lite experiment: UpdateDL5000ControlSurfaceControls end selectorLite=%p\n",
                phaseTag ? phaseTag : "",
                g_channelSelectorLite);
        actions++;
    }

    if (doInputPreamp && updateInputPreAmp) {
        fprintf(stderr,
                "[MC] %sselector-lite experiment: UpdateInputPreAmp begin selectorLite=%p\n",
                phaseTag ? phaseTag : "",
                g_channelSelectorLite);
        updateInputPreAmp(g_channelSelectorLite);
        fprintf(stderr,
                "[MC] %sselector-lite experiment: UpdateInputPreAmp end selectorLite=%p\n",
                phaseTag ? phaseTag : "",
                g_channelSelectorLite);
        actions++;
    }
    if (doInputPreamp && updateInputPreAmpSingle && g_channelSelectorLite && selectedInputCh >= 0) {
        int pairStart = isChannelStereo(selectedInputCh) ? (selectedInputCh & ~1) : selectedInputCh;
        int pairEnd = isChannelStereo(selectedInputCh) ? (pairStart + 1) : selectedInputCh;
        for (int targetCh = pairStart; targetCh <= pairEnd; ++targetCh) {
            fprintf(stderr,
                    "[MC] %sselector-lite experiment: UpdateInputPreAmp(single) begin selectorLite=%p ch=%d\n",
                    phaseTag ? phaseTag : "",
                    g_channelSelectorLite,
                    targetCh + 1);
            updateInputPreAmpSingle(g_channelSelectorLite, (unsigned char)targetCh);
            fprintf(stderr,
                    "[MC] %sselector-lite experiment: UpdateInputPreAmp(single) end selectorLite=%p ch=%d\n",
                    phaseTag ? phaseTag : "",
                    g_channelSelectorLite,
                    targetCh + 1);
            actions++;
        }
    }

    if (selectedInputCh >= 0 && g_channelSelector && informPreampControls) {
        fprintf(stderr,
                "[MC] %sselector experiment: InformDL5000ControlSurfacePreAmpControls begin selector=%p ch=%d audioType=0\n",
                phaseTag ? phaseTag : "",
                g_channelSelector,
                selectedInputCh + 1);
        informPreampControls(g_channelSelector, (unsigned char)selectedInputCh, 0);
        fprintf(stderr,
                "[MC] %sselector experiment: InformDL5000ControlSurfacePreAmpControls end selector=%p\n",
                phaseTag ? phaseTag : "",
                g_channelSelector);
        actions++;
    }

    if (autotestEnvEnabled("MC_AUTOTEST_SURFACE_CHANNELS_PREAMP_EXPERIMENT") &&
        g_surfaceChannels && selectedInputCh >= 0) {
        int pairStart = isChannelStereo(selectedInputCh) ? (selectedInputCh & ~1) : selectedInputCh;
        int pairEnd = isChannelStereo(selectedInputCh) ? (pairStart + 1) : selectedInputCh;
        if (surfaceUpdateInputPreAmp) {
            for (int targetCh = pairStart; targetCh <= pairEnd; ++targetCh) {
                fprintf(stderr,
                        "[MC] %ssurface-channels experiment: UpdateInputPreAmp begin surfaceChannels=%p ch=%d\n",
                        phaseTag ? phaseTag : "",
                        g_surfaceChannels,
                        targetCh + 1);
                surfaceUpdateInputPreAmp(g_surfaceChannels, (unsigned char)targetCh);
                fprintf(stderr,
                        "[MC] %ssurface-channels experiment: UpdateInputPreAmp end surfaceChannels=%p ch=%d\n",
                        phaseTag ? phaseTag : "",
                        g_surfaceChannels,
                        targetCh + 1);
                actions++;
            }
        }
        if (surfaceUpdateInputPreAmps) {
            fprintf(stderr,
                    "[MC] %ssurface-channels experiment: UpdateInputPreAmps begin surfaceChannels=%p\n",
                    phaseTag ? phaseTag : "",
                    g_surfaceChannels);
            surfaceUpdateInputPreAmps(g_surfaceChannels);
            fprintf(stderr,
                    "[MC] %ssurface-channels experiment: UpdateInputPreAmps end surfaceChannels=%p\n",
                    phaseTag ? phaseTag : "",
                    g_surfaceChannels);
            actions++;
        }
    }

    fprintf(stderr,
            "[MC] %sselector-lite experiment: end selectedCh=%d selector=%p selectorLite=%p surfaceChannels=%p actions=%d\n",
            phaseTag ? phaseTag : "",
            selectedInputCh >= 0 ? selectedInputCh + 1 : -1,
            g_channelSelector,
            g_channelSelectorLite,
            g_surfaceChannels,
            actions);
    QApplication::processEvents();
}

static void runSelectorSurfacePreampExperiment(int ch, const char* phaseTag) {
    if (!autotestEnvEnabled("MC_EXPERIMENT_SELECTOR_SURFACE_PREAMP"))
        return;

    typedef void (*fn_ChannelSelectorDL5000PreampGainRotary)(void*, uint16_t);
    typedef void (*fn_ChannelSelectorInformDL5000ControlSurfacePreAmpControls)(void*, unsigned char, int);
    typedef void (*fn_SurfaceChannelsUpdateInputPreAmp)(void*, unsigned char);
    typedef void (*fn_ChannelSelectorManagerLinkInputMicPre)(void*, unsigned char, unsigned char);

    auto preampGainRotary =
        (fn_ChannelSelectorDL5000PreampGainRotary)RESOLVE(0x1001e3360);
    auto informPreampControls =
        (fn_ChannelSelectorInformDL5000ControlSurfacePreAmpControls)RESOLVE(0x1001ddcd0);
    auto updateInputPreAmp =
        (fn_SurfaceChannelsUpdateInputPreAmp)RESOLVE(0x10040d7c0);
    auto linkInputMicPre =
        (fn_ChannelSelectorManagerLinkInputMicPre)RESOLVE(0x1001b9fc0);

    if (ch < 0 || ch >= 128)
        ch = getSelectedInputChannel(false);
    if (ch < 0 || ch >= 128) {
        fprintf(stderr,
                "[MC] %sselector-surface experiment: skipped, no selected input channel\n",
                phaseTag ? phaseTag : "");
        return;
    }

    uintptr_t selectorVt = (uintptr_t)0x106c77c58 + g_slide + 0x10;
    uintptr_t selectorMgrVt = (uintptr_t)0x106c77ca0 + g_slide + 0x10;
    uintptr_t selectorLiteVt = (uintptr_t)0x106c7c098 + g_slide + 0x10;
    uintptr_t surfaceChannelsVt = (uintptr_t)0x106ce5900 + g_slide + 0x10;
    if (!g_channelSelectorManager) {
        discoverSelectorManagerFromChannelMapper(phaseTag);
    }
    if (!g_channelSelectorManager) {
        g_channelSelectorManager = findSurfaceDiscoveryNamedObject("Channel Selector Manager");
        if (g_channelSelectorManager) {
            fprintf(stderr,
                    "[MC] %sselector-surface experiment: discovered Channel Selector Manager = %p\n",
                    phaseTag ? phaseTag : "",
                    g_channelSelectorManager);
        }
    }
    if (!g_channelSelector && g_channelSelectorManager) {
        g_channelSelector = findChildObjectByVtable(g_channelSelectorManager, selectorVt, 0x800, 0x800);
        if (g_channelSelector) {
            fprintf(stderr,
                    "[MC] %sselector-surface experiment: discovered selector from manager = %p\n",
                    phaseTag ? phaseTag : "",
                    g_channelSelector);
        }
    }
    if (!g_channelSelectorLite && g_channelSelectorManager) {
        g_channelSelectorLite = findChildObjectByVtable(g_channelSelectorManager, selectorLiteVt, 0x800, 0x800);
        if (g_channelSelectorLite) {
            fprintf(stderr,
                    "[MC] %sselector-surface experiment: discovered selectorLite from manager = %p\n",
                    phaseTag ? phaseTag : "",
                    g_channelSelectorLite);
        }
    }
    if (!g_channelSelector) {
        g_channelSelector = findSurfaceDiscoveryNamedObject("Control Surface Channel Selector 01");
        if (g_channelSelector) {
            fprintf(stderr,
                    "[MC] %sselector-surface experiment: discovered selector via explicit name = %p\n",
                    phaseTag ? phaseTag : "",
                    g_channelSelector);
        }
    }
    if (!g_channelSelectorLite) {
        g_channelSelectorLite = findSurfaceDiscoveryNamedObject("Control Surface Channel Selector Lite");
        if (g_channelSelectorLite) {
            fprintf(stderr,
                    "[MC] %sselector-surface experiment: discovered selectorLite via explicit name = %p\n",
                    phaseTag ? phaseTag : "",
                    g_channelSelectorLite);
        }
    }
    std::array<std::pair<const char*, void*>, 3> roots = {{
        {"AppInstance", g_AppInstance ? g_AppInstance() : nullptr},
        {"UIManagerHolder", g_uiManagerHolder},
        {"qApp", qApp},
    }};
    for (const auto& [label, root] : roots) {
        if (!root)
            continue;
        if (!g_channelSelectorManager) {
            g_channelSelectorManager = findChildObjectByVtable(root, selectorMgrVt, 0x800, 0x800);
            if (g_channelSelectorManager) {
                fprintf(stderr,
                        "[MC] %sselector-surface experiment: discovered manager from %s = %p\n",
                        phaseTag ? phaseTag : "",
                        label,
                        g_channelSelectorManager);
            }
        }
        if (!g_channelSelector) {
            g_channelSelector = findChildObjectByVtable(root, selectorVt, 0x800, 0x800);
            if (g_channelSelector) {
                fprintf(stderr,
                        "[MC] %sselector-surface experiment: discovered selector from %s = %p\n",
                        phaseTag ? phaseTag : "",
                        label,
                        g_channelSelector);
            }
        }
        if (!g_channelSelectorLite) {
            g_channelSelectorLite = findChildObjectByVtable(root, selectorLiteVt, 0x800, 0x800);
            if (g_channelSelectorLite) {
                fprintf(stderr,
                        "[MC] %sselector-surface experiment: discovered selectorLite from %s = %p\n",
                        phaseTag ? phaseTag : "",
                        label,
                        g_channelSelectorLite);
            }
        }
        if (!g_surfaceChannels) {
            g_surfaceChannels = findChildObjectByVtable(root, surfaceChannelsVt, 0x800, 0x800);
            if (g_surfaceChannels) {
                fprintf(stderr,
                        "[MC] %sselector-surface experiment: discovered surfaceChannels from %s = %p\n",
                        phaseTag ? phaseTag : "",
                        label,
                        g_surfaceChannels);
            }
        }
    }
    if (!g_channelSelector) {
        fprintf(stderr,
                "[MC] %sselector-surface experiment: skipped selector=%p selectorLite=%p selectorManager=%p surfaceChannels=%p\n",
                phaseTag ? phaseTag : "",
                g_channelSelector,
                g_channelSelectorLite,
                g_channelSelectorManager,
                g_surfaceChannels);
        return;
    }

    PatchData livePatch = {};
    PreampData pd = {};
    if (!readPatchData(ch, livePatch) || !readPreampDataForPatch(livePatch, pd)) {
        fprintf(stderr,
                "[MC] %sselector-surface experiment: skipped, failed to read patch/preamp for ch %d\n",
                phaseTag ? phaseTag : "",
                ch + 1);
        return;
    }

    bool stereo = isChannelStereo(ch);
    int pairStart = stereo ? (ch & ~1) : ch;
    int pairEnd = stereo ? (pairStart + 1) : ch;
    int actions = 0;

    fprintf(stderr,
            "[MC] %sselector-surface experiment: begin ch=%d stereo=%d pair=%d/%d selector=%p surfaceChannels=%p source={type=%u,num=%u} gainRaw=%d gainWord=%u\n",
            phaseTag ? phaseTag : "",
            ch + 1,
            stereo ? 1 : 0,
            pairStart + 1,
            pairEnd + 1,
            g_channelSelector,
            g_surfaceChannels,
            livePatch.source.type,
            livePatch.source.number,
            pd.gain,
            (unsigned)(uint16_t)pd.gain);

    if (preampGainRotary) {
        fprintf(stderr,
                "[MC] %sselector-surface experiment: DL5000PreampGainRotary begin selector=%p gainWord=%u\n",
                phaseTag ? phaseTag : "",
                g_channelSelector,
                (unsigned)(uint16_t)pd.gain);
        preampGainRotary(g_channelSelector, (uint16_t)pd.gain);
        fprintf(stderr,
                "[MC] %sselector-surface experiment: DL5000PreampGainRotary end selector=%p\n",
                phaseTag ? phaseTag : "",
                g_channelSelector);
        actions++;
    }

    if (linkInputMicPre && g_channelSelectorManager) {
        unsigned char linkArg =
            (unsigned char)atoi(getenv("MC_EXPERIMENT_SELECTOR_MANAGER_LINK_ARG")
                                    ? getenv("MC_EXPERIMENT_SELECTOR_MANAGER_LINK_ARG")
                                    : "1");
        for (int targetCh = pairStart; targetCh <= pairEnd; ++targetCh) {
            fprintf(stderr,
                    "[MC] %sselector-surface experiment: LinkInputMicPre begin manager=%p ch=%d arg=%u\n",
                    phaseTag ? phaseTag : "",
                    g_channelSelectorManager,
                    targetCh + 1,
                    (unsigned)linkArg);
            linkInputMicPre(g_channelSelectorManager, (unsigned char)targetCh, linkArg);
            fprintf(stderr,
                    "[MC] %sselector-surface experiment: LinkInputMicPre end manager=%p ch=%d\n",
                    phaseTag ? phaseTag : "",
                    g_channelSelectorManager,
                    targetCh + 1);
            actions++;
        }
    }

    if (informPreampControls) {
        for (int targetCh = pairStart; targetCh <= pairEnd; ++targetCh) {
            fprintf(stderr,
                    "[MC] %sselector-surface experiment: InformDL5000ControlSurfacePreAmpControls begin selector=%p ch=%d audioType=0\n",
                    phaseTag ? phaseTag : "",
                    g_channelSelector,
                    targetCh + 1);
            informPreampControls(g_channelSelector, (unsigned char)targetCh, 0);
            fprintf(stderr,
                    "[MC] %sselector-surface experiment: InformDL5000ControlSurfacePreAmpControls end selector=%p ch=%d\n",
                    phaseTag ? phaseTag : "",
                    g_channelSelector,
                    targetCh + 1);
            actions++;
        }
    }

    if (updateInputPreAmp && g_surfaceChannels) {
        for (int targetCh = pairStart; targetCh <= pairEnd; ++targetCh) {
            fprintf(stderr,
                    "[MC] %sselector-surface experiment: UpdateInputPreAmp begin surfaceChannels=%p ch=%d\n",
                    phaseTag ? phaseTag : "",
                    g_surfaceChannels,
                    targetCh + 1);
            updateInputPreAmp(g_surfaceChannels, (unsigned char)targetCh);
            fprintf(stderr,
                    "[MC] %sselector-surface experiment: UpdateInputPreAmp end surfaceChannels=%p ch=%d\n",
                    phaseTag ? phaseTag : "",
                    g_surfaceChannels,
                    targetCh + 1);
            actions++;
        }
    }

    fprintf(stderr,
            "[MC] %sselector-surface experiment: end ch=%d stereo=%d actions=%d\n",
            phaseTag ? phaseTag : "",
            ch + 1,
            stereo ? 1 : 0,
            actions);
    QApplication::processEvents();
}

static void refreshToolbarReorderButton() {
    QmlToolbarTargets qmlTargets = findQmlToolbarTargets();
    QWidget* host = nullptr;
    QWidget* anchor = nullptr;
    QRect anchorRect;
    QRect rightRect;

    if (qmlTargets.host && qmlTargets.quickWidget && qmlTargets.tabrow) {
        host = qmlTargets.host;
        anchorRect = qmlObjectRectInHost(qmlTargets.tabrow, qmlTargets.quickWidget, host);
        if (qmlTargets.homeButton)
            rightRect = qmlObjectRectInHost(qmlTargets.homeButton, qmlTargets.quickWidget, host);
        else if (qmlTargets.tabbar)
            rightRect = qmlObjectRectInHost(qmlTargets.tabbar, qmlTargets.quickWidget, host);
    }

    if (!host || !anchorRect.isValid() || !rightRect.isValid() || rightRect.x() <= anchorRect.right()) {
        if (g_toolbarReorderButton)
            g_toolbarReorderButton->hide();
        return;
    }

    if (!g_toolbarReorderButton || g_toolbarReorderButton->parentWidget() != host) {
        if (g_toolbarReorderButton)
            delete g_toolbarReorderButton;
        g_toolbarReorderButton = new QPushButton(host);
        g_toolbarReorderButton->setObjectName("mcToolbarReorderButton");
        QObject::connect(g_toolbarReorderButton, &QPushButton::clicked, host, []() {
            showReorderDialog();
        });
        fprintf(stderr, "[MC] Installed toolbar reorder button host='%s'.\n",
                host->objectName().toUtf8().constData());
    }

    QString styleText = "Reorder";
    g_toolbarReorderButton->setText(styleText);
    QFont navFont = anchor ? anchor->font() : host->font();
    navFont.setFamily("Liberation Sans");
    if (anchorRect.isValid()) {
        int targetPixelSize = std::max(16, std::min(20, anchorRect.height() - 12));
        navFont.setPixelSize(targetPixelSize);
        navFont.setWeight(QFont::Normal);
    }
    g_toolbarReorderButton->setFont(navFont);
    QString copiedStyle = anchor ? anchor->styleSheet() : QString();
    if (copiedStyle.isEmpty()) {
        copiedStyle =
            "QPushButton {"
            " background-color: transparent;"
            " color: rgb(240, 240, 240);"
            " border: none;"
            " padding: 0px 0px 0px 0px;"
            " text-align: left;"
            "}"
            "QPushButton:pressed {"
            " color: rgb(255, 255, 255);"
            "}"
            "QPushButton:hover {"
            " color: rgb(255, 255, 255);"
            "}";
    }
    g_toolbarReorderButton->setStyleSheet(copiedStyle);
    g_toolbarReorderButton->setPalette(anchor ? anchor->palette() : host->palette());
    g_toolbarReorderButton->setEnabled(anchor ? anchor->isEnabled() : true);
    g_toolbarReorderButton->setVisible(true);
    g_toolbarReorderButton->raise();

    int desiredWidth = std::max(96,
                                g_toolbarReorderButton->fontMetrics().horizontalAdvance(styleText) + 10);
    int desiredHeight = 26;
    int x = 0;
    int y = 4;

    int gap = rightRect.x() - anchorRect.right() - 1;
    if (gap < 76) {
        g_toolbarReorderButton->hide();
        return;
    }
    desiredWidth = std::max(desiredWidth,
                            g_toolbarReorderButton->fontMetrics().horizontalAdvance(styleText) + 8);
    desiredWidth = std::min(desiredWidth, gap - 18);
    if (desiredWidth < 48) {
        g_toolbarReorderButton->hide();
        return;
    }
    desiredHeight = std::max(26, std::min(anchorRect.height(), 30));
    x = anchorRect.right() + 18;
    y = anchorRect.y() + std::max(0, (anchorRect.height() - desiredHeight) / 2);

    g_toolbarReorderButton->setGeometry(x, y, desiredWidth, desiredHeight);
    g_toolbarReorderButton->show();
}

static void showMoveDialog() {
    if (g_dialog) { g_dialog->show(); g_dialog->raise(); g_dialog->activateWindow(); return; }

    g_dialog = new QDialog(nullptr, Qt::WindowStaysOnTopHint);
    g_dialog->setWindowTitle("Move Channel");
    g_dialog->setMinimumWidth(420);
    g_dialog->setMinimumHeight(340);
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

    auto* ioPortShiftCheck = new QCheckBox("In Scenario A, also shift MixRack I/O Port sockets");
    ioPortShiftCheck->setChecked(false);
    layout->addWidget(ioPortShiftCheck);

    auto* blockRow = new QHBoxLayout();
    auto* blockLabel = new QLabel("Channels to Move:");
    auto* blockSizeSpin = new QSpinBox();
    blockSizeSpin->setRange(1, 128);
    blockSizeSpin->setValue(1);
    blockRow->addWidget(blockLabel);
    blockRow->addWidget(blockSizeSpin);
    blockRow->addStretch(1);
    layout->addLayout(blockRow);

    auto* moveHintLabel = new QLabel();
    moveHintLabel->setWordWrap(true);
    layout->addWidget(moveHintLabel);

    auto* statusLabel = new QLabel("Ready.");
    statusLabel->setWordWrap(true);
    layout->addWidget(statusLabel);

    auto* btnLayout = new QHBoxLayout();
    auto* moveBtn = new QPushButton("Move");
    auto* reorderBtn = new QPushButton("Reorder...");
    auto* closeBtn = new QPushButton("Close");
    btnLayout->addWidget(moveBtn);
    btnLayout->addWidget(reorderBtn);
    btnLayout->addWidget(closeBtn);
    layout->addLayout(btnLayout);

    auto updateMoveUi = [=]() {
        updateStereoLabels();

        int srcCh = srcSpin->value() - 1;
        int dstCh = dstSpin->value() - 1;
        bool srcSt = isChannelStereo(srcCh);
        ioPortShiftCheck->setEnabled(!patchCheck->isChecked());

        MovePlan plan;
        char err[256];
        auto explainMoveError = [&](const char* rawErr) {
            QString text = QString(rawErr);
            if (text.contains("split stereo pair")) {
                text += " Use an even channel count (2, 4, 6...) so stereo pairs stay intact.";
            }
            return text;
        };
        if (!buildMovePlan(srcCh, dstCh, blockSizeSpin->value(), plan, err, sizeof(err))) {
            moveHintLabel->setText(QString("Unsupported right now: %1").arg(explainMoveError(err)));
            moveBtn->setEnabled(false);
            return;
        }

        if (plan.srcStereo) {
            QString text = QString("Stereo move: ch %1+%2 will move together to %3+%4.")
                .arg(plan.srcStart + 1).arg(plan.srcStart + 2)
                .arg(plan.dstStart + 1).arg(plan.dstStart + 2);
            if (plan.rawSrc != plan.srcStart || plan.rawDst != plan.dstStart)
                text += " Selection normalized to the stereo pair boundary.";
            if (patchCheck->isChecked()) {
                text += " Patching/preamp socket will move with the channel.";
            } else {
                text += " Patching/preamp socket will shift by the move amount.";
                text += ioPortShiftCheck->isChecked()
                    ? " MixRack I/O Port sockets will also shift by the move amount."
                    : " MixRack I/O Port sockets will stay with the channel.";
            }
            moveHintLabel->setText(text);
        } else if (plan.srcMonoBlock) {
            QString text = QString("Two-mono block move: ch %1+%2 will move together to %3+%4.")
                .arg(plan.srcStart + 1).arg(plan.srcStart + 2)
                .arg(plan.dstStart + 1).arg(plan.dstStart + 2);
            if (patchCheck->isChecked()) {
                text += " Patching/preamp socket will move with the channel.";
            } else {
                text += " Patching/preamp socket will shift by the move amount.";
                text += ioPortShiftCheck->isChecked()
                    ? " MixRack I/O Port sockets will also shift by the move amount."
                    : " MixRack I/O Port sockets will stay with the channel.";
            }
            moveHintLabel->setText(text);
        } else if (plan.blockSize > 1) {
            QString text = QString("Block move: ch %1-%2 will move together to %3-%4.")
                .arg(plan.srcStart + 1).arg(plan.srcStart + plan.blockSize)
                .arg(plan.dstStart + 1).arg(plan.dstStart + plan.blockSize);
            text += " The move will be blocked if it would split any stereo pair.";
            if (patchCheck->isChecked()) {
                text += " Patching/preamp socket will move with the channel.";
            } else {
                text += " Patching/preamp socket will shift by the move amount.";
                text += ioPortShiftCheck->isChecked()
                    ? " MixRack I/O Port sockets will also shift by the move amount."
                    : " MixRack I/O Port sockets will stay with the channel.";
            }
            moveHintLabel->setText(text);
        } else {
            if (patchCheck->isChecked()) {
                moveHintLabel->setText(
                    "Mono move: affected range is all mono. Patching/preamp socket will move with the channel.");
            } else {
                moveHintLabel->setText(ioPortShiftCheck->isChecked()
                    ? "Mono move: affected range is all mono. Patching/preamp socket will shift by the move amount, including MixRack I/O Port sockets."
                    : "Mono move: affected range is all mono. Patching/preamp socket will shift by the move amount, while MixRack I/O Port sockets stay with the channel.");
            }
        }

        moveBtn->setEnabled(true);
    };

    QObject::connect(srcSpin, QOverload<int>::of(&QSpinBox::valueChanged), [=](int) { updateMoveUi(); });
    QObject::connect(dstSpin, QOverload<int>::of(&QSpinBox::valueChanged), [=](int) { updateMoveUi(); });
    QObject::connect(blockSizeSpin, QOverload<int>::of(&QSpinBox::valueChanged), [=](int) { updateMoveUi(); });
    QObject::connect(patchCheck, &QCheckBox::toggled, [=](bool) { updateMoveUi(); });
    QObject::connect(ioPortShiftCheck, &QCheckBox::toggled, [=](bool) { updateMoveUi(); });
    updateMoveUi();

    QObject::connect(closeBtn, &QPushButton::clicked, g_dialog, &QDialog::hide);
    QObject::connect(reorderBtn, &QPushButton::clicked, [=]() {
        showReorderDialog();
    });

    QObject::connect(moveBtn, &QPushButton::clicked, [=]() {
        int src = srcSpin->value() - 1;
        int dst = dstSpin->value() - 1;
        bool movePatchWithChannel = patchCheck->isChecked();
        bool shiftMixRackIOPortWithMoveInScenarioA = ioPortShiftCheck->isChecked();
        int requestedBlockSize = blockSizeSpin->value();
        MovePlan plan;
        char err[256];
        if (!buildMovePlan(src, dst, requestedBlockSize, plan, err, sizeof(err))) {
            QString text = QString(err);
            if (text.contains("split stereo pair")) {
                text += " Use an even channel count (2, 4, 6...) so stereo pairs stay intact.";
            }
            statusLabel->setText(QString("Unsupported: %1").arg(text));
            moveBtn->setEnabled(false);
            return;
        }
        statusLabel->setText("Moving...");
        moveBtn->setEnabled(false);
        QApplication::processEvents();

        bool ok = runMoveWithProgressDialog(
            g_dialog,
            formatMoveProgressLabel("Phase: preparing move"),
            [&]() {
                return moveChannel(src, dst, movePatchWithChannel,
                                   shiftMixRackIOPortWithMoveInScenarioA,
                                   requestedBlockSize);
            });
        if (!ok) {
            MoveConflictInfo conflict;
            if (takeLastMoveConflict(conflict)) {
                statusLabel->setText(conflict.summary);
                QMessageBox msgBox(g_dialog);
                msgBox.setIcon(QMessageBox::Warning);
                msgBox.setWindowTitle(conflict.title);
                msgBox.setTextFormat(Qt::RichText);
                msgBox.setText(conflict.summary);
                msgBox.setInformativeText(conflict.details);
                msgBox.setStandardButtons(QMessageBox::Ok);
                msgBox.exec();
            } else {
                statusLabel->setText("Failed — check log.");
            }
        } else {
            statusLabel->setText("Done!");
        }
        updateMoveUi();
    });

    g_dialog->show();
}

static void showReorderDialog() {
    if (g_reorderDialog) {
        g_reorderDialog->show();
        g_reorderDialog->raise();
        g_reorderDialog->activateWindow();
        return;
    }

    auto blocks = std::make_shared<std::vector<ReorderBlockEntry>>(snapshotReorderBlocks());

    g_reorderDialog = new QDialog(nullptr, Qt::WindowStaysOnTopHint);
    g_reorderDialog->setAttribute(Qt::WA_DeleteOnClose, true);
    QObject::connect(g_reorderDialog, &QObject::destroyed, []() {
        g_reorderDialog = nullptr;
    });
    g_reorderDialog->setWindowTitle("Channel Reorder Panel");
    g_reorderDialog->setMinimumWidth(500);
    g_reorderDialog->setMinimumHeight(760);

    auto* layout = new QVBoxLayout(g_reorderDialog);

    auto* intro = new QLabel(
        "Drag channels to their final positions. Shift-select to move multiple channels together. "
        "Apply stays disabled until the final order is legal.");
    intro->setWordWrap(true);
    layout->addWidget(intro);

    auto* patchCheck = new QCheckBox("Move preamp socket with channel (Scenario B)");
    patchCheck->setChecked(false);
    layout->addWidget(patchCheck);

    auto* ioPortShiftCheck = new QCheckBox("In Scenario A, also shift MixRack I/O Port sockets");
    ioPortShiftCheck->setChecked(false);
    layout->addWidget(ioPortShiftCheck);

    auto* table = new ReorderTableWidget(g_reorderDialog);
    table->setColumnCount(5);
    table->setHorizontalHeaderLabels({"Pos", "Channels", "Name", "Type", "Final Preamp"});
    table->horizontalHeader()->setSectionResizeMode(0, QHeaderView::ResizeToContents);
    table->horizontalHeader()->setSectionResizeMode(1, QHeaderView::ResizeToContents);
    table->horizontalHeader()->setSectionResizeMode(2, QHeaderView::ResizeToContents);
    table->horizontalHeader()->setSectionResizeMode(3, QHeaderView::ResizeToContents);
    table->horizontalHeader()->setSectionResizeMode(4, QHeaderView::ResizeToContents);
    layout->addWidget(table, 1);
    std::vector<int> initialOrder;
    initialOrder.reserve(blocks->size());
    for (const auto& block : *blocks)
        initialOrder.push_back(block.blockId);
    populateReorderTable(table, initialOrder);

    struct ReorderHistoryState {
        std::vector<std::vector<int>> undoStack;
        std::vector<std::vector<int>> redoStack;
    };
    auto history = std::make_shared<ReorderHistoryState>();

    auto* statusLabel = new QLabel("Ready.");
    statusLabel->setWordWrap(true);
    layout->addWidget(statusLabel);

    auto* btnLayout = new QHBoxLayout();
    auto* undoBtn = new QPushButton("Undo");
    auto* redoBtn = new QPushButton("Redo");
    auto* applyBtn = new QPushButton("Apply");
    auto* closeBtn = new QPushButton("Close");
    btnLayout->addWidget(undoBtn);
    btnLayout->addWidget(redoBtn);
    btnLayout->addStretch(1);
    btnLayout->addWidget(applyBtn);
    btnLayout->addWidget(closeBtn);
    layout->addLayout(btnLayout);

    auto refreshPanel = [=]() {
        ioPortShiftCheck->setEnabled(!patchCheck->isChecked());
        std::vector<int> blockOrder = readCurrentReorderBlockOrder(table);
        std::vector<int> order = expandReorderBlockOrder(blockOrder, *blocks);
        std::vector<IllegalStereoPlacement> illegalPlacements =
            findIllegalStereoPlacements(blockOrder, *blocks);
        std::set<int> illegalRows;
        for (const auto& placement : illegalPlacements)
            illegalRows.insert(placement.row);
        int tgtStart = 0;

        for (int row = 0; row < table->rowCount(); row++) {
            auto* posItem = table->item(row, 0);
            auto* channelNumItem = table->item(row, 1);
            auto* channelNameItem = table->item(row, 2);
            auto* stereoItem = table->item(row, 3);
            auto* preampItem = table->item(row, 4);
            int blockId = posItem ? posItem->data(Qt::UserRole).toInt() : row;
            if (blockId < 0 || blockId >= (int)blocks->size())
                continue;
            const auto& entry = (*blocks)[blockId];
            QColor bg = colorForChannelColourIndex(entry.colour);
            QColor fg = textColorForChannelColourIndex(entry.colour);
            if (illegalRows.count(row)) {
                bg = QColor(255, 226, 226);
                fg = QColor(155, 32, 32);
            }
            QBrush bgBrush(bg);
            QBrush fgBrush(fg);
            if (posItem)
                posItem->setText(QString::number(tgtStart + 1));
            if (channelNumItem)
                channelNumItem->setText(formatReorderChannelNumberText(entry));
            if (channelNameItem)
                channelNameItem->setText(formatReorderChannelNameText(entry));
            if (stereoItem)
                stereoItem->setText(formatReorderStereoText(entry));
            if (preampItem) {
                preampItem->setText(formatPreampPreviewForTarget(entry, tgtStart,
                                                                 patchCheck->isChecked(),
                                                                 ioPortShiftCheck->isChecked()));
            }
            if (posItem)
                posItem->setTextAlignment(Qt::AlignCenter);
            if (channelNumItem)
                channelNumItem->setTextAlignment(Qt::AlignCenter);
            if (stereoItem)
                stereoItem->setTextAlignment(Qt::AlignCenter);
            for (int col = 0; col < table->columnCount(); col++) {
                QTableWidgetItem* item = table->item(row, col);
                if (!item)
                    continue;
                item->setBackground(bgBrush);
                item->setForeground(fgBrush);
            }
            tgtStart += entry.width;
        }

        if (!illegalPlacements.empty()) {
            const auto& placement = illegalPlacements.front();
            const auto& block = (*blocks)[placement.blockId];
            QString text = QString("Illegal layout: stereo block Ch %1+%2 would start at position %3. Add or move one mono channel before it so stereo blocks start on 1, 3, 5, ...")
                .arg(block.srcStart + 1, 3, 10, QChar('0'))
                .arg(block.srcStart + 2, 3, 10, QChar('0'))
                .arg(placement.targetStart + 1);
            statusLabel->setText(text);
            applyBtn->setEnabled(false);
            undoBtn->setEnabled(!history->undoStack.empty());
            redoBtn->setEnabled(!history->redoStack.empty());
            resizeReorderDialogToTable(g_reorderDialog, table);
            return;
        }

        MovePlan plan;
        char err[256];
        if (!buildReorderPlan(order, plan, err, sizeof(err))) {
            QString text = QString("Illegal layout: %1").arg(err);
            if (QString(err).contains("split stereo pair")) {
                text += " Keep stereo channels together on positions 1+2, 3+4, 5+6, ...";
            }
            statusLabel->setText(text);
            applyBtn->setEnabled(false);
            undoBtn->setEnabled(!history->undoStack.empty());
            redoBtn->setEnabled(!history->redoStack.empty());
            resizeReorderDialogToTable(g_reorderDialog, table);
            return;
        }

        int changed = 0;
        for (int i = 0; i < 128; i++) {
            if (order[i] != i) changed++;
        }
        bool hasPatchOverrides = false;
        for (const auto& block : *blocks) {
            if (block.hasPatchOverrideA || block.hasPatchOverrideB) {
                hasPatchOverrides = true;
                break;
            }
        }
        if (changed == 0 && !hasPatchOverrides) {
            statusLabel->setText("No changes yet.");
            applyBtn->setEnabled(false);
        } else {
            if (hasPatchOverrides && changed == 0) {
                statusLabel->setText("Ready to apply. Manual patch overrides are pending.");
            } else if (hasPatchOverrides) {
                statusLabel->setText(QString("Ready to apply. %1 channel positions changed, with manual patch overrides.")
                                     .arg(changed));
            } else {
                statusLabel->setText(QString("Ready to apply. %1 channel positions changed.")
                                     .arg(changed));
            }
            applyBtn->setEnabled(true);
        }
        undoBtn->setEnabled(!history->undoStack.empty());
        redoBtn->setEnabled(!history->redoStack.empty());
        resizeReorderDialogToTable(g_reorderDialog, table);
    };

    auto restoreOrder = [=](const std::vector<int>& order, const std::vector<int>& selectedBlocks = std::vector<int>()) {
        populateReorderTable(table, order);
        refreshPanel();
        selectReorderRowsForBlocks(table, selectedBlocks);
    };

    table->onItemsReordered = [=](const std::vector<int>& before, const std::vector<int>& after) {
        if (before == after)
            return;
        history->undoStack.push_back(before);
        history->redoStack.clear();
        restoreOrder(after);
    };
    QObject::connect(patchCheck, &QCheckBox::toggled, [=](bool) { refreshPanel(); });
    QObject::connect(ioPortShiftCheck, &QCheckBox::toggled, [=](bool) { refreshPanel(); });
    QObject::connect(closeBtn, &QPushButton::clicked, g_reorderDialog, &QDialog::close);
    QObject::connect(undoBtn, &QPushButton::clicked, [=]() {
        if (history->undoStack.empty())
            return;
        std::vector<int> current = readCurrentReorderBlockOrder(table);
        history->redoStack.push_back(current);
        std::vector<int> prior = history->undoStack.back();
        history->undoStack.pop_back();
        restoreOrder(prior);
    });
    QObject::connect(redoBtn, &QPushButton::clicked, [=]() {
        if (history->redoStack.empty())
            return;
        std::vector<int> current = readCurrentReorderBlockOrder(table);
        history->undoStack.push_back(current);
        std::vector<int> next = history->redoStack.back();
        history->redoStack.pop_back();
        restoreOrder(next);
    });

    auto* undoShortcut = new QShortcut(QKeySequence(QStringLiteral("Ctrl+Z")), g_reorderDialog);
    QObject::connect(undoShortcut, &QShortcut::activated, undoBtn, &QPushButton::click);
    auto* redoShortcut = new QShortcut(QKeySequence(QStringLiteral("Ctrl+Shift+Z")), g_reorderDialog);
    QObject::connect(redoShortcut, &QShortcut::activated, redoBtn, &QPushButton::click);
    auto* undoShortcutMac = new QShortcut(QKeySequence(QStringLiteral("Meta+Z")), g_reorderDialog);
    QObject::connect(undoShortcutMac, &QShortcut::activated, undoBtn, &QPushButton::click);
    auto* redoShortcutMac = new QShortcut(QKeySequence(QStringLiteral("Meta+Shift+Z")), g_reorderDialog);
    QObject::connect(redoShortcutMac, &QShortcut::activated, redoBtn, &QPushButton::click);

    auto patchSourceChoiceForSource = [](const sAudioSource& source) -> QString {
        if (audioSourceIsUnassigned(source))
            return "Unassigned";
        return buildPatchMenuBankLabel(source.type, source.number);
    };

    QObject::connect(table, &QWidget::customContextMenuRequested, g_reorderDialog, [=](const QPoint& pos) {
        QModelIndex idx = table->indexAt(pos);
        if (idx.isValid() && !table->selectionModel()->isRowSelected(idx.row(), QModelIndex()))
            table->selectRow(idx.row());

        std::vector<int> selectedBlockIds;
        QModelIndexList selected = table->selectionModel()->selectedRows();
        selectedBlockIds.reserve(selected.size());
        for (const QModelIndex& rowIndex : selected) {
            QTableWidgetItem* item = table->item(rowIndex.row(), 0);
            if (!item) continue;
            selectedBlockIds.push_back(item->data(Qt::UserRole).toInt());
        }
        if (selectedBlockIds.empty())
            return;

        QMenu menu(g_reorderDialog);
        if (selectedBlockIds.size() == 1 && idx.isValid()) {
            QAction* patchAction = menu.addAction("Set Main Patch...");
            QObject::connect(patchAction, &QAction::triggered, g_reorderDialog, [=]() {
                QTableWidgetItem* posItem = table->item(idx.row(), 0);
                if (!posItem)
                    return;
                int blockId = posItem->data(Qt::UserRole).toInt();
                if (blockId < 0 || blockId >= (int)blocks->size())
                    return;
                int tgtStart = std::max(0, posItem->text().toInt() - 1);
                auto& block = (*blocks)[blockId];
                PatchData currentA = getEffectiveBlockPatchData(block, 0, tgtStart,
                                                                patchCheck->isChecked(),
                                                                ioPortShiftCheck->isChecked());
                PatchData currentB = block.width > 1
                    ? getEffectiveBlockPatchData(block, 1, tgtStart + 1,
                                                 patchCheck->isChecked(),
                                                 ioPortShiftCheck->isChecked())
                    : currentA;

                std::vector<PatchSourceChoiceEntry> sourceChoices = buildPatchSourceChoices(&currentA);
                int currentSourceIndex = 0;
                for (int i = 0; i < (int)sourceChoices.size(); i++) {
                    const auto& choice = sourceChoices[i];
                    if (choice.type != currentA.source.type)
                        continue;
                    if (currentA.source.number < choice.startNumber ||
                        currentA.source.number >= choice.startNumber + choice.count)
                        continue;
                    currentSourceIndex = i;
                    break;
                }

                auto sourceTypeForChoice = [&](const QString& sourceChoice) -> uint32_t {
                    for (const auto& choice : sourceChoices) {
                        if (choice.label == sourceChoice)
                            return choice.type;
                    }
                    return 20;
                };
                auto maxStartSocketForChoice = [&](const QString& sourceChoice) -> int {
                    if (sourceChoice == "Unassigned")
                        return 0;
                    for (const auto& choice : sourceChoices) {
                        if (choice.label != sourceChoice)
                            continue;
                        if (choice.count == 0)
                            return 0;
                        return block.width > 1 ? std::max(0, (int)choice.count - 1) : (int)choice.count;
                    }
                    return 0;
                };

                QDialog patchDialog(g_reorderDialog, Qt::WindowTitleHint | Qt::WindowCloseButtonHint);
                patchDialog.setWindowTitle("Set Main Patch");
                auto* patchLayout = new QVBoxLayout(&patchDialog);
                auto* patchForm = new QFormLayout();
                auto* sourceCombo = new QComboBox(&patchDialog);
                for (const auto& choice : sourceChoices)
                    sourceCombo->addItem(choice.label, QVariant((uint)choice.type));
                sourceCombo->setCurrentIndex(currentSourceIndex);
                int widestLabel = 0;
                QFontMetrics fm(sourceCombo->font());
                for (const auto& choice : sourceChoices)
                    widestLabel = std::max(widestLabel, fm.horizontalAdvance(choice.label));
                int comboWidth = std::max(260, std::min(520, widestLabel + 90));
                sourceCombo->setMinimumWidth(comboWidth);
                if (sourceCombo->view())
                    sourceCombo->view()->setMinimumWidth(comboWidth + 40);
                if (auto* model = qobject_cast<QStandardItemModel*>(sourceCombo->model())) {
                    for (int i = 0; i < (int)sourceChoices.size(); i++) {
                        if (sourceChoices[i].available)
                            continue;
                        if (QStandardItem* item = model->item(i)) {
                            item->setFlags(item->flags() & ~Qt::ItemIsEnabled);
                            item->setData(QColor(120, 120, 120), Qt::ForegroundRole);
                        }
                    }
                }
                auto* socketSpin = new QSpinBox(&patchDialog);
                socketSpin->setRange(1, std::max(1, maxStartSocketForChoice(sourceCombo->currentText())));
                int currentSocket = 1;
                if (currentSourceIndex >= 0 && currentSourceIndex < (int)sourceChoices.size()) {
                    const auto& currentChoice = sourceChoices[currentSourceIndex];
                    if (currentChoice.type == currentA.source.type &&
                        currentA.source.number >= currentChoice.startNumber &&
                        currentA.source.number < currentChoice.startNumber + currentChoice.count) {
                        currentSocket = (int)(currentA.source.number - currentChoice.startNumber + 1);
                    }
                }
                socketSpin->setValue(currentSocket);
                patchForm->addRow(block.width > 1 ? "Source bank:" : "Source bank:", sourceCombo);
                patchForm->addRow(block.width > 1 ? "Start socket:" : "Socket:", socketSpin);
                patchLayout->addLayout(patchForm);
                auto* patchButtons = new QDialogButtonBox(QDialogButtonBox::Ok | QDialogButtonBox::Cancel,
                                                          Qt::Horizontal, &patchDialog);
                patchLayout->addWidget(patchButtons);
                QObject::connect(patchButtons, &QDialogButtonBox::accepted, &patchDialog, &QDialog::accept);
                QObject::connect(patchButtons, &QDialogButtonBox::rejected, &patchDialog, &QDialog::reject);

                auto updateSocketUi = [&]() {
                    QString choice = sourceCombo->currentText();
                    int maxStartSocket = maxStartSocketForChoice(choice);
                    bool needsSocket = (choice != "Unassigned");
                    socketSpin->setEnabled(needsSocket);
                    if (!needsSocket) {
                        socketSpin->setSuffix("");
                        return;
                    }
                    if (maxStartSocket < 1) {
                        socketSpin->setRange(1, 1);
                        socketSpin->setValue(1);
                        socketSpin->setSuffix(" (unavailable)");
                    } else {
                        socketSpin->setRange(1, maxStartSocket);
                        if (socketSpin->value() > maxStartSocket)
                            socketSpin->setValue(maxStartSocket);
                        socketSpin->setSuffix("");
                    }
                };
                QObject::connect(sourceCombo, QOverload<int>::of(&QComboBox::currentIndexChanged),
                                 &patchDialog, [&](int) { updateSocketUi(); });
                updateSocketUi();

                if (patchDialog.exec() != QDialog::Accepted)
                    return;

                QString sourceChoice = sourceCombo->currentText();
                if (sourceChoice == "Unassigned") {
                    PatchData overrideA = makePatchDataForAudioSource({20, 0}, &currentA);
                    block.hasPatchOverrideA = true;
                    block.patchOverrideA = overrideA;
                    if (block.width > 1) {
                        PatchData overrideB = makePatchDataForAudioSource({20, 0}, &currentB);
                        block.hasPatchOverrideB = true;
                        block.patchOverrideB = overrideB;
                    } else {
                        block.hasPatchOverrideB = false;
                    }
                    refreshPanel();
                    return;
                }

                int maxStartSocket = maxStartSocketForChoice(sourceChoice);
                if (maxStartSocket < 1) {
                    QMessageBox::warning(g_reorderDialog, "Set Main Patch",
                                         QString("Source bank '%1' is unavailable on this scene.")
                                             .arg(sourceChoice));
                    return;
                }

                uint32_t sourceType = sourceTypeForChoice(sourceChoice);
                int socketNumber = socketSpin->value();
                uint32_t sourceNumber = 0;
                for (const auto& choice : sourceChoices) {
                    if (choice.label != sourceChoice)
                        continue;
                    sourceNumber = choice.startNumber + (uint32_t)std::max(0, socketNumber - 1);
                    break;
                }

                block.hasPatchOverrideA = true;
                block.patchOverrideA = makePatchDataForAudioSource(
                    {sourceType, sourceNumber}, &currentA);
                if (block.width > 1) {
                    block.hasPatchOverrideB = true;
                    block.patchOverrideB = makePatchDataForAudioSource(
                        {sourceType, sourceNumber + 1}, &currentB);
                } else {
                    block.hasPatchOverrideB = false;
                }
                refreshPanel();
            });

            const bool hasOverride =
                ((*blocks)[selectedBlockIds.front()].hasPatchOverrideA ||
                 (*blocks)[selectedBlockIds.front()].hasPatchOverrideB);
            if (hasOverride) {
                QAction* clearPatchAction = menu.addAction("Clear Main Patch Override");
                QObject::connect(clearPatchAction, &QAction::triggered, g_reorderDialog, [=]() {
                    auto& block = (*blocks)[selectedBlockIds.front()];
                    block.hasPatchOverrideA = false;
                    block.hasPatchOverrideB = false;
                    refreshPanel();
                });
            }
            menu.addSeparator();
        }

        QMenu* colorMenu = menu.addMenu("Set Color");
        for (const auto& option : kChannelColorOptions) {
            QAction* action = colorMenu->addAction(option.name);
            QObject::connect(action, &QAction::triggered, g_reorderDialog, [=]() {
                for (int blockId : selectedBlockIds) {
                    if (blockId < 0 || blockId >= (int)blocks->size())
                        continue;
                    auto& block = (*blocks)[blockId];
                    block.colour = option.index;
                    for (int i = 0; i < block.width; i++) {
                        int ch = block.srcStart + i;
                        if (g_setChannelColour)
                            g_setChannelColour(g_audioDM, 1, (uint8_t)ch, option.index);
                    }
                }
                refreshPanel();
            });
        }
        menu.exec(table->viewport()->mapToGlobal(pos));
    });

    QObject::connect(applyBtn, &QPushButton::clicked, [=]() {
        std::vector<int> blockOrder = readCurrentReorderBlockOrder(table);
        char err[256];
        bool ok = runMoveWithProgressDialog(
            g_reorderDialog,
            formatMoveProgressLabel("Phase: preparing reorder"),
            [&]() {
                return applyChannelReorder(blockOrder,
                                           *blocks,
                                           patchCheck->isChecked(),
                                           ioPortShiftCheck->isChecked(),
                                           err, sizeof(err));
            });
        if (!ok) {
            MoveConflictInfo conflict;
            if (takeLastMoveConflict(conflict)) {
                statusLabel->setText(conflict.summary);
                QMessageBox msgBox(g_reorderDialog);
                msgBox.setIcon(QMessageBox::Warning);
                msgBox.setWindowTitle(conflict.title);
                msgBox.setTextFormat(Qt::RichText);
                msgBox.setText(conflict.summary);
                msgBox.setInformativeText(conflict.details);
                msgBox.setStandardButtons(QMessageBox::Ok);
                msgBox.exec();
            } else {
                statusLabel->setText(QString("Failed: %1").arg(err[0] ? err : "check log"));
            }
            return;
        }
        g_reorderDialog->close();
    });

    refreshPanel();
    g_reorderDialog->show();
}

static SelectedStripInfo g_lastSelectedStrip;
static uint64_t g_lastSelectedStripMs = 0;
static int g_lastSelectedInputChannel = -1;
static uint64_t g_lastSelectedInputChannelMs = 0;
static uint64_t g_lastPointerSelectionEventMs = 0;
static int getPersistentShortcutSelectionFallback(bool verbose = false);
static void refreshSelectionCacheForShortcut();
static bool copySelectedChannelSettings();
static bool pasteCopiedChannelSettings();
static uint64_t g_lastCopyShortcutMs = 0;
static uint64_t g_lastPasteShortcutMs = 0;

static bool canUseRecentSelectionCache(uint64_t cachedMs) {
    return cachedMs != 0 && (monotonicMs() - cachedMs) <= kShortcutSelectionFallbackWindowMs;
}

static void rememberSelectedStrip(const SelectedStripInfo& strip) {
    if (!strip.valid || strip.channel < 0)
        return;
    g_lastSelectedStrip = strip;
    g_lastSelectedStripMs = monotonicMs();
}

static void rememberSelectedInputChannel(int ch) {
    if (ch < 0 || ch >= 128)
        return;
    g_lastSelectedInputChannel = ch;
    g_lastSelectedInputChannelMs = monotonicMs();
}

static SelectedStripInfo getSelectedStripInfo(bool verbose = false) {
    SelectedStripInfo out;
    if (!g_uiManagerHolder) return out;
    if (!safeRead((uint8_t*)g_uiManagerHolder + 0x50, &out.channelPtr, sizeof(out.channelPtr)) ||
        !out.channelPtr || (uintptr_t)out.channelPtr < 0x100000000ULL) {
        if (verbose) fprintf(stderr, "[MC] UIHolderSelectedChannel: no selected cChannel pointer.\n");
        if (canUseRecentSelectionCache(g_lastSelectedStripMs)) {
            uint64_t ageMs = monotonicMs() - g_lastSelectedStripMs;
            if (verbose) {
                fprintf(stderr,
                        "[MC] UIHolderSelectedChannel: using cached strip type=%u channel=%d (age=%llums).\n",
                        g_lastSelectedStrip.stripType,
                        g_lastSelectedStrip.channel + 1,
                        (unsigned long long)ageMs);
            }
            return g_lastSelectedStrip;
        }
        out.channelPtr = nullptr;
        return out;
    }

    typedef void* (*fn_GetManagedChannel)(const void* mgr, uint64_t stripKey);
    auto getManagedChannel = (fn_GetManagedChannel)RESOLVE(0x1006aa580);
    if (g_channelManager && getManagedChannel) {
        struct StripProbeRange { uint32_t type; int maxChannels; const char* label; };
        const StripProbeRange ranges[] = {
            {1, 128, "input"},
            {4, 64, "aux"},
            {5, 64, "stereo-aux"},
            {8, 8, "main"},
            {10, 32, "matrix"},
        };
        for (const auto& range : ranges) {
            for (int ch = 0; ch < range.maxChannels; ch++) {
                uint64_t key = MAKE_KEY(range.type, (uint8_t)ch);
                if (getManagedChannel(g_channelManager, key) == out.channelPtr) {
                    out.valid = true;
                    out.stripType = range.type;
                    out.channel = ch;
                    if (verbose) {
                        fprintf(stderr,
                                "[MC] UIHolderSelectedChannel: ptr=%p matched %s strip type=%u channel=%d\n",
                                out.channelPtr, range.label, range.type, ch + 1);
                    }
                    rememberSelectedStrip(out);
                    return out;
                }
            }
        }
    }

    uint32_t chNum = 0xffffffffu;
    uint8_t stripType = 0xff;
    safeRead((uint8_t*)out.channelPtr + 0x100, &chNum, sizeof(chNum));
    safeRead((uint8_t*)out.channelPtr + 0x104, &stripType, sizeof(stripType));
    if (verbose) {
        fprintf(stderr, "[MC] UIHolderSelectedChannel: ptr=%p stripType=%u channel=%u\n",
                out.channelPtr, (unsigned)stripType, (unsigned)chNum);
    }
    if (stripType < 0xff && chNum < 128) {
        out.valid = true;
        out.stripType = stripType;
        out.channel = (int)chNum;
        rememberSelectedStrip(out);
    }
    return out;
}

static int getSelectedInputChannel(bool verbose = false) {
    typedef uint64_t (*fn_GetSelectedChannelPacked)(const void* mgr, int selectorIdx);
    auto getSelectorSelectedChannel = (fn_GetSelectedChannelPacked)RESOLVE(0x1001ed500);
    auto getMultiSelectedChannel = (fn_GetSelectedChannelPacked)RESOLVE(0x1001098470);

    auto probePacked = [&](const char* tag, void* obj, fn_GetSelectedChannelPacked fn) -> int {
        if (!obj || !fn) return -1;
        for (int idx = 0; idx < 16; idx++) {
            uint64_t raw = fn(obj, idx);
            uint32_t ch = (uint32_t)(raw & 0xffffffffu);
            uint8_t stripType = (uint8_t)((raw >> 32) & 0xffu);
            if (verbose) {
                fprintf(stderr, "[MC] %s[%d]: stripType=%u channel=%u\n",
                        tag, idx, (unsigned)stripType, (unsigned)ch);
            }
            if (stripType == 1 && ch < 128)
                return (int)ch;
        }
        return -1;
    };

    SelectedStripInfo selectedStrip = getSelectedStripInfo(verbose);

    if ((!g_channelSelectorManager || !g_multifunctionChannelInterface) && selectedStrip.valid)
        rescanSelectionProvidersFromUIHolder((int)selectedStrip.stripType,
                                             selectedStrip.channel,
                                             verbose);

    int selected = probePacked("SelectedChannel", g_channelSelectorManager, getSelectorSelectedChannel);
    if (selected >= 0) {
        if (verbose && selectedStrip.valid && selectedStrip.stripType == 1 &&
            selectedStrip.channel != selected) {
            fprintf(stderr,
                    "[MC] getSelectedInputChannel: selector manager channel %d overrides UIHolder channel %d.\n",
                    selected + 1, selectedStrip.channel + 1);
        }
        rememberSelectedInputChannel(selected);
        return selected;
    }

    selected = probePacked("MultifunctionSelectedChannel", g_multifunctionChannelInterface, getMultiSelectedChannel);
    if (selected >= 0) {
        if (verbose && selectedStrip.valid && selectedStrip.stripType == 1 &&
            selectedStrip.channel != selected) {
            fprintf(stderr,
                    "[MC] getSelectedInputChannel: multifunction channel %d overrides UIHolder channel %d.\n",
                    selected + 1, selectedStrip.channel + 1);
        }
        rememberSelectedInputChannel(selected);
        return selected;
    }

    if (selectedStrip.valid && selectedStrip.stripType == 1) {
        rememberSelectedInputChannel(selectedStrip.channel);
        return selectedStrip.channel;
    }

    if (canUseRecentSelectionCache(g_lastSelectedInputChannelMs)) {
        uint64_t ageMs = monotonicMs() - g_lastSelectedInputChannelMs;
        if (verbose) {
            fprintf(stderr,
                    "[MC] getSelectedInputChannel: using cached input channel %d (age=%llums).\n",
                    g_lastSelectedInputChannel + 1,
                    (unsigned long long)ageMs);
        }
        return g_lastSelectedInputChannel;
    }

    int persistentFallback = getPersistentShortcutSelectionFallback(verbose);
    if (persistentFallback >= 0)
        return persistentFallback;

    if (!g_uiManagerHolder)
        fprintf(stderr, "[MC] getSelectedInputChannel: UIManagerHolder unavailable.\n");
    if (!g_channelSelectorManager)
        fprintf(stderr, "[MC] getSelectedInputChannel: ChannelSelectorManager unavailable.\n");
    if (!g_multifunctionChannelInterface)
        fprintf(stderr, "[MC] getSelectedInputChannel: MultifunctionChannelInterface unavailable.\n");
    if (!getSelectorSelectedChannel && !getMultiSelectedChannel) {
        fprintf(stderr, "[MC] getSelectedInputChannel: selected-channel symbols unavailable.\n");
    }
    fprintf(stderr, "[MC] getSelectedInputChannel: no selected input channel found.\n");
    return -1;
}

static void refreshSelectionCacheForShortcut() {
    SelectedStripInfo strip = getSelectedStripInfo(false);
    if ((!g_channelSelectorManager || !g_multifunctionChannelInterface) && strip.valid)
        rescanSelectionProvidersFromUIHolder((int)strip.stripType,
                                             strip.channel,
                                             false);
    if (strip.valid)
        rememberSelectedStrip(strip);
    int inputCh = getSelectedInputChannel(false);
    if (inputCh >= 0)
        rememberSelectedInputChannel(inputCh);
}

static void scheduleWestPreampGainPushAfterPointerSelection() {
    if (!westPreampGainPushEnabled())
        return;
    uint64_t token = g_lastPointerSelectionEventMs;
    QTimer::singleShot(kPointerSelectionSettleDelayMs, qApp, [token]() {
        if (token == 0 || token != g_lastPointerSelectionEventMs)
            return;
        refreshSelectionCacheForShortcut();
        int ch = getSelectedInputChannel(false);
        if (ch < 0) {
            fprintf(stderr,
                    "[MC] pointer-settle west gain push: no selected input channel after settle\n");
            return;
        }
        fprintf(stderr,
                "[MC] pointer-settle west gain push: selected ch %d after pointer settle\n",
                ch + 1);
        scheduleWestPreampGainPush(ch, "[MC] pointer-settle: ");
    });
}

static void runCopyPasteShortcutAction(bool isCopy, const char* origin) {
    uint64_t now = monotonicMs();
    bool shouldDelay =
        g_lastPointerSelectionEventMs != 0 &&
        (now - g_lastPointerSelectionEventMs) <= kPointerSelectionSettleWindowMs;
    int previousSelection = g_lastSelectedInputChannel;

    auto action = [isCopy, origin]() {
        refreshSelectionCacheForShortcut();
        fprintf(stderr, "[MC] %s shortcut executing via %s.\n",
                isCopy ? "Copy" : "Paste",
                origin ? origin : "shortcut");
        if (isCopy) copySelectedChannelSettings();
        else pasteCopiedChannelSettings();
    };

    if (!shouldDelay) {
        action();
        return;
    }

    fprintf(stderr,
            "[MC] %s shortcut waiting for selection settle.\n",
            isCopy ? "Copy" : "Paste");

    auto attempts = std::make_shared<int>(0);
    auto poll = std::make_shared<std::function<void()>>();
    *poll = [=]() {
        refreshSelectionCacheForShortcut();
        int currentSelection = getSelectedInputChannel(false);
        bool changed = (currentSelection >= 0 &&
                        previousSelection >= 0 &&
                        currentSelection != previousSelection);
        bool usable = (currentSelection >= 0) && (previousSelection < 0 || changed);
        if (usable || *attempts >= kPointerSelectionSettlePollAttempts) {
            if (currentSelection >= 0) {
                fprintf(stderr,
                        "[MC] %s shortcut settle selected ch %d after %d poll(s).\n",
                        isCopy ? "Copy" : "Paste",
                        currentSelection + 1,
                        *attempts + 1);
            } else {
                fprintf(stderr,
                        "[MC] %s shortcut settle timed out with no selected channel after %d poll(s).\n",
                        isCopy ? "Copy" : "Paste",
                        *attempts + 1);
            }
            action();
            return;
        }

        (*attempts)++;
        QTimer::singleShot(kPointerSelectionSettleDelayMs, qApp, *poll);
    };

    QTimer::singleShot(kPointerSelectionSettleDelayMs, qApp, *poll);
}

static int getPersistentShortcutSelectionFallback(bool verbose) {
    if (g_lastSelectedInputChannel < 0 || g_lastSelectedInputChannel >= 128)
        return -1;
    if (verbose) {
        fprintf(stderr,
                "[MC] getSelectedInputChannel: using persistent cached input channel %d for shortcut fallback.\n",
                g_lastSelectedInputChannel + 1);
    }
    return g_lastSelectedInputChannel;
}

static bool shouldTriggerCopyPasteShortcut(bool isCopy, bool verbose = true) {
    uint64_t now = monotonicMs();
    uint64_t& lastMs = isCopy ? g_lastCopyShortcutMs : g_lastPasteShortcutMs;
    if (lastMs != 0 && (now - lastMs) < kCopyPasteShortcutDebounceMs) {
        if (verbose) {
            fprintf(stderr,
                    "[MC] %s shortcut ignored due to debounce (%llums since last).\n",
                    isCopy ? "Copy" : "Paste",
                    (unsigned long long)(now - lastMs));
        }
        return false;
    }
    lastMs = now;
    return true;
}

static void clearCopyBuffer() {
    if (!g_copyBuffer.valid) return;
    for (int i = 0; i < g_copyBuffer.blockSize; i++)
        destroySnapshot(g_copyBuffer.snaps[i]);
    g_copyBuffer = {};
}

static bool captureCopiedInputSettings(int ch) {
    bool stereo = isChannelStereo(ch);
    int srcStart = stereo ? (ch & ~1) : ch;
    int blockSize = stereo ? 2 : 1;

    clearCopyBuffer();
    g_copyBuffer.stereo = stereo;
    g_copyBuffer.blockSize = blockSize;
    g_copyBuffer.srcStart = srcStart;

    for (int i = 0; i < blockSize; i++) {
        if (!snapshotChannel(srcStart + i, g_copyBuffer.snaps[i])) {
            fprintf(stderr, "[MC] Copy channel settings failed while snapshotting ch %d.\n",
                    srcStart + i + 1);
            clearCopyBuffer();
            return false;
        }
    }

    g_copyBuffer.valid = true;
    fprintf(stderr, "[MC] Copied %s settings from ch %d%s.\n",
            stereo ? "stereo" : "mono",
            srcStart + 1,
            stereo ? QString("+%1").arg(srcStart + 2).toUtf8().constData() : "");
    fprintf(stderr,
            "[MC] Copy scope: strip processing + mixer + mute groups + preamp values + Dyn8 inserts; patch/ABCD socket assignment and non-Dyn8 inserts stay excluded.\n");
    return true;
}

struct CopyPasteDyn8Op {
    int tgtCh = -1;
    int ip = 0;
    int unitIdx = -1;
    bool clearOnly = false;
    bool validData = false;
    uint8_t dyn8Data[0x94] = {};
};

struct CopyPasteDyn8StereoPairOp {
    int tgtStart = -1;
    int ip = 0;
    int leftUnitIdx = -1;
    bool validLeftData = false;
    bool validRightData = false;
    uint8_t leftDyn8Data[0x94] = {};
    uint8_t rightDyn8Data[0x94] = {};
};

static void refreshDyn8RackForCopyPaste(const std::vector<CopyPasteDyn8Op>& dyn8Ops,
                                        const std::vector<CopyPasteDyn8StereoPairOp>& dyn8StereoOps,
                                        const char* phaseTag) {
    if (!g_dynRack)
        return;

    typedef void (*fn_InputConfigurationChanged)(void* rack);
    auto inputConfigurationChanged = (fn_InputConfigurationChanged)RESOLVE(0x1005ce2f0);
    if (!inputConfigurationChanged)
        return;

    fprintf(stderr,
            "[MC]   [%s] DynamicsRack InputConfigurationChanged (rack=%p)\n",
            phaseTag, g_dynRack);
    inputConfigurationChanged(g_dynRack);

    for (const auto& op : dyn8StereoOps) {
        if (op.leftUnitIdx < 0)
            continue;
        assignDyn8InsertWithSetInserts(op.tgtStart, op.leftUnitIdx, op.ip, 0, phaseTag);
        refreshDyn8InsertAssignment(op.leftUnitIdx, op.tgtStart, phaseTag);
        refreshDyn8InsertAssignment(op.leftUnitIdx + 1, op.tgtStart + 1, phaseTag);
    }

    for (const auto& op : dyn8Ops) {
        if (op.clearOnly || op.unitIdx < 0)
            continue;
        assignDyn8InsertWithSetInserts(op.tgtCh, op.unitIdx, op.ip, 0, phaseTag);
        refreshDyn8InsertAssignment(op.unitIdx, op.tgtCh, phaseTag);
    }

    QApplication::processEvents();
}

static uint8_t remapCopiedSidechainChannel(uint8_t oldChannel,
                                           int copySrcStart,
                                           int copyBlockSize,
                                           int dstStart) {
    if (copyBlockSize <= 0)
        return oldChannel;
    int rel = (int)oldChannel - copySrcStart;
    if (rel < 0 || rel >= copyBlockSize)
        return oldChannel;
    int mapped = dstStart + rel;
    if (mapped < 0 || mapped > 127)
        return oldChannel;
    return (uint8_t)mapped;
}

static bool pasteCopyBufferToInputStart(int dstStart) {
    if (!g_copyBuffer.valid) {
        fprintf(stderr, "[MC] Paste channel settings: clipboard is empty.\n");
        return false;
    }

    std::vector<CopyPasteDyn8Op> dyn8Ops;
    std::vector<CopyPasteDyn8StereoPairOp> dyn8StereoOps;
    std::set<int> reservedDyn8Units;
    collectAssignedDyn8Units(reservedDyn8Units);
    ChannelSnapshot liveBefore[2];
    bool haveLiveBefore[2] = {false, false};
    bool dyn8Handled[2][2] = {};

    fprintf(stderr, "[MC] Pasting %s settings to ch %d%s.\n",
            g_copyBuffer.stereo ? "stereo" : "mono",
            dstStart + 1,
            g_copyBuffer.stereo ? QString("+%1").arg(dstStart + 2).toUtf8().constData() : "");

    for (int i = 0; i < g_copyBuffer.blockSize; i++) {
        int tgtCh = dstStart + i;
        haveLiveBefore[i] = snapshotChannel(tgtCh, liveBefore[i]);

        ChannelSnapshot pasteSnap = g_copyBuffer.snaps[i];
        for (int p = 5; p <= 6; p++) {
            if (!pasteSnap.validB[p])
                continue;
            uint8_t stripType = pasteSnap.dataB[p].buf[1];
            uint8_t oldChannel = pasteSnap.dataB[p].buf[2];
            if (stripType != 1)
                continue;
            uint8_t newChannel = remapCopiedSidechainChannel(oldChannel,
                                                             g_copyBuffer.srcStart,
                                                             g_copyBuffer.blockSize,
                                                             dstStart);
            if (newChannel != oldChannel) {
                pasteSnap.dataB[p].buf[2] = newChannel;
                fprintf(stderr,
                        "[MC]   Copy-paste remap %s for target ch %d: channel %u -> %u\n",
                        g_procB[p].name, tgtCh + 1, oldChannel, newChannel);
            }
        }

        if (!recallChannel(tgtCh, pasteSnap, true)) {
            fprintf(stderr, "[MC] Paste channel settings failed on ch %d.\n", tgtCh + 1);
            for (int j = 0; j <= i; j++) {
                if (haveLiveBefore[j])
                    destroySnapshot(liveBefore[j]);
            }
            return false;
        }
        if (pasteSnap.validB[1]) {
            uint16_t wantDelay = ((uint16_t)pasteSnap.dataB[1].buf[1] << 8) |
                                 pasteSnap.dataB[1].buf[2];
            bool wantBypass = pasteSnap.dataB[1].buf[3] != 0;
            setDelayForChannel(tgtCh, wantDelay, wantBypass);
        }
        writeProcOrderForChannel(tgtCh, pasteSnap);
        replayMixerStateForChannel(tgtCh, pasteSnap, "copy-paste");
        refreshSideChainStateForChannel(tgtCh, "copy-paste");
        if (pasteSnap.validPreamp) {
            PatchData tgtPatch = {};
            if (readPatchData(tgtCh, tgtPatch) &&
                patchDataUsesSocketBackedPreamp(tgtPatch) &&
                writePreampDataForPatch(tgtPatch, pasteSnap.preampData)) {
                fprintf(stderr,
                        "[MC]   Copy-paste preamp on ch %d: gain=%d pad=%d phantom=%d\n",
                        tgtCh + 1,
                        pasteSnap.preampData.gain,
                        pasteSnap.preampData.pad,
                        pasteSnap.preampData.phantom);
            } else {
                fprintf(stderr,
                        "[MC]   Copy-paste preamp skipped on ch %d (no writable socket-backed preamp)\n",
                        tgtCh + 1);
            }
        }
    }

    if (g_copyBuffer.stereo && g_copyBuffer.blockSize == 2 && isChannelStereo(dstStart)) {
        for (int ip = 0; ip < 2; ip++) {
            bool srcLeftDyn8 = g_copyBuffer.snaps[0].validDyn8 &&
                               g_copyBuffer.snaps[0].insertInfo[ip].hasInsert &&
                               g_copyBuffer.snaps[0].insertInfo[ip].parentType == 5;
            bool srcRightDyn8 = g_copyBuffer.snaps[1].validDyn8 &&
                                g_copyBuffer.snaps[1].insertInfo[ip].hasInsert &&
                                g_copyBuffer.snaps[1].insertInfo[ip].parentType == 5;
            if (!srcLeftDyn8 || !srcRightDyn8)
                continue;

            bool tgtLeftForeign = haveLiveBefore[0] &&
                                  liveBefore[0].insertInfo[ip].hasInsert &&
                                  liveBefore[0].insertInfo[ip].parentType != 0 &&
                                  liveBefore[0].insertInfo[ip].parentType != 5;
            bool tgtRightForeign = haveLiveBefore[1] &&
                                   liveBefore[1].insertInfo[ip].hasInsert &&
                                   liveBefore[1].insertInfo[ip].parentType != 0 &&
                                   liveBefore[1].insertInfo[ip].parentType != 5;
            if (tgtLeftForeign || tgtRightForeign) {
                fprintf(stderr,
                        "[MC]   Copy-paste stereo Dyn8 Insert%c on ch %d+%d skipped: target pair has non-Dyn8 insert(s)\n",
                        'A' + ip, dstStart + 1, dstStart + 2);
                continue;
            }

            bool tgtLeftDyn8 = haveLiveBefore[0] &&
                               liveBefore[0].insertInfo[ip].hasInsert &&
                               liveBefore[0].insertInfo[ip].parentType == 5;
            bool tgtRightDyn8 = haveLiveBefore[1] &&
                                liveBefore[1].insertInfo[ip].hasInsert &&
                                liveBefore[1].insertInfo[ip].parentType == 5;
            int leftUnitIdx = tgtLeftDyn8 ? findDyn8UnitIdx(liveBefore[0].insertInfo[ip].fxSendPt) : -1;
            int rightUnitIdx = tgtRightDyn8 ? findDyn8UnitIdx(liveBefore[1].insertInfo[ip].fxSendPt) : -1;

            CopyPasteDyn8StereoPairOp op = {};
            op.tgtStart = dstStart;
            op.ip = ip;
            memcpy(op.leftDyn8Data, g_copyBuffer.snaps[0].dyn8Data, sizeof(op.leftDyn8Data));
            memcpy(op.rightDyn8Data, g_copyBuffer.snaps[1].dyn8Data, sizeof(op.rightDyn8Data));
            op.validLeftData = true;
            op.validRightData = true;

            if (leftUnitIdx >= 0 && rightUnitIdx == leftUnitIdx + 1) {
                op.leftUnitIdx = leftUnitIdx;
                fprintf(stderr,
                        "[MC]   Copy-paste stereo Dyn8 Insert%c on ch %d+%d will reuse pair units %d/%d\n",
                        'A' + ip, dstStart + 1, dstStart + 2, leftUnitIdx, rightUnitIdx);
            } else {
                op.leftUnitIdx = findFreeDyn8StereoPair(reservedDyn8Units);
                if (op.leftUnitIdx < 0) {
                    fprintf(stderr,
                            "[MC]   Copy-paste stereo Dyn8 Insert%c on ch %d+%d skipped: no free Dyn8 pair\n",
                            'A' + ip, dstStart + 1, dstStart + 2);
                    continue;
                }
                reservedDyn8Units.insert(op.leftUnitIdx);
                reservedDyn8Units.insert(op.leftUnitIdx + 1);
                fprintf(stderr,
                        "[MC]   Copy-paste stereo Dyn8 Insert%c on ch %d+%d will allocate free pair %d/%d\n",
                        'A' + ip, dstStart + 1, dstStart + 2, op.leftUnitIdx, op.leftUnitIdx + 1);
            }

            dyn8StereoOps.push_back(op);
            dyn8Handled[0][ip] = true;
            dyn8Handled[1][ip] = true;
        }
    }

    for (int i = 0; i < g_copyBuffer.blockSize; i++) {
        int tgtCh = dstStart + i;
        for (int ip = 0; ip < 2; ip++) {
            if (dyn8Handled[i][ip])
                continue;

            bool srcDyn8 = g_copyBuffer.snaps[i].validDyn8 &&
                           g_copyBuffer.snaps[i].insertInfo[ip].hasInsert &&
                           g_copyBuffer.snaps[i].insertInfo[ip].parentType == 5;
            bool tgtDyn8 = haveLiveBefore[i] &&
                           liveBefore[i].insertInfo[ip].hasInsert &&
                           liveBefore[i].insertInfo[ip].parentType == 5;
            bool tgtForeignInsert = haveLiveBefore[i] &&
                                    liveBefore[i].insertInfo[ip].hasInsert &&
                                    liveBefore[i].insertInfo[ip].parentType != 0 &&
                                    liveBefore[i].insertInfo[ip].parentType != 5;
            int tgtDyn8Unit = tgtDyn8 ? findDyn8UnitIdx(liveBefore[i].insertInfo[ip].fxSendPt) : -1;

            if (srcDyn8) {
                CopyPasteDyn8Op op = {};
                op.tgtCh = tgtCh;
                op.ip = ip;
                op.clearOnly = false;
                op.validData = true;
                memcpy(op.dyn8Data, g_copyBuffer.snaps[i].dyn8Data, sizeof(op.dyn8Data));

                if (tgtDyn8 && tgtDyn8Unit >= 0) {
                    op.unitIdx = tgtDyn8Unit;
                    fprintf(stderr,
                            "[MC]   Copy-paste Dyn8 Insert%c on ch %d will reuse unit %d\n",
                            'A' + ip, tgtCh + 1, op.unitIdx);
                } else if (tgtForeignInsert) {
                    fprintf(stderr,
                            "[MC]   Copy-paste Dyn8 Insert%c on ch %d skipped: target has non-Dyn8 insert type=%d\n",
                            'A' + ip, tgtCh + 1, liveBefore[i].insertInfo[ip].parentType);
                    continue;
                } else {
                    op.unitIdx = findFreeDyn8Unit(reservedDyn8Units);
                    if (op.unitIdx < 0) {
                        fprintf(stderr,
                                "[MC]   Copy-paste Dyn8 Insert%c on ch %d skipped: no free Dyn8 unit\n",
                                'A' + ip, tgtCh + 1);
                        continue;
                    }
                    reservedDyn8Units.insert(op.unitIdx);
                    fprintf(stderr,
                            "[MC]   Copy-paste Dyn8 Insert%c on ch %d will allocate free unit %d\n",
                            'A' + ip, tgtCh + 1, op.unitIdx);
                }

                dyn8Ops.push_back(op);
            } else if (tgtDyn8 && tgtDyn8Unit >= 0) {
                CopyPasteDyn8Op op = {};
                op.tgtCh = tgtCh;
                op.ip = ip;
                op.unitIdx = tgtDyn8Unit;
                op.clearOnly = true;
                dyn8Ops.push_back(op);
                fprintf(stderr,
                        "[MC]   Copy-paste will clear stale Dyn8 Insert%c on ch %d (unit %d)\n",
                        'A' + ip, tgtCh + 1, tgtDyn8Unit);
            }
        }
    }

    for (int i = 0; i < g_copyBuffer.blockSize; i++) {
        if (haveLiveBefore[i])
            destroySnapshot(liveBefore[i]);
    }

    for (const auto& op : dyn8Ops) {
        if (!op.clearOnly)
            continue;
        routeDyn8InsertForChannelSlot(op.tgtCh, op.ip, op.unitIdx, true, "copy-paste-dyn8-clear");
    }
    auto replayCopyPasteDyn8Payloads = [&](const char* phaseTag) {
        for (const auto& op : dyn8StereoOps) {
            if (op.validLeftData)
                replayDyn8DataToUnit(op.leftUnitIdx, op.leftDyn8Data, op.tgtStart, op.ip, phaseTag);
            if (op.validRightData)
                replayDyn8DataToUnit(op.leftUnitIdx + 1, op.rightDyn8Data, op.tgtStart + 1, op.ip, phaseTag);
        }
        for (const auto& op : dyn8Ops) {
            if (op.clearOnly)
                continue;
            replayDyn8DataToUnit(op.unitIdx, op.dyn8Data, op.tgtCh, op.ip, phaseTag);
        }
    };

    for (const auto& op : dyn8StereoOps) {
        setInputChannelInsertFlags(op.tgtStart, op.ip, true, true, "copy-paste-dyn8-stereo");
        setInputChannelInsertFlags(op.tgtStart + 1, op.ip, true, true, "copy-paste-dyn8-stereo");
        if (!assignDyn8InsertWithSetInserts(op.tgtStart, op.leftUnitIdx, op.ip, 0, "copy-paste-dyn8-stereo"))
            continue;
        if (op.validLeftData)
            replayDyn8DataToUnit(op.leftUnitIdx, op.leftDyn8Data, op.tgtStart, op.ip, "copy-paste-dyn8-stereo");
        if (op.validRightData)
            replayDyn8DataToUnit(op.leftUnitIdx + 1, op.rightDyn8Data, op.tgtStart + 1, op.ip, "copy-paste-dyn8-stereo");
    }
    for (const auto& op : dyn8Ops) {
        if (op.clearOnly)
            continue;
        if (!routeDyn8InsertForChannelSlot(op.tgtCh, op.ip, op.unitIdx, false, "copy-paste-dyn8-assign"))
            continue;
        replayDyn8DataToUnit(op.unitIdx, op.dyn8Data, op.tgtCh, op.ip, "copy-paste-dyn8-data");
    }

    if (!dyn8Ops.empty() || !dyn8StereoOps.empty()) {
        refreshDyn8RackForCopyPaste(dyn8Ops, dyn8StereoOps, "copy-paste-dyn8-rack-refresh");
        replayCopyPasteDyn8Payloads("copy-paste-dyn8-post-refresh");
    }

    for (const auto& op : dyn8Ops) {
        if (op.clearOnly)
            continue;
        ChannelSnapshot verify;
        if (snapshotChannel(op.tgtCh, verify)) {
            fprintf(stderr,
                    "[MC]   [copy-paste-dyn8-verify] live ch %d: validDyn8=%d Insert%c type=%d first16=%02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x\n",
                    op.tgtCh + 1,
                    verify.validDyn8 ? 1 : 0,
                    'A' + op.ip,
                    verify.insertInfo[op.ip].parentType,
                    verify.dyn8Data[0], verify.dyn8Data[1], verify.dyn8Data[2], verify.dyn8Data[3],
                    verify.dyn8Data[4], verify.dyn8Data[5], verify.dyn8Data[6], verify.dyn8Data[7],
                    verify.dyn8Data[8], verify.dyn8Data[9], verify.dyn8Data[10], verify.dyn8Data[11],
                    verify.dyn8Data[12], verify.dyn8Data[13], verify.dyn8Data[14], verify.dyn8Data[15]);
            destroySnapshot(verify);
        }
    }

    return true;
}

static bool isAuxStripType(uint32_t stripType) {
    return (stripType & ~1u) == 4u;
}

struct UICopyPasteResetCommand {
    uint32_t task;
    uint32_t target;
    uint64_t stripKey;
};

static bool sendBuiltInCopyPasteResetCommand(uint32_t task, uint32_t target, const SelectedStripInfo& strip) {
    if (!strip.valid || strip.channel < 0 || strip.channel > 255) return false;
    uint64_t stripKey = MAKE_KEY(strip.stripType, (uint8_t)strip.channel);
    if (g_uiCopyPasteResetManager) {
        typedef void (*fn_PerformCommand)(void* obj, const UICopyPasteResetCommand& cmd);
        auto performCommand = (fn_PerformCommand)RESOLVE(0x10076de90);
        if (performCommand) {
            UICopyPasteResetCommand cmd = {};
            cmd.task = task;
            cmd.target = target;
            cmd.stripKey = stripKey;
            fprintf(stderr,
                    "[MC] Built-in CPR command via UI manager: task=%u target=%u stripType=%u channel=%d\n",
                    task, target, strip.stripType, strip.channel + 1);
            performCommand(g_uiCopyPasteResetManager, cmd);
            return true;
        }
        fprintf(stderr, "[MC] Built-in CPR command unavailable: PerformCommand symbol missing.\n");
    }

    if (!g_copyPasteResetSwitchInterpreter) {
        fprintf(stderr,
                "[MC] Built-in CPR command unavailable: UI manager and switch interpreter not found.\n");
        return false;
    }
    typedef void (*fn_SendCopyPasteResetCommand)(void* obj, uint32_t task, uint32_t target, uint64_t stripKey);
    auto sendCommand = (fn_SendCopyPasteResetCommand)RESOLVE(0x10040a720);
    if (!sendCommand) {
        fprintf(stderr, "[MC] Built-in CPR command unavailable: switch interpreter symbol missing.\n");
        return false;
    }
    fprintf(stderr, "[MC] Built-in CPR command via switch interpreter: task=%u target=%u stripType=%u channel=%d\n",
            task, target, strip.stripType, strip.channel + 1);
    sendCommand(g_copyPasteResetSwitchInterpreter, task, target, stripKey);
    return true;
}

static bool copySelectedChannelSettings() {
    SelectedStripInfo selectedStrip = getSelectedStripInfo(true);
    if (selectedStrip.valid && isAuxStripType(selectedStrip.stripType)) {
        return sendBuiltInCopyPasteResetCommand(1, 2, selectedStrip);
    }

    int ch = getSelectedInputChannel(true);
    if (ch < 0) {
        fprintf(stderr, "[MC] Copy channel settings: no selected input channel found.\n");
        return false;
    }
    return captureCopiedInputSettings(ch);
}

static bool pasteCopiedChannelSettings() {
    SelectedStripInfo selectedStrip = getSelectedStripInfo(true);
    if (selectedStrip.valid && isAuxStripType(selectedStrip.stripType)) {
        return sendBuiltInCopyPasteResetCommand(2, 2, selectedStrip);
    }

    if (!g_copyBuffer.valid) {
        fprintf(stderr, "[MC] Paste channel settings: clipboard is empty.\n");
        return false;
    }

    int ch = getSelectedInputChannel(true);
    if (ch < 0) {
        fprintf(stderr, "[MC] Paste channel settings: no selected input channel found.\n");
        return false;
    }

    bool targetStereo = isChannelStereo(ch);
    int dstStart = g_copyBuffer.stereo ? (ch & ~1) : ch;
    if (g_copyBuffer.stereo != targetStereo) {
        fprintf(stderr,
                "[MC] Paste channel settings rejected: source is %s but target ch %d is %s.\n",
                g_copyBuffer.stereo ? "stereo" : "mono",
                ch + 1,
                targetStereo ? "stereo" : "mono");
        return false;
    }

    return pasteCopyBufferToInputStart(dstStart);
}

static void installMoveShortcuts() {
    const QList<QWidget*> widgets = QApplication::topLevelWidgets();
    for (QWidget* widget : widgets) {
        if (!widget) continue;
        if (!widget->property("mcMoveShortcutInstalled").toBool()) {
            auto installOne = [widget](const QKeySequence& seq) {
                auto* shortcut = new QShortcut(seq, widget);
                shortcut->setContext(Qt::ApplicationShortcut);
                QObject::connect(shortcut, &QShortcut::activated, widget, []() {
                    fprintf(stderr, "[MC] Move shortcut activated.\n");
                    showMoveDialog();
                });
            };
            auto installUiShortcut = [widget](const QKeySequence& seq,
                                              const char* label,
                                              void (*action)()) {
                auto* shortcut = new QShortcut(seq, widget);
                shortcut->setContext(Qt::ApplicationShortcut);
                QObject::connect(shortcut, &QShortcut::activated, widget, [label, action]() {
                    fprintf(stderr, "[MC] %s shortcut activated.\n", label);
                    action();
                });
            };
            auto installAction = [widget](const QKeySequence& seq,
                                          const char* label,
                                          bool (*action)()) {
                auto* shortcut = new QShortcut(seq, widget);
                shortcut->setContext(Qt::ApplicationShortcut);
                QObject::connect(shortcut, &QShortcut::activated, widget, [label, action]() {
                    if (!shouldCaptureCopyPasteShortcut()) return;
                    fprintf(stderr, "[MC] %s shortcut activated.\n", label);
                    runCopyPasteShortcutAction(action == copySelectedChannelSettings,
                                              "QShortcut");
                });
            };
            installOne(QKeySequence(QStringLiteral("Ctrl+Shift+M")));
            installOne(QKeySequence(QStringLiteral("Meta+Shift+M")));
            installUiShortcut(QKeySequence(QStringLiteral("Ctrl+Shift+R")), "Reorder panel", showReorderDialog);
            installUiShortcut(QKeySequence(QStringLiteral("Meta+Shift+R")), "Reorder panel", showReorderDialog);
            installAction(QKeySequence(QStringLiteral("Ctrl+C")), "Copy", copySelectedChannelSettings);
            installAction(QKeySequence(QStringLiteral("Meta+C")), "Copy", copySelectedChannelSettings);
            installAction(QKeySequence(QStringLiteral("Ctrl+V")), "Paste", pasteCopiedChannelSettings);
            installAction(QKeySequence(QStringLiteral("Meta+V")), "Paste", pasteCopiedChannelSettings);
            widget->setProperty("mcMoveShortcutInstalled", true);
            fprintf(stderr, "[MC] Installed move shortcuts on top-level widget '%s'.\n",
                    widget->objectName().toUtf8().constData());
        }
    }
}

static bool shouldCaptureCopyPasteShortcut() {
    QWidget* focus = QApplication::focusWidget();
    if (!focus) return true;
    return !(focus->inherits("QLineEdit") ||
             focus->inherits("QTextEdit") ||
             focus->inherits("QPlainTextEdit") ||
             focus->inherits("QAbstractSpinBox"));
}

static void installNativeMacMoveShortcut() {
    if (g_moveShortcutMonitor) return;
    g_moveShortcutMonitor =
        [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown
                                              handler:^NSEvent* _Nullable(NSEvent* event) {
        if (!event) return event;
        NSEventModifierFlags mods = (event.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask);
        bool cmdShift = (mods & NSEventModifierFlagCommand) && (mods & NSEventModifierFlagShift);
        NSString* chars = [event charactersIgnoringModifiers];
        if (cmdShift && chars &&
            [chars caseInsensitiveCompare:@"m"] == NSOrderedSame) {
            fprintf(stderr, "[MC] Move shortcut caught by native mac monitor.\n");
            dispatch_async(dispatch_get_main_queue(), ^{
                showMoveDialog();
            });
            return nil;
        }
        if (cmdShift && chars &&
            [chars caseInsensitiveCompare:@"r"] == NSOrderedSame) {
            fprintf(stderr, "[MC] Reorder shortcut caught by native mac monitor.\n");
            dispatch_async(dispatch_get_main_queue(), ^{
                showReorderDialog();
            });
            return nil;
        }
        return event;
    }];
    fprintf(stderr, "[MC] Native mac shortcut monitor installed (Cmd+Shift+M / Cmd+Shift+R).\n");
}

// =============================================================================
// Global key event filter (more reliable than QShortcut for injected code)
// =============================================================================
class MCEventFilter : public QObject {
public:
    using QObject::QObject;
protected:
    bool eventFilter(QObject* obj, QEvent* event) override {
        if (event->type() == QEvent::MouseButtonPress ||
            event->type() == QEvent::MouseButtonRelease ||
            event->type() == QEvent::TouchBegin ||
            event->type() == QEvent::TouchEnd) {
            g_lastPointerSelectionEventMs = monotonicMs();
            if (event->type() == QEvent::MouseButtonRelease ||
                event->type() == QEvent::TouchEnd) {
                scheduleWestPreampGainPushAfterPointerSelection();
            }
        }
        if (event->type() == QEvent::ShortcutOverride || event->type() == QEvent::KeyPress) {
            auto* ke = static_cast<QKeyEvent*>(event);
            Qt::KeyboardModifiers mods = ke->modifiers();
            bool ctrlShift = (mods & (Qt::ControlModifier | Qt::ShiftModifier)) ==
                             (Qt::ControlModifier | Qt::ShiftModifier);
            bool metaShift = (mods & (Qt::MetaModifier | Qt::ShiftModifier)) ==
                             (Qt::MetaModifier | Qt::ShiftModifier);
            bool ctrlOnly = (mods & Qt::ControlModifier) && !(mods & Qt::ShiftModifier) &&
                            !(mods & Qt::MetaModifier) && !(mods & Qt::AltModifier);
            bool metaOnly = (mods & Qt::MetaModifier) && !(mods & Qt::ShiftModifier) &&
                            !(mods & Qt::ControlModifier) && !(mods & Qt::AltModifier);
            if (ke->key() == Qt::Key_M &&
                (ctrlShift || metaShift)) {
                fprintf(stderr, "[MC] Move shortcut caught by global filter (type=%d).\n",
                        (int)event->type());
                showMoveDialog();
                return true;
            }
            if (ke->key() == Qt::Key_R &&
                (ctrlShift || metaShift)) {
                fprintf(stderr, "[MC] Reorder shortcut caught by global filter (type=%d).\n",
                        (int)event->type());
                showReorderDialog();
                return true;
            }
            if ((ke->key() == Qt::Key_C || ke->key() == Qt::Key_V) &&
                (ctrlOnly || metaOnly) && shouldCaptureCopyPasteShortcut()) {
                bool isCopy = (ke->key() == Qt::Key_C);
                if (ke->isAutoRepeat() || !shouldTriggerCopyPasteShortcut(isCopy))
                    return true;
                fprintf(stderr, "[MC] %s shortcut caught by global filter (type=%d).\n",
                        isCopy ? "Copy" : "Paste", (int)event->type());
                runCopyPasteShortcutAction(isCopy, "global-filter");
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
        int socketNum = -1;
        if (readPreampDataForPatch(patch, pd) &&
            getAnalogueSocketIndexForAudioSource(patch.source, socketNum))
            fprintf(stderr, "[MC]      preamp: socket=%u gain=%d pad=%d phantom=%d\n",
                    (unsigned)socketNum, pd.gain, pd.pad, pd.phantom);
    }

    ChannelSnapshot abcdSnap;
    if (snapshotChannel(ch, abcdSnap)) {
        fprintf(stderr, "[MC]       ABCD: enabled=%d active=%u\n",
                abcdSnap.abcdEnabled ? 1 : 0, abcdSnap.activeInputSource);
        for (int i = 0; i < 4; i++) {
            const auto& aid = abcdSnap.activeInputData[i];
            if (!aid.assigned) continue;
            fprintf(stderr, "[MC]   ABCD-%c: type=%u num=%u",
                    'A' + i, aid.source.type, aid.source.number);
            if (aid.validPreamp) {
                fprintf(stderr, " gain=%d pad=%d phantom=%d",
                        aid.preampData.gain, aid.preampData.pad, aid.preampData.phantom);
            }
            fprintf(stderr, "\n");
        }
        destroySnapshot(abcdSnap);
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
    if (const char* dumpShowsEnv = getenv("MC_DUMP_SHOWS")) {
        fprintf(stderr, "[MC] MC_DUMP_SHOWS='%s'\n", dumpShowsEnv);
    }
    if (const char* recallShowEnv = getenv("MC_AUTOTEST_RECALL_SHOW")) {
        fprintf(stderr, "[MC] MC_AUTOTEST_RECALL_SHOW='%s'\n", recallShowEnv);
    }
    resolveSlide();
    maybePatchDirectorSingletonKey();
    resolveSymbols();

    // Poll for app instance availability (user may need to click Offline first)
    __block int pollCount = 0;
    __block void (^pollBlock)(void) = nullptr;
    pollBlock = Block_copy(^{
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
        installMoveShortcuts();
        installNativeMacMoveShortcut();
        refreshToolbarReorderButton();
        if (const char* dumpEnv = getenv("MC_DUMP_TOPNAV")) {
            if (atoi(dumpEnv) != 0) {
                QTimer::singleShot(1500, qApp, []() {
                    dumpTopNavWidgets();
                    dumpTopNavQuickTree();
                });
            }
        }
        if (!g_toolbarButtonRefreshTimer) {
            g_toolbarButtonRefreshTimer = new QTimer(qApp);
            g_toolbarButtonRefreshTimer->setInterval(1000);
            QObject::connect(g_toolbarButtonRefreshTimer, &QTimer::timeout, qApp, []() {
                refreshToolbarReorderButton();
            });
            g_toolbarButtonRefreshTimer->start();
        }
        if (g_autotestOverlayStatusPath.isEmpty()) {
            if (const char* statusPathEnv = getenv("MC_AUTOTEST_STATUS_FILE")) {
                if (statusPathEnv[0] != '\0')
                    g_autotestOverlayStatusPath = QString::fromUtf8(statusPathEnv);
            }
        }
        if (!g_autotestOverlayStatusPath.isEmpty() && !g_autotestOverlayStatusTimer) {
            g_autotestOverlayStatusTimer = new QTimer(qApp);
            g_autotestOverlayStatusTimer->setInterval(300);
            QObject::connect(g_autotestOverlayStatusTimer, &QTimer::timeout, qApp, []() {
                pollAutotestOverlayStatusFile();
            });
            g_autotestOverlayStatusTimer->start();
            pollAutotestOverlayStatusFile();
        }
        if (westPreampSyncEnabled() && !g_westPreampSyncTimer) {
            g_westPreampSyncTimer = new QTimer(qApp);
            g_westPreampSyncTimer->setInterval(250);
            QObject::connect(g_westPreampSyncTimer, &QTimer::timeout, qApp, []() {
                syncWestPreampUiToSelectedChannel(false);
            });
            g_westPreampSyncTimer->start();
            QTimer::singleShot(1200, qApp, []() {
                syncWestPreampUiToSelectedChannel(true, "[MC] west sync (startup) ");
            });
        }
        QObject::connect(qApp, &QGuiApplication::focusWindowChanged, qApp, [](QWindow*) {
            SelectedStripInfo strip = getSelectedStripInfo(false);
            if (strip.valid)
                rescanSelectionProvidersFromUIHolder((int)strip.stripType,
                                                     strip.channel,
                                                     false);
            installMoveShortcuts();
            refreshToolbarReorderButton();
            if (westPreampSyncEnabled())
                syncWestPreampUiToSelectedChannel(true, "[MC] west sync (focus) ");
        });
        hookShowManagerSignalsForLogging();
        fprintf(stderr, "[MC] Global key filter installed (Ctrl+Shift+M / Cmd+Shift+M).\n");

        if (envFlagEnabled("MC_DUMP_SHOWS")) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 500 * NSEC_PER_MSEC),
                           dispatch_get_main_queue(), ^{
                dumpAvailableShows();
            });
        }

        if (getenv("MC_EXPERIMENT_ARCHIVE_SHOW_NAME")) {
            fprintf(stderr, "[MC] Native show archive experiment requested via environment.\n");
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC),
                           dispatch_get_main_queue(), ^{
                if (!maybeRecallAutotestShow()) {
                    if (autotestEnvEnabled("MC_AUTOTEST_EXIT"))
                        qApp->quit();
                    return;
                }
                bool ok = runArchiveCurrentShowExperiment();
                if (autotestEnvEnabled("MC_AUTOTEST_EXIT")) {
                    fprintf(stderr,
                            "[MC] Native show archive experiment finished, quitting app (%s).\n",
                            ok ? "PASS" : "FAIL");
                    qApp->quit();
                }
            });
        } else if (getenv("MC_EXPERIMENT_COPY_SHOW_SRC")) {
            fprintf(stderr, "[MC] Native show copy experiment requested via environment.\n");
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 6 * NSEC_PER_SEC),
                           dispatch_get_main_queue(), ^{
                bool ok = runShowCopyRecallExperiment();
                if (autotestEnvEnabled("MC_AUTOTEST_EXIT")) {
                    fprintf(stderr,
                            "[MC] Native show copy experiment finished, quitting app (%s).\n",
                            ok ? "PASS" : "FAIL");
                    qApp->quit();
                }
            });
        } else if (getenv("MC_AUTOTEST_SELECT_ONLY") && getenv("MC_AUTOTEST_SELECT_CH")) {
            fprintf(stderr, "[MC] Select autotest requested via environment.\n");
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC),
                           dispatch_get_main_queue(), ^{
                if (const char* recallShowEnv = getenv("MC_AUTOTEST_RECALL_SHOW")) {
                    if (recallShowEnv[0] != '\0') {
                        if (!maybeRecallAutotestShow()) {
                            if (autotestEnvEnabled("MC_AUTOTEST_EXIT"))
                                qApp->quit();
                            return;
                        }
                    }
                }
                bool ok = runAutomatedSelectTest();
                if (const char* exitEnv = getenv("MC_AUTOTEST_EXIT")) {
                    if (atoi(exitEnv) != 0) {
                        fprintf(stderr, "[MC] Select autotest finished, quitting app (%s).\n", ok ? "PASS" : "FAIL");
                        qApp->quit();
                    }
                }
            });
        } else if (getenv("MC_AUTOTEST_COPY_SRC") && getenv("MC_AUTOTEST_COPY_DST")) {
            fprintf(stderr, "[MC] Copy/paste autotest requested via environment.\n");
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC),
                           dispatch_get_main_queue(), ^{
                if (!maybeRecallAutotestShow()) {
                    if (autotestEnvEnabled("MC_AUTOTEST_EXIT"))
                        qApp->quit();
                    return;
                }
                bool ok = runAutomatedCopyPasteTest();
                if (const char* exitEnv = getenv("MC_AUTOTEST_EXIT")) {
                    if (atoi(exitEnv) != 0) {
                        fprintf(stderr, "[MC] Copy/paste autotest finished, quitting app (%s).\n", ok ? "PASS" : "FAIL");
                        qApp->quit();
                    }
                }
            });
        } else if (getenv("MC_AUTOTEST_SRC") && getenv("MC_AUTOTEST_DST")) {
            fprintf(stderr, "[MC] Autotest requested via environment.\n");
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC),
                           dispatch_get_main_queue(), ^{
                if (!maybeRecallAutotestShow()) {
                    if (autotestEnvEnabled("MC_AUTOTEST_EXIT"))
                        qApp->quit();
                    return;
                }
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
                moveChannel(0, 3, true, false);
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
    });
    // Start polling after initial 5s delay
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC),
                   dispatch_get_main_queue(), pollBlock);
}
