/*---   REXX   ---*/
/*------------------------------------------------------------------*/
/*-   Program to execute Stored Procedure DSNACCOX.                -*/
/*-   The output is used to decide if some utilities (COPY, REORG, -*/
/*-   RUNSTATS) should be executed.                                -*/
/*-                                                                -*/
/*-   For DDNAME SYSIN must a member be specified, which contains  -*/
/*-   the parameters of the SP with their values.                  -*/
/*-   See for an example:                                          -*/
/*-                                                                -*/
/*-            ASNTDBA.STRATEB.PROCINP(XMPACCOX)                   -*/
/*-                                                                -*/
/*-   Copy this member and change the parameter values.            -*/
/*-                                                                -*/
/*-   DDNAMEs ICILST, ICTLST, RSILST, RSTLST, REILST, RELLST and   -*/
/*-   RETLST are gonne be filled with the several LISTDEF lists,   -*/
/*-   which are input for the succeeding utility jobs.             -*/
/*-                                                                -*/
/*------------------------------------------------------------------*/
/*-                                                                -*/
/*-   Programmer: Ben van Straten                                  -*/
/*-   Date      : April 2017                                       -*/
/*-                                                                -*/
/*-   Changes                                                      -*/
/*-  ---------                                                     -*/
/*-   Reason    : Reduce amount of copies                          -*/
/*-   Date      : January 2018                                     -*/
/*-  ----------------------------------------------------------    -*/
/*-   Reason    : Make ready for daily use (esp: Image Copy)       -*/
/*-               When freq='Day' then only COPY listdef created   -*/
/*-               This was requested by the FTM team.              -*/
/*-   Date      : May 2018                                         -*/
/*-  ----------------------------------------------------------    -*/
/*-   Reason    : Stored Procedure DSNACCOX gets modified in V12.  -*/
/*-               Therefore this program needs to be modified to   -*/
/*-               prevent abends calling this SP.                  -*/
/*-   Date      : August 2018                                      -*/
/*-  ----------------------------------------------------------    -*/
/*-   Reason    :-Added the prossibility to include/exclude objects-*/
/*-               from C4..DBA.LISTDEF table.                      -*/
/*-              -PBG tablespaces can now safely (DB2 12) processed-*/
/*-               by partition                                     -*/
/*-              -Minor bug and cosmetic fixes                     -*/
/*-   Date      : Januari 2019                                     -*/
/*-  ----------------------------------------------------------    -*/
/*-   Reason    : Exclude object was missing Partition field       -*/
/*-               OBJTYPE = '"objtype"'" added for correct objtype -*/
/*-   Date      : Januari 2022                                     -*/
/*------------------------------------------------------------------*/
/*-   Reason    : Include/Exclude objects was only executed if     -*/
/*-               row count was > 0, but should always be executed.-*/
/*-   Date      : March 2022                                       -*/
/*------------------------------------------------------------------*/
 
parse upper arg ssid
 
/*----------------------------------------------------- Mainline ---*/
Call Initialize_Program
Call Initialize_Parameters
Call Initialize_Indicators
Call Check_Parameters
Call Connect_to_DB2
Call Execute_SP_DSNACCOX
Call Process_Results
Call Write_LISTDEF
 
return
/*-------------------------------------------------- End program ---*/
 
Initialize_Program:
/*----------------*/
/*   Initialize   */
/*----------------*/
 
say 'Start Initialize_Program'
say copies("-",72)
 
Hostname = mvsvar(sysname)
sqlid = 'C4'substr(ssid,3,2)'DBA'
say 'Hostname is        :' Hostname
say 'ssid is            :' ssid
say 'sqlid is           :' sqlid
 
/* DB2 ssid always has a length of 4 */
if LENGTH(ssid) <> 4
then do
   say 'DB2 ssid must have a length of 4. Is now: ' ssid
   exit 12
end
 
/* Check: Do Hostname and DB2 ssid match? */
select
   when SUBSTR(ssid,3,1) = 'D'
   then do
      if SUBSTR(Hostname,1,3) <> 'DPS'
      then do
         say ssid 'only runs on DPS LPARs!'
         exit 12
      end
   end
   when SUBSTR(ssid,3,1) = 'E'
   then do
      if SUBSTR(Hostname,1,3) <> 'EHV'
      then do
         say ssid 'only runs on EHV LPARs!'
         exit 12
      end
   end
   when SUBSTR(ssid,3,2) = 'FZ'
   then do
      if SUBSTR(Hostname,1,4) <> 'SON5' & SUBSTR(Hostname,1,4) <> 'SON6'
      then do
         say ssid 'only runs on SON5 en SON6 LPARs!'
         exit 12
      end
   end
   when SUBSTR(ssid,3,1) = 'F'
   then do
      if SUBSTR(Hostname,1,3) <> 'FTE'
      then do
         say ssid 'only runs on FTE LPARs!'
         exit 12
      end
   end
   when SUBSTR(ssid,3,1) = 'R'
   then do
      if SUBSTR(Hostname,1,3) <> 'RPS'
      then do
         say ssid 'only runs on RPS LPARs!'
         exit 12
      end
   end
   when SUBSTR(ssid,3,1) = 'S'
   then do
      if SUBSTR(Hostname,1,3) <> 'SON'
      then do
         say ssid 'only runs on SON LPARs!'
         exit 12
      end
   end
   when SUBSTR(ssid,3,1) = 'X'
   then do
      if SUBSTR(Hostname,1,3) <> 'XAT'
      then do
         say ssid 'only runs on XAT LPARs!'
         exit 12
      end
   end
   when SUBSTR(ssid,4,1) = 'Z'
   then do
      if SUBSTR(Hostname,1,3) <> 'SON'
      then do
         say ssid 'only runs on SON LPARs!'
         exit 12
      end
   end
   otherwise
      say 'Programma not suitable for:' ssid
      say 'Report this at: ito.bs.os.zos.db2.dba@rabobank.nl'
      exit 12
end
 
/* Get JOBNAME from TCB */
cvt   = STORAGE(10,4)                      /* FLCCVT-PSA data area*/
tcbp  = STORAGE(d2x(c2d(cvt)),4)           /* CVTTCBP             */
tcb   = STORAGE(d2x(c2d(tcbp)+4),4)
tiot  = STORAGE(d2x(c2d(tcb)+12),4)        /* TCBTIO              */
JOBN  = STRIP(STORAGE(d2x(c2d(tiot)),8))   /* TIOCNJOB            */
say 'Jobname is: ' JOBN
STEPN = STRIP(STORAGE(d2x(c2d(tiot)+8),8)) /* TIOCSTEP            */
say 'Stepname is: ' STEPN
 
/* Position 3 of the jobname decides the frequency of the job */
select
   when SUBSTR(JOBN,3,1) = 'D' then FREQ = 'Day'
   when SUBSTR(JOBN,3,1) = 'W' then FREQ = 'Week'
   when SUBSTR(JOBN,3,1) = 'K' then FREQ = 'Quarter'
   when SUBSTR(JOBN,3,1) = 'J' then FREQ = 'Year'
   when SUBSTR(JOBN,3,1) = 'I' then FREQ = 'Incidental'
   otherwise FREQ = 'Unknown'
end
say 'FREQ is: 'FREQ
 
ici_count = 0
ict_count = 0
rei_count = 0
rel_count = 0
ret_count = 0
rsi_count = 0
rst_count = 0
REORG_yes = 0
COPY_yes  = 0
 
say copies("-",72)
say 'End Initialize_Program'
say copies("-",72)
 
return
/*--------------------------------------- End Initialize_Program ---*/
 
Initialize_Parameters:
/*-----------------------------------------------------------*/
/*   Initialize all parameters with their default value.     */
/*-----------------------------------------------------------*/
 
say 'Start Initialize_Parameters'
say copies("-",72)
 
SpecialParm        = "-1  -1  "
CRUpdatedPagesPct  = 20.0
CRUpdatedPagesAbs  = 0
CRChangesPct       = 10.0
CRDaySncLastCopy   = 7
ICRUpdatedPagesPct = 1.0
ICRUpdatedPagesAbs = 0
ICRChangesPct      = 1.0
CRIndexSize        = 50
RRTInsertsPct      = 25.0
RRTInsertsAbs      = 0
RRTDeletesPct      = 25.0
RRTDeletesAbs      = 0
RRTUnclustInsPct   = 10.0
RRTDisorgLobPct    = 50.0
RRTDataSpaceRat    = -1
RRTMassDelLimit    = 0
RRTIndRefLimit     = 5.0
RRIInsertsPct      = 30.0
RRIInsertsAbs      = 0
RRIDeletesPct      = 30.0
RRIDeletesAbs      = 0
RRIAppendInsertPct = 20.0
RRIPseudoDeletePct = 5.0
RRIMassDelLimit    = 0
RRILeafLimit       = 10.0
RRINumLevelsLimit  = 0
SRTInsDelUpdPct    = 20.0
SRTInsDelUpdAbs    = 0
SRTMassDelLimit    = 0.0
SRIInsDelUpdPct    = 20.0
SRIInsDelUpdAbs    = 0
SRIMassDelLimit    = 0
ExtentLimit        = 254
LastStatement      = " "
ReturnCode         = 0
ErrorMsg           = " "
IfCaRetCode        = 0
IfCaResCode        = 0
XsBytes            = 0
 
say 'End Initialize_Parameters'
say copies("-",72)
 
return
/*----------------------------------- End Initialize_Parameters ---*/
 
Initialize_Indicators:
/*-----------------------------------------------------------*/
/*   Initialize all non-essential input variables to -1      */
/*   to represent input value NULL and to use the default    */
/*   value.                                                  */
/*-----------------------------------------------------------*/
 
