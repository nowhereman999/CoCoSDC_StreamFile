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
* Filename must be terminated with a zero.  The FCN opcode adds the zero when assembling
************************************************************************
* Filesize limitations:
* Files must be padded so they are in a 512 byte boundary or the routine will be stuck in a loop
* In other words the filesize in HEX must be end with $000,$200,$400,$600,$800,$A00,$C00,$E00
* The smallest size a file can be is 79,360 bytes, in hex that is $13600
* I haven't tested the max filesize but since the CoCoSDC uses 512 bytes sectors and a 24 bit system to keep track of the sectors
* I would guess the max filesize would be 512x256x256x256 = 1,879,048,192 bytes = 1,835,008 kilobytes = 1,835.008 Megabytes = 1.835008 Gigbytes
********************************************************************

	ORG     $0E00

        INCLUDE ./includes/SDC_Stream_File_Library.asm        * Include SDC Library for openning for streaming & closing big files on the SDC
************************************************************************
MountFile:
        FCN     'HEY12345JNK'       * Filename on SD card to open, FCN puts a zero on the end of the string
************************************************************************

CoCo_START:
***********************************************************
        PSHS    CC,D,DP,X,Y,U       * Backup everything
        ORCC    #$50                * Disable interrupts

* CoCo Prep
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
        BCC     StreamDone          * exit if BUSY cleared (we reached the End of the File)
        BEQ     PollSDC             * continue polling if the Buffer is not completely loaded

        DECA                        * Decrement the sector counter
        BNE     LoopAgain           * keep reading if we haven't counted down to zero

StreamDone:
        JSR     Close_SD_File       * Close file and put the SDC back into Emulation Mode
        PULS    CC,D,DP,X,Y,U,PC    * restore and return

* Get here if an error occurred openning a file, probably a filename error.
FileOpenError:
        JSR     Close_SD_File       * Put Controller back into Emulation Mode
        LDD     #$FFFF              * Otherwiese hand an error
        STD     $0400               * Show somtheing on the screen
        BRA     *                   * Loop forever
        END   CoCo_START
