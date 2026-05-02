@ ======================================================================
@ TESTE COMPLETO DO CONJUNTO DE INSTRUÇÕES ARM7TDMI (SINTAXE GNU AS)
@ ======================================================================

        .section .text          @ Define a área de código (equivalente ao AREA CODE)
        .global _start          @ Ponto de entrada do programa (equivalente ao ENTRY)

_start:
        @ ==============================================================
        @ 1. PREPARAÇÃO (SETUP INICIAL)
        @ ==============================================================
        MOV     R0, #10             @ Carrega R0 com 10 (0x0A)
        MOV     R1, #3              @ Carrega R1 com 3 (0x03)
        LDR     R12, =DataArea      @ Aponta R12 para nossa área de dados na memória
        
        LDR     R13, =StackArea     @ Inicializa o Stack Pointer (R13)
        ADD     R13, R13, #128      @ Ajusta o SP para o final do bloco (pilha cresce para baixo)

        @ ==============================================================
        @ 2. INSTRUÇÕES DE PROCESSAMENTO DE DADOS (ARITMÉTICA E LÓGICA)
        @ ==============================================================
        ADD     R2, R0, R1          @ R2 = R0 + R1 (10 + 3 = 13)
        SUB     R2, R0, R1          @ R2 = R0 - R1 (10 - 3 = 7)
        RSB     R2, R0, #20         @ R2 = 20 - R0 (20 - 10 = 10) (Reverse Subtract)
        
        @ Operações com Carry (Vai-um/Empréstimo)
        ADDS    R2, R0, R1          @ Soma e atualiza as flags de status (CPSR)
        ADC     R3, R0, R1          @ R3 = R0 + R1 + Carry
        SUBS    R2, R0, R1          @ Subtrai e atualiza flags (gera borrow se necessário)
        SBC     R3, R0, R1          @ R3 = R0 - R1 - NOT Carry
        RSC     R3, R0, R1          @ R3 = R1 - R0 - NOT Carry

        @ Operações Lógicas Bit-a-Bit
        AND     R4, R0, #0xFF       @ Mascara R0 com 0xFF (Mantém R4 = 10)
        ORR     R4, R0, R1          @ R4 = R0 OR R1
        EOR     R4, R0, R1          @ R4 = R0 XOR R1 (Ou Exclusivo)
        BIC     R4, R0, #2          @ R4 = R0 AND NOT 2 (Bit Clear - zera o bit 1)
        MVN     R5, R0              @ R5 = NOT R0 (Move Negativo / Inverte os bits)

        @ Comparações e Testes (Não guardam resultado, apenas atualizam flags)
        CMP     R0, R1              @ Compara R0 com R1 (R0 - R1)
        CMN     R0, R1              @ Compara Negativo (R0 + R1)
        TST     R0, #1              @ Testa bit (R0 AND 1) para verificar se é ímpar
        TEQ     R0, R1              @ Testa Equivalência (R0 XOR R1)

        @ ==============================================================
        @ 3. INSTRUÇÕES DE MULTIPLICAÇÃO
        @ ==============================================================
        MUL     R6, R0, R1          @ R6 = R0 * R1 (32-bit result)
        MLA     R6, R0, R1, R2      @ R6 = (R0 * R1) + R2 (Multiply-Accumulate)
        UMULL   R6, R7, R0, R1      @ Unsigned Long Mul: R7:R6 = R0 * R1 (64-bit)
        UMLAL   R6, R7, R0, R1      @ Unsigned Long Mul-Acc: R7:R6 += R0 * R1
        SMULL   R6, R7, R0, R1      @ Signed Long Mul: R7:R6 = R0 * R1 (64-bit)
        SMLAL   R6, R7, R0, R1      @ Signed Long Mul-Acc: R7:R6 += R0 * R1

        @ ==============================================================
        @ 4. PSEUDO-INSTRUÇÕES DE DESLOCAMENTO (SHIFTS)
        @ ==============================================================
        LSL     R8, R0, #1          @ Logical Shift Left: Multiplica R0 por 2
        LSR     R8, R0, #1          @ Logical Shift Right: Divide R0 por 2
        ASR     R8, R5, #1          @ Arithmetic Shift Right: Divide preservando sinal
        ROR     R8, R0, #4          @ Rotate Right: Rotaciona bits 4 posições à direita
        RRX     R8, R0              @ Rotate Right c/ Extend: Rotaciona através do Carry

        @ ==============================================================
        @ 5. TRANSFERÊNCIA DE DADOS (MEMÓRIA) - LOAD / STORE
        @ ==============================================================
        STR     R0, [R12]           @ Armazena a palavra (32 bits) de R0 em [R12]
        LDR     R9, [R12]           @ Carrega a palavra de [R12] para R9
        
        STRB    R0, [R12, #4]       @ Armazena 1 Byte (8 bits) de R0 no endereço R12+4
        LDRB    R9, [R12, #4]       @ Carrega 1 Byte (Zero-extended)
        LDRSB   R9, [R12, #4]       @ Carrega 1 Byte (Sign-extended)
        
        STRH    R0, [R12, #8]       @ Armazena Halfword (16 bits) no endereço R12+8
        LDRH    R9, [R12, #8]       @ Carrega Halfword (Zero-extended)
        LDRSH   R9, [R12, #8]       @ Carrega Halfword (Sign-extended)

        SWP     R10, R3, [R12]      @ Troca a palavra de R0 com a memória apontada por R12
        SWPB    R10, R2, [R12]      @ Troca o byte de R0 com a memória apontada por R12

        @ ==============================================================
        @ 6. MÚLTIPLOS REGISTRADORES E PILHA (STACK)
        @ ==============================================================
        STMIA   R12!, {R0-R2}       @ Store Multiple Increment After: Grava R0, R1, R2
        LDMDB   R12!, {R3-R5}       @ Load Multiple Decrement Before: Lê de volta

        PUSH    {R0, R1, LR}        @ Salva R0, R1 e Link Register na Pilha (R13)
        POP     {R0, R1, R10}       @ Recupera R0, R1 e coloca o LR em R10

        @ ==============================================================
        @ 7. ACESSO AO REGISTRADOR DE STATUS (CPSR/SPSR)
        @ ==============================================================
        MRS     R11, CPSR           @ Lê o Current Program Status Register para R11
        MSR     CPSR_f, R11         @ Escreve R11 de volta nas flags do CPSR

        @ ==============================================================
        @ 8. CONTROLE DE FLUXO E SALTOS
        @ ==============================================================
        NOP                         @ Pseudo-instrução: Não faz nada (gasta 1 ciclo)
        BL      Subroutine          @ Branch and Link: Chama a rotina

FimProg:
        SWI     0x11                @ Software Interrupt

        @ ==============================================================
        @ SUB-ROTINA
        @ ==============================================================
Subroutine:
        MOV     R0, #0xFF           @ Ação da rotina
        BX      LR                  @ Branch and eXchange: Retorna da rotina

        @ ==============================================================
        @ ÁREA DE DADOS EM MEMÓRIA RAM
        @ ==============================================================
        .section .data              @ Define seção de dados que podem ser lidos/escritos
        .align 2                    @ Garante alinhamento de 4 bytes (2^2)
DataArea:
        .space  64                  @ Aloca 64 bytes com zeros
        
        .align 2
StackArea:
        .space  128                 @ Aloca 128 bytes para usarmos como Pilha

        .end                        @ Diretiva opcional de fim de arquivo