say 'Start Initialize_Indicators'
say copies("-",72)
 
QueryTypeInd          = 0
ObjectTypeInd         = 0
ICTypeInd             = 0
CatlgSchemaInd        = 0
LocalSchemaInd        = 0
ChkLvlInd             = 0
CriteriaInd           = -1
SpecialParmInd        = -1
CRUpdatedPagesPctInd  = -1
CRUpdatedPagesAbsInd  = -1
CRChangesPctInd       = -1
CRDaySncLastCopyInd   = -1
ICRUpdatedPagesPctInd = -1
ICRUpdatedPagesAbsInd = -1
ICRChangesPctInd      = -1
CRIndexSizeInd        = -1
RRTInsertsPctInd      = -1
RRTInsertsAbsInd      = -1
RRTDeletesPctInd      = -1
RRTDeletesAbsInd      = -1
RRTUnclustInsPctInd   = -1
RRTDisorgLobPctInd    = -1
RRTDataSpaceRatInd    = -1
RRTMassDelLimitInd    = -1
RRTIndRefLimitInd     = -1
RRIInsertsPctInd      = -1
RRIInsertsAbsInd      = -1
RRIDeletesPctInd      = -1
RRIDeletesAbsInd      = -1
RRIAppendInsertPctInd = -1
RRIPseudoDeletePctInd = -1
RRIMassDelLimitInd    = -1
RRILeafLimitInd       = -1
RRINumLevelsLimitInd  = -1
SRTInsDelUpdPctInd    = -1
SRTInsDelUpdAbsInd    = -1
SRTMassDelLimitInd    = -1
SRIInsDelUpdPctInd    = -1
SRIInsDelUpdAbsInd    = -1
SRIMassDelLimitInd    = -1
ExtentLimitInd        = -1
LastStatementInd      = -1
ReturnCodeInd         = -1
ErrorMsgInd           = -1
IfCaRetCodeInd        = -1
IfCaResCodeInd        = -1
XsBytesInd            = -1
XxBytes               = -1
 
say 'End Initialize_Indicators'
say copies("-",72)
 
return
/*----------------------------------- End Initialize_Indicators ---*/
 
Check_Parameters:
/*--------------------------------------------*/
/*   Check the parameters for valid values.   */
/*--------------------------------------------*/
 
