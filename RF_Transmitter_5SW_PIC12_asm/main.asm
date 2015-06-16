;------------------------------------------------------------------
;	FILE:		main.asm
;	AUTHOR:		gaurav singh
;	COMPANY:	CircuitValley.com
;	DEVICE:		12F615
;	CREATED:	17/04/2015
;	UPDATED:	mm/dd/yyyy
;
;	DESCRIP:	RF transmitter using very basic low cost RF OOK/ASK based modules, 
;				there is only one dependency ,the delay routine which ultimately depends on ins clock ( ins clock is aroung 2Mhz on internal osc)
;------------------------------------------------------------------



#include <p12f615.inc>
		__config _FOSC_INTOSCIO & _WDTE_OFF & _PWRTE_OFF & _MCLRE_OFF & _CP_OFF & _IOSCFS_8MHZ & _BOREN_ON

; System Inputs
#define KEY_LEFT 		GPIO, GP1	; Define which pin switches are connected
#define KEY_CENTER		GPIO, GP2	
#define KEY_RIGHT 		GPIO, GP3	
#define KEY_UP			GPIO, GP4	
#define KEY_DOWN 		GPIO, GP5	

#define KEY_CODE_LEFT		0xA0	; hex code for each individual key press 
#define KEY_CODE_CENTER		0xA1
#define KEY_CODE_RIGHT		0xA2
#define KEY_CODE_UP			0xA3	; in this particular demo the the transmitter sends 4 bytes total
#define KEY_CODE_DOWN		0xA4	; outof which  3 bytes are like fixed header and footer and only 1 byte is actual key code (data)


; System Outputs
#define	RF_OUT 			GPIO, GP0	; Define the transmitter module pin


#define PREAMBLE_LENGTH	0x20 	;32 bit preamble , packet format is strip down version of how TI CC2500 does it , 
								;although i have omitted many this to keep it simple like i don't have length field as i make transmitter and receiver both to be informed about datalenght (it is possible to change datalenght though), and i omitted CRC also. but CRC can be easily added  
								;preamble-->syncpulse(only one long pulse instead many bits)--->startbit-->header-->data-->footer-->stopbit

#define	DEL416us		0xA6	; delay constants
#define DEL500us		0xC8	

; Register Assignments
#define Delay_Count 	0x40		; Define registers for various variables
#define Delay_Count2 	0x41		
#define loopindex		0x42		
#define bitloopindex	0x43

#define DATAPACKET 		0x50		; location to store data packet 
#define DATAPACKET1		0x51		; they need to be consecsutive location as table processing is implemented using indirect addressing
#define DATAPACKET2 	0x52
#define DATAPACKET3 	0x53

#define PACKET_LENGTH	0x04

;------------------------------------------------------------------
;  PROGRAM CODE
;------------------------------------------------------------------	


	org 0 						; Processor Reset vectory
	goto Main					; redirect flow on powerup to Main label

	org 4						; isr vector 
isr: 
	btfss	INTCON,GPIF			; see if gpio interrupt it is there or goback 
    retfie					
	movlw	0xF3				; load data packet with fixed header and footer data goes into DATAPACKET1
	movwf	DATAPACKET
	movlw	0x51
	movwf	DATAPACKET2
	movlw	0x5A
	movwf	DATAPACKET3

	movlw	DEL500us
	call 	delay_x2u5s			;debounce 

	movlw	DEL500us
	call 	delay_x2u5s			;debounce 

	btfsc KEY_LEFT				;test for KEY_LEFT 
	goto $+3					; skip for next if not low(pressed)
	movlw	KEY_CODE_LEFT		;load keycode into DATAPACKET1 for KEY_LEFT
	movwf	DATAPACKET1

	btfsc KEY_RIGHT
	goto $+3
	movlw	KEY_CODE_RIGHT
	movwf	DATAPACKET1

	btfsc KEY_UP
	goto $+3
	movlw	KEY_CODE_UP
	movwf	DATAPACKET1


	btfsc KEY_DOWN
	goto $+3
	movlw	KEY_CODE_DOWN
	movwf	DATAPACKET1


	btfsc KEY_CENTER
	goto $+3
	movlw	KEY_CODE_CENTER
	movwf	DATAPACKET1
	
	btfsc DATAPACKET1,7		;check weather datapacket actually have any data or not(any of the keys was actually pressed) , bit 7 is used as flag, 
	call send_over_rf		; call the acutal routine which will send all the data
	clrf DATAPACKET1		; clear the data packet as on next press we need to test the bit 7 

	movf	GPIO,W			;read gpio register to clearup mismatch condition
	bcf INTCON,GPIF			; clear interrupt flag
	retfie 					; go back from isr

