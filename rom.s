            INCLUDE 'ROMTools/Include.s'
            INCLUDE 'ROMTools/Globals.s'
            INCLUDE 'ROMTools/TrapMacros.s'
            INCLUDE 'ROMTools/CommonConst.s'
            INCLUDE 'ROMTools/Macros.s'
            INCLUDE 'ROMTools/Hardware/PowerBook170.s'

            machine 68030

; Orphaned equates
BootGlobalsSize		EQU $400
QDBootGlobalsSize	EQU 190
RelPram     EQU     $400B8
MMStartMode EQU     $0
MMSysHeap   EQU     $2
mmHighSysHeap       EQU $4
arrow       EQU     -$6C
gray        EQU     -$18
;ProductInfo.
Rom85Word   EQU     $14
ProductKind EQU     $12

            org     $40800000

BaseOfRom:
            dc.l    $420DBFF3
StartPC:
            dc.l    ResetEntry-BaseOfRom
ROMVersion:
            dc.b    $6
            dc.b    $7C
StBoot:
            jmp     StartBoot
BadDisk:
            jmp     StartBoot
            dc.w    $15F1
PatchFlags:
            dc.b    0
            dc.b    0
            dc.l    ForeignOS-BaseOfRom
RomRsrc:
            dc.l    $7EC10
Eject:
            jmp     GOOFYDoEject
DispOff:
            dc.l    DispTable-BaseOfRom
Critical:
            jmp     CritErr
ResetEntry:
            jmp     StartBoot
RomLoc:
            dc.b    $0
            dc.b    $0
            dc.l    $120B50F
            dc.l    $138C8FB
            dc.l    $11EE472
            dc.l    $1388767
            dc.l    1024*1024                       ; Size of ROM
ForeignOS:
            dc.l    InitDispatcher-BaseOfRom
            dc.l    EMT1010-BaseOfRom
            dc.l    BadTrap-BaseOfRom
            dc.l    StartSDeclMgr-BaseOfRom
            dc.l    InitMemVect-BaseOfRom
            dc.l    SwitchMMU-BaseOfRom
SwitchMMU:
            movec   CACR,D0
            move.w  D0,D1
            andi.w  #$FEFE,D0
            movec   D0,CACR
            lea     TCOff,A2
            pmove.l (A2),TC
            pflusha
            pmove.d (theCRP,A0),CRP
            pmove.l (theTC,A0),TC
            ori.w   #$808,D1
            movec   D1,CACR
TCOff:
            dc.w    0
StartBoot:
            move    #$2700,SR
            lea     DisableMMUPatchReturn,A6
            bra.w   DisableMMUPatch
            ds.b    4
DisableMMUPatch:
            reset
            BSR6    Universal
            BigBSR6 PortableCheck,A0
            bra.w   RunDiags
StartInit1:
            moveq   #0,D2
            movem.l A6-A5/D7-D5,-(SP)
            BSR6    GetHardwareInfo
            movea.l ($8,A0),A4
            moveq   #$40,D4
            and.b   (A4),D4
            BSR6    InitVIAs
            cmpi.b  #5,D2
            bne.b   .L1
            moveq   #-$41,D3
            and.b   (A4),D3
            or.b    D4,D3
            move.b  D3,(A4)
.L1:
            movem.l A3-A0/D2-D0,-(SP)
            BigBSR6 ValidatePRAM,A5
            movem.l (SP)+,D0-D2/A0-A3
            movem.l (SP)+,D5-D7/A5-A6
            bsr.w   WhichCPU
            bsr.w   WhichBoard
            bsr.w   ConfigureRAM
            bsr.w   GoToInitMMU
            movea.l (-$14,A4),A6
            movea.l A4,A5
            adda.l  (-$C,A4),A5
            move.l  D0,(AddrMapFlags)
            move.l  D1,(UnivROMFlags)
            move.l  A1,(UnivInfoPtr)
            swap    D2
            move.w  D2,(HWCfgFlags)
            swap    D2
            bsr.w   SetupHWBases
            bsr.l   InitHWRoutines
            nop
            nop
            nop
            move.l  WarmStart,-(SP)
            move.l  AddrMapFlags,-(SP)
            move.l  UnivROMFlags,-(SP)
            move.l  UnivInfoPtr,-(SP)
            jsr     FlagsPatch
            move.l  (SP)+,UnivInfoPtr
            move.l  (SP)+,UnivROMFlags
            move.l  (SP)+,AddrMapFlags
            move.l  (SP)+,WarmStart
            bsr.w   SetupHWBases
            move.b  D7,CPUFlag
            swap    D7
            move.b  D7,BoxFlag
            move.l  A6,MemTop
            move.l  A5,BufPtr
            move.l  A4,BootGlobPtr
            bsr.w   InitMMUGlobals
            bsr.w   SysErrInitPatch
            nop
            nop
            bsr.w   EnableCachesPatch
            bra.b   .L2
            ds.b    4