say 'Start Check_Parameters'
say copies("-",72)
 
   /* Open the Parameterfile and read it until the end is reached. */
   "EXECIO * DISKR SYSIN (STEM accoxin."
   do r = 1 to accoxin.0
      select
         when STRIP(SUBSTR(accoxin.r,1,20)) = 'QUERYTYPE'
         then do
            QueryType = STRIP(SUBSTR(accoxin.r,23))
            if Querytype = ""
            then do
               say 'QueryType not defined. Default: ALL'
            end
            else do
               select
                  when QueryType = 'ALL' then nop
                  when QueryType = 'COPY' then nop
                  when QueryType = 'RUNSTATS' then nop
                  when QueryType = 'REORG' then nop
                  when QueryType = 'EXTENTS' then nop
                  when QueryType = 'RESTRICT' then nop
                  otherwise
                     say 'QueryType ' QueryType ' incorrect.'
                     say 'Default ALL is being used.'
                     QueryTypeInd = 0
               end
            end
         end
         when STRIP(SUBSTR(accoxin.r,1,20)) = 'OBJECTTYPE'
         then do
            ObjectType = STRIP(SUBSTR(accoxin.r,23))
            if ObjectType = ""
            then do
               say 'ObjectType not defined. Default: ALL'
            end
            else do
               select
                  when ObjectType = 'ALL' then nop
                  when ObjectType = 'TS' then nop
                  when ObjectType = 'IX' then nop
                  otherwise
                     say 'ObjectType ' ObjectType ' incorrect.'
                     say 'Default ALL is being used.'
                     ObjectTypeInd = -1
               end
            end
         end
         when STRIP(SUBSTR(accoxin.r,1,20)) = 'ICTYPE'
         then do
            ICType = STRIP(SUBSTR(accoxin.r,23))
            if ICType = ""
            then do
               say 'ICType not defined. Default: B'
            end
            else do
               select
                  when ICType = 'F' then nop
                  when ICType = 'I' then nop
                  when ICType = 'B' then nop
               otherwise
                  say 'ICType ' ICType ' incorrect.'
                  say 'Default B is being used.'
                  ICTypeInd = 0
               end
            end
         end
         when STRIP(SUBSTR(accoxin.r,1,20)) = 'CATLGSCHEMA'
         then do
            CatlgSchema = STRIP(SUBSTR(accoxin.r,23))
            if CatlgSchema <> 'SYSIBM'
            then do
               say 'CatlgSchema must be SYSIBM. This is adjusted!'
               CatlgSchema = 'SYSIBM'
            end
            CatlgSchemaInd = 0
         end
         when STRIP(SUBSTR(accoxin.r,1,20)) = 'LOCALSCHEMA'
         then do
            LocalSchema = STRIP(SUBSTR(accoxin.r,23))
            if LocalSchema <> 'DSNACC'
            then do
               say 'LocalSchema must be DSNACC. This is adjusted!'
               LocalSchema = 'DSNACC'
            end
            LocalSchemaInd = 0
         end
         when STRIP(SUBSTR(accoxin.r,1,20)) = 'CHKLVL'
         then do
            ChkLvl = STRIP(SUBSTR(accoxin.r,23))
            if ChkLvl = ""
            then do
               say 'ChkLvl not defined. Default: 5'
            end
            else do
               if DATATYPE(ChkLvl,'N') = 0
               then do
                  say 'ChkLvl must be numeric.'
                  exit 12
               end
               else do
                  if ChkLvl < 0 | ChkLvl > 64
                  then do
                     say 'ChkLvl must be between 0 and 64.'
                     exit 12
                  end
               end
               ChkLvlInd = 0
            end
         end
         when STRIP(SUBSTR(accoxin.r,1,20)) = 'CRITERIA'
         then do
            Criteria = STRIP(SUBSTR(accoxin.r,23))
            if Criteria = ""
            then do
               say 'Criteria must be defined.'
               exit 12
            end
            CriteriaInd = 0
         end
         when STRIP(SUBSTR(accoxin.r,1,20)) = 'SPECIALPARM'
         then do
            /*----------------------------------------------------*/
            /* Acoording to the Manual of DB2 V12 SpecialParm is: */
            /* -------------------------------------------------- */
            /* SpecialParm is an input of type CHAR(160), broken  */
            /* into 4 bytes sections to accomodate new options.   */
            /* An empty 4 bytes of EBCDIC blanks indicates that   */
            /* the default is used for the option. An EBCDIC cha- */
            /* racter string of '-1' indicates that this option   */
            /* is not used.                                       */
            /* -------------------------------------------------- */
            /* In V12 next parameters have been introduced:       */
            /*    RRIEmptyLimit (byte 1-4); default is 10         */
            /*    RRTHashOvrFlwRatio (byte 5-8): default is 15    */
            /*----------------------------------------------------*/
 
            SpecialParm = '-1  -1'   /* For now no options used */
 
         end
         when STRIP(SUBSTR(accoxin.r,1,20)) = 'CRUPDATEDPAGESPCT'
         then do
            CRUpdatedPagesPct = STRIP(SUBSTR(accoxin.r,23))
            if CRUpdatedPagesPct = ""
            then do
               say 'CRUpdatedPagesPct not defined. Default: 20'
            end
            else do
               if DATATYPE(CRUpdatedPagesPct,'N') = 0
               then do
                  say 'CRUpdatedPagesPct must be numeric.'
                  exit 12
               end
               else do
                  if CRUpdatedPagesPct < 1 | CRUpdatedPagesPct > 99
                     then do
                        say 'CRUpdatedPagesPct must be between 1 and 99.'
                        say 'But is: ' CRUpdatedPagesPct
                        exit 12
                     end
               end
               CRUpdatedPagesPctInd = 0
            end
         end
         when STRIP(SUBSTR(accoxin.r,1,20)) = 'CRUPDATEDPAGESABS'
         then do
            CRUpdatedPagesAbs = STRIP(SUBSTR(accoxin.r,23))
            if CRUpdatedPagesAbs = ""
            then do
               say 'CRUpdatedPagesAbs not defined. Default: 0'
            end
            else do
               if DATATYPE(CRUpdatedPagesAbs,'N') = 0
               then do
                  say 'CRUpdatedPagesAbs must be numeric.'
                  exit 12
               end
               else do
                  CRUpdatedPagesAbsInd = 0
               end
            end
         end
         when STRIP(SUBSTR(accoxin.r,1,20)) = 'CRCHANGESPCT'
         then do
            CRChangesPct = STRIP(SUBSTR(accoxin.r,23))
            if CrChangesPct = ""
            then do
               say 'CRChangesPct not defined. Default: 10'
            end
            else do
               if DATATYPE(CRChangesPct,'N') = 0
               then do
                  say 'CRChangesPct must be numeric.'
                  exit 12
               end
               else do
                  if CrChangesPct < 1 | CrChangesPct > 99
                  then do
                     say 'CRChangesPct must be between 1 and 99.'
                     exit 12
                  end
               end
               CRChangesPctInd = 0
            end
         end
         when STRIP(SUBSTR(accoxin.r,1,20)) = 'CRDAYSNCLASTCOPY'
         then do
            CRDaySncLastCopy = STRIP(SUBSTR(accoxin.r,23))
            if CrDaySncLastCopy = ""
            then do
               say 'CRDaySncLastCopy not defined. Default: 7'
            end
            else do
               if DATATYPE(CRDaySncLastCopy,'N') = 0
               then do
                  say 'CRDaySncLastCopy must be numeric.'
                  exit 12
               end
               CRDaySncLastCopyInd = 0
            end
         end
         when STRIP(SUBSTR(accoxin.r,1,20)) = 'ICRUPDATEDPAGESPCT'
         then do
            ICRUpdatedPagesPct = STRIP(SUBSTR(accoxin.r,23))
            if ICRUpdatedPagesPct = ""
            then do
               say 'ICRUpdatedPagesPct not defined. Default: 1'
            end
            else do
               if DATATYPE(ICRUpdatedPagesPct,'N') = 0
               then do
                  say 'ICRUpdatedPagesPct must be numeric.'
                  exit 12
               end
               else do
                  if ICRUpdatedPagesPct < 1 | ICRUpdatedPagesPct > 99
                  then do
                     say 'ICRUpdatedPagesPct must be between 1 and 99.'
                     exit 12
                  end
               end
               ICRUpdatedPagesPctInd = 0
            end
         end
         when STRIP(SUBSTR(accoxin.r,1,20)) = 'ICRUPDATEDPAGESABS'
         then do
            ICRUpdatedPagesAbs = STRIP(SUBSTR(accoxin.r,23))
            if ICRUpdatedPagesAbs = ""
            then do
               say 'ICRUpdatedPagesAbs not defined. Default: 0'
            end
            else do
               if DATATYPE(ICRUpdatedPagesAbs,'N') = 0
               then do
                  say 'ICRUpdatedPagesAbs must be numeric.'
                  exit 12
               end
               else do
                  ICRUpdatedPagesAbsInd = 0
               end
            end
         end
         when STRIP(SUBSTR(accoxin.r,1,20)) = 'ICRCHANGESPCT'
         then do
            ICRChangesPct = STRIP(SUBSTR(accoxin.r,23))
            if ICrChangesPct = ""
            then do
               say 'ICRChangesPct not defined. Default: 1'
            end
            else do
               if DATATYPE(ICRChangesPct,'N') = 0
               then do
                  say 'ICRChangesPct must be numeric.'
                  exit 12
               end
               else do
                  if ICRChangesPct < 1 | ICRChangesPct > 99
                  then do
                     say 'ICRChangesPct must be between 1 and 99.'
                     exit 12
                  end
               end
               ICRChangesPctInd = 0
            end
         end
         when STRIP(SUBSTR(accoxin.r,1,20)) = 'CRINDEXSIZE'
         then do
            CRIndexSize = STRIP(SUBSTR(accoxin.r,23))
            if CrIndexSize = ""
            then do
               say 'CRIndexSize not defined. Default: 50'
            end
            else do
               if DATATYPE(CRIndexSize,'N') = 0
               then do
                  say 'CRIndexSize must be numeric.'
                  exit 12
               end
               if CRIndexSize < 0
               then do
                  say 'CRIndexSize cannot be negative.'
                  exit 12
               end
               else do
                  CRIndexSizeInd = 0
               end
            end
         end
         when STRIP(SUBSTR(accoxin.r,1,20)) = 'RRTINSERTSPCT'
         then do
            RRTInsertsPct = STRIP(SUBSTR(accoxin.r,23))
            if RRTInsertsPct = ""
            then do
               say 'RRTInsertsPct not defined. Default: 25'
            end
            else do
               if DATATYPE(RRTInsertsPct,'N') = 0
               then do
                  say 'RRTInsertsPct must be numeric.'
                  exit 12
               end
               if RRTInsertsPct < 0
               then do
                  say 'RRTInsertsPct cannot be negative.'
                  exit 12
               end
               else do
                  RRTInsertsPctInd = 0
               end
            end
         end
         when STRIP(SUBSTR(accoxin.r,1,20)) = 'RRTINSERTSABS'
         then do
            RRTInsertsAbs = STRIP(SUBSTR(accoxin.r,23))
            if RRTInsertsAbs = ""
            then do
               say 'RRTInsertsAbs not defined. Default: 0'
            end
            else do
               if DATATYPE(RRTInsertsAbs,'N') = 0
               then do
                  say 'RRTInsertsAbs must be numeric.'
                  exit 12
               end
               RRTInsertsAbsInd = 0
            end
         end
         when STRIP(SUBSTR(accoxin.r,1,20)) = 'RRTDELETESPCT'
         then do
            RRTDeletesPct = STRIP(SUBSTR(accoxin.r,23))
            if RRTDeletesPct = ""
            then do
               say 'RRTDeletesPct not defined. Default: 25'
            end
            else do
               if DATATYPE(RRTDeletesPct,'N') = 0
               then do
                  say 'RRTDeletesPct must be numeric.'
                  exit 12
               end
               if RRTDeletesPct < 0
               then do
                  say 'RRTDeletesPct cannot be negative.'
                  exit 12
               end
               else do
                  RRTDeletesPctInd = 0
               end
            end
         end
         when STRIP(SUBSTR(accoxin.r,1,20)) = 'RRTDELETESABS'
         then do
            RRTDeletesAbs = STRIP(SUBSTR(accoxin.r,23))
            if RRTDeletesAbs = ""
            then do
               say 'RRTDeletesAbs not defined. Default: 0'
            end
            else do
               if DATATYPE(RRTDeletesAbs,'N') = 0
               then do
                  say 'RRTDeletesAbs must be numeric.'
                  exit 12
               end
               RRTDeletesAbsInd = 0
            end
         end
         when STRIP(SUBSTR(accoxin.r,1,20)) = 'RRTUNCLUSTINSPCT'
         then do
            RRTUnclustInsPct = STRIP(SUBSTR(accoxin.r,23))
            if RRTUnclustInsPct = ""
            then do
               say 'RRTUnclustInsPct not defined. Default: 10'
            end
            else do
               if DATATYPE(RRTUnclustInsPct,'N') = 0
               then do
                  say 'RRTUnclustInsPct must be numeric.'
                  exit 12
               end
               if RRTUnclustInsPct < 0
               then do
                  say 'RRTUnclustInsPct cannot be negative.'
                  exit 12
               end
               else do
                  RRTUnclustInsPctInd = 0
               end
            end
         end
         when STRIP(SUBSTR(accoxin.r,1,20)) = 'RRTDISORGLOBPCT'
         then do
            RRTDisorgLOBPct = STRIP(SUBSTR(accoxin.r,23))
            if RRTDisorgLOBPct = ""
            then do
               say 'RRTDisorgLOBPct not defined. Default: 10'
            end
            else do
               if DATATYPE(RRTDisorgLOBPct,'N') = 0
               then do
                  say 'RRTDisorgLOBPct must be numeric.'
                  exit 12
               end
               if RRTDisorgLOBPct < 0
               then do
                  say 'RRTDisorgLOBPct cannot be negative.'
                  exit 12
               end
               else do
                  RRTDisorgLOBPctInd = 0
               end
            end
         end
         when STRIP(SUBSTR(accoxin.r,1,20)) = 'RRTDATASPACERAT'
         then do
            RRTDataSpaceRat = STRIP(SUBSTR(accoxin.r,23))
            if RRTDataSpaceRat = ""
            then do
               say 'RRTDataSpaceRat not defined. Default: -1'
            end
            else do
               if DATATYPE(RRTDataSpaceRat,'N') = 0
               then do
                  say 'RRTDataSpaceRat must be numeric.'
                  exit 12
               end
               else do
                  RRTDataSpaceRatInd = 0
               end
            end
         end
         when STRIP(SUBSTR(accoxin.r,1,20)) = 'RRTMASSDELLIMIT'
         then do
            RRTMassDelLimit = STRIP(SUBSTR(accoxin.r,23))
            if RRTMassDelLimit = ""
            then do
               say 'RRTMassDelLimit not defined. Default: 0'
            end
            else do
               if DATATYPE(RRTMassDelLimit,'N') = 0
               then do
                  say 'RRTMassDelLimit must be numeric.'
                  exit 12
               end
               if RRTMassDelLimit < 0
               then do
                  say 'RRTMassDelLimit cannot be negative.'
                  exit 12
               end
               else do
                  RRTMassDelLimitInd = 0
               end
            end
         end
         when STRIP(SUBSTR(accoxin.r,1,20)) = 'RRTINDREFLIMIT'
         then do
            RRTIndRefLimit = STRIP(SUBSTR(accoxin.r,23))
            if RRTIndRefLimit = ""
            then do
               say 'RRTIndRefLimit not defined. Default: 10'
            end
            else do
               if DATATYPE(RRTIndRefLimit,'N') = 0
               then do
                  say 'RRTIndRefLimit must be numeric.'
                  exit 12
               end
               if RRTIndRefLimit < 0
               then do
                  say 'RRTIndRefLimit cannot be negative.'
                  exit 12
               end
               else do
                  RRTIndRefLimitInd = 0
               end
            end
         end
         when STRIP(SUBSTR(accoxin.r,1,20)) = 'RRIINSERTSPCT'
         then do
            RRIInsertsPct = STRIP(SUBSTR(accoxin.r,23))
            if RRIInsertsPct = ""
            then do
               say 'RRIInsertsPct not defined. Default: 30'
            end
            else do
               if DATATYPE(RRIInsertsPct,'N') = 0
               then do
                  say 'RRIInsertsPct must be numeric.'
                  exit 12
               end
               if RRIInsertsPct < 0
               then do
                  say 'RRIInsertsPct cannot be negative.'
                  exit 12
               end
               else do
                  RRIInsertsPctInd = 0
               end
            end
         end
         when STRIP(SUBSTR(accoxin.r,1,20)) = 'RRIINSERTSABS'
         then do
            RRIInsertsAbs = STRIP(SUBSTR(accoxin.r,23))
            if RRIInsertsAbs = ""
            then do
               say 'RRIInsertsAbs not defined. Default: 0'
            end
            else do
               if DATATYPE(RRIInsertsAbs,'N') = 0
               then do
                  say 'RRIInsertsAbs must be numeric.'
                  exit 12
               end
               if RRIInsertsAbs < 0
               then do
                  say 'RRIInsertsAbs cannot be negative.'
                  exit 12
               end
               else do
                  RRIInsertsAbsInd = 0
               end
            end
         end
         when STRIP(SUBSTR(accoxin.r,1,20)) = 'RRIDELETESPCT'
         then do
            RRIDeletesPct = STRIP(SUBSTR(accoxin.r,23))
            if RRIDeletesPct = ""
            then do
               say 'RRIDeletesPct not defined. Default: 30'
            end
            else do
               if DATATYPE(RRIDeletesPct,'N') = 0
               then do
                  say 'RRIDeletesPct must be numeric.'
                  exit 12
               end
               if RRIDeletesPct < 0
               then do
                  say 'RRIDeletesPct cannot be negative.'
                  exit 12
               end
               else do
                  RRIDeletesPctInd = 0
               end
            end
         end
         when STRIP(SUBSTR(accoxin.r,1,20)) = 'RRIDELETESABS'
         then do
            RRIDeletesAbs = STRIP(SUBSTR(accoxin.r,23))
            if RRIDeletesAbs = ""
            then do
               say 'RRIDeletesAbs not defined. Default: 0'
            end
            else do
               if DATATYPE(RRIDeletesAbs,'N') = 0
               then do
                  say 'RRIDeletesAbs must be numeric.'
                  exit 12
               end
               if RRIDeletesAbs < 0
               then do
                  say 'RRIDeletesAbs cannot be negative.'
                  exit 12
               end
               else do
                  RRIDeletesAbsInd = 0
               end
            end
         end
         when STRIP(SUBSTR(accoxin.r,1,20)) = 'RRIAPPENDINSERTPCT'
         then do
            RRIAppendInsertPct = STRIP(SUBSTR(accoxin.r,23))
            if RRIAppendInsertPct = ""
            then do
               say 'RRIAppendInsertPct not defined. Default: 10'
            end
            else do
               if DATATYPE(RRIAppendInsertPct,'N') = 0
               then do
                  say 'RRIAppendInsertPct must be numeric.'
                  exit 12
               end
               if RRIAppendInsertPct < 0
               then do
                  say 'RRIAppendInsertPct cannot be negative.'
                  exit 12
               end
               else do
                  RRIAppendInsertPctInd = 0
               end
            end
         end
         when STRIP(SUBSTR(accoxin.r,1,20)) = 'RRIPSEUDODELETEPCT'
         then do
            RRIPseudoDeletePct = STRIP(SUBSTR(accoxin.r,23))
            if RRIPseudoDeletePct = ""
            then do
               say 'RRIPseudoDeletePct not defined. Default: 10'
            end
            else do
               if DATATYPE(RRIPseudoDeletePct,'N') = 0
               then do
                  say 'RRIPseudoDeletePct must be numeric.'
                  exit 12
               end
               if RRIPseudoDeletePct < 0
               then do
                  say 'RRIPseudoDeletePct cannot be negative.'
                  exit 12
               end
               else do
                  RRIPseudoDeletePctInd = 0
               end
            end
         end
         when STRIP(SUBSTR(accoxin.r,1,20)) = 'RRIMASSDELLIMIT'
         then do
            RRIMassDelLimit = STRIP(SUBSTR(accoxin.r,23))
            if RRIMassDelLimit = ""
            then do
               say 'RRIMassDelLimit not defined. Default: 0'
            end
            else do
               if DATATYPE(RRIMassDelLimit,'N') = 0
               then do
                  say 'RRIMassDelLimit must be numeric.'
                  exit 12
               end
               if RRIMassDelLimit < 0
               then do
                  say 'RRIMassDelLimit cannot be negative.'
                  exit 12
               end
               else do
                  RRIMassDelLimitInd = 0
               end
            end
         end
         when STRIP(SUBSTR(accoxin.r,1,20)) = 'RRILEAFLIMIT'
         then do
            RRILeafLimit = STRIP(SUBSTR(accoxin.r,23))
            if RRILeafLimit = ""
            then do
               say 'RRILeafLimit not defined. Default: 10'
            end
            else do
               if DATATYPE(RRILeafLimit,'N') = 0
               then do
                  say 'RRILeafLimit must be numeric.'
                  exit 12
               end
               if RRILeafLimit < 0
               then do
                  say 'RRILeafLimit cannot be negative.'
                  exit 12
               end
               else do
                  RRILeafLimitInd = 0
               end
            end
         end
         when STRIP(SUBSTR(accoxin.r,1,20)) = 'RRINUMLEVELSLIMIT'
         then do
            RRINumLevelsLimit = STRIP(SUBSTR(accoxin.r,23))
            if RRINumLevelsLimit = ""
            then do
               say 'RRINumLevelsLimit not defined. Default: 0'
            end
            else do
               if DATATYPE(RRINumLevelsLimit,'N') = 0
               then do
                  say 'RRINumLevelsLimit must be numeric.'
                  exit 12
               end
               if RRINumLevelsLimit < 0
               then do
                  say 'RRINumLevelsLimit cannot be negative.'
                  exit 12
               end
               else do
                  RRINumLevelsLimitInd = 0
               end
            end
         end
         when STRIP(SUBSTR(accoxin.r,1,20)) = 'SRTINSDELUPDPCT'
         then do
            SRTInsDelUpdPct = STRIP(SUBSTR(accoxin.r,23))
            if SRTInsDelUpdPct = ""
            then do
               say 'SRTInsDelUpdPct not defined. Default: 20'
            end
            else do
               if DATATYPE(SRTInsDelUpdPct,'N') = 0
               then do
                  say 'SRTInsDelUpdPct must be numeric.'
                  exit 12
               end
               if SRTInsDelUpdPct < 0
               then do
                  say 'SRTInsDelUpdPct cannot be negative.'
                  exit 12
               end
               else do
                  SRTInsDelUpdPctInd = 0
               end
            end
         end
         when STRIP(SUBSTR(accoxin.r,1,20)) = 'SRTINSDELUPDABS'
         then do
            SRTInsDelUpdAbs = STRIP(SUBSTR(accoxin.r,23))
            if SRTInsDelUpdAbs = ""
            then do
               say 'SRTInsDelUpdAbs not defined. Default: 0'
            end
            else do
               if DATATYPE(SRTInsDelUpdAbs,'N') = 0
               then do
                  say 'SRTInsDelUpdAbs must be numeric.'
                  exit 12
               end
               if SRTInsDelUpdAbs < 0
               then do
                  say 'SRTInsDelUpdAbs cannot be negative.'
                  exit 12
               end
               else do
                  SRTInsDelUpdAbsInd = 0
               end
            end
         end
         when STRIP(SUBSTR(accoxin.r,1,20)) = 'SRTMASSDELLIMIT'
         then do
            SRTMassDelLimit = STRIP(SUBSTR(accoxin.r,23))
            if SRTMassDelLimit = ""
            then do
               say 'SRTMassDelLimit not defined. Default: 0'
            end
            else do
               if DATATYPE(SRTMassDelLimit,'N') = 0
               then do
                  say 'SRTMassDelLimit must be numeric.'
                  exit 12
               end
               if SRTMassDelLimit < 0
               then do
                  say 'SRTMassDelLimit cannot be negative.'
                  exit 12
               end
               else do
                  SRTMassDelLimitInd = 0
               end
            end
         end
         when STRIP(SUBSTR(accoxin.r,1,20)) = 'SRIINSDELUPDPCT'
         then do
            SRIInsDelUpdPct = STRIP(SUBSTR(accoxin.r,23))
            if SRIInsDelUpdPct = ""
            then do
               say 'SRIInsDelUpdPct not defined. Default: 20'
            end
            else do
               if DATATYPE(SRIInsDelUpdPct,'N') = 0
               then do
                  say 'SRIInsDelUpdPct must be numeric.'
                  exit 12
               end
               if SRIInsDelUpdPct < 0
               then do
                  say 'SRIInsDelUpdPct cannot be negative.'
                  exit 12
               end
               else do
                  SRIInsDelUpdPctInd = 0
               end
            end
         end
         when STRIP(SUBSTR(accoxin.r,1,20)) = 'SRIINSDELUPDABS'
         then do
            SRIInsDelUpdAbs = STRIP(SUBSTR(accoxin.r,23))
            if SRIInsDelUpdAbs = ""
            then do
               say 'SRIInsDelUpdAbs not defined. Default: 0'
            end
            else do
               if DATATYPE(SRIInsDelUpdAbs,'N') = 0
               then do
                  say 'SRIInsDelUpdAbs must be numeric.'
                  exit 12
               end
               if SRIInsDelUpdAbs < 0
               then do
                  say 'SRIInsDelUpdAbs cannot be negative.'
                  exit 12
               end
               else do
                  SRIInsDelUpdAbsInd = 0
               end
            end
         end
         when STRIP(SUBSTR(accoxin.r,1,20)) = 'SRIMASSDELLIMIT'
         then do
            SRIMassDelLimit = STRIP(SUBSTR(accoxin.r,23))
            if SRIMassDelLimit = ""
            then do
               say 'SRIMassDelLimit not defined. Default: 0'
            end
            else do
               if DATATYPE(SRIMassDelLimit,'N') = 0
               then do
                  say 'SRIMassDelLimit must be numeric.'
                  exit 12
               end
               if SRIMassDelLimit < 0
               then do
                  say 'SRIMassDelLimit cannot be negative.'
                  exit 12
               end
               else do
                  SRIMassDelLimitInd = 0
               end
            end
         end
         when STRIP(SUBSTR(accoxin.r,1,20)) = 'EXTENTLIMIT'
         then do
            ExtentLimit = STRIP(SUBSTR(accoxin.r,23))
            if ExtentLimit = ""
            then do
               say 'ExtentLimit not defined. Default: 50'
            end
            else do
               if DATATYPE(ExtentLimit,'N') = 0
               then do
                  say 'ExtentLimit must be numeric.'
                  exit 12
               end
               if ExtentLimit < 0
               then do
                  say 'ExtentLimit cannot be negative.'
                  exit 12
               end
               else do
                  ExtentLimitInd = 0
               end
            end
         end
         otherwise do
            say 'Unknown parameter!'
            say accoxin.r
            exit 12
         end
      end
   end
 
