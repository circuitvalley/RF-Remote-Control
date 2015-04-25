;------------------------------------------------------------------
;	FILE:		main.asm
;	AUTHOR:		Gaurav Singh
;	COMPANY:	CircuitValley.com
;	DEVICE:		12F675
;	CREATED:	17/04/2015
;	UPDATED:	mm/dd/yyyy
;
;	DESCRIP:	RF receiver routine using very basic low cost RF OOK/ASK based modules, 
;				there are only two dependency first the delay routine which ultimately depends on ins clock ( ins clock is aroung 1Mhz on internal osc)
;				and second dependency is a hardware timer which is used for measuring time between pulses		

;------------------------------------------------------------------



#include <p12f675.inc>
		__config _FOSC_INTRCIO & _WDTE_OFF & _PWRTE_OFF & _MCLRE_OFF & _CP_OFF & _BOREN_ON	
		;configuration internal oscillator with IO, wdt is off,no power up timer,mclr off,no code protect , brown out enabled (just in case)

; System Outputs
#define RELAY1 			GPIO, GP0	; Define Relay outputs
#define RELAY2			GPIO, GP1	
#define RELAY3 			GPIO, GP2	
#define RELAY4			GPIO, GP4	
#define STATUS_LED 		GPIO, GP5	; Define Status LED (just blinks after preamble reception)
#define	GPIO_BIT_RL1		0x01
#define	GPIO_BIT_RL2		0x02
#define	GPIO_BIT_RL3		0x04
#define	GPIO_BIT_RL4		0x10

#define PACKET_HEADER		0xF3
#define KEY_CODE_RL1		0xA0	; hex code for each individual key press in the transmitter 
#define KEY_CODE_RL2		0xA1	; need to be match the transmission codes .
#define KEY_CODE_RL3		0xA2	; in this particular demo the the transmitter sends 4 bytes total
#define KEY_CODE_RL4		0xA3	; outof which  3 bytes are like fixed header and footer and only 1 byte is actual key code (data)

; System inputs
#define	RF_IN 			GPIO, GP3	; pin where the RF module is connected to the micrcontroller


#define PREAMBLE_LENGTH	0x20 		;32 bit preamble , packet format is strip down version of how TI CC2500 does it , 
									;although i have omitted many this to keep it simple like i don't have length field as i make transmitter and receiver both to be informed about datalenght (it is possible to change datalenght though), and i omitted CRC also. but CRC can be easily added  
									;preamble-->syncpulse(only one long pulse instead many bits)--->startbit-->header-->data-->footer-->stopbit

#define	DEL416us		0x53		;delay count to achieve 416 us delay ,you load this value in wreg and just call the delay routine, delay routine which we have implemented gives us delay in step of 5us each so 416 goes 416/5 -->83=0x53
#define DEL624us		0x7C		;delay count to achieve 624 us delay

#define count396h		0x01		; as timer is used to count time between pulses these values are compraed with timer value to know if pulse arrive at correct time
#define count396l		0x70		; and the timer we use runs on system clock which is (INTOSC)~4Mhz/4 -->1Mhz--->1us each count 
									; but he issue is the PIC12F675 data sheet say the INTOSC is calibrated to  1% .
									; but the device i have gives around 4.4Mhz on INTOSC which means 1.1Mhz into timer
									; so these values are adjusted to the 1.1Mhz clock input
#define count432l		0xE5		; if the clock was absolute 1Mhz then count for 396us would have been same 396us
#define	count432h		0x01		; as we are using 16bit timer so values are dived into LSByte and HSByte

#define count1500l		0xdc
#define count1500h		0x05

#define count1850l		0x10	
#define count1850h		0x08

; Register Assignments 
#define Delay_Count 		0x40		; used internally by the delay routines
#define loopindex			0x42		; used various places for looping 
#define bitloopindex		0x43		; used by loop counting bit inside packet loop

