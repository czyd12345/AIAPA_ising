

module float_adder (
	input 	wire [15:0] floatA,
	input 	wire [15:0] floatB,
	output	reg	 [15:0] sum
);

reg sign; // sign of the result
reg signed [5:0] exponent; // signed because the exponent can be negative
reg [9:0] mantissa; // result mantissa
reg [4:0] exponentA, exponentB; // operand exponents
reg [10:0] fractionA, fractionB, fraction;	// {1'b1, mantissa}, with a spare bit for alignment
reg [7:0] shiftAmount; 	// shift amount used to align the exponents before adding
reg cout;

always @ (floatA or floatB) 
begin
	exponentA = floatA[14:10];
	exponentB = floatB[14:10];
	fractionA = {1'b1,floatA[9:0]};
	fractionB = {1'b1,floatB[9:0]}; 
	
	exponent = exponentA;

	if ((floatA == 16'h0) || (floatA==16'h8000)) 		// special case: A is zero
	begin						
		sum = floatB;
	end 
	else if ((floatB == 16'h0) || (floatB==16'h8000))  // special case: B is zero
	begin					
		sum = floatA;
	end 
	else if (floatA[14:0] == floatB[14:0] && floatA[15]^floatB[15]==1'b1) // special case: equal magnitudes, opposite signs -> result is zero
	begin
		sum=0;
	end 
	else 
	begin
		if (exponentB > exponentA)  // align the operands so both share the same exponent
		begin
			shiftAmount = exponentB - exponentA;
			fractionA = fractionA >> (shiftAmount);
			exponent = exponentB;
		end 
		else if (exponentA > exponentB) 
		begin 
			shiftAmount = exponentA - exponentB;
			fractionB = fractionB >> (shiftAmount);
			exponent = exponentA;
		end
		if (floatA[15] == floatB[15]) 	// same sign: magnitudes add
		begin							
			{cout,fraction} = fractionA + fractionB;
			if (cout == 1'b1) 
			begin
				{cout,fraction} = {cout,fraction} >> 1;
				exponent = exponent + 1;
			end
			sign = floatA[15];
		end 
		else 
		begin						// opposite signs: magnitudes subtract
			if (floatA[15] == 1'b1) // A is negative
			begin
				{cout,fraction} = fractionB - fractionA;	// B-A
			end 
			else 
			begin
				{cout,fraction} = fractionA - fractionB;	// A-B
			end
			sign = cout;
			if (cout == 1'b1) 
				fraction = -fraction; // 0 - fraction gives the magnitude
			// renormalise the fraction to obtain the mantissa
			if (fraction [10] == 0) begin
				if (fraction[9] == 1'b1) begin
					fraction = fraction << 1;
					exponent = exponent - 1;
				end else if (fraction[8] == 1'b1) begin
					fraction = fraction << 2;
					exponent = exponent - 2;
				end else if (fraction[7] == 1'b1) begin
					fraction = fraction << 3;
					exponent = exponent - 3;
				end else if (fraction[6] == 1'b1) begin
					fraction = fraction << 4;
					exponent = exponent - 4;
				end else if (fraction[5] == 1'b1) begin
					fraction = fraction << 5;
					exponent = exponent - 5;
				end else if (fraction[4] == 1'b1) begin
					fraction = fraction << 6;
					exponent = exponent - 6;
				end else if (fraction[3] == 1'b1) begin
					fraction = fraction << 7;
					exponent = exponent - 7;
				end else if (fraction[2] == 1'b1) begin
					fraction = fraction << 8;
					exponent = exponent - 8;
				end else if (fraction[1] == 1'b1) begin
					fraction = fraction << 9;
					exponent = exponent - 9;
				end else if (fraction[0] == 1'b1) begin
					fraction = fraction << 10;
					exponent = exponent - 10;
				end 
			end
		end
		mantissa = fraction[9:0];
		if(exponent[5]==1'b1) begin // exponent underflow - flush to zero
			sum = 16'b0000000000000000;
		end
		else begin
			sum = {sign,exponent[4:0],mantissa}; // assemble the result
		end		
	end		
end

endmodule