say 'End Check_Parameters'
say copies("-",72)
 
return
/*----------------------------------------- End Check_Parameters ---*/
 
Connect_to_DB2:
/*------------------------------------------------------------------*/
/*- In this routine is the connection to the DB2 subsystem esta-   -*/
/*- blished.If SQLCODE is not 0, then the program stops with an    -*/
/*- RC=8.                                                          -*/
/*------------------------------------------------------------------*/
 
say 'Start Connect_to_DB2'
say copies("-",72)
 
/* ADDRESS TSO 'SUBCOM DSNREXX'
   if rc <>  0
   then s_rc = RXSUBCOM('ADD','DSNREXX','DSNREXX') */
 
   s_rc = RXSUBCOM('ADD','DSNREXX','DSNREXX')
   ADDRESS DSNREXX "CONNECT" ssid
 
   if sqlcode <> 0
   then Call SQLFOUT sqlcode
 
 /* Decide which version and mode of DB2 this is */
   sqlstmt = "EXECSQL CONNECT"
   ADDRESS DSNREXX sqlstmt
 
   if sqlcode <> 0
   then Call SQLFOUT sqlcode
 
   /* SQLERRP has format: 'DSNvv01m'; vv = '11' or '12' and */
   /*                                 m = '0'(CM) or '5'(NFM) */
   say sqlerrp
   version = substr(SQLERRP,4,2)
   if substr(SQLERRP,8,1) = '0'
   then mode = 'CM'
   else mode = 'NFM'
 