Main:
Init:

	; Initialize port functions and directions
	; disable the comparator to use GPIO pins as I/O
	; Also disable Timer 0, and enable pullups on inputs.
	movlw 	b'00111110'			; Define GP0, GP1 as inputs.
	tris 	GPIO				; Load W into TRIS
	bsf 	STATUS,RP0			;switch to bank1
	clrf    ANSEL				;need no analog
	movlw	0x3F				
	movwf	IOC					;need interrupt on change on all pins

	movlw 	b'00001000'			; Enable wake-up on change, pullups, and
	movwf   OPTION_REG			; set prescalar to WDT to disable tmr0	

	bcf		STATUS,RP0			; switch back to bank 0

	bsf		INTCON,GPIE			; enable gpio interrupt
	bcf		INTCON,GPIF			; clear gpio interrupt flag
	bsf		INTCON,GIE			; enable global interrupt
	bcf		RF_OUT				; Init rf module pin to low
	
MainLoop:
	sleep						; just sleep to save power
	goto MainLoop				; keep looping (got to sleep satement)
 	
;-----------------------------------------------------------
; send_over_rf routine take care of all of the rf activity 
; it send the preamble for PREAMBLE_LENGHTH (defined up the top) ,send number of bytes data 
; it maintain a certain baud rate with simple delays between toggels for whole transaction 
; 
;-----------------------------------------------------------
send_over_rf:
	movlw PREAMBLE_LENGTH	;load how many preamble need to be send
	movwf loopindex			; loop for preamble
preamable
	bsf		RF_OUT			; set rf module pin to high
	movlw	DEL416us		; 166*2.5us = ~416us
	call 	delay_x2u5s		; delay for 416us
	bcf		RF_OUT			; set rf module pin low
	movlw	DEL416us		; 166*2.5us = ~416us
	call 	delay_x2u5s		; delay
	decfsz 	loopindex,f		; see if loop runs out
	goto 	preamable	    ; preamble loop
							; preamble loop finished

	movlw	DEL416us		; delay yet anouter 416us twice for sync bit
	call 	delay_x2u5s
	movlw	DEL416us		
	call 	delay_x2u5s
	movlw	DEL416us	
	call 	delay_x2u5s
							;sync bit finished
	bsf		RF_OUT			;send start bit
	movlw	DEL416us		
	call 	delay_x2u5s
	bcf		RF_OUT
	movlw	DEL416us		
	call 	delay_x2u5s
								
	movlw	DATAPACKET		; start sending data
	movwf	FSR				; using indirect addressing for table processing
	
	movlw	PACKET_LENGTH   ; load package lenght (number of bytes)
	movwf	loopindex		; loop for each byte of data
packetloop					
	movlw	0x8				;load 8(bits) lenght of a byte
	movwf	bitloopindex	;loop for 8 times 
	
bitsloop
	btfss INDF,7			; test for the bit 7(MSb) the indrect addressing data register , 
	goto false				; if goto bit is low
	bsf		RF_OUT			; this is true block so set bit high
	movlw	DEL416us		; delay for the required baud rate
	call 	delay_x2u5s		
	bcf		RF_OUT			; clear the rf module pin
	movlw	DEL416us		
	call 	delay_x2u5s
	goto 	testend			; get of the ture block 
false
	bcf		RF_OUT			; false block so set pin to low 
	movlw	DEL416us			
	call 	delay_x2u5s		
	bsf		RF_OUT
	movlw	DEL416us	
	call 	delay_x2u5s
testend						; bit test if block end here 
	rlf		INDF,f			; shif the bits left 

	decfsz 	bitloopindex,f	;loop till the how byte get transfered 
	goto 	bitsloop
	incf	FSR,f			;one byte finished , point to next byte of data
	decfsz 	loopindex,f		;check if any more byte need to be transmited 
	goto 	packetloop
	
	bsf		RF_OUT			; send last stop bit
	movlw	DEL416us		
	call 	delay_x2u5s
	bcf		RF_OUT
	movlw	DEL416us		
	call 	delay_x2u5s
	return
;------------------------------------------------------------------
;  delay_x2u5s	parameter in wreg , reg>=2
;			
;		Precise delay of (wreg value)*2.5us ,
; the loop has 10cycle minimum  (2 calling, 1 movwf, 1 decf , 1 nop , 1 nop,2 decfsz,2 return )
; so for 2Mhz ins clock delay is 5us minimum  
; minimum parameter in the wreg register is 2 please look at the loop routine for explanation
; each for every count in wreg 5cyle overhead 
;------------------------------------------------------------------
delay_x2u5s:

	movwf	Delay_Count			; +1 
	decf 	Delay_Count,f

	nop
	nop
	decfsz 	Delay_Count, F		; Decrement F, skip if result = 0
	goto 	$-3					; Go back 1, keep decrementing until 0	

	return						; +2 Return program flow




;``````````````````````````````````````````````````````````````````
	end

