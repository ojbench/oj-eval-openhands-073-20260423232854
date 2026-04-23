// RISCV32I CPU top module
// port modification allowed for debugging purposes

module cpu(
  input  wire                 clk_in,			// system clock signal
  input  wire                 rst_in,			// reset signal
	input  wire					        rdy_in,			// ready signal, pause cpu when low

  input  wire [ 7:0]          mem_din,		// data input bus
  output reg  [ 7:0]          mem_dout,		// data output bus
  output reg  [31:0]          mem_a,			// address bus (only 17:0 is used)
  output reg                  mem_wr,			// write/read signal (1 for write)
	
	input  wire                 io_buffer_full, // 1 if uart buffer is full
	
	output wire [31:0]			dbgreg_dout		// cpu register output (debugging demo)
);

// Specifications:
// - Pause cpu(freeze pc, registers, etc.) when rdy_in is low
// - Memory read result will be returned in the next cycle. Write takes 1 cycle(no need to wait)
// - Memory is of size 128KB, with valid address ranging from 0x0 to 0x20000
// - I/O port is mapped to address higher than 0x30000 (mem_a[17:16]==2'b11)
// - 0x30000 read: read a byte from input
// - 0x30000 write: write a byte to output (write 0x00 is ignored)
// - 0x30004 read: read clocks passed since cpu starts (in dword, 4 bytes)
// - 0x30004 write: indicates program stop (will output '\0' through uart tx)

// Register file
reg [31:0] registers [0:31];

// PC register
reg [31:0] pc;

// Instruction cache
reg [31:0] icache [0:1023];
reg icache_valid [0:1023];

// Pipeline registers
reg [31:0] if_pc, if_inst;
reg [31:0] id_pc, id_inst;
reg [4:0]  id_rs1, id_rs2, id_rd;
reg [31:0] id_imm;
reg [6:0]  id_opcode;
reg [2:0]  id_funct3;
reg [6:0]  id_funct7;
reg [31:0] ex_pc, ex_inst;
reg [31:0] ex_rs1_val, ex_rs2_val;
reg [4:0]  ex_rd;
reg [31:0] ex_imm;
reg [6:0]  ex_opcode;
reg [2:0]  ex_funct3;
reg [6:0]  ex_funct7;
reg [31:0] ex_alu_result;
reg [31:0] mem_pc, mem_inst;
reg [31:0] mem_alu_result;
reg [31:0] mem_rs2_val;
reg [4:0]  mem_rd;
reg [6:0]  mem_opcode;
reg [2:0]  mem_funct3;
reg [31:0] wb_pc, wb_inst;
reg [31:0] wb_data;
reg [4:0]  wb_rd;
reg        wb_we;

// State machine
reg [2:0] state;
localparam FETCH = 3'd0;
localparam DECODE = 3'd1;
localparam EXECUTE = 3'd2;
localparam MEMORY = 3'd3;
localparam WRITEBACK = 3'd4;

// Memory interface state
reg [1:0] mem_state;
reg [31:0] mem_addr_buf;
reg [31:0] mem_data_buf;
reg [1:0] mem_byte_cnt;

// Instruction fetch state
reg [1:0] if_state;
reg [31:0] if_addr;
reg [31:0] if_inst_buf;
reg [1:0] if_byte_cnt;

assign dbgreg_dout = registers[10]; // a0 register for debugging

integer i;