#define temptimerl			0x45		; as the name say hold timer value during compare process as timer is 16 bit so two separate High and low bytes
#define temptimerh			0x46
#define received_preamble 	0x47		; used to count how may total valid preamble pulses have been received
#define DATAPACKET 			0x50		;received data put to these locations , first byte (header in our case)
#define DATAPACKET1			0x51		; second byte of received data (acutal key code byte) 
#define DATAPACKET2 		0x52		; third byte (footer1)
#define DATAPACKET3 		0x53		; forth byte (footer2) 		
										;if you are changing packetlengh in next line add more data packet addresses here

#define PACKET_LENGTH		0x04		; define how may byte of toal reception you are going to do need to be same on both receiver and transmitter , can be

;------------------------------------------------------------------
;  PROGRAM CODE
;------------------------------------------------------------------	

	org 0 						; Processor Reset vector
								; but this goto Main is for portability
	goto Main					; redirect flow on powerup to Main label
Main:
Init:
	; Initialize port functions and directions
	;  disable the comparator to use GPIO pins as I/O
	movlw	0x07				; load 0x07 to wreg
	movwf	CMCON				; disable the timer by writing 0x07 to CMCON
	bsf 	STATUS,RP0			; switch to bank 1
	clrf    ANSEL				; set all pins digital
	movlw 	b'00001000'			; Define only GP3 as inputs rest output.
	movwf 	TRISIO				; Load W into TRIS
	bcf		STATUS,RP0			; switch back to bank 0

	clrf	GPIO				; clear the gpio pins in the start
								; if wanted to retain the gpio state during power cycles then 
								; replace this line with block of code to read data from eeprom and write to gpio reg

	
MainLoop:



	call 	receive_over_rf		; call the acutal rf packet decoder routine , routine returns 0 on success and 1 on failure
	andlw	0x01				; and 0x01 to wreg to check if routine call returns failure in data reception
	btfss	STATUS,Z			; skip next instruction if wreg  is zero which means rf routine return with valid data
	goto 	key_decode_finish			; if failed 

	movf	DATAPACKET,w		;load the datapacket to wreg to check if we received valid header 
	sublw	PACKET_HEADER		;check PACKET_HEADER-DATAPACKET (header of the packet)
	btfss	STATUS,Z			; if ==0 then we have valid header received 
	goto 	key_decode_finish	;if invalid header 
	;we are not checking for valid footer but if you like to check then validate DATAPACKET2 DATAPACKET3 here

key_decode:
	movf 	DATAPACKET1,w			; move DATAPACKET1 content to wreg which actually is received key_code
	sublw	KEY_CODE_RL1 			; KEY_CODE_RL1-DATAPACKET1
	btfss	STATUS,Z				; check if ==0 (KEY_CODE_RL1==DATAPACKET1)
	goto 	next_key1				; if != check for next key code
	movlw	GPIO_BIT_RL1			; load wreg which gpio line to be toggled					
	xorwf	GPIO,F					; xor gpio value with wreg will flip the correct bit
	goto 	key_decode_finish		; we finished the processing command go clearup for next call

next_key1
	movf 	DATAPACKET1,w			;see description above 
	sublw	KEY_CODE_RL2 
	btfss	STATUS,Z
	goto 	next_key2
	movlw	GPIO_BIT_RL2
	xorwf	GPIO,F
	goto 	key_decode_finish


next_key2
	movf 	DATAPACKET1,w
	sublw	KEY_CODE_RL3 
	btfss	STATUS,Z
	goto 	next_key3
	movlw	GPIO_BIT_RL3
	xorwf	GPIO,F
	goto 	key_decode_finish

next_key3
	movf 	DATAPACKET1,w
	sublw	KEY_CODE_RL4 
	btfss	STATUS,Z
	goto 	key_decode_finish
	movlw	GPIO_BIT_RL4
	xorwf	GPIO,F