.L2:
            bsr.w   EnableExtCache
            BigJsr  DisableIntSources,A0
            bsr.w   SetUpTimeK
            bsr.w   InitHiMemGlobals
BootRetry:
            move    #$2700,SR
            moveq   #1,D0
            movea.l JSwapMMU,A0
            jsr     (A0)
            jsr     InitGlobalVars
            BigJsr  DisableIntSources,A0
            BigJsr  InitIntHandler,A0
            BigJsr  InitDispatcher,A0
            bsr.w   MMUStuff
            bra.w   InitEgretPatch
EgretPatchCont:
            bsr.w   InitMemMgrPatch
            btst.b  #0,MMFlags
            beq.b   .L1
            lea     NewTranslate24To32,A0
            move.l  A0,$644
.L1:
            moveq   #0,D0
            _SwapMMUMode
            bsr.w   SetupSysAppZone
            bsr.w   InitSwitcherTable
            bra.w   InitEgretPatch1
EgretPatch1Cont:
            BigJsr  NMInit,A0
            BigJsr  InitTimeMgr,A0
            bsr.w   InitMemDispAndShutdownMgrs
            BigJsr  InitSlots,A0
            bsr.w   InitDTQueue
            BigJsr  EnableOneSecInts,A0
            BigJsr  EnableParityPatch,A0
            move    #$2000,SR
            bsr.w   InitVidGlobals
            bsr.w   CompBootStack
            movea.l A0,SP
            suba.w  #$2000,A0
            move.b  MMFlags,-(SP)
            btst.b  #MMSysHeap,MMFlags
            beq.b   .do24
            bset.b  #MMStartMode,MMFlags
            bra.b   .knowHeap
.do24:
            bclr.b  #MMStartMode,MMFlags
.knowHeap:
            _SetApplLimit
            move.b  (SP)+,MMFlags
            lea     DrvQHdr,A1
            BigJsr  InitQueue,A0
            BigJsr  SCSIInit,A0
            bsr.w   InitIOMgr
            BigJsr  InitADB,A0
            bsr.w   InitCrsrMgr
            move.l  #$1BA,D0
            _NewPtrSysClear
            move.l  A0,ExpandMem
            move.w  #$11B,(A0)+
            move.l  #$1BA,(A0)
            BigJsr  InitGestalt,A0
            BigJsr  EclipseEgretPatches,A0
            BigJsr  TEGlobalInit,A0
            movea.l SysZone,A0
            movea.l (A0),A0
            adda.w  #$4000,A0
            _SetApplBase
            movea.l SysZone,A0
            move.l  A0,TheZone
            move.l  A0,ApplZone
            move.l  (A0),HeapEnd
            lea     (BootGlobalsSize,SP),A6
            lea     (QDBootGlobalsSize,SP),A5
            BigJsr  EnableSlotInts,A0
            bsr.w   PowerDownPatch
            bsr.b   CheckForResetPRAM
            move.l  #wmStConst,WarmStart
            moveq   #1,D0
            _SwapMMUMode
            BigJsr  SoundInitPatch,A0
SoundInitPatchRtn:
            bra.w   BootMe
CheckForResetPRAM:
            lea     .Keys,A1
            lea     KeyMap,A0
            moveq   #4-1,D0
.loop:
            cmpm.l  (A0)+,(A1)+
            dbne    D0,.loop
            beq.b   .normNuke
            rts
