function y = round_dec(x, digits)
%ROUND_DEC Decimal round-half-even (Python round()) via formatting.
%   MATLAB's round() is round-half-AWAY-from-zero -- NOT parity-safe for the
%   PPR score lock. sprintf uses the C library's correctly-rounded decimal
%   conversion (ties-to-even), identical to Python round / Rust format.
y = str2double(sprintf('%.*f', digits, x));
end