key_decode_finish
	clrf	DATAPACKET				;clear up the received data file register (not verymuch required)
	clrf 	DATAPACKET1			
		
	goto MainLoop					; go back to main loop


; receiver_over_rf is the actual routine which monitor RF_IN input pin , measure the time between pulses using timer1 which increment ~1us 
; dependebcies are , RF_IN must be initialized as input ,TMR1 should be initialized (default value works for our purpose)
;packet format is strip down version of how TI CC2500 does it , 
;although i have omitted many this to keep it simple like i don't have length field as i make transmitter and receiver both to be informed about datalenght (it is possible to change datalenght though), and i omitted CRC also. but CRC can be easily added  
;preamble-->syncpulse(only one long pulse insted many bits)--->startbit-->header-->data-->footer-->stopbit

receive_over_rf:				
	movlw PREAMBLE_LENGTH			; load the preamble length in to wreg
	movwf loopindex					; move preamble length into loopindex file register which will be used to make
	clrf received_preamble
preamble_wait		
	bcf		PIR1,TMR1IF				; clear timer1 interrupt in case of overrun
	clrf 	TMR1L					; clear up TMR1L 
	clrf 	TMR1H					; clear up TMR1H

	btfsc	RF_IN					;wait till rf input pin is high (it will happen very quickly even if no transmission is there in the air due to very noisy output of the receiver module"
	goto $-1						; go to previous instruction if it is still high
	bsf		T1CON,TMR1ON			; start the timer 

	btfss	RF_IN					;wait till rf input pin low it's state (it will happen very quickly even if no transmission is there in the air due to very noisy output of the receiver module"
	goto $-1						; goto previous instruction if it is still low
	bcf		T1CON,TMR1ON			; it just got high stop the timer 

	btfsc	PIR1,TMR1IF				; if timer overrun happen then data is not going to be valid and we know that the pulse time just too long to fall in our timing requirements
	goto   	next_preamble_wait		; if overrun happen there is no point of continuing further just loop for next pulse 


;	checking timer < count

	movf	TMR1L,W					; move timer result LSbyte to wreg
	movwf	temptimerl				; move wreg(timer LSbyte) to temptimerl
	movf	TMR1H,W					; move timer result HSbyte to wreg
	movwf	temptimerh				; move wreg(timer HSbyte) to temptimerh

	movf	temptimerl,w			;(16bit compare through substraction) 
	sublw	count432l				; perform count432l - w(temtimerl)
	movf	temptimerh,w			; load the temptimerh to wreg 
	btfss	STATUS,C				; check if last subtration result was negative 
	addlw 0x01						; if it was negative increment temptimerh
	sublw	count432h				;count432h-temptimerh(+1 maybe) (result negative if timer>target)
	btfss	STATUS,C				;skip the next instruction if result was positive 
	goto	next_preamble_wait		;will go false to if timer>count


;	checking timer > count

	movf	temptimerl,w			; 16 bit comprare but goes false if timer <count
	sublw	count396l				; descryption is same as above 
	movf	temptimerh,w
	btfss	STATUS,C
	addlw 0x01
	sublw	count396h				;count-timer(+1) (result negative if timer<target)
	btfsc	STATUS,C				;count-timer 
	goto next_preamble_wait			;will go false to if timer<count

timeokey							; the pulse falls within time duration 
	incf	received_preamble,f		; increase number of valid preamble received counter
	movf 	received_preamble,w 	; check if number of valid preamble received is morethan 10
	sublw	d'10'					; 10-W(received_preamble) count < 10 loop
	btfss	STATUS,C				; skip next if result is negative
	goto	sync_bit				; goto for sync_bit wait
next_preamble_wait					
	decfsz	loopindex,f				; keep looping till try exhaust or we find 10 vaild preamble pulses
	goto 	preamble_wait

	retlw	1 						; if tried enough then return with error in wreg


;wait till sync pulse occur   1500us<pulsetime<1850us
sync_bit					
	btfsc	RF_IN					;wait till rf input pin change it's state 
	goto $-1
	bcf		PIR1,TMR1IF				;clear timer interrupt flag
	clrf 	TMR1L					; clear timer
	clrf 	TMR1H
	bsf		T1CON,TMR1ON			; start timer

	btfss	RF_IN					;wait till rf input pin change it's state 
	goto $-1							
	bcf		T1CON,TMR1ON			;stop timer
	movf	TMR1L,W				
	movwf	temptimerl				; store timer value into temptimer
	movf	TMR1H,W
	movwf	temptimerh

	btfsc	PIR1,TMR1IF				; see if timer rol over
	retlw	1						;error occur go back			


;check if pulsetime<1850us (16bit compare)
	movf	temptimerl,w		
	sublw	count1850l			
	movf	temptimerh,w
	btfss	STATUS,C
	addlw 0x01
	sublw	count1850h			
	btfss	STATUS,C			
	goto   	sync_bit				;will go false to if timer>count

;check if pulsetime>1500us	
	movf	temptimerl,w		
	sublw	count1500l			 
	movf	temptimerh,w
	btfss	STATUS,C
	addlw 0x01
	sublw	count1500h			
	btfsc	STATUS,C			
	goto   	sync_bit 				;will go false to if timer<count

; sync pulse just finished
; wait till startbit finish
	bsf		STATUS_LED				; set status led
	btfsc	RF_IN					;wait till rf input pin goes low  
	goto $-1

;delay some amount of time so that you can land at the middle of first databit
	movlw	DEL624us		
	call 	delay_x5us				;delay for wreg*5us

	movlw	DATAPACKET				;load first datapacket address to wreg
	movwf	FSR						; point the indirect address to DATAPACKET
	movlw	PACKET_LENGTH			; how long the packet is ?
	movwf	loopindex				; we need to loop till then

packetloop
	movlw	0x8						; 8bit byte is
	movwf	bitloopindex			; loop 8 times
	clrf 	INDF					; clear DATAPACKETx through indirect addressing 
	bcf		STATUS,C				; clear the carry flag
bitsloop	
	rlf		INDF,f					; rotate left through carry(which is cleared) DATAPACKETx 
	btfsc	RF_IN					; see what is our RF_IN (databit)
	goto 	wHigh
wLow
	btfss	RF_IN					; wait till low
	goto   	$-1
	goto	wFinish
wHigh								;wait till high make a note into DATAPACKETx also
	bsf		INDF,0					; if RF_IN was high then set the lsb (shifed later)
	btfsc	RF_IN					;wait till RF_IN pin goes low  
	goto 	$-1				

wFinish
	movlw	DEL624us				
	call 	delay_x5us
	decfsz 	bitloopindex,f			;decrement bits loop index
	goto 	bitsloop
	incf	FSR,f					; point to next DATAPACKETx after receiving 8bits

	decfsz 	loopindex,f				; decrement packet loopindex
	goto 	packetloop

	bcf		STATUS_LED				; clear status led


	retlw	0						; return with success
;------------------------------------------------------------------
;  delay_x5us	parameter in wreg , reg>=2
;			
;		Precise delay of (wreg value)*5us ,
; the loop has 10cycle minimum  (2 calling, 1 movwf, 1 decf , 1 nop , 1 nop,2 decfsz,2 return )
; so for 1Mhz ins clock delay is 10us minimum  
; minimum parameter in the wreg register is 2 please look at the loop routine for explanation
; each for every count in wreg 5cyle overhead 
;------------------------------------------------------------------
delay_x5us:  ;at 1Mhz ins clock

	movwf	Delay_Count			; +1 
	decf 	Delay_Count,f		; +1 cycle
	nop							; +1
	nop							; +1
	decfsz 	Delay_Count, F		; +1 or +2
	goto 	$-3					; +2, Go back 3, keep decrementing until 0	

	return						; +2 Return program flow

;``````````````````````````````````````````````````````````````````
	end