.normNuke:
            subq.l  #RelPram>>16,SP
            movea.l SP,A0
            move.l  #RelPram,D0
            _ReadXPRam
            move.l  (A0)+,D0
            _WriteXPRam
            _InitUtil
            movea.l SP,A0
            move.l  #RelPram,D0
            _WriteXPRam
            jmp     StartBoot
.Keys:
            dc.l    $800000
            dc.l    $8008004
            dc.l    $0
            dc.l    $0
            dc.l    $4000
            dc.l    'Gone'
            ds.b    2
EDiskPatch2:
            lea     .EDisk,A1
            move.l  A1,($12,A0)
            _Open
            lea     SndName,A1
            rts
.EDisk:
            dc.b    6
            dc.b    '.EDisk'
            ds.l    54
            ds.b    0
JmpTblInit:
            move.l  A0,D0
JmpTbl2:
            moveq   #0,D2
            move.w  (A0)+,D2
            add.l   D0,D2
            move.l  D2,(A1)+
            dbf     D1,JmpTbl2
NewTranslate24To32:
            rts
FillWithOnes:
            move.l  A1,D0
            sub.l   A0,D0
            lsr.l   #2,D0
            moveq   #-1,D1
.L1:
            move.l  D1,(A0)+
            subq.l  #1,D0
            bne.b   .L1
            rts
CompBootStack:
            move.l  BufPtr,D0
            add.l   SysZone,D0
            lsr.l   #1,D0
            bclr.l  #0,D0
            subi.w  #$400,D0
            movea.l D0,A0
            rts
            ds.b    10
SetupSysAppZone:
            lea     SysHeap,A0
            move.b  MMFlags,-(SP)
            btst.b  #MMSysHeap,MMFlags
            beq.b   .do24
            bset.b  #MMStartMode,MMFlags
            btst.b  #mmHighSysHeap,MMFlags
            beq.b   .knowHeap
            lea     SysHoleHeap,A0
            bra.b   .knowHeap
.do24:
            bclr.b  #MMStartMode,MMFlags
.knowHeap:
            _InitZone
            move.l  TheZone,SysZone
            move.l  SysZone,RAMBase
            movea.l SysZone,A0
            move.l  A0,ApplZone
            movea.l (A0),A0
            move.l  A0,HeapEnd
            bsr.b   CompBootStack
            cmpa.l  SP,A0
            bls.b   .L1
            movea.l SP,A0
.L1:
            suba.w  #$2000,A0
            _SetApplLimit
            move.b  (SP)+,MMFlags
            rts
SysHeap:
            dc.l    HeapStart
            dc.l    HeapStart+SysZoneSize
            dc.w    4*dfltMasters
            dc.l    0
SysHoleHeap:
            dc.l    HoleSysHeap
            dc.l    HoleSysHeap+SysZoneSize
            dc.w    2*dfltMasters
            dc.l    0
            ds.b    10
DrawBeepScreen:
            pea     (-4,A5)
            _InitGraf
            pea     (-$200,A6)
            _OpenCPort
            movea.l (A5),A2
            pea     (arrow,A2)
            _SetCursor
            bra.l   DrawBeepScreenPatch
DrawBeepScreenReturn:
            lea     Scratch8,A1
            move.l  A1,-(SP)
            move.l  A1,-(SP)
            move.l  (A0)+,(A1)+
            move.l  (A0),(A1)
            move.l  #$FFFDFFFD,-(SP)
            _InsetRect
            move.l  #$30003,-(SP)
            _PenSize
            move.l  #$160016,-(SP)
            _FrameRoundRect
            _PenNormal
            move.l  #$100010,-(SP)
            pea     (gray,A2)
            _FillRoundRect
            rts
InitShutdownMgr:
            clr.w   -(SP)
            _ShutDown
            rts
            ds.b    10
InitHiMemGlobals:
            move.w  #-1,PWMValue
            movea.l BufPtr,A0
            move.l  MemTop,PhysMemTop
            move.l  A0,RealMemTop
            dc.b    $21,$F0,$81,$E2,$0D,$DC,$FF,$E8,$1E,$F0
            moveq   #0,D1
            dc.b    $08,$30,$00,$00,$81,$E2,$0D,$DC,$FF,$E7
            bne.b   .L1
            move.l  #bufWorldSize,D0
            cmpa.l  D0,A0
            bls.b   .BufPtrOK
            movea.l D0,A0