say 'DB2 version/mode is: ' version'/'mode
 
say 'End Connect_to_DB2'
say copies("-",72)
 
return
/*------------------------------------------- End Connect_to_DB2 ---*/
 
Execute_SP_DSNACCOX:
/*------------------------------------------------------------------*/
/*- In this routine is Stored Procedure DSNACCOX being executed.   -*/
/*- This SP is delivered with DB2 by IBM and is being used to      -*/
/*- select objects, which can use some housekeeping.               -*/
/*- Only a ReturnCode of 0 is acceptable.                          -*/
/*------------------------------------------------------------------*/
 
say 'Start Execute_SP_DSNACCOX'
say copies('-',72)
 
say "DSNACCOX is being executed with the parameters:"
say "QueryType         :" QueryType ":" QueryTypeInd
say "ObjectType        :" ObjectType ":" ObjectTypeInd
say "ICType            :" ICType ":" ICTypeInd
say "CatlgSchema       :" CatlgSchema ":" CatlgSchemaInd
say "LocalSchema       :" LocalSchema ":" LocalSchemaInd
say "ChkLvl            :" ChkLvl ":" ChkLvlInd
say "Criteria          :" Criteria ":" CriteriaInd
say "SpecialParm       :" SpecialParm ":" SpecialParmInd
say "CRUpdatedPagesPct :" CRUpdatedPagesPct ":" CRUpdatedPagesPctInd
say "CRUpdatedPagesAbs :" CRUpdatedPagesAbs ":" CRUpdatedPagesAbsInd
say "CRChangesPct      :" CRChangesPct ":" CRChangesPctInd
say "CRDaySncLastCopy  :" CRDaySncLastCopy ":" CRDaySncLastCopyInd
say "ICRUpdatedPagesPct:" ICRUpdatedPagesPct ":" ICRUpdatedPagesPctInd
say "ICRUpdatedPagesAbs:" ICRUpdatedPagesAbs ":" ICRUpdatedPagesAbsInd
say "ICRChangesPct     :" ICRChangesPct ":" ICRChangesPctInd
say "CRIndexSize       :" CRIndexSize ":" CRIndexSizeInd
say "RRTInsertsPct     :" RRTInsertsPct ":" RRTInsertsPctInd
say "RRTInsertsAbs     :" RRTInsertsAbs ":" RRTInsertsAbsInd
say "RRTDeletesPct     :" RRTDeletesPct ":" RRTDeletesPctInd
say "RRTDeletesAbs     :" RRTDeletesAbs ":" RRTDeletesAbsInd
say "RRTUnclustInsPct  :" RRTUnclustInsPct ":" RRTUnclustInsPctInd
say "RRTDisOrgLOBPct   :" RRTDisOrgLOBPct ":" RRTDisOrgLOBPctInd
say "RRTDataSpaceRat   :" RRTDataSpaceRat ":" RRTDataSpaceRatInd
say "RRTMassDelLimit   :" RRTMassDelLimit ":" RRTMassDelLimitInd
say "RRTIndRefLimit    :" RRTIndRefLimit ":" RRTIndRefLimitInd
say "RRIInsertsPct     :" RRIInsertsPct ":" RRIInsertsPctInd
say "RRIInsertsAbs     :" RRIInsertsAbs ":" RRIInsertsAbsInd
say "RRIDeletesPct     :" RRIDeletesPct ":" RRIDeletesPctInd
say "RRIDeletesAbs     :" RRIDeletesAbs ":" RRIDeletesAbsInd
say "RRIAppendInsertPct:" RRIAppendInsertPct ":" RRIAppendInsertPctInd
say "RRIPseudoDeletePct:" RRIPseudoDeletePct ":" RRIPseudoDeletePctInd
say "RRIMassDelLimit   :" RRIMassDelLimit ":" RRIMassDelLimitInd
say "RRILeafLimit      :" RRILeafLimit ":" RRILeafLimitInd
say "RRINumLevelsLimit :" RRINumLevelsLimit ":" RRINumLevelsLimitInd
say "SRTInsDelUpdPct   :" SRTInsDelUpdPct ":" SRTInsDelUpdPctInd
say "SRTInsDelUpdAbs   :" SRTInsDelUpdAbs ":" SRTInsDelUpdAbsInd
say "SRTMassDelLimit   :" SRTMassDelLimit ":" SRTMassDelLimitInd
say "SRIInsDelUpdPct   :" SRIInsDelUpdPct ":" SRIInsDelUpdPctInd
say "SRIInsDelUpdAbs   :" SRIInsDelUpdAbs ":" SRIInsDelUpdAbsInd
say "SRIMassDelLimit   :" SRIMassDelLimit ":" SRIMassDelLimitInd
say "ExtentLimit       :" ExtentLimit ":" ExtentLimitInd
say "LastStatement     :" LastStatement ":" LastStatementInd
say "ReturnCode        :" ReturnCode ":" ReturnCodeInd
say "ErrorMsg          :" ErrorMsg ":" ErrorMsgInd
say "IfCARetCode       :" IfCARetCode ":" IfCARetCodeInd
say "IfCAResCode       :" IfCAResCode ":" IfCAResCodeInd
say "XSBytes           :" XSBytes ":" XSBytesInd
 
   sqlstmt = "CALL SYSPROC.DSNACCOX",
                "(:QueryType          :QueryTypeInd, ",
                " :ObjectType         :ObjectTypeInd, ",
                " :ICType             :ICTypeInd, ",
                " :CatlgSchema        :CatlgSchemaInd, ",
                " :LocalSchema        :LocalSchemaInd, ",
                " :ChkLvl             :ChkLvlInd, ",
                " :Criteria           :CriteriaInd, ",
                " :SpecialParm        :SpecialParmInd, ",
                " :CRUpdatedPagesPct  :CRUpdatedPagesPctInd, ",
                " :CRUpdatedPagesAbs  :CRUpdatedPagesAbsInd, ",
                " :CRChangesPct       :CRChangesPctInd, ",
                " :CRDaySncLastCopy   :CRDaySncLastCopyInd, ",
                " :ICRUpdatedPagesPct :ICRUpdatedPagesPctInd, ",
                " :ICRUpdatedPagesAbs :ICRUpdatedPagesAbsInd, ",
                " :ICRChangesPct      :ICRChangesPctInd, ",
                " :CRIndexSize        :CRIndexSizeInd, ",
                " :RRTInsertsPct      :RRTInsertsPctInd, ",
                " :RRTInsertsAbs      :RRTInsertsAbsInd, ",
                " :RRTDeletesPct      :RRTDeletesPctInd, ",
                " :RRTDeletesAbs      :RRTDeletesAbsInd, ",
                " :RRTUnclustInsPct   :RRTUnclustInsPctInd, ",
                " :RRTDisOrgLOBPct    :RRTDisOrgLOBPctInd, ",
                " :RRTDataSpaceRat    :RRTDataSpaceRatInd, ",
                " :RRTMassDelLimit    :RRTMassDelLimitInd, ",
                " :RRTIndRefLimit     :RRTIndRefLimitInd, ",
                " :RRIInsertsPct      :RRIInsertsPctInd, ",
                " :RRIInsertsAbs      :RRIInsertsAbsInd, ",
                " :RRIDeletesPct      :RRIDeletesPctInd, ",
                " :RRIDeletesAbs      :RRIDeletesAbsInd, ",
                " :RRIAppendInsertPct :RRIAppendInsertPctInd, ",
                " :RRIPseudoDeletePct :RRIPseudoDeletePctInd, ",
                " :RRIMassDelLimit    :RRIMassDelLimitInd, ",
                " :RRILeafLimit       :RRILeafLimitInd, ",
                " :RRINumLevelsLimit  :RRINumLevelsLimitInd, ",
                " :SRTInsDelUpdPct    :SRTInsDelUpdPctInd, ",
                " :SRTInsDelUpdAbs    :SRTInsDelUpdAbsInd, ",
                " :SRTMassDelLimit    :SRTMassDelLimitInd, ",
                " :SRIInsDelUpdPct    :SRIInsDelUpdPctInd, ",
                " :SRIInsDelUpdAbs    :SRIInsDelUpdAbsInd, ",
                " :SRIMassDelLimit    :SRIMassDelLimitInd, ",
                " :ExtentLimit        :ExtentLimitInd, ",
                " :LastStatement      :LastStatementInd, ",
                " :ReturnCode         :ReturnCodeInd, ",
                " :ErrorMsg           :ErrorMsgInd, ",
                " :IfCARetCode        :IfCARetCodeInd, ",
                " :IfCAResCode        :IfCAResCodeInd, ",
                " :XSBytes            :XSBytesInd)"
