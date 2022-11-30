********************************************************************
* Open a file on the CoCoSDC and stream it using 512 bytes sectors
*
* NOTE: In order to stream files using this method the files need to be large
* in order to be recognized.  Small files aren't found and will cause the routine to be stuck in a loop
*
* Filesize limitations:
* Files must be padded so they are in a 512 byte boundary or the routine will be stuck in a loop
* In other words the filesize in HEX must be end with $000,$200,$400,$600,$800,$A00,$C00,$E00
* The smallest size a file can be is 79,360 bytes, in hex that is $13600
* I haven't tested the max filesize but since the CoCoSDC uses 512 bytes sectors and a 24 bit system to keep track of the sectors
* I would guess the max filesize would be 512x256x256x256 = 1,879,048,192 bytes = 1,835,008 kilobytes = 1,835.008 Megabytes = 1.835008 Gigbytes
********************************************************************
controller_latch          EQU     $FF40
stat_or_cmnd_register     EQU     $FF48

param_register_1          EQU     $FF49
param_register_2          EQU     $FF4A
param_register_3          EQU     $FF4B
********************************************************************
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
*
* Open a file for streaming
* Filename must be given with the full path on the SDC card
* The SDC calls the home directory "M:" this library automatically puts "M:" on the beginning of the full file path so you don't need to include it
* X = location in memory for the full filename with a zero terminating the name (use FCN to add the trailing Zero), for example:
*
*  MountFile  FCN     'FILENAMEEXT'         * 8 character filename + 3 character extension must be 11 characters total
*                                           * pad with spaces if the filename is not 8 characters
*
* Example code to use this library:
*
** Get here if an error occurred openning a file
*FileOpenError:
*        JSR     Close_SD_File       * Put Controller back into Emulation Mode
*        LDD     #$FFFF              * Otherwiese hand an error
*        STD     $0400               * Show somtheing on the screen
*        BRA     *                   * Loop forever
*
*  Start:
*        LDX     #MountFile                  * Point X at filename to stream
*        JSR     OpenSDC_File_X_At_Start     * Open a file on the SDC for streaming, 512 bytes at a time
*        BCS     FileOpenError       * If Carry is set then an error occured openning the file go handle it
*
*        LDY     #$FF48              * Memory location to Poll SDC
* Reading three, 512 byte sectors
*        LDA     #3                  * Let's show three 512 byte sectors to the text screen
*LoopAgain:
*        LDX     #$0400              * Start of Text screen
*!       LDU     $FF4A               * Read 2 bytes of data
*        STU     ,X++                * store it on the screen
*        CMPX    #$0600              * are we done?
*        BNE     <
**After reading 512 bytes you must check if the SDC's has had enough time to fully load the buffer again
*PollSDC:
*        LDB     ,Y                  * Poll status, get status Bits 000000xx:
*                                    * Bit 1 set = SDC Buffer has been loaded, Bit 1 clear = SDC Buffer is still being loaded
*                                    * Bit 0 set = Not at End of File yet,     Bit 0 clear = Reached the End of the File
*        ASRB                        * BUSY --> carry
*        BCC     StreamDone          * exit if BUSY cleared
*        BEQ     PollSDC             * continue polling if not READY
*
*        DECA                        * Decrement the sector counter
*        BNE     LoopAgain           * keep reading if we haven't counted down to zero
*
*StreamDone:
*        JSR     Close_SD_File       * Put Controller back into Emulation Mode
*
**Continue your program...
********************************************************************
*
OpenSDC_File_X_At_Start:
        PSHS    A,U                 * Save the registers
        CLRA                        * Set High LSN byte value to zero
        LDU     #$0000              * Set Mid LSN byte value & Low LSN byte Value to zero
        BSR     OpenSDC_File_X_At_AU    * Open a file at Logical Sector Block (24 bit block where A=MSB (bits 23 to 16), U=Least significant Word (bits 15 to 0)
        PULS    A,U,PC              * File is open, restore and return

* Open a file for streaming starting at Logical Sector Number, each sector is 512 bytes.  The LSN is in A & U where
* the Logical Sector Block, 24 bit block where A=MSB (bits 23 to 16), U=Least significant Word (bits 15 to 0)
*
OpenSDC_File_X_At_AU:
        PSHS    D,U                 * Save the registers

* Put controller in Command mode
* This changes the mode the CoCo SDC work in.  It is now ready for direct communication
        LDA     #$43                * control latch value to enable SDC command mode
        STA     controller_latch    * Send the command to the SDC controller_latch=$FF40
        JSR     POLLBUSY            * Wait for the SDC to signify it is not busy - Busy signal is low

* Mount a file
* Mounting a file auto ejects any previous file that was mounted
* If you want to eject a file manually you can do so by using 'M:' by itself for the name
        LDA     #$E0                * Mount Image in drive 0, use $E1 for drive 1
        STA     stat_or_cmnd_register * Send to the command register, stat_or_cmnd_register=$FF48
        JSR     POLLREADY           * Delay 20 microseconds and wait for the SDC to signify the ready signal is on
        LDD     #$4D3A              * D = 'M:'
        STD     $FF4A               * Send two bytes (the home directory on the SD card)
        LDA     #256-2              * Number of bytes left to send in this block, so set the counter to 256-2
        BSR     SendDataBlock       * Write filename to SDC
        JSR     POLLBUSY            * Wait for the SDC to signify it is not busy - Busy signal is low
        LDB     stat_or_cmnd_register *   STATUS REGISTER, stat_or_cmnd_register=$FF48
        BPL     >                   * If File is found then we are good get it ready to be read
        ROLB                        * Otherwise the file doesn't exist or can't be openned for some reason, CC = 1
        BRA     StreamFileDone      * Exit with CC = 1
!

* Our file is now mounted in drive 0 and is ready to use the read command
* Set the LSN (Logical Sector Number) to A,U
        LDA     ,S                  * Get original A (saved on the stack) which is the
        STA     $FF49               * High LSN byte value A=MSB (bits 23 to 16)
        STU     $FF4A               * U = Mid LSN byte value & Low LSN byte Value

        LDA     #$43                * control latch value to enable SDC command mode
        STA     controller_latch    * controller_latch=$FF40
        JSR     POLLBUSY            * Wait for the SDC to signify it is not busy - Busy signal is low

* Send the Read Logical Sector $90 is a 512 byte sector read
* Probably can use $91 for virtual drive 1 if you used $E1 when mounting the file above
        LDA     #$90                * STREAM FROM SDC USING 6809 STYLE TRANSFER (DRIVE 0)
        STA     stat_or_cmnd_register * SEND TO COMMAND REGISTER ($FF48), stat_or_cmnd_register=$FF48
                                    * FILE SECTOR READ READY
                                    * DATA PORT AT $FF4A, 512 BYTE SECTORS
        JSR     POLLREADY           * Delay 20 microseconds and wait for the SDC to signify the ready signal is on
        CLRB                        * Clears the condition Code
StreamFileDone:
        PULS    D,U,PC              * File is open, restore and return

* At this point, you can begin reading the data bytes from the port as 16 bit data at $FF4A & $FF4B.
* The MCU will continue to feed data to the port until EOF is reached or an abort command is issued ($D0).
* The busy bit in status will remain set until that time.
* You will have to poll for the ready bit between 512 byte sectors, as the MCU has to fill a buffer.
* However, using 6809 style transfer, it is able to pretty much keep up with the CPU.
* There is also a small wait you need built into the polling routines in order to give the MCU
* time to reset/set the bit (20 microseconds or so is sufficient).

Close_SD_File:
        LDA     #$D0                * Stop transfer mode
        STA     stat_or_cmnd_register * Send to the command register, stat_or_cmnd_register=$FF48
        JSR     POLLREADY           * Delay 20 microseconds and wait for the SDC to signify the ready signal is on
        CLR     controller_latch    * Put Controller back into Emulation Mode,  controller_latch=$FF40
        RTS                         * Done, Return

************************************************************************
* Wait for the SDC to signify it is not busy - Busy signal is low
* If bit 0 of $FF48 is high then the SDC is busy, loop until it is low
* When bit 0 of $FF48 is low then the SDC is not busy, carry on and return
************************************************************************
POLLBUSY:                           ;   POLLING LOOP HERE - FOR BUSY
        LDA     #%00000001          ;   BUSY STATUS MASK
POLL0:  BITA    stat_or_cmnd_register * STATUS REGISTER, stat_or_cmnd_register=$FF48
        BNE     POLL0               ;   LOOP IF BUSY
        RTS                         ;   RETURN FROM POLLBUSY

************************************************************************
* Delay 20 microseconds and wait for the SDC to signify the ready signal is on
* If bit 1 of $FF48 is low then the SDC is not ready yet, loop until bit 1 is high
* When bit 1 of $FF48 is high then the SDC is in ready state, carry on and return
************************************************************************
POLLREADY:                          ;   POLLING LOOP HERE - FOR READY - INCLUDES...
                                    ;   20+ MICROSECOND WAIT, if CPU is in normal speed (not high speed mode)
        LBRN    $FFFF               ;   5 CYCLES
        LBRN    $FFFF               ;   5 CYCLES
        LBRN    $FFFF               ;   5 CYCLES
        LBRN    $FFFF               ;   5 CYCLES
        LDA     #%00000010          ;   READY STATUS MASK
POLL1:  BITA    stat_or_cmnd_register *   STATUS REGISTER, stat_or_cmnd_register=$FF48
        BEQ     POLL1               ;   LOOP IF NOT READY
        RTS                         ;   RETURN FROM POLLREADY

************************************************************************
* Copy command string to the SDC and Pad the rest of the 256 byte block with zeros
*
* X = pointer to the command string
* A = the counter for the rest of this block,
* Do a CLRA before jumping to this routine if you need to send all 256 bytes
* of the command/filename
* Clobbers B
************************************************************************
SendDataBlock:
!       DECA
        LDB     ,X+
        STB     $FF4A
        BEQ     ClearFF4B
        DECA
        LDB     ,X+
        STB     $FF4B
        BNE     <
* Add Zero padding for the rest of the 256 byte buffer
SendPadding:
!       CLR     $FF4A
        DECA
ClearFF4B:
        CLR     $FF4B
        DECA
        BNE     <
!       RTS