.BufPtrOK:
            cmp.l   BootGlobPtr,D0
            bgt.b   .L1
            moveq   #1,D1
            bra.b   .L1
            ds.b    12
.L1:
            suba.w  #$2FF,A0
            move.l  A0,PWMBuf1
            move.l  A0,PWMBuf2
            subq.w  #1,A0
            move.l  A0,SoundBase
            move.l  A0,BufPtr
            tst.l   D1
            beq.b   .Exit
            bsr.w   MMUCleanupFor8MB
.Exit:
            rts
            ds.b    2
InitGlobalVars:
            lea     BaseOfRom,A0
            move.l  A0,ROMBase
            moveq   #-1,D0
            move.l  D0,SMGlobals
            movea.l UnivInfoPtr,A0
            move.w  (Rom85Word,A0),ROM85
            nop
            nop
            nop
            move.l  $10001,OneOne
            moveq   #-1,D0
            move.l  D0,MinusOne
            move.w  D0,FSFCBLen
            bsr.w   SetupHWBases
            clr.l   PollProc
            clr.l   DSAlertTab
            BigJsr  FSIODneTbl,A0
            lea     JFetch,A1
            moveq   #2,D1
            bsr.w   JmpTblInit
            clr.b   DskVerify
            clr.b   LoadTrap
            clr.b   MmInOK
            clr.w   SysEvtMask
            clr.l   JKybdTask
            clr.l   StkLowPt
            lea     VBLQueue,A1
            BigJsr  InitQueue,A0
            clr.l   Ticks
            move.b  #$80,MBState
            clr.l   MBTicks
            clr.l   SysFontFam
            clr.l   WidthTabHandle
            clr.w   TESysJust
            clr.b   WordRedraw
            clr.l   SynListHandle
            move.w  MinusOne,FMExist
            jsr     InitCrsrVars
            clr.w   SysVersion
            bclr.b  #0,AlarmState
            BigJsr  NMGNEFILTER,A0
            move.l  A0,JGNEFilter
            clr.l   IAZNotify
            move.w  #$FF7F,FlEvtMask
            moveq   #-1,D0
            move.w  D0,ChunkyDepth
            move.l  D0,CrsrPtr
            move.l  D0,PortList
            lea     RGBWhite,A0
            move.l  D0,(A0)+
            move.w  D0,(A0)
            lea     RGBBlack,A0
            clr.l   (A0)+
            clr.w   (A0)
            clr.l   LockMemCT
            rts
            dc.b    8
SWITCHGOODIES:
            dc.w    OSTable, 4*numOStrap
            dc.w    ToolTable, 4*numTBtrap
            dc.w    $B80, $26
            dc.w    $BAE, $52
            dc.w    HFSFlags, 2
            dc.w    DefVRefNum, 2
            dc.w    DefVCBPtr, 4
            dc.w    ScrDmpEnb, 2
            dc.w    CurDirStore, 4
            dc.w    MBProcHndl, 4
            dc.w    MonkeyLives, $2
            dc.w    MemTop, $14
            dc.w    SEvtEnb, $4
            dc.w    MinStack, $22
            dc.w    $800, $2FC
            dc.w    ApplLimit, $4
            dc.w    ApplZone, $4
            dc.w    AuxWinHead, $4
            dc.w    AuxCtlHead, $4
            dc.w    BNMQHd, $4
            dc.w    MenuCInfo, $4
            dc.w    MenuDisable, $8
            dc.w    TheGDevice, $4
WDCBSwitch:
            dc.w    0,0,0
PMSPSwitch:
            dc.w    0,0,4,0,0
WDCBSWOS:
            dc.w    $5C
PMSPSWOS:
            dc.w    $62
InitSwitcherTable:
            moveq   #$6C,D0
            _NewPtrSysClear
            movea.l A0,A1
            lea     SWITCHGOODIES,A0
            moveq   #$6C,D0
            _BlockMove
            move.l  A1,SwitcherTPtr
            rts
            ds.b    12
GetPRAM:
            _InitUtil
            moveq   #0,D1
            move.b  SPKbd,D1
            moveq   #$F,D0
            and.w   D1,D0
            bne.b   .L1
            moveq   #$48,D0