say copies('-',72)
/* say sqlstmt */
/* say copies('-',72) */
 
   ADDRESS DSNREXX "EXECSQL" sqlstmt
   if sqlcode <> 0 & sqlcode <> 466   /* +466 = more rows to fetch */
   then Call SQLFOUT sqlcode
 
   /* Process the ReturnCode of the SP */
   if ReturnCode <> 0
   then do
      Select
         when ReturnCode = 4
            then say 'DSNACCOX completed with incompatible parms.'
         when ReturnCode = 8
            then say 'DSNACCOX terminated with errors.'
         when ReturnCode = 12
            then say 'DSNACCOX terminated with severe errors.'
         when ReturnCode = 14
            then say 'You need to create RTS tables or grant access.'
         when ReturnCode = 16
            then say 'You need to create a TEMP database and tablespaces.'
         otherwise say 'Onbekende ReturnCode is: ' ReturnCode
      end
      say 'Error Message      : 'ErrorMsg
      say 'IFCA Return Code   : 'IFCARetCode
      say 'IFCA Reason Code   : 'IFCAResCode
      say 'Last statement     : 'LastStatement
      exit ReturnCode
   end
   else do
      say 'Error Message      : 'ErrorMsg
      say 'IFCA Return Code   : 'IFCARetCode
      say 'IFCA Reason Code   : 'IFCAResCode
      say 'Last statement     : 'LastStatement
      say 'XSBytes            : 'XSBytes
   end
 
say copies('-',72)
say 'End Execute_SP_DSNACCOX'
say copies('-',72)
 
return
/*-------------------------------------- End Execute_SP_DSNACCOX ---*/
 
