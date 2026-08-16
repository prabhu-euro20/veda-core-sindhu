OUTPUT_ARCH( "riscv" )
ENTRY(_start)
SECTIONS
{
  . = 0x80000000;
  .text : { *(.text) *(.text.*) }
  .data : { *(.data) }
  . = ALIGN(8);
  .tohost : { *(.tohost) }
  . = 0x80070000;
  .signature : { *(.signature) }
  . = ALIGN(0x1000);
  _end = .;
}