.L1:
            add.w   D0,D0
            move.w  D0,KeyRepThresh
            lsr.w   #4,D1
            bne.b   .L2
            move.w  #$1FFF,D1
.L2:
            lsl.w   #2,D1
            move.w  D1,KeyThresh
            move.b  SPClikCaret,D1
            moveq   #$F,D0
            and.b   D1,D0
            lsl.b   #2,D0
            move.l  D0,CaretTime
            lsr.b   #2,D1
            moveq   #$3C,D0
            and.b   D1,D0
            move.l  D0,DoubleTime
            rts
            ds.b    2
WhichCPU:
            moveq   #2,D7
            jmp     (.CheckIndexScale,PC,D7*2)
.CheckIndexScale:
            bra.b   .NoIndexScale
            bra.w   WhichCPUPatch
            ds.b    14
.NoIndexScale:
            move.l  SP,D7
            clr.w   -(SP)
            bsr.b   .doRTE
            exg     D7,SP
            sub.l   SP,D7
            addq.l  #2,D7
            lsr.l   #1,D7
            rts
.doRTE:
            move    SR,-(SP)
            rte
            ds.b    2
WhichBoard:
            swap    D7
            clr.w   D7
            move.b  (ProductKind,A1),D7
            swap    D7
            rts
            ds.b    4
SetUpTimeK:
            move.l  Lev1AutoVector,-(SP)
            move    SR,-(SP)
            ori     #HiIntMask,SR
            movea.l VIA,A1
            bclr.b  #5,(vACR,A1)
            move.b  #$FF,(vT2CH)
            move.b  #$A0,(vIER,A1)
            moveq   #$C,D1
            moveq   #3,D2
            movea.l SP,A3
            lea     TimerInt,A0
            move.l  A0,Lev1AutoVector
            lea     TimingTable,A4
.nextRoutine:
            movea.l A4,A0
            adda.w  (A4),A0
            moveq   #2,D0
            lea     .cacheLoaded,A2
            jmp     (A0)
.cacheLoaded:
            movea.l A4,A0
            adda.w  (A4)+,A0
            moveq   #-1,D0
            lea     .timedOut,A2
            andi    #$F8FF,SR
            jmp     (A0)
.timedOut:
            not.w   D0
            movea.w (A4)+,A0
            move.w  D0,(A0)
            tst.w   (A4)
            bne.b   .nextRoutine
            move.b  #$20,(vIER,A1)
            move    (SP)+,SR
            move.l  (SP)+,Lev1AutoVector
            rts
TimerInt:
            tst.b   (vT2C,A1)
            movea.l A3,SP
            jmp     (A2)
TimingTable:
            dc.w    DbraTime-*,TimeDBRA
            dc.w    SCCTime-*,TimeSCCDB
            dc.w    SCSITime-*,TimeSCSIDB
            dc.w    VIATime-*,TimeVIA
            dc.w    0
DbraTime:
            move.b  D1,(vT2C,A1)
            move.b  D2,(vT2CH,A1)
.loop:
            dbf     D0,.loop
            jmp     (A2)
SCCTime:
            movea.l (SCCRd),A0
            move.b  D1,(vT2C,A1)
            move.b  D2,(vT2CH,A1)
.loop:
            btst.b  #0,(A0)
            dbf     D0,.loop
            jmp     (A2)
SCSITime:
            bra.l   SETUPSCSITIME
            ds.b    18
VIATime:
            lea     (vIER,A1),A0
            move.b  D1,(vT2C,A1)
            move.b  D2,(vT2CH,A1)
.loop:
            btst.b  #0,(A0)
            dbf     D0,.loop
            jmp     (A2)
            ds.b    14
RunDiags:
            BigJsr  StartTest1,A0                   
            ds.b    30
STARTTESTFLAGS:
            ds.b    8
SetupHWBases:
            move.l  AddrMapFlags,D0
            movea.l UnivInfoPtr,A0
            adda.l  (A0),A0
            lea     .BaseInitTable,A2               ; Point to the table
.loop:
            move.w  (A2)+,D3                        ; Get the bit number
            bmi.b   .exit                           ; Exit if end of table
            movea.w (A2)+,A3                        ; Get the low mem address
            btst.l  D3,D0                           ; See if the base is valid
            beq.b   .loop                           ; If not, skip it
            lsl.w   #2,D3                           ; Setup index into bases table
            move.l  (A0,D3),A3                      ; Initialize the low mem
            bra.s   .loop
