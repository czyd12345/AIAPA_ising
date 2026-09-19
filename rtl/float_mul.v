//////////////////////////////////////////////////////////////////////////////////
// Module Name : float_mul
// Description : Combinational IEEE-754 binary16 (fp16) multiplier.
//
//               Note: subnormal inputs are not handled - the implicit leading 1
//               is always assumed - and results whose exponent underflows are
//               flushed to zero. No NaN/Inf handling.
//////////////////////////////////////////////////////////////////////////////////
module float_mul
(
	input wire [15:0] floatA,
	input wire [15:0] floatB,
	output reg [15:0] product
);

reg sign;                    // sign of the product
reg signed [5:0] exponent;   // signed because the exponent can be negative
reg [9:0] mantissa;          // product mantissa
reg [10:0] fractionA, fractionB;	// fraction = {1'b1, mantissa} - restore the implicit leading 1
reg [21:0] fraction;         // raw 11x11 product before normalisation


always @ (floatA or floatB) 
begin
	if ((floatA == 0) || (floatB == 0) || (floatA==16'h8000) || (floatB==16'h8000))  // one or both operands are zero
		product = 0;				// result is zero
	else 
	begin
		sign = floatA[15] ^ floatB[15]; // sign of the product
		exponent = floatA[14:10] + floatB[14:10] - 5'd15 + 5'd2; // both fractions carry an implicit 1'b1: subtract the bias twice, add it back once
	
		fractionA = {1'b1,floatA[9:0]}; // restore the implicit leading 1
		fractionB = {1'b1,floatB[9:0]}; // restore the implicit leading 1
		fraction = fractionA * fractionB; // raw binary multiply
		// normalise: shift out the leading 1 and decrement the exponent to match
		if (fraction[21] == 1'b1) 
		begin
			fraction = fraction << 1;
			exponent = exponent - 1; 
		end 
		else if (fraction[20] == 1'b1) 
		begin
			fraction = fraction << 2;
			exponent = exponent - 2;
		end 
		else if (fraction[19] == 1'b1) 
		begin
			fraction = fraction << 3;
			exponent = exponent - 3;
		end 
		else if (fraction[18] == 1'b1) 
		begin
			fraction = fraction << 4;
			exponent = exponent - 4;
		end 
		else if (fraction[17] == 1'b1) 
		begin
			fraction = fraction << 5;
			exponent = exponent - 5;
		end 
		else if (fraction[16] == 1'b1) 
		begin
			fraction = fraction << 6;
			exponent = exponent - 6;
		end 
		else if (fraction[15] == 1'b1) 
		begin
			fraction = fraction << 7;
			exponent = exponent - 7;
		end 
		else if (fraction[14] == 1'b1) 
		begin
			fraction = fraction << 8;
			exponent = exponent - 8;
		end 
		else if (fraction[13] == 1'b1) 
		begin
			fraction = fraction << 9;
			exponent = exponent - 9;
		end 
		else if (fraction[12] == 1'b0) 
		begin
			fraction = fraction << 10;
			exponent = exponent - 10;
		end 
		// assemble the binary16 result
		mantissa = fraction[21:12];
		if(exponent[5]==1'b1) begin // exponent underflow - flush to zero
			product=16'b0000000000000000;
		end
		else begin
			product = {sign,exponent[4:0],mantissa}; // concatenate sign, exponent and mantissa
		end
	end
end
endmodule