Process_Results:
/*-----------------------------------------------------------------*/
/*- In this routine are the 2 resultsets being associateed to the -*/
/*- locators and then these resultsets are being processed with a -*/
/*- cursor.                                                       -*/
/*-----------------------------------------------------------------*/
say 'Start Process_Results'
say copies('-',72)
   /* Associate the locators to the resultsets */
   LOC1 = d2x(0)
   LOC2 = d2x(0)
 
   sqlstmt = "ASSOCIATE LOCATORS(:LOC1, :LOC2)",
             "WITH PROCEDURE SYSPROC.DSNACCOX"
   ADDRESS DSNREXX "EXECSQL" sqlstmt
 
   if sqlcode <> 0
   then Call SQLFOUT sqlcode
   else say 'Locators associated to the result sets'
 
   /* Allocate a cursor to a result set */
   sqlstmt = "ALLOCATE C101 CURSOR FOR RESULT SET :LOC1"
   ADDRESS DSNREXX "EXECSQL" sqlstmt
 
   if sqlcode <> 0
   then Call SQLFOUT sqlcode
   else say 'Cursor C101 allocated to result set LOC1'
 
   /* and process this until all results have been read. */
   do while sqlcode = 0
      sqlstmt = "FETCH C101 INTO :RS_SEQ, :RS_DATA"
      ADDRESS DSNREXX "EXECSQL" sqlstmt
   end
   if sqlcode <> 0 & sqlcode <> 100
   then Call SQLFOUT sqlcode
   else say 'FETCH C101 executed'
 
   /* Allocate a cursor to the 2nd result set */
   sqlstmt = "ALLOCATE C102 CURSOR FOR RESULT SET :LOC2"
   ADDRESS DSNREXX "EXECSQL" sqlstmt
   if sqlcode <> 0 & sqlcode <> 100
   then Call SQLFOUT sqlcode
   else say 'Cursor C102 allocated to result set LOC2'
 
   /* and process this until all results have been read. */
   /* At first check the version and mode level */
 do while sqlcode = 0
  if version = '12' & mode = 'NFM'
  then do
       sqlstmt = "FETCH C102 INTO ",
                 ":DBNAME          :DBNAME_IND ,",
                 ":NAME            :NAME_IND ,",
                 ":PARTITION       :PARTITION_IND ,",
                 ":INSTANCE        :INSTANCE_IND ,",
                 ":CLONE           :CLONE_IND ,",
                 ":OBJECTTYPE      :OBJECTTYPE_IND ,",
                 ":INDEXSPACE      :INDEXSPACE_IND ,",
                 ":CREATOR         :CREATOR_IND ,",
                 ":OBJECTSTATUS    :OBJECTSTATUS_IND ,",
                 ":IMAGECOPY       :IMAGECOPY_IND ,",
                 ":RUNSTATS        :RUNSTATS_IND ,",
                 ":EXTENTS         :EXTENTS_IND ,",
                 ":REORG           :REORG_IND ,",
                 ":INEXCEPTTABLE   :INEXCEPTTABLE_IND ,",
                 ":ASSOCIATEDTS    :ASSOCIATEDTS_IND ,",
                 ":COPYLASTTIME    :COPYLASTTIME_IND ,",
                 ":LOADRLASTTIME   :LOADRLASTTIME_IND ,",
                 ":REBUILDLASTTIME :REBUILDLASTTIME_IND ,",
                 ":CRUPDPGSPCT     :CRUPDPGSPCT_IND ,",
                 ":CRUPDPGSABS     :CRUPDPGSABS_IND ,",
                 ":CRCPYCHGPCT     :CRCPYCHGPCT_IND ,",
                 ":CRDAYSCELSTCPY  :CRDAYSCELSTCPY_IND ,",
                 ":CRINDEXSIZE     :CRINDEXSIZE_IND ,",
                 ":REORGLASTTIME   :REORGLASTTIME_IND ,",
                 ":RRTINSERTSPCT   :RRTINSERTSPCT_IND ,",
                 ":RRTINSERTSABS   :RRTINSERTSABS_IND ,",
                 ":RRTDELETESPCT   :RRTDELETESPCT_IND ,",
                 ":RRTDELETESABS   :RRTDELETESABS_IND ,",
                 ":RRTUNCINSPCT    :RRTUNCINSPCT_IND ,",
                 ":RRTDISORGLOBPCT :RRTDISORGLOBPCT_IND ,",
                 ":RRTDATASPACERAT :RRTDATASPACERAT_IND ,",
                 ":RRTMASSDELETE   :RRTMASSDELETE_IND ,",
                 ":RRTINDREF       :RRTINDREF_IND ,",
                 ":RRIINSERTPCT    :RRIINSERTPCT_IND ,",
                 ":RRIINSERTABS    :RRIINSERTABS_IND ,",
                 ":RRIDELETEPCT    :RRIDELETEPCT_IND ,",
                 ":RRIDELETEABS    :RRIDELETEABS_IND ,",
                 ":RRIAPPINSPCT    :RRIAPPINSPCT_IND ,",
                 ":RRIPSDDELPCT    :RRIPSDDELPCT_IND ,",
                 ":RRIMASSDELETE   :RRIMASSDELETE_IND ,",
                 ":RRILEAF         :RRILEAF_IND ,",
                 ":RRINUMLEVELS    :RRINUMLEVELS_IND ,",
                 ":STATSLASTTIME   :STATSLASTTIME_IND ,",
                 ":SRTINSDELUPDPCT :SRTINSDELUPDPCT_IND ,",
                 ":SRTINSDELUPDABS :SRTINSDELUPDABS_IND ,",
                 ":SRTMASSDELETE   :SRTMASSDELETE_IND ,",
                 ":SRIINSDELPCT    :SRIINSDELPCT_IND ,",
                 ":SRIINSDELABS    :SRIINSDELABS_IND ,",
                 ":SRIMASSDELETE   :SRIMASSDELETE_IND ,",
                 ":TOTALEXTENTS    :TOTALEXTENTS_IND ,",
                 ":RRIEMPTYLIMIT   :RRIEMPTYLIMIT_IND ,",
                 ":RRTHASHOVRFLWRAT:RRTHASHOVRFLWRAT_IND ,",
                 ":RRTPBGSPACEPCT  :RRTPBGSPACEPCT_IND "
  end
  else do
       sqlstmt = "FETCH C102 INTO ",
                 ":DBNAME          :DBNAME_IND ,",
                 ":NAME            :NAME_IND ,",
                 ":PARTITION       :PARTITION_IND ,",
                 ":INSTANCE        :INSTANCE_IND ,",
                 ":CLONE           :CLONE_IND ,",
                 ":OBJECTTYPE      :OBJECTTYPE_IND ,",
                 ":INDEXSPACE      :INDEXSPACE_IND ,",
                 ":CREATOR         :CREATOR_IND ,",
                 ":OBJECTSTATUS    :OBJECTSTATUS_IND ,",
                 ":IMAGECOPY       :IMAGECOPY_IND ,",
                 ":RUNSTATS        :RUNSTATS_IND ,",
                 ":EXTENTS         :EXTENTS_IND ,",
                 ":REORG           :REORG_IND ,",
                 ":INEXCEPTTABLE   :INEXCEPTTABLE_IND ,",
                 ":ASSOCIATEDTS    :ASSOCIATEDTS_IND ,",
                 ":COPYLASTTIME    :COPYLASTTIME_IND ,",
                 ":LOADRLASTTIME   :LOADRLASTTIME_IND ,",
                 ":REBUILDLASTTIME :REBUILDLASTTIME_IND ,",
                 ":CRUPDPGSPCT     :CRUPDPGSPCT_IND ,",
                 ":CRUPDPGSABS     :CRUPDPGSABS_IND ,",
                 ":CRCPYCHGPCT     :CRCPYCHGPCT_IND ,",
                 ":CRDAYSCELSTCPY  :CRDAYSCELSTCPY_IND ,",
                 ":CRINDEXSIZE     :CRINDEXSIZE_IND ,",
                 ":REORGLASTTIME   :REORGLASTTIME_IND ,",
                 ":RRTINSERTSPCT   :RRTINSERTSPCT_IND ,",
                 ":RRTINSERTSABS   :RRTINSERTSABS_IND ,",
                 ":RRTDELETESPCT   :RRTDELETESPCT_IND ,",
                 ":RRTDELETESABS   :RRTDELETESABS_IND ,",
                 ":RRTUNCINSPCT    :RRTUNCINSPCT_IND ,",
                 ":RRTDISORGLOBPCT :RRTDISORGLOBPCT_IND ,",
                 ":RRTDATASPACERAT :RRTDATASPACERAT_IND ,",
                 ":RRTMASSDELETE   :RRTMASSDELETE_IND ,",
                 ":RRTINDREF       :RRTINDREF_IND ,",
                 ":RRIINSERTPCT    :RRIINSERTPCT_IND ,",
                 ":RRIINSERTABS    :RRIINSERTABS_IND ,",
                 ":RRIDELETEPCT    :RRIDELETEPCT_IND ,",
                 ":RRIDELETEABS    :RRIDELETEABS_IND ,",
                 ":RRIAPPINSPCT    :RRIAPPINSPCT_IND ,",
                 ":RRIPSDDELPCT    :RRIPSDDELPCT_IND ,",
                 ":RRIMASSDELETE   :RRIMASSDELETE_IND ,",
                 ":RRILEAF         :RRILEAF_IND ,",
                 ":RRINUMLEVELS    :RRINUMLEVELS_IND ,",
                 ":STATSLASTTIME   :STATSLASTTIME_IND ,",
                 ":SRTINSDELUPDPCT :SRTINSDELUPDPCT_IND ,",
                 ":SRTINSDELUPDABS :SRTINSDELUPDABS_IND ,",
                 ":SRTMASSDELETE   :SRTMASSDELETE_IND ,",
                 ":SRIINSDELPCT    :SRIINSDELPCT_IND ,",
                 ":SRIINSDELABS    :SRIINSDELABS_IND ,",
                 ":SRIMASSDELETE   :SRIMASSDELETE_IND ,",
                 ":TOTALEXTENTS    :TOTALEXTENTS_IND "
  end
 
      ADDRESS DSNREXX "EXECSQL" sqlstmt
 
      if sqlcode = 0
      then do
         COPY_yes = 0
         REORG_yes = 0
         if REORG <> 'NO' & REORG_IND <> -1 then do
         if FREQ <> 'Day'
         then do
            REORG_yes = 1
            COPY_yes  = 1
            if OBJECTTYPE = 'IX' | OBJECTTYPE = 'LX'
            then do
               if rei_count = 0
               then do
                  rei_count = rei_count + 1
                  rei_list.rei_count = 'LISTDEF REORIX'
               end
               rei_count = rei_count + 1
               rei_list.rei_count = 'INCLUDE INDEXSPACE ',
                    strip(DBNAME)'.'strip(INDEXSPACE) 'PARTLEVEL 'PARTITION
            end
            else do
               Call Select_TSType NAME
               if TSTYPE = 'O'     /* LOB */
               then do
                  if rel_count = 0
                  then do
                     rel_count = 1
                     rel_list.rel_count = 'LISTDEF REORLOB'
                  end
                  rel_count = rel_count + 1
                  rel_list.rel_count = 'INCLUDE TABLESPACE ',
                       strip(DBNAME)'.'strip(NAME) 'PARTLEVEL 'PARTITION
               end
               else do
                  if ret_count = 0
                  then do
                     ret_count = 1
                     ret_list.ret_count = 'LISTDEF REORTS'
                  end
                  ret_count = ret_count + 1
                  ret_list.ret_count = 'INCLUDE TABLESPACE ',
                       strip(DBNAME)'.'strip(NAME) 'PARTLEVEL 'PARTITION
               end
            end
            if REORGLASTTIME_IND = -1
            then REORGLASTTIME = "NEVER"
         end
         end
         /* REORG includes COPY */
         if IMAGECOPY <> 'NO' & IMAGECOPY_IND <> -1 then do
         if REORG_yes = 0
         then do
            COPY_yes = 1
            if OBJECTTYPE = 'IX' | OBJECTTYPE = 'LX'
            then do
               if ici_count = 0
               then do
                  ici_count = ici_count + 1
                  ici_list.ici_count = 'LISTDEF COPYIX'
               end
               ici_count = ici_count + 1
               ici_list.ici_count = 'INCLUDE INDEXSPACE ',
                    strip(DBNAME)'.'strip(INDEXSPACE) 'PARTLEVEL 'PARTITION
            end
            else do
               if ict_count = 0
               then do
                  ict_count = ict_count + 1
                  ict_list.ict_count = 'LISTDEF COPYTS'
               end
               ict_count = ict_count + 1
               ict_list.ict_count = 'INCLUDE TABLESPACE ',
                    strip(DBNAME)'.'strip(NAME) 'PARTLEVEL 'PARTITION
            end
            if COPYLASTTIME_IND = -1
            then COPYLASTTIME = "NEVER"
         end
         end
         /* REORG and includes inline RUNSTATS */
 
         if RUNSTATS <> 'NO' & RUNSTATS_IND <> -1 then do
         if REORG_yes = 0 then do
         if COPY_yes = 0 | COPY_yes = 1
         then do
            if OBJECTTYPE = 'IX' | OBJECTTYPE = 'LX'
            then do
               if rsi_count = 0
               then do
                  rsi_count = rsi_count + 1
                  rsi_list.rsi_count = 'LISTDEF RUNSIX'
               end
               rsi_count = rsi_count + 1
               rsi_list.rsi_count = 'INCLUDE INDEXSPACE ',
                    strip(DBNAME)'.'strip(INDEXSPACE) 'PARTLEVEL 'PARTITION
            end
            else do
               if rst_count = 0
               then do
                  rst_count = rst_count + 1
                  rst_list.rst_count = 'LISTDEF RUNSTS'
               end
               rst_count = rst_count + 1
               rst_list.rst_count = 'INCLUDE TABLESPACE ',
                    strip(DBNAME)'.'strip(NAME) 'PARTLEVEL 'PARTITION
            end
            if STATSLASTTIME_IND = -1
            then STATSLASTTIME = "NEVER"
         end
         end
         end
         if EXTENTS <> 'NO' & EXTENTS_IND <> -1
         then do
            say "Extents: "EXTENTS ", "TOTALEXTENTS" extent(s)"
         end
      end
   end
 
   if sqlcode <> 0 & sqlcode <> 100
   then Call SQLFOUT sqlcode
   else say 'FETCH C102 executed'
 
say copies('-',72)
say 'End Process_Results'
say copies('-',72)
 
return
/*------------------------------------------ End Process_Results ---*/
 
Write_LISTDEF:
 
/*----------------------------------------------------------------*/
/*-   Write LISTDEF records to seperate files to be processed    -*/
/*-   by ImageCopy, Runstats and Reorg utilities.                -*/
/*----------------------------------------------------------------*/
 
say 'Start Write_LISTDEF'
say copies('-',72)
 
   /* Make LISTDEF for COPY (IX/LX) */
      Util = "COPY = 'Y'"
      objtype= 'INDEX'
      "EXECIO * DISKW ICILST (STEM ICI_LIST. OPEN "
      "EXECIO * DISKW ICILST (STEM RTS_LIST. FINIS"
say ici_count' records written to ICILST'
 
   /* Make LISTDEF for COPY (TS/LS) */
      rts_rows = 0
      Util = "COPY = 'Y'"
      objtype= 'TABLE'
      Call Select_LISTDEF
      /* If no tables selected by DSNACCOX, but included in   */
      /* LISTDEF table, then also define first line (LISTDEF) */
      if ict_count = 0 & rts_rows > 0
      then do
        ict_count = ict_count + 1
        ict_list.ict_count = "LISTDEF COPYTS"
      end
      "EXECIO * DISKW ICTLST (STEM ict_list. OPEN "
      "EXECIO * DISKW ICTLST (STEM rts_list. FINIS"
      ict_count = ict_count + rts_rows
 say ict_count' records written to ICTLST incl 'rts_rows' records from LISTDEF'
 
   /* Don't process RUNSTATS and REORG daily */
   if freq <> 'Day'
   then do
      /* Make LISTDEF t.b.v. RUNSTATS (IX/LX) */
      Util = "RUNS = 'Y'"
      objtype= 'INDEX'
      "EXECIO * DISKW RSILST (STEM rsi_list. OPEN "
      "EXECIO * DISKW RSILST (STEM rts_list. FINIS"