.exit:
            bra.l   SETUPMISKSCSI
            ds.b    20
.BaseInitTable:
            dc.w    VIA1Exists, VIA
            dc.w    SCCRdExists, SCCRd
            dc.w    SCCWrExists, SCCWr
            dc.w    SCCIOPExists, SCCRd
            dc.w    SCCIOPExists, SCCWr
            dc.w    IWMExists, IWM
            dc.w    SWIMExists, IWM
            dc.w    PWMExists, PWMBuf1
            dc.w    PWMExists, PWMBuf2
            dc.w    SoundExists, SoundBase
            dc.w    SCSIExists, SCSIBase
            dc.w    SCSIDackExists, SCSIDMA
            dc.w    SCSIHskExists, SCSIHsk
            dc.w    VIA2Exists, VIA2
            dc.w	ASCExists, ASCBase
            dc.w	SCSIDMAExists, SCSIBase
            dc.w	SCSIDMAExists, SCSIDMA
            dc.w	SCSIDMAExists, SCSIHsk
            dc.w    -1
            ds.b    4
InitSCSI:
            bra.l   InitSCSHW
            ds.b    26
InitIWM:
            btst.b  #5,(AddrMapFlags+3)
            beq.b   .ExitInitIWM
            movea.l IWM,A0
            moveq   #$17,D0
.L1:
            move.b  #-$42,(ph3L,A0)
            move.b  #-$8,(ph3H,A0)
            tst.b   (q7L,A0)
            tst.b   (mtrOff,A0)
            tst.b   (q6H,A0)
            move.b  (q7L,A0),D2
            btst.l  #5,D2
            bne.b   .L1
            and.b   D0,D2
            cmp.b   D0,D2
            beq.b   .L2
            move.b  D0,(q7H,A0)
            tst.b   (q7L,A0)
            bra.b   .L1
.L2:
            tst.b   (q6L,A0)
.ExitInitIWM:
            rts
            ds.b    10
InitSCCData:
            dc.l    $9C00940
            dc.l    $44C0200
            dc.l    $3C00F00
            dc.l    $100010
            dc.l    $1000980
            dc.l    $44C03C0
            dc.l    $F000010
            dc.l    $100100
InitSCC:
            btst.b  #1,(AddrMapFlags+1)
            beq.b   .NoIOP
            jsr     SCCIOPHWINIT
.NoIOP:
            movea.l SCCWr,A0
            movea.l SCCRd,A1
            lea     InitSCCData,A2
            moveq   #12,D1
            bsr.b   InitSCC2
            addq.w  #2,A0
            addq.w  #2,A1
            moveq   #14,D1
InitSCC2:
            move.b  (A1),D2
            bra.b   .L2
.L1:
            move.l  (SP),(SP)
            move.l  (SP),(SP)
            move.b  (A2)+,(A0)
.L2:
            dbf     D1,.L1
            rts
            ds.b    12
ConfigureRAM:
            movea.l (SP)+,SP
            move.l  (4,A6),D3
            cmpi.b  #$200000,D3
            bge.b   .plentyORam
            lsr.l   #2,D3
            mulu.l  #3,D3
            bra.b   .stakOk
.plentyORam:
            move.l  #defStackAddr,D3
.stakOk:
            exg     D3,SP
            adda.l  (A6),SP
            move.l  D3,-(SP)
            movea.l A6,A3
.L1:
            movea.l A3,A2
            move.l  (A3)+,D3
.L2:
            add.l   (A3)+,D3
            cmp.l   (A3)+,D3
            beq.b   .L2
            sub.l   (A2)+,D3
            move.l  D3,(A2)+
            subq.l  #4,A3
            cmpi.l  #-1,(A3)
            bne.b   .L1
            move.l  (A3),(A2)+
.L3:
            clr.l   (A2)+
            move.w  A2,D3
            bne.b   .L3
            suba.l  A6,A2
            move.l  A2,(-8,A6)
            rts
            ds.b    288
InitVidGlobals:
            rts
            rts
            ds.b    12
