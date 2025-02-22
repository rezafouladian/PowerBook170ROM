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
            dc.w    $400

