SpeedTest  			EQU  1  * 1 = show the border while drawing dots on screen then turn off when done, shows CPU usage

* Include CoCo 3 standard hardware pointers
        INCLUDE ./includes/CoCo3_Start.asm
;        INCLUDE ./includes/CommSDC.asm          * low level code to send and receive command blocks to the SDC

************************************************************************
* Filename format info:
* This can include a full path name to the file
* Filenames must be 8 characters + a 3 character extension (no dot before the extension)
* If the filename is not 8 characters long then it must be padded with spaces
*
* Examples of the filename format:
* Name on the SD card is "TEST.TXT" needs to be accessed with the name 'TEST    TXT'
* Name on the SD card is "CHECK123.BIN" needs to be accessed with the name 'CHECK123BIN'
* Name on the SD card is "HELLO.TXT" in a subfolder called "NEW" needs to be accessed with 'NEW/HELLO   TXT'
*
* Filename must be terminated with a zero.  The FCN command adds the zero when assembling
************************************************************************
* From talking with Ed snider, the files on the SD card don't have to be Disk images they can be any file type but they
* do have to be padded to 512 byte boundary and they need to be 80K or larger

				ORG     $0E00

        INCLUDE ./includes/SDC_Stream_File_Library.asm        * Include SDC Library for openning, streaming & closing big files on the SDC
************************************************************************
MountFile:
        FCN     'HEY12345JNK'       * Filename on SD card to open, FCN puts a zero on the end of the string
************************************************************************

CoCo_START:
***********************************************************
        PSHS    CC,D,DP,X,Y,U       * Backup everything
        ORCC    #$50                * Disable interrupts
; 			CLRA
;				STA			$FF40										* Turn off drive motor
;        STA     High_Speed_Mode       	* High Speed mode enabled

* CoCo Prep
        SETDP   CoCo_START/256      * Set the direct Page for the assembler
        LDA     #CoCo_START/256
        TFR     A,DP
        LDX     #MountFile          * Memory location of Filename, terminated with a zero
        JSR     OpenSDC_File_X_At_Start   * Open a file on the SDC for streaming, 512 bytes at a time
        BCS     FileOpenError       * If Carry is set then an error occured openning the file go handle it

        LDY     #$FF48              * Memory location to Poll SDC
* Reading three, 512 byte sectors
        LDA     #3                 * Let's show three 512 bytes sectors to the text screen
LoopAgain:
        LDX     #$0400              * Start of Text screen
!       LDU     $FF4A               * Read 2 bytes of data
        STU     ,X++                * store it on the screen
        CMPX    #$0600              * are we done?
        BNE     <
* After reading a 512 byte sector we check if we are done and also make sure the SDC's buffer has been fully loaded again
PollSDC:
        LDB     ,Y                  * Poll status, get status Bits 000000xx:
                                    * Bit 1 set = SDC Buffer has been loaded, Bit 1 clear = SDC Buffer is still being loaded
                                    * Bit 0 set = Not at End of File yet,     Bit 0 clear = Reached the End of the File
        ASRB                        * BUSY --> carry
        BCC     StreamDone          * exit if BUSY cleared
        BEQ     PollSDC             * continue polling if not READY

        DECA                        * Decrement the sector counter
        BNE     LoopAgain           * keep reading if we haven't counted down to zero

StreamDone:
        JSR     Close_SD_File       * Put Controller back into Emulation Mode
        PULS    CC,D,DP,X,Y,U,PC    * restore and return

* Get here if an error occurred openning a file
FileOpenError:
        JSR     Close_SD_File       * Put Controller back into Emulation Mode
        LDD     #$FFFF              * Otherwiese hand an error
        STD     $0400               * Show somtheing on the screen
        BRA     *                   * Loop forever
        END   CoCo_START
