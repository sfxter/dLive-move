#pragma once
#include <cstdint>

// =============================================================================
// sChannelStripKey: 8 bytes, passed by value in a single register
// =============================================================================
// Layout: { uint32_t type; uint8_t number; uint8_t pad[3]; }
// Low 32 bits = eChannelStripType enum (1-based)
// Byte 4 (bits 32-39) = channel number (0-indexed)
// Bytes 5-7 = padding (zero)

struct sChannelStripKey {
    uint32_t type;
    uint8_t  number;
    uint8_t  _pad[3];
};
static_assert(sizeof(sChannelStripKey) == 8, "sChannelStripKey must be 8 bytes");

inline uint64_t makeKey(uint32_t type, uint8_t channel) {
    return (uint64_t)type | ((uint64_t)channel << 32);
}

// =============================================================================
// eChannelStripType enum values (1-based, values 1-20 valid)
// =============================================================================
enum eChannelStripType : uint32_t {
    CST_Input        = 1,   // Input channels 0-127 (128 total)
    CST_Mix2         = 2,   // Mix channel type (via DoesMixChannelExist)
    CST_Mix3         = 3,   // Mix channel type (exists ch=0)
    CST_Mix4         = 4,   // Mix channel type
    CST_Mix5         = 5,   // Mix channel type (exists ch=0)
    CST_Mix6         = 6,   // Mix channel type (exists ch=0)
    CST_Mix7         = 7,   // Mix channel type
    CST_Mix8         = 8,   // Mix channel type (exists ch=0)
    CST_Type9        = 9,   // Not present in default config
    CST_Type10       = 10,  // exists ch=0
    CST_Type11       = 11,  // exists ch=0
    CST_Type12       = 12,  // exists ch=0
    CST_Type13       = 13,  // exists ch=0
    CST_Type14       = 14,  // exists ch=0
    CST_Type15       = 15,  // exists ch=0
    CST_Type16       = 16,  // exists ch=0
    CST_Type17       = 17,
    CST_Type18       = 18,
    CST_Type19       = 19,  // exists ch=0
    CST_Type20       = 20,  // exists ch=0
};

// =============================================================================
// sAudioSource: 8 bytes, returned in rax
// =============================================================================
// Layout: { uint32_t sourceType; uint32_t channelNumber; }
// For local inputs: sourceType=5, channelNumber=0..127
// Input Ch 0 → {5, 0}, Ch 1 → {5, 1}, etc.

struct sAudioSource {
    uint32_t sourceType;
    uint32_t channelNumber;
};
static_assert(sizeof(sAudioSource) == 8, "sAudioSource must be 8 bytes");

// =============================================================================
// eCopyPasteResetDataType enum values (for GetDataNetObjectName)
// =============================================================================
// Discovered by probing GetDataNetObjectName with Input Ch 0
enum eCPRDataType : int {
    // 0 = unknown/invalid (no name returned)
    // 1 = unknown/invalid
    CPRDT_DigitalAttenuator     = 2,   // "Digital Attenuator Input Channel %02d"
    CPRDT_StereoImage           = 3,   // "Stereo Image Input Channel %02d"
    CPRDT_PreampModel           = 4,   // "Preamp Model Input Channel %02d"
    CPRDT_HPF                   = 5,   // "Highpass Filter Input Channel %02d"
    CPRDT_LPF                   = 6,   // "Lowpass Filter Input Channel %02d"
    CPRDT_Gate                  = 7,   // "Gate, Input Channel %02d"
    CPRDT_GateSCFilter          = 8,   // "SCF Gate, Input Channel %02d"
    CPRDT_GateSCSource          = 9,   // "Gate side chain source, Input Channel %02d"
    CPRDT_PEQ                   = 10,  // "Parametric EQ, Input Channel %02d"
    CPRDT_PEQIntermediate1      = 11,  // "Parametric EQ, Input Channel %02d - Intermediate"
    CPRDT_PEQIntermediate2      = 12,  // same
    CPRDT_PEQIntermediate3      = 13,  // same
    CPRDT_PEQIntermediate4      = 14,  // same
    // 15 = no name for Input ch (could be GEQ or Dynamics Insert)
    CPRDT_Compressor            = 16,  // "Compressor, Input Channel %02d"
    CPRDT_CompressorSCSource    = 17,  // "Compressor side chain source, Input Channel %02d"
    CPRDT_Delay                 = 18,  // "Delay, Input Channel %02d"
    CPRDT_DirectOutput          = 19,  // "Direct Output, Input Channel %02d"
    CPRDT_MixAssignments        = 20,  // "Mix Assignments Copy Paste Reset Manager"
    // 21-26 = not returned for Input channels (may be for GEQ, MIDI, etc.)
    CPRDT_MeteringRepeater      = 27,  // "Metering Repeater"
};

