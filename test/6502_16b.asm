	.PROCESSOR	6502
	.TRACE	on

RAM_START	.equ   $80
my_addr		.equ    (RAM_START + 192)

	.ORG 0

	and.b	my_addr	; forced byte addressing and too large value should trigger