say rsi_count' records written to RSILST'
 
      /* Make LISTDEF t.b.v. RUNSTATS (TS/LS) */
      rts_rows = 0
      Util = "RUNS = 'Y'"
      objtype= 'TABLE'
      Call Select_LISTDEF
      /* If no tables selected by DSNACCOX, but included in   */
      /* LISTDEF table, then also define first line (LISTDEF) */
      if rst_count = 0 & rts_rows > 0
      then do
        rst_count = rst_count + 1
        rst_list.rst_count = "LISTDEF RUNSTS"
      end
      "EXECIO * DISKW RSTLST (STEM rst_list. OPEN "
      "EXECIO * DISKW RSTLST (STEM rts_list. FINIS"
      rst_count = rst_count + rts_rows
say rst_count' records written to RSTLST incl 'rts_rows' records from LISTDEF'
 
      /* Make LISTDEF t.b.v. REORG (IX/LX) */
      Util = "REOR = 'Y'"
      objtype= 'INDEX'
      "EXECIO * DISKW REILST (STEM rei_list. OPEN "
      "EXECIO * DISKW REILST (STEM rts_list. FINIS"
say rei_count' records written to REILST'
 
      /* Make LISTDEF t.b.v. REORG (LOB) */
      rts_rows = 0
      Util = "REOR = 'Y'"
      objtype= 'TABLE'
      Call Select_LISTDEF
      /* If no tables selected by DSNACCOX, but included in   */
      /* LISTDEF table, then also define first line (LISTDEF) */
      if rel_count = 0 & rts_rows > 0
      then do
        rel_count = rel_count + 1
        rel_list.rel_count = "LISTDEF REORLOB"
      end
      "EXECIO * DISKW RELLST (STEM rel_list. OPEN "
      "EXECIO * DISKW RELLST (STEM rts_list. FINIS"
      rel_count = rel_count + rts_rows
say rel_count' records written to RELLST incl 'rts_rows' records from LISTDEF'
 
      /* Make LISTDEF t.b.v. REORG (TS/LS) */
      rts_rows = 0
      Util = "REOR = 'Y'"
      objtype= 'TABLE'
      Call Select_LISTDEF
      /* If no tables selected by DSNACCOX, but included in   */
      /* LISTDEF table, then also define first line (LISTDEF) */
      if ret_count = 0 & rts_rows > 0
      then do
        ret_count = ret_count + 1
        ret_list.ret_count = "LISTDEF RUNSIX"
      end
      "EXECIO * DISKW RETLST (STEM ret_list. OPEN "
      "EXECIO * DISKW RETLST (STEM rts_list. FINIS"
      ret_count = ret_count + rts_rows
say ret_count' records written to RETLST incl 'rts_rows' records from LISTDEF'
   end
 
say copies('-',72)
say 'End Write_LISTDEF'
say copies('-',72)
 
return
/*-------------------------------------------- End Write_LISTDEF ---*/
 
Select_TSType:
   /*---------------------------------------------------------------*/
   /*- Select tablespace type, because every type has it's own     -*/
   /*- specific process. Following types are being processed:      -*/
   /*-    blank - Tablespace - no LOB and no MEMBER CLUSTER        -*/
   /*-      G   - Partitioned-by-Growth tablespace                 -*/
   /*-      L   - Large tablespace (> 64 GB)                       -*/
   /*-      O   - LOB tablespace                                   -*/
   /*-      P   - Implicit tablespace for XML columns              -*/
   /*-      R   - Partition-by-Range tablespace                    -*/
   /*---------------------------------------------------------------*/
 
   arg TSNAAM
 
   sqlstmt = "SELECT TYPE",
             "  FROM SYSIBM.SYSTABLESPACE",
             " WHERE NAME = '"TSNAAM"'"
   ADDRESS DSNREXX "EXECSQL DECLARE C1 CURSOR FOR S1"
 
   if sqlcode <> 0
   then Call SQLFOUT sqlcode
   ADDRESS DSNREXX "EXECSQL PREPARE S1 FROM :sqlstmt"
 
   if sqlcode <> 0
   then Call SQLFOUT sqlcode
   ADDRESS DSNREXX "EXECSQL OPEN C1"
 
   if sqlcode <> 0
   then Call SQLFOUT sqlcode
   ADDRESS DSNREXX "EXECSQL FETCH C1 INTO :TSTYPE:IND_TSTYPE"
 
   if sqlcode <> 0
   then Call SQLFOUT sqlcode
 
   ADDRESS DSNREXX "EXECSQL CLOSE C1"
   if sqlcode <> 0 & sqlcode <> 100
   then Call SQLFOUT sqlcode
 
return
/*-------------------------------------------- End Select_TSType ---*/
 
 
Select_LISTDEF:
   /*----------------------------------------------------------------*/
   /*    this routine expands the LISTDEF with objects defined in the*/
   /*    LISTDEF table                                               */
   /*----------------------------------------------------------------*/
 
   rts_list. = ''
   sqlstmt1 ="SELECT CAST('INCLUDE "objtype"SPACE  '  ",
             "            ||STRIP(DBNAME)||'.'||STRIP(NAME)||' PARTLEVEL '|| ",
             "            STRIP(CHAR(PARTITION)) AS CHAR(80)) ",
             " FROM "sqlid".LISTDEF   ",
             " WHERE TYPE = 'F' ",
             " AND " Util ,
             "   AND (     FREQ = 'A' OR FREQ IS NULL ",
             "         OR ",
             "            (FREQ = 'M' AND DAY(CURRENT DATE) < '8') ",
             "         OR ",
             "            (    FREQ = 'K' ",
             "             AND MONTH(CURRENT DATE) IN ('3','6','9','12') ",
             "             AND DAY(CURRENT DATE) < '8' ",
             "            ) ",
             "         OR ",
             "            (    FREQ = 'W1' ",
             "             AND DAY(CURRENT DATE) < '8' ",
             "            ) ",
             "         OR ",
             "            (    FREQ = 'W2' ",
             "             AND DAY(CURRENT DATE) BETWEEN  8 AND 15 ",
             "            ) ",
             "         OR ",
             "            (    FREQ = 'W3' ",
             "             AND DAY(CURRENT DATE) BETWEEN 16 AND 23 ",
             "            ) ",
             "         OR ",
             "            (    FREQ = 'W4' ",
             "             AND DAY(CURRENT DATE) > '23' ",
             "            ) ",
             "       ) ",
             " AND " Criteria ,
             " UNION ALL ",
             " SELECT CAST('INCLUDE "objtype"SPACE  '  ",
             " ||STRIP(DBNAME)||'.'||STRIP(NAME)||' PARTLEVEL '||PARTITION ",
             " AS CHAR(80))  " ,
             " FROM "sqlid".LISTDEF   ",
             " WHERE TYPE = 'I' ",
             " AND " Util ,
             " AND " Criteria ,
             " UNION ALL ",
             " SELECT CAST('EXCLUDE "objtype"SPACE  '  ",
             " ||STRIP(DBNAME)||'.'||STRIP(NAME)||' PARTLEVEL '||PARTITION ",
             " AS CHAR(80))  " ,
             " FROM "sqlid".LISTDEF   ",
             " WHERE TYPE = 'E' " ,
             " AND " Util ,
             " AND " Criteria ,
             " ORDER BY 1"
 
  /* say "sqlstmt1:  " sqlstmt1 */
  ADDRESS DSNREXX "EXECSQL DECLARE  C1 CURSOR FOR S1"
  if sqlcode <> 0 then Call SQLFOUT sqlcode
  ADDRESS DSNREXX "EXECSQL PREPARE  S1 FROM :SQLSTMT1"
  if sqlcode = -204 then do
    say 'SQLCODE: ' sqlcode ' probably LISTDEF table not defined'
    return
  end
  if sqlcode <> 0 then Call SQLFOUT sqlcode
  ADDRESS DSNREXX "EXECSQL OPEN C1"
  if sqlcode <> 0 then Call SQLFOUT sqlcode
  do until(sqlcode <> 0)
     ADDRESS DSNREXX "EXECSQL FETCH C1 into :rowtje"
     if sqlcode = 0 then
     do
      rts_rows= rts_rows + 1
      rts_list.rts_rows = rowtje
     end
  end
  ADDRESS DSNREXX "EXECSQL CLOSE C1"
  if sqlcode <> 0 & sqlcode <> 100
  then Call SQLFOUT sqlcode
return
/*-------------------------------------------- End Select_LISTDEF ------*/
 
SQLFOUT:
   /*----------------------------------------------------------------*/
   /*    This is a standard error handling routine for DB2 actions  -*/
   /*    DSNTIAR is the standard IBM routine being used for this.   -*/
   /*----------------------------------------------------------------*/
 
   arg sqlcode
 
   sqlc = d2x(sqlcode,8)
   sqlc = x2c(sqlc)
 
   sqlca = 'SQLCA   '
   sqlca = sqlca || x2c(00000088)
   sqlca = sqlca || sqlc
   sqlca = sqlca || x2c(0000)
   sqlca = sqlca || copies(' ',78)
   sqlca = sqlca || copies(x2c(00),24)
   sqlca = sqlca || copies(' ',16)
 
   dsntiar_msg = x2c(0190)copies(' ',400)
   dsntiar_len = x2c(00000050)
 
   /* Extract Message from Return Area */
   ADDRESS ATTCHPGM 'DSNTIAR SQLCA DSNTIAR_MSG DSNTIAR_LEN'
   say substr(dsntiar_msg,4,400)
   len = c2d(substr(rtrnarea,5,2))
 
   say 'SQCLODE   =' sqlcode
   say 'SQLERRMC  =' sqlerrmc
   say 'SQLWARNS  =' sqlwarn.5
   say 'SQLERRP   =' sqlerrp
   say 'SQLSTATE  =' sqlstate
 
   exit 8     /* End the jobstep with RC=08 */
 
 return
/*-------------------------------------------------- End SQLFOUT ---*/