// Channel name format: "Input Channel %02d" (1-indexed: ch0 → "01", ch1 → "02")

// =============================================================================
// Helpers instance layout (at known offsets)
// =============================================================================
// helpers[0] = vtable pointer
// helpers[1] = cChannelMapperBase* (offset 8) — used for GetActiveInputChannelSource
// helpers[2] = cTSnakeStatusManager* (offset 16)
// helpers[3] = cTSnakeStatusManager* (offset 24)
// helpers[4] = cPortBSocketType** (offset 32)
// helpers[5] = null (offset 40)

// =============================================================================
// Symbol addresses (static, before ASLR slide)
// =============================================================================
namespace Addr {
    // Singletons
    constexpr uintptr_t CPRHelpers_Instance       = 0x100403270;
    constexpr uintptr_t App_Instance              = 0x100d5a120;
    constexpr uintptr_t UIManagerHolder_Instance   = 0x10076d170;
    constexpr uintptr_t Discovery_Instance         = 0x10059c610;

    // CPRHelpers member functions (this=rdi, key=rsi)
    constexpr uintptr_t Helpers_ChannelExists      = 0x100405630;
    constexpr uintptr_t Helpers_ChannelIsStereo    = 0x100405740;
    constexpr uintptr_t Helpers_ChannelHasPreamp   = 0x100405850;
    constexpr uintptr_t Helpers_GetAudioSource     = 0x1004058b0;
    constexpr uintptr_t Helpers_GetPreampName      = 0x100403aa0;
    constexpr uintptr_t Helpers_GetDataNetObjName  = 0x1004033e0;
    constexpr uintptr_t Helpers_IsMixChannel       = 0x100405830;

    // AudioCoreDM (member functions, need instance)
    constexpr uintptr_t AudioCoreDM_GetChannelName   = 0x1001a3750;
    constexpr uintptr_t AudioCoreDM_SetChannelName   = 0x1001a3670;
    constexpr uintptr_t AudioCoreDM_GetChannelColour = 0x1001a34a0;
    constexpr uintptr_t AudioCoreDM_SetChannelColour = 0x1001a3580;

    // SeekObject
    constexpr uintptr_t SeekObject_FindObject      = 0x1000f3f10;

    // Network messaging
    constexpr uintptr_t SendNetworkMessage         = 0x1000f3720;

    // Processing object GetStatus/SetStatus
    constexpr uintptr_t Compressor_GetStatus       = 0x1001f1000;
    constexpr uintptr_t Compressor_SetStatus       = 0x1001f1790;
    constexpr uintptr_t PreampModel_GetStatus      = 0x1002d4130;
    constexpr uintptr_t PreampModel_SetStatus      = 0x1002d4350;
    constexpr uintptr_t StereoImage_GetStatus      = 0x1002f5ca0;
    constexpr uintptr_t StereoImage_SetStatus      = 0x1002f5d20;
    constexpr uintptr_t DirectOutput_GetStatus     = 0x100234c60;
    constexpr uintptr_t DirectOutput_SetStatus     = 0x100234cd0;
    constexpr uintptr_t InsertNetObj_GetStatus     = 0x1002a4800;
    constexpr uintptr_t InsertNetObj_SetStatus     = 0x1002a4890;

    // Dynamics
    constexpr uintptr_t DynRack_FindFirstFreeUnit  = 0x1005ce210;
    constexpr uintptr_t DynRack_GetUnitClient      = 0x1005ce200;
    constexpr uintptr_t DynUnit_FullyUnassign      = 0x1005e7800;
    constexpr uintptr_t DynUnit_SetInsertIn        = 0x1005e8a50;
    constexpr uintptr_t DynUnit_SetSCSource        = 0x1005e9110;

    // Input channel
    constexpr uintptr_t InputChannel_AssignInsert1 = 0x100290490;
    constexpr uintptr_t InputChannel_AssignInsert2 = 0x1002905b0;

    // Stereo config
    constexpr uintptr_t AudioCoreDM_NewStereoConfig = 0x1001a0f10;
    constexpr uintptr_t App_NewInputConfig          = 0x100d6e0c0;

    // ChannelMapper
    constexpr uintptr_t ChMapper_GetActiveInputSrc  = 0x1004f2c40;

    // Name/Colour manager
    constexpr uintptr_t NameColourMgr_GetName      = 0x10055e870;
    constexpr uintptr_t NameColourMgr_SetName      = 0x10055e890;
    constexpr uintptr_t NameColourMgr_GetColour    = 0x10055e990;
}