always @(posedge clk_in) begin
  if (rst_in) begin
    // Reset all registers
    pc <= 32'h00000000;
    state <= FETCH;
    mem_wr <= 1'b0;
    mem_a <= 32'h00000000;
    mem_dout <= 8'h00;
    if_state <= 2'd0;
    if_byte_cnt <= 2'd0;
    mem_state <= 2'd0;
    mem_byte_cnt <= 2'd0;
    wb_we <= 1'b0;
    
    // Initialize registers
    for (i = 0; i < 32; i = i + 1) begin
      registers[i] <= 32'h00000000;
    end
    
    // Initialize instruction cache
    for (i = 0; i < 1024; i = i + 1) begin
      icache_valid[i] <= 1'b0;
    end
  end
  else if (!rdy_in) begin
    // Pause CPU when not ready
  end
  else begin
    // Simple state machine for instruction execution
    case (state)
      FETCH: begin
        // Fetch instruction from memory (4 bytes)
        if (if_state == 2'd0) begin
          mem_wr <= 1'b0;
          mem_a <= pc;
          if_addr <= pc;
          if_byte_cnt <= 2'd0;
          if_inst_buf <= 32'h00000000;
          if_state <= 2'd1;
        end
        else if (if_state == 2'd1) begin
          // Read byte 0
          if_inst_buf[7:0] <= mem_din;
          mem_a <= pc + 1;
          if_state <= 2'd2;
        end
        else if (if_state == 2'd2) begin
          // Read byte 1
          if_inst_buf[15:8] <= mem_din;
          mem_a <= pc + 2;
          if_state <= 2'd3;
        end
        else if (if_state == 2'd3) begin
          // Read byte 2
          if_inst_buf[23:16] <= mem_din;
          mem_a <= pc + 3;
          if_state <= 2'd0;
          state <= DECODE;
        end
        else begin
          // Read byte 3
          if_inst_buf[31:24] <= mem_din;
          if_inst <= if_inst_buf;
          if_pc <= if_addr;
        end
      end
      
      DECODE: begin
        // Wait one more cycle for the last byte
        if_inst_buf[31:24] <= mem_din;
        id_inst <= if_inst_buf;
        id_pc <= if_addr;
        id_opcode <= if_inst_buf[6:0];
        id_rd <= if_inst_buf[11:7];
        id_funct3 <= if_inst_buf[14:12];
        id_rs1 <= if_inst_buf[19:15];
        id_rs2 <= if_inst_buf[24:20];
        id_funct7 <= if_inst_buf[31:25];
        
        // Decode immediate based on instruction type
        case (if_inst_buf[6:0])
          7'b0110111, // LUI
          7'b0010111: // AUIPC
            id_imm <= {if_inst_buf[31:12], 12'b0};
          7'b1101111: // JAL
            id_imm <= {{11{if_inst_buf[31]}}, if_inst_buf[31], if_inst_buf[19:12], if_inst_buf[20], if_inst_buf[30:21], 1'b0};
          7'b1100111, // JALR
          7'b0000011, // Load instructions
          7'b0010011: // I-type ALU
            id_imm <= {{20{if_inst_buf[31]}}, if_inst_buf[31:20]};
          7'b0100011: // Store instructions
            id_imm <= {{20{if_inst_buf[31]}}, if_inst_buf[31:25], if_inst_buf[11:7]};
          7'b1100011: // Branch instructions
            id_imm <= {{19{if_inst_buf[31]}}, if_inst_buf[31], if_inst_buf[7], if_inst_buf[30:25], if_inst_buf[11:8], 1'b0};
          default:
            id_imm <= 32'h00000000;
        endcase
        
        state <= EXECUTE;
      end
      
      EXECUTE: begin
        // Read register values
        ex_inst <= id_inst;
        ex_pc <= id_pc;
        ex_opcode <= id_opcode;
        ex_funct3 <= id_funct3;
        ex_funct7 <= id_funct7;
        ex_rd <= id_rd;
        ex_imm <= id_imm;
        ex_rs1_val <= (id_rs1 == 5'b0) ? 32'h00000000 : registers[id_rs1];
        ex_rs2_val <= (id_rs2 == 5'b0) ? 32'h00000000 : registers[id_rs2];
        
        // Execute ALU operation
        case (id_opcode)
          7'b0110111: // LUI
            ex_alu_result <= id_imm;
          7'b0010111: // AUIPC
            ex_alu_result <= id_pc + id_imm;
          7'b1101111: // JAL
            ex_alu_result <= id_pc + 4;
          7'b1100111: // JALR
            ex_alu_result <= id_pc + 4;
          7'b0010011: begin // I-type ALU
            case (id_funct3)
              3'b000: // ADDI
                ex_alu_result <= ((id_rs1 == 5'b0) ? 32'h00000000 : registers[id_rs1]) + id_imm;
              3'b010: // SLTI
                ex_alu_result <= ($signed((id_rs1 == 5'b0) ? 32'h00000000 : registers[id_rs1]) < $signed(id_imm)) ? 32'h00000001 : 32'h00000000;
              3'b011: // SLTIU
                ex_alu_result <= (((id_rs1 == 5'b0) ? 32'h00000000 : registers[id_rs1]) < id_imm) ? 32'h00000001 : 32'h00000000;
              3'b100: // XORI
                ex_alu_result <= ((id_rs1 == 5'b0) ? 32'h00000000 : registers[id_rs1]) ^ id_imm;
              3'b110: // ORI
                ex_alu_result <= ((id_rs1 == 5'b0) ? 32'h00000000 : registers[id_rs1]) | id_imm;
              3'b111: // ANDI
                ex_alu_result <= ((id_rs1 == 5'b0) ? 32'h00000000 : registers[id_rs1]) & id_imm;
              3'b001: // SLLI
                ex_alu_result <= ((id_rs1 == 5'b0) ? 32'h00000000 : registers[id_rs1]) << id_imm[4:0];
              3'b101: begin // SRLI/SRAI
                if (id_funct7[5])
                  ex_alu_result <= $signed((id_rs1 == 5'b0) ? 32'h00000000 : registers[id_rs1]) >>> id_imm[4:0]; // SRAI
                else
                  ex_alu_result <= ((id_rs1 == 5'b0) ? 32'h00000000 : registers[id_rs1]) >> id_imm[4:0]; // SRLI
              end
              default:
                ex_alu_result <= 32'h00000000;
            endcase
          end
          7'b0110011: begin // R-type ALU
            case (id_funct3)
              3'b000: begin // ADD/SUB
                if (id_funct7[5])
                  ex_alu_result <= ((id_rs1 == 5'b0) ? 32'h00000000 : registers[id_rs1]) - ((id_rs2 == 5'b0) ? 32'h00000000 : registers[id_rs2]); // SUB
                else
                  ex_alu_result <= ((id_rs1 == 5'b0) ? 32'h00000000 : registers[id_rs1]) + ((id_rs2 == 5'b0) ? 32'h00000000 : registers[id_rs2]); // ADD
              end
              3'b001: // SLL
                ex_alu_result <= ((id_rs1 == 5'b0) ? 32'h00000000 : registers[id_rs1]) << ((id_rs2 == 5'b0) ? 5'b0 : registers[id_rs2][4:0]);
              3'b010: // SLT
                ex_alu_result <= ($signed((id_rs1 == 5'b0) ? 32'h00000000 : registers[id_rs1]) < $signed((id_rs2 == 5'b0) ? 32'h00000000 : registers[id_rs2])) ? 32'h00000001 : 32'h00000000;
              3'b011: // SLTU
                ex_alu_result <= (((id_rs1 == 5'b0) ? 32'h00000000 : registers[id_rs1]) < ((id_rs2 == 5'b0) ? 32'h00000000 : registers[id_rs2])) ? 32'h00000001 : 32'h00000000;
              3'b100: // XOR
                ex_alu_result <= ((id_rs1 == 5'b0) ? 32'h00000000 : registers[id_rs1]) ^ ((id_rs2 == 5'b0) ? 32'h00000000 : registers[id_rs2]);
              3'b101: begin // SRL/SRA
                if (id_funct7[5])
                  ex_alu_result <= $signed((id_rs1 == 5'b0) ? 32'h00000000 : registers[id_rs1]) >>> ((id_rs2 == 5'b0) ? 5'b0 : registers[id_rs2][4:0]); // SRA
                else
                  ex_alu_result <= ((id_rs1 == 5'b0) ? 32'h00000000 : registers[id_rs1]) >> ((id_rs2 == 5'b0) ? 5'b0 : registers[id_rs2][4:0]); // SRL
              end
              3'b110: // OR
                ex_alu_result <= ((id_rs1 == 5'b0) ? 32'h00000000 : registers[id_rs1]) | ((id_rs2 == 5'b0) ? 32'h00000000 : registers[id_rs2]);
              3'b111: // AND
                ex_alu_result <= ((id_rs1 == 5'b0) ? 32'h00000000 : registers[id_rs1]) & ((id_rs2 == 5'b0) ? 32'h00000000 : registers[id_rs2]);
              default:
                ex_alu_result <= 32'h00000000;
            endcase
          end
          7'b0000011, // Load
          7'b0100011: // Store
            ex_alu_result <= ((id_rs1 == 5'b0) ? 32'h00000000 : registers[id_rs1]) + id_imm;
          7'b1100011: // Branch
            ex_alu_result <= id_pc + id_imm;
          default:
            ex_alu_result <= 32'h00000000;
        endcase
        
        state <= MEMORY;
      end
      
      MEMORY: begin
        mem_inst <= ex_inst;
        mem_pc <= ex_pc;
        mem_alu_result <= ex_alu_result;
        mem_rs2_val <= ex_rs2_val;
        mem_rd <= ex_rd;
        mem_opcode <= ex_opcode;
        mem_funct3 <= ex_funct3;
        
        // Handle memory operations
        case (ex_opcode)
          7'b0000011: begin // Load
            if (mem_state == 2'd0) begin
              mem_wr <= 1'b0;
              mem_a <= ex_alu_result;
              mem_addr_buf <= ex_alu_result;
              mem_data_buf <= 32'h00000000;
              mem_byte_cnt <= 2'd0;
              mem_state <= 2'd1;
            end
            else if (mem_state == 2'd1) begin
              // Read first byte
              mem_data_buf[7:0] <= mem_din;
              if (ex_funct3 == 3'b000 || ex_funct3 == 3'b100) begin // LB/LBU
                mem_state <= 2'd0;
                state <= WRITEBACK;
              end
              else begin
                mem_a <= ex_alu_result + 1;
                mem_state <= 2'd2;
              end
            end
            else if (mem_state == 2'd2) begin
              // Read second byte
              mem_data_buf[15:8] <= mem_din;
              if (ex_funct3 == 3'b001 || ex_funct3 == 3'b101) begin // LH/LHU
                mem_state <= 2'd0;
                state <= WRITEBACK;
              end
              else begin
                mem_a <= ex_alu_result + 2;
                mem_state <= 2'd3;
              end
            end
            else if (mem_state == 2'd3) begin
              // Read third byte
              mem_data_buf[23:16] <= mem_din;
              mem_a <= ex_alu_result + 3;
              mem_state <= 2'd0;
              state <= WRITEBACK;
            end
            else begin
              // Read fourth byte
              mem_data_buf[31:24] <= mem_din;
            end
          end
          7'b0100011: begin // Store
            if (mem_state == 2'd0) begin
              mem_wr <= 1'b1;
              mem_a <= ex_alu_result;
              mem_dout <= ex_rs2_val[7:0];
              mem_state <= 2'd1;
            end
            else if (mem_state == 2'd1) begin
              if (ex_funct3 == 3'b000) begin // SB
                mem_wr <= 1'b0;
                mem_state <= 2'd0;
                state <= WRITEBACK;
              end
              else begin
                mem_a <= ex_alu_result + 1;
                mem_dout <= ex_rs2_val[15:8];
                mem_state <= 2'd2;
              end
            end
            else if (mem_state == 2'd2) begin
              if (ex_funct3 == 3'b001) begin // SH
                mem_wr <= 1'b0;
                mem_state <= 2'd0;
                state <= WRITEBACK;
              end
              else begin
                mem_a <= ex_alu_result + 2;
                mem_dout <= ex_rs2_val[23:16];
                mem_state <= 2'd3;
              end
            end
            else if (mem_state == 2'd3) begin
              mem_a <= ex_alu_result + 3;
              mem_dout <= ex_rs2_val[31:24];
              mem_wr <= 1'b0;
              mem_state <= 2'd0;
              state <= WRITEBACK;
            end
          end
          default: begin
            state <= WRITEBACK;
          end
        endcase
      end
      
      WRITEBACK: begin
        wb_inst <= mem_inst;
        wb_pc <= mem_pc;
        wb_rd <= mem_rd;
        
        // Write back to register
        case (mem_opcode)
          7'b0110111, // LUI
          7'b0010111, // AUIPC
          7'b1101111, // JAL
          7'b1100111, // JALR
          7'b0010011, // I-type ALU
          7'b0110011: begin // R-type ALU
            if (mem_rd != 5'b0) begin
              registers[mem_rd] <= mem_alu_result;
            end
          end
          7'b0000011: begin // Load
            if (mem_rd != 5'b0) begin
              case (mem_funct3)
                3'b000: // LB
                  registers[mem_rd] <= {{24{mem_data_buf[7]}}, mem_data_buf[7:0]};
                3'b001: // LH
                  registers[mem_rd] <= {{16{mem_data_buf[15]}}, mem_data_buf[15:0]};
                3'b010: // LW
                  registers[mem_rd] <= mem_data_buf;
                3'b100: // LBU
                  registers[mem_rd] <= {24'b0, mem_data_buf[7:0]};
                3'b101: // LHU
                  registers[mem_rd] <= {16'b0, mem_data_buf[15:0]};
                default:
                  registers[mem_rd] <= 32'h00000000;
              endcase
            end
          end
        endcase
        
        // Update PC
        case (mem_opcode)
          7'b1101111: // JAL
            pc <= mem_pc + {{11{mem_inst[31]}}, mem_inst[31], mem_inst[19:12], mem_inst[20], mem_inst[30:21], 1'b0};
          7'b1100111: // JALR
            pc <= (registers[mem_inst[19:15]] + {{20{mem_inst[31]}}, mem_inst[31:20]}) & ~32'h00000001;
          7'b1100011: begin // Branch
            case (mem_funct3)
              3'b000: // BEQ
                if (registers[mem_inst[19:15]] == registers[mem_inst[24:20]])
                  pc <= mem_alu_result;
                else
                  pc <= mem_pc + 4;
              3'b001: // BNE
                if (registers[mem_inst[19:15]] != registers[mem_inst[24:20]])
                  pc <= mem_alu_result;
                else
                  pc <= mem_pc + 4;
              3'b100: // BLT
                if ($signed(registers[mem_inst[19:15]]) < $signed(registers[mem_inst[24:20]]))
                  pc <= mem_alu_result;
                else
                  pc <= mem_pc + 4;
              3'b101: // BGE
                if ($signed(registers[mem_inst[19:15]]) >= $signed(registers[mem_inst[24:20]]))
                  pc <= mem_alu_result;
                else
                  pc <= mem_pc + 4;
              3'b110: // BLTU
                if (registers[mem_inst[19:15]] < registers[mem_inst[24:20]])
                  pc <= mem_alu_result;
                else
                  pc <= mem_pc + 4;
              3'b111: // BGEU
                if (registers[mem_inst[19:15]] >= registers[mem_inst[24:20]])
                  pc <= mem_alu_result;
                else
                  pc <= mem_pc + 4;
              default:
                pc <= mem_pc + 4;
            endcase
          end
          default:
            pc <= mem_pc + 4;
        endcase
        
        state <= FETCH;
      end
      
      default: begin
        state <= FETCH;
      end
    endcase
  end
end

endmodule