RdVidParam:
            movem.l A2-A1/D3,-(SP)
            move.b  (spId,A0),D3
            clr.b   (spExtDev,A0)
            _SRsrcInfo
            bne.w   .L1
            _SFindDevBase
            bne.w   .L1
            move.l  (A0),ScrnBase
            move.b  #MinorLength,(spId,A0)
            _SReadLong
            bne.w   .L1
            move.l  (A0),ScreenBytes
            move.b  D3,(spId,A0)
            bsr.w   GetDefVidMode
            move.b  D0,(spId,A0)
            _SFindStruct
            bne.w   .L1
            move.b  #1,(spId,A0)
            _SGetBlock
            bne.w   .L1
            movea.l (A0),A1
            move.w  ($A,A1),ColLines
            move.w  ($C,A1),RowBits
            move.w  ($4,A1),D0
            move.w  D0,ScreenRow
            move.w  D0,CRSRROW
            move.w  ($1A,A1),ScrVRes
            move.w  ($16,A1),ScrHRes
            move.l  (A1),D0
            add.l   D0,ScrnBase
            move.l  ScrnBase,CRSRBASE
            moveq   #0,D0
            move.b  ($31,A0),D0
            _AttachVBL
            move.l  #VideoMagic,VideoInfoOK
            move.l  A1,($4,A0)
            _SDisposePtr
            moveq   #0,D0
            bra.b   .L2
.L1:
            moveq   #1,D0
.L2:
            move.b  D3,(spId,A0)
            movem.l (SP)+,D3/A1-A2
            rts
OpensDrvr:
            move.l  A2,-(SP)
            suba.w  #$18,SP
            movea.l SP,A2
            move.l  A2,($14,A0)
            suba.l  #$100,SP
            move.l  SP,(A0)
            _SReadDrvrName
            bne.w   .L1
            move.l  (spResult,A0),(seIOFileName,A2)
            move.b  (spSlot,A0),(seSlot,A2)
            move.b  (spID,A0),(sesRsrcId,A2)
            clr.b   (seDevice,A2)
            move.l  (seIOFileName,A2),(ioFileName,A1)
            clr.l   (ioMix,A1)
            clr.w   (ioFlags,A1)
            bset.b  #fMulti,(ioFlags+1,A1)
            move.l  A2,(ioSEBlkPtr,A1)
            clr.b   (ioPermssn,A1)
            exg.l   A0,A1
            _HOpen
            exg.l   A0,A1
.L1:
            lea     ($118,SP),SP
            movea.l (SP)+,A2
            rts
            ds.b    12
OpenVidDeflt:
            movea.l A0,A2
            subq.w  #2,SP
            movea.l SP,A0
            _GetVideoDefault
            move.b  (A0)+,(spSlot,A2)
            move.b  (A0)+,(spID,A2)
            addq.w  #2,SP
            movea.l A2,A0
            clr.b   (spExtDev,A0)
            _SRsrcInfo
            bne.b   .Error
            cmpi.l  #$30001,(spCategory,A0)
            bne.b   .Error
            cmpi.w  #DrSwApple,(spDrvrSW,A0)
            bne.b   .Error
            bsr.w   RdVidParam
            bne.b   .Error
            bsr.w   OpensDrvr
            bne.b   .Error
            bsr.w   InitVidDeflt
.Error:
            rts
            ds.b    14
InitVidDeflt:
            movem.l A1-A0/D2-D1,-(SP)
            clr.l   -(SP)
            move.w  (ioRefNum,A1),-(SP)
            bsr.w   GetDefVidMode
            move.l  D0,-(SP)
            _NewGDevice
            movea.l (SP)+,A0
            move.l  A0,TheGDevice
            move.l  A0,DeviceList
            move.l  A0,MainDevice
            move.l  A0,SrcDevice
            move.l  A0,CrsrDevice
            movea.l (A0),A1
            ori.w   #$B800,(GDFlags,A1)
            jsr    InitDefGamma
            movem.l (SP)+,D1-D2/A0-A1
            rts
            ds.b    4
AddVidDevice:
            movem.l A3-A0/D2-D1,-(SP)
            move.w  (ioRefNum,A1),D1
            move.l  DeviceList,D0
.NextDev:
            movea.l D0,A